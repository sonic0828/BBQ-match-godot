extends SceneTree

var checks = 0
var failures: Array[String] = []
var directory = "/private/tmp/bbq-save-recovery-%d" % OS.get_process_id()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func snapshot(coins: int, level: int = 8) -> ConfigFile:
	var store = SaveStore.new()
	store.highest_unlocked = level
	store.last_selected = level
	store.completed = range(1, level)
	store.coins = coins
	store.bag_stock = 1
	store.bag_tutorial_done = true
	store.bag_day = "2026-09-29"
	store.run_serial = 12
	store.last_reward_run = 11
	store.save_progress(directory.path_join("fixture.cfg"))
	var config = ConfigFile.new()
	config.load(directory.path_join("fixture.cfg"))
	config.erase_section("storage")
	return config

func read_store(path: String) -> SaveStore:
	var store = SaveStore.new()
	store.storage_path = path
	store.load_progress()
	return store

func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var args = OS.get_cmdline_user_args()
	if args.size() == 2:
		var store = read_store(args[1])
		if args[0] == "write":
			store.coins = 650
			var run_id = store.begin_run()
			check(store.complete_level(8, run_id), "award level eight")
			check(store.consume_bag(true), "complete teaching")
			check(store.buy_bag() == OK, "exchange bag")
			check(store.coins == 400 and store.bag_stock == 1, "wallet and stock committed together")
		elif args[0] == "read":
			check(store.highest_unlocked == 9 and 8 in store.completed, "new process restores cleared level")
			check(store.bag_tutorial_done, "new process does not repeat teaching")
			check(store.coins == 400 and store.bag_stock == 1, "new process restores debit and credit")
			check(not store.complete_level(8, store.last_reward_run) and store.coins == 400, "reward stays deduplicated after process restart")
		finish()
		return
	var old = snapshot(650)
	var latest = snapshot(350, 9)
	var cases = ["newer", "invalid", "incomplete", "equal", "older", "modern", "pending"]
	for name in cases:
		old.save(directory.path_join(name + ".cfg"))
	latest.save(directory.path_join("equal.cfg.tmp"))
	while FileAccess.get_modified_time(directory.path_join("equal.cfg")) != FileAccess.get_modified_time(directory.path_join("equal.cfg.tmp")):
		old.save(directory.path_join("equal.cfg"))
		latest.save(directory.path_join("equal.cfg.tmp"))
	latest.save(directory.path_join("older.cfg.tmp"))
	# FileAccess modification timestamps have second resolution.
	await create_timer(1.1).timeout
	old.save(directory.path_join("older.cfg"))
	for name in ["newer", "invalid", "incomplete", "modern"]:
		latest.save(directory.path_join(name + ".cfg.tmp"))
	var invalid = ConfigFile.new()
	invalid.load(directory.path_join("invalid.cfg.tmp"))
	invalid.set_value("economy", "coins", -1)
	invalid.save(directory.path_join("invalid.cfg.tmp"))
	invalid = snapshot(999)
	invalid.erase_section_key("economy", "bagTutorialDone")
	invalid.save(directory.path_join("incomplete.cfg.tmp"))
	latest.save(directory.path_join("pending.cfg.pending"))
	var modern = read_store(directory.path_join("modern.cfg"))
	modern.coins = 50
	modern.save_progress()
	for name in cases:
		var path = directory.path_join(name + ".cfg")
		var before = FileAccess.get_file_as_bytes(path)
		var temp_before = FileAccess.get_file_as_bytes(path + ".tmp") if FileAccess.file_exists(path + ".tmp") else PackedByteArray()
		var store = read_store(path)
		var expected = 350 if name == "newer" else (50 if name == "modern" else 650)
		check(store.coins == expected, name + ": choose one complete snapshot")
		if name == "newer":
			check(store.highest_unlocked == 9 and store.bag_tutorial_done and store.bag_stock == 1, "recover progress, tutorial and wallet together")
			check(FileAccess.get_file_as_bytes(path + ".legacy-backup") == before, "old formal save preserved byte for byte")
		store.coins -= 1
		check(store.save_progress() == OK, name + ": can save after recovery decision")
		check(read_store(path).coins == expected - 1, name + ": stale temp never overwrites post-fix save")
		if not temp_before.is_empty():
			check(FileAccess.get_file_as_bytes(path + ".tmp") == temp_before, name + ": old temp retained untouched")
	var no_formal = directory.path_join("missing.cfg")
	latest.save(no_formal + ".tmp")
	check(read_store(no_formal).coins == 350, "recover complete legacy snapshot when formal save is absent")
	var padded = directory.path_join("padded.cfg")
	var file = FileAccess.open(padded + ".tmp", FileAccess.WRITE)
	file.store_buffer(latest.encode_to_text().to_utf8_buffer())
	file.store_buffer(PackedByteArray([0, 0, 0, 0]))
	file.close()
	check(read_store(padded).coins == 350, "legacy snapshot with template NUL padding can recover")
	# A real native rename failure must roll back the economy operation.
	var blocked_path = directory.path_join("directory-target")
	DirAccess.make_dir_absolute(blocked_path)
	var blocked = SaveStore.new()
	blocked.storage_path = blocked_path
	blocked.coins = 650
	check(blocked.buy_bag() != OK and blocked.coins == 650 and blocked.bag_stock == 0, "rename failure rolls back wallet and stock")
	check(not blocked.consume_bag(true) and not blocked.bag_tutorial_done, "failed save cannot complete teaching")
	finish()

func finish() -> void:
	for failure in failures: push_error(failure)
	print("Save persistence: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
