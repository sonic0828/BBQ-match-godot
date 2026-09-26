// Called by Godot's JavaScriptBridge; the Web navigator has no vibration API here.
module.exports = function installHaptics(wx) {
    let hidden = false;
    let warned = false;
    const reportFailure = error => {
        if (!warned) console.warn('[BBQ haptics] 短震动不可用', error);
        warned = true;
    };
    wx.onHide(() => { hidden = true; });
    wx.onShow(() => { hidden = false; });
    return {
        pulse() {
            if (hidden || typeof wx.vibrateShort !== 'function') return false;
            try {
                wx.vibrateShort({ type: 'light', fail: reportFailure });
                return true;
            } catch (error) {
                reportFailure(error);
                return false;
            }
        },
    };
};
