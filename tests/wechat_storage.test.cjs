const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const { original, patched } = JSON.parse(execFileSync('python3', ['-B', '-c', `
import hashlib, json, zipfile
from tools.export_wechat import ROOT, VERSION, SHA256, patch_wechat_engine
p = ROOT / 'build/cache' / f'minigame{VERSION}.tpz'
assert hashlib.sha256(p.read_bytes()).hexdigest() == SHA256
with zipfile.ZipFile(p) as z:
    source = z.read('engine/godot.js').decode()
print(json.dumps(dict(original=source, patched=patch_wechat_engine(source))))
`], { cwd: path.resolve(__dirname, '..'), encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 }));

// Every fixture creates a new VM and mounts the actual pinned WXMEMFS. Only the
// host disk survives restart; no in-memory nodes or streams are reused.
function boot(source, disk = new Map(), fail = () => false) {
    const calls = [], warnings = [];
    class ErrnoError extends Error { constructor(errno) { super('FS error'); this.name = 'ErrnoError'; this.errno = errno; } }
    const FS = {
        isDir: mode => (mode & 0xf000) === 0x4000,
        isFile: mode => (mode & 0xf000) === 0x8000,
        isLink: () => false, isChrdev: () => false, isBlkdev: () => false, isFIFO: () => false,
        createNode: (parent, name, mode) => ({ parent, name, mode }),
        lookupNode: (parent, name) => {
            if (!parent.contents[name]) throw new ErrnoError(44);
            return parent.contents[name];
        },
        getPath: node => node.parent ? FS.getPath(node.parent) + '/' + node.name : '/userfs',
        hashRemoveNode() {}, ErrnoError,
    };
    const native = {
        statSync: () => [...disk].map(([name, data]) => ({ path: name, stats: { size: data.length, isDirectory: () => false } })),
        readFileSync: name => {
            if (fail('read', name) || !disk.has(name.slice(3))) throw new Error('read failed');
            const data = disk.get(name.slice(3));
            return Uint8Array.from(data).buffer;
        },
        writeFileSync: (name, data) => {
            if (fail('write', name)) throw new Error('disk full');
            const bytes = typeof data === 'string' ? Buffer.from(data) : Buffer.from(new Uint8Array(data));
            disk.set(name.slice(3), fail('short-write', name) ? bytes.subarray(0, 1) : bytes);
        },
        renameSync: (from, to) => {
            calls.push([from, to]);
            if (fail('rename', from) || !disk.has(from.slice(3))) throw new Error('rename failed');
            if (from !== to) { disk.set(to.slice(3), disk.get(from.slice(3))); disk.delete(from.slice(3)); }
        },
    };
    const context = vm.createContext({ FS, wx: { env: { USER_DATA_PATH: '/wx' }, getFileSystemManager: () => native },
        console: { log() {}, error: (...args) => warnings.push(args), warn: (...args) => warnings.push(args) } });
    const start = source.indexOf('var WXMEMFS=');
    vm.runInContext(source.slice(start, source.indexOf(';_0x20f62f=', start) + 1), context);
    const patchStart = source.indexOf('/* BBQ filesystem patch */');
    if (patchStart >= 0) vm.runInContext(source.slice(patchStart, source.indexOf('var GodotFS=', patchStart)), context);
    const fs = context.WXMEMFS;
    const root = fs.mount({ mountpoint: '/userfs' });
    function write(name, value) {
        const node = root.contents[name] || fs.node_ops.mknod(root, name, 0x8000 | 0o666, 0);
        const stream = { node, path: '/userfs/' + name, flags: 577 };
        fs.stream_ops.open(stream);
        const bytes = Uint8Array.from(Buffer.from(value));
        // Multiple writes force an overallocated underlying buffer in WXMEMFS.
        const middle = Math.ceil(bytes.length / 2);
        fs.stream_ops.write(stream, bytes, 0, middle, 0, false);
        fs.stream_ops.write(stream, bytes, middle, bytes.length - middle, middle, false);
        fs.stream_ops.close(stream);
        return node;
    }
    function read(name) {
        const node = FS.lookupNode(root, name);
        const stream = { node, path: '/userfs/' + name, flags: 0 };
        fs.stream_ops.open(stream);
        const value = Buffer.from(fs.getFileDataAsTypedArray(node)).toString();
        fs.stream_ops.close(stream);
        return value;
    }
    return { disk, root, fs, write, read, calls, warnings,
        save: value => fs.node_ops.rename(write('progress.cfg.pending', value), root, 'progress.cfg') };
}

test('原固定模板复现：保存返回成功，重启后仍读取旧正式存档', () => {
    const disk = new Map([['/progress.cfg', Buffer.from('old')]]);
    const first = boot(original, disk);
    first.save('new');
    assert.deepEqual(first.calls, [['/wx/progress.cfg', '/wx/progress.cfg']]);
    assert.equal(boot(original, disk).read('progress.cfg'), 'old');
});

for (const existing of [false, true]) {
    test(`微信新运行实例恢复完整关卡、教学与钱包快照，已有存档 ${existing}`, () => {
        const disk = existing ? new Map([['/progress.cfg', Buffer.from('old')]]) : new Map();
        const snapshot = '[progress]\nlevel=9\n[economy]\ncoins=350\nbagStock=1\nbagTutorialDone=true\n';
        const first = boot(patched, disk);
        first.save(snapshot);
        assert.deepEqual(first.calls, [['/wx/progress.cfg.pending', '/wx/progress.cfg']]);
        assert.equal(boot(patched, disk).read('progress.cfg'), snapshot);
        assert.equal(disk.get('/progress.cfg').length, Buffer.byteLength(snapshot), 'no unused buffer bytes');
        assert.equal(disk.has('/progress.cfg.pending'), false);
    });
}

for (const operation of ['write', 'short-write', 'read', 'rename']) {
    test(`微信 ${operation} 失败不能提交新快照，旧存档和内存目标均保留，可重试`, () => {
        const disk = new Map([['/progress.cfg', Buffer.from('old')]]);
        let failing = true;
        const first = boot(patched, disk, (op, name) => failing && op === operation && name.endsWith('.pending'));
        const oldNode = first.root.contents['progress.cfg'];
        assert.throws(() => first.save('new snapshot'), error => error.name === 'ErrnoError');
        assert.equal(first.root.contents['progress.cfg'], oldNode);
        assert.equal(boot(patched, disk).read('progress.cfg'), 'old');
        failing = false;
        first.save('retry snapshot');
        assert.equal(boot(patched, disk).read('progress.cfg'), 'retry snapshot');
    });
}

test('微信只读文件关闭不重写，普通资源读取不触发存档校验', () => {
    const disk = new Map([['/progress.cfg', Buffer.from('old')]]);
    const first = boot(patched, disk, op => op === 'write');
    assert.equal(first.read('progress.cfg'), 'old');
    assert.equal(first.calls.length, 0);
    assert.equal(first.warnings.length, 0);
});

test('空快照覆盖也会实际截断磁盘文件，写入失败不能提交旧临时字节', () => {
    const disk = new Map([['/progress.cfg.pending', Buffer.from('stale bytes')]]);
    const first = boot(patched, disk);
    first.save('');
    assert.equal(boot(patched, disk).read('progress.cfg'), '');
    const failing = boot(patched, disk, op => op === 'write');
    assert.throws(() => failing.save(''), error => error.name === 'ErrnoError');
});
