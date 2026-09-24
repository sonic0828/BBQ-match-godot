// Keep startup failures visible on phones where no debugger is attached.
module.exports = function installBootDiagnostics(wxApi, root) {
    let finished = false;
    let reported = false;
    let phase = '加载引擎分包';
    const device = wxApi.getDeviceInfo();
    const app = wxApi.getAppBaseInfo();
    const environment = `${device.platform} / 微信 ${app.version} / 基础库 ${app.SDKVersion}`;
    const mode = root.isIOSHighPerformanceMode ? '高性能模式' : '普通模式';

    console.log('[BBQ startup]', environment, mode);

    function fail(error) {
        if (finished || reported) return;
        reported = true;
        const detail = String(error && (error.stack || error.message || error.errMsg) || error);
        console.error('[BBQ startup failed]', phase, environment, mode, detail);
        wxApi.showModal({
            title: '游戏启动失败',
            content: `${phase}\n${environment}\n${mode}\n${detail.slice(0, 800)}`,
            showCancel: false,
            confirmText: '知道了',
        });
    }

    const onRejection = event => fail(event.reason);
    wxApi.onError(fail);
    wxApi.onUnhandledRejection(onRejection);

    return {
        fail,
        stage(value) {
            phase = value;
            console.log('[BBQ startup]', phase);
        },
        ready() {
            finished = true;
            wxApi.offError(fail);
            wxApi.offUnhandledRejection(onRejection);
            console.log('[BBQ startup] ready');
        },
    };
};
