extends SceneTree
## Real view with deterministic game time; optional captures stay outside exports.

var app: Control
var failures: Array[String] = []
var checks = 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)

func start_level(number: int = 4) -> void:
	app._start_level(number)
	app.board.set_process(false)

func advance(seconds: float) -> void:
	for i in range(roundi(seconds * 100)):
		app._process(0.01)
		app.board.advance_animations(0.01)

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.audio.enabled = false
	app.audio.music_enabled = false
	start_level()
	var origin = app.board.slot_center(0, 0)
	advance(7.99)
	check(app.board.hint_slots.is_empty(), "no idle hint before eight seconds")
	advance(0.13)
	check(app.board.hint_slots.size() == 3 and app.board.hint_angle(0, 0) != 0, "eight seconds starts subtle rotation of selected corn")
	check(app.board.hint_angle(0, 2) == 0 and app.board.hint_angle(6, 1) == 0, "unrelated and covered food remain still")
	check(app.board.slot_center(0, 0) == origin and app.model.matches == 0, "hint changes neither hit boxes nor board rules")
	advance(3.45)
	check(app.board.hint_slots.size() == 3 and app.board.hint_angle(0, 0) != 0, "hint keeps looping beyond its first cycle")
	var touch = InputEventScreenTouch.new()
	touch.pressed = true
	app._input(touch)
	check(app.board.hint_slots.is_empty(), "touch anywhere stops the hint immediately")
	advance(9)
	check(app.board.hint_slots.is_empty() and app.board.hint_idle == 0, "holding a pointer cannot start a hint")
	touch.pressed = false
	app._input(touch)
	advance(7.9)
	check(app.board.hint_slots.is_empty(), "release restarts the full idle delay")
	advance(0.2)
	check(app.board.hint_slots.size() == 3, "idle hint returns after release plus eight seconds")
	app._pause()
	advance(9)
	check(app.board.hint_slots.is_empty(), "paused hint stays stopped")
	app._resume()
	advance(7.9)
	check(app.board.hint_slots.is_empty(), "resume also starts a fresh eight-second delay")
	start_level(1)
	advance(9)
	check(app.board.hint_slots.is_empty() and app.model.remaining == 75, "forced tutorial keeps its existing guidance without idle wobble")
	start_level()
	check(app.board.lid_alpha(6) == 1, "closed lid completely hides the food")
	app.model.begin_drag(0, 2)
	app.model.drop(1, 2)
	advance(0.21)
	check(app.board.lid_alpha(6) == 1 and not app.model.can_touch(6), "lid waits for plate impact before fading")
	advance(0.40)
	var alpha = app.board.lid_alpha(6)
	check(alpha > 0 and alpha < 1 and not app.model.can_touch(6), "lid crossfades while food is still locked")
	app._pause()
	advance(1)
	check(app.board.lid_alpha(6) == alpha, "pause freezes lid transparency")
	app._resume()
	advance(0.23)
	check(app.board.lid_alpha(6) == 0 and app.model.can_touch(6), "food becomes touchable only when lid has disappeared")
	app.board.hint_idle = 8.1
	advance(0.2)
	var valid = true
	for cell in app.board.hint_slots:
		valid = valid and app.model.can_touch(cell.x) and app.model.grills[cell.x].slots[cell.y] != ""
	check(valid, "board changes refresh hints instead of pointing at cleared corn")
	app.model.remaining = 0.001
	advance(0.01)
	check(app.board.hint_slots.is_empty(), "failure clears all hint rotations")
	start_level()
	check(app.board.hint_slots.is_empty() and app.board.lid_alpha(6) == 1, "restart has no old hint or opening tail")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-lid-hints="):
			await capture(arg.trim_prefix("--capture-lid-hints="))
	if failures.is_empty(): print("PASS: %d lid and idle hint animation checks" % checks)
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
	start_level()
	for frame in range(390):
		# 13 seconds: genuine eight-second wait, repeated hint, then corn unlock.
		if app.model.state == BoardModel.GameState.PAUSED: app._resume()
		if frame == 318:
			app.board.note_pointer(true)
			app.model.begin_drag(0, 2)
		if frame >= 318 and frame <= 330:
			var progress = float(frame - 318) / 12
			app.board.pointer = app.board.slot_center(0, 2).lerp(app.board.slot_center(1, 2), progress) + Vector2(0, 24)
		if frame == 330:
			app.model.drop(1, 2)
			app.board.note_pointer(false)
		app._process(1.0 / 30)
		app.board.advance_animations(1.0 / 30)
		app.board.queue_redraw()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("frame_%03d.png" % frame))
