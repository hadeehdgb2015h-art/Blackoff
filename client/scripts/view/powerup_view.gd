class_name PowerupView
extends Node3D
## A power-up pickup lying where a zombie died: a slowly spinning glowing
## prism with the name above it and a small light. Blinks in its last seconds.
## Cosmetic only; the sim decides pickups.

const COLORS := {
	"instaKill": Color(1.0, 0.25, 0.2), "doublePoints": Color(1.0, 0.8, 0.2), "maxAmmo": Color(0.3, 0.75, 1.0),
	"nuke": Color(0.55, 1.0, 0.35), "fireSale": Color(1.0, 0.5, 0.9),
}

var powerup_id: int
var until: float = 0.0  ## sim time when it vanishes (for the blink)
var _mesh: MeshInstance3D
var _light := OmniLight3D.new()
var _label: Label3D
var _t: float = 0.0


func setup(id: int, type: String, display_name: String, pos: Vector2, until_time: float) -> void:
	powerup_id = id
	until = until_time
	position = Vector3(pos.x, 0.0, pos.y)
	var col: Color = COLORS.get(type, Color(0.8, 0.8, 1.0))
	_mesh = MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.36, 0.5, 0.36)
	_mesh.mesh = prism
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.3)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.2
	m.roughness = 0.3
	_mesh.material_override = m
	_mesh.position.y = 0.55
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_light.light_color = col
	_light.omni_range = 3.5
	_light.light_energy = 1.3
	_light.position.y = 0.7
	_light.shadow_enabled = false
	add_child(_light)
	_label = Label3D.new()
	_label.text = I18n.name_of(display_name)
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.outline_size = 10
	_label.modulate = col.lightened(0.4)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position.y = 1.15
	add_child(_label)


func update_view(sim_time: float, delta: float) -> void:
	_t += delta
	_mesh.rotation.y += delta * 2.2
	_mesh.position.y = 0.55 + sin(_t * 2.5) * 0.06
	var left := until - sim_time
	var on := true
	if left < 5.0:
		on = fmod(_t, 0.4) < 0.25  # blink before it vanishes
	_mesh.visible = on
	_light.visible = on
