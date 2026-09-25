const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const vm = require('node:vm');
const installBootDiagnostics = require('../platform/wechat/boot-diagnostics.js');

function fixture(t, options = {}, flags = { isIOSHighPerformanceMode: true }) {
    t.mock.timers.enable({ apis: ['setTimeout'] });
    const handlers = {};
    const dialogs = [];
    const reports = [];
    t.mock.method(console, 'log', (label, data) => {
        if (label === '[BBQ startup report]') reports.push(JSON.parse(data));
    });
    const wx = {
        getDeviceInfo: () => ({ platform: 'ios' }),
        getAppBaseInfo: () => ({ version: '8.0.78', SDKVersion: '3.17.3' }),
        showModal: options => dialogs.push(options),
        setClipboardData: () => assert.fail('启动诊断不应依赖剪贴板隐私权限'),
        onError: callback => { handlers.error = callback; },
        offError: callback => { assert.equal(handlers.error, callback); delete handlers.error; },
        onUnhandledRejection: callback => { handlers.rejection = callback; },
        offUnhandledRejection: callback => { assert.equal(handlers.rejection, callback); delete handlers.rejection; },
    };
    const root = { ...flags };
    root.bbqBoot = installBootDiagnostics(wx, root, options);
    return { root, handlers, dialogs, reports };
}

test('错误洪流后重新输出完整首错和次数，弹窗不调用需隐私声明的剪贴板', t => {
    const logged = [];
    t.mock.method(console, 'error', (...args) => logged.push(args));
    const { root, dialogs, reports } = fixture(t, { diagnostics: true });
    root.bbqBoot.printError('original startup failure');
    for (let i = 0; i < 1500; i++) root.bbqBoot.printError('repeated ObjectDB failure');
    t.mock.timers.tick(30000);
    assert.match(dialogs[0].content, /首次：original startup failure/);
    assert.equal(logged.length, 2);
    assert.equal(dialogs[0].showCancel, false);
    assert.equal(dialogs[0].confirmText, '知道了');
    assert.equal(dialogs[0].success, undefined);
    const report = reports[0];
    assert.equal(report.errorCount, 1501);
    assert.equal(report.firstErrors[0].line, 'original startup failure');
    assert.equal(report.errorStats[1].count, 1500);
});

for (const flags of [
    { isIOSHighPerformanceMode: false, isIOSHighPerformanceModePlus: true },
    { isIOSHighPerformanceMode: false, isIOSHighPerformanceModePlus: false },
    {},
]) {
    test(`分别记录 iOS 高性能与 Plus 标志 ${JSON.stringify(flags)}`, t => {
        const { reports } = fixture(t, { diagnostics: true }, flags);
        t.mock.timers.tick(30000);
        const report = reports[0];
        assert.equal(report.highPerformance, flags.isIOSHighPerformanceMode ?? null);
        assert.equal(report.highPerformancePlus, flags.isIOSHighPerformanceModePlus ?? null);
        assert.equal(report.mode, flags.isIOSHighPerformanceModePlus ? '高性能 Plus 模式' : '普通模式');
    });
}

for (const corrupted of [false, true]) {
    test(`核对预加载资源字节与当前 WASM 内存，资源损坏 ${corrupted}`, t => {
        const { root, reports } = fixture(t, {
            diagnostics: true, pack: { bytes: 9, crc32: 'cbf43926' },
        });
        const bytes = new Uint8Array([0, ...Buffer.from(corrupted ? '123456780' : '123456789'), 0]);
        const engine = {
            preloader: { preloadedFiles: [{ path: '/engine/bbq.bin', buffer: bytes.subarray(1, 10) }] },
            rtenv: { HEAPU8: new Uint8Array(1024) },
        };
        root.bbqBoot.inspectRuntime(engine);
        engine.rtenv.HEAPU8 = new Uint8Array(2048);
        t.mock.timers.tick(30000);
        const report = reports[0];
        assert.equal(report.runtime.pack.matches, !corrupted);
        assert.equal(report.runtime.pack.bytes, 9);
        assert.equal(report.runtime.wasmMemoryBytes, 2048);
        assert.equal(engine.preloader.preloadedFiles.length, 1);
    });
}

test('缺少运行时诊断字段不会阻止启动与首帧', t => {
    const { root, handlers, dialogs } = fixture(t, { diagnostics: true });
    root.bbqBoot.inspectRuntime({});
    root.bbqBoot.ready();
    root.bbqBoot.print('[BBQ first frame]');
    t.mock.timers.tick(3000);
    assert.match(dialogs[0].content, /首帧 已绘制/);
    assert.deepEqual(handlers, {});
});

test('手机未处理的启动异常会显示错误与运行环境，重复上报只显示一次', t => {
    const { root, handlers, dialogs } = fixture(t);
    root.bbqBoot.stage('初始化游戏引擎与食材资源');
    const onError = handlers.error;
    handlers.rejection({ reason: new Error('WASM compile failed') });
    onError('same failure');
    assert.equal(dialogs.length, 1);
    assert.match(dialogs[0].content, /WASM compile failed/);
    assert.match(dialogs[0].content, /初始化游戏引擎与食材资源/);
    assert.match(dialogs[0].content, /ios.*8\.0\.78.*3\.17\.3/);
    assert.match(dialogs[0].content, /高性能模式/);
    assert.deepEqual(handlers, {});
});

test('引擎 Promise 完成不代表首帧成功，超时报告 Godot stderr', t => {
    const { root, dialogs } = fixture(t);
    root.bbqBoot.ready();
    root.bbqBoot.printError('ERROR: Unable to create OpenGL context');
    t.mock.timers.tick(30000);
    assert.equal(dialogs.length, 1);
    assert.match(dialogs[0].content, /引擎 已启动.*场景 未确认.*首帧 未确认/);
    assert.match(dialogs[0].content, /Unable to create OpenGL context/);
});

for (const frameFirst of [false, true]) {
    test(`普通包首帧确认后解除启动监听，首帧先到 ${frameFirst}`, t => {
        const { root, handlers, dialogs } = fixture(t);
        if (!frameFirst) root.bbqBoot.ready();
        root.bbqBoot.print('[BBQ scene ready] (720, 1280)');
        root.bbqBoot.print('[BBQ first frame]');
        if (frameFirst) root.bbqBoot.ready();
        assert.deepEqual(handlers, {});
        t.mock.timers.tick(30000);
        assert.equal(dialogs.length, 0);
    });
}

test('诊断包显示首帧与实际 WebGL 缓冲尺寸，不修改或重绘画布', t => {
    const { root, dialogs } = fixture(t, { diagnostics: true, build: 'render-test' });
    root.godotLoader = {
        onScreenCanvas: Object.freeze({ width: 1206, height: 2622 }),
        gl: { drawingBufferWidth: 1206, drawingBufferHeight: 2622,
            isContextLost: () => false, getError: () => 0 },
    };
    root.bbqBoot.ready();
    root.bbqBoot.print('[BBQ scene ready] (720, 1565)');
    root.bbqBoot.print('[BBQ first frame]');
    t.mock.timers.tick(3000);
    assert.equal(dialogs.length, 1);
    assert.match(dialogs[0].content, /render-test/);
    assert.match(dialogs[0].content, /首帧 已绘制/);
    assert.match(dialogs[0].content, /WebGL2.*画布 1206×2622/);
    assert.match(dialogs[0].content, /缓冲 1206×2622.*丢失 false.*GL 0/);
});

const entry = readFileSync(new URL('../platform/wechat/engine-entry.js', `file://${__filename}`), 'utf8')
    .replace(/^import .*\n/gm, '');

for (const kind of ['throw', 'init-reject', 'pack-reject', 'start-reject', 'exit', 'success']) {
    test(`引擎入口 ${kind} 的结果会正确处理`, async t => {
        const { root, handlers, dialogs } = fixture(t);
        let cleaned = false;
        root.godotLoader = {
            config: { textConfig: { compilingText: 'compiling' } },
            cleanup() { cleaned = true; },
        };
        const canvas = {};
        const sdk = {};
        vm.runInNewContext(entry, {
            GameGlobal: root, GODOTSDK: sdk, canvas,
            Engine: class {
                constructor(options) {
                    if (kind === 'throw') throw new Error('constructor failure');
                    assert.equal(options.canvas, canvas);
                    this.options = options;
                }
                init(executable) {
                    assert.equal(executable, '/engine/godot');
                    if (kind === 'init-reject') return Promise.reject(new Error('init failure'));
                    return Promise.resolve();
                }
                preloadFile(pack) {
                    assert.equal(pack, '/engine/bbq.bin');
                    if (kind === 'pack-reject') return Promise.reject(new Error('pack failure'));
                    return Promise.resolve();
                }
                start(options) {
                    assert.equal(cleaned, true);
                    assert.deepEqual(Array.from(options.args), ['--main-pack', '/engine/bbq.bin']);
                    if (kind === 'start-reject') return Promise.reject(new Error('start failure'));
                    if (kind === 'exit') this.options.onExit(1);
                    return Promise.resolve();
                }
            },
        });
        await new Promise(resolve => setImmediate(resolve));
        if (kind === 'success') {
            assert.equal(dialogs.length, 0);
            assert.equal(typeof handlers.error, 'function');
            sdk.engine.options.onPrint('[BBQ scene ready] (720, 1280)');
            sdk.engine.options.onPrint('[BBQ first frame]');
            assert.deepEqual(handlers, {});
        } else {
            assert.equal(dialogs.length, 1);
            assert.match(dialogs[0].content, /failure|退出码 1/);
        }
    });
}
