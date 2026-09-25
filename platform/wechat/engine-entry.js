import './godot-sdk'
import './godot'

GameGlobal.bbqBoot.stage('初始化游戏引擎与食材资源');
Promise.resolve()
    .then(() => {
        // Use the template's public Engine API so Godot stderr and exit codes
        // reach phone diagnostics, not just JavaScript Promise rejections.
        const boot = GameGlobal.bbqBoot;
        const loader = GameGlobal.godotLoader;
        const engine = new Engine({
            canvas,
            onPrint: boot.print,
            onPrintError: boot.printError,
            onExit: code => boot.fail(new Error(`Godot 在启动期间退出，退出码 ${code}`)),
        });
        GODOTSDK.engine = engine;
        loader.currentText = loader.config.textConfig.compilingText;
        return Promise.all([
            engine.init('/engine/godot'),
            engine.preloadFile('/engine/bbq.bin'),
        ]).then(() => {
            boot.inspectRuntime(engine);
            boot.stage('资源就绪，正在创建游戏画面');
            loader.cleanup();
            return engine.start({ args: ['--main-pack', '/engine/bbq.bin'] });
        });
    })
    .then(() => GameGlobal.bbqBoot.ready())
    .catch(error => GameGlobal.bbqBoot.fail(error));
