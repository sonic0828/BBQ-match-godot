class_name LevelLoader
extends RefCounted

const FOOD_TYPES = ["L", "C", "J", "S", "W", "M", "E", "O"]

static func load_level(number: int) -> Dictionary:
	var path = "res://data/level_%02d.json" % number
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Invalid level JSON: " + path)
		return {}
	var errors = validate(parsed)
	if not errors.is_empty():
		push_error("Level %d: %s" % [number, "; ".join(errors)])
		return {}
	return parsed

static func validate(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var counts: Dictionary = {}
	var ids: Array = []
	var grills = config.get("grills", [])
	if grills.size() != (6 if config.get("level", 0) == 1 else 9):
		errors.append("grills: expected 6 for level 1, otherwise 9")
	if float(config.get("timeLimitSec", 0)) <= 0:
		errors.append("timeLimitSec must be positive")
	for grill in grills:
		var id = str(grill.get("id", ""))
		if id.is_empty() or id in ids:
			errors.append("grill ID missing or duplicated: " + id)
		ids.append(id)
		var initial = grill.get("initial", [])
		if initial.size() != 3:
			errors.append(id + ".initial must have exactly 3 slots")
		var foods = initial.duplicate()
		for plate in grill.get("plates", []):
			if not plate is Array or plate.size() < 1 or plate.size() > 3:
				errors.append(id + ".plates must contain 1–3 foods per plate")
				continue
			for food in plate:
				if food == null:
					errors.append(id + ".plates cannot contain empty food")
			foods.append_array(plate)
		for food in foods:
			if food == null:
				continue
			if food not in FOOD_TYPES:
				errors.append(id + ": unknown food " + str(food))
			counts[food] = counts.get(food, 0) + 1
	for food in counts:
		if counts[food] % 3 != 0:
			errors.append("%s total %d is not a multiple of 3" % [food, counts[food]])
	if counts.is_empty():
		errors.append("level must contain food")
	return errors
