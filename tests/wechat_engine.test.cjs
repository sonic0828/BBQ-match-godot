const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const configureRenderProbe = require('../platform/wechat/render-probe');

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

test('固定引擎首次创建上下文时 D 真正选择 WebGL2，B 与 iOS 保持 WXGLX', () => {
    const helpers = source.slice(source.indexOf('function wxGLXGetNativeExport('), source.indexOf('function wxGLXCallNative('));
    const createContext = source.slice(source.indexOf('function wxGLXPatchCreateContext('), source.indexOf('function wxGLXPatchMakeContextCurrent('));
    for (const [platform, probe, expected] of [['android', 'B', 'wxwebgl2'], ['android', 'D', 'webgl2'], ['android', undefined, 'webgl2'], ['ios', 'D', 'wxwebgl2']]) {
        const types = [];
        const root = {};
        const wx = { getDeviceInfo: () => ({ platform }), env: { isSupportEmscriptenGLX: true } };
        configureRenderProbe(wx, root, { androidRenderProbe: probe });
        const canvas = { getContext: type => { types.push(type); return { emscriptenGLX: type === 'wxwebgl2' }; } };
        const originalGetContext = canvas.getContext;
        const context = vm.createContext({ GameGlobal: root, wx, canvas,
            Module: { _glxInit() {}, _glxInitBufferDataAndGlState() {}, _glxUpdateContextId() {} },
            GL: { createContext: (target, attributes) => target.getContext('webgl2', attributes) },
        });
        vm.runInContext(helpers + createContext + `
            function wxGLXInitContext(gl) { wxGLXValidateAndPinContext(gl); }
            wxGLXPatchCreateContext();
            GL.createContext(canvas, { majorVersion: 2 });
        `, context);
        assert.deepEqual(types, [expected]);
        assert.equal(root.__godotMinigameWXGLXEnabled, expected === 'wxwebgl2');
        assert.equal(canvas.getContext, originalGetContext);
    }
});
