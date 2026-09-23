class_name BoardModel
extends RefCounted
## Deterministic rules. Visuals observe events; animation callbacks never mutate the board.

signal event(kind: String, detail: Dictionary)

enum GameState { INIT, TUTORIAL, PLAYING, PAUSED, WIN, FAIL }
enum GrillState { STABLE, TRANSFERRING, MATCHING, CLEARING, EMPTY, REFILLING }
enum InteractionState { IDLE, DRAGGING, COMMITTING, CANCELING }

var state = GameState.INIT
var interaction = InteractionState.IDLE
var grills: Array = []
var drag: Dictionary = {}
var level = 1
var time_limit = 75.0
var remaining = 75.0
var clock = 0.0
var matches = 0
var total_matches = 0
var combo = 0
var last_match_at = -100.0
var tutorial = ""
var tutorial_done = false
var refill_tip_shown = false
var epoch = 0
var resume_state = GameState.PLAYING
var settle_time = 0.0

func start(config: Dictionary) -> void:
	epoch += 1
	grills.clear()
	drag.clear()
	interaction = InteractionState.IDLE
	level = int(config.level)
	time_limit = float(config.timeLimitSec)
	remaining = time_limit
	clock = 0.0
	matches = 0
	combo = 0
	last_match_at = -100.0
	settle_time = 0.0
	tutorial = config.get("tutorial", "")
	tutorial_done = false
	refill_tip_shown = false
	var total = 0
	for source in config.grills:
		var slots: Array = []
		for food in source.initial:
			slots.append("" if food == null else food)
			if food != null:
				total += 1
		var queue = source.plates.duplicate(true)
		for plate in queue:
			total += plate.size()
		grills.append({"slots": slots, "queue": queue, "state": GrillState.STABLE,
			"elapsed": 0.0, "version": 0, "refill_foods": []})
	total_matches = total / 3
	state = GameState.TUTORIAL if tutorial in ["MOVE", "SWAP"] else GameState.PLAYING
	for index in range(grills.size()):
		_resolve(index)
	event.emit("started", {})

func active() -> bool:
	return state in [GameState.PLAYING, GameState.TUTORIAL]

func can_touch(index: int) -> bool:
	return active() and index >= 0 and index < grills.size() and grills[index].state == GrillState.STABLE

func begin_drag(index: int, slot: int) -> bool:
	if not can_touch(index) or slot < 0 or slot > 2 or not drag.is_empty():
		return false
	var grill = grills[index]
	if grill.slots[slot] == "":
		return false
	drag = {"grill": index, "slot": slot, "food": grill.slots[slot], "version": grill.version, "epoch": epoch}
	interaction = InteractionState.DRAGGING
	event.emit("pick", drag.duplicate())
	return true

func cancel_drag() -> void:
	if drag.is_empty():
		return
	var old = drag.duplicate()
	drag.clear()
	interaction = InteractionState.CANCELING
	event.emit("cancel", old)
	interaction = InteractionState.IDLE

func drop(index: int, slot: int, expected_version: int = -1) -> bool:
	if drag.is_empty():
		return false
	var origin = drag.duplicate()
	if not can_touch(index) or index == origin.grill or slot < 0 or slot > 2:
		cancel_drag()
		return false
	var source = grills[origin.grill]
	var target = grills[index]
	if origin.epoch != epoch or source.version != origin.version or not can_touch(origin.grill):
		cancel_drag()
		return false
	if expected_version >= 0 and target.version != expected_version:
		cancel_drag()
		return false
	var displaced = target.slots[slot]
	# A single commit: picking up never clears the logical source slot.
	interaction = InteractionState.COMMITTING
	source.slots[origin.slot] = displaced
	target.slots[slot] = origin.food
	source.version += 1
	target.version += 1
	_set_state(origin.grill, GrillState.TRANSFERRING)
	_set_state(index, GrillState.TRANSFERRING)
	drag.clear()
	interaction = InteractionState.IDLE
	var is_swap = displaced != ""
	event.emit("transfer", {"source": origin.grill, "source_slot": origin.slot,
		"target": index, "target_slot": slot, "food": origin.food, "displaced": displaced, "swap": is_swap})
	if state == GameState.TUTORIAL:
		var correct_move = tutorial == "MOVE" and not is_swap and _is_match(index)
		if correct_move or (tutorial == "SWAP" and is_swap):
			tutorial_done = true
			state = GameState.PLAYING
			event.emit("tutorial_done", {})
	return true

func pause() -> void:
	if not active():
		return
	cancel_drag()
	resume_state = state
	state = GameState.PAUSED
	event.emit("paused", {})

func resume() -> void:
	if state == GameState.PAUSED:
		state = resume_state
		event.emit("resumed", {})

func tick(delta: float) -> void:
	if not active():
		return
	if state == GameState.PLAYING:
		remaining = maxf(0.0, remaining - delta)
		if remaining <= 0.0:
			cancel_drag()
			state = GameState.FAIL
			event.emit("fail", {})
			return
	clock += delta
	if clock - last_match_at > 2.0:
		combo = 0
	for index in range(grills.size()):
		var grill = grills[index]
		grill.elapsed += delta
		match grill.state:
			GrillState.TRANSFERRING:
				if grill.elapsed >= 0.20:
					_set_state(index, GrillState.STABLE)
					_resolve(index)
			GrillState.MATCHING:
				if grill.elapsed >= 0.08:
					_set_state(index, GrillState.CLEARING)
			GrillState.CLEARING:
				if grill.elapsed >= 0.22:
					grill.slots = ["", "", ""]
					grill.version += 1
					_set_state(index, GrillState.EMPTY)
					_refill(index)
			GrillState.REFILLING:
				if grill.elapsed >= 0.32:
					_set_state(index, GrillState.STABLE)
					_resolve(index)
	if is_cleared() and drag.is_empty():
		settle_time += delta
		if settle_time >= 0.25:
			state = GameState.WIN
			event.emit("win", {})
	else:
		settle_time = 0.0

func _set_state(index: int, next: int) -> void:
	grills[index].state = next
	grills[index].elapsed = 0.0

func _is_match(index: int) -> bool:
	var slots = grills[index].slots
	return slots[0] != "" and slots[0] == slots[1] and slots[1] == slots[2]

func _resolve(index: int) -> void:
	if _is_match(index):
		_set_state(index, GrillState.MATCHING)
		combo = combo + 1 if clock - last_match_at <= 2.0 else 1
		var simultaneous = is_equal_approx(clock, last_match_at)
		last_match_at = clock
		matches += 1
		event.emit("match", {"grill": index, "combo": combo, "double": simultaneous})
	elif grills[index].slots == ["", "", ""]:
		_refill(index)

func _refill(index: int) -> void:
	var grill = grills[index]
	if grill.queue.is_empty():
		_set_state(index, GrillState.STABLE)
		return
	var foods: Array = grill.queue.pop_front()
	grill.refill_foods = foods.duplicate()
	match foods.size():
		1: grill.slots = ["", foods[0], ""]
		2: grill.slots = [foods[0], "", foods[1]]
		3: grill.slots = foods.duplicate()
	grill.version += 1
	_set_state(index, GrillState.REFILLING)
	event.emit("refill", {"grill": index})
	if tutorial == "REFILL" and not refill_tip_shown:
		refill_tip_shown = true
		event.emit("refill_tip", {})

func is_cleared() -> bool:
	for grill in grills:
		if grill.state != GrillState.STABLE or grill.slots != ["", "", ""] or not grill.queue.is_empty():
			return false
	return true
