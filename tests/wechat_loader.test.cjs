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

function fixture(source, { probe, platform = 'android', supportGLX = true } = {}) {
    const frames = [];
    const images = [];
    let draws = 0;
    let deletions = 0;
    let auxiliaryCanvases = 0;
    let subpackages = 0;
    const contexts = [];
    const events = [];
    const screen = { width: 390, height: 844, style: {} };
    const context2d = new Proxy({}, { get: () => () => {} });
    const gl = new Proxy({ canvas: screen }, { get(target, key) {
        if (key in target) return target[key];
        if (key === 'drawArrays') return () => draws++;
        if (String(key).startsWith('delete')) return () => deletions++;
        if (String(key).startsWith('get')) return () => true;
        if (String(key).startsWith('create')) return () => ({});
        return () => {};
    } });
    const globals = {
        GameGlobal: { bbqBoot: { loaderEvent: (loader, event) => events.push({ loader, event }) } }, console,
        window: { addEventListener() {}, removeEventListener() {},
            requestAnimationFrame: fn => frames.push(fn) },
        wx: { getWindowInfo: () => ({ windowWidth: 390, windowHeight: 844, pixelRatio: 3 }),
            getDeviceInfo: () => ({ platform }), env: { isSupportEmscriptenGLX: supportGLX },
            loadSubpackage: ({ name }) => { assert.equal(name, 'engine'); subpackages++; } },
        Image: class { constructor() { images.push(this); } },
        document: { createElement: () => {
            auxiliaryCanvases++;
            return { getContext: () => context2d };
        } },
    };
    const policy = configureRenderProbe(globals.wx, globals.GameGlobal, { androidRenderProbe: probe });
    screen.getContext = type => { contexts.push(type); return gl; };
    vm.runInNewContext(source, globals);
    const loader = new globals.GameGlobal.GodotLoader(screen, {
        skipRendering: policy.skipLoaderRendering,
        textConfig: { firstStartText: 'loading', style: { fontSize: 15 } },
        barConfig: { style: { width: 240, height: 12, padding: 2, borderRadius: 6 } },
        iconConfig: { visible: false, style: { height: 30, bottom: 20 } },
        materialConfig: { backgroundImage: 'background.jpg' },
    });
    loader.updateProgress(100, 'init');
    return { loader, screen, frames, images, contexts, events, policy, auxiliaryCanvases, subpackages,
        root: globals.GameGlobal, draws: () => draws, deletions: () => deletions };
}

test('原加载器在 cleanup 后仍会被迟到图片与已排队的帧触发绘制', () => {
    const f = fixture(original);
    f.loader.cleanup();
    const before = f.draws();
    f.images[0].onload();
    f.frames.forEach(fn => fn());
    assert.equal(f.draws(), before + 2);
});

test('修复后 cleanup 幂等，迟到图片、进度、动画帧和 resize 不再绘制或改变游戏画布', () => {
    const f = fixture(patched);
    assert.ok(f.draws() > 0, 'loading screen still renders before cleanup');
    f.loader.cleanup();
    const before = f.draws();
    const deletes = f.deletions();
    f.screen.width = 720;
    f.screen.height = 1280;
    f.images[0].onload();
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

for (const probe of [undefined, 'A', 'C']) {
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
