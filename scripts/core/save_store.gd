class_name SaveStore
extends RefCounted

const PATH = "user://progress.cfg"
# Compatibility paths only; these names are never displayed in the game.
const LEGACY_NAMES = ["烧烤串串消", "火锅串串消"]
var storage_path = PATH
var highest_unlocked = 1
var completed: Array = []
var last_selected = 1
var audio_enabled = true
var music_enabled = true
var vibration_enabled = true

func load_progress(path: String = "") -> void:
	if path.is_empty():
		path = storage_path
	var config = ConfigFile.new()
	var migrating = path == PATH and not FileAccess.file_exists(path)
	var source_path = path
	if migrating:
		# Renaming the application changes user://; retain existing prototype progress.
		source_path = _legacy_path(OS.get_user_data_dir().get_base_dir())
	if config.load(source_path) != OK:
		return
	highest_unlocked = clampi(int(config.get_value("progress", "highestUnlockedLevel", 1)), 1, 10)
	last_selected = clampi(int(config.get_value("progress", "lastSelectedLevel", 1)), 1, highest_unlocked)
	completed.clear()
	var saved = config.get_value("progress", "completedLevels", [])
	if saved is Array:
		for entry in saved:
			if entry is int and entry >= 1 and entry <= 10 and entry not in completed:
				completed.append(entry)
	audio_enabled = bool(config.get_value("settings", "audioEnabled", true))
	# Existing players who muted sound should not hear new music after upgrading.
	music_enabled = bool(config.get_value("settings", "musicEnabled", audio_enabled))
	vibration_enabled = bool(config.get_value("settings", "vibrationEnabled", true))
	if migrating:
		save_progress(path)

func _legacy_path(directory: String) -> String:
	for old_name in LEGACY_NAMES:
		var candidate = directory.path_join(old_name).path_join("progress.cfg")
		if FileAccess.file_exists(candidate):
			return candidate
	return PATH

func save_progress(path: String = "") -> Error:
	if path.is_empty():
		path = storage_path
	var config = ConfigFile.new()
	config.set_value("progress", "highestUnlockedLevel", highest_unlocked)
	config.set_value("progress", "completedLevels", completed)
	config.set_value("progress", "lastSelectedLevel", last_selected)
	config.set_value("settings", "audioEnabled", audio_enabled)
	config.set_value("settings", "musicEnabled", music_enabled)
	config.set_value("settings", "vibrationEnabled", vibration_enabled)
	var result = config.save(path)
	if result != OK:
		push_warning("Could not save progress: %s" % error_string(result))
	return result

func complete_level(number: int) -> void:
	if number not in completed:
		completed.append(number)
	highest_unlocked = maxi(highest_unlocked, mini(number + 1, 10))
	save_progress()
