const assert = require('node:assert/strict');
const { test } = require('node:test');
const installHaptics = require('../platform/wechat/haptics');

function fixture(vibrateShort) {
    const events = {};
    const bridge = installHaptics({
        vibrateShort,
        onHide: callback => { events.hide = callback; },
        onShow: callback => { events.show = callback; },
    });
    return { bridge, events };
}

test('Godot 桥接只请求 light 短震动，后台禁止调用，前台恢复', () => {
    const calls = [];
    const { bridge, events } = fixture(options => calls.push(options));
    assert.equal(bridge.pulse(), true);
    assert.equal(calls[0].type, 'light');
    events.hide();
    assert.equal(bridge.pulse(), false);
    assert.equal(calls.length, 1);
    events.show();
    assert.equal(bridge.pulse(), true);
    assert.equal(calls.length, 2);
});

test('缺少震动 API 时安全跳过', () => {
    assert.equal(fixture().bridge.pulse(), false);
});

test('设备拒绝短震动时只提示一次，不重试更强震动', t => {
    const warnings = [];
    t.mock.method(console, 'warn', (...args) => warnings.push(args));
    let attempts = 0;
    const { bridge } = fixture(options => {
        attempts++;
        options.fail({ errMsg: 'style is not support' });
    });
    bridge.pulse();
    bridge.pulse();
    assert.equal(attempts, 2);
    assert.equal(warnings.length, 1);
});

test('同步接口错误不打断游戏', t => {
    t.mock.method(console, 'warn', () => {});
    const { bridge } = fixture(() => { throw new Error('device unavailable'); });
    assert.equal(bridge.pulse(), false);
});
