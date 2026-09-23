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

func _ready() -> void:
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
	if model.grills.size() == 6:
		board.row_gap = 260.0
		top += maxf(0, (available_height - 480) * 0.5)
	else:
		board.row_gap = (available_height - 220) * 0.5
	board.position = Vector2(0, top)
	board.size = Vector2(720, bottom_ui.position.y - 24 - top)

func _process(delta: float) -> void:
	ui_clock += delta
	if current_page == "game":
		model.tick(delta)
		_update_hud(delta)
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
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		if current_page == "game" and model != null and model.active():
			_pause()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if current_page == "game":
			if model.state == BoardModel.GameState.PAUSED:
				_resume()
			elif model.active():
				_pause()
		else:
			_show_home()

func _new_page(name_value: String) -> void:
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
	_button(page, "设置", Rect2(566, 48, 110, 58), _show_settings, false, 24)
	_label(page, "人 间 烟 火  ·  一 串 入 魂", Rect2(60, 148, 600, 38), 23, GOLD)
	var title = _label(page, "烧烤串串消", Rect2(30, 206, 660, 112), 76, CREAM)
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
	save.save_progress()
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
	var pause_button = _texture_button(game_hud, preload("res://assets/ui/pause.svg"), Rect2(609, 0, 82, 82))
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
		else:
			hint_label.text = "拖到食材上可交换，拖到空位可移动"

func _on_model_event(kind: String, detail: Dictionary) -> void:
	match kind:
		"pick", "cancel", "refill": audio.play(kind)
		"transfer": audio.play("swap" if detail.swap else "drop")
		"match":
			audio.play("combo" if detail.combo > 1 else "match")
			if save.vibration_enabled and (OS.has_feature("android") or OS.has_feature("ios")):
				Input.vibrate_handheld(22)
			combo_label.text = "双重消除！  连消 ×%d" % detail.combo if detail.double else ("好香！  连消 ×%d" % detail.combo if detail.combo > 1 else "滋啦～  美味出炉！")
			combo_until = model.clock + 1.2
		"refill_tip":
			hint_label.text = "烤架清空后，下方食材会自动补上"
			toast_until = model.clock + 1.5
		"tutorial_done":
			hint_label.text = "就是这样！开动脑筋，让美味一起出炉"
			toast_until = model.clock + 2
		"win":
			save.complete_level(model.level)
			audio.play("win")
			_show_result(true)
		"fail":
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
	_close_modal()
	model.resume()

func _show_settings() -> void:
	var content = _open_modal("小摊设置", "调成你喜欢的节奏", 485)
	_settings_buttons(content, 177)
	_button(content, "好，知道啦", Rect2(62, 343, 432, 76), _close_modal, true)

func _settings_buttons(parent: Control, y: float) -> void:
	var sound_button = _button(parent, "音效  " + ("开" if save.audio_enabled else "关"), Rect2(62, y, 204, 70), func(): pass, false, 24)
	sound_button.pressed.connect(func():
		save.audio_enabled = not save.audio_enabled
		audio.enabled = save.audio_enabled
		sound_button.text = "音效  " + ("开" if save.audio_enabled else "关")
		save.save_progress()
		audio.play("pick"))
	var vibration_button = _button(parent, "震动  " + ("开" if save.vibration_enabled else "关"), Rect2(290, y, 204, 70), func(): pass, false, 24)
	vibration_button.pressed.connect(func():
		save.vibration_enabled = not save.vibration_enabled
		vibration_button.text = "震动  " + ("开" if save.vibration_enabled else "关")
		save.save_progress())
	_label(parent, "震动将在支持的移动设备上生效", Rect2(45, y + 88, 466, 35), 19, MUTED)

func _show_result(won: bool) -> void:
	var title = ("全部通关！" if model.level == 10 else "美味出炉！") if won else "时间到！"
	var subtitle = "第 %d 关完成  ·  用时 %s" % [model.level, _time_text(model.time_limit - model.remaining)] if won else "已经完成 %d / %d 组，再试一次吧" % [model.matches, model.total_matches]
	var content = _open_modal(title, subtitle, 610 if won else 500)
	_label(content, "今夜，你就是夜市大厨。" if won else "好味道，值得再来一串。", Rect2(38, 153, 480, 48), 26, GOLD)
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
