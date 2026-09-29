extends Control

const CREAM = Color("fff0cc")
const MUTED = Color("cfc0a3")
const GOLD = Color("f6c772")

var model = BoardModel.new()
var save = SaveStore.new()
var stage: Control
var page: Control
var modal: Control
var board: BoardView
var audio: Node
var haptics: Node
var font: Font
var current_page = "home"
var timer_label: Label
var progress_label: Label
var game_hud: Control
var hint_panel: Panel
var bottom_ui: Control
var hint_label: Label
var combo_label: Label
var shown_matches = 0
var progress_elapsed = 0.0
var toast_until = 0.0
var combo_until = 0.0
var last_warning = -1
var ui_clock = 0.0
var capture_path = ""
var capture_frames = 0
var pending_win = false
var run_id = -1
var win_reward = false
var bag_button: TextureButton
var bag_badge: Label
var bag_mode = ""
var bag_teaching = false
var bag_dialog: BagDialog
var center_toast: Panel
var center_toast_until = 0.0
var daily_check = 0.0
var startup_diagnostics = false
var startup_sampling = false
var startup_sample_last_usec = 0
var startup_sample_seconds = 0.0
var startup_sample_frames = 0
var startup_sample_slow_frames = 0
var startup_sample_max_delta = 0.0
var startup_sample_count = 0
var startup_sample_limit = 12
var startup_resume_pending = false
var startup_foreground = true

func _ready() -> void:
	startup_diagnostics = OS.has_feature("wechat") and "--startup-diagnostics" in OS.get_cmdline_user_args()
	startup_sampling = startup_diagnostics
	font = load("res://assets/fonts/game.ttf")
	var theme_resource = Theme.new()
	theme_resource.default_font = font
	theme_resource.default_font_size = 26
	theme = theme_resource
	if "--test-session" in OS.get_cmdline_user_args():
		save.storage_path = "/private/tmp/hotpot-ui-progress.cfg"
	save.load_progress()
	audio = preload("res://scripts/core/game_audio.gd").new()
	add_child(audio)
	audio.enabled = save.audio_enabled
	audio.music_enabled = save.music_enabled
	haptics = preload("res://scripts/core/game_haptics.gd").new()
	add_child(haptics)
	haptics.enabled = save.vibration_enabled
	var background = TextureRect.new()
	background.texture = load("res://assets/art/night_market.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade = ColorRect.new()
	shade.color = Color(0.045, 0.035, 0.025, 0.20)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	stage = Control.new()
	stage.size = Vector2(720, 1280)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	resized.connect(_layout)
	_layout()
	model.event.connect(_on_model_event)
	_show_home()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			_start_level(clampi(arg.get_slice("=", 1).to_int(), 1, 10))
		elif arg == "--skip-tutorial":
			model.state = BoardModel.GameState.PLAYING
		elif arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
	if OS.has_feature("wechat"):
		_report_wechat_startup.call_deferred()

func _report_wechat_startup() -> void:
	print("[BBQ scene ready] ", size)
	await RenderingServer.frame_post_draw
	print("[BBQ first frame]")

func _report_wechat_resume() -> void:
	await RenderingServer.frame_post_draw
	startup_resume_pending = false
	if startup_foreground:
		print("[BBQ resume frame] ", current_page)

func _layout() -> void:
	if stage == null:
		return
	var available = Rect2(Vector2.ZERO, size)
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe = DisplayServer.get_display_safe_area()
		var screen = DisplayServer.screen_get_size()
		if screen.x > 0 and screen.y > 0:
			available = Rect2(Vector2(safe.position) / Vector2(screen) * size, Vector2(safe.size) / Vector2(screen) * size)
	var factor = minf(available.size.x / 720.0, available.size.y / 1280.0)
	stage.size = Vector2(720, available.size.y / factor if current_page == "game" else 1280.0)
	stage.scale = Vector2.ONE * factor
	stage.position = available.position + (available.size - stage.size * factor) * 0.5
	if page != null:
		page.size = stage.size
	_layout_game()
	if modal != null:
		modal.size = stage.size
		modal.get_child(0).size = stage.size
		var content = modal.get_child(1)
		content.position.y = (stage.size.y - content.size.y) * 0.5

func _layout_game() -> void:
	if current_page != "game" or board == null or model.grills.is_empty():
		return
	var height = stage.size.y
	game_hud.position.y = height * 0.08
	hint_panel.position.y = game_hud.position.y + 108
	combo_label.position.y = hint_panel.position.y + 49
	bottom_ui.position.y = height - 265
	var top = height * 0.266
	var available_height = bottom_ui.position.y - 24 - top
	board.scale = Vector2.ONE
	if model.grills.size() >= 10:
		# Four rows, including the isolated covered grill. Scale only on short screens.
		top = hint_panel.position.y + 96
		available_height = bottom_ui.position.y - 24 - top
		board.row_gap = maxf(212.0, (available_height - 236.0) / 3.0)
		board.scale = Vector2.ONE * minf(1.0, available_height / (board.row_gap * 3.0 + 236.0))
	elif model.grills.size() == 6:
		board.row_gap = 260.0
		top += maxf(0, (available_height - 480) * 0.5)
	else:
		board.row_gap = (available_height - 220) * 0.5
	board.position = Vector2((720 - 720 * board.scale.x) * 0.5, top)
	board.size = Vector2(720, (bottom_ui.position.y - 24 - top) / board.scale.y)

func _process(delta: float) -> void:
	if startup_sampling and startup_foreground:
		var now_usec = Time.get_ticks_usec()
		if startup_sample_last_usec > 0:
			var elapsed = float(now_usec - startup_sample_last_usec) / 1000000.0
			startup_sample_seconds += elapsed
			startup_sample_frames += 1
			startup_sample_max_delta = maxf(startup_sample_max_delta, elapsed)
			if elapsed > 0.05:
				startup_sample_slow_frames += 1
		startup_sample_last_usec = now_usec
		if startup_sample_seconds >= 10.0:
			print("[BBQ frame sample] ", JSON.stringify({"page": current_page,
				"fps": startup_sample_frames / startup_sample_seconds,
				"frames_over_50ms": startup_sample_slow_frames,
				"max_frame_ms": startup_sample_max_delta * 1000.0}))
			startup_sample_seconds = 0.0
			startup_sample_frames = 0
			startup_sample_slow_frames = 0
			startup_sample_max_delta = 0.0
			startup_sample_count += 1
			startup_sampling = startup_sample_count < startup_sample_limit
	ui_clock += delta
	if is_instance_valid(center_toast) and ui_clock >= center_toast_until:
		center_toast.queue_free()
		center_toast = null
	if current_page == "game" and model.level >= 5:
		daily_check += delta
		if daily_check >= 1.0:
			daily_check = 0
			save.refresh_daily()
			_update_bag_badge()
	if current_page == "game":
		model.tick(delta)
		_update_hud(delta)
		if pending_win and not board.has_combo_animations():
			pending_win = false
			audio.play("win")
			_show_result(true)
	if not capture_path.is_empty():
		capture_frames += 1
		if capture_frames == 12:
			_capture.call_deferred()

func _capture() -> void:
	# Capture mode is only an explicit development CLI request.
	if model.state == BoardModel.GameState.PAUSED:
		_resume()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_path)
	get_tree().quit()

func _notification(what: int) -> void:
	# The Web template forwards canvas focus as WINDOW notifications.
	# Native platforms may send both kinds; apply each transition only once.
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		if not startup_foreground:
			return
		startup_foreground = false
		startup_sample_last_usec = 0
		if startup_diagnostics:
			print("[BBQ godot lifecycle] ", JSON.stringify({"foreground": false, "notification": what}))
		if audio != null:
			audio.set_backgrounded(true)
		if haptics != null:
			haptics.set_backgrounded(true)
		if current_page == "game" and model != null and model.active():
			_pause()
	elif what in [NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		if startup_foreground:
			return
		startup_foreground = true
		startup_sample_last_usec = 0
		if startup_diagnostics:
			print("[BBQ godot lifecycle] ", JSON.stringify({"foreground": true, "notification": what}))
		if is_node_ready() and startup_diagnostics:
			startup_sampling = true
			startup_sample_count = 0
			startup_sample_limit = 3
			startup_sample_seconds = 0.0
			startup_sample_frames = 0
			startup_sample_slow_frames = 0
			startup_sample_max_delta = 0.0
			if not startup_resume_pending:
				startup_resume_pending = true
				_report_wechat_resume.call_deferred()
		if audio != null:
			audio.set_backgrounded(false)
		if haptics != null:
			haptics.set_backgrounded(false)

func _input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		audio.unlock()
	if current_page == "game" and board != null and (event is InputEventMouseButton or event is InputEventScreenTouch):
		board.note_pointer(event.pressed)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if current_page == "game":
			if bag_mode != "":
				_close_bag()
			elif model.state == BoardModel.GameState.PAUSED:
				_resume()
			elif model.active():
				_pause()
		else:
			_show_home()

func _new_page(name_value: String) -> void:
	bag_mode = ""
	bag_teaching = false
	bag_button = null
	bag_badge = null
	bag_dialog = null
	if is_instance_valid(center_toast): center_toast.queue_free()
	center_toast = null
	pending_win = false
	audio.reset_effects()
	audio.set_game_paused(false)
	haptics.reset()
	haptics.set_game_paused(false)
	_close_modal()
	if page != null:
		stage.remove_child(page)
		page.queue_free()
	board = null
	current_page = name_value
	page = Control.new()
	page.size = Vector2(720, 1280)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(page)
	_layout()

func _show_home() -> void:
	model.cancel_drag()
	model.state = BoardModel.GameState.INIT
	_new_page("home")
	var settings_button = _button(page, "设置", Rect2(566, 48, 110, 58), _show_settings, false, 24)
	settings_button.name = "SettingsButton"
	var club_button = _button(page, "", Rect2(566, 122, 110, 110), _open_game_club)
	club_button.name = "GameClubButton"
	club_button.tooltip_text = "游戏圈"
	var club_icon = TextureRect.new()
	club_icon.texture = preload("res://assets/ui/game_club.svg")
	club_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	club_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	club_icon.position = Vector2(30, 12)
	club_icon.size = Vector2(50, 50)
	club_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	club_button.add_child(club_icon)
	_label(club_button, "游戏圈", Rect2(4, 68, 102, 30), 23, CREAM)
	_label(page, "人 间 烟 火  ·  一 串 入 魂", Rect2(60, 148, 600, 38), 23, GOLD)
	var title = _label(page, "烧烤消消消", Rect2(30, 206, 660, 112), 76, CREAM)
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color("582517"))
	_label(page, "把喜欢的味道，串在一起。", Rect2(50, 330, 620, 42), 28, CREAM)
	var hero = preload("res://scripts/ui/hero_art.gd").new()
	hero.position = Vector2(75, 398)
	hero.size = Vector2(570, 400)
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(hero)
	var next = save.highest_unlocked
	_button(page, "开 摊 啦   ›", Rect2(128, 836, 464, 98), func(): _start_level(next), true, 35)
	_label(page, "继续第 %d 关  ·  %d / 10 已完成" % [next, save.completed.size()], Rect2(80, 949, 560, 36), 22, CREAM)
	_button(page, "关卡选择", Rect2(186, 1014, 348, 76), _show_levels, false, 28)
	_label(page, "拖动交换  /  三同消除  /  越消越香", Rect2(45, 1180, 630, 34), 21, MUTED)

func _show_levels() -> void:
	_new_page("levels")
	_button(page, "‹ 返回", Rect2(38, 48, 136, 60), _show_home, false, 24)
	_label(page, "夜市小摊", Rect2(50, 190, 620, 80), 57, CREAM)
	_label(page, "十道烟火滋味，等你一一解锁", Rect2(45, 283, 630, 45), 25, GOLD)
	_panel(page, Rect2(38, 405, 644, 582), Color(0.07, 0.14, 0.15, 0.94), 30)
	var names = ["初来乍到", "新鲜上桌", "交换滋味", "双倍满足", "一碟接一碟", "香菇来啦", "串串高手", "茄子飘香", "海味登场", "夜市大厨"]
	for i in range(10):
		var number = i + 1
		var x = 64 + (i % 5) * 120
		var y = 456 + (i / 5) * 241
		var unlocked = number <= save.highest_unlocked
		var label_text = str(number) if unlocked else "·"
		var btn = _button(page, label_text, Rect2(x, y, 110, 111), func(): _start_level(number), unlocked, 38)
		btn.disabled = not unlocked
		var status = "已完成" if number in save.completed else ("可挑战" if unlocked else "未解锁")
		_label(page, status, Rect2(x - 2, y + 124, 114, 32), 20, GOLD if unlocked else MUTED)
		_label(page, names[i], Rect2(x - 4, y + 163, 118, 30), 17, MUTED)
	_label(page, "完成当前关卡，即可解锁下一摊", Rect2(50, 1080, 620, 42), 24, CREAM)

func _start_level(number: int) -> void:
	var config = LevelLoader.load_level(number)
	if config.is_empty():
		return
	_new_page("game")
	shown_matches = 0
	progress_elapsed = 0
	last_warning = -1
	toast_until = 0
	combo_until = 0
	save.last_selected = number
	run_id = save.begin_run()
	win_reward = false
	if number >= 5: save.refresh_daily()
	game_hud = Control.new()
	game_hud.name = "GameHUD"
	game_hud.size = Vector2(720, 84)
	game_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(game_hud)
	_panel(game_hud, Rect2(132, 12, 122, 55), Color(0.10, 0.18, 0.25, 0.68), 13, Color(0.62, 0.74, 0.80, 0.25))
	var level_label = _label(game_hud, "LV.%d" % number, Rect2(133, 12, 120, 55), 34, CREAM)
	_hud_number_style(level_label)
	var timer_frame = TextureRect.new()
	timer_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	timer_frame.texture = preload("res://assets/ui/hud_timer.svg")
	timer_frame.position = Vector2(264, 3)
	timer_frame.size = Vector2(190, 74)
	timer_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_hud.add_child(timer_frame)
	timer_label = _label(game_hud, "01:15", Rect2(322, 9, 122, 59), 37, CREAM)
	_hud_number_style(timer_label)
	_panel(game_hud, Rect2(466, 12, 124, 55), Color(0.10, 0.18, 0.25, 0.68), 13, Color(0.62, 0.74, 0.80, 0.25))
	progress_label = _label(game_hud, "0/5", Rect2(468, 12, 120, 55), 34, CREAM)
	_hud_number_style(progress_label)
	var pause_button = _texture_button(game_hud, preload("res://assets/ui/pause.svg"), Rect2(29, 0, 82, 82))
	pause_button.name = "PauseButton"
	pause_button.pressed.connect(_pause)
	hint_panel = _panel(page, Rect2(42, 0, 636, 44), Color(0.06, 0.12, 0.13, 0.78), 14)
	hint_label = _label(hint_panel, "同一烤架凑齐 3 串相同食材，即可出炉", Rect2(7, 0, 622, 44), 21, CREAM)
	board = BoardView.new()
	page.add_child(board)
	board.bind(model)
	combo_label = _label(page, "", Rect2(35, 0, 650, 44), 29, GOLD)
	bottom_ui = Control.new()
	bottom_ui.name = "BottomReservedArea"
	bottom_ui.size = Vector2(720, 265)
	bottom_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bottom_ui)
	for i in range(4):
		var slot = _texture_button(bottom_ui, preload("res://assets/ui/locked_slot.svg"), Rect2(72 + i * 152, 0, 120, 124))
		slot.name = "ReservedFunction%d" % (i + 1)
		slot.disabled = true
		slot.focus_mode = Control.FOCUS_NONE
		if i == 0 and number >= 5:
			bag_button = slot
			slot.texture_normal = preload("res://assets/ui/bag_slot.svg")
			slot.texture_disabled = slot.texture_normal
			slot.disabled = false
			slot.pressed.connect(_open_bag)
			BagDialog.art(slot, preload("res://assets/art/takeaway-bag.png"), Rect2(18, 9, 84, 94))
			var badge = _panel(slot, Rect2(83, 88, 40, 35), Color("c63225"), 18, CREAM)
			bag_badge = _label(badge, "", Rect2(0, 0, 40, 35), 24, Color.WHITE)
			_update_bag_badge()
	# Empty banner reservation, matching the reference banner's ~6.6:1 ratio.
	var ad_space = Control.new()
	ad_space.name = "AdSlot"
	ad_space.position = Vector2(76, 145)
	ad_space.size = Vector2(568, 86)
	ad_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_ui.add_child(ad_space)
	model.start(config)
	_layout_game()
	_update_hud(0)
	if number >= 5 and not save.bag_tutorial_done: _show_bag_unlock()

func _hud_number_style(label: Label) -> void:
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color("142536"))
	label.add_theme_constant_override("shadow_offset_y", 3)

func _texture_button(parent: Control, texture: Texture2D, rect: Rect2) -> TextureButton:
	var button = TextureButton.new()
	button.position = rect.position
	button.size = rect.size
	button.texture_normal = texture
	button.texture_disabled = texture
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	return button

func _update_hud(delta: float) -> void:
	if timer_label == null or not is_instance_valid(timer_label):
		return
	timer_label.text = _time_text(model.remaining)
	timer_label.add_theme_color_override("font_color", Color("ff9065") if model.remaining <= 30 else CREAM)
	if model.remaining <= 10 and model.state == BoardModel.GameState.PLAYING:
		timer_label.modulate.a = 0.72 + absf(sin(model.clock * 5)) * 0.28
		var second = ceili(model.remaining)
		if second != last_warning:
			last_warning = second
			audio.play("warning")
	else:
		timer_label.modulate.a = 1
	if model.active():
		progress_elapsed += delta
		if shown_matches < model.matches and progress_elapsed >= 0.10:
			shown_matches += 1
			progress_elapsed = 0
	if model.state == BoardModel.GameState.WIN:
		shown_matches = model.matches
	progress_label.text = "%d/%d" % [shown_matches, model.total_matches]
	if model.clock >= combo_until:
		combo_label.text = ""
	if model.clock >= toast_until:
		if model.state == BoardModel.GameState.TUTORIAL:
			hint_label.text = "拖动玉米，凑齐 3 个相同食材 · 计时暂停" if model.tutorial == "MOVE" else "拖到另一串食材上，交换位置 · 计时暂停"
		elif model.grills.size() == 10 and model.grills[6].state == BoardModel.GrillState.LOCKED:
			hint_label.text = "三消玉米，打开中间的锅盖"
		else:
			hint_label.text = "拖到食材上可交换，拖到空位可移动"

func _on_model_event(kind: String, detail: Dictionary) -> void:
	match kind:
		"started":
			audio.reset_effects()
			haptics.reset()
		"paused":
			audio.set_game_paused(true)
			haptics.set_game_paused(true)
		"resumed":
			audio.set_game_paused(false)
			haptics.set_game_paused(false)
		"pick", "cancel": audio.play(kind)
		"refill": audio.refill(model.grills[detail.grill].refill_foods.size())
		"lid_opening": audio.schedule("lid", detail.get("delay", BoardModel.LID_OPEN_DELAY))
		"transfer":
			audio.play("move")
			audio.schedule("swap" if detail.swap else "drop", 0.16)
		"match":
			audio.match_food(detail.combo)
			haptics.match_food(detail.combo, detail.double)
			combo_label.text = "双重消除！  连消 ×%d" % detail.combo if detail.double else ("好香！  连消 ×%d" % detail.combo if detail.combo > 1 else "滋啦～  美味出炉！")
			combo_until = model.clock + 1.2
		"pack":
			audio.play("bag")
			audio.schedule("gather", 0.15)
			audio.schedule("match", 0.7)
			haptics.match_food(detail.combo, false, 0.7)
			combo_label.text = "打包出炉！" if detail.combo < 3 else "打包出炉！ 连消 ×%d" % detail.combo
			combo_until = model.clock + 1.6
		"pack_finished":
			board.reset_hint()
		"refill_tip":
			hint_label.text = "烤架清空后，下方食材会自动补上"
			toast_until = model.clock + 1.5
		"tutorial_done":
			hint_label.text = "就是这样！开动脑筋，让美味一起出炉"
			toast_until = model.clock + 2
		"win":
			win_reward = save.complete_level(model.level, run_id)
			pending_win = true
		"fail":
			audio.reset_effects()
			haptics.reset()
			audio.play("fail")
			_show_result(false)

func _pause() -> void:
	if not model.active():
		return
	model.pause()
	var content = _open_modal("歇一歇，再开烤", "美味不急，时间已经暂停", 694)
	_button(content, "继续游戏", Rect2(62, 174, 432, 79), _resume, true)
	_button(content, "重新开始", Rect2(62, 272, 432, 72), func(): _start_level(model.level))
	_button(content, "返回首页", Rect2(62, 363, 432, 72), _show_home)
	_settings_buttons(content, 472)

func _resume() -> void:
	if bag_mode != "":
		_close_bag()
		return
	_close_modal()
	model.resume()

func _show_settings() -> void:
	var content = _open_modal("小摊设置", "调成你喜欢的节奏", 485)
	_settings_buttons(content, 177)
	_button(content, "好，知道啦", Rect2(62, 343, 432, 76), _close_modal, true)

func _open_game_club() -> void:
	if OS.has_feature("wechat"):
		var bridge = JavaScriptBridge.get_interface("bbqGameClub")
		if bridge != null:
			bridge.open()
			return
	var content = _open_modal("游戏圈", "请在微信中打开游戏圈", 300)
	_button(content, "知道了", Rect2(62, 189, 432, 72), _close_modal, true)

func _settings_buttons(parent: Control, y: float) -> void:
	var music_button = _button(parent, "音乐 " + ("开" if save.music_enabled else "关"), Rect2(42, y, 148, 70), func(): pass, false, 23)
	music_button.pressed.connect(func():
		save.music_enabled = not save.music_enabled
		audio.music_enabled = save.music_enabled
		music_button.text = "音乐 " + ("开" if save.music_enabled else "关")
		save.save_progress())
	var sound_button = _button(parent, "音效 " + ("开" if save.audio_enabled else "关"), Rect2(204, y, 148, 70), func(): pass, false, 23)
	sound_button.pressed.connect(func():
		save.audio_enabled = not save.audio_enabled
		audio.enabled = save.audio_enabled
		sound_button.text = "音效 " + ("开" if save.audio_enabled else "关")
		save.save_progress()
		audio.play("pick"))
	var vibration_button = _button(parent, "震动 " + ("开" if save.vibration_enabled else "关"), Rect2(366, y, 148, 70), func(): pass, false, 23)
	vibration_button.pressed.connect(func():
		save.vibration_enabled = not save.vibration_enabled
		haptics.enabled = save.vibration_enabled
		haptics.preview()
		vibration_button.text = "震动 " + ("开" if save.vibration_enabled else "关")
		save.save_progress())
	_label(parent, "震动将在支持的移动设备上生效", Rect2(45, y + 88, 466, 35), 19, MUTED)

func _show_result(won: bool) -> void:
	var title = ("全部通关！" if model.level == 10 else "美味出炉！") if won else "时间到！"
	var subtitle = "第 %d 关完成  ·  用时 %s" % [model.level, _time_text(model.time_limit - model.remaining)] if won else "已经完成 %d / %d 组，再试一次吧" % [model.matches, model.total_matches]
	var content = _open_modal(title, subtitle, 610 if won else 500)
	_label(content, ("本局获得 +50 金币" if win_reward else "今夜，你就是夜市大厨。") if won else "好味道，值得再来一串。", Rect2(38, 153, 480, 48), 26, GOLD)
	if won:
		_button(content, "下一关" if model.level < 10 else "回到关卡选择", Rect2(62, 241, 432, 79), func():
			if model.level < 10: _start_level(model.level + 1)
			else: _show_levels(), true)
		_button(content, "再玩一次", Rect2(62, 341, 432, 74), func(): _start_level(model.level))
		_button(content, "返回首页", Rect2(62, 437, 432, 74), _show_home)
	else:
		_button(content, "再试一次", Rect2(62, 241, 432, 79), func(): _start_level(model.level), true)
		_button(content, "返回首页", Rect2(62, 342, 432, 74), _show_home)

func _open_modal(title: String, subtitle: String, height: float) -> Control:
	_close_modal()
	modal = Control.new()
	modal.size = stage.size
	stage.add_child(modal)
	var backdrop = ColorRect.new()
	backdrop.size = modal.size
	backdrop.color = Color(0.025, 0.04, 0.045, 0.78)
	modal.add_child(backdrop)
	var content = _panel(modal, Rect2(82, (stage.size.y - height) * 0.5, 556, height), Color("1e3335"), 28, Color("a98b57"))
	_label(content, title, Rect2(30, 40, 496, 67), 42, CREAM)
	_label(content, subtitle, Rect2(30, 113, 496, 40), 22, MUTED)
	return content

func _close_modal() -> void:
	if modal != null:
		stage.remove_child(modal)
		modal.queue_free()
		modal = null

func _time_text(value: float) -> String:
	var seconds = ceili(value)
	return "%02d:%02d" % [seconds / 60, seconds % 60]

func _style(color: Color, radius: int, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	if border.a > 0:
		style.set_border_width_all(2)
		style.border_color = border
	return style

func _panel(parent: Control, rect: Rect2, color: Color, radius: int = 18, border: Color = Color.TRANSPARENT) -> Panel:
	var panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = _style(color, radius, border)
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 5)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _label(parent: Control, text_value: String, rect: Rect2, font_size: int, color: Color, alignment: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label = Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text_value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.06, 0.03, 0.02, 0.65))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Control, text_value: String, rect: Rect2, action: Callable, primary: bool = false, font_size: int = 28) -> Button:
	var button = Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = text_value
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color("492b1a") if primary else CREAM)
	button.add_theme_color_override("font_hover_color", Color("492b1a") if primary else CREAM)
	button.add_theme_color_override("font_pressed_color", Color("492b1a") if primary else CREAM)
	var normal = _style(Color("f6bb62") if primary else Color("28454a"), 20, Color("ffe1a2") if primary else Color("567075"))
	normal.shadow_color = Color("79451e") if primary else Color("102126")
	normal.shadow_size = 1
	normal.shadow_offset = Vector2(0, 6)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", _style(Color("ffd18a") if primary else Color("36575a"), 20, GOLD))
	button.add_theme_stylebox_override("pressed", _style(Color("dca052") if primary else Color("1b3338"), 20, GOLD))
	button.add_theme_stylebox_override("disabled", _style(Color("2e3b3b"), 20, Color("53605b")))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, 20, GOLD))
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _update_bag_badge() -> void:
	if not is_instance_valid(bag_badge): return
	var count = save.available_bags()
	bag_badge.text = str(count) if count > 0 else "+"
	var panel = bag_badge.get_parent()
	panel.add_theme_stylebox_override("panel", _style(Color("c63225") if count > 0 else Color("4f9f27"), 18, CREAM))

func _show_bag_unlock() -> void:
	bag_teaching = true
	bag_mode = "unlock"
	model.pause()
	var content = _open_modal("新道具解锁", "打包袋 · 任意打包一种烤串", 420)
	BagDialog.art(content, preload("res://assets/art/takeaway-bag.png"), Rect2(190, 165, 176, 180))
	_label(content, "赠送 1 次！点击下方打包袋试试", Rect2(23, 352, 510, 42), 26, GOLD)
	var position_y = bottom_ui.position.y
	var spotlight = _texture_button(modal, preload("res://assets/ui/bag_slot.svg"), Rect2(72, position_y, 120, 124))
	spotlight.name = "BagUnlock"
	BagDialog.art(spotlight, preload("res://assets/art/takeaway-bag.png"), Rect2(18, 9, 84, 94))
	var lock = BagDialog.art(spotlight, preload("res://assets/ui/locked_slot.svg"), Rect2(0, 0, 120, 124))
	var unlock = lock.create_tween()
	unlock.tween_property(lock, "modulate:a", 0.0, 0.35).set_delay(0.12)
	unlock.tween_callback(lock.queue_free)
	spotlight.pressed.connect(func(): _show_bag_dialog(false))
	_label(spotlight, "免费", Rect2(8, 95, 104, 33), 24, CREAM)
	var arrow = _label(modal, "↓", Rect2(84, position_y - 78, 96, 75), 69, GOLD)
	BagDialog.outline(arrow, 5)
	var tween = arrow.create_tween().set_loops()
	tween.tween_property(arrow, "position:y", position_y - 66, 0.35)
	tween.tween_property(arrow, "position:y", position_y - 78, 0.35)
	spotlight.pivot_offset = spotlight.size * 0.5
	var reveal = spotlight.create_tween()
	spotlight.scale = Vector2.ONE * 0.3
	reveal.tween_property(spotlight, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _open_bag() -> void:
	if not model.active() or model.pack_until >= 0: return
	save.refresh_daily()
	bag_teaching = false
	model.pause()
	_show_bag_dialog(save.available_bags() == 0)

func _show_bag_dialog(shop: bool) -> void:
	var old = _open_modal("", "", 890)
	modal.remove_child(old)
	old.queue_free()
	bag_mode = "shop" if shop else "use"
	bag_dialog = BagDialog.new()
	bag_dialog.position = Vector2(60, (stage.size.y - 890) * 0.5)
	modal.add_child(bag_dialog)
	bag_dialog.setup(self, shop, bag_teaching)
	bag_dialog.add_wallet(self, modal)
	bag_dialog.closed.connect(_close_bag)
	bag_dialog.used.connect(_use_bag)
	bag_dialog.exchanged.connect(_exchange_bag)
	bag_dialog.ad_requested.connect(_request_bag_ad)
	bag_dialog.pivot_offset = bag_dialog.size * 0.5
	bag_dialog.scale = Vector2.ONE * 0.94
	var tween = bag_dialog.create_tween()
	tween.tween_property(bag_dialog, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _close_bag() -> void:
	if bag_teaching: return
	bag_mode = ""
	bag_dialog = null
	_close_modal()
	model.resume()
	_update_bag_badge()

func _use_bag() -> void:
	if bag_mode != "use" or model.state != BoardModel.GameState.PAUSED: return
	var choice = model.pack_candidate("C" if bag_teaching else "")
	if choice.is_empty():
		_show_center_toast("食材正在整理，请稍后再试")
		_close_bag()
		return
	var teaching = bag_teaching
	if not save.consume_bag(teaching):
		_show_center_toast("次数不足或存档失败，请稍后再试")
		return
	bag_teaching = false
	_close_bag()
	# No await between the validated selection, persisted debit and model commit.
	model.pack_food(choice.food, teaching)
	_update_bag_badge()

func _exchange_bag() -> void:
	if bag_mode != "shop": return
	var result = save.buy_bag()
	if result == ERR_UNAVAILABLE:
		_show_center_toast("金币不足，通关可获得金币")
	elif result != OK:
		_show_center_toast("保存失败，请稍后再试")
	else:
		_close_bag()
		_show_center_toast("兑换成功，打包袋 +1")

func _request_bag_ad() -> void:
	# The rewarded-video slot is intentionally unconfigured until an ad ID arrives.
	# A future completed-view callback must credit persistent stock, never auto-use.
	_show_center_toast("广告尚未准备好")

func _show_center_toast(message: String) -> void:
	if is_instance_valid(center_toast):
		stage.remove_child(center_toast)
		center_toast.queue_free()
	center_toast = _panel(stage, Rect2(94, stage.size.y * 0.5 - 40, 532, 80), Color(0.04, 0.035, 0.03, 0.94), 17)
	center_toast.name = "CenterToast"
	_label(center_toast, message, Rect2(12, 10, 508, 60), 27, Color.WHITE)
	center_toast_until = ui_clock + 2.0
