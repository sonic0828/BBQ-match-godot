extends SceneTree

class ObservedHaptics extends "res://scripts/core/game_haptics.gd":
	var pulses: Array[float] = []
	func _pulse() -> void:
		pulses.append(clock)

var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.audio.enabled = false
	app.haptics.queue_free()
	var haptics = ObservedHaptics.new()
	app.haptics = haptics
	app.add_child(haptics)
	haptics.set_process(false)
	app._start_level(3)
	app.model.begin_drag(0, 2)
	app.model.drop(1, 2)
	app.model.tick(0.21)
	check(haptics.pending.size() == 2, "actual double match merges into two taps")
	haptics._process(0.26)
	check(haptics.pulses.is_empty(), "feedback waits for plate impact")
	haptics._process(0.02)
	check(haptics.pulses.size() == 1, "first tap aligns with plate pop")
	haptics._process(0.12)
	check(haptics.pulses.size() == 2 and haptics.pending.is_empty(), "multi clear adds one spaced tap")
	haptics.match_food(1, false)
	check(haptics.pending.size() == 1, "ordinary three-match has one light tap")
	haptics.reset()
	haptics.match_food(2, false)
	check(haptics.pending.size() == 2, "second chained match has two taps")
	haptics.match_food(3, true)
	haptics.match_food(9, true)
	check(haptics.pending.size() == 3, "long chains cap at three merged taps")
	haptics._process(0.28)
	haptics._process(0.12)
	haptics._process(0.12)
	check(haptics.pulses.size() == 5 and haptics.pending.is_empty(), "three chain taps remain spaced")
	haptics.match_food(3, false)
	haptics._process(1.0)
	check(haptics.pulses.size() == 6, "slow frames never burst multiple overdue taps")
	haptics.match_food(3, false)
	app._pause()
	check(haptics.game_paused and haptics.pending.is_empty(), "pause discards queued haptics")
	haptics.match_food(3, false)
	haptics._process(1)
	check(haptics.pulses.size() == 6, "paused gameplay cannot schedule or emit feedback")
	app._resume()
	haptics._process(1)
	check(haptics.pulses.size() == 6, "resume never replays stale taps")
	haptics.match_food(3, false)
	app._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(haptics.backgrounded and haptics.pending.is_empty(), "background clears queued feedback")
	haptics.preview()
	check(haptics.pulses.size() == 6, "settings preview cannot vibrate in background")
	app._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not haptics.backgrounded and haptics.game_paused, "foreground still waits for explicit resume")
	app._resume()
	haptics.match_food(3, false)
	haptics.enabled = false
	haptics.preview()
	check(haptics.pending.is_empty() and haptics.pulses.size() == 6, "mute cancels queue and preview")
	haptics.enabled = true
	haptics.preview()
	check(haptics.pulses.size() == 7, "enabling vibration offers one light preview")
	haptics.match_food(3, false)
	app._show_home()
	check(haptics.pending.is_empty(), "leaving game clears feedback")
	app._start_level(3)
	haptics.match_food(3, false)
	app._start_level(3)
	check(haptics.pending.is_empty(), "restarting game clears feedback")
	haptics.match_food(3, false)
	app.model.state = BoardModel.GameState.PLAYING
	app.model.remaining = 0.001
	app.model.tick(0.01)
	check(haptics.pending.is_empty(), "timeout cancels feedback")
	app.queue_free()
	await process_frame
	for failure in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: %d haptic rhythm and lifecycle checks" % checks)
	quit(0 if failures.is_empty() else 1)
