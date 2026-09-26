extends SceneTree
## Exercise scheduling, actual playback state, lifecycle and persisted settings.

var app: Control
var failures: Array[String] = []
var checks = 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	check("乐" in app.font.get_supported_chars(), "music setting character is present in bundled font")
	var audio = app.audio
	audio.set_process(false)
	audio.enabled = true
	audio.music_enabled = true
	check(not audio.music.playing, "music waits for first interaction")
	var press = InputEventScreenTouch.new()
	press.pressed = true
	app._input(press)
	check(audio.music.playing and not audio.music.stream_paused, "touch starts music")
	await create_timer(0.15).timeout
	# Native window focus can change during startup; begin the scenario foregrounded.
	app._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	var music_playback = audio.music.get_stream_playback()
	audio.music_enabled = false
	audio.music_enabled = true
	check(audio.music.get_stream_playback() == music_playback, "mute resumes the same music playback instead of restarting it")
	music_playback = null
	check(audio.music.stream.loop and audio.music.stream.get_length() > 40, "compressed music is a complete looping phrase")
	for id in audio.sounds:
		check(audio.sounds[id] != null and audio.sounds[id].get_length() > 0, "effect decodes: " + id)
	app._start_level(3)
	app.board.set_process(false)
	app.model.begin_drag(0, 2)
	app.model.drop(1, 2)
	check(audio.last_played.has("move") and not audio.last_played.has("swap"), "transfer starts with movement, not landing")
	audio._process(0.17)
	check(audio.last_played.has("swap"), "swap landing follows movement")
	app.model.tick(0.21)
	check(audio.last_played.has("gather") and not audio.last_played.has("match"), "double clear gathers before impact")
	check(audio.pending.size() == 1, "simultaneous clears share a single plate impact")
	audio._process(0.15)
	app._pause()
	var frozen = audio.clock
	audio._process(1.0)
	check(audio.clock == frozen and not audio.last_played.has("match") and audio.music.stream_paused, "pause freezes pending cues and music")
	app._resume()
	audio._process(0.13)
	check(audio.last_played.has("match") and not audio.music.stream_paused, "impact resumes at plate pop without restarting music")
	check(audio.music.volume_db < -2, "plate impact briefly lowers background music")
	audio.reset_effects()
	audio.refill(3)
	audio._process(0.23)
	check(audio.last_played.has("refill") and audio.pending.size() == 2, "refill taps follow staggered arrivals")
	audio._process(0.05)
	check(audio.pending.size() == 1, "second refill tap waits its turn")
	audio.enabled = false
	check(audio.pending.is_empty() and audio.players.all(func(p): return not p.playing), "mute immediately stops voices and discards pending effects")
	check(not audio.music.stream_paused, "effect mute leaves music running")
	audio.enabled = true
	audio._process(1)
	check(audio.last_played.is_empty(), "unmute never replays stale effects")
	audio.music_enabled = false
	audio.play("pick")
	check(audio.music.stream_paused and audio.last_played.has("pick"), "music mute leaves effects available")
	audio.music_enabled = true
	audio.match_food(3)
	audio._process(.31)
	check(audio.last_played.has("combo"), "third combo adds reward")
	audio.reset_effects()
	audio.match_food(9)
	audio._process(.31)
	check(not audio.last_played.has("combo"), "long chains do not keep stacking rewards")
	audio.match_food(5)
	app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(audio.backgrounded and audio.game_paused and audio.music.stream_paused, "background suspends both music and gameplay effects")
	app._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not audio.backgrounded and audio.music.stream_paused, "foreground waits for explicit game resume")
	app._show_home()
	check(audio.pending.is_empty() and not audio.music.stream_paused, "home discards game cues and resumes music")
	app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(audio.music.stream_paused, "home also silences background audio")
	app._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not audio.music.stream_paused, "home music resumes on foreground")
	app._start_level(3)
	audio.match_food(3)
	app.model.state = BoardModel.GameState.PLAYING
	app.model.remaining = .001
	app.model.tick(.01)
	check(audio.pending.is_empty() and audio.last_played.has("fail"), "timeout cancels delayed combo audio before failure cue")
	app._show_home()
	app._show_settings()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-audio="):
			var directory = arg.trim_prefix("--capture-audio=")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join("settings.png"))
			app._start_level(3)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join("level3.png"))
			app._show_home()
			app._show_settings()
	var content = app.modal.get_child(1)
	var switches: Array = []
	for child in content.get_children():
		if child is Button and (child.text.begins_with("音乐") or child.text.begins_with("音效") or child.text.begins_with("震动")):
			switches.append(child)
	check(switches.size() == 3, "settings exposes three separate switches")
	for child in switches:
		var initial = child.text
		child.pressed.emit()
		check(child.text != initial, "setting toggles its displayed state")
		child.pressed.emit()
	_test_storage()
	app.queue_free()
	await process_frame
	await process_frame
	# Let the audio mixer retire stopped voices before shutting down the engine.
	await create_timer(0.15).timeout
	for failure in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: %d audio, lifecycle and settings checks" % checks)
	quit(0 if failures.is_empty() else 1)

func _test_storage() -> void:
	var path = "/private/tmp/bbq-audio-settings.cfg"
	var legacy = ConfigFile.new()
	legacy.set_value("settings", "audioEnabled", false)
	legacy.set_value("progress", "highestUnlockedLevel", 4)
	legacy.save(path)
	var store = SaveStore.new()
	store.load_progress(path)
	check(not store.music_enabled and not store.audio_enabled and store.highest_unlocked == 4, "legacy mute migrates to music without losing progress")
	store.music_enabled = true
	store.save_progress(path)
	var loaded = SaveStore.new()
	loaded.load_progress(path)
	check(loaded.music_enabled and not loaded.audio_enabled and loaded.highest_unlocked == 4, "music and effects persist independently")
	DirAccess.remove_absolute(path)
