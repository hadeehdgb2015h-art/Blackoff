class_name PlayerIntent
extends RefCounted
## One tick of player input. Mirrors the `input` message in shared/protocol.json.

const FIRE_HELD := 1
const RELOAD := 2
const INTERACT := 4
const REVIVE := 8
const SWITCH := 16
const FIRE_PRESSED := 32
const ADS := 64  ## aim down sights (held)

var seq: int = 0
var move := Vector2.ZERO  ## x = strafe right, y = forward; length <= 1
var yaw: float = 0.0
var pitch: float = 0.0
var buttons: int = 0


func has(bit: int) -> bool:
	return (buttons & bit) != 0
