const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const { test } = require('node:test');
const configure = require('../platform/wechat/render-probe');

function options(...argv) {
    return JSON.parse(execFileSync('python3', ['-B', '-c', `
import json, sys
from tools.export_wechat import parse_args
a = parse_args(sys.argv[1:])
print(json.dumps(dict(androidRenderProbe=a.android_render_probe,
    iosStartupProfile=a.ios_startup_profile, androidNativeLoading=a.android_native_loading,
    diagnostics=a.diagnostics, minimal=a.startup_minimal)))
`, ...argv], { cwd: path.resolve(__dirname, '..'), encoding: 'utf8' }));
}

test('普通导出使用安卓 D、iOS 轻量 Loading、原生等待，完整游戏且关闭详细诊断', () => {
    const defaults = options();
    assert.deepEqual(defaults, { androidRenderProbe: 'D', iosStartupProfile: 'loader',
        androidNativeLoading: true, diagnostics: false, minimal: false });
    for (const platform of ['android', 'ios', 'devtools']) {
        const root = {};
        const policy = configure({ getDeviceInfo: () => ({ platform }) }, root, defaults);
        assert.equal(policy.skipLoaderRendering, platform !== 'ios');
        assert.equal(root.__GODOT_DISABLE_WXGLX === true, platform !== 'ios');
        assert.equal(policy.lightLoader, platform === 'ios');
        assert.equal(policy.skipWasmRead, false);
    }
});

test('诊断、最小场景和实验需要显式选择，不由默认优化策略隐式开启', () => {
    const diagnostic = options('--diagnostics');
    assert.deepEqual(diagnostic, { ...options(), diagnostics: true });
    const comparison = options('--android-render-probe', 'B', '--ios-startup-profile', 'baseline', '--no-android-native-loading');
    assert.equal(comparison.androidRenderProbe, 'B');
    assert.equal(comparison.iosStartupProfile, 'baseline');
    assert.equal(comparison.androidNativeLoading, false);
    assert.equal(comparison.diagnostics, false);
    assert.equal(options('--startup-minimal', '--diagnostics').minimal, true);
});
