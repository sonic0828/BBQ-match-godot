const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

// Use the shipped adapter and engine's actual focus registration, not a second
// implementation of the event routing that failed on the phone.
const { adapter, registration } = JSON.parse(execFileSync('python3', ['-B', '-c', `
import hashlib, json, zipfile
from tools.export_wechat import ROOT, VERSION, SHA256
template = ROOT / 'build/cache' / f'minigame{VERSION}.tpz'
assert hashlib.sha256(template.read_bytes()).hexdigest() == SHA256
with zipfile.ZipFile(template) as archive:
    adapter = archive.read('weapp-adapter.js').decode()
    engine = archive.read('engine/godot.js').decode()
start = engine.index('function _godot_js_display_notification_cb(')
end = engine.index('function _godot_js_display_pixel_ratio_get(', start)
print(json.dumps(dict(adapter=adapter, registration=engine[start:end])))
`], { cwd: path.resolve(__dirname, '..'), encoding: 'utf8' }));

test('真实微信入口经固定模板适配器向 Godot 转发窗口失焦和恢复，不重建 Loader', () => {
    const host = {}, events = [];
    let loaders = 0;
    class Canvas { getContext() { assert.fail('生命周期不应创建 GL 上下文'); } }
    const context = vm.createContext({
        console, setTimeout, clearTimeout, setInterval, clearInterval,
        requestAnimationFrame() {}, cancelAnimationFrame() {},
        wx: {
            getSystemInfoSync: () => ({ platform: 'android', windowWidth: 360, windowHeight: 840 }),
            createCanvas: () => new Canvas(), createImage: () => ({}),
            onTouchStart() {}, onTouchMove() {}, onTouchEnd() {}, onTouchCancel() {},
            onNetworkStatusChange() {},
            onHide: fn => { host.hide = fn; }, onShow: fn => { host.show = fn; },
        },
        GodotLoader: class { constructor() { loaders++; } },
    });
    context.GameGlobal = context;
    context.require = name => {
        if (name === './weapp-adapter') vm.runInContext(adapter, context);
        if (name === './render-probe') return () => ({ skipLoaderRendering: true });
        if (name === './boot-options') return {};
        if (name === './boot-diagnostics') return () => ({ mark() {},
            visibility: value => events.push(['host', value]) });
        if (name === './haptics' || name === './game-club') return () => ({});
        return {};
    };
    vm.runInContext(readFileSync(path.join(__dirname, '../platform/wechat/game.js'), 'utf8'), context);
    context.GodotConfig = { canvas: context.canvas };
    context.GodotRuntime = { get_func: () => value => events.push(['godot', value]) };
    context.GodotEventListeners = { add: (target, type, fn) => target.addEventListener(type, fn) };
    vm.runInContext(registration + '_godot_js_display_notification_cb(0,1002,1003,1004,1005);', context);
    host.hide();
    host.show({ scene: 1089 });
    assert.deepEqual(events, [['host', false], ['godot', 1005], ['host', true], ['godot', 1004]]);
    assert.equal(loaders, 1);
});
