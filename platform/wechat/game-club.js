// Game-circle homepage OPENLINK supplied by the project owner.
const OPENLINK = '-SSEykJvFV3pORt5kTNpS9Q9sBVxFitD09h_5u161sDTw60TyvHZ5hOdvqxVdWokBu9dUiQ4JHcOPfdUGo4-lGORnIuGRsD_Msq8r6cD5pIuGJaiaV-9wJWpPKBbCiV4-bL6GioVtR57grNIeGA8p_v9h8r_cBeK1nSDfU3SxoVaFIHvynNDmzRoEbt7S1o4tavc5E_iduf8c4N5qIGQzSMk5GjW2WSNRw8gfkZIAYirGPVkm5ihsMUwyBI_e2RdA8qxzw9CDrR2Yqp13ezdVmrVY1sWf8cQqk0VU4orRAwVlhPD8DsdMGWLBW6GlLJKKq7Ko9FgHOYDPgkoalTiYQ';

module.exports = function installGameClub(wx) {
    let manager = null;
    let loaded = false;
    let opening = false;
    return {
        async open() {
            if (opening) return false;
            if (typeof wx.createPageManager !== 'function') {
                wx.showToast({ title: '请更新微信后打开游戏圈', icon: 'none' });
                return false;
            }
            opening = true;
            try {
                if (!manager) manager = wx.createPageManager();
                if (!loaded) {
                    await manager.load({ openlink: OPENLINK });
                    loaded = true;
                }
                await manager.show();
                return true;
            } catch (error) {
                console.warn('[BBQ game club] 打开失败', error);
                try { if (manager) manager.destroy(); } catch (_) { /* Already closed. */ }
                manager = null;
                loaded = false;
                wx.showToast({ title: '游戏圈暂时无法打开，请稍后再试', icon: 'none' });
                return false;
            } finally {
                opening = false;
            }
        },
    };
};
