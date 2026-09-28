extends Control

var foreground = true
var pending_frame = false
var texture = preload("res://probe.svg")
var taps = 0

func _ready() -> void:
	label("RENDER / REENTRY PROBE", Vector2(28, 45), 38)
	label("Every labeled box below must be visible.", Vector2(28, 105))
	label("1  Texture image", Vector2(28, 170))
	var picture = TextureRect.new()
	picture.texture = texture
	picture.position = Vector2(40, 215)
	picture.size = Vector2(260, 115)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(picture)
	label("2  Solid / transparent ColorRect", Vector2(28, 365))
	for i in range(2):
		var box = ColorRect.new()
		box.position = Vector2(40 + i * 320, 410)
		box.size = Vector2(260, 115)
		box.color = Color(0.2, 0.8, 0.6, 1.0 if i == 0 else 0.5)
		add_child(box)
	label("3  StyleBoxFlat / rounded + shadow", Vector2(28, 560))
	for i in range(2):
		var panel = Panel.new()
		panel.position = Vector2(40 + i * 320, 605)
		panel.size = Vector2(260, 115)
		var style = StyleBoxFlat.new()
		style.bg_color = Color("edb54e")
		style.set_corner_radius_all(24 * i)
		style.shadow_color = Color(0, 0, 0, 0.8)
		style.shadow_size = 12 * i
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
	label("4  draw_rect / draw_circle", Vector2(28, 755))
	label("5  Styled button (tap to test input)", Vector2(28, 975))
	var button = Button.new()
	button.position = Vector2(40, 1030)
	button.size = Vector2(580, 100)
	button.text = "Tap count: 0"
	button.add_theme_font_size_override("font_size", 32)
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = Color("286484")
	button_style.set_corner_radius_all(20)
	button.add_theme_stylebox_override("normal", button_style)
	button.pressed.connect(func():
		taps += 1
		button.text = "Tap count: %d" % taps)
	add_child(button)
	label("Test both first launch and return from WeChat.", Vector2(28, 1180), 25)
	print("[BBQ scene ready] minimal ", size)
	await RenderingServer.frame_post_draw
	print("[BBQ first frame]")

func label(text: String, position_value: Vector2, font_size: int = 29) -> void:
	var item = Label.new()
	item.text = text
	item.position = position_value
	item.add_theme_font_size_override("font_size", font_size)
	add_child(item)

func _draw() -> void:
	draw_rect(Rect2(40, 815, 260, 115), Color("d77a50"))
	draw_circle(Vector2(490, 873), 57, Color("d77a50"))

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		foreground = false
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		if not foreground and is_node_ready() and not pending_frame:
			pending_frame = true
			report_resume.call_deferred()
		foreground = true

func report_resume() -> void:
	await RenderingServer.frame_post_draw
	pending_frame = false
	if foreground: print("[BBQ resume frame] probe")
