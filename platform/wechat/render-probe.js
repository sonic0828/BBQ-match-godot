// Apply the phone-verified defaults before any GL context is created.
module.exports = function configureRenderProbe(wx, root, options) {
    const platform = wx.getDeviceInfo().platform;
    const requested = options.androidRenderProbe || null;
    // Keep the phone-verified Android workaround in ordinary exports as well.
    const effective = platform === 'android' || platform === 'devtools' ? requested || 'D' : null;
    const iosProfile = platform === 'ios' ? options.iosStartupProfile || 'loader' : null;
    if (effective === 'C' || effective === 'D') root.__GODOT_DISABLE_WXGLX = true;
    return {
        requested, effective, iosProfile,
        skipLoaderRendering: effective === 'B' || effective === 'D',
        lightLoader: iosProfile === 'loader' || iosProfile === 'combined',
        skipWasmRead: iosProfile === 'wasm' || iosProfile === 'combined',
    };
};
