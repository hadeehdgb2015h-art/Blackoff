extends SceneTree
## Headless test runner:  godot --headless --path client --script res://tests/run_tests.gd
## Exits with code 0 on success, 1 on any failure.

var _failures := 0
var _count := 0


func _initialize() -> void:
	var shared_script: GDScript = load("res://scripts/core/shared_data.gd")
	var shared: Node = shared_script.new()
	shared.reload()
	_check(shared.is_valid(), "shared data valid: %s" % "; ".join(shared.errors))
	_check(shared.weapons.has("pistol") and shared.weapons.has("rifle"), "both slice weapons defined")
	_check(shared.zombies.has("walker") and shared.zombies.has("runner"), "both slice zombies defined")
	_check(int(shared.constants.sim.tickRate) == 20, "tick rate is 20")
	shared.free()

	var boot: PackedScene = load("res://scenes/boot/boot.tscn")
	_check(boot != null and boot.can_instantiate(), "boot scene loads")

	print("TESTS: %d run, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_count += 1
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)
