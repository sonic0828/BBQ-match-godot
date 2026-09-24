const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

// Exercise the actual pinned SDK, including the exporter's patch, rather than
// duplicating the problematic assignment in a fixture. Export once to cache it.
const { original, patched } = JSON.parse(execFileSync('python3', ['-c', `
import hashlib, json, zipfile
from tools.export_wechat import ROOT, VERSION, SHA256, patch_wechat_sdk
template = ROOT / 'build/cache' / f'minigame{VERSION}.tpz'
assert hashlib.sha256(template.read_bytes()).hexdigest() == SHA256
with zipfile.ZipFile(template) as archive:
    original = archive.read('engine/godot-sdk.js').decode()
print(json.dumps(dict(original=original, patched=patch_wechat_sdk(original))))
`], { cwd: path.resolve(__dirname, '..'), encoding: 'utf8' }));

function boot(source, platform, descriptor, highPerformance = false) {
    const context = {
        window: { Symbol },
        console: { log() {}, warn() {}, error() {} },
        setTimeout() {}, clearTimeout() {},
        isIOSHighPerformanceMode: highPerformance,
        WXWebAssembly: WebAssembly,
        wx: {
            env: { USER_DATA_PATH: '/test' },
            getSystemInfoSync: () => ({ platform, system: 'iOS 26.7', version: '8.0.78', SDKVersion: '3.17.3' }),
            getAccountInfoSync: () => ({ miniProgram: { envVersion: 'develop' } }),
            getFileSystemManager: () => ({ rmdir() {}, mkdir() {} }),
            createWebAudioContext: () => ({ resume() {}, suspend() {} }),
            onHide() {}, onShow() {}, onAudioInterruptionBegin() {}, onAudioInterruptionEnd() {},
        },
    };
    context.GameGlobal = context;
    Object.defineProperty(context.window, 'devicePixelRatio', descriptor);
    vm.runInNewContext('"use strict";\n' + source, context);
    return context;
}

test('原模板在 iOS getter-only 像素比例上复现 TypeError', () => {
    assert.throws(() => boot(original, 'ios', { get: () => 3, configurable: true }),
        error => error.name === 'TypeError' && /devicePixelRatio/.test(error.message));
});

for (const highPerformance of [false, true]) {
    for (const configurable of [false, true]) {
        test(`修复后的完整 SDK 可在 iOS 只读 getter 上初始化：高性能 ${highPerformance}，可配置 ${configurable}`, () => {
            const context = boot(patched, 'ios', { get: () => 3, configurable }, highPerformance);
            assert.equal(context.window.devicePixelRatio, 3);
            assert.equal(typeof context.GODOTSDK.startGame, 'function');
            assert.equal(typeof context.GODOTSDK.audio.WEBAudio.audioContext.resume, 'function');
            assert.equal(Object.getOwnPropertyDescriptor(context.window, 'devicePixelRatio').set, undefined);
        });
    }
}

for (const platform of ['ios', 'android', 'devtools', 'mac']) {
    for (const writable of [false, true]) {
        test(`保留 ${platform} 的实际像素比例，可写 ${writable}`, () => {
            const context = boot(patched, platform, { value: 3, writable });
            assert.equal(context.window.devicePixelRatio, 3);
            assert.equal(typeof context.GODOTSDK.startGame, 'function');
        });
    }
}
