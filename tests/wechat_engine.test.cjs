const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const source = execFileSync('python3', ['-B', '-c', `
import hashlib, zipfile
from tools.export_wechat import ROOT, VERSION, SHA256, patch_wechat_engine
p = ROOT / 'build/cache' / f'minigame{VERSION}.tpz'
assert hashlib.sha256(p.read_bytes()).hexdigest() == SHA256
with zipfile.ZipFile(p) as z:
    print(patch_wechat_engine(z.read('engine/godot.js').decode()))
`], { cwd: path.resolve(__dirname, '..'), encoding: 'utf8' });

function fixture({ skip = false, native = true, streaming = false, fail = '' } = {}) {
    const reads = [], instantiations = [], marks = [];
    const hostWasm = {
        instantiate: async file => {
            instantiations.push(file);
            if (fail === 'wasm') throw new Error('WASM rejected');
            return { instance: {}, module: {} };
        },
    };
    if (streaming) hostWasm.instantiateStreaming = async response => {
        instantiations.push(await response);
        return { instance: {}, module: {} };
    };
    const module = { initFS: async () => {
        if (fail === 'fs-reject') throw new Error('FS rejected');
        return fail === 'fs-error' ? new Error('FS error') : null;
    } };
    const globals = {
        window: { fsUtils: { localFetch: async file => {
            reads.push(file);
            if (fail === 'read') throw new Error('read failed');
            return file.endsWith('.bin') ? new ArrayBuffer(4) : { data: 'wasm response' };
        } } },
        WebAssembly: hostWasm, WXWebAssembly: native ? hostWasm : {},
        GameGlobal: { bbqRenderProbe: { skipWasmRead: skip },
            bbqBoot: { mark: (name, detail) => marks.push({ name, detail }) } },
        requestAnimationFrame() {}, setTimeout: callback => setImmediate(callback), console,
        Godot: config => new Promise((resolve, reject) => {
            config.instantiateWasm({}, () => resolve(module), reject);
        }),
    };
    // Exercise the pinned public loader/Config/Engine code; only the native VM is stubbed.
    vm.runInNewContext(source.slice(source.indexOf('const Features =')), globals);
    return { engine: new globals.window.Engine({}), reads, instantiations, marks, module };
}

for (const skip of [false, true]) {
    test(`微信路径 WASM 预读对照 ${skip}，资源包仍读取且 init 只执行一次`, async () => {
        const f = fixture({ skip });
        await Promise.all([f.engine.init('/engine/godot'), f.engine.preloadFile('/engine/bbq.bin')]);
        await f.engine.init('/engine/godot');
        assert.equal(f.reads.filter(file => file.endsWith('.wasm.br')).length, skip ? 0 : 1);
        assert.equal(f.reads.filter(file => file.endsWith('.bin')).length, 1);
        assert.deepEqual(f.instantiations, ['/engine/godot.wasm.br']);
        assert.equal(f.engine.rtenv, f.module);
        assert.equal(f.marks.find(mark => mark.name === 'wasm-read:start').detail.skipped, skip);
        assert.ok(f.marks.some(mark => mark.name === 'wasm-instantiate:ready'));
    });
}

for (const options of [{ native: false }, { streaming: true }]) {
    test(`非文件路径实例化继续预读 ${JSON.stringify(options)}`, async () => {
        const f = fixture({ skip: true, ...options });
        await f.engine.init('/engine/godot');
        assert.deepEqual(f.reads, ['/engine/godot.wasm.br']);
        assert.equal(f.marks[0].detail.skipped, false);
    });
}

for (const fail of ['wasm', 'read', 'fs-error', 'fs-reject']) {
    test(`引擎 ${fail} 失败会 reject，入口可显示重试提示`, async () => {
        const f = fixture({ fail });
        await assert.rejects(f.engine.init('/engine/godot'), /rejected|failed|FS error/);
    });
}
