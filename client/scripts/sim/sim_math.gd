class_name SimMath
extends RefCounted
## Angle conventions shared with the server. yaw = 0 faces -Z; positive yaw
## turns left (Godot rotation.y). Sim plane = (x, z) stored in Vector2(x, y).


static func forward(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


static func right(yaw: float) -> Vector2:
	return Vector2(cos(yaw), -sin(yaw))


static func yaw_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(-d.x, -d.y)


static func dir3(yaw: float, pitch: float) -> Vector3:
	var cp := cos(pitch)
	return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)


static func wrap_angle(a: float) -> float:
	return wrapf(a, -PI, PI)


static func approach_angle(cur: float, target: float, max_step: float) -> float:
	var diff := wrap_angle(target - cur)
	return cur + clampf(diff, -max_step, max_step)
