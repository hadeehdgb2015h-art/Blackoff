extends Node3D
## Phase 0 boot / smoke-test scene. Proves on a real phone that:
## the Web export loads, the Compatibility renderer draws lit 3D with fog,
## shared JSON data is present and valid, and Telegram integration is detected.
## Replaced by the main menu in phase 1.

@onready var _info: Label = %Info
@onready var _fps: Label = %Fps
@onready var _spinner: Node3D = %Spinner
@onready var _alarm: OmniLight3D = %AlarmLight

var _t := 0.0


func _ready() -> void:
	%FullscreenButton.pressed.connect(Platform.request_fullscreen)
	%FullscreenButton.text = tr("Fullscreen")
	_info.text = _build_info()


func _process(delta: float) -> void:
	_t += delta
	_spinner.rotate_y(delta * 0.8)
	_alarm.light_energy = 1.2 + 0.8 * sin(_t * 4.0)
	_fps.text = tr("%d FPS") % Engine.get_frames_per_second()


func _build_info() -> String:
	var v := Engine.get_version_info()
	var lines := PackedStringArray()
	lines.append(tr("%s — phase 0 build") % "BLACKOFF")
	lines.append("Godot %s.%s.%s %s" % [v.major, v.minor, v.patch, v.status])
	lines.append(tr("Renderer: %s") % RenderingServer.get_current_rendering_method())
	lines.append(tr("GPU: %s") % RenderingServer.get_video_adapter_name())
	lines.append(tr("Web: %s  Touch: %s  Telegram: %s %s") % [
		Platform.is_web, Platform.is_touch, Platform.is_telegram, Platform.telegram_platform])
	if SharedData.is_valid():
		lines.append(tr("Shared data OK: protocol v%d, %d weapons, %d zombies") % [
			int(SharedData.protocol.get("protocolVersion", 0)), SharedData.weapons.size(), SharedData.zombies.size()])
	else:
		lines.append(tr("Shared data ERROR: %s") % "; ".join(SharedData.errors))
	return "\n".join(lines)
