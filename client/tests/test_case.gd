class_name TestCase
extends RefCounted
## Minimal assertion helpers for headless tests.

var failures: PackedStringArray = []
static var _defs: Dictionary = {}


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(a: Variant, b: Variant, msg: String) -> void:
	if a != b:
		failures.append("%s (got %s, expected %s)" % [msg, str(a), str(b)])


func near(a: float, b: float, eps: float, msg: String) -> void:
	if absf(a - b) > eps:
		failures.append("%s (got %f, expected %f ±%f)" % [msg, a, b, eps])


## Shared data loaded once per run.
static func defs() -> Dictionary:
	if _defs.is_empty():
		_defs = SharedLoader.load_all()
	return _defs
