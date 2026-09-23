class_name BoardView
extends Control

var model: BoardModel
var pointer = Vector2.ZERO
var hover = Vector2i(-1, -1)
var hover_version = -1
var motions: Array = []
var bursts: Array = []
var tutorial_visible = true
var row_gap = 220.0
var font: Font
var glow_style: StyleBoxFlat
var hover_style: StyleBoxFlat
var plate_style: StyleBoxFlat
var stacked_plate_style: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = load("res://assets/fonts/game.ttf")
	glow_style = StyleBoxFlat.new()
	glow_style.bg_color = Color(1, 0.48, 0.05, 0.23)
	glow_style.set_corner_radius_all(26)
	glow_style.shadow_color = Color(1, 0.53, 0.05, 0.5)
	glow_style.shadow_size = 16
	hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(1, 0.77, 0.36, 0.14)
	hover_style.border_color = Color("ffce70")
	hover_style.set_border_width_all(2)
	hover_style.set_corner_radius_all(18)
	plate_style = StyleBoxFlat.new()
	plate_style.bg_color = Color("eee2cd")
	plate_style.border_color = Color("fff8e8")
	plate_style.set_border_width_all(3)
	plate_style.set_corner_radius_all(9)
	plate_style.shadow_color = Color(0.13, 0.07, 0.03, 0.4)
	plate_style.shadow_size = 3
	plate_style.shadow_offset = Vector2(0, 4)
	stacked_plate_style = plate_style.duplicate()
	stacked_plate_style.bg_color = Color("b7a996")

func bind(value: BoardModel) -> void:
	model = value
	model.event.connect(_on_event)

func grill_rect(index: int) -> Rect2:
	var row = index / 3
	var column = index % 3
	return Rect2(15.0 + column * 234.0, 16.0 + row * row_gap, 222.0, 156.0)

func slot_center(index: int, slot: int) -> Vector2:
	var rect = grill_rect(index)
	return rect.position + Vector2(47 + slot * 64, 70)

func plate_center(index: int) -> Vector2:
	return grill_rect(index).position + Vector2(111, 182)

func hit(point: Vector2) -> Vector2i:
	for index in range(model.grills.size()):
		var rect = grill_rect(index).grow(3)
		if rect.has_point(point):
			var slot = clampi(roundi((point.x - rect.position.x - 50) / 64.0), 0, 2)
			return Vector2i(index, slot)
	return Vector2i(-1, -1)

func _gui_input(event: InputEvent) -> void:
	if model == null or not model.active():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pointer = event.position
		var target = hit(pointer)
		if target.x >= 0:
			model.begin_drag(target.x, target.y)
		accept_event()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or model == null or model.drag.is_empty():
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		pointer = get_global_transform_with_canvas().affine_inverse() * event.position
		var target = hit(pointer)
		if target != hover:
			hover = target
			hover_version = model.grills[target.x].version if target.x >= 0 else -1
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			model.drop(hover.x, hover.y, hover_version)
			hover = Vector2i(-1, -1)
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if model != null and is_visible_in_tree():
		motions = motions.filter(func(m): return model.clock - m.start < m.duration and m.epoch == model.epoch)
		bursts = bursts.filter(func(b): return model.clock - b.start < 0.65)
		queue_redraw()

func _on_event(kind: String, detail: Dictionary) -> void:
	match kind:
		"started":
			motions.clear()
			bursts.clear()
			hover = Vector2i(-1, -1)
		"transfer":
			motions.append({"food": detail.food, "from": pointer + Vector2(0, -24),
				"to": slot_center(detail.target, detail.target_slot), "grill": detail.target,
				"slot": detail.target_slot, "start": model.clock, "duration": 0.20, "epoch": model.epoch})
			if detail.swap:
				motions.append({"food": detail.displaced, "from": slot_center(detail.target, detail.target_slot),
					"to": slot_center(detail.source, detail.source_slot), "grill": detail.source,
					"slot": detail.source_slot, "start": model.clock, "duration": 0.20, "epoch": model.epoch})
		"cancel":
			motions.append({"food": detail.food, "from": pointer + Vector2(0, -24),
				"to": slot_center(detail.grill, detail.slot), "grill": detail.grill,
				"slot": detail.slot, "start": model.clock, "duration": 0.16, "epoch": model.epoch})
		"match":
			bursts.append({"grill": detail.grill, "start": model.clock})

func _draw() -> void:
	if model == null:
		return
	for index in range(model.grills.size()):
		_draw_grill(index)
	for burst in bursts:
		var age = model.clock - burst.start
		var center = grill_rect(burst.grill).get_center()
		for particle in range(14):
			var angle = particle * TAU / 14.0
			var distance = 22 + age * (110 + (particle % 3) * 38)
			var point = center + Vector2(cos(angle), sin(angle)) * distance
			point.y -= age * 34
			draw_circle(point, maxf(1, 4 - age * 4), Color(1.0, 0.65 + (particle % 2) * 0.25, 0.22, 1.0 - age / 0.65))
	for motion in motions:
		var progress = clampf((model.clock - motion.start) / motion.duration, 0, 1)
		var eased = 1.0 - pow(1.0 - progress, 3)
		var center = motion.from.lerp(motion.to, eased) + Vector2(0, -sin(progress * PI) * 22)
		_draw_food(motion.food, center, Vector2(62, 156), Color.WHITE)
	if not model.drag.is_empty():
		var center = pointer + Vector2(0, -24)
		_draw_food(model.drag.food, center + Vector2(6, 12), Vector2(69, 169), Color(0.05, 0.025, 0.01, 0.4))
		_draw_food(model.drag.food, center, Vector2(69, 169), Color.WHITE)
	if model.state == BoardModel.GameState.TUTORIAL and tutorial_visible and model.drag.is_empty():
		_draw_tutorial()

func _draw_grill(index: int) -> void:
	var grill = model.grills[index]
	var rect = grill_rect(index)
	var active_match = grill.state in [BoardModel.GrillState.MATCHING, BoardModel.GrillState.CLEARING]
	if active_match:
		draw_style_box(glow_style, rect.grow(3))
	draw_texture_rect(FoodArt.grill(), rect, false)
	# A small coal glow under the grid makes a matched grill feel hot.
	if active_match:
		draw_rect(Rect2(rect.position + Vector2(33, 53), Vector2(156, 70)), Color(1, 0.27, 0.02, 0.20))
	for slot in range(3):
		var center = slot_center(index, slot)
		var food = grill.slots[slot]
		var target_hover = hover == Vector2i(index, slot) and not model.drag.is_empty() and model.drag.grill != index and model.can_touch(index)
		if target_hover:
			draw_style_box(hover_style, Rect2(center - Vector2(31, 72), Vector2(62, 144)))
		if food == "":
			draw_circle(center, 8, Color(1, 0.86, 0.63, 0.15))
			continue
		var dragging = not model.drag.is_empty() and model.drag.grill == index and model.drag.slot == slot
		var in_motion = false
		for motion in motions:
			if motion.grill == index and motion.slot == slot:
				in_motion = true
		if in_motion:
			continue
		var tint = Color(1, 1, 1, 0.18) if dragging else Color.WHITE
		var food_size = Vector2(60, 153) * (1.08 if target_hover else 1.0)
		if grill.state == BoardModel.GrillState.MATCHING:
			food_size *= 1.0 + grill.elapsed / 0.08 * 0.10
		elif grill.state == BoardModel.GrillState.CLEARING:
			var progress = clampf(grill.elapsed / 0.22, 0, 1)
			food_size *= lerpf(1.1, 0.15, progress * progress)
			tint.a = 1.0 - progress * progress
		elif grill.state == BoardModel.GrillState.REFILLING:
			var progress = clampf(grill.elapsed / 0.32, 0, 1)
			var origin = plate_center(index) + Vector2((slot - 1) * 34, 0)
			center = origin.lerp(center, 1.0 - pow(1.0 - progress, 3))
			food_size *= lerpf(0.35, 1.0, progress)
		_draw_food(food, center, food_size, tint)
	_draw_plate(index)

func _draw_plate(index: int) -> void:
	var queue = model.grills[index].queue
	var center = plate_center(index)
	if queue.is_empty():
		draw_string(font, center + Vector2(-30, 8), "已上齐", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.86, 0.64, 0.55))
		return
	for layer in range(mini(queue.size(), 3) - 1, -1, -1):
		var plate = plate_style if layer == 0 else stacked_plate_style
		draw_style_box(plate, Rect2(center - Vector2(78, 22) + Vector2(0, layer * 5), Vector2(156, 44)))
	var foods = queue[0]
	for i in range(foods.size()):
		_draw_food(foods[i], center + Vector2((i - (foods.size() - 1) * 0.5) * 35, -2), Vector2(26, 48), Color.WHITE)

func _draw_food(id: String, center: Vector2, bounds: Vector2, tint: Color) -> void:
	var texture = FoodArt.food(id)
	var dimensions = texture.get_size()
	var factor = minf(bounds.x / dimensions.x, bounds.y / dimensions.y)
	var drawn = dimensions * factor
	draw_texture_rect(texture, Rect2(center - drawn * 0.5, drawn), false, tint)

func _draw_tutorial() -> void:
	var from = slot_center(2, 1) if model.tutorial == "MOVE" else slot_center(0, 2)
	var to = slot_center(0, 2) if model.tutorial == "MOVE" else slot_center(1, 2)
	var progress = fmod(model.clock * 0.65, 1.0)
	draw_arc(to, 32 + sin(model.clock * 4) * 3, 0, TAU, 32, Color("ffe4a0"), 3, true)
	for i in range(13):
		var point = from.lerp(to, float(i) / 12)
		draw_circle(point, 2, Color(1, 0.88, 0.64, 0.8))
	var finger = from.lerp(to, smoothstep(0, 0.85, progress))
	draw_circle(finger, 14, Color(1, 0.95, 0.82, 0.94))
	draw_arc(finger, 21, 0, TAU, 28, Color(1, 0.86, 0.54, 0.6), 3, true)
