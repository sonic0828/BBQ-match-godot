extends SceneTree
## Deterministic visual timeline + real scene result handling; optional rendered frames.

var app: Control
var failures: Array[String] = []
var checks = 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.audio.enabled = false
	app._start_level(3)
	app.board.set_process(false)
	_test_all_foods_and_pause()
	_test_refill_origins()
	_test_chain_and_restart()
	_test_result_tail()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-combo="):
			await _capture_frames(arg.trim_prefix("--capture-combo="))
	if failures.is_empty():
		print("PASS: %d combo animation and lifecycle checks" % checks)
	else:
		for failure in failures: printerr("FAIL: " + failure)
	app.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)

func start_board(initials: Array, queues: Dictionary = {}) -> void:
	app._close_modal()
	app.pending_win = false
	var config = {"level": 3, "timeLimitSec": 100, "tutorial": "", "grills": []}
	for i in range(initials.size()):
		config.grills.append({"id": "G%d" % i, "initial": initials[i], "plates": queues.get(i, [])})
	app.model.start(config)
	app._layout_game()

func advance(duration: float) -> void:
	for i in range(roundi(duration * 100)):
		app._process(0.01)
		app.board.advance_animations(0.01)

func _test_all_foods_and_pause() -> void:
	var initials: Array = []
	for food in LevelLoader.FOOD_TYPES:
		initials.append([food, food, food])
		var texture = FoodArt.combo(food) as AtlasTexture
		check(texture != null and texture.atlas != null and Rect2(Vector2.ZERO, texture.atlas.get_size()).encloses(texture.region), "combo atlas region valid for " + food)
	start_board(initials)
	check(app.board.combos.size() == 8, "initial matches survive started event and show all eight plates")
	advance(0.15)
	app._pause()
	var frozen = app.board.animation_clock
	var remaining = app.model.remaining
	advance(1.0)
	check(app.board.animation_clock == frozen and app.model.remaining == remaining, "pause freezes combo and timer together")
	app._resume()
	advance(0.1)
	check(app.board.animation_clock > frozen, "combo resumes at its paused phase")
	app.model.remaining = 0.001
	advance(0.01)
	check(app.model.state == BoardModel.GameState.FAIL and app.modal != null and app.board.combos.is_empty(), "timeout clears visual tails and shows failure immediately")

func _test_refill_origins() -> void:
	for foods in [["C"], ["C", "J"], ["C", "J", "L"]]:
		start_board([[null, null, null], ["S", null, null]], {0: [foods, ["O"]]})
		check(app.board.refills[0].foods == foods and app.model.grills[0].queue[0] == ["O"], "outgoing tray snapshot remains distinct from next tray")
		for order in range(foods.size()):
			var pose = app.board.refill_pose(0, order)
			check(pose.center.is_equal_approx(app.board.tray_food_center(0, order, foods.size())) and pose.size == Vector2(26, 48), "refill starts at exact preview position and size, count %d order %d" % [foods.size(), order])
		advance(0.04)
		check(app.board.refill_pose(0, 0).center.y < app.board.tray_food_center(0, 0, foods.size()).y, "first food has launched")
		if foods.size() > 1:
			check(app.board.refill_pose(0, 1).center.is_equal_approx(app.board.tray_food_center(0, 1, foods.size())), "second food waits for stagger instead of launching simultaneously")
		app._pause()
		var before = app.board.refill_pose(0, 0)
		advance(0.5)
		check(app.board.refill_pose(0, 0) == before, "pause freezes food in flight")
		app._resume()
		advance(0.29)
		for order in range(foods.size()):
			var slot = 1 if foods.size() == 1 else (order * 2 if foods.size() == 2 else order)
			var pose = app.board.refill_pose(0, order)
			check(pose.center.is_equal_approx(app.board.slot_center(0, slot)) and pose.size == Vector2(60, 153), "food lands at correct slot and full size")
		check(app.model.can_touch(0), "refilled grill unlocks at original refill completion")

func _test_chain_and_restart() -> void:
	start_board([["C", "C", "C"], ["S", null, null]], {0: [["L", "L", "L"], ["J", "C", "W"]]})
	advance(0.65)
	check(app.model.matches == 2 and app.board.combos.size() == 2, "automatic chain starts while first plate is finishing")
	check(app.board.combos[0].food == "C" and app.board.combos[1].food == "L", "overlapping plates retain their original food IDs")
	advance(0.15)
	check(app.board.combos.size() == 1 and app.board.combos[0].food == "L", "old plate retires before new plate appears")
	advance(0.49)
	check(app.model.can_touch(0) and app.board.has_combo_animations(), "refilled grill is interactive while its plate remains visible")
	check(app.model.begin_drag(0, 0), "plate overlay does not block logical picking")
	app.model.cancel_drag()
	start_board([["M", null, null]])
	check(app.board.combos.is_empty() and app.board.refills.is_empty() and app.board.motions.is_empty(), "restart removes prior epoch animations and snapshots")

func _test_result_tail() -> void:
	start_board([["C", "C", "C"]])
	advance(0.60)
	check(app.model.state == BoardModel.GameState.WIN and app.pending_win and app.modal == null, "victory is recorded but modal waits for last plate")
	var remaining = app.model.remaining
	advance(0.40)
	check(app.modal != null and not app.pending_win and app.board.combos.is_empty(), "last plate finishes before victory modal appears")
	check(app.model.remaining == remaining, "visual victory tail does not consume countdown")
	start_board([["C", "C", "C"]])
	advance(0.60)
	app._show_home()
	app._process(1.0)
	check(app.current_page == "home" and app.modal == null and not app.pending_win, "navigation cancels deferred victory presentation")
	app._start_level(3)
	app.board.set_process(false)

func _capture_frames(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(720, 1280)
	await process_frame
	var initials: Array = []
	var queues: Dictionary = {}
	for food in LevelLoader.FOOD_TYPES:
		queues[initials.size()] = [["J", "C", "W"], ["M", "E", "O"]]
		initials.append([food, food, food])
	initials.append(["L", "C", "J"])
	start_board(initials, queues)
	app.board.tutorial_visible = false
	for frame in range(73):
		# Explicit capture mode may run behind the user's foreground application.
		if app.model.state == BoardModel.GameState.PAUSED:
			app._resume()
		if frame > 0:
			app._process(1.0 / 60)
			app.board.advance_animations(1.0 / 60)
		app.board.queue_redraw()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("frame_%03d.png" % frame))
	check(app.model.clock > 1.0 and app.model.active(), "rendered capture advances through the entire animation")
