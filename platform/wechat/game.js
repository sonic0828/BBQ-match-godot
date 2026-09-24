// Runtime files come from godothub/godot-minigame 4.7.0.8.
import './weapp-adapter'
import './glx-config'
import './godot-loader'

const installBootDiagnostics = require('./boot-diagnostics');
GameGlobal.bbqBoot = installBootDiagnostics(wx, GameGlobal, require('./boot-options'));

// All current effects are short WAVs mixed by Godot, with no external audio CDN.
GameGlobal.__godotMinigameNativeAudioMinDurationSeconds = Number.MAX_SAFE_INTEGER;

// The adapter routes window/canvas listeners through document. Forward host
// lifecycle events so the existing Godot focus-out handler pauses the game.
wx.onHide(() => document.dispatchEvent({ type: 'blur' }));
wx.onShow(() => document.dispatchEvent({ type: 'focus' }));

GameGlobal.godotLoader = new GodotLoader(canvas, {
    textConfig: {
        firstStartText: '炭火已备好，正在准备食材',
        downloadingText: ['正在准备食材', '正在点燃炭火', '马上开烤'],
        compilingText: '正在点燃炭火',
        initText: '正在摆好烤盘',
        completeText: '开烤啦',
        textDuration: 1500,
        style: { color: '#fff0cc', fontSize: 15 },
    },
    barConfig: {
        style: {
            width: 240, height: 12,
            backgroundColor: 'rgba(0, 0, 0, 0.55)',
            foregroundColor: '#f6c772', borderRadius: 6, padding: 2,
        },
    },
    iconConfig: { visible: false, style: { width: 74, height: 30, bottom: 20 } },
    materialConfig: {
        backgroundImage: 'images/background.jpg', backgroundVideo: '',
        iconImage: 'images/logo.png',
    },
});
