class_name BagDialog
extends Control

signal closed
signal used
signal exchanged
signal ad_requested

const BAG = preload("res://assets/art/takeaway-bag.png")
var wallet: Label
var use_button: TextureButton

func setup(app: Control, shop: bool, teaching: bool) -> void:
	size = Vector2(600, 890)
	art(self, preload("res://assets/ui/bag_panel.svg"), Rect2(Vector2.ZERO, size))
	var title = app._label(self, "打包袋", Rect2(104, 50, 392, 85), 59, app.CREAM)
	outline(title, 7)
	var close_button = app._button(self, "×", Rect2(530, 65, 65, 65), func(): closed.emit(), false, 47)
	close_button.name = "BagClose"
	for key in ["normal", "hover", "pressed"]:
		var style = app._style(Color("d43925") if key != "pressed" else Color("9f2018"), 34, Color("ffdf9b"))
		style.set_border_width_all(5)
		close_button.add_theme_stylebox_override(key, style)
	close_button.visible = not teaching
	art(self, BAG, Rect2(153, 190, 284, 320))
	var quantity = app._label(self, "×1", Rect2(384, 416, 112, 73), 52, Color("fff7df"))
	outline(quantity, 7)
	var description = app._label(self, "任意打包一种烤串！", Rect2(50, 533, 500, 54), 35, Color.WHITE)
	outline(description, 5)
	if shop:
		var buy = decorated_button(app, "300", Rect2(80, 605, 440, 126), false, func(): exchanged.emit())
		buy.name = "BagBuy"
		art(buy, preload("res://assets/ui/coin.svg"), Rect2(94, 25, 66, 72))
		var ad = decorated_button(app, "看视频 +1", Rect2(80, 742, 440, 126), true, func(): ad_requested.emit())
		ad.name = "BagAd"
		art(ad, preload("res://assets/ui/video.svg"), Rect2(81, 22, 85, 77))
	else:
		var tip = "首次解锁赠送 1 次，快试试吧！" if teaching else "可用 %d 次 · 本次收取同类三串" % app.save.available_bags()
		app._label(self, tip, Rect2(42, 606, 516, 50), 25, app.CREAM)
		use_button = decorated_button(app, "使用", Rect2(80, 713, 440, 126), false, func(): used.emit())
		use_button.name = "BagUse"
		if teaching:
			var arrow = app._label(self, "↓", Rect2(250, 651, 100, 64), 59, app.GOLD)
			outline(arrow, 5)
			var tween = create_tween().set_loops()
			tween.tween_property(arrow, "position:y", 660.0, 0.35)
			tween.tween_property(arrow, "position:y", 651.0, 0.35)

func add_wallet(app: Control, parent: Control) -> void:
	var bar = app._panel(parent, Rect2(56, 25, 174, 53), Color("fff1d9"), 16, Color("d79a4f"))
	bar.name = "CoinWallet"
	wallet = app._label(bar, str(app.save.coins), Rect2(45, 1, 122, 50), 30, Color("553222"))
	art(bar, preload("res://assets/ui/coin.svg"), Rect2(-12, -8, 64, 68))

static func art(parent: Node, texture: Texture2D, rect: Rect2) -> TextureRect:
	var image = TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.position = rect.position
	image.size = rect.size
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

static func outline(label: Label, width: int) -> void:
	label.add_theme_constant_override("outline_size", width)
	label.add_theme_color_override("font_outline_color", Color("54301e"))

func decorated_button(app: Control, text: String, rect: Rect2, orange: bool, action: Callable) -> TextureButton:
	var texture = preload("res://assets/ui/bag_orange.svg") if orange else preload("res://assets/ui/bag_green.svg")
	var button = app._texture_button(self, texture, rect)
	button.pressed.connect(action)
	button.button_down.connect(func(): button.modulate = Color(0.85, 0.85, 0.85))
	button.button_up.connect(func(): button.modulate = Color.WHITE)
	var label = app._label(button, text, Rect2(150 if text != "使用" else 0, 22, 225 if text != "使用" else 440, 77), 55, Color("fffce5"))
	if text == "看视频 +1": label.add_theme_font_size_override("font_size", 36)
	outline(label, 6)
	return button
