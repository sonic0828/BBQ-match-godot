// Native ads own their UI; never draw or resize Godot's canvas here.
const IDS = {
    banner: 'adunit-233a4ca2226318cb',
    interstitial: 'adunit-2755fcb37576135b',
    rewarded: 'adunit-fa265b1ae6f2c262',
};
const RECEIPT_KEY = 'bbq.ads.bag-receipt';
const COOLDOWN_KEY = 'bbq.ads.last-close';
// 20:7 full-image card. The host may clamp/ignore width: onResize wins.
const CARD_WIDTH = 300;

module.exports = function installAds(wx, now = Date.now) {
    let listener, disposed = false, foreground = true, active = null;
    let lastClose = 0, receipt = '', serial = 0;
    const slots = {};
    let banner = null, bannerShowing = false, bannerPending = false;
    let bannerDismissed = false, bannerFailed = false, bannerContext = null, bannerWanted = null;
    let cardWidth = CARD_WIDTH, cardHeight = CARD_WIDTH * 7 / 20;
    const emit = data => { if (listener && !disposed) listener(JSON.stringify(data)); };
    const warn = (kind, error) => console.warn('[BBQ ad]', kind, error && (error.errCode || error.message || error.errMsg) || error);
    function read(key, fallback) {
        try { return wx.getStorageSync(key) || fallback; } catch (_) { return fallback; }
    }
    function write(key, value) {
        try { wx.setStorageSync(key, value); return true; } catch (error) { warn('storage', error); return false; }
    }
    function metrics() {
        const info = wx.getWindowInfo ? wx.getWindowInfo() : wx.getSystemInfoSync();
        const bottom = info.safeArea ? Math.max(0, (info.screenHeight || info.windowHeight) - info.safeArea.bottom) : 0;
        return { windowWidth: info.windowWidth, windowHeight: info.windowHeight, safeBottom: bottom,
            bannerWidth: cardWidth, bannerHeight: cardHeight };
    }
    function reportSize() { emit({ type: 'layout', ...metrics() }); }
    function hideBanner() {
        if (!banner) return;
        const ad = banner;
        const failed = error => {
            warn('banner hide', error);
            // Never leave native UI over a modal when a template cannot hide.
            if (banner === ad) {
                banner = null; bannerShowing = bannerPending = false;
                ad.destroy();
            }
        };
        bannerShowing = false;
        try { Promise.resolve(ad.hide()).catch(failed); }
        catch (error) { failed(error); }
    }
    function syncBanner() {
        const box = bannerWanted;
        if (!box || !box.visible || !foreground || active || bannerDismissed || disposed) { hideBanner(); return; }
        if (!banner && !bannerFailed && typeof wx.createCustomAd === 'function') {
            try {
                const ad = wx.createCustomAd({ adUnitId: IDS.banner, adIntervals: 60,
                    style: { left: box.left, top: box.top, width: CARD_WIDTH } });
                banner = ad;
                ad.onLoad(() => { if (banner === ad) syncBanner(); });
                ad.onError(error => { if (banner !== ad) return; warn('banner', error); bannerFailed = true; hideBanner(); });
                if (ad.onClose) ad.onClose(() => { if (banner === ad) { bannerDismissed = true; hideBanner(); } });
                if (ad.onResize) ad.onResize(size => {
                    if (banner !== ad || !(size.width > 0 && size.height > 0)) return;
                    if (cardWidth === size.width && cardHeight === size.height) return;
                    cardWidth = size.width; cardHeight = size.height;
                    // Wait for Godot to reserve the returned dimensions before showing.
                    hideBanner(); reportSize();
                });
            } catch (error) { bannerFailed = true; warn('banner create', error); }
        }
        // CustomAd has no load(): show owns preparation; don't wait for an
        // onLoad event that a host may emit only after the first show request.
        if (!banner || bannerFailed) return;
        const info = metrics();
        // Preserve the entire card, including its close control and attribution.
        if (box.width + 1 < cardWidth || box.height + 1 < cardHeight || cardWidth > info.windowWidth
            || box.top < 0 || box.top + cardHeight > info.windowHeight - info.safeBottom + 1) { hideBanner(); return; }
        banner.style.left = (info.windowWidth - cardWidth) / 2;
        banner.style.top = box.top;
        if (bannerShowing || bannerPending) return;
        const ad = banner;
        bannerPending = true;
        try {
            Promise.resolve(ad.show()).then(() => {
                if (banner !== ad) return;
                bannerPending = false; bannerShowing = true;
                syncBanner();
            }, error => { if (banner === ad) { bannerPending = false; bannerFailed = true; warn('banner show', error); } });
        } catch (error) { bannerPending = false; bannerFailed = true; warn('banner show', error); }
    }
    function finish(request, status, reward = '') {
        if (active !== request) return;
        clearTimeout(request.timer);
        active = null;
        emit({ type: 'result', kind: request.kind, id: request.id, status, receipt: reward });
        // Godot restores the right page/modal before asking to show the banner.
    }
    function destroySlot(kind) {
        const slot = slots[kind];
        if (!slot) return;
        delete slots[kind];
        for (const event of ['Load', 'Close', 'Error']) {
            if (slot.ad['off' + event]) slot.ad['off' + event](slot[event]);
        }
        try { slot.ad.destroy(); } catch (error) { warn('destroy', error); }
    }
    function prepare(kind) {
        if (disposed || slots[kind]) return slots[kind];
        const create = kind === 'interstitial' ? wx.createInterstitialAd : wx.createRewardedVideoAd;
        if (typeof create !== 'function') return null;
        try {
            const ad = create.call(wx, { adUnitId: IDS[kind] });
            const slot = { ad, ready: false };
            slots[kind] = slot;
            slot.Load = () => { if (slots[kind] === slot) slot.ready = true; };
            slot.Error = error => {
                if (slots[kind] !== slot) return;
                slot.ready = false; warn(kind, error);
                // Before show settles, its rejection owns the one retry.
                if (active && active.slot === slot && active.shown) finish(active, 'failed');
            };
            slot.Close = result => {
                const request = active;
                if (!request || request.slot !== slot) return;
                lastClose = now(); write(COOLDOWN_KEY, lastClose);
                slot.ready = false;
                if (kind === 'rewarded' && result && result.isEnded === true) {
                    receipt = `${now()}:${++serial}:${Math.random().toString(36).slice(2)}`;
                    // Acknowledge only after SaveStore commits inventory + receipt together.
                    write(RECEIPT_KEY, receipt);
                    finish(request, 'completed', receipt);
                } else finish(request, kind === 'interstitial' ? 'closed' : 'cancelled');
                preload(slot);
            };
            ad.onLoad(slot.Load); ad.onError(slot.Error); ad.onClose(slot.Close);
            preload(slot);
            return slot;
        } catch (error) { warn(kind + ' create', error); return null; }
    }
    function preload(slot) {
        if (!slot || !slot.ad.load || slot.loading) return;
        slot.loading = true;
        try { Promise.resolve(slot.ad.load()).then(() => { slot.loading = false; slot.ready = true; }, error => {
            slot.loading = false; warn('preload', error);
        }); }
        catch (error) { slot.loading = false; warn('preload', error); }
    }
    function show(kind, id) {
        if (disposed) return;
        if (active) { emit({ type: 'result', kind, id, status: 'busy' }); return; }
        if (kind === 'rewarded' && receipt) { emit({ type: 'result', kind, id, status: 'completed', receipt }); return; }
        const slot = prepare(kind);
        const blocked = kind === 'interstitial' && (now() - lastClose < 120000 || !slot || !slot.ready);
        if (!foreground || !slot || blocked) {
            // A no-fill at startup must not disable later milestones. Retry
            // in the background, but never show late over the next level.
            if (foreground && slot && !slot.ready) preload(slot);
            emit({ type: 'result', kind, id, status: 'unavailable' }); return;
        }
        const request = { kind, id, slot, shown: false, timer: null };
        active = request; hideBanner();
        // Bound preparation, not viewing time. Destroy a timed-out instance so
        // a late load cannot place an ad over the next level.
        request.timer = setTimeout(() => {
            if (active !== request || request.shown) return;
            destroySlot(kind); finish(request, 'failed');
        }, kind === 'interstitial' ? 3000 : 8000);
        async function attempt() {
            try {
                try { await slot.ad.show(); }
                catch (error) {
                    if (kind !== 'rewarded' || active !== request || !foreground) throw error;
                    await slot.ad.load();
                    if (active !== request || !foreground) { finish(request, 'failed'); return; }
                    await slot.ad.show();
                }
                if (active === request) { request.shown = true; clearTimeout(request.timer); }
            } catch (error) { warn(kind + ' show', error); finish(request, 'failed'); }
        }
        attempt();
    }
    function resize() { if (!disposed && listener) { hideBanner(); reportSize(); } }
    return {
        initialize(callback) {
            if (listener || disposed) return;
            listener = callback;
            const saved = read(RECEIPT_KEY, '');
            receipt = typeof saved === 'string' ? saved : '';
            lastClose = Math.min(now(), Number(read(COOLDOWN_KEY, 0)) || 0);
            reportSize();
            if (receipt) emit({ type: 'pending_reward', receipt });
            prepare('interstitial');
            if (wx.onWindowResize) wx.onWindowResize(resize);
        },
        prepareReward() { prepare('rewarded'); },
        showInterstitial(id) { show('interstitial', id); },
        showRewarded(id) { show('rewarded', id); },
        acknowledgeReward(id) {
            if (receipt !== id) return;
            if (write(RECEIPT_KEY, '')) receipt = '';
        },
        setBanner(value) {
            bannerWanted = JSON.parse(value);
            if (bannerContext !== bannerWanted.context) {
                bannerContext = bannerWanted.context; bannerDismissed = false;
                if (bannerFailed && banner) { banner.destroy(); banner = null; bannerPending = bannerShowing = false; }
                bannerFailed = false;
            }
            syncBanner();
        },
        visibility(value) { foreground = value; syncBanner(); },
        dispose() {
            disposed = true; listener = null;
            if (active) clearTimeout(active.timer);
            active = null;
            destroySlot('interstitial'); destroySlot('rewarded');
            if (banner) { const ad = banner; hideBanner(); ad.destroy(); banner = null; }
            if (wx.offWindowResize) wx.offWindowResize(resize);
        },
    };
};
