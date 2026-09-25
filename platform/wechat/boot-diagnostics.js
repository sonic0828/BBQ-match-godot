// Keep startup failures visible on phones where no debugger is attached.
module.exports = function installBootDiagnostics(wxApi, root, options = {}) {
    let finished = false;
    let reported = false;
    let phase = '加载引擎分包';
    let engineStarted = false;
    let scene = '';
    let firstFrame = false;
    let engine;
    let errorCount = 0;
    const startedAt = Date.now();
    const errors = [];
    const errorStats = new Map();
    const runtime = {};
    const device = wxApi.getDeviceInfo();
    const app = wxApi.getAppBaseInfo();
    const environment = `${device.platform} / 微信 ${app.version} / 基础库 ${app.SDKVersion}`;
    const mode = () => root.isIOSHighPerformanceModePlus ? '高性能 Plus 模式'
        : root.isIOSHighPerformanceMode ? '高性能模式' : '普通模式';

    console.log('[BBQ startup]', options.build, environment, mode());
    let timer = setTimeout(() => report('启动状态诊断', '30 秒内未确认游戏首帧'), 30000);

    function dispose() {
        finished = true;
        clearTimeout(timer);
        wxApi.offError(fail);
        wxApi.offUnhandledRejection(onRejection);
    }

    function report(title, detail) {
        if (finished || reported) return;
        reported = true;
        clearTimeout(timer);
        try {
            runtime.wasmMemoryBytes = engine && engine.rtenv && engine.rtenv.HEAPU8
                ? engine.rtenv.HEAPU8.buffer.byteLength : null;
        } catch (error) {
            runtime.memoryError = String(error);
        }
        let rendering = '';
        const loader = root.godotLoader;
        if (loader && loader.gl) {
            const gl = loader.gl;
            const canvas = loader.onScreenCanvas;
            rendering = `\n${root.__godotMinigameWXGLXEnabled ? 'WXGLX' : 'WebGL2'} / 画布 ${canvas.width}×${canvas.height}`;
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
            highPerformance: root.isIOSHighPerformanceMode ?? null,
            highPerformancePlus: root.isIOSHighPerformanceModePlus ?? null,
            elapsedMs: Date.now() - startedAt, engineStarted, scene, firstFrame,
            rendering, runtime, errorCount, firstErrors: errors,
            errorStats: Array.from(errorStats.values()), detail,
        };
        const fullReport = JSON.stringify(diagnostic, null, 2);
        // Re-emit the first failures after the engine's error flood, as one entry.
        console.log('[BBQ startup report]', fullReport);
        const resource = runtime.pack ? `\n资源校验 ${runtime.pack.matches ? '一致' : '不一致'}` : '';
        const memory = runtime.wasmMemoryBytes == null ? ''
            : `\nWASM 内存 ${(runtime.wasmMemoryBytes / 1024 / 1024).toFixed(1)} MiB`;
        wxApi.showModal({
            title,
            content: `${options.build || ''}\n${environment}\n${mode()}\n${phase}\n引擎 ${engineStarted ? '已启动' : '未确认'} / 场景 ${scene || '未确认'} / 首帧 ${firstFrame ? '已绘制' : '未确认'}${rendering}${resource}${memory}\n${detail}\n错误 ${errorCount} 条；首次：${errors.length ? errors[0].line.slice(0, 400) : '无'}`,
            // Clipboard access requires a separate WeChat privacy declaration.
            // Keep the complete report in vConsole without requesting that access.
            showCancel: false,
            confirmText: '知道了',
        });
        dispose();
    }

    function fail(error) {
        if (finished || reported) return;
        const detail = String(error && (error.stack || error.message || error.errMsg) || error);
        console.error('[BBQ startup failed]', phase, environment, mode(), detail);
        report('游戏启动失败', detail.slice(0, 800));
    }

    const onRejection = event => fail(event.reason);
    wxApi.onError(fail);
    wxApi.onUnhandledRejection(onRejection);

    function checkReady() {
        if (finished || !engineStarted || !firstFrame) return;
        phase = '已收到游戏首帧信号';
        clearTimeout(timer);
        if (options.diagnostics) {
            timer = setTimeout(() => report('启动状态诊断', '已记录首帧；请确认关闭弹窗后是否显示游戏'), 3000);
        } else {
            dispose();
        }
    }

    return {
        fail,
        inspectRuntime(value) {
            engine = value;
            if (!options.diagnostics) return;
            try {
                const file = engine.preloader.preloadedFiles.find(item => item.path === '/engine/bbq.bin');
                if (!file || !options.pack) return;
                const bytes = ArrayBuffer.isView(file.buffer)
                    ? new Uint8Array(file.buffer.buffer, file.buffer.byteOffset, file.buffer.byteLength)
                    : new Uint8Array(file.buffer);
                // CRC32 checks the bytes already loaded by Godot, without another read/copy.
                let crc = 0xffffffff;
                for (const byte of bytes) {
                    crc ^= byte;
                    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
                }
                const crc32 = ((crc ^ 0xffffffff) >>> 0).toString(16).padStart(8, '0');
                runtime.pack = { bytes: bytes.byteLength, crc32, expected: options.pack,
                    matches: bytes.byteLength === options.pack.bytes && crc32 === options.pack.crc32 };
            } catch (error) {
                runtime.inspectError = String(error);
            }
        },
        print(...args) {
            console.log(...args);
            const line = args.join(' ');
            if (line.startsWith('[BBQ scene ready]')) scene = line.slice('[BBQ scene ready]'.length).trim();
            if (line.startsWith('[BBQ first frame]')) {
                firstFrame = true;
                checkReady();
            }
        },
        printError(...args) {
            if (finished) { console.error(...args); return; }
            const line = args.join(' ').slice(0, 2000);
            const elapsedMs = Date.now() - startedAt;
            errorCount++;
            if (errors.length < 12) errors.push({ elapsedMs, line });
            const previous = errorStats.get(line);
            if (previous) previous.count++;
            else if (errorStats.size < 64) errorStats.set(line, { line, count: 1, elapsedMs });
            // Keep normal builds unchanged; diagnostic builds aggregate repeated lines.
            if (!options.diagnostics || !previous) console.error(...args);
        },
        stage(value) {
            phase = value;
            console.log('[BBQ startup]', phase);
        },
        ready() {
            engineStarted = true;
            phase = '引擎已启动，等待游戏首帧';
            console.log('[BBQ startup] engine started');
            checkReady();
        },
    };
};
