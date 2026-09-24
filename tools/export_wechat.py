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
    return source.replace(legacy, warning + ';')


def patch_wechat_loader(source):
    # Image/subpackage callbacks and queued animation frames can outlive cleanup.
    # They must not draw with deleted GL resources or resize Godot's live canvas.
    replacements = {
        '        render() {': '        render() {\n            if (this.disposed) return;',
        '        resizeCanvases() {': '        resizeCanvases() {\n            if (this.disposed) return;',
        '        cleanup() {': '        cleanup() {\n            if (this.disposed) return;\n            this.disposed = true;',
    }
    for before, after in replacements.items():
        if source.count(before) != 1:
            raise ValueError('微信加载器生命周期补丁与模板不匹配，请重新检查模板。')
        source = source.replace(before, after)
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--appid', default='wxd575463c13869e7d')
    parser.add_argument('--godot', default=shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot')
    parser.add_argument('--template', type=Path)
    parser.add_argument('--project', type=Path, default=ROOT)
    parser.add_argument('--preset', default='WeChat Resources')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/wechat')
    parser.add_argument('--diagnostics', action='store_true', help='启动后显示真机渲染诊断；仅用于排查预览包')
    args = parser.parse_args()
    if len(args.appid) != 18 or not args.appid.startswith('wx'):
        parser.error('AppID 必须为 wx 开头的 18 位字符串。')
    engine_version = subprocess.check_output([args.godot, '--version'], text=True).strip()
    if not engine_version.startswith('4.7.'):
        parser.error(f'当前固定模板只验证 Godot 4.7 系列，实际为 {engine_version}')
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
        loader = stage / 'godot-loader.js'
        loader.write_text(patch_wechat_loader(loader.read_text()))
        build_id = datetime.now().strftime('%Y%m%d-%H%M%S')
        (stage / 'boot-options.js').write_text('module.exports = ' + json.dumps({
            'diagnostics': args.diagnostics, 'build': build_id,
        }) + ';\n')
        config.update(appid=args.appid, projectname='烧烤串串消', description='烧烤串串消 · Godot 微信小游戏', isGameTourist=False)
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
        shutil.copy2(ROOT / 'platform/wechat/THIRD_PARTY_NOTICES.txt', stage / 'THIRD_PARTY_NOTICES.txt')
        shutil.copy2(ROOT / 'platform/wechat/engine-entry.js', stage / 'engine/game.js')
        log = output.parent / 'wechat-export.log'
        subprocess.run([args.godot, '--headless', '--path', str(args.project.resolve()),
                        '--export-pack', args.preset, str(stage / 'engine/bbq.pck'),
                        '--log-file', str(log)], check=True)
        pack = stage / 'engine/bbq.pck'
        if not pack.exists() or pack.stat().st_size < 100:
            raise SystemExit(f'Godot 未生成资源包，请检查 {log}')
        # WeChat's package file filter accepts .bin, but does not ship .pck.
        pack.rename(stage / 'engine/bbq.bin')
        sizes = {str(p.relative_to(stage)): p.stat().st_size for p in sorted(stage.rglob('*')) if p.is_file() and not p.name.startswith('.')}
        total = sum(sizes.values())
        write_json(stage / 'export-info.json', {
            'appid': args.appid, 'godot': engine_version,
            'template': URL, 'template_sha256': SHA256,
            'runtime_patches': ['sdk-preserve-device-pixel-ratio', 'loader-stop-after-cleanup'],
            'diagnostics': args.diagnostics, 'build': build_id,
            'total_bytes': total, 'files': sizes,
        })
        # Only replace our generated directory; never clean an arbitrary output.
        if output.exists():
            if not (output / 'export-info.json').exists():
                raise SystemExit(f'输出目录不是本脚本生成的目录，已保留：{output}')
            shutil.rmtree(output)
        shutil.copytree(stage, output)
    zip_path = Path(shutil.make_archive(str(output), 'zip', output))
    print(f'微信工程：{output}\n压缩包：{zip_path}\n包体：{total / 1024 / 1024:.2f} MiB')


if __name__ == '__main__':
    main()
