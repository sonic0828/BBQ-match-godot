// Bounded startup evidence; a slow launch is not a fatal error.
module.exports = function installBootDiagnostics(wxApi, root, options = {}) {
    let finished = false;
    let reported = false;
    let phase = '加载引擎分包';
    let engineStarted = false;
    let scene = '';
    let firstFrame = false;
    let firstFrameElapsedMs = null;
    let observing = false;
    let engine;
    let errorCount = 0;
    const startedAt = Date.now();
    const errors = [];
    const errorStats = new Map();
    const runtime = {};
    const loaderRecords = new WeakMap();
    const loaders = [];
    let loaderInstances = 0;
    const watchedCanvases = new Set();
    const contextEvents = [];
    const marks = [];
    const frameSamples = [];
    const memoryWarnings = [];
    let foreground = true;
    let status = 'starting';
    const storageKey = 'bbq.startup.last';
    const device = wxApi.getDeviceInfo();
    const app = wxApi.getAppBaseInfo();
    const environment = `${device.platform} / 微信 ${app.version} / 基础库 ${app.SDKVersion}`;
    const mode = () => device.platform !== 'ios' ? `${device.platform}（iOS 高性能标志不适用）`
        : root.isIOSHighPerformanceModePlus ? '高性能 Plus 模式'
        : root.isIOSHighPerformanceMode ? '高性能模式' : '普通模式';

    console.log('[BBQ startup]', options.build, environment, mode());
    if (options.diagnostics) console.log('[BBQ render probe]', JSON.stringify(root.bbqRenderProbe || {}));
    if (options.diagnostics && wxApi.getStorageSync) {
        try {
            const previous = wxApi.getStorageSync(storageKey);
            if (previous) console.log('[BBQ previous startup]', JSON.stringify(previous));
        } catch (error) { console.warn('[BBQ startup storage]', String(error)); }
    }
    mark('boot');
    let timer = setTimeout(() => {
        mark('slow-start');
        report('启动较慢', '30 秒内未确认游戏首帧，继续等待', false);
    }, 30000);

    function heapBytes() {
        return engine && engine.rtenv && engine.rtenv.HEAPU8
            ? engine.rtenv.HEAPU8.buffer.byteLength : null;
    }

    function checkpoint(lastEvent) {
        if (!options.diagnostics || !wxApi.setStorageSync) return;
        try {
            wxApi.setStorageSync(storageKey, {
                build: options.build, recordedAt: Date.now(), elapsedMs: Date.now() - startedAt,
                status, phase, lastEvent, foreground, firstFrame, firstFrameElapsedMs,
                wasmMemoryBytes: heapBytes(), errorCount,
                // This is the last observed state, never a diagnosis of a crash.
                lastError: errors.length ? errors[errors.length - 1].line.slice(0, 500) : null,
            });
        } catch (error) { console.warn('[BBQ startup storage]', String(error)); }
    }

    function mark(name, detail) {
        if (finished || marks.length >= 64) return;
        const item = { name, elapsedMs: Date.now() - startedAt, wasmMemoryBytes: heapBytes() };
        if (detail !== undefined) item.detail = detail;
        marks.push(item);
        if (options.diagnostics) console.log('[BBQ startup mark]', JSON.stringify(item));
        checkpoint(name);
    }

    function onMemoryWarning(event) {
        if (finished || memoryWarnings.length >= 12) return;
        memoryWarnings.push({ elapsedMs: Date.now() - startedAt, level: event && event.level });
        mark('memory-warning');
    }

    function dispose() {
        finished = true;
        clearTimeout(timer);
        wxApi.offError(fail);
        wxApi.offUnhandledRejection(onRejection);
        if (options.diagnostics && wxApi.offMemoryWarning) wxApi.offMemoryWarning(onMemoryWarning);
        for (const canvas of watchedCanvases) {
            canvas.removeEventListener('webglcontextlost', onContextEvent);
            canvas.removeEventListener('webglcontextrestored', onContextEvent);
        }
        watchedCanvases.clear();
    }

    function onContextEvent(event) {
        if (contextEvents.length < 12) contextEvents.push({
            type: event.type, elapsedMs: Date.now() - startedAt,
        });
        mark(event.type);
    }

    function recordError(line) {
        const elapsedMs = Date.now() - startedAt;
        errorCount++;
        if (errors.length < 12) errors.push({ elapsedMs, line });
        const previous = errorStats.get(line);
        if (previous) previous.count++;
        else if (errorStats.size < 64) {
            errorStats.set(line, { line, count: 1, elapsedMs });
            return true;
        }
        return false;
    }

    function report(title, detail, terminal = true) {
        if (finished || reported) return;
        if (terminal) {
            reported = true;
            clearTimeout(timer);
        }
        try {
            runtime.wasmMemoryBytes = engine && engine.rtenv && engine.rtenv.HEAPU8
                ? engine.rtenv.HEAPU8.buffer.byteLength : null;
        } catch (error) {
            runtime.memoryError = String(error);
        }
        let rendering = '';
        const loader = root.godotLoader;
        const renderPath = typeof root.__godotMinigameWXGLXEnabled !== 'boolean' ? '未确认'
            : root.__godotMinigameWXGLXEnabled ? 'WXGLX' : 'WebGL2';
        const canvas = loader && loader.onScreenCanvas;
        if (canvas) rendering = `\n${renderPath} / 画布 ${canvas.width}×${canvas.height}`;
        if (loader && loader.gl) {
            const gl = loader.gl;
            rendering += `\n缓冲 ${gl.drawingBufferWidth}×${gl.drawingBufferHeight}`;
            // Inspect only; never clear, resize or redraw the engine's canvas.
            try {
                rendering += ` / 丢失 ${gl.isContextLost()} / GL ${gl.getError()}`;
            } catch (error) {
                rendering += ` / 状态不可读 ${error.message}`;
            }
        }
        const diagnostic = {
            build: options.build, environment, mode: mode(), phase,
            device: { platform: device.platform, brand: device.brand, model: device.model, system: device.system },
            probe: root.bbqRenderProbe || null, renderPath,
            highPerformance: root.isIOSHighPerformanceMode ?? null,
            highPerformancePlus: root.isIOSHighPerformanceModePlus ?? null,
            elapsedMs: Date.now() - startedAt, engineStarted, scene, firstFrame,
            firstFrameElapsedMs, observationMs: observing ? 120000 : 0,
            marks, frameSamples, memoryWarnings, status, foreground,
            loaderInstances, loaders, contextEvents,
            rendering, runtime, errorCount, firstErrors: errors,
            errorStats: Array.from(errorStats.values()), detail,
        };
        const fullReport = JSON.stringify(diagnostic, null, 2);
        // Re-emit the first failures after the engine's error flood, as one entry.
        console.log('[BBQ startup report]', fullReport);
        if (terminal) dispose();
    }

    function fail(error) {
        if (finished || reported) return;
        const detail = String(error && (error.stack || error.message || error.errMsg) || error).slice(0, 2000);
        const fresh = recordError(detail);
        if (options.diagnostics && observing) {
            if (fresh) {
                console.error('[BBQ runtime error]', detail);
                checkpoint('runtime-error');
            }
            return;
        }
        console.error('[BBQ startup failed]', phase, environment, mode(), detail);
        status = 'failed';
        mark('failed');
        const loader = root.godotLoader;
        if (loader && loader.setStage) loader.setStage('暂时无法开摊，请退出后重试');
        report('游戏启动失败', detail.slice(0, 800));
        wxApi.showModal({ title: '暂时无法开摊', content: '请退出小游戏后重新打开。',
            showCancel: false, confirmText: '知道了' });
    }

    const onRejection = event => fail(event.reason);
    wxApi.onError(fail);
    wxApi.onUnhandledRejection(onRejection);
    if (options.diagnostics && wxApi.onMemoryWarning) wxApi.onMemoryWarning(onMemoryWarning);

    function checkReady() {
        if (finished || observing || !engineStarted || !firstFrame) return;
        phase = '已收到游戏首帧信号';
        status = 'first-frame';
        mark('home:first-frame');
        clearTimeout(timer);
        if (options.diagnostics) {
            observing = true;
            console.log('[BBQ render observation]', '首帧后继续观察 120 秒；仅输出日志，不弹窗');
            timer = setTimeout(() => {
                status = 'observed';
                mark('observation:complete');
                report('渲染交接诊断', '首帧后 120 秒观察结束');
            }, 120000);
        } else {
            report('启动完成', '已收到游戏首帧');
        }
    }

    return {
        diagnostics: !!options.diagnostics,
        mark,
        fail,
        visibility(value) {
            foreground = value;
            if (!finished) checkpoint(value ? 'show' : 'hide');
        },
        loaderEvent(loader, event) {
            if (!options.diagnostics || finished) return;
            const elapsedMs = Date.now() - startedAt;
            if (event === 'created') {
                loaderInstances++;
                if (loaders.length >= 8) return;
                const record = { id: loaderInstances, createdElapsedMs: elapsedMs,
                    skipRendering: !!loader.config.skipRendering, draws: 0,
                    drawsAfterCleanup: 0, drawsAfterFirstFrame: 0,
                    renderCallsAfterCleanup: 0, cleanupElapsedMs: null, lastDrawElapsedMs: null };
                loaderRecords.set(loader, record);
                loaders.push(record);
                const canvas = loader.onScreenCanvas;
                if (canvas && typeof canvas.addEventListener === 'function' && !watchedCanvases.has(canvas)) {
                    watchedCanvases.add(canvas);
                    canvas.addEventListener('webglcontextlost', onContextEvent);
                    canvas.addEventListener('webglcontextrestored', onContextEvent);
                }
            }
            const record = loaderRecords.get(loader);
            if (!record) return;
            if (event === 'cleanup') {
                record.cleanupElapsedMs = elapsedMs;
                mark('loader:cleanup');
                console.log('[BBQ loader cleanup]', JSON.stringify(record));
            }
            if (event === 'render' && loader.disposed) record.renderCallsAfterCleanup++;
            if (event === 'draw') {
                record.draws++;
                record.lastDrawElapsedMs = elapsedMs;
                record.lastText = loader.currentText;
                if (loader.disposed) record.drawsAfterCleanup++;
                if (firstFrame) record.drawsAfterFirstFrame++;
            }
        },
        inspectRuntime(value) {
            engine = value;
            if (!options.diagnostics) return;
            try {
                const file = engine.preloader.preloadedFiles.find(item => item.path === '/engine/bbq.bin');
                if (!file || !options.pack) return;
                const bytes = ArrayBuffer.isView(file.buffer)
                    ? new Uint8Array(file.buffer.buffer, file.buffer.byteOffset, file.buffer.byteLength)
                    : new Uint8Array(file.buffer);
                // Do not synchronously hash the entire pack on the startup path.
                // Exact build identity is recorded by the exporter, size is runtime evidence only.
                runtime.pack = { bytes: bytes.byteLength, expected: options.pack,
                    sizeMatches: bytes.byteLength === options.pack.bytes };
            } catch (error) {
                runtime.inspectError = String(error);
            }
        },
        print(...args) {
            console.log(...args);
            const line = args.join(' ');
            if (line.startsWith('[BBQ scene ready]')) {
                scene = line.slice('[BBQ scene ready]'.length).trim();
                mark('scene:ready');
            }
            if (options.diagnostics && !finished && line.startsWith('[BBQ frame sample] ') && frameSamples.length < 12) {
                try {
                    frameSamples.push({ elapsedMs: Date.now() - startedAt,
                        ...JSON.parse(line.slice('[BBQ frame sample] '.length)) });
                    checkpoint('frame-sample');
                } catch (error) { console.warn('[BBQ frame sample parse]', String(error)); }
            }
            if (line.startsWith('[BBQ first frame]')) {
                if (!firstFrame) firstFrameElapsedMs = Date.now() - startedAt;
                firstFrame = true;
                checkReady();
            }
        },
        printError(...args) {
            if (finished) { console.error(...args); return; }
            const line = args.join(' ').slice(0, 2000);
            const fresh = recordError(line);
            // Keep normal builds unchanged; diagnostic builds aggregate repeated lines.
            if (!options.diagnostics || fresh) console.error(...args);
        },
        stage(value) {
            if (finished) return;
            phase = value;
            mark(value);
            console.log('[BBQ startup]', phase);
        },
        ready() {
            if (finished || engineStarted) return;
            engineStarted = true;
            phase = '引擎已启动，等待游戏首帧';
            console.log('[BBQ startup] engine started');
            mark('engine-start:ready');
            checkReady();
        },
    };
};
