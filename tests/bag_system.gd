extends SceneTree

var checks = 0
var failures: Array[String] = []
var app: Control

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text)

func fresh_store(suffix: String) -> SaveStore:
	var store = SaveStore.new()
	store.storage_path = "/private/tmp/bbq-bag-%s.cfg" % suffix
	store.save_progress()
	return store

func storage_checks() -> void:
	var store = fresh_store("economy")
	var first = store.begin_run()
	check(store.complete_level(1, first) and store.coins == 50, "one completed run awards 50")
	check(not store.complete_level(1, first) and store.coins == 50, "duplicate win cannot reward twice")
	var replay = store.begin_run()
	check(store.complete_level(1, replay) and store.coins == 100, "a new replay can earn 50 again")
	var failed = store.begin_run()
	check(store.coins == 100, "starting or failing a run gives no coins")
	check(not store.complete_level(1, failed + 100) and store.coins == 100, "unknown future run cannot claim reward")
	store.coins = 650
	store.refresh_daily()
	check(store.consume_bag(true) and store.bag_tutorial_done and store.available_bags() == 1, "tutorial consumes only its own gift")
	check(not store.consume_bag(true), "tutorial cannot grant a second gift")
	check(store.buy_bag() == OK and store.coins == 350 and store.bag_stock == 1 and store.available_bags() == 2, "purchase adds permanent inventory without use")
	check(store.consume_bag() and store.bag_daily_used and store.bag_stock == 1, "daily free use is consumed first")
	check(store.consume_bag() and store.bag_stock == 0, "paid stock is consumed after daily use")
	check(not store.consume_bag(), "no negative inventory")
	check(store.buy_bag() == OK and store.coins == 50 and store.bag_stock == 1, "second paid exchange is persisted")
	check(store.buy_bag() == ERR_UNAVAILABLE and store.coins == 50 and store.bag_stock == 1, "insufficient coins mutate nothing")
	var restored = SaveStore.new()
	restored.storage_path = store.storage_path
	restored.load_progress()
	check(restored.coins == 50 and restored.bag_stock == 1 and restored.bag_daily_used and restored.bag_tutorial_done, "restart restores wallet, stock, daily quota and teaching")
	check(not restored.complete_level(1, replay) and restored.coins == 50, "reward deduplication survives restart")
	var midnight = Time.get_unix_time_from_datetime_string("2026-10-01T16:00:00")
	store.bag_day = "2026-10-01"
	store.bag_daily_used = true
	store.refresh_daily(midnight - 1)
	check(store.bag_daily_used, "no free use before Beijing midnight")
	store.refresh_daily(midnight)
	check(not store.bag_daily_used and store.bag_day == "2026-10-02" and store.bag_stock == 1, "midnight refills one daily use and preserves purchased stock")
	store.refresh_daily(midnight + 3 * 86400)
	check(store.available_bags() == 2, "unused days do not accumulate")
	store.bag_daily_used = true
	store.refresh_daily(midnight)
	check(store.bag_daily_used, "clock rollback does not refill a consumed day")
	store.coins = 400
	store.storage_path = "/private/tmp/bbq-nonexistent-folder/subdir/progress.cfg"
	var before = store.bag_stock
	check(store.buy_bag() != OK and store.coins == 400 and store.bag_stock == before, "failed disk write rolls back both debit and inventory")
	var legacy = ConfigFile.new()
	legacy.set_value("progress", "completedLevels", [1, 2, 3, 4])
	legacy.save("/private/tmp/bbq-bag-legacy.cfg")
	var migrated = SaveStore.new()
	migrated.storage_path = "/private/tmp/bbq-bag-legacy.cfg"
	migrated.load_progress()
	check(migrated.coins == 200, "existing completed levels receive one migration credit")
	migrated.coins -= 50
	migrated.save_progress()
	migrated.load_progress()
	check(migrated.coins == 150, "migration never regrants old-level coins")

func advance_model(model: BoardModel, seconds: float) -> void:
	for i in range(roundi(seconds * 100)): model.tick(0.01)

func food_count(model: BoardModel) -> int:
	var count = 0
	for grill in model.grills:
		count += 3 - grill.slots.count("")
		for plate in grill.queue: count += plate.size()
	return count

func rules_checks() -> void:
	var model = BoardModel.new()
	model.start(LevelLoader.load_level(5))
	check(model.grills.size() == 12 and food_count(model) == 72 and model.total_matches == 24, "level five contains 12 grills and exactly 72 foods")
	for i in [6, 7, 8]: check(model.grills[i].state == BoardModel.GrillState.LOCKED, "third row is covered")
	var original = model.grills.duplicate(true)
	var candidate = model.pack_candidate("C")
	check(candidate.sources.size() == 3 and model.grills == original, "candidate discovery is read-only")
	check(model.pack_food("C", true), "corn gift packing starts")
	check(model.matches == 1 and food_count(model) == 69 and model.grills[6].state == BoardModel.GrillState.OPENING, "one triple removed, one match counted, corresponding lid opens")
	check(model.grills[7].state == BoardModel.GrillState.LOCKED and model.grills[8].state == BoardModel.GrillState.LOCKED, "unrelated lids stay closed")
	check(not model.pack_food("S") and not model.begin_drag(0, 2), "packing rejects duplicate use and board input")
	var remaining = model.remaining
	advance_model(model, 0.5)
	model.pause()
	var clock = model.clock
	advance_model(model, 2)
	check(model.clock == clock, "pause freezes packing")
	model.resume()
	advance_model(model, 1.06)
	check(model.pack_until < 0 and absf(model.remaining - remaining) < 0.02, "tutorial animation protects countdown")
	check(model.can_touch(6), "corn lid becomes usable after reveal")
	check(model.pack_food("S"), "ordinary packing starts after teaching")
	advance_model(model, 1.6)
	check(model.remaining < remaining - 1.5 and model.can_touch(7), "normal packing counts time and opens sausage lid")
	check(model.pack_food("W"), "wings can open the last lid")
	advance_model(model, 1.6)
	check(model.can_touch(8) and model.matches == 3, "all three independent lid conditions work")
	model.start({"level": 5, "timeLimitSec": 100, "grills": [
		{"initial": ["C", null, null], "plates": [["C"], ["C", "L"], ["J"]]},
		{"initial": ["L", "J", "W"], "plates": []},
		{"initial": ["C", "C", "C"], "plates": [], "unlockFood": "S"}]})
	candidate = model.pack_candidate("C")
	check(candidate.sources.size() == 3 and candidate.sources.all(func(v): return v.grill == 0), "reserve supplementation excludes covered food")
	check(model.pack_food("C"), "packing spans visible and multiple reserve plates")
	advance_model(model, 1.6)
	check(model.grills[0].slots == ["", "L", ""] and model.grills[0].queue == [["J"]], "reserve entries keep order and empty grill refills once")
	check(model.grills[2].slots == ["C", "C", "C"], "covered triple remains untouched")
	check(not model.pack_food("W"), "fewer than three eligible foods cannot be consumed")
	model.start({"level": 5, "timeLimitSec": 100, "grills": [
		{"initial": ["C", "C", null], "plates": []}, {"initial": ["C", null, null], "plates": []}]})
	model.pack_food("C")
	advance_model(model, 1.0)
	check(model.state == BoardModel.GameState.PLAYING, "last triple waits for bag to leave before victory")
	advance_model(model, 0.9)
	check(model.state == BoardModel.GameState.WIN and model.matches == 1, "last packed triple can win")
	model.start(LevelLoader.load_level(5))
	for i in range(24):
		var next = model.pack_candidate()
		if next.is_empty(): break
		model.pack_food(next.food)
		advance_model(model, 1.9)
	check(model.state == BoardModel.GameState.WIN and model.matches == 24 and food_count(model) == 0, "successive packs preserve all 24 groups through covers and reserve queues")

func advance(seconds: float) -> void:
	for i in range(roundi(seconds * 100)):
		app._process(0.01)
		app.board.advance_animations(0.01)

func click(button: Control) -> void:
	# Injected pointer events do not focus a native macOS window themselves.
	if app.audio.backgrounded:
		app._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
		if app.bag_mode == "" and app.model.state == BoardModel.GameState.PAUSED: app._resume()
	await process_frame
	var point = button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		root.push_input(event, true)
		await process_frame

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-bag="):
			app = load("res://scenes/main.tscn").instantiate()
			root.add_child(app)
			await process_frame
			app.set_process(false)
			app.audio.enabled = false
			app.audio.music_enabled = false
			await capture(arg.trim_prefix("--capture-bag="))
			app.queue_free()
			await process_frame
			await process_frame
			print("Rendered bag demonstration")
			quit()
			return
	storage_checks()
	rules_checks()
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.audio.enabled = false
	app.audio.music_enabled = false
	app.save = fresh_store("ui")
	app.save.coins = 600
	app._start_level(5)
	app.board.set_process(false)
	check(app.bag_mode == "unlock" and app.model.state == BoardModel.GameState.PAUSED, "first level five entry immediately starts paused teaching")
	app._close_bag()
	check(app.bag_mode == "unlock", "teaching cannot be dismissed without its free use")
	await click(app.modal.get_node("BagUnlock"))
	check(app.bag_mode == "use" and app.bag_dialog.use_button != null, "highlighted bag opens tutorial use confirmation")
	await click(app.bag_dialog.use_button)
	check(app.modal == null and app.model.matches == 1 and app.save.available_bags() == 1, "real use button spends gift and leaves daily use")
	app._use_bag()
	check(app.model.matches == 1 and app.save.available_bags() == 1, "double use callback cannot deduct twice")
	advance(1.8)
	await click(app.bag_button)
	await click(app.bag_dialog.use_button)
	advance(1.8)
	check(app.save.available_bags() == 0, "normal use consumes the daily quota")
	await click(app.bag_button)
	check(app.bag_mode == "shop" and app.bag_dialog.wallet.text == "600", "empty quota opens shop with wallet")
	var before = app.model.remaining
	await click(app.bag_dialog.get_node("BagAd"))
	check(app.center_toast.get_child(0).text == "广告尚未准备好" and app.save.available_bags() == 0, "unconfigured ad gives exact toast without reward")
	advance(2.1)
	check(app.model.remaining == before and app.center_toast == null, "shop pauses timer while toast expires on UI clock")
	await click(app.bag_dialog.get_node("BagBuy"))
	check(app.modal == null and app.save.coins == 300 and app.save.bag_stock == 1 and app.model.matches == 2, "exchange returns to board and never auto-uses bag")
	app._exchange_bag()
	check(app.save.coins == 300 and app.save.bag_stock == 1, "double exchange callback cannot debit twice")
	await click(app.bag_button)
	await click(app.bag_dialog.get_node("BagClose"))
	check(app.save.bag_stock == 1 and app.model.active(), "closing use confirmation preserves stock")
	app._start_level(5)
	app.board.set_process(false)
	check(app.bag_mode == "" and app.save.bag_stock == 1 and app.save.bag_daily_used, "restarting level neither repeats gift nor refills quota")
	for dimensions in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(768, 1024)]:
		root.size = dimensions
		await process_frame
		app._layout()
		var bottom = app.board.position.y + (app.board.plate_center(11).y + 24) * app.board.scale.y
		check(bottom < app.bottom_ui.position.y and app.board.grill_rect(6).position.y == app.board.grill_rect(8).position.y, "12-grill layout fits above tools at %s" % dimensions)
		app._open_bag()
		var bounds = Rect2(Vector2.ZERO, app.size)
		check(bounds.encloses(app.bag_dialog.get_global_rect()), "bag dialog fits %s" % dimensions)
		app._close_bag()
	for text in ["打包袋", "广告尚未准备好", "兑换成功", "本局获得"]:
		check(text.to_utf8_buffer().size() > 0 and Array(text.split("")).all(func(c): return c in app.font.get_supported_chars()), "bundled font covers " + text)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-bag="): await capture(arg.trim_prefix("--capture-bag="))
	if failures.is_empty(): print("PASS: %d bag, wallet, calendar and UI checks" % checks)
	else:
		for failure in failures: printerr("FAIL: " + failure)
	app.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(540, 1170)
	await process_frame
	app.save = fresh_store("capture")
	app.save.coins = 600
	app._start_level(5)
	app.board.set_process(false)
	for frame in range(270):
		if app.bag_mode == "" and app.model.state == BoardModel.GameState.PAUSED: app._resume()
		if frame == 35: app._show_bag_dialog(false)
		if frame == 75: app._use_bag()
		if frame == 135:
			app.save.bag_daily_used = true
			app._open_bag()
		if frame == 180: app._request_bag_ad()
		if frame == 245: app._exchange_bag()
		app._process(1.0 / 30)
		app.board.advance_animations(1.0 / 30)
		app.board.queue_redraw()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("frame_%03d.png" % frame))
