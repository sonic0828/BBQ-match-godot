// Keep startup failures visible on phones where no debugger is attached.
module.exports = function installBootDiagnostics(wxApi, root, options = {}) {
    let finished = false;
    let reported = false;
    let phase = '加载引擎分包';
    let engineStarted = false;
    let scene = '';
    let firstFrame = false;
    const errors = [];
    const device = wxApi.getDeviceInfo();
    const app = wxApi.getAppBaseInfo();
    const environment = `${device.platform} / 微信 ${app.version} / 基础库 ${app.SDKVersion}`;
    const mode = root.isIOSHighPerformanceMode ? '高性能模式' : '普通模式';

    console.log('[BBQ startup]', options.build, environment, mode);
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
        wxApi.showModal({
            title,
            content: `${options.build || ''}\n${environment}\n${mode}\n${phase}\n引擎 ${engineStarted ? '已启动' : '未确认'} / 场景 ${scene || '未确认'} / 首帧 ${firstFrame ? '已绘制' : '未确认'}${rendering}\n${detail}\n${errors.join('\n').slice(-1000)}`,
            showCancel: false,
            confirmText: '知道了',
        });
        dispose();
    }

    function fail(error) {
        if (finished || reported) return;
        const detail = String(error && (error.stack || error.message || error.errMsg) || error);
        console.error('[BBQ startup failed]', phase, environment, mode, detail);
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
            console.error(...args);
            if (finished) return;
            errors.push(args.join(' '));
            if (errors.length > 12) errors.shift();
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
