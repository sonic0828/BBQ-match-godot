#!/usr/bin/env python3
"""Assemble the pinned godothub WeChat runtime with a Godot resource export."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
VERSION = '4.7.0.8'
SHA256 = '6e9938ec4f8de0cd9b693a1d851a6b361a7397d6f3ee6a6de4909b053bac8a23'
URL = f'https://github.com/godothub/godot-minigame/releases/download/4.7/minigame{VERSION}.tpz'
RUNTIME_FILES = (
    'weapp-adapter.js', 'glx-config.js', 'godot-loader.js',
    'engine/godot-sdk.js', 'engine/godot.js', 'engine/godot.wasm.br',
    'images/background.jpg', 'images/logo.png',
)


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def patch_wechat_sdk(source):
    # The pinned loader owns DPR and may expose a getter-only property. The
    # legacy SDK forces DPR=1 on iOS, which throws in WeChat's strict modules.
    warning = ('B&&D&&j&&z&&!_&&console.error("此AppID未开通高性能模式\\n'
               '请前往mp后台-能力地图-开发提效包-高性能模式开通\\n可大幅提升游戏运行性能")')
    legacy = (f'if({warning},D)window.devicePixelRatio=1;else if(T)try{{'
              'window.devicePixelRatio<2&&(window.devicePixelRatio=2)'
              '}catch(e){console.warn(e)}')
    if source.count(legacy) != 1:
        raise ValueError('微信 SDK 像素比例补丁与模板不匹配，请重新检查模板。')
    source = source.replace(legacy, warning + ';')
    read = 'r.readFile({filePath:e,complete:e=>{t(e.data)}})'
    if source.count(read) != 1:
        raise ValueError('微信 SDK 文件读取补丁与模板不匹配。')
    return source.replace(read, 'r.readFile({filePath:e,success:e=>t(e.data),fail:s})')


def patch_wechat_engine(source):
    # Guard the injection point; the entire template is also pinned by SHA-256.
    if source.count('var GodotFS=') != 1 or source.count('rename:function(old_node,new_dir,new_name)') != 1:
        raise ValueError('微信文件系统补丁与固定模板不匹配。')
    source = source.replace('var GodotFS=',
                            (ROOT / 'platform/wechat/filesystem-patch.js').read_text() + '\nvar GodotFS=')
    replacements = {
        'Module["instantiateWasm"](info,(mod,inst)=>{resolve(receiveInstance(mod,inst))})':
            'Module["instantiateWasm"](info,(mod,inst)=>{resolve(receiveInstance(mod,inst))},reject)',
        "'instantiateWasm': function (imports, onSuccess) {": """'instantiateWasm': function (imports, onSuccess, onFailure) {
                const boot = GameGlobal.bbqBoot;
                if (boot) boot.mark('wasm-instantiate:start');""",
        "\t\t\t\t\tonSuccess(result['instance'], result['module']);": """                    if (boot) boot.mark('wasm-instantiate:ready');
                    onSuccess(result['instance'], result['module']);""",
        'WebAssembly.instantiateStreaming(Promise.resolve(r), imports).then(done);':
            'WebAssembly.instantiateStreaming(Promise.resolve(r), imports).then(done, onFailure);',
        'WebAssembly.instantiate(loadPath + ".wasm.br", imports).then(done);':
            'WebAssembly.instantiate(loadPath + ".wasm.br", imports).then(done, onFailure);',
        '\t\t\tloadPromise = preloader.loadPromise(`${loadPath}.wasm.br`, size, true);': """            const probe = GameGlobal.bbqRenderProbe || {};
            const nativePath = typeof WXWebAssembly !== 'undefined' && WebAssembly === WXWebAssembly
                && typeof WebAssembly.instantiateStreaming === 'undefined';
            const skipRead = probe.skipWasmRead && nativePath;
            const boot = GameGlobal.bbqBoot;
            if (boot) boot.mark('wasm-read:start', { skipped: !!skipRead });
            loadPromise = (skipRead ? Promise.resolve({})
                : preloader.loadPromise(`${loadPath}.wasm.br`, size, true)).then(value => {
                if (boot) boot.mark('wasm-read:ready', { skipped: !!skipRead });
                return value;
            });""",
    }
    for before, after in replacements.items():
        if source.count(before) != 1:
            raise ValueError('微信引擎启动补丁与固定模板不匹配。')
        source = source.replace(before, after)
    start = source.index('\t\t\t\tfunction doInit(promise) {')
    end = source.index('\t\t\t\tpreloader.setProgressFunc', start)
    source = source[:start] + """                function doInit(promise) {
                    return promise.then(response => Godot(me.config.getModuleConfig(loadPath, response.data)))
                        .then(module => module['initFS'](me.config.persistentPaths).then(error => {
                            if (error) throw error;
                            me.rtenv = module;
                            if (me.config.unloadAfterInit) Engine.unload();
                        }));
                }
""" + source[end:]
    return source


def patch_wechat_loader(source):
    # Image/subpackage callbacks and queued animation frames can outlive cleanup.
    # They must not draw with deleted GL resources or resize Godot's live canvas.
    replacements = {
        '    class GodotLoader {': '''    function reportLoaderEvent(loader, event) {
        const boot = gameGlobal.bbqBoot;
        if (boot) boot.loaderEvent(loader, event);
    }

    class GodotLoader {''',
        'this.offScreenCanvas = document.createElement("canvas");':
            'this.offScreenCanvas = config.skipRendering ? null : document.createElement("canvas");',
        'this.currentText = config.textConfig.firstStartText;':
            '''this.currentText = config.textConfig.firstStartText;
            this.progress = null;
            this.downloadComplete = false;
            this.preparing = false;
            this.images = [];
            this.renderTask = null;
            reportLoaderEvent(this, "created");''',
        '            this.initWebGL();': '            if (!config.skipRendering) this.initWebGL();',
        '            this.loadImages();': '            if (!config.skipRendering) this.loadImages();',
        '            this.offScreenCanvas.width = width * this.dpr;\n            this.offScreenCanvas.height = height * this.dpr;':
            '''            if (this.offScreenCanvas) {
                this.renderDpr = this.config.lightRendering ? 1 : this.dpr;
                this.offScreenCanvas.width = Math.round(width * this.renderDpr);
                this.offScreenCanvas.height = Math.round(height * this.renderDpr);
            }''',
        '        render() {': '''        render() {
            reportLoaderEvent(this, "render");
            if (this.disposed || this.config.skipRendering) return;''',
        '        renderToWebGL() {': '''        renderToWebGL() {
            if (this.disposed || this.config.skipRendering) return;''',
        '            this.gl.drawArrays(this.gl.TRIANGLE_STRIP, 0, 4);':
            '            this.gl.drawArrays(this.gl.TRIANGLE_STRIP, 0, 4);\n            reportLoaderEvent(this, "draw");',
        '        resizeCanvases() {': '        resizeCanvases() {\n            if (this.disposed) return;',
        '        cleanup() {': '''        cleanup() {
            if (this.disposed) return;
            this.disposed = true;
            reportLoaderEvent(this, "cleanup");''',
        '            this.program = this.createProgram(vertexShader, fragmentShader);': '''            this.program = this.createProgram(vertexShader, fragmentShader);
            this.gl.deleteShader(vertexShader);
            this.gl.deleteShader(fragmentShader);''',
        '            const image = new Image();': '''            const image = new Image();
            this.images.push(image);''',
        '            image.onload = () => {': '            image.onload = () => {\n                if (this.disposed) return;',
        '            image.onerror = (event) => {': '            image.onerror = (event) => {\n                if (this.disposed) return;',
        '            this.loadImage(materialConfig.iconImage, "icon", (image) => {':
            '            if (this.config.iconConfig.visible) this.loadImage(materialConfig.iconImage, "icon", (image) => {',
        '''            const barY =
                height -
                iconConfig.bottom * this.dpr -
                iconConfig.height * this.dpr -
                30 * this.dpr -
                barConfig.height * this.dpr;''': '''            const info = this.getWindowInfo() || {};
            const safe = info.safeArea || {};
            const top = Math.max(0, Number(safe.top) || 0) * this.dpr;
            const bottom = Math.min(height, (Number(safe.bottom) || height / this.dpr) * this.dpr);
            const barY = top + (bottom - top) * 0.78;''',
        '            ctx.fillStyle = barConfig.backgroundColor;':
            '            if (this.progress !== null) {\n            ctx.fillStyle = barConfig.backgroundColor;',
        '            const textConfig = this.config.textConfig;':
            '            }\n            const textConfig = this.config.textConfig;',
        '            ctx.fillText(this.currentText, width / 2, barY + (barConfig.height * this.dpr) / 2);': '''            const caption = this.currentText + (this.progress === null ? " …" : ` · 下载 ${Math.round(this.progress * 100)}%`);
            ctx.fillText(caption, width / 2, barY - 20 * this.dpr);''',
        'value > 1 ? value / 100 : value': 'value',
        '''            const normalized = this.normalizeProgress(progress);
            this.progress = Math.max(this.progress || 0, normalized);''': '''            if (this.disposed || this.preparing) return;
            const normalized = this.normalizeProgress(progress);
            this.progress = Math.max(this.progress || 0, normalized);''',
        '''
            if (typeof windowObject.requestAnimationFrame === "function") {
                windowObject.requestAnimationFrame(() => this.render());
            }''': '',
        '''            const task = wxApi.loadSubpackage({''': '''            if (gameGlobal.bbqBoot) gameGlobal.bbqBoot.mark("subpackage:start");
            const task = wxApi.loadSubpackage({''',
        '''                    this.progress = 1;
                    this.updateProgress(this.progress, this.config.textConfig.initText);''': '''                    this.downloadComplete = true;
                    if (gameGlobal.bbqBoot) gameGlobal.bbqBoot.mark("subpackage:ready");
                    // The package entry may already have started the engine.
                    if (!this.preparing) this.setStage(this.config.textConfig.compilingText);''',
        '''                },
            });

            if (task && typeof task.onProgressUpdate''': '''                },
                fail: error => { if (gameGlobal.bbqBoot) gameGlobal.bbqBoot.fail(error); },
            });

            if (task && typeof task.onProgressUpdate''',
        '''                    this.updateProgress(progress, this.config.textConfig.downloadingText[0]);''': '''                    if (!this.downloadComplete) {
                        if (gameGlobal.bbqBoot) gameGlobal.bbqBoot.downloadProgress(event);
                        const written = Number(event.totalBytesWritten);
                        const expected = Number(event.totalBytesExpectedToWrite);
                        const fraction = Number.isFinite(written) && written >= 0 && Number.isFinite(expected) && expected > 0
                            ? written / expected : progress / 100;
                        this.updateProgress(fraction, this.config.textConfig.downloadingText[0]);
                        if (fraction >= 1) {
                            this.downloadComplete = true;
                            if (gameGlobal.bbqBoot) gameGlobal.bbqBoot.mark("subpackage:downloaded");
                            this.setStage(this.config.textConfig.compilingText);
                        }
                    }''',
        '                task.onProgressUpdate(({ progress }) => {':
            '                task.onProgressUpdate(event => {\n                    const { progress } = event;',
        '''            windowObject.removeEventListener("resize", this.resizeHandler);

            if (!this.gl)''': '''            windowObject.removeEventListener("resize", this.resizeHandler);
            if (this.renderTask !== null) {
                if (this.config.lightRendering || !windowObject.cancelAnimationFrame) clearTimeout(this.renderTask);
                else windowObject.cancelAnimationFrame(this.renderTask);
                this.renderTask = null;
            }
            for (const image of this.images) { image.onload = null; image.onerror = null; }
            this.images.length = 0;
            this.backgroundImage = this.iconImage = null;
            if (this.offScreenCanvas) {
                this.offScreenCanvas.width = this.offScreenCanvas.height = 1;
                this.offScreenCanvas = null;
            }

            if (!this.gl)''',
        '''            this.gl.clearColor(0, 0, 0, 0);
            this.gl.clear(this.gl.COLOR_BUFFER_BIT);''': '''            // Preserve the last loading frame until Godot presents its own frame.
            // Never draw/resize this shared canvas after handing it to the engine.
            this.program = this.positionBuffer = this.texCoordBuffer = this.texture = null;''',
    }
    for before, after in replacements.items():
        if source.count(before) != 1:
            raise ValueError('微信加载器生命周期补丁与模板不匹配，请重新检查模板。')
        source = source.replace(before, after)
    # Rendering uses its own backing resolution; never lower Godot's canvas DPR here.
    begin, end = source.index('        render() {'), source.index('        renderToWebGL() {')
    source = source[:begin] + source[begin:end].replace('this.dpr', 'this.renderDpr') + source[end:]
    source = source.replace('this.render();', 'this.requestRender();')
    source = source.replace('            this.requestRender();\n            this.loadGameEngine();',
                            '            this.render();\n            this.loadGameEngine();')
    source = source.replace('        render() {', '''        handoff(text) {
            if (this.disposed) return;
            this.setStage(text);
            // Commit the final loading message before releasing this GL owner.
            // cleanup cancels the queued duplicate and all late callbacks.
            try { this.render(); } finally { this.cleanup(); }
        }

        setStage(text) {
            if (this.disposed) return;
            this.preparing = true;
            this.progress = null;
            this.currentText = text;
            this.requestRender();
        }

        requestRender() {
            if (this.disposed || this.config.skipRendering || this.renderTask !== null) return;
            const callback = () => {
                this.renderTask = null;
                this.render();
            };
            if (!this.config.lightRendering && windowObject.requestAnimationFrame && windowObject.cancelAnimationFrame) {
                this.renderTask = windowObject.requestAnimationFrame(callback);
            } else {
                this.renderTask = setTimeout(callback, this.config.lightRendering ? 100 : 16);
            }
        }

        render() {''')
    return source


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--appid', default='wxd575463c13869e7d')
    parser.add_argument('--godot', default=shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot')
    parser.add_argument('--template', type=Path)
    parser.add_argument('--project', type=Path, default=ROOT)
    parser.add_argument('--preset', default='WeChat Resources')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/wechat')
    parser.add_argument('--zip', action='store_true', help='额外生成 ZIP 压缩包；仅在明确需要时使用')
    parser.add_argument('--diagnostics', action='store_true', help='采集启动阶段与首帧后 120 秒诊断；仅用于排查预览包')
    parser.add_argument('--ios-startup-profile', choices=('baseline', 'loader', 'wasm', 'combined'),
                        default='loader', help='iOS 默认轻量 Loading；其余策略仅用于对照')
    parser.add_argument('--startup-minimal', action='store_true', help='导出同引擎最小场景，仅用于测量启动下限')
    parser.add_argument('--android-render-probe', choices=('A', 'B', 'C', 'D'),
                        default='D', help='安卓默认 D（跳过自绘 Loading＋WebGL2）；A/B/C 仅用于对照')
    parser.add_argument('--android-native-loading', action=argparse.BooleanOptionalAction, default=True,
                        help='安卓默认使用微信原生等待提示；可加 --no-android-native-loading 关闭')
    args = parser.parse_args(argv)
    if len(args.appid) != 18 or not args.appid.startswith('wx'):
        parser.error('AppID 必须为 wx 开头的 18 位字符串。')
    return args


def main():
    args = parse_args()
    engine_version = subprocess.check_output([args.godot, '--version'], text=True).strip()
    if not engine_version.startswith('4.7.'):
        raise SystemExit(f'当前固定模板只验证 Godot 4.7 系列，实际为 {engine_version}')
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    (build / '.gdignore').touch()
    template = args.template or build / 'cache' / f'minigame{VERSION}.tpz'
    if not template.exists():
        template.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['curl', '--fail', '--silent', '--show-error', '-L', URL, '-o', str(template)], check=True)
    digest = hashlib.sha256(template.read_bytes()).hexdigest()
    if digest != SHA256:
        raise SystemExit(f'模板 SHA-256 校验失败：{digest}')
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.wechat-export-', dir=output.parent) as temp:
        stage = Path(temp)
        (stage / '.gdignore').touch()
        with zipfile.ZipFile(template) as archive:
            for name in RUNTIME_FILES:
                destination = stage / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(archive.read(name))
            config = json.loads(archive.read('project.config.json'))
        sdk = stage / 'engine/godot-sdk.js'
        sdk.write_text(patch_wechat_sdk(sdk.read_text()))
        engine_script = stage / 'engine/godot.js'
        engine_script.write_text(patch_wechat_engine(engine_script.read_text()))
        loader = stage / 'godot-loader.js'
        loader.write_text(patch_wechat_loader(loader.read_text()))
        build_id = datetime.now().strftime('%Y%m%d-%H%M%S')
        config.update(appid=args.appid, projectname='烧烤消消消', description='烧烤消消消 · Godot 微信小游戏', isGameTourist=False)
        config['setting']['urlCheck'] = True
        # The engine is already generated/minified. Keep its dynamic binary
        # resources, and avoid running SWC/minification over the Emscripten glue.
        config['setting'].update(minified=False, swc=False, disableSWC=True,
                                 ignoreUploadUnusedFiles=False)
        config['packOptions'] = {'ignore': [{'type': 'file', 'value': 'export-info.json'}], 'include': []}
        write_json(stage / 'project.config.json', config)
        write_json(stage / 'game.json', {
            'deviceOrientation': 'portrait',
            'iOSHighPerformance': True,
            'iOSHighPerformance+': True,
            'subpackages': [{'name': 'engine', 'root': 'engine/'}],
        })
        shutil.copy2(ROOT / 'platform/wechat/game.js', stage / 'game.js')
        shutil.copy2(ROOT / 'platform/wechat/boot-diagnostics.js', stage / 'boot-diagnostics.js')
        shutil.copy2(ROOT / 'platform/wechat/render-probe.js', stage / 'render-probe.js')
        shutil.copy2(ROOT / 'platform/wechat/haptics.js', stage / 'haptics.js')
        shutil.copy2(ROOT / 'platform/wechat/game-club.js', stage / 'game-club.js')
        shutil.copy2(ROOT / 'platform/wechat/ads.js', stage / 'ads.js')
        shutil.copy2(ROOT / 'platform/wechat/THIRD_PARTY_NOTICES.txt', stage / 'THIRD_PARTY_NOTICES.txt')
        shutil.copy2(ROOT / 'platform/wechat/engine-entry.js', stage / 'engine/game.js')
        log = output.parent / 'wechat-export.log'
        project = ROOT / 'tests/fixtures/wechat_startup' if args.startup_minimal else args.project.resolve()
        subprocess.run([args.godot, '--headless', '--path', str(project),
                        '--export-pack', args.preset, str(stage / 'engine/bbq.pck'),
                        '--log-file', str(log)], check=True)
        pack = stage / 'engine/bbq.pck'
        if not pack.exists() or pack.stat().st_size < 100:
            raise SystemExit(f'Godot 未生成资源包，请检查 {log}')
        # WeChat's package file filter accepts .bin, but does not ship .pck.
        pack = pack.rename(stage / 'engine/bbq.bin')
        (stage / 'boot-options.js').write_text('module.exports = ' + json.dumps({
            'diagnostics': args.diagnostics, 'build': build_id,
            'androidRenderProbe': args.android_render_probe,
            'androidNativeLoading': args.android_native_loading,
            'iosStartupProfile': args.ios_startup_profile, 'minimal': args.startup_minimal,
            'pack': {'bytes': pack.stat().st_size, 'crc32': f'{zlib.crc32(pack.read_bytes()):08x}'},
        }) + ';\n')
        sizes = {str(p.relative_to(stage)): p.stat().st_size for p in sorted(stage.rglob('*')) if p.is_file() and not p.name.startswith('.')}
        total = sum(sizes.values())
        write_json(stage / 'export-info.json', {
            'appid': args.appid, 'godot': engine_version,
            'template': URL, 'template_sha256': SHA256,
            'runtime_patches': ['sdk-preserve-device-pixel-ratio', 'loader-stop-after-cleanup',
                                'loader-render-probe', 'loader-progress-and-release',
                                'sdk-file-read-errors', 'engine-startup-probes', 'wxmemfs-durable-rename'],
            'diagnostics': args.diagnostics, 'build': build_id,
            'android_render_probe': args.android_render_probe,
            'android_native_loading': args.android_native_loading,
            'ios_startup_profile': args.ios_startup_profile, 'startup_minimal': args.startup_minimal,
            'total_bytes': total, 'files': sizes,
        })
        # Only replace our generated directory; never clean an arbitrary output.
        if output.exists():
            if not (output / 'export-info.json').exists():
                raise SystemExit(f'输出目录不是本脚本生成的目录，已保留：{output}')
            shutil.rmtree(output)
        shutil.copytree(stage, output)
    print(f'微信工程：{output}\n包体：{total / 1024 / 1024:.2f} MiB')
    if args.zip:
        zip_path = Path(shutil.make_archive(str(output), 'zip', output))
        print(f'压缩包：{zip_path}')


if __name__ == '__main__':
    main()
