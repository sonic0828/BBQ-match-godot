extends SceneTree

var failures: Array[String] = []
var checks = 0

func _initialize() -> void:
	_test_levels()
	_test_transactions()
	_test_parallel_and_refill()
	_test_timer_pause_and_chain()
	_test_storage()
	_test_playthroughs()
	if failures.is_empty():
		print("PASS: %d checks; all 10 levels solved with actual move/swap rules." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func fixture(initials: Array, queues: Dictionary = {}) -> BoardModel:
	var data = {"level": 3, "timeLimitSec": 100, "tutorial": "", "grills": []}
	for i in range(initials.size()):
		data.grills.append({"id": "G%d" % i, "initial": initials[i], "plates": queues.get(i, [])})
	var model = BoardModel.new()
	model.start(data)
	return model

func settle(model: BoardModel, duration: float = 1.2) -> void:
	for i in range(int(duration * 100)):
		model.tick(0.01)

func move(model: BoardModel, source: int, source_slot: int, target: int, target_slot: int) -> bool:
	if not model.begin_drag(source, source_slot):
		return false
	return model.drop(target, target_slot, model.grills[target].version)

func _test_levels() -> void:
	var expected = [5, 10, 12, 12, 15, 16, 18, 20, 20, 22]
	for number in range(1, 11):
		var config = LevelLoader.load_level(number)
		check(not config.is_empty(), "level %d loads and validates" % number)
		var model = BoardModel.new()
		model.start(config)
		check(model.total_matches == expected[number - 1], "level %d total match groups" % number)
	var invalid = LevelLoader.load_level(2).duplicate(true)
	invalid.grills[0].plates.append([])
	invalid.grills[1].id = invalid.grills[0].id
	invalid.grills[2].initial[0] = "BAD"
	invalid.timeLimitSec = 0
	check(LevelLoader.validate(invalid).size() >= 4, "validator reports malformed plates, IDs, foods and time")

func _test_transactions() -> void:
	var model = fixture([["C", null, null], ["L", null, null]], {0: [["J"]]})
	check(model.begin_drag(0, 0), "pick starts drag")
	check(model.grills[0].slots[0] == "C" and model.grills[0].queue.size() == 1, "drag reserves source without consuming a plate")
	check(not model.drop(0, 1), "same grill rejected")
	check(model.grills[0].slots[0] == "C", "cancel leaves board intact")
	check(move(model, 0, 0, 1, 0), "drop on occupied slot swaps even when other slots empty")
	check(model.grills[0].slots[0] == "L" and model.grills[1].slots[0] == "C", "swap commits both sides atomically")
	check(not model.begin_drag(0, 0), "transferring grill locked")
	settle(model)
	model.begin_drag(0, 0)
	var version = model.grills[1].version
	model.grills[1].version += 1
	check(not model.drop(1, 1, version), "stale target version rejected")
	check(model.grills[0].slots[0] == "L", "stale drop preserves source")
	model.begin_drag(0, 0)
	check(not model.drop(-1, -1), "UI or blank drop rejected")
	check(model.drag.is_empty(), "invalid drop cancels transaction")

func _test_parallel_and_refill() -> void:
	var model = fixture([["C", "C", "S"], ["S", "S", "C"], ["L", null, null], ["J", null, null]])
	check(move(model, 0, 2, 1, 2), "double-match swap accepted")
	settle(model, 0.21)
	check(model.matches == 2 and model.combo == 2, "both matches start on same tick and count combo")
	check(model.grills[0].state == model.grills[1].state, "double match phases synchronized")
	check(model.begin_drag(2, 0), "other grill remains interactive during match")
	check(not model.drop(0, 0), "locked match grill rejects drop")
	check(move(model, 2, 0, 3, 1), "independent move can run during match")
	settle(model)
	check(model.grills[0].slots == ["", "", ""] and model.grills[1].slots == ["", "", ""], "double match clears both")
	model = fixture([["C", null, null], ["C", "C", null]], {0: [["J", "L"], ["S"]]})
	move(model, 0, 0, 1, 2)
	settle(model, 0.21)
	check(model.grills[0].state == BoardModel.GrillState.REFILLING and model.grills[1].state == BoardModel.GrillState.MATCHING, "source refill and target match run concurrently")
	settle(model)
	check(model.grills[0].slots == ["J", "", "L"], "two-item plate uses outer slots")
	check(model.grills[0].queue.size() == 1, "partial plate does not auto top up")
	model = fixture([["L", null, null], ["J", null, null]], {0: [["C"], ["S", "J", "L"]]})
	move(model, 0, 0, 1, 1)
	settle(model)
	check(model.grills[0].slots == ["", "C", ""], "one-item plate centered after manual empty")
	move(model, 0, 1, 1, 2)
	settle(model)
	check(model.grills[0].slots == ["S", "J", "L"], "three-item plate fills all slots")

func _test_timer_pause_and_chain() -> void:
	var model = BoardModel.new()
	model.start(LevelLoader.load_level(1))
	model.tick(5)
	check(model.remaining == 75, "tutorial does not reduce timer")
	move(model, 2, 1, 0, 2)
	check(model.state == BoardModel.GameState.PLAYING, "tutorial closes after player match move")
	model.tick(0.1)
	check(model.remaining < 75, "timer starts after tutorial")
	model.pause()
	var frozen = model.grills.duplicate(true)
	var remaining = model.remaining
	model.tick(10)
	check(model.grills == frozen and model.remaining == remaining, "pause freezes transfer, refill and timer")
	model.resume()
	settle(model)
	model.begin_drag(1, 0)
	model.remaining = 0.005
	model.tick(0.01)
	check(model.state == BoardModel.GameState.FAIL and model.drag.is_empty(), "timeout cancels drag immediately")
	check(not model.drop(2, 0), "no final drop allowed after timeout")
	model = fixture([["C", "C", "C"]], {0: [["L", "L", "L"], ["J", "J", "J"]]})
	settle(model, 3)
	check(model.matches == 3 and model.state == BoardModel.GameState.WIN, "refill auto-chain counts every match then wins")
	model = fixture([["C", "C", "C"]])
	model.remaining = 0.005
	model.tick(0.01)
	check(model.state == BoardModel.GameState.FAIL and not model.is_cleared(), "timeout during match cannot become win")
	model = fixture([["C", null, null], ["L", null, null]], {0: [["J"]]})
	move(model, 0, 0, 1, 1)
	settle(model, 0.21)
	model.pause()
	frozen = model.grills.duplicate(true)
	model.tick(2)
	check(model.grills == frozen, "refill remains frozen during pause")
	model.resume()
	settle(model)
	check(model.grills[0].slots == ["", "J", ""], "refill resumes correctly")
	check(not model.is_cleared(), "victory inspects slots and queues, not progress count")

func _test_storage() -> void:
	var path = "/private/tmp/hotpot-test-progress.cfg"
	var store = SaveStore.new()
	store.highest_unlocked = 6
	store.completed = [1, 2, 3, 4, 5]
	store.last_selected = 4
	store.audio_enabled = false
	check(store.save_progress(path) == OK, "local settings save")
	var reloaded = SaveStore.new()
	reloaded.load_progress(path)
	check(reloaded.highest_unlocked == 6 and reloaded.completed.size() == 5 and not reloaded.audio_enabled, "local progress and sound survive reload")
	var broken = ConfigFile.new()
	broken.set_value("progress", "highestUnlockedLevel", 999)
	broken.set_value("progress", "completedLevels", "bad")
	broken.save(path)
	reloaded.load_progress(path)
	check(reloaded.highest_unlocked == 10 and reloaded.completed.is_empty(), "out-of-range and malformed save data sanitized")
	DirAccess.remove_absolute(path)

func _test_playthroughs() -> void:
	for number in range(1, 11):
		var model = BoardModel.new()
		model.start(LevelLoader.load_level(number))
		model.state = BoardModel.GameState.PLAYING
		model.remaining = 10000 # Solvability proof is separate from human timing/balance.
		var actions = 0
		while model.state == BoardModel.GameState.PLAYING and actions < 500:
			settle(model)
			if model.state == BoardModel.GameState.WIN:
				break
			if not solver_step(model):
				break
			actions += 1
		check(model.state == BoardModel.GameState.WIN, "level %d can clear every slot and plate (%d moves)" % [number, actions])
		check(model.matches == model.total_matches, "level %d solved progress equals total" % number)
		print("Level %02d: %d moves, %d/%d matches" % [number, actions, model.matches, model.total_matches])

func solver_step(model: BoardModel) -> bool:
	var counts: Dictionary = {}
	for grill in model.grills:
		for food in grill.slots:
			if food != "": counts[food] = counts.get(food, 0) + 1
	var chosen = ""
	var destination = -1
	var best = -1
	for food in counts:
		if counts[food] < 3: continue
		for g in range(model.grills.size()):
			var amount = model.grills[g].slots.count(food)
			if amount > best:
				best = amount
				chosen = food
				destination = g
	if destination >= 0:
		for slot in range(3):
			if model.grills[destination].slots[slot] == chosen: continue
			for g in range(model.grills.size()):
				if g == destination: continue
				for s in range(3):
					if model.grills[g].slots[s] == chosen:
						return move(model, g, s, destination, slot)
	# Expose a hidden plate by emptying its grill into available slots.
	var source = -1
	var fewest = 4
	for g in range(model.grills.size()):
		var occupied = 3 - model.grills[g].slots.count("")
		if not model.grills[g].queue.is_empty() and occupied < fewest:
			source = g
			fewest = occupied
	if source >= 0:
		for s in range(3):
			if model.grills[source].slots[s] == "": continue
			for g in range(model.grills.size()):
				if g == source: continue
				for t in range(3):
					if model.grills[g].slots[t] == "":
						return move(model, source, s, g, t)
	return false
