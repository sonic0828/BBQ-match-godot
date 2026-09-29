const assert = require('node:assert/strict');
const { test } = require('node:test');
const install = require('../platform/wechat/ads');
const flush = () => new Promise(resolve => setImmediate(resolve));

function fixture(t, storage = new Map()) {
    t.mock.method(console, 'warn', () => {});
    const events = [], instances = {}, handlers = {};
    let time = 1_000_000;
    class Ad {
        constructor(options) {
            this.options = options; this.style = { ...options.style }; this.events = {};
            this.shows = 0; this.hides = 0; this.loads = 0; this.destroyed = false;
            for (const name of ['Load', 'Close', 'Error', 'Resize']) {
                this['on' + name] = fn => { this.events[name] = fn; };
                this['off' + name] = () => { delete this.events[name]; };
            }
        }
        show() { this.shows++; return this.showResult ? this.showResult() : Promise.resolve(); }
        hide() { this.hides++; return this.hideResult ? this.hideResult() : Promise.resolve(); }
        load() { this.loads++; return this.loadResult ? this.loadResult() : Promise.resolve(); }
        destroy() { this.destroyed = true; }
        emit(name, value) { this.events[name]?.(value); }
    }
    const wx = {
        getWindowInfo: () => ({ windowWidth: 390, windowHeight: 844, screenHeight: 844, safeArea: { bottom: 810 } }),
        getStorageSync: key => storage.get(key),
        setStorageSync: (key, value) => storage.set(key, value),
        onWindowResize: fn => { handlers.resize = fn; },
        offWindowResize: () => { delete handlers.resize; },
    };
    for (const [kind, method] of Object.entries({ banner: 'createCustomAd', interstitial: 'createInterstitialAd', rewarded: 'createRewardedVideoAd' })) {
        wx[method] = options => { const ad = new Ad(options); (instances[kind] ??= []).push(ad); return ad; };
    }
    const bridge = install(wx, () => time);
    t.after(() => bridge.dispose());
    const initialize = () => bridge.initialize(value => events.push(JSON.parse(value)));
    const banner = (overrides = {}) => bridge.setBanner(JSON.stringify({ visible: true, context: 1, left: 45, top: 697, width: 300, height: 105, ...overrides }));
    return { wx, bridge, instances, events, storage, handlers, initialize, banner, advance: ms => { time += ms; } };
}

test('首帧初始化后预加载正确插屏，未就绪立即放行；关闭后 120 秒保护', async t => {
    const f = fixture(t);
    assert.deepEqual(f.instances, {});
    f.initialize();
    const ad = f.instances.interstitial[0];
    assert.equal(ad.options.adUnitId, 'adunit-2755fcb37576135b');
    assert.equal(f.instances.rewarded, undefined);
    f.bridge.showInterstitial(1);
    assert.equal(f.events.at(-1).status, 'unavailable');
    ad.emit('Load'); f.bridge.showInterstitial(2); await flush();
    ad.emit('Close'); ad.emit('Close');
    assert.equal(f.events.filter(e => e.id === 2).length, 1);
    assert.equal(f.events.at(-1).status, 'closed');
    assert.equal(ad.loads, 2);
    ad.emit('Load'); f.bridge.showInterstitial(3);
    assert.equal(f.events.at(-1).status, 'unavailable');
    f.advance(120000); f.bridge.showInterstitial(4); await flush(); ad.emit('Close');
    assert.equal(ad.shows, 2);
});

test('插屏 show 拒绝不重试，超时销毁后迟到的 Promise 不再继续或奖励', async t => {
    t.mock.timers.enable({ apis: ['setTimeout'] });
    const f = fixture(t); f.initialize(); const ad = f.instances.interstitial[0];
    ad.emit('Load'); ad.showResult = () => Promise.reject(new Error('frequency'));
    f.bridge.showInterstitial(1); await flush();
    assert.equal(f.events.at(-1).status, 'failed'); assert.equal(ad.loads, 1);
    let resolve;
    ad.showResult = () => new Promise(done => { resolve = done; });
    f.bridge.showInterstitial(2); t.mock.timers.tick(3000);
    assert.equal(ad.destroyed, true); assert.equal(f.events.at(-1).status, 'failed');
    resolve(); await flush(); ad.emit('Close');
    assert.equal(f.events.filter(e => e.id === 2).length, 1);
});

test('首次无填充的插屏会在后续机会重新预加载，当次跳过不迟到补播', async t => {
    const f = fixture(t); f.initialize(); await flush();
    const ad = f.instances.interstitial[0]; ad.emit('Error', { errCode: 1004 });
    let resolve;
    ad.loadResult = () => new Promise(done => { resolve = done; });
    f.bridge.showInterstitial(1); f.bridge.showInterstitial(2);
    assert.equal(ad.loads, 2); assert.equal(ad.shows, 0);
    assert.equal(f.events.at(-1).status, 'unavailable');
    resolve(); await flush(); assert.equal(ad.shows, 0);
    f.bridge.showInterstitial(3); await flush(); assert.equal(ad.shows, 1); ad.emit('Close');
});

test('激励失败只重试一次；完整观看才奖励，重入及重复关闭不会重复奖励', async t => {
    const f = fixture(t); f.initialize(); f.bridge.prepareReward(); const ad = f.instances.rewarded[0];
    assert.equal(ad.options.adUnitId, 'adunit-fa265b1ae6f2c262');
    ad.showResult = () => ad.shows === 1 ? Promise.reject(new Error('not loaded')) : Promise.resolve();
    f.bridge.showRewarded(1); f.bridge.showRewarded(2); await flush();
    assert.equal(f.events.at(-1).status, 'busy');
    assert.equal(ad.shows, 2); assert.equal(ad.loads, 2);
    ad.emit('Close', { isEnded: true }); ad.emit('Close', { isEnded: true });
    const result = f.events.at(-1);
    assert.equal(result.id, 1); assert.equal(result.status, 'completed'); assert.ok(result.receipt);
    assert.equal(f.events.filter(e => e.status === 'completed').length, 1);
    assert.equal(f.storage.get('bbq.ads.bag-receipt'), result.receipt);
    f.bridge.showRewarded(3); assert.equal(f.events.at(-1).receipt, result.receipt); assert.equal(ad.shows, 2);
    f.bridge.acknowledgeReward('wrong'); assert.equal(f.storage.get('bbq.ads.bag-receipt'), result.receipt);
    f.bridge.acknowledgeReward(result.receipt); assert.equal(f.storage.get('bbq.ads.bag-receipt'), '');
    f.instances.interstitial[0].emit('Load'); f.bridge.showInterstitial(4);
    assert.equal(f.events.at(-1).status, 'unavailable');
});

test('提前退出/旧版无 isEnded 不发奖；切后台取消加载重试，已显示视频不受准备超时影响', async t => {
    t.mock.timers.enable({ apis: ['setTimeout'] });
    const f = fixture(t); f.initialize(); f.bridge.prepareReward(); const ad = f.instances.rewarded[0];
    for (const result of [undefined, { isEnded: false }]) {
        f.bridge.showRewarded(1); await flush(); t.mock.timers.tick(30000); ad.emit('Close', result);
        assert.equal(f.events.at(-1).status, 'cancelled');
    }
    assert.equal(f.storage.has('bbq.ads.bag-receipt'), false);
    ad.showResult = () => Promise.reject(new Error('not loaded'));
    let resolve;
    ad.loadResult = () => new Promise(done => { resolve = done; });
    f.bridge.showRewarded(2); await flush(); f.bridge.visibility(false); resolve(); await flush();
    assert.equal(ad.shows, 3); assert.equal(f.events.at(-1).status, 'failed');
});

test('未确认奖励和全屏广告冷却可冷启动恢复；保存失败保留回执以便重领', async t => {
    const f = fixture(t); f.initialize(); f.bridge.prepareReward();
    f.bridge.showRewarded(1); await flush(); f.instances.rewarded[0].emit('Close', { isEnded: true });
    const receipt = f.events.at(-1).receipt;
    const restored = fixture(t, f.storage); restored.initialize();
    assert.equal(restored.events.at(-1).type, 'pending_reward');
    assert.equal(restored.events.at(-1).receipt, receipt);
    restored.instances.interstitial[0].emit('Load'); restored.bridge.showInterstitial(1);
    assert.equal(restored.events.at(-1).status, 'unavailable');
    restored.wx.setStorageSync = () => { throw new Error('disk'); };
    restored.bridge.acknowledgeReward(receipt); restored.bridge.showRewarded(2);
    assert.equal(restored.events.at(-1).receipt, receipt);
    assert.equal(restored.instances.rewarded, undefined);
});

test('20:7 横幅预留安全区，回传尺寸优先，弹层/后台/迟到 show 均隐藏', async t => {
    const f = fixture(t); f.initialize();
    assert.equal(f.events[0].bannerWidth, 300); assert.equal(f.events[0].bannerHeight, 105);
    f.banner(); const ad = f.instances.banner[0];
    assert.equal(ad.options.adUnitId, 'adunit-233a4ca2226318cb');
    assert.equal('height' in ad.options.style, false);
    await flush(); assert.equal(ad.shows, 1); assert.equal(ad.style.left, 45);
    // Initial show must not depend on onLoad; later load doesn't duplicate show.
    ad.emit('Load'); assert.equal(ad.shows, 1);
    ad.emit('Resize', { width: 300, height: 105 }); await flush(); assert.equal(ad.shows, 1);
    ad.emit('Resize', { width: 320, height: 112 });
    assert.equal(f.events.at(-1).bannerWidth, 320);
    f.banner(); await flush(); assert.equal(ad.shows, 1);
    f.banner({ width: 320, height: 112, top: 690 }); await flush();
    assert.equal(ad.shows, 2); assert.equal(ad.style.left, 35);
    f.banner({ top: 800 }); await flush(); assert.equal(ad.shows, 2);
    let resolve;
    ad.showResult = () => new Promise(done => { resolve = done; });
    f.banner({ width: 320, height: 112, top: 690 });
    f.banner({ visible: false }); const hides = ad.hides; resolve(); await flush(); assert.ok(ad.hides > hides);
    f.bridge.visibility(false); f.banner({ width: 320, height: 112, top: 690 }); assert.equal(ad.shows, 3);
    ad.showResult = null; f.bridge.visibility(true); await flush(); assert.equal(ad.shows, 4);
    ad.emit('Close'); f.banner(); assert.equal(ad.shows, 4);
    f.banner({ context: 2, width: 320, height: 112, top: 690 }); await flush(); assert.equal(ad.shows, 5);
});

test('缺失接口安全跳过；横幅不能 hide 时销毁并在恢复游戏时重建，无填充本局不重试', async t => {
    const f = fixture(t); delete f.wx.createInterstitialAd; delete f.wx.createRewardedVideoAd;
    f.initialize(); f.bridge.showInterstitial(1); f.bridge.showRewarded(2);
    assert.equal(f.events.filter(e => e.status === 'unavailable').length, 2);
    f.banner(); const ad = f.instances.banner[0]; ad.emit('Load'); await flush();
    ad.hideResult = () => Promise.reject(new Error('hide unsupported'));
    f.banner({ visible: false }); await flush(); assert.equal(ad.destroyed, true);
    f.banner(); assert.equal(f.instances.banner.length, 2);
    f.banner({ context: 2 }); assert.equal(f.instances.banner.length, 2);
    f.instances.banner[1].emit('Error', { errCode: 1004 }); f.banner({ context: 2 });
    assert.equal(f.instances.banner.length, 2);
    f.bridge.dispose(); assert.equal(f.handlers.resize, undefined);
});
