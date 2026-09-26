extends Node
## Small, merged pulses at the plate impact; no stale feedback after leaving play.

var enabled = true:
	set(value):
		enabled = value
		if not enabled:
			reset()
var backgrounded = false
var game_paused = false
var clock = 0.0
var pending: Array[float] = []
var bridge: JavaScriptObject

func _ready() -> void:
	if OS.has_feature("wechat"):
		bridge = JavaScriptBridge.get_interface("bbqHaptics")

func match_food(combo: int, simultaneous: bool) -> void:
	if not enabled or backgrounded or game_paused:
		return
	var pulses = 3 if combo >= 3 else (2 if simultaneous or combo == 2 else 1)
	for i in range(pulses):
		var at = clock + 0.27 + i * 0.12
		# Two grills can emit match in the same frame: one shared rhythm, not two.
		if not pending.any(func(queued): return absf(queued - at) < 0.04):
			pending.append(at)
	pending.sort()

func _process(delta: float) -> void:
	if not enabled or backgrounded or game_paused:
		return
	clock += delta
	if pending.is_empty() or pending[0] > clock:
		return
	# A slow frame must not compress several overdue taps into one strong burst.
	while not pending.is_empty() and pending[0] <= clock:
		pending.pop_front()
	_pulse()

func set_backgrounded(value: bool) -> void:
	backgrounded = value
	if value:
		reset()

func set_game_paused(value: bool) -> void:
	game_paused = value
	if value:
		reset()

func reset() -> void:
	pending.clear()

func preview() -> void:
	if enabled and not backgrounded:
		_pulse()

func _pulse() -> void:
	if OS.has_feature("wechat"):
		if bridge != null:
			bridge.pulse()
	elif OS.has_feature("android") or OS.has_feature("ios"):
		Input.vibrate_handheld(15, 0.25)
