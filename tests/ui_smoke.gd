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
	check("圈" in app.font.get_supported_chars(), "game circle label is included in the bundled font")
	var club = app.page.get_node("GameClubButton")
	# Children must pass clicks through to the full square button.
	await click(club.get_child(0).get_global_rect().get_center())
	check(app.modal != null and app.current_page == "home", "game circle icon opens the native preview explanation")
	app._close_modal()
	await process_frame
	await click(club.get_child(1).get_global_rect().get_center())
	check(app.modal != null, "game circle text is also clickable")
	app._close_modal()
	app._start_level(1)
	await process_frame
	var from = app.board.get_global_transform_with_canvas() * app.board.slot_center(2, 1)
	var to = app.board.get_global_transform_with_canvas() * app.board.slot_center(0, 2)
	await drag(from, to)
	check(app.model.state == BoardModel.GameState.PLAYING, "actual mouse drag completes tutorial")
	await create_timer(0.7).timeout
	check(app.model.matches == 1, "input-routed move triggers match")
	var pause_button = app.game_hud.get_node("PauseButton")
	await click(pause_button.get_global_rect().get_center())
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
	# Web forwards WINDOW focus, not APPLICATION focus. Exercise both without
	# requiring a phone, including duplicate notifications from native platforms.
	app.startup_diagnostics = true
	app.startup_sampling = true
	app.startup_sample_last_usec = Time.get_ticks_usec() - 1900000
	app._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	var paused_modal = app.modal
	check(not app.startup_foreground and app.startup_sample_last_usec == 0, "window blur clears frame timing")
	check(app.model.state == BoardModel.GameState.PAUSED and app.audio.backgrounded and app.haptics.backgrounded, "window blur pauses game, audio and haptics")
	app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.modal == paused_modal, "duplicate blur does not replace pause panel")
	await create_timer(0.1).timeout
	app._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	check(app.startup_foreground and app.startup_sample_last_usec == 0 and app.startup_sample_seconds == 0.0, "window focus discards background duration")
	check(not app.audio.backgrounded and not app.haptics.backgrounded and app.model.state == BoardModel.GameState.PAUSED, "window focus restores host state but awaits player resume")
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	check(not app.startup_resume_pending, "resume confirmation waits for an actual rendered frame")
	app.startup_sample_count = 1
	app._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(app.startup_sample_count == 1 and not app.startup_resume_pending, "duplicate focus neither resets sampling nor queues another frame")
	check(app.startup_sample_max_delta < 0.5, "background gap is excluded from measured frame stalls")
	app.startup_diagnostics = false
	app.startup_sampling = false
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
		app._show_home()
		club = app.page.get_node("GameClubButton")
		var settings = app.page.get_node("SettingsButton")
		check(club.size.x == club.size.y and club.size.x == settings.size.x and club.position.y > settings.position.y + settings.size.y, "game circle stays square below settings at %s" % str(dimensions))
		app._start_level(3)
		await process_frame
		var safe_bounds = Rect2(Vector2.ZERO, app.size)
		var stage_end = app.stage.position + app.stage.size * app.stage.scale
		check(safe_bounds.has_point(app.stage.position + Vector2.ONE) and safe_bounds.has_point(stage_end - Vector2.ONE), "stage fits %s window" % str(dimensions))
		var source = app.board.get_global_transform_with_canvas() * app.board.slot_center(0, 2)
		pause_button = app.game_hud.get_node("PauseButton")
		check(pause_button.position.x < 60 and pause_button.position.x + pause_button.size.x < 132, "pause stays left of HUD numbers at %s" % str(dimensions))
		var target = app.board.get_global_transform_with_canvas() * app.board.slot_center(1, 2)
		await drag(source, target)
		await create_timer(0.55).timeout
		check(app.model.matches == 2, "drag coordinates remain correct at %s" % str(dimensions))
		app._start_level(4)
		await process_frame
		var covered = app.board.grill_rect(6)
		check(covered.get_center().x == app.board.grill_rect(1).get_center().x and covered.position.y > app.board.grill_rect(4).position.y and covered.position.y < app.board.grill_rect(8).position.y, "covered grill is alone in third row at %s" % str(dimensions))
		var bottom = app.board.position.y + (app.board.plate_center(9).y + 24) * app.board.scale.y
		check(bottom < app.bottom_ui.position.y and app.board.row_gap >= 212, "four rows and trays fit above tools without overlaps at %s" % str(dimensions))
		source = app.board.get_global_transform_with_canvas() * app.board.slot_center(6, 0)
		target = app.board.get_global_transform_with_canvas() * app.board.slot_center(0, 0)
		await drag(source, target)
		check(app.model.grills[6].slots == ["L", "C", "W"] and app.model.grills[0].slots[0] == "C", "touch cannot pull food through lid at %s" % str(dimensions))
		source = app.board.get_global_transform_with_canvas() * app.board.slot_center(0, 2)
		target = app.board.get_global_transform_with_canvas() * app.board.slot_center(1, 2)
		await drag(source, target)
		await create_timer(0.9).timeout
		check(app.model.can_touch(6), "real corn swap opens scaled covered grill at %s" % str(dimensions))
		source = app.board.get_global_transform_with_canvas() * app.board.slot_center(6, 0)
		target = app.board.get_global_transform_with_canvas() * app.board.slot_center(0, 0)
		await drag(source, target)
		await create_timer(0.25).timeout
		check(app.model.grills[0].slots[0] == "L", "revealed food uses correct scaled drag coordinates at %s" % str(dimensions))
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

func click(position: Vector2) -> void:
	# Keep synthetic clicks in one input burst; native mouse events between the
	# press/release frames can otherwise cancel a button's pressed state.
	var motion = InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		root.push_input(event, true)
	await process_frame
