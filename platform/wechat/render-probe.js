// Apply the experiment before either the loader or Godot creates a GL context.
module.exports = function configureRenderProbe(wx, root, options) {
    const platform = wx.getDeviceInfo().platform;
    const requested = options.androidRenderProbe || null;
    const effective = platform === 'android' || platform === 'devtools' ? requested : null;
    if (effective === 'C') root.__GODOT_DISABLE_WXGLX = true;
    return { requested, effective, skipLoaderRendering: effective === 'B' };
};
