class_name DevPanel
extends Control
## The owner's in-game powers (phase 20). Shown from the DEV button, which only
## ADMIN_TELEGRAM_IDS accounts get (welcome.dev); the server checks again and
## applies each command to the live zone. Ids match server/src/admin/devPowers.ts.

signal closed

enum Cmd { GOD = 1, AMMO = 2, MONEY = 3, SKIP_WAVE = 4, SPAWN_BOSS = 5, KILL_ALL = 6, GOTO_WAVE = 7, HEAL = 8 }

static var god := false   ## toggles as last sent (reset when a new game starts)
static var ammo := false

var _god_btn: Button
var _ammo_btn: Button


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(22))
	center.add_child(panel)
	var v := VBoxContainer.new()
	I18n.dir(v)
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := UiTheme.title(tr("DEVELOPER POWERS"), 30, UiTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	_god_btn = _add(grid, "", func():
		god = not god
		_send(Cmd.GOD)
		_refresh())
	_ammo_btn = _add(grid, "", func():
		ammo = not ammo
		_send(Cmd.AMMO)
		_refresh())
	_add(grid, "+10,000 $", func(): _send(Cmd.MONEY, 10000))
	_add(grid, tr("FULL HEAL"), func(): _send(Cmd.HEAL))
	_add(grid, tr("SKIP WAVE"), func(): _send(Cmd.SKIP_WAVE))
	_add(grid, tr("KILL ALL"), func(): _send(Cmd.KILL_ALL))
	_add(grid, tr("SUMMON THE WARDEN"), func(): _send(Cmd.SPAWN_BOSS))
	for n in [5, 10, 25]:
		_add(grid, tr("JUMP TO WAVE %d") % n, func(): _send(Cmd.GOTO_WAVE, n))
	var close := UiTheme.gold_button(tr("CLOSE"), func():
		closed.emit()
		queue_free())
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close)
	_refresh()


func _add(grid: GridContainer, text: String, cb: Callable) -> Button:
	var b := UiTheme.button(text, cb)
	b.custom_minimum_size = Vector2(250, 64)
	grid.add_child(b)
	return b


func _refresh() -> void:
	_god_btn.text = tr("GOD MODE: ON") if god else tr("GOD MODE: OFF")
	_ammo_btn.text = tr("INFINITE AMMO: ON") if ammo else tr("INFINITE AMMO: OFF")


func _send(cmd: int, arg := 0) -> void:
	Net.send("dev", {"cmd": cmd, "arg": arg})
	Platform.haptic("light")
