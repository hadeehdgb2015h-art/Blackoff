extends SceneTree
## Headless test runner:  godot --headless --path client --script res://tests/run_tests.gd
## Runs every tests/test_*.gd. Each file extends TestCase and defines test_* methods.
## Exits 0 on success, 1 on any failure. Optional filter: -- <substring>

## Captures engine/script errors so a runtime error fails the current test.
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		errors.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function])
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var total := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at("res://tests/"))
	files.sort()
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		catcher.errors.clear()
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			total += 1
			failed += 1
			printerr("  FAIL %s: cannot load test file: %s" % [f, "; ".join(catcher.errors)])
			continue
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_") or (filter != "" and not (f + ":" + name).contains(filter)):
				continue
			catcher.errors.clear()
			var tc: TestCase = script.new()
			var t0 := Time.get_ticks_usec()
			tc.call(name)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			total += 1
			tc.failures.append_array(catcher.errors)
			if tc.failures.is_empty():
				print("  ok   %s:%s (%.0f ms)" % [f, name, ms])
			else:
				failed += 1
				for msg in tc.failures:
					printerr("  FAIL %s:%s: %s" % [f, name, msg])
	print("TESTS: %d run, %d failed" % [total, failed])
	quit(1 if failed > 0 or total == 0 else 0)
