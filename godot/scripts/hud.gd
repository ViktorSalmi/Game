extends CanvasLayer
## AoE-inspirerat gränssnitt (platshållare): resursrad, info, minikarta, legend.

const GOLD := Color("a07a34")
const CREAM := Color("f2e6c4")
const DIM := Color("b9a57a")

var res_label: Label
var era_label: Label
var fps_label: Label
var info_label: Label
var legend_panel: PanelContainer
var legend_label: RichTextLabel
var minimap_holder: PanelContainer
var help_label: Label
var buttons := {}
var speed_buttons := {}
var log_label: RichTextLabel
var sel_panel: PanelContainer
var sel_label: Label
var log_lines: Array = []

func style(bg_top: Color = Color("45321b")) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg_top
	s.border_color = GOLD
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.shadow_size = 6
	s.shadow_color = Color(0, 0, 0, 0.5)
	return s

func _label(text: String, size: int = 14, col: Color = CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	return l

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", style(Color("5a4121")))
	b.add_theme_stylebox_override("hover", style(Color("74552b")))
	b.add_theme_stylebox_override("pressed", style(Color("3a2a14")))
	b.add_theme_color_override("font_color", CREAM)
	return b

func build() -> void:
	# övre rad
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", style())
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	top.add_child(hb)
	res_label = _label("Trä 200   Mat 200   Guld 100   Sten 200   Befolkning 1/5", 14)
	hb.add_child(res_label)
	era_label = _label("Mörka åldern", 14, Color("ffd36b"))
	hb.add_child(era_label)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	fps_label = _label("", 13, DIM)
	hb.add_child(fps_label)
	for k in ["Paus", "1×", "2×", "4×", "8×", "16×"]:
		var sb := _button(k)
		speed_buttons[k] = sb
		hb.add_child(sb)
	for k in ["Karta", "Dimma", "Info"]:
		var b := _button(k)
		buttons[k] = b
		hb.add_child(b)
	# info (hover)
	var ip := PanelContainer.new()
	ip.add_theme_stylebox_override("panel", style())
	ip.position = Vector2(14, 56)
	add_child(ip)
	info_label = _label("", 14)
	info_label.custom_minimum_size = Vector2(270, 0)
	ip.add_child(info_label)
	# legend
	legend_panel = PanelContainer.new()
	legend_panel.add_theme_stylebox_override("panel", style())
	legend_panel.position = Vector2(14, 160)
	legend_panel.visible = false
	add_child(legend_panel)
	legend_label = RichTextLabel.new()
	legend_label.bbcode_enabled = true
	legend_label.fit_content = true
	legend_label.custom_minimum_size = Vector2(270, 0)
	legend_label.scroll_active = false
	legend_label.add_theme_color_override("default_color", CREAM)
	legend_panel.add_child(legend_label)
	# minikarta
	minimap_holder = PanelContainer.new()
	var ms := style(Color("2b1d0f"))
	ms.set_border_width_all(3)
	minimap_holder.add_theme_stylebox_override("panel", ms)
	minimap_holder.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap_holder.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	minimap_holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	minimap_holder.offset_right = -14
	minimap_holder.offset_bottom = -14
	add_child(minimap_holder)
	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", style(Color("2b1d0f")))
	lp.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	lp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lp.offset_left = 14
	lp.offset_bottom = -36
	add_child(lp)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.scroll_active = false
	log_label.custom_minimum_size = Vector2(440, 0)
	log_label.add_theme_color_override("default_color", CREAM)
	log_label.add_theme_font_size_override("normal_font_size", 13)
	lp.add_child(log_label)
	sel_panel = PanelContainer.new()
	sel_panel.add_theme_stylebox_override("panel", style())
	sel_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	sel_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sel_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sel_panel.offset_right = -14
	sel_panel.offset_bottom = -150
	sel_panel.visible = false
	add_child(sel_panel)
	sel_label = _label("", 14)
	sel_label.custom_minimum_size = Vector2(270, 0)
	sel_panel.add_child(sel_label)
	help_label = _label("WASD/pilar: panorera · mushjul: zoom · högerklick: flytta spejaren · mitten-dra: panorera · M: hela kartan · F: dimma · L: förklaring · Esc: avsluta", 12, DIM)
	help_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help_label.offset_bottom = -8
	add_child(help_label)

func add_log(text: String, important: bool = false) -> void:
	log_lines.append(("[color=#ffd36b]%s[/color]" % text) if important else text)
	while log_lines.size() > 8:
		log_lines.pop_front()
	log_label.text = "\n".join(log_lines)

func set_legend(data) -> void:
	var cols := ["1f5d9c", "55a9db", "e0cf94", "79b24b", "386e34", "cdb06a", "8f8a7c", "f4f7fa", "7f9f7d", "bdb7a8"]
	var total := 0
	for i in 10:
		total += data.counts[i]
	var t := "[b]%s[/b]\n" % data.map_name
	for i in [0, 1, 4, 3, 8, 9, 6]:
		t += "[color=#%s]■[/color]  %s   [color=#b9a57a]%.1f %%[/color]\n" % [cols[i], data.BIOME_NAMES[i], 100.0 * data.counts[i] / maxf(1.0, total)]
	t += "\n[color=#b9a57a]%d orter · %d sevärdheter\n1 ruta = %d m · %d×%d[/color]" % [data.places.size(), data.pois.size(), int(data.cell_m), data.w, data.h]
	legend_label.text = t
