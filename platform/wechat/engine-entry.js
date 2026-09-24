import './godot-sdk'
import './godot'

GameGlobal.bbqBoot.stage('初始化游戏引擎与食材资源');
Promise.resolve()
    .then(() => GODOTSDK.startGame('/engine/godot', '/engine/bbq.bin'))
    .then(() => GameGlobal.bbqBoot.ready())
    .catch(error => GameGlobal.bbqBoot.fail(error));
