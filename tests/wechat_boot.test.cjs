const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const vm = require('node:vm');
const installBootDiagnostics = require('../platform/wechat/boot-diagnostics.js');

function fixture() {
    const handlers = {};
    const dialogs = [];
    const wx = {
        getDeviceInfo: () => ({ platform: 'ios' }),
        getAppBaseInfo: () => ({ version: '8.0.78', SDKVersion: '3.17.3' }),
        showModal: options => dialogs.push(options),
        onError: callback => { handlers.error = callback; },
        offError: callback => { assert.equal(handlers.error, callback); delete handlers.error; },
        onUnhandledRejection: callback => { handlers.rejection = callback; },
        offUnhandledRejection: callback => { assert.equal(handlers.rejection, callback); delete handlers.rejection; },
    };
    const root = { isIOSHighPerformanceMode: true };
    root.bbqBoot = installBootDiagnostics(wx, root);
    return { root, handlers, dialogs };
}

test('手机未处理的启动异常会显示错误与运行环境，重复上报只显示一次', () => {
    const { root, handlers, dialogs } = fixture();
    root.bbqBoot.stage('初始化游戏引擎与食材资源');
    handlers.rejection({ reason: new Error('WASM compile failed') });
    handlers.error('same failure');
    assert.equal(dialogs.length, 1);
    assert.match(dialogs[0].content, /WASM compile failed/);
    assert.match(dialogs[0].content, /初始化游戏引擎与食材资源/);
    assert.match(dialogs[0].content, /ios.*8\.0\.78.*3\.17\.3/);
    assert.match(dialogs[0].content, /高性能模式/);
});

const entry = readFileSync(new URL('../platform/wechat/engine-entry.js', `file://${__filename}`), 'utf8')
    .replace(/^import .*\n/gm, '');

for (const kind of ['throw', 'reject', 'success']) {
    test(`引擎入口 ${kind} 的结果会正确处理`, async () => {
        const { root, handlers, dialogs } = fixture();
        vm.runInNewContext(entry, {
            GameGlobal: root,
            GODOTSDK: {
                startGame(executable, pack) {
                    assert.equal(executable, '/engine/godot');
                    assert.equal(pack, '/engine/bbq.bin');
                    if (kind === 'throw') throw new Error('synchronous failure');
                    if (kind === 'reject') return Promise.reject(new Error('asynchronous failure'));
                    return Promise.resolve();
                },
            },
        });
        await new Promise(resolve => setImmediate(resolve));
        if (kind === 'success') {
            assert.equal(dialogs.length, 0);
            assert.deepEqual(handlers, {});
            root.bbqBoot.fail('late error');
            assert.equal(dialogs.length, 0);
        } else {
            assert.equal(dialogs.length, 1);
            assert.match(dialogs[0].content, /failure/);
        }
    });
}
