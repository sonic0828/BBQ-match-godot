extends Node
## Short effects use a bounded voice pool; music keeps its position across pauses.

var enabled = true:
	set(value):
		enabled = value
		if not enabled:
			reset_effects()
var music_enabled = true:
	set(value):
		music_enabled = value
		_sync_playback()
var players: Array[AudioStreamPlayer] = []
var sounds: Dictionary = {}
var music: AudioStreamPlayer
var music_started = false
var cursor = 0
var unlocked = false
var backgrounded = false
var game_paused = false
var pending: Array[Dictionary] = []
var last_played: Dictionary = {}
var clock = 0.0
var duck_left = 0.0

func _ready() -> void:
	for i in range(8):
		var player = AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	for id in ["pick", "move", "drop", "swap", "cancel", "gather", "match", "combo", "refill", "warning", "win", "fail"]:
		sounds[id] = load("res://audio/%s.wav" % id)
	music = AudioStreamPlayer.new()
	music.stream = load("res://audio/night_market.ogg")
	music.stream.loop = true
	music.volume_db = -2
	add_child(music)

func unlock() -> void:
	# First pointer gesture also allows the host's audio context to resume.
	unlocked = true
	_sync_playback()

func set_backgrounded(value: bool) -> void:
	backgrounded = value
	_sync_playback()

func set_game_paused(value: bool) -> void:
	game_paused = value
	_sync_playback()

func _sync_playback() -> void:
	var suspended = backgrounded or game_paused
	for player in players:
		player.stream_paused = suspended
	if music == null:
		return
	var can_play = unlocked and music_enabled and not suspended
	if can_play and not music_started:
		music.play()
		music_started = true
	music.stream_paused = not can_play

func _process(delta: float) -> void:
	if backgrounded or game_paused:
		return
	clock += delta
	for index in range(pending.size() - 1, -1, -1):
		var cue = pending[index]
		if cue.at <= clock:
			pending.remove_at(index)
			play(cue.id, cue.pitch)
	duck_left = maxf(0, duck_left - delta)
	music.volume_db = move_toward(music.volume_db, -5.0 if duck_left > 0 else -2.0, delta * 30)

func schedule(id: String, delay: float, pitch: float = 1.0) -> void:
	if not enabled or not unlocked or backgrounded or game_paused:
		return
	var at = clock + delay
	# Simultaneous grill clears share their impact instead of doubling loudness.
	for cue in pending:
		if cue.id == id and absf(cue.at - at) < 0.04:
			cue.pitch = maxf(cue.pitch, pitch)
			return
	pending.append({"id": id, "at": at, "pitch": pitch})

func play(id: String, pitch: float = 1.0) -> void:
	if not enabled or not unlocked or backgrounded or game_paused or not sounds.has(id):
		return
	if clock - last_played.get(id, -100.0) < 0.04:
		return
	last_played[id] = clock
	var player = players[cursor % players.size()]
	for candidate in players:
		if not candidate.playing:
			player = candidate
			break
	cursor += 1
	player.stream = sounds[id]
	player.pitch_scale = clampf(pitch, 0.9, 1.15)
	player.play()
	if id in ["match", "combo", "win", "fail"]:
		duck_left = 0.65

func match_food(combo: int) -> void:
	play("gather")
	schedule("match", 0.27)
	if combo in [3, 5, 8]:
		schedule("combo", 0.30, 1.0 if combo == 3 else (1.06 if combo == 5 else 1.12))

func refill(count: int) -> void:
	for order in range(count):
		schedule("refill", 0.22 + order * 0.05, 1.0 + order * 0.055)

func reset_effects() -> void:
	pending.clear()
	last_played.clear()
	duck_left = 0
	for player in players:
		player.stream_paused = false
		player.stop()

func _exit_tree() -> void:
	reset_effects()
	for player in players:
		player.stream = null
	if music != null:
		music.stream_paused = false
		music.stop()
		music.stream = null
	sounds.clear()
