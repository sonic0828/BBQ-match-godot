extends Control

var elapsed = 0.0

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(FoodArt.grill(), Rect2(50, 70, 470, 300), false)
	var ids = ["L", "C", "S", "J", "W"]
	for i in range(ids.size()):
		var texture = FoodArt.food(ids[i])
		var height = 243.0 + sin(elapsed * 1.7 + i) * 5
		var dimensions = texture.get_size() * minf(82.0 / texture.get_width(), height / texture.get_height())
		draw_texture_rect(texture, Rect2(Vector2(119 + i * 83, 191) - dimensions * 0.5, dimensions), false)
	for i in range(7):
		var phase = fmod(elapsed * 0.3 + i * 0.13, 1)
		var point = Vector2(110 + i * 59 + sin(phase * 6 + i) * 9, 80 - phase * 70)
		draw_circle(point, 3 + phase * 7, Color(1, 0.92, 0.7, (1 - phase) * 0.10))
