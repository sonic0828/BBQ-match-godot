extends SceneTree
## Real scene + Input events: validates coordinates, GUI routing and screen transitions.

var app: Control
var failures: Array[String] = []
var checks = 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	check(app.current_page == "home", "home scene renders")
	app._start_level(1)
	await process_frame
	var from = app.board.get_global_transform_with_canvas() * app.board.slot_center(2, 1)
	var to = app.board.get_global_transform_with_canvas() * app.board.slot_center(0, 2)
	await drag(from, to)
	check(app.model.state == BoardModel.GameState.PLAYING, "actual mouse drag completes tutorial")
	await create_timer(0.7).timeout
	check(app.model.matches == 1, "input-routed move triggers match")
	app._pause()
	var before = app.model.remaining
	await create_timer(0.1).timeout
	check(app.model.remaining == before and app.modal != null, "pause modal freezes game")
	app._resume()
	check(app.modal == null and app.model.active(), "resume closes modal")
	app._start_level(3)
	await process_frame
	from = app.board.get_global_transform_with_canvas() * app.board.slot_center(0, 2)
	to = app.board.get_global_transform_with_canvas() * app.board.slot_center(1, 2)
	await drag(from, to)
	await create_timer(0.7).timeout
	check(app.model.matches == 2, "real mouse swap triggers double match")
	app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.model.state == BoardModel.GameState.PAUSED and app.modal != null, "background focus loss auto-pauses")
	app._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(app.model.state == BoardModel.GameState.PAUSED, "foreground never auto-resumes timer")
	app._resume()
	app.model.remaining = 0.001
	await create_timer(0.1).timeout
	check(app.model.state == BoardModel.GameState.FAIL and app.modal != null, "timeout shows result modal")
	app._show_home()
	check(app.current_page == "home" and app.modal == null, "home navigation clears modal")
	app._show_levels()
	check(app.current_page == "levels", "level selection opens")
	app._show_home()
	app._show_settings()
	check(app.modal != null, "settings opens")
	app._close_modal()
	for dimensions in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(768, 1024)]:
		root.size = dimensions
		await process_frame
		await process_frame
		app._start_level(3)
		await process_frame
		var safe_bounds = Rect2(Vector2.ZERO, app.size)
		var stage_end = app.stage.position + app.stage.size * app.stage.scale
		check(safe_bounds.has_point(app.stage.position + Vector2.ONE) and safe_bounds.has_point(stage_end - Vector2.ONE), "stage fits %s window" % str(dimensions))
		var source = app.board.get_global_transform_with_canvas() * app.board.slot_center(0, 2)
		var target = app.board.get_global_transform_with_canvas() * app.board.slot_center(1, 2)
		await drag(source, target)
		await create_timer(0.55).timeout
		check(app.model.matches == 2, "drag coordinates remain correct at %s" % str(dimensions))
	app._show_home()
	await create_timer(0.65).timeout
	if failures.is_empty():
		print("PASS: %d real-scene input and navigation checks" % checks)
	else:
		for failure in failures: printerr("FAIL: " + failure)
	app.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)

func drag(from: Vector2, to: Vector2) -> void:
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	root.push_input(press, true)
	await process_frame
	var motion = InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	var release = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	root.push_input(release, true)
	await process_frame
