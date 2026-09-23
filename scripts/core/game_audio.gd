extends Node

var enabled = true
var players: Array[AudioStreamPlayer] = []
var sounds: Dictionary = {}
var cursor = 0

func _exit_tree() -> void:
	for player in players:
		player.stop()
		player.stream = null
	sounds.clear()

func _ready() -> void:
	for i in range(6):
		var player = AudioStreamPlayer.new()
		player.volume_db = -10
		add_child(player)
		players.append(player)
	for id in ["pick", "drop", "swap", "cancel", "match", "combo", "refill", "warning", "win", "fail"]:
		sounds[id] = load("res://audio/%s.wav" % id)

func play(id: String) -> void:
	if not enabled or not sounds.has(id):
		return
	var player = players[cursor % players.size()]
	cursor += 1
	player.stream = sounds[id]
	player.play()
