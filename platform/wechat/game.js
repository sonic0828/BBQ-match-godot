// Runtime files come from godothub/godot-minigame 4.7.0.8.
const installBootDiagnostics = require('./boot-diagnostics');
const bootOptions = require('./boot-options');
GameGlobal.bbqRenderProbe = require('./render-probe')(wx, GameGlobal, bootOptions);
GameGlobal.bbqBoot = installBootDiagnostics(wx, GameGlobal, bootOptions);
GameGlobal.bbqBoot.mark('adapter:start');
require('./weapp-adapter');
require('./glx-config');
require('./godot-loader');
GameGlobal.bbqBoot.mark('adapter:ready');
GameGlobal.bbqHaptics = require('./haptics')(wx);
GameGlobal.bbqGameClub = require('./game-club')(wx);

// All current effects are short WAVs mixed by Godot, with no external audio CDN.
GameGlobal.__godotMinigameNativeAudioMinDurationSeconds = Number.MAX_SAFE_INTEGER;

// The adapter routes window/canvas listeners through document. Forward host
// lifecycle events so the existing Godot focus-out handler pauses the game.
wx.onHide(() => {
    GameGlobal.bbqBoot.visibility(false);
    document.dispatchEvent({ type: 'blur' });
});
wx.onShow(() => {
    GameGlobal.bbqBoot.visibility(true);
    document.dispatchEvent({ type: 'focus' });
});

GameGlobal.godotLoader = new GodotLoader(canvas, {
    skipRendering: GameGlobal.bbqRenderProbe.skipLoaderRendering,
    lightRendering: GameGlobal.bbqRenderProbe.lightLoader,
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
