const boot = GameGlobal.bbqBoot;
Promise.resolve()
    .then(() => {
        boot.mark('engine-entry');
        boot.mark('sdk:start');
        require('./godot-sdk');
        boot.mark('sdk:ready');
        require('./godot');
        boot.mark('engine-script:ready');
        boot.stage('初始化游戏引擎与食材资源');
        // Use the template's public Engine API so Godot stderr and exit codes
        // reach phone diagnostics, not just JavaScript Promise rejections.
        const loader = GameGlobal.godotLoader;
        const engine = new Engine({
            canvas,
            onPrint: boot.print,
            onPrintError: boot.printError,
            onExit: code => boot.fail(new Error(`Godot 在启动期间退出，退出码 ${code}`)),
        });
        GODOTSDK.engine = engine;
        loader.setStage(loader.config.textConfig.compilingText);
        boot.mark('engine-init:start');
        boot.mark('pack-read:start');
        return Promise.all([
            engine.init('/engine/godot').then(() => {
                boot.inspectRuntime(engine);
                boot.mark('engine-init:ready');
            }),
            engine.preloadFile('/engine/bbq.bin').then(() => boot.mark('pack-read:ready')),
        ]).then(() => {
            boot.inspectRuntime(engine);
            boot.stage('资源就绪，正在创建游戏画面');
            loader.handoff(loader.config.textConfig.initText);
            boot.mark('engine-start:start');
            const args = ['--main-pack', '/engine/bbq.bin'];
            if (boot.diagnostics) args.push('--', '--startup-diagnostics');
            return engine.start({ args });
        });
    })
    .then(() => GameGlobal.bbqBoot.ready())
    .catch(error => GameGlobal.bbqBoot.fail(error));
