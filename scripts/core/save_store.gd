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
const BAG_COST = 300
const WIN_COINS = 50
var coins = 0
var bag_stock = 0
var bag_tutorial_done = false
var bag_day = ""
var bag_daily_used = false
var run_serial = 0
var last_reward_run = 0
var last_ad_receipt = ""

func load_progress(path: String = "") -> void:
	if path.is_empty():
		path = storage_path
	var config = ConfigFile.new()
	var migrating = path == PATH and not FileAccess.file_exists(path)
	var source_path = path
	if migrating:
		# Renaming the application changes user://; retain existing prototype progress.
		source_path = _legacy_path(OS.get_user_data_dir().get_base_dir())
	var loaded = config.load(source_path)
	var recovered = false
	# Old WeChat builds left committed-looking snapshots in .tmp. New writes
	# use .pending; failed new transactions must never be recovered as successes.
	var legacy_temp = path + ".tmp"
	if int(config.get_value("storage", "format", 0)) == 0 and FileAccess.file_exists(legacy_temp):
		var candidate = ConfigFile.new()
		var newer = FileAccess.get_modified_time(legacy_temp) > FileAccess.get_modified_time(source_path)
		if newer and candidate.load(legacy_temp) == OK and _valid_recovery_snapshot(candidate):
			config = candidate
			recovered = true
	if loaded != OK and not recovered:
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
	var economy_migration = not config.has_section("economy")
	coins = maxi(0, int(config.get_value("economy", "coins", completed.size() * WIN_COINS)))
	bag_stock = maxi(0, int(config.get_value("economy", "bagStock", 0)))
	bag_tutorial_done = bool(config.get_value("economy", "bagTutorialDone", false))
	bag_day = str(config.get_value("economy", "bagDay", ""))
	bag_daily_used = bool(config.get_value("economy", "bagDailyUsed", false))
	run_serial = maxi(0, int(config.get_value("economy", "runSerial", 0)))
	last_reward_run = maxi(0, int(config.get_value("economy", "lastRewardRun", 0)))
	last_ad_receipt = str(config.get_value("economy", "lastAdReceipt", ""))
	if migrating or economy_migration or recovered:
		var result = save_progress(path)
		if recovered and result == OK:
			print("[BBQ save] Recovered complete legacy snapshot; original files retained")

func _valid_recovery_snapshot(config: ConfigFile) -> bool:
	var fields = {
		"progress": {"highestUnlockedLevel": TYPE_INT, "lastSelectedLevel": TYPE_INT, "completedLevels": TYPE_ARRAY},
		"settings": {"audioEnabled": TYPE_BOOL, "musicEnabled": TYPE_BOOL, "vibrationEnabled": TYPE_BOOL},
		"economy": {"coins": TYPE_INT, "bagStock": TYPE_INT, "bagTutorialDone": TYPE_BOOL,
			"bagDay": TYPE_STRING, "bagDailyUsed": TYPE_BOOL, "runSerial": TYPE_INT, "lastRewardRun": TYPE_INT},
	}
	for section in fields:
		for key in fields[section]:
			if not config.has_section_key(section, key) or typeof(config.get_value(section, key)) != fields[section][key]: return false
	var highest = config.get_value("progress", "highestUnlockedLevel")
	var selected = config.get_value("progress", "lastSelectedLevel")
	if highest < 1 or highest > 10 or selected < 1 or selected > highest: return false
	var seen: Array = []
	for level in config.get_value("progress", "completedLevels"):
		if not level is int or level < 1 or level > 10 or level in seen or mini(level + 1, 10) > highest: return false
		seen.append(level)
	for key in ["coins", "bagStock", "runSerial", "lastRewardRun"]:
		if config.get_value("economy", key) < 0: return false
	var day: String = config.get_value("economy", "bagDay")
	if not day.is_empty() and (day.length() != 10 or Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(day)) != day): return false
	return config.get_value("economy", "lastRewardRun") <= config.get_value("economy", "runSerial")

func _legacy_path(directory: String) -> String:
	for old_name in LEGACY_NAMES:
		var candidate = directory.path_join(old_name).path_join("progress.cfg")
		if FileAccess.file_exists(candidate):
			return candidate
	return PATH

func save_progress(path: String = "") -> Error:
	if path.is_empty():
		path = storage_path
	# Preserve both old candidates before the first post-fix overwrite. Leave
	# .tmp untouched even when incomplete or its timestamp cannot be trusted.
	if FileAccess.file_exists(path + ".tmp") and FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".legacy-backup"):
		var original = FileAccess.open(path, FileAccess.READ)
		if original == null: return FileAccess.get_open_error()
		var bytes = original.get_buffer(original.get_length())
		if bytes.size() != original.get_length(): return ERR_FILE_CANT_READ
		original.close()
		var backup_result = _commit_snapshot(bytes, path + ".legacy-backup")
		if backup_result != OK: return backup_result
	var config = ConfigFile.new()
	config.set_value("storage", "format", 1)
	config.set_value("progress", "highestUnlockedLevel", highest_unlocked)
	config.set_value("progress", "completedLevels", completed)
	config.set_value("progress", "lastSelectedLevel", last_selected)
	config.set_value("settings", "audioEnabled", audio_enabled)
	config.set_value("settings", "musicEnabled", music_enabled)
	config.set_value("settings", "vibrationEnabled", vibration_enabled)
	config.set_value("economy", "coins", coins)
	config.set_value("economy", "bagStock", bag_stock)
	config.set_value("economy", "bagTutorialDone", bag_tutorial_done)
	config.set_value("economy", "bagDay", bag_day)
	config.set_value("economy", "bagDailyUsed", bag_daily_used)
	config.set_value("economy", "runSerial", run_serial)
	config.set_value("economy", "lastRewardRun", last_reward_run)
	config.set_value("economy", "lastAdReceipt", last_ad_receipt)
	# Replace one complete snapshot: never persist a debit without its item credit.
	var result = _commit_snapshot(config.encode_to_text().to_utf8_buffer(), path)
	if result != OK:
		push_warning("Could not save progress: %s" % error_string(result))
	return result

func _commit_snapshot(bytes: PackedByteArray, path: String) -> Error:
	var file = FileAccess.open(path + ".pending", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(bytes)
	var result = file.get_error()
	file.close()
	if result != OK: return result
	return DirAccess.rename_absolute(path + ".pending", path)

func begin_run() -> int:
	run_serial += 1
	if save_progress() != OK:
		run_serial -= 1
		return -1
	return run_serial

func complete_level(number: int, run_id: int = -1) -> bool:
	var before = [completed.duplicate(), highest_unlocked, coins, last_reward_run]
	if number not in completed:
		completed.append(number)
	highest_unlocked = maxi(highest_unlocked, mini(number + 1, 10))
	var reward = run_id > last_reward_run and run_id <= run_serial
	if reward:
		coins += WIN_COINS
		last_reward_run = run_id
	if save_progress() != OK:
		completed.assign(before[0])
		highest_unlocked = before[1]
		coins = before[2]
		last_reward_run = before[3]
		return false
	return reward

func refresh_daily(unix_time: float = -1) -> bool:
	if unix_time < 0: unix_time = Time.get_unix_time_from_system()
	var today = Time.get_date_string_from_unix_time(int(unix_time) + 8 * 3600)
	# Clock rollback cannot refill a day that has already been consumed.
	if today <= bag_day: return true
	var before = [bag_day, bag_daily_used]
	bag_day = today
	bag_daily_used = false
	if save_progress() == OK: return true
	bag_day = before[0]
	bag_daily_used = before[1]
	return false

func available_bags() -> int:
	return bag_stock + (0 if bag_daily_used else 1)

func buy_bag() -> Error:
	if coins < BAG_COST: return ERR_UNAVAILABLE
	coins -= BAG_COST
	bag_stock += 1
	var result = save_progress()
	if result != OK:
		coins += BAG_COST
		bag_stock -= 1
	return result

func grant_ad_bag(receipt: String) -> Error:
	if receipt.is_empty(): return ERR_INVALID_PARAMETER
	if receipt == last_ad_receipt: return OK
	var previous = last_ad_receipt
	bag_stock += 1
	last_ad_receipt = receipt
	var result = save_progress()
	if result != OK:
		bag_stock -= 1
		last_ad_receipt = previous
	return result

func consume_bag(tutorial_use: bool = false) -> bool:
	if not refresh_daily(): return false
	var before = [bag_tutorial_done, bag_daily_used, bag_stock]
	if tutorial_use:
		if bag_tutorial_done: return false
		bag_tutorial_done = true
	elif not bag_daily_used:
		bag_daily_used = true
	elif bag_stock > 0:
		bag_stock -= 1
	else:
		return false
	if save_progress() == OK: return true
	bag_tutorial_done = before[0]
	bag_daily_used = before[1]
	bag_stock = before[2]
	return false
