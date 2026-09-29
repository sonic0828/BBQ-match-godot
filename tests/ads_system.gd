extends SceneTree

class FakeAds extends GameAds:
	var requests: Array = []
	var acknowledged: Array = []
	var box = Rect2()
	var showing = false
	func request(kind: String) -> int:
		request_serial += 1
		requests.append({"id": request_serial, "kind": kind})
		return request_serial
	func acknowledge(receipt: String) -> void:
		acknowledged.append(receipt)
	func set_banner(rect: Rect2, visible: bool, _context: int) -> void:
		box = rect
		showing = visible
	func result(status: String, receipt: String = "") -> void:
		var latest = requests.back()
		event_received.emit({"type": "result", "kind": latest.kind, "id": latest.id, "status": status, "receipt": receipt})

var app: Control
var ads: FakeAds
var checks = 0
var failures: Array[String] = []
var directory = "/private/tmp/bbq-ad-test-%d" % OS.get_process_id()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text)

func storage_checks() -> void:
	var store = SaveStore.new()
	store.storage_path = directory.path_join("reward.cfg")
	store.coins = 250
	store.bag_stock = 1
	store.bag_daily_used = true
	check(store.grant_ad_bag("one") == OK and store.bag_stock == 2 and store.coins == 250 and store.bag_daily_used, "reward adds only permanent stock")
	check(store.grant_ad_bag("one") == OK and store.bag_stock == 2, "repeat receipt grants once")
	var restored = SaveStore.new()
	restored.storage_path = store.storage_path
	restored.load_progress()
	check(restored.grant_ad_bag("one") == OK and restored.bag_stock == 2, "inventory and receipt survive restart together")
	check(restored.grant_ad_bag("") != OK and restored.bag_stock == 2, "empty receipt rejected")
	store.storage_path = directory # Intentional rename failure: destination is a directory.
	check(store.grant_ad_bag("two") != OK and store.bag_stock == 2 and store.last_ad_receipt == "one", "failed save rolls back receipt and stock together")
	store.storage_path = restored.storage_path
	check(store.grant_ad_bag("two") == OK and store.bag_stock == 3, "failed receipt can be retried without another ad")

func win(level: int) -> void:
	app._start_level(level)
	app.model.state = BoardModel.GameState.WIN
	app._on_model_event("win", {})
	app.pending_win = false
	app._show_result(true)

func advance() -> void:
	app._process(0.01)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	storage_checks()
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.audio.enabled = false
	app.audio.music_enabled = false
	app._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	app.ads.queue_free()
	ads = FakeAds.new()
	app.ads = ads
	app.add_child(ads)
	ads.event_received.connect(app._on_ad_event)
	ads.layout_changed.connect(app._layout)
	app.save = SaveStore.new()
	app.save.storage_path = directory.path_join("game.cfg")
	app.save.bag_tutorial_done = true
	app.save.refresh_daily()
	app.save.bag_daily_used = true
	for level in [3, 6, 9]:
		win(level)
		check(app.interstitial_due and app.save.highest_unlocked == level + 1, "first clear arms next-button interstitial at %d" % level)
		var saved = SaveStore.new()
		saved.storage_path = app.save.storage_path
		saved.load_progress()
		check(saved.coins == app.save.coins and level in saved.completed, "progress and coins durable before ad at %d" % level)
		var count = ads.requests.size()
		app._next_level()
		app._next_level()
		check(ads.requests.size() == count + 1 and app.ad_busy and app.model.level == level, "double next starts one ad and delays navigation")
		ads.result("closed" if level == 3 else "unavailable")
		if level == 3:
			app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			advance()
			check(app.ad_busy and app.model.level == 3, "closed ad cannot start next level in background")
			app._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
			check(app.audio.backgrounded and app.haptics.backgrounded, "focus-in keeps ad audio muted until completion is consumed")
		advance()
		check(not app.ad_busy and app.model.level == level + 1 and app.modal == null, "close/unavailable both enter next level")
		win(level)
		check(not app.interstitial_due, "replay never arms milestone ad")
	win(2)
	check(not app.interstitial_due, "ordinary clear does not arm an ad")
	app._start_level(6)
	check(not app.interstitial_due, "re-entering does not catch up historical milestone")
	app._start_level(5)
	app._open_bag()
	check(app.bag_mode == "shop", "no available bag opens reward shop")
	app._request_bag_ad()
	var before = app.model.remaining
	ads.result("cancelled")
	advance()
	check(app.save.bag_stock == 0 and app.modal != null and app.model.remaining == before, "cancel keeps shop paused and grants nothing")
	app._request_bag_ad()
	ads.result("completed", "view-one")
	ads.result("completed", "view-one")
	advance()
	check(app.save.bag_stock == 1 and app.save.bag_daily_used and app.model.matches == 0 and app.model.pack_until < 0, "completed video adds one without auto-use or daily reset")
	check(app.modal == null and app.model.active(), "reward returns control to player")
	check(ads.acknowledged.has("view-one"), "successful save acknowledges durable receipt")
	app._on_ad_event({"type": "pending_reward", "receipt": "view-one"})
	check(app.save.bag_stock == 1, "cold replay of committed receipt cannot grant twice")
	app.save.bag_stock = 0
	app._open_bag()
	app._request_bag_ad()
	var path = app.save.storage_path
	app.save.storage_path = directory
	ads.result("completed", "view-two")
	advance()
	check(app.save.bag_stock == 0 and app.unsaved_ad_receipt == "view-two" and not ads.acknowledged.has("view-two"), "save failure retains unacknowledged reward")
	app.save.storage_path = path
	var count = ads.requests.size()
	app._request_bag_ad()
	check(app.save.bag_stock == 1 and app.unsaved_ad_receipt.is_empty() and ads.requests.size() == count, "retry claims saved reward without viewing twice")
	await layout_checks()
	for text in ["看视频", "完整观看视频后可获得打包袋", "奖励保存失败，请再次点击领取"]:
		check(Array(text.split("")).all(func(c): return c in app.font.get_supported_chars()), "font covers " + text)
	for failure in failures: printerr("FAIL: " + failure)
	print("Ads: %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func layout_checks() -> void:
	for dimensions in [Vector2i(360, 640), Vector2i(375, 812), Vector2i(390, 844), Vector2i(402, 874), Vector2i(768, 1024)]:
		root.size = dimensions
		await process_frame
		await process_frame
		ads._deliver({"type": "layout", "windowWidth": dimensions.x, "windowHeight": dimensions.y, "safeBottom": 34, "bannerWidth": 300, "bannerHeight": 105})
		app._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
		for level in [1, 3, 4, 5, 9]:
			app._start_level(level)
			var end = app.board.position.y + (app.board.plate_center(app.model.grills.size() - 1).y + 32) * app.board.scale.y
			check(end < app.bottom_ui.position.y and app.board.row_gap >= 222, "trays and tools separate at %s, level %d" % [dimensions, level])
			check(ads.box.position.y >= 0 and ads.box.end.y <= dimensions.y - 34 and ads.box.size.distance_to(Vector2(300, 105)) < 0.5, "native card stays above safe inset at %s: %s" % [dimensions, ads.box])
			check(app.ad_slot.position.y > app.tools_row.size.y * app.tools_row.scale.y, "tools never overlap card")
			check(ads.showing, "gameplay shows banner")
		app._pause()
		check(not ads.showing, "pause hides banner")
		app._resume()
		check(ads.showing, "resume restores banner")
		app._show_home()
		check(not ads.showing, "home hides banner")
	# SDK may clamp requested size. Respect a larger actual card too.
	ads._deliver({"type": "layout", "windowWidth": 768, "windowHeight": 1024, "safeBottom": 34, "bannerWidth": 350, "bannerHeight": 122.5})
	app._start_level(5)
	check(ads.box.size.is_equal_approx(Vector2(350, 122.5)), "layout uses actual native dimensions")
	app.save.bag_tutorial_done = false
	app._show_bag_unlock()
	await create_timer(0.6).timeout
	check(app.modal.get_node("BagUnlock").get_global_rect().is_equal_approx(app.bag_button.get_global_rect()), "tutorial spotlight follows shrunken tool position and size")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-ads="): await capture(arg.trim_prefix("--capture-ads="))

func capture(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	app.save.bag_tutorial_done = true
	for dimensions in [Vector2i(390, 844), Vector2i(360, 640)]:
		root.size = dimensions
		await process_frame
		ads._deliver({"type": "layout", "windowWidth": dimensions.x, "windowHeight": dimensions.y, "safeBottom": 34, "bannerWidth": 300, "bannerHeight": 105})
		app._start_level(5)
		var slot = app.ad_slot
		app._panel(slot, Rect2(Vector2.ZERO, slot.size), Color("28454a"), 8, Color("fff0cc"))
		app._label(slot, "20:7 广告区域\n布局示意 · 非真实广告", Rect2(Vector2.ZERO, slot.size), 27, Color.WHITE)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path.path_join("level5-%dx%d.png" % [dimensions.x, dimensions.y]))
	app.save.bag_stock = 0
	for child in app.ad_slot.get_children(): child.queue_free()
	app._open_bag()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path.path_join("reward-shop.png"))
