class_name SimZombie
extends RefCounted
## Authoritative zombie state. Behaviour lives in ZombieBrain.

enum State { CHASE, WINDUP }

var id: int
var type: String
var def: Dictionary
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var yaw: float = 0.0
var hp: float = 100.0
var max_hp: float = 100.0
var speed: float = 1.5
var state: State = State.CHASE
var target_id: int = -1
var attack_ready_time: float = 0.0
var windup_end: float = 0.0
var path := PackedVector2Array()
var path_index: int = 0
var path_goal := Vector2.INF
var next_repath_time: float = 0.0
var stuck_check_time: float = 0.0
var stuck_check_pos := Vector2.ZERO
var moving: bool = false


func radius() -> float:
	return float(def.radius)
