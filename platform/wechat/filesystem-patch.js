/* BBQ filesystem patch */
// Injected into the pinned engine before GodotFS mounts WXMEMFS.
(function () {
    const open = WXMEMFS.stream_ops.open;
    WXMEMFS.stream_ops.open = function (stream) {
        open(stream);
        // O_TRUNC is a write even when the new file has no bytes (e.g. backing
        // up an empty old save). The template otherwise keeps stale disk data.
        if (stream.flags & 512) WXMEMFS.openStreams[stream.wxfd].dirty = true;
    };
    WXMEMFS.persistNode = function (node, wxPath) {
        if (!FS.isFile(node.mode)) return;
        node.bbqPersistFailed = false;
        try {
            const bytes = WXMEMFS.getFileDataAsTypedArray(node);
            const fs = wx.getFileSystemManager();
            // A subarray's buffer also contains unused capacity. Persist only
            // the file bytes, otherwise ConfigFile snapshots acquire NUL tails.
            fs.writeFileSync(wxPath, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
            if (wxPath.endsWith('.pending')) {
                const saved = new Uint8Array(fs.readFileSync(wxPath));
                if (saved.length !== bytes.length || saved.some((value, i) => value !== bytes[i])) {
                    throw new Error('saved snapshot differs from written bytes');
                }
            }
        } catch (error) {
            // ConfigFile closes its file before rename. The template swallows
            // close errors, so carry failure to that commit boundary as well.
            node.bbqPersistFailed = true;
            console.warn('[BBQ save] snapshot write failed:', error.message);
            throw error;
        }
    };

    WXMEMFS.node_ops.rename = function (node, newDir, newName) {
        const oldDir = node.parent;
        const oldName = node.name;
        let target;
        try { target = FS.lookupNode(newDir, newName); } catch (error) {
            if (error.errno !== 44) throw error;
        }
        if (target === node) return;
        if (target && FS.isDir(node.mode) && Object.keys(target.contents).length) throw new FS.ErrnoError(55);
        if (node.bbqPersistFailed || !WXMEMFS.wxBasePath) throw new FS.ErrnoError(29);
        // Compute both paths while the old node still has its original name.
        // Native failure must leave both the old disk snapshot and nodes intact.
        const from = WXMEMFS.getWxPath(FS.getPath(node));
        const to = WXMEMFS.getWxPath(FS.getPath(newDir) + '/' + newName);
        try {
            wx.getFileSystemManager().renameSync(from, to);
        } catch (error) {
            console.warn('[BBQ save] snapshot rename failed:', error.message);
            throw new FS.ErrnoError(29);
        }
        if (target) FS.hashRemoveNode(target);
        delete oldDir.contents[oldName];
        newDir.contents[newName] = node;
        node.name = newName;
        node.parent = newDir;
        oldDir.ctime = oldDir.mtime = newDir.ctime = newDir.mtime = Date.now();
    };
})();
