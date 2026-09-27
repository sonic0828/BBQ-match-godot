const assert = require('node:assert/strict');
const { test } = require('node:test');
const installGameClub = require('../platform/wechat/game-club');

const expectedOpenlink = '-SSEykJvFV3pORt5kTNpS9Q9sBVxFitD09h_5u161sDTw60TyvHZ5hOdvqxVdWokBu9dUiQ4JHcOPfdUGo4-lGORnIuGRsD_Msq8r6cD5pIuGJaiaV-9wJWpPKBbCiV4-bL6GioVtR57grNIeGA8p_v9h8r_cBeK1nSDfU3SxoVaFIHvynNDmzRoEbt7S1o4tavc5E_iduf8c4N5qIGQzSMk5GjW2WSNRw8gfkZIAYirGPVkm5ihsMUwyBI_e2RdA8qxzw9CDrR2Yqp13ezdVmrVY1sWf8cQqk0VU4orRAwVlhPD8DsdMGWLBW6GlLJKKq7Ko9FgHOYDPgkoalTiYQ';

test('首次点击才加载用户提供的 OPENLINK，重复点击合并，返回后复用页面', async () => {
    let creates = 0, loads = 0, shows = 0, finishLoad;
    const bridge = installGameClub({
        createPageManager() {
            creates++;
            return {
                load(options) {
                    loads++;
                    assert.equal(options.openlink, expectedOpenlink);
                    return new Promise(resolve => { finishLoad = resolve; });
                },
                async show() { shows++; },
            };
        },
        showToast: () => assert.fail('successful open must not show a failure toast'),
    });
    assert.equal(creates, 0);
    const opening = bridge.open();
    assert.equal(shows, 0);
    assert.equal(await bridge.open(), false);
    finishLoad();
    assert.equal(await opening, true);
    assert.equal(await bridge.open(), true);
    assert.deepEqual([creates, loads, shows], [1, 1, 2]);
});

test('不支持开放页面接口时提供可理解的提示', async () => {
    const messages = [];
    const bridge = installGameClub({ showToast: value => messages.push(value) });
    assert.equal(await bridge.open(), false);
    assert.match(messages[0].title, /更新微信/);
});

for (const phase of ['create', 'load', 'show']) {
    test(`${phase} 失败不会抛出未处理异常，下一次点击可以重试`, async t => {
        t.mock.method(console, 'warn', () => {});
        let failing = true, creates = 0, destroys = 0;
        const messages = [];
        const maybeFail = step => { if (failing && step === phase) throw new Error(step); };
        const bridge = installGameClub({
            createPageManager() {
                creates++;
                maybeFail('create');
                return {
                    async load() { maybeFail('load'); },
                    async show() { maybeFail('show'); },
                    destroy() { destroys++; },
                };
            },
            showToast: value => messages.push(value),
        });
        assert.equal(await bridge.open(), false);
        assert.match(messages[0].title, /稍后再试/);
        assert.equal(destroys, phase === 'create' ? 0 : 1);
        failing = false;
        assert.equal(await bridge.open(), true);
        assert.equal(creates, 2);
    });
}
