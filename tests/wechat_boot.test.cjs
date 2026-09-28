const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const vm = require('node:vm');
const installBootDiagnostics = require('../platform/wechat/boot-diagnostics.js');

function fixture(t, options = {}, flags = { isIOSHighPerformanceMode: true }, device = { platform: 'ios' }) {
    t.mock.timers.enable({ apis: ['setTimeout', 'Date'] });
    const handlers = {};
    const dialogs = [];
    const reports = [];
    const storage = {};
    const checkpoints = [];
    const nativeLoading = [];
    t.mock.method(console, 'log', (label, data) => {
        if (label === '[BBQ startup report]') reports.push(JSON.parse(data));
    });
    const wx = {
        getDeviceInfo: () => device,
        getLaunchOptionsSync: () => ({ scene: 1011, query: { privateToken: 'must-not-log' } }),
        getEnterOptionsSync: () => ({ scene: 1089, query: { privateToken: 'must-not-log' } }),
        getStorageSync: key => storage[key],
        setStorageSync: (key, value) => { storage[key] = value; checkpoints.push(value); },
        onMemoryWarning: callback => { handlers.memory = callback; },
        offMemoryWarning: () => { delete handlers.memory; },
        getAppBaseInfo: () => ({ version: '8.0.78', SDKVersion: '3.17.3' }),
        showModal: options => dialogs.push(options),
        showLoading: options => nativeLoading.push(options.title),
        hideLoading: () => nativeLoading.push('hide'),
        setClipboardData: () => assert.fail('启动诊断不应依赖剪贴板隐私权限'),
        onError: callback => { handlers.error = callback; },
        offError: callback => { assert.equal(handlers.error, callback); delete handlers.error; },
        onUnhandledRejection: callback => { handlers.rejection = callback; },
        offUnhandledRejection: callback => { assert.equal(handlers.rejection, callback); delete handlers.rejection; },
    };
    const root = { ...flags };
    root.bbqBoot = installBootDiagnostics(wx, root, options);
    return { root, wx, handlers, dialogs, reports, storage, checkpoints, nativeLoading };
}

test('慢启动仅记录错误汇总，不弹技术诊断窗', t => {
    const logged = [];
    t.mock.method(console, 'error', (...args) => logged.push(args));
    const { root, dialogs, reports } = fixture(t, { diagnostics: true });
    root.bbqBoot.printError('original startup failure');
    for (let i = 0; i < 1500; i++) root.bbqBoot.printError('repeated ObjectDB failure');
    t.mock.timers.tick(30000);
    assert.equal(dialogs.length, 0);
    assert.equal(logged.length, 2);
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

for (const truncated of [false, true]) {
    test(`轻量诊断只核对字节数，不在首帧前扫描 CRC，长度不符 ${truncated}`, t => {
        const { root, reports } = fixture(t, {
            diagnostics: true, pack: { bytes: 9, crc32: 'cbf43926' },
        });
        const bytes = new Uint8Array([0, ...Buffer.from(truncated ? '12345678' : '123456789'), 0]);
        const engine = {
            preloader: { preloadedFiles: [{ path: '/engine/bbq.bin', buffer: bytes.subarray(1, bytes.length - 1) }] },
            rtenv: { HEAPU8: new Uint8Array(1024) },
        };
        root.bbqBoot.inspectRuntime(engine);
        engine.rtenv.HEAPU8 = new Uint8Array(2048);
        t.mock.timers.tick(30000);
        const report = reports[0];
        assert.equal(report.runtime.pack.sizeMatches, !truncated);
        assert.equal(report.runtime.pack.bytes, truncated ? 8 : 9);
        assert.equal(report.runtime.wasmMemoryBytes, 2048);
        assert.equal(engine.preloader.preloadedFiles.length, 1);
    });
}

test('缺少运行时诊断字段不会阻止启动与首帧，观察结束只输出日志', t => {
    const { root, handlers, dialogs, reports } = fixture(t, { diagnostics: true });
    root.bbqBoot.inspectRuntime({});
    root.bbqBoot.ready();
    root.bbqBoot.print('[BBQ first frame]');
    t.mock.timers.tick(120000);
    assert.equal(reports[0].firstFrame, true);
    assert.equal(dialogs.length, 0);
    assert.deepEqual(handlers, {});
});

test('手机未处理的启动异常会显示错误与运行环境，重复上报只显示一次', t => {
    const { root, handlers, dialogs, reports } = fixture(t);
    root.bbqBoot.stage('初始化游戏引擎与食材资源');
    const onError = handlers.error;
    handlers.rejection({ reason: new Error('WASM compile failed') });
    onError('same failure');
    assert.equal(dialogs.length, 1);
    assert.match(reports[0].detail, /WASM compile failed/);
    assert.match(reports[0].phase, /初始化游戏引擎与食材资源/);
    assert.match(reports[0].environment, /ios.*8\.0\.78.*3\.17\.3/);
    assert.equal(dialogs[0].content, '请退出小游戏后重新打开。');
    assert.deepEqual(handlers, {});
});

test('引擎 Promise 完成不代表首帧成功，超时报告 Godot stderr', t => {
    const { root, dialogs, reports } = fixture(t);
    root.bbqBoot.ready();
    root.bbqBoot.printError('ERROR: Unable to create OpenGL context');
    t.mock.timers.tick(30000);
    assert.equal(dialogs.length, 0);
    assert.equal(reports[0].engineStarted, true);
    assert.equal(reports[0].firstFrame, false);
    assert.match(reports[0].firstErrors[0].line, /Unable to create OpenGL context/);
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
    const { root, dialogs, reports } = fixture(t, { diagnostics: true, build: 'render-test' });
    root.__godotMinigameWXGLXEnabled = false;
    root.godotLoader = {
        onScreenCanvas: Object.freeze({ width: 1206, height: 2622 }),
        gl: { drawingBufferWidth: 1206, drawingBufferHeight: 2622,
            isContextLost: () => false, getError: () => 0 },
    };
    root.bbqBoot.ready();
    root.bbqBoot.print('[BBQ scene ready] (720, 1565)');
    root.bbqBoot.print('[BBQ first frame]');
    t.mock.timers.tick(120000);
    assert.equal(dialogs.length, 0);
    assert.equal(reports[0].build, 'render-test');
    assert.equal(reports[0].firstFrame, true);
    assert.match(reports[0].rendering, /WebGL2.*画布 1206×2622/);
    assert.match(reports[0].rendering, /缓冲 1206×2622.*丢失 false.*GL 0/);
});

test('首帧后的微信异常、Promise 拒绝与 Godot 错误持续汇总 120 秒，不弹窗且不延长观察窗口', t => {
    const logged = [];
    t.mock.method(console, 'error', (...args) => logged.push(args));
    const { root, handlers, dialogs, reports } = fixture(t, { diagnostics: true });
    root.bbqBoot.print('[BBQ first frame]');
    root.bbqBoot.ready();
    t.mock.timers.tick(30000);
    for (let i = 0; i < 100; i++) handlers.error({ message: 'WAPixi vertex_attrib' });
    handlers.rejection({ reason: new Error('late rejection') });
    root.bbqBoot.printError('Godot draw failure');
    root.bbqBoot.print('[BBQ first frame]');
    root.bbqBoot.ready();
    assert.equal(dialogs.length, 0);
    assert.equal(reports.length, 0);
    t.mock.timers.tick(89999);
    assert.equal(reports.length, 0);
    t.mock.timers.tick(1);
    assert.equal(reports.length, 1);
    assert.equal(reports[0].errorCount, 102);
    assert.equal(reports[0].errorStats[0].count, 100);
    assert.equal(reports[0].observationMs, 120000);
    assert.equal(logged.length, 3);
    assert.deepEqual(handlers, {});
    assert.equal(dialogs.length, 0);
});

test('诊断区分迟到 render 调用和实际绘制，记录多实例及上下文事件并移除监听', t => {
    const { root, reports } = fixture(t, { diagnostics: true }, {}, {
        platform: 'android', model: 'OPPO Find N3 Flip', system: 'Android 16',
    });
    const listeners = {};
    const canvas = { width: 1080, height: 2520,
        addEventListener: (event, fn) => { listeners[event] = fn; },
        removeEventListener: event => { delete listeners[event]; },
    };
    const loader = { config: {}, onScreenCanvas: canvas, currentText: 'loading' };
    root.godotLoader = loader;
    root.__godotMinigameWXGLXEnabled = true;
    root.bbqBoot.loaderEvent(loader, 'created');
    root.bbqBoot.loaderEvent(loader, 'draw');
    loader.disposed = true;
    root.bbqBoot.loaderEvent(loader, 'cleanup');
    root.bbqBoot.ready();
    root.bbqBoot.print('[BBQ first frame]');
    root.bbqBoot.loaderEvent(loader, 'render');
    root.bbqBoot.loaderEvent(loader, 'draw'); // Simulate an actual lifecycle violation.
    root.bbqBoot.loaderEvent({ config: { skipRendering: true } }, 'created');
    listeners.webglcontextlost({ type: 'webglcontextlost' });
    t.mock.timers.tick(120000);
    const report = reports[0];
    assert.equal(report.loaderInstances, 2);
    assert.equal(report.loaders[0].draws, 2);
    assert.equal(report.loaders[0].drawsAfterCleanup, 1);
    assert.equal(report.loaders[0].drawsAfterFirstFrame, 1);
    assert.equal(report.loaders[0].renderCallsAfterCleanup, 1);
    assert.equal(typeof report.loaders[0].cleanupElapsedMs, 'number');
    assert.equal(typeof report.firstFrameElapsedMs, 'number');
    assert.equal(report.loaders[1].draws, 0);
    assert.equal(report.renderPath, 'WXGLX');
    assert.equal(report.device.model, 'OPPO Find N3 Flip');
    assert.match(report.mode, /不适用/);
    assert.equal(report.contextEvents[0].type, 'webglcontextlost');
    assert.deepEqual(listeners, {});
});

const entry = readFileSync(new URL('../platform/wechat/engine-entry.js', `file://${__filename}`), 'utf8');

test('45 秒首帧仍被记录，超时不会解除监听或阻止后续观察', t => {
    const { root, reports, dialogs, handlers, checkpoints } = fixture(t, { diagnostics: true, build: 'slow' });
    t.mock.timers.tick(30000);
    assert.equal(reports.length, 1);
    assert.equal(dialogs.length, 0);
    assert.equal(typeof handlers.error, 'function');
    t.mock.timers.tick(15000);
    root.bbqBoot.ready();
    root.bbqBoot.print('[BBQ first frame]');
    root.bbqBoot.print('[BBQ frame sample] {"fps":30,"frames_over_50ms":2}');
    handlers.memory({});
    root.bbqBoot.visibility(false);
    assert.equal(checkpoints.at(-1).foreground, false);
    root.bbqBoot.visibility(true);
    t.mock.timers.tick(120000);
    assert.equal(reports[1].firstFrameElapsedMs, 45000);
    assert.equal(reports[1].frameSamples[0].fps, 30);
    assert.equal(reports[1].memoryWarnings.length, 1);
    assert.equal(checkpoints.at(-1).status, 'observed');
    assert.equal(dialogs.length, 0);
    assert.deepEqual(handlers, {});
});

test('普通包同样不因超过 30 秒弹窗，仍可完成启动', t => {
    const { root, dialogs, reports, checkpoints } = fixture(t);
    t.mock.timers.tick(50000);
    root.bbqBoot.ready();
    root.bbqBoot.print('[BBQ first frame]');
    assert.equal(dialogs.length, 0);
    assert.equal(reports.at(-1).firstFrameElapsedMs, 50000);
    assert.equal(checkpoints.length, 0);
});

for (const kind of ['throw', 'init-reject', 'pack-reject', 'start-reject', 'exit', 'success']) {
    test(`引擎入口 ${kind} 的结果会正确处理`, async t => {
        const { root, handlers, dialogs, reports } = fixture(t);
        let cleaned = false;
        root.godotLoader = {
            config: { textConfig: { compilingText: 'compiling', initText: 'creating' } },
            setStage() {},
            handoff(text) { assert.equal(text, 'creating'); cleaned = true; },
        };
        const canvas = {};
        const sdk = {};
        vm.runInNewContext(entry, {
            GameGlobal: root, GODOTSDK: sdk, canvas, require() {},
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
            assert.match(reports[0].detail, /failure|退出码 1/);
        }
    });
}

test('120 秒结束后仍保留前后台检查点，恢复后重开 30 秒观察且等待实际帧信号', t => {
    const f = fixture(t, { diagnostics: true, build: 'reentry' });
    f.root.bbqBoot.mark('engine-entry');
    f.root.bbqBoot.ready();
    f.root.bbqBoot.print('[BBQ first frame]');
    t.mock.timers.tick(120000);
    assert.deepEqual(f.handlers, {});
    const originalId = f.checkpoints.at(-1).instanceId;
    f.root.bbqBoot.visibility(false);
    assert.equal(f.checkpoints.at(-1).lastEvent, 'hide');
    f.root.bbqBoot.print('[BBQ resume frame]');
    f.root.bbqBoot.visibility(true);
    assert.equal(typeof f.handlers.error, 'function');
    assert.equal(f.checkpoints.at(-1).resumeFrameElapsedMs, null);
    assert.equal(f.checkpoints.at(-1).entry.scene, 1089);
    assert.equal(f.checkpoints.at(-1).launch.scene, 1011);
    t.mock.timers.tick(250);
    f.root.bbqBoot.print('[BBQ resume frame] home');
    f.handlers.error({ message: 'restore draw error' });
    f.root.bbqBoot.print('[BBQ frame sample] {"fps":30}');
    f.root.bbqBoot.visibility(true); // A duplicate onShow must not reset the timer.
    t.mock.timers.tick(29749);
    assert.equal(f.reports.length, 1);
    t.mock.timers.tick(1);
    const report = f.reports[1];
    assert.equal(report.instanceId, originalId);
    assert.equal(report.observationKind, 'resume');
    assert.equal(report.observationMs, 30000);
    assert.equal(report.resumeCount, 1);
    assert.equal(report.resumeFrameElapsedMs, 250);
    assert.equal(report.engineEntries, 1);
    assert.equal(report.errorCount, 1);
    assert.equal(report.frameSamples.at(-1).fps, 30);
    assert.equal(f.dialogs.length, 0);
    assert.deepEqual(f.handlers, {});
    assert.doesNotMatch(JSON.stringify(f.checkpoints), /privateToken|must-not-log/);
});

test('多次恢复记录有界，不重建加载器；没有首帧的恢复不会假报成功', t => {
    const f = fixture(t, { diagnostics: true });
    f.root.bbqBoot.ready();
    f.root.bbqBoot.print('[BBQ first frame]');
    t.mock.timers.tick(120000);
    for (let i = 0; i < 40; i++) {
        f.root.bbqBoot.visibility(false);
        f.root.bbqBoot.visibility(true);
        t.mock.timers.tick(30000);
    }
    const last = f.reports.at(-1);
    assert.equal(last.resumeCount, 40);
    assert.equal(last.resumeFrameElapsedMs, null);
    assert.equal(last.lifecycle.length, 32);
    assert.ok(last.marks.length <= 64);
    assert.equal(last.loaderInstances, 0);
    assert.deepEqual(f.handlers, {});
});

test('恢复观察重新监听原画布，观察结束解除监听；不调用 getContext', t => {
    const f = fixture(t, { diagnostics: true });
    const listeners = {};
    const loader = { config: {}, onScreenCanvas: {
        getContext: () => assert.fail('诊断不能创建图形上下文'),
        addEventListener: (name, fn) => { listeners[name] = fn; },
        removeEventListener: name => { delete listeners[name]; },
    } };
    f.root.godotLoader = loader;
    f.root.bbqBoot.loaderEvent(loader, 'created');
    f.root.bbqBoot.ready();
    f.root.bbqBoot.print('[BBQ first frame]');
    t.mock.timers.tick(120000);
    assert.deepEqual(listeners, {});
    f.root.bbqBoot.visibility(false);
    f.root.bbqBoot.visibility(true);
    listeners.webglcontextlost({ type: 'webglcontextlost' });
    f.handlers.memory({ level: 15 });
    t.mock.timers.tick(30000);
    assert.equal(f.reports.at(-1).contextEvents.at(-1).type, 'webglcontextlost');
    assert.equal(f.reports.at(-1).memoryWarnings.at(-1).level, 15);
    assert.deepEqual(listeners, {});
});

test('新实例读取上次检查点并递增启动计数；热恢复保持同一实例', t => {
    const f = fixture(t, { diagnostics: true, build: 'same-build' });
    const firstId = f.checkpoints[0].instanceId;
    f.root.bbqBoot.ready();
    f.root.bbqBoot.print('[BBQ first frame]');
    t.mock.timers.tick(120000);
    t.mock.timers.tick(1);
    const second = installBootDiagnostics(f.wx, {}, { diagnostics: true, build: 'same-build' });
    assert.equal(f.checkpoints.at(-1).startNumber, 2);
    assert.notEqual(f.checkpoints.at(-1).instanceId, firstId);
    second.visibility(false);
    second.visibility(true);
    assert.equal(f.checkpoints.at(-1).startNumber, 2);
});

test('下载诊断采集原始百分比和字节数，重复高频回调不会扩张记录', t => {
    const f = fixture(t, { diagnostics: true });
    for (let i = 0; i < 2000; i++) f.root.bbqBoot.downloadProgress({ progress: 1,
        totalBytesWritten: 100, totalBytesExpectedToWrite: 200 });
    f.root.bbqBoot.downloadProgress({ progress: 100, totalBytesWritten: 200, totalBytesExpectedToWrite: 200 });
    t.mock.timers.tick(30000);
    assert.equal(f.reports[0].downloads.length, 2);
    assert.equal(f.reports[0].downloads[0].written, 100);
    assert.equal(f.reports[0].downloads[0].progress, 1);
});

for (const platform of ['ios', 'android']) {
    test(`${platform} 原生等待提示仅用于安卓启动，首帧后恢复不再展示`, t => {
        const f = fixture(t, { androidNativeLoading: true }, {}, { platform });
        assert.equal(f.nativeLoading.length, platform === 'android' ? 1 : 0);
        f.root.bbqBoot.visibility(false);
        f.root.bbqBoot.visibility(true);
        f.root.bbqBoot.ready();
        f.root.bbqBoot.print('[BBQ first frame]');
        if (platform === 'android') assert.deepEqual(f.nativeLoading,
            ['正在准备开摊', 'hide', '正在准备开摊', 'hide']);
        const count = f.nativeLoading.length;
        f.root.bbqBoot.visibility(false);
        f.root.bbqBoot.visibility(true);
        assert.equal(f.nativeLoading.length, count);
    });
}

test('启动失败关闭安卓等待提示，重复恢复不重启诊断或遮挡错误提示', t => {
    const f = fixture(t, { androidNativeLoading: true, diagnostics: true }, {}, { platform: 'android' });
    f.handlers.error({ message: 'cannot start' });
    f.root.bbqBoot.visibility(false);
    f.root.bbqBoot.visibility(true);
    assert.deepEqual(f.nativeLoading, ['正在准备开摊', 'hide']);
    assert.deepEqual(f.handlers, {});
    assert.equal(f.dialogs.length, 1);
});
