class_name BoardModel
extends RefCounted
## Deterministic rules. Visuals observe events; animation callbacks never mutate the board.

signal event(kind: String, detail: Dictionary)

enum GameState { INIT, TUTORIAL, PLAYING, PAUSED, WIN, FAIL }
enum GrillState { STABLE, TRANSFERRING, MATCHING, CLEARING, EMPTY, REFILLING, LOCKED, OPENING, PACKING }
enum InteractionState { IDLE, DRAGGING, COMMITTING, CANCELING }

const LID_OPEN_DELAY = 0.27 # Start fading with the matched food's plate impact.
const LID_FADE_DURATION = 0.35

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
const PACK_DURATION = 1.55
var pack_until = -1.0
var pack_refill_at = -1.0
var pack_tutorial = false

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
	pack_until = -1.0
	pack_tutorial = false
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
		var unlock_food = source.get("unlockFood", "")
		grills.append({"slots": slots, "queue": queue,
			"state": GrillState.LOCKED if unlock_food != "" else GrillState.STABLE,
			"elapsed": 0.0, "version": 0, "refill_foods": [],
			"unlock_food": unlock_food, "lid_open_at": -1.0})
	total_matches = total / 3
	state = GameState.TUTORIAL if tutorial in ["MOVE", "SWAP"] else GameState.PLAYING
	event.emit("started", {})
	for index in range(grills.size()):
		_resolve(index)

func active() -> bool:
	return state in [GameState.PLAYING, GameState.TUTORIAL]

func can_touch(index: int) -> bool:
	return active() and pack_until < 0 and index >= 0 and index < grills.size() and grills[index].state == GrillState.STABLE

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
	if state == GameState.PLAYING and not pack_tutorial:
		remaining = maxf(0.0, remaining - delta)
		if remaining <= 0.0:
			cancel_drag()
			state = GameState.FAIL
			event.emit("fail", {})
			return
	clock += delta
	if pack_until >= 0 and clock >= pack_until:
		pack_until = -1.0
		pack_tutorial = false
		event.emit("pack_finished", {})
	if clock - last_match_at > 2.0:
		combo = 0
	for index in range(grills.size()):
		var grill = grills[index]
		grill.elapsed += delta
		match grill.state:
			GrillState.PACKING:
				if clock >= pack_refill_at:
					_set_state(index, GrillState.STABLE)
					_resolve(index)
			GrillState.OPENING:
				if clock >= grill.lid_open_at + LID_FADE_DURATION:
					grill.version += 1
					_set_state(index, GrillState.STABLE)
					event.emit("lid_opened", {"grill": index})
					_resolve(index)
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
	if grills[index].state in [GrillState.LOCKED, GrillState.OPENING]:
		return
	if _is_match(index):
		_set_state(index, GrillState.MATCHING)
		var detail = _record_match(grills[index].slots[0])
		detail.grill = index
		event.emit("match", detail)
	elif grills[index].slots == ["", "", ""]:
		_refill(index)

func _record_match(food: String, opening_delay: float = LID_OPEN_DELAY) -> Dictionary:
	combo = combo + 1 if clock - last_match_at <= 2.0 else 1
	var simultaneous = is_equal_approx(clock, last_match_at)
	last_match_at = clock
	matches += 1
	for index in range(grills.size()):
		var grill = grills[index]
		if grill.state == GrillState.LOCKED and grill.unlock_food == food:
			_set_state(index, GrillState.OPENING)
			grill.lid_open_at = clock + opening_delay
			event.emit("lid_opening", {"grill": index, "delay": opening_delay})
	return {"combo": combo, "double": simultaneous}

func pack_candidate(preferred: String = "") -> Dictionary:
	if state not in [GameState.PLAYING, GameState.PAUSED] or pack_until >= 0 or not drag.is_empty(): return {}
	var foods: Dictionary = {}
	var visible: Dictionary = {}
	var keys: Array = []
	for index in range(grills.size()):
		var grill = grills[index]
		if grill.state == GrillState.LOCKED:
			keys.append(grill.unlock_food)
			continue
		if grill.state != GrillState.STABLE: return {}
		for slot in range(3):
			var food = grill.slots[slot]
			if food == "": continue
			if not foods.has(food): foods[food] = []
			foods[food].append({"grill": index, "slot": slot, "plate": -1, "offset": -1})
			visible[food] = visible.get(food, 0) + 1
	# Visible food always comes first; reserve food never comes from a closed lid.
	for index in range(grills.size()):
		var grill = grills[index]
		if grill.state == GrillState.LOCKED: continue
		for plate in range(grill.queue.size()):
			for offset in range(grill.queue[plate].size()):
				var food = grill.queue[plate][offset]
				if not foods.has(food): foods[food] = []
				foods[food].append({"grill": index, "slot": -1, "plate": plate, "offset": offset})
	var chosen = ""
	var best = -1
	for food in foods:
		if foods[food].size() < 3 or (preferred != "" and food != preferred): continue
		var score = mini(visible.get(food, 0), 3) * 10 + (50 if food in keys else 0)
		if score > best:
			best = score
			chosen = food
	if chosen == "": return {}
	return {"food": chosen, "sources": foods[chosen].slice(0, 3)}

func pack_food(food: String, tutorial_use: bool = false) -> bool:
	if not active(): return false
	var selected = pack_candidate(food)
	if selected.is_empty(): return false
	pack_until = clock + PACK_DURATION
	pack_refill_at = clock + 0.8
	pack_tutorial = tutorial_use
	# Reverse the source list so removing reserve entries preserves earlier indices.
	var sources = selected.sources.duplicate(true)
	sources.reverse()
	for source in sources:
		var grill = grills[source.grill]
		if source.plate < 0:
			grill.slots[source.slot] = ""
		else:
			grill.queue[source.plate].remove_at(source.offset)
			if grill.queue[source.plate].is_empty(): grill.queue.remove_at(source.plate)
		grill.version += 1
		_set_state(source.grill, GrillState.PACKING)
	var detail = _record_match(food, 0.7)
	detail.merge(selected)
	event.emit("pack", detail)
	return true

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
	if pack_until >= 0: return false
	for grill in grills:
		if grill.state != GrillState.STABLE or grill.slots != ["", "", ""] or not grill.queue.is_empty():
			return false
	return true

func hint_group() -> Array[Vector2i]:
	# Read-only: choose three visible foods that can be assembled by legal swaps.
	if state != GameState.PLAYING or not drag.is_empty(): return []
	var available: Dictionary = {}
	var unlock_foods: Array = []
	for index in range(grills.size()):
		if grills[index].state == GrillState.LOCKED:
			unlock_foods.append(grills[index].unlock_food)
		if not can_touch(index):
			continue
		for slot in range(3):
			var food = grills[index].slots[slot]
			if food != "":
				if not available.has(food): available[food] = []
				available[food].append(Vector2i(index, slot))
	var best: Array[Vector2i] = []
	var best_score = -1
	for food in available:
		if available[food].size() < 3: continue
		for index in range(grills.size()):
			if not can_touch(index): continue
			var local: Array[Vector2i] = []
			var outside: Array[Vector2i] = []
			for cell in available[food]:
				if cell.x == index: local.append(cell)
				else: outside.append(cell)
			if local.is_empty() or local.size() >= 3: continue
			# One-move matches first; among equally short options prefer opening a lid.
			var score = local.size() * 100 + (50 if food in unlock_foods else 0)
			if score > best_score:
				best_score = score
				best = local.duplicate()
				for cell in outside:
					if best.size() == 3: break
					best.append(cell)
	return best
