const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

const { original, patched } = JSON.parse(execFileSync('python3', ['-B', '-c', `
import hashlib, json, zipfile
from tools.export_wechat import ROOT, VERSION, SHA256, patch_wechat_loader
template = ROOT / 'build/cache' / f'minigame{VERSION}.tpz'
assert hashlib.sha256(template.read_bytes()).hexdigest() == SHA256
with zipfile.ZipFile(template) as archive:
    original = archive.read('godot-loader.js').decode()
print(json.dumps(dict(original=original, patched=patch_wechat_loader(original))))
`], { cwd: path.resolve(__dirname, '..'), encoding: 'utf8' }));

function fixture(source) {
    const frames = [];
    const images = [];
    let draws = 0;
    let deletions = 0;
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
        GameGlobal: {}, console,
        window: { addEventListener() {}, removeEventListener() {},
            requestAnimationFrame: fn => frames.push(fn) },
        wx: { getWindowInfo: () => ({ windowWidth: 390, windowHeight: 844, pixelRatio: 3 }) },
        Image: class { constructor() { images.push(this); } },
        document: { createElement: () => ({ getContext: () => context2d }) },
    };
    screen.getContext = () => gl;
    vm.runInNewContext(source, globals);
    const loader = new globals.GameGlobal.GodotLoader(screen, {
        textConfig: { firstStartText: 'loading', style: { fontSize: 15 } },
        barConfig: { style: { width: 240, height: 12, padding: 2, borderRadius: 6 } },
        iconConfig: { visible: false, style: { height: 30, bottom: 20 } },
        materialConfig: { backgroundImage: 'background.jpg' },
    });
    loader.updateProgress(100, 'init');
    return { loader, screen, frames, images, draws: () => draws, deletions: () => deletions };
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
    f.loader.cleanup();
    assert.equal(f.draws(), before);
    assert.equal(f.deletions(), deletes);
    assert.equal(f.screen.width, 720);
    assert.equal(f.screen.height, 1280);
});
