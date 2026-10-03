class_name SettingsPanel
extends PanelContainer
## Settings dialog used by the main menu and the pause menu.

signal closed

signal open_layout

var _sens_label: Label
var _vol_label: Label
var _music_label: Label
var _sfx_label: Label
var _restart: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(620, 0)
	# the list is taller than a phone screen: it scrolls (drag with a finger)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(580, minf(640.0, get_viewport_rect().size.y - 70.0))
	add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	I18n.dir(v)
	v.add_child(UiTheme.title(tr("SETTINGS"), 30, UiTheme.GOLD))
	v.add_child(UiTheme.rule(560))

	# Language (phase 24): the page reloads so every text is rebuilt in it
	v.add_child(UiTheme.label(tr("Language"), 18, UiTheme.MUTED))
	var langs := HBoxContainer.new()
	langs.add_theme_constant_override("separation", 8)
	var lgroup := ButtonGroup.new()
	for code in I18n.LANGS:
		var b := Button.new()
		b.text = I18n.NAMES[code]
		b.toggle_mode = true
		b.button_group = lgroup
		b.button_pressed = I18n.lang == code
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func():
			if code == I18n.lang:
				return
			for c in langs.get_children():
				(c as Button).disabled = true
			_restart.text = tr("Restarting in %s…") % I18n.NAMES[code]
			_restart.visible = true
			Settings.save()
			I18n.set_language(code))
		langs.add_child(b)
	v.add_child(langs)
	_restart = UiTheme.label("", 16, UiTheme.GOLD)
	_restart.visible = false
	v.add_child(_restart)

	_sens_label = UiTheme.label("")
	v.add_child(_sens_label)
	var sens := HSlider.new()
	sens.min_value = 0.2
	sens.max_value = 3.0
	sens.step = 0.05
	sens.value = Settings.sensitivity
	sens.custom_minimum_size = Vector2(0, 40)
	sens.value_changed.connect(_on_sens)
	v.add_child(sens)

	_vol_label = UiTheme.label("")
	v.add_child(_vol_label)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Settings.master_volume
	vol.custom_minimum_size = Vector2(0, 40)
	vol.value_changed.connect(_on_vol)
	v.add_child(vol)

	_music_label = UiTheme.label("")
	v.add_child(_music_label)
	var music := HSlider.new()
	music.min_value = 0.0
	music.max_value = 1.0
	music.step = 0.05
	music.value = Settings.music_volume
	music.custom_minimum_size = Vector2(0, 40)
	music.value_changed.connect(func(val: float):
		Settings.music_volume = val
		_music_label.text = tr("Music: %d%%") % roundi(val * 100)
		Audio.apply_volumes())
	v.add_child(music)
	_sfx_label = UiTheme.label("")
	v.add_child(_sfx_label)
	var sfx := HSlider.new()
	sfx.min_value = 0.0
	sfx.max_value = 1.0
	sfx.step = 0.05
	sfx.value = Settings.sfx_volume
	sfx.custom_minimum_size = Vector2(0, 40)
	sfx.value_changed.connect(func(val: float):
		Settings.sfx_volume = val
		_sfx_label.text = tr("Sound effects: %d%%") % roundi(val * 100)
		Audio.apply_volumes())
	v.add_child(sfx)
	_music_label.text = tr("Music: %d%%") % roundi(Settings.music_volume * 100)
	_sfx_label.text = tr("Sound effects: %d%%") % roundi(Settings.sfx_volume * 100)
	v.add_child(UiTheme.button(tr("CONTROLS LAYOUT  ·  move and resize buttons"), func():
		open_layout.emit()
		_close()))

	v.add_child(UiTheme.label(tr("Graphics quality  (Auto picks a tier from your frame rate)"), 18, UiTheme.MUTED))
	var q := HBoxContainer.new()
	q.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for name in Settings.QUALITY:
		var b := Button.new()
		b.text = {"auto": tr("Auto"), "low": tr("Low"), "medium": tr("Medium"), "high": tr("High")}.get(name, name.capitalize())
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = Settings.quality == name
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func(): Settings.quality = name)
		q.add_child(b)
	v.add_child(q)
	v.add_child(UiTheme.label(tr("Frame rate  (Auto: a steady 30 on phones, cooler and smoother; try 60 if your phone is strong)"), 18, UiTheme.MUTED))
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 8)
	var fgroup := ButtonGroup.new()
	for cap in [0, 60, 30]:
		var b := Button.new()
		b.text = tr("Auto") if cap == 0 else tr("%d FPS") % cap
		b.toggle_mode = true
		b.button_group = fgroup
		b.button_pressed = Settings.fps_cap == cap
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func(): Settings.fps_cap = cap)
		fr.add_child(b)
	v.add_child(fr)

	var tpp := CheckButton.new()
	tpp.text = tr("Third-person camera (over the shoulder)")
	tpp.button_pressed = Settings.third_person
	tpp.toggled.connect(func(on): Settings.third_person = on)
	v.add_child(tpp)
	var inv := CheckButton.new()
	inv.text = tr("Invert vertical look")
	inv.button_pressed = Settings.invert_y
	inv.toggled.connect(func(on): Settings.invert_y = on)
	v.add_child(inv)
	var fps := CheckButton.new()
	fps.text = tr("Show FPS")
	fps.button_pressed = Settings.show_fps
	fps.toggled.connect(func(on): Settings.show_fps = on)
	v.add_child(fps)

	var spk := CheckButton.new()
	spk.text = tr("Voice chat: hear other players")
	spk.button_pressed = Settings.voice_speaker
	spk.toggled.connect(func(on): Settings.voice_speaker = on)
	v.add_child(spk)

	v.add_child(UiTheme.gold_button(tr("DONE"), _close))
	_refresh()


func _on_sens(x: float) -> void:
	Settings.sensitivity = x
	_refresh()


func _on_vol(x: float) -> void:
	Settings.master_volume = x
	_refresh()


func _refresh() -> void:
	_sens_label.text = tr("Look sensitivity: %.2f") % Settings.sensitivity
	_vol_label.text = tr("Volume: %d%%") % roundi(Settings.master_volume * 100)


func _close() -> void:
	Settings.save()
	closed.emit()
	queue_free()
