const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');
const configureRenderProbe = require('../platform/wechat/render-probe');

const { original, patched } = JSON.parse(execFileSync('python3', ['-B', '-c', `
import hashlib, json, zipfile
from tools.export_wechat import ROOT, VERSION, SHA256, patch_wechat_loader
template = ROOT / 'build/cache' / f'minigame{VERSION}.tpz'
assert hashlib.sha256(template.read_bytes()).hexdigest() == SHA256
with zipfile.ZipFile(template) as archive:
    original = archive.read('godot-loader.js').decode()
print(json.dumps(dict(original=original, patched=patch_wechat_loader(original))))
`], { cwd: path.resolve(__dirname, '..'), encoding: 'utf8' }));

function fixture(source, { probe = 'A', platform = 'android', supportGLX = true, iosProfile, initialProgress = 1 } = {}) {
    const frames = [];
    const images = [];
    const captions = [];
    const marks = [];
    const tasks = new Map();
    let sequence = 0;
    let progressCallback, packageSuccess, packageFail;
    const schedule = callback => { const id = ++sequence; tasks.set(id, callback); frames.push(callback); return id; };
    const cancel = id => tasks.delete(id);
    const flush = () => { const pending = [...tasks.values()]; tasks.clear(); pending.forEach(fn => fn()); };
    let clears = 0;
    let draws = 0;
    let deletions = 0;
    let auxiliaryCanvases = 0;
    let subpackages = 0;
    const contexts = [];
    const events = [];
    const screen = { width: 390, height: 844, style: {} };
    const context2d = new Proxy({}, { get: (_target, key) => key === 'fillText' ? (...args) => captions.push(args) : () => {} });
    const gl = new Proxy({ canvas: screen }, { get(target, key) {
        if (key in target) return target[key];
        if (key === 'clear') return () => clears++;
        if (key === 'drawArrays') return () => draws++;
        if (String(key).startsWith('delete')) return () => deletions++;
        if (String(key).startsWith('get')) return () => true;
        if (String(key).startsWith('create')) return () => ({});
        return () => {};
    } });
    const globals = {
        GameGlobal: { bbqBoot: { mark: name => marks.push(name), fail: error => marks.push(error), loaderEvent: (loader, event) => events.push({ loader, event }) } }, console,
        window: { addEventListener() {}, removeEventListener() {},
            requestAnimationFrame: schedule, cancelAnimationFrame: cancel },
        wx: { getWindowInfo: () => ({ windowWidth: 390, windowHeight: 844, pixelRatio: 3, safeArea: { top: 47, bottom: 810 } }),
            getDeviceInfo: () => ({ platform }), env: { isSupportEmscriptenGLX: supportGLX },
            loadSubpackage: ({ name, success, fail }) => { assert.equal(name, 'engine'); subpackages++;
                packageSuccess = success; packageFail = fail;
                return { onProgressUpdate: callback => { progressCallback = callback; } }; } },
        setTimeout: schedule, clearTimeout: cancel,
        Image: class { constructor() { images.push(this); } },
        document: { createElement: () => {
            auxiliaryCanvases++;
            return { getContext: () => context2d };
        } },
    };
    const policy = configureRenderProbe(globals.wx, globals.GameGlobal, { androidRenderProbe: probe, iosStartupProfile: iosProfile });
    screen.getContext = type => { contexts.push(type); return gl; };
    vm.runInNewContext(source, globals);
    const loader = new globals.GameGlobal.GodotLoader(screen, {
        skipRendering: policy.skipLoaderRendering, lightRendering: policy.lightLoader,
        textConfig: { firstStartText: 'loading', downloadingText: ['downloading'], compilingText: 'compiling', initText: 'init', style: { fontSize: 15 } },
        barConfig: { style: { width: 240, height: 12, padding: 2, borderRadius: 6 } },
        iconConfig: { visible: false, style: { height: 30, bottom: 20 } },
        materialConfig: { backgroundImage: 'background.jpg' },
    });
    if (initialProgress !== null) loader.updateProgress(initialProgress, 'init');
    flush();
    return { loader, screen, frames, images, contexts, events, policy, auxiliaryCanvases, subpackages,
        root: globals.GameGlobal, captions, marks, tasks, flush,
        progress: value => progressCallback({ progress: value }), packageSuccess: () => packageSuccess(),
        packageFail: error => packageFail(error), clears: () => clears, draws: () => draws, deletions: () => deletions };
}

test('原加载器在 cleanup 后仍会被迟到图片与已排队的帧触发绘制', () => {
    const f = fixture(original);
    const lateImage = f.images[0].onload;
    f.loader.cleanup();
    const before = f.draws();
    lateImage();
    f.frames.forEach(fn => fn());
    assert.ok(f.draws() > before);
});

test('修复后 cleanup 幂等，迟到图片、进度、动画帧和 resize 不再绘制或改变游戏画布', () => {
    const f = fixture(patched);
    assert.ok(f.draws() > 0, 'loading screen still renders before cleanup');
    const lateImage = f.images[0].onload;
    f.loader.cleanup();
    const before = f.draws();
    const deletes = f.deletions();
    f.screen.width = 720;
    f.screen.height = 1280;
    lateImage();
    f.loader.updateProgress(100, 'late');
    f.frames.forEach(fn => fn());
    f.loader.resizeCanvases();
    f.loader.renderToWebGL();
    f.loader.cleanup();
    assert.equal(f.draws(), before);
    assert.equal(f.deletions(), deletes);
    assert.equal(f.screen.width, 720);
    assert.equal(f.screen.height, 1280);
    assert.equal(f.events.filter(item => item.event === 'cleanup').length, 1);
    assert.equal(f.events.filter(item => item.event === 'draw').length, before);
});

for (const platform of ['android', 'devtools']) {
    test(`${platform} B 组不创建辅助 Canvas、图片或 GL 上下文，仍加载分包并保持主画布尺寸`, () => {
        const f = fixture(patched, { probe: 'B', platform });
        assert.equal(f.auxiliaryCanvases, 0);
        assert.equal(f.images.length, 0);
        assert.deepEqual(f.contexts, []);
        assert.equal(f.draws(), 0);
        assert.equal(f.subpackages, 1);
        assert.equal(f.screen.width, 1170);
        assert.equal(f.screen.height, 2532);
        assert.equal(f.root.__godotMinigamePixelRatio, 3);
        assert.notEqual(f.root.__GODOT_DISABLE_WXGLX, true);
        f.loader.cleanup();
        f.loader.updateProgress(100, 'late');
        f.frames.forEach(fn => fn());
        f.loader.renderToWebGL();
        assert.equal(f.draws(), 0);
        assert.equal(f.deletions(), 0);
        assert.equal(f.events.filter(item => item.event === 'created').length, 1);
        assert.equal(f.events.filter(item => item.event === 'cleanup').length, 1);
    });
}

for (const probe of [undefined, 'A', 'B', 'C']) {
    test(`iOS 保持原 Loading 和 WXGLX 路径，不应用安卓对照 ${probe}`, () => {
        const f = fixture(patched, { probe, platform: 'ios' });
        assert.equal(f.policy.effective, null);
        assert.deepEqual(f.contexts, ['wxwebgl2']);
        assert.ok(f.draws() > 0);
        assert.equal(f.auxiliaryCanvases, 1);
    });
}

for (const probe of ['A', 'C']) {
    test(`安卓 ${probe || '普通包'} 在首次 getContext 前选定渲染路径`, () => {
        const f = fixture(patched, { probe });
        assert.deepEqual(f.contexts, [probe === 'C' ? 'webgl2' : 'wxwebgl2']);
        assert.equal(f.root.__godotMinigameWXGLXEnabled, probe !== 'C');
        assert.ok(f.draws() > 0);
    });
}

test('A 组设备未声明支持 WXGLX 时沿用模板 WebGL2 回退', () => {
    const f = fixture(patched, { probe: 'A', supportGLX: false });
    assert.deepEqual(f.contexts, ['webgl2']);
    assert.equal(f.root.__godotMinigameWXGLXEnabled, false);
});

test('普通安卓导出保留 B 兼容策略，iOS 普通导出不跳过 Loading', () => {
    for (const platform of ['android', 'ios']) {
        const policy = configureRenderProbe({ getDeviceInfo: () => ({ platform }) }, {}, {});
        assert.equal(policy.skipLoaderRendering, platform === 'android');
        assert.equal(policy.skipWasmRead, false);
    }
});

test('真实微信进度 1% 不会变成 100%，下载完成后转为引擎准备状态', () => {
    const f = fixture(patched, { initialProgress: null });
    for (const percent of [0, 1, 2, 50, 99]) {
        f.progress(percent);
        f.flush();
        assert.equal(f.loader.progress, percent / 100);
        assert.match(f.captions.at(-1)[0], new RegExp(`下载 ${percent}%$`));
    }
    f.progress(100);
    f.flush();
    assert.equal(f.loader.progress, null);
    assert.equal(f.loader.currentText, 'compiling');
    assert.equal(f.captions.at(-1)[0], 'compiling …');
    assert.ok(f.marks.includes('subpackage:downloaded'));
    f.loader.setStage('creating home');
    f.packageSuccess();
    f.progress(20);
    assert.equal(f.loader.currentText, 'creating home');
});

test('批量进度回调只安排一次绘制，清理释放辅助资源且不清黑主画布', () => {
    const f = fixture(patched, { platform: 'ios', iosProfile: 'loader', initialProgress: null });
    const auxiliary = f.loader.offScreenCanvas;
    assert.equal(auxiliary.width, 390);
    assert.equal(f.screen.width, 1170);
    const before = f.draws();
    for (let i = 1; i <= 50; i++) f.progress(i);
    assert.equal(f.tasks.size, 1);
    f.flush();
    assert.equal(f.draws(), before + 1);
    const lateImage = f.images[0].onload;
    f.progress(51);
    f.loader.cleanup();
    assert.equal(f.tasks.size, 0);
    assert.equal(f.loader.offScreenCanvas, null);
    assert.equal(auxiliary.width, 1);
    assert.equal(f.images[0].onload, null);
    assert.equal(f.loader.backgroundImage, null);
    assert.equal(f.clears(), 0);
    lateImage();
    f.flush();
    assert.equal(f.draws(), before + 1);
});

test('Loading 文案位于安全区 78% 附近的进度条上方，失败回调进入诊断', () => {
    const f = fixture(patched, { platform: 'ios', iosProfile: 'loader' });
    const [text, x, y] = f.captions.at(-1);
    assert.match(text, /init/);
    assert.equal(x, 195);
    assert.equal(y, 47 + (810 - 47) * 0.78 - 20);
    f.packageFail('download failed');
    assert.equal(f.marks.at(-1), 'download failed');
});

for (const profile of ['baseline', 'loader', 'wasm', 'combined']) {
    test(`iOS ${profile} 对照参数仅启用指定优化`, () => {
        const f = fixture(patched, { platform: 'ios', iosProfile: profile });
        assert.equal(f.policy.lightLoader, ['loader', 'combined'].includes(profile));
        assert.equal(f.policy.skipWasmRead, ['wasm', 'combined'].includes(profile));
        assert.equal(f.screen.width, 1170);
    });
}
