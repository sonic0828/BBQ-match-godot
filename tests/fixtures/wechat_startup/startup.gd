extends Control

func _ready() -> void:
	print("[BBQ scene ready] minimal ", size)
	await RenderingServer.frame_post_draw
	print("[BBQ first frame]")
