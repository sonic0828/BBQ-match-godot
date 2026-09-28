// Apply the experiment before either the loader or Godot creates a GL context.
module.exports = function configureRenderProbe(wx, root, options) {
    const platform = wx.getDeviceInfo().platform;
    const requested = options.androidRenderProbe || null;
    // Keep the phone-verified Android workaround in ordinary exports as well.
    const effective = platform === 'android' || platform === 'devtools' ? requested || 'B' : null;
    const iosProfile = platform === 'ios' ? options.iosStartupProfile || 'baseline' : null;
    if (effective === 'C') root.__GODOT_DISABLE_WXGLX = true;
    return {
        requested, effective, iosProfile,
        skipLoaderRendering: effective === 'B',
        lightLoader: iosProfile === 'loader' || iosProfile === 'combined',
        skipWasmRead: iosProfile === 'wasm' || iosProfile === 'combined',
    };
};
