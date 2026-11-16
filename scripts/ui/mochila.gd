extends Control
## Tela da mochila: personagem em 3D, 6 espaços de equipamento, 20 espaços de inventário,
## peso no canto e os botões VOLTAR, EQUIPAR, SOLTAR e USAR.
##
## Uso: var m = Mochila.new(); hud.add_child(m); m.abrir(jogo)
## (jogo = o nó do jogo3d; a mochila lê e muda jogo._bag e chama jogo._update_inventory())

signal closed

const Menu := preload("res://scripts/main_menu.gd")
const Perfil := preload("res://scripts/perfil.gd")
const Desenhos := preload("res://scripts/ui/desenhos.gd")
const Itens := preload("res://scripts/itens.gd")
const FONT_PATH := "res://fontes/oswald.fonte"

const C_TEXT := Color(0.93, 0.92, 0.89)
const C_DIM := Color(0.68, 0.67, 0.64)
const C_RED := Color(0.86, 0.13, 0.12)
const C_GREEN := Color(0.18, 0.78, 0.33)
const C_SLOT := Color(0.06, 0.06, 0.06, 0.72)
const C_SLOT_LINE := Color(0.78, 0.78, 0.76, 0.55)
const C_SEL := Color(1.0, 0.62, 0.25)
const COLS := 4
const ROWS := 5
const EQUIP := ["bone", "camisa", "colete", "calca", "botas", "mochila"]
const EQUIP_NAME := {"bone": "Boné", "camisa": "Camisa", "colete": "Colete", "calca": "Calça", "botas": "Botas", "mochila": "Mochila"}

static var _font: Font
static var _font_bold: Font

var _game: Node
var _items: Array = []          # [{id, nome, kg}] na ordem dos espaços
var _selected := -1
var _slots: Array = []          # botões da grade
var _weight_label: Label
var _weight_bar: ProgressBar
var _info: Label
var _btn := {}
var _view: SubViewport
var _pivot: Node3D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_font()
	_build()


func abrir(game: Node) -> void:
	_game = game
	_refresh()
	_build_character.call_deferred()


func fechar() -> void:
	closed.emit()
	queue_free()


func _process(delta: float) -> void:
	if _pivot and is_instance_valid(_pivot):
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, 0.0, minf(1.0, delta * 3.0))


func _gui_input(e: InputEvent) -> void:
	accept_event()


# ================== MONTAGEM ==================

static func _load_font() -> void:
	if _font != null:
		return
	var bytes := FileAccess.get_file_as_bytes(FONT_PATH)
	if bytes.is_empty():
		_font = ThemeDB.fallback_font
		_font_bold = ThemeDB.fallback_font
		return
	var ff := FontFile.new()
	ff.data = bytes
	var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	var reg := FontVariation.new()
	reg.base_font = ff
	reg.variation_opentype = {tag: 500}
	_font = reg
	var bold := FontVariation.new()
	bold.base_font = ff
	bold.variation_opentype = {tag: 700}
	_font_bold = bold


func _label(text: String, size_px: int, color := C_TEXT, bold := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font_bold if bold else _font)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	return l


static func _box(bg: Color, border: Color, bw := 2, radius := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _build() -> void:
	# o jogo fica atrás, escurecido
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + k, 22)
	mc.add_theme_constant_override("margin_top", 12)
	mc.add_theme_constant_override("margin_bottom", 14)
	add_child(mc)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	mc.add_child(root)

	# ---------- cabeçalho ----------
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, 92)
	head.add_theme_constant_override("separation", 18)
	root.add_child(head)
	var logo_icon := LogoIcon.new()
	logo_icon.custom_minimum_size = Vector2(92, 88)
	head.add_child(logo_icon)
	var logo := VBoxContainer.new()
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	logo.add_theme_constant_override("separation", -14)
	head.add_child(logo)
	logo.add_child(_label("LAST", 42))
	logo.add_child(_label("HORIZON", 42, C_RED))
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.5)
	sep.custom_minimum_size = Vector2(2, 70)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sep)
	var title := VBoxContainer.new()
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.add_theme_constant_override("separation", -6)
	head.add_child(title)
	title.add_child(_label("MOCHILA", 52))
	title.add_child(_label("EQUIPAMENTO E INVENTÁRIO", 20, C_DIM, false))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	var wbox := PanelContainer.new()
	wbox.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), 0, 6))
	wbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(wbox)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 6)
	wbox.add_child(wv)
	var wh := HBoxContainer.new()
	wh.add_theme_constant_override("separation", 16)
	wv.add_child(wh)
	var wi := WeightIcon.new()
	wi.custom_minimum_size = Vector2(46, 46)
	wh.add_child(wi)
	_weight_label = _label("0.0 / 30.0 KG", 32)
	wh.add_child(_weight_label)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(290, 16)
	_weight_bar.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0.6), Color(1, 1, 1, 0.45), 2, 5))
	var fill_sb := _box(C_GREEN, Color(0, 0, 0, 0), 0, 4)
	_weight_bar.add_theme_stylebox_override("fill", fill_sb)
	wv.add_child(_weight_bar)

	# ---------- corpo: personagem | equipamento | inventário ----------
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_stretch_ratio = 0.62
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(svc)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_2X
	svc.add_child(_view)

	var equip := VBoxContainer.new()
	equip.add_theme_constant_override("separation", 8)
	body.add_child(equip)
	for slot in EQUIP:
		var b := Button.new()
		b.custom_minimum_size = Vector2(118, 0)
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("normal", _box(C_SLOT, C_SLOT_LINE))
		b.add_theme_stylebox_override("hover", _box(Color(0.12, 0.12, 0.12, 0.8), C_SLOT_LINE))
		b.add_theme_stylebox_override("pressed", _box(C_SLOT, C_SEL))
		b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
		b.tooltip_text = EQUIP_NAME[slot]
		var ic := SlotIcon.new()
		ic.kind = slot
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		b.pressed.connect(func(): _say("%s: nada equipado." % EQUIP_NAME[slot]))
		equip.add_child(b)

	var div := ColorRect.new()
	div.color = Color(1, 1, 1, 0.45)
	div.custom_minimum_size = Vector2(2, 0)
	body.add_child(div)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	right.add_child(grid)
	for i in COLS * ROWS:
		var s := Button.new()
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
		s.toggle_mode = true
		s.add_theme_stylebox_override("normal", _box(C_SLOT, C_SLOT_LINE))
		s.add_theme_stylebox_override("hover", _box(Color(0.12, 0.12, 0.12, 0.8), C_SLOT_LINE))
		s.add_theme_stylebox_override("pressed", _box(Color(0.16, 0.11, 0.07, 0.85), C_SEL, 3))
		s.add_theme_stylebox_override("hover_pressed", _box(Color(0.16, 0.11, 0.07, 0.85), C_SEL, 3))
		s.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
		var ic := SlotIcon.new()
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_child(ic)
		var q := _label("", 18)
		q.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		q.offset_left = -90
		q.offset_top = -30
		q.offset_right = -8
		q.offset_bottom = -4
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		q.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		q.add_theme_constant_override("outline_size", 4)
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_child(q)
		s.pressed.connect(_select.bind(i))
		grid.add_child(s)
		_slots.append([s, ic, q])
	_info = _label("", 20, C_DIM, false)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.custom_minimum_size = Vector2(0, 28)
	right.add_child(_info)

	# ---------- botões ----------
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	bar.custom_minimum_size = Vector2(0, 66)
	root.add_child(bar)
	for t in ["VOLTAR", "EQUIPAR", "SOLTAR", "USAR"]:
		var b := Button.new()
		b.text = t
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", _font_bold)
		b.add_theme_font_size_override("font_size", 32)
		b.add_theme_color_override("font_color", C_TEXT)
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		b.add_theme_color_override("font_disabled_color", Color(C_TEXT, 0.3))
		b.add_theme_stylebox_override("normal", _box(Color(0.07, 0.07, 0.07, 0.88), Color(1, 1, 1, 0.3), 2, 10))
		b.add_theme_stylebox_override("hover", _box(Color(0.13, 0.13, 0.13, 0.9), Color(1, 1, 1, 0.5), 2, 10))
		b.add_theme_stylebox_override("pressed", _box(Color(0.2, 0.14, 0.08, 0.95), C_SEL, 2, 10))
		b.add_theme_stylebox_override("disabled", _box(Color(0.05, 0.05, 0.05, 0.7), Color(1, 1, 1, 0.12), 2, 10))
		b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
		bar.add_child(b)
		_btn[t] = b
	_btn.VOLTAR.pressed.connect(fechar)
	_btn.EQUIPAR.pressed.connect(_equip)
	_btn.USAR.pressed.connect(_use)
	_btn.SOLTAR.pressed.connect(_drop)


func _build_character() -> void:
	await get_tree().process_frame
	if _view == null or not is_instance_valid(_view):
		return
	var world := Node3D.new()
	_view.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 25, 0)
	key.light_energy = 1.3
	key.light_color = Color(1.0, 0.92, 0.82)
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_energy = 0.8
	rim.light_color = Color(0.7, 0.8, 1.0)
	world.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, 0.95, 4.3)
	world.add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0))
	_pivot = Node3D.new()
	world.add_child(_pivot)
	var body := Menu._load_character(Perfil.skin())
	if body:
		_pivot.add_child(body)


# ================== ITENS ==================

func _refresh() -> void:
	_items.clear()
	if _game and float(_game._bag) > 0.0005:
		_items.append({"id": "argila", "nome": "Argila", "kg": float(_game._bag)})
	if _game and int(_game._seeds) > 0:
		_items.append({"id": "semente", "nome": "Semente de Cedrinho", "kg": int(_game._seeds) * 0.002, "qtd": int(_game._seeds)})
	if _game:
		for id in _game._itens:
			var n := int(_game._itens[id])
			_items.append({"id": id, "nome": Itens.nome(id), "kg": Itens.kg(id) * n, "qtd": n})
	var total: float = _game._bag_total() if _game else 0.0
	var cap: float = _game.BAG_MAX if _game else 30.0
	_weight_label.text = "%.1f / %.1f KG" % [total, cap]
	_weight_bar.max_value = cap
	_weight_bar.value = total
	var fill: StyleBoxFlat = _weight_bar.get_theme_stylebox("fill").duplicate()
	fill.bg_color = C_GREEN if total < cap * 0.75 else (Color(0.95, 0.7, 0.15) if total < cap * 0.95 else C_RED)
	_weight_bar.add_theme_stylebox_override("fill", fill)
	for i in _slots.size():
		var s: Button = _slots[i][0]
		var ic = _slots[i][1]
		var q: Label = _slots[i][2]
		if i < _items.size():
			ic.kind = "item_" + str(_items[i].id)
			q.text = ("x%d" % int(_items[i].qtd)) if _items[i].has("qtd") else ("%.1f kg" % float(_items[i].kg)).replace(".", ",")
			if _game and str(_items[i].id) == str(_game._mao):
				q.text = "NA MÃO"
		else:
			ic.kind = ""
			q.text = ""
		ic.queue_redraw()
		s.set_pressed_no_signal(i == _selected)
	if _selected >= _items.size():
		_selected = -1
	var has := _selected >= 0
	var tool: bool = has and bool(Itens.ITENS.get(str(_items[_selected].id), {}).get("ferramenta", false))
	_btn.EQUIPAR.disabled = not tool
	_btn.EQUIPAR.text = "GUARDAR" if tool and _game and str(_game._mao) == str(_items[_selected].id) else "EQUIPAR"
	_btn.USAR.disabled = not has
	_btn.SOLTAR.disabled = not has
	if _info.text == "" or not has:
		_info.text = "Toque num item para ver o que fazer com ele." if not _items.is_empty() else "A mochila está vazia."


func _select(i: int) -> void:
	if i >= _items.size():
		_selected = -1
		_refresh()
		return
	_selected = i
	var it: Dictionary = _items[i]
	_refresh()
	if it.id == "semente":
		_say("%s · %d · USAR planta aqui, SOLTAR larga uma no chão" % [it.nome, int(it.qtd)])
	elif Itens.ITENS.has(str(it.id)) and it.id != "argila":
		_say("%s · %s kg · %s" % [it.nome, Itens.kg_txt(Itens.kg(str(it.id))), Itens.ITENS[it.id].desc])
	else:
		_say("%s · %s kg" % [it.nome, ("%.1f" % float(it.kg)).replace(".", ",")])


func _equip() -> void:
	if _selected < 0 or _selected >= _items.size() or _game == null:
		return
	var id := str(_items[_selected].id)
	if str(_game._mao) == id:
		_game.equip("")
		_refresh()
		_say("%s guardado na mochila." % Itens.nome(id))
		return
	_game.equip(id)
	fechar()


func _use() -> void:
	if _selected < 0 or _selected >= _items.size():
		return
	var it: Dictionary = _items[_selected]
	if it.id == "machado":
		_equip()
		return
	if it.id == "semente" and _game:
		if _game.put_seed_from_bag(true):
			fechar()
		else:
			_say("Não dá para plantar aqui. Vá para terra boa, longe da água e das pedras.")
		return
	_say("Não dá para usar a argila assim. Ela vai servir para fabricar coisas.")


func _drop() -> void:
	if _selected < 0 or _selected >= _items.size():
		return
	var it: Dictionary = _items[_selected]
	if it.id == "semente" and _game:
		_game.put_seed_from_bag(false)
		_refresh()
		_say("Você soltou uma semente no chão.")
		return
	if it.id == "argila" and _game:
		_game._bag = 0.0
		_game._update_inventory()
	elif _game and it.id != "semente":
		_game.drop_item(str(it.id), 1)
		_selected = -1
		_refresh()
		_say("Você soltou 1 %s no chão." % str(it.nome).to_lower())
		return
	_selected = -1
	_refresh()
	_say("Você soltou %s kg de %s." % [("%.1f" % float(it.kg)).replace(".", ","), str(it.nome).to_lower()])


func _say(t: String) -> void:
	_info.text = t


# ================== DESENHOS ==================

## Logo: dois pinheiros e uma torre de vigia, em branco.
class LogoIcon extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := Color(0.93, 0.92, 0.89)
		var base := h * 0.96
		for t in [[0.12, 0.55, 0.16], [0.3, 0.38, 0.2]]:
			var x: float = w * t[0]
			var top: float = h * t[1]
			var half: float = w * t[2]
			for k in 3:
				var y0 := top + (base - top) * k * 0.28
				var y1 := y0 + (base - top) * 0.42
				var hw := half * (0.55 + k * 0.25)
				draw_colored_polygon(PackedVector2Array([Vector2(x, y0), Vector2(x - hw, y1), Vector2(x + hw, y1)]), c)
		# torre: cabine, telhado, pernas e travessas
		var tx := w * 0.68
		var cw := w * 0.26
		var cab_y := h * 0.18
		draw_colored_polygon(PackedVector2Array([Vector2(tx - cw * 0.65, cab_y), Vector2(tx, h * 0.04), Vector2(tx + cw * 0.65, cab_y)]), c)
		draw_rect(Rect2(tx - cw * 0.5, cab_y, cw, h * 0.13), c, false, 2.0)
		draw_line(Vector2(tx - cw * 0.55, cab_y + h * 0.13), Vector2(tx + cw * 0.55, cab_y + h * 0.13), c, 3.0)
		var top_l := Vector2(tx - cw * 0.4, cab_y + h * 0.13)
		var top_r := Vector2(tx + cw * 0.4, cab_y + h * 0.13)
		var bot_l := Vector2(tx - cw * 0.75, base)
		var bot_r := Vector2(tx + cw * 0.75, base)
		draw_line(top_l, bot_l, c, 2.5)
		draw_line(top_r, bot_r, c, 2.5)
		for k in 3:
			var t0 := 0.18 + k * 0.28
			var t1 := t0 + 0.28
			draw_line(top_l.lerp(bot_l, t0), top_r.lerp(bot_r, t1), c, 1.5)
			draw_line(top_r.lerp(bot_r, t0), top_l.lerp(bot_l, t1), c, 1.5)
			draw_line(top_l.lerp(bot_l, t1), top_r.lerp(bot_r, t1), c, 1.5)


## Peso (como um peso de balança), em branco.
class WeightIcon extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := Color(0.93, 0.92, 0.89)
		draw_arc(Vector2(w * 0.5, h * 0.24), w * 0.14, 0, TAU, 20, c, 3.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.3, h * 0.38), Vector2(w * 0.7, h * 0.38),
			Vector2(w * 0.95, h * 0.95), Vector2(w * 0.05, h * 0.95)]), c)


## Desenho de cada espaço: silhueta clara da peça (equipamento vazio) ou o item guardado.
class SlotIcon extends Control:
	const Desenhos := preload("res://scripts/ui/desenhos.gd")
	var kind := ""

	func _draw() -> void:
		if kind == "":
			return
		var s := minf(size.x, size.y) * 0.72
		var c := size * 0.5
		var faint := Color(1, 1, 1, 0.18)
		match kind:
			"item_argila":
				_clay(c, s)
			"item_semente":
				_seed(c, s)
			"mochila":
				Desenhos.backpack(self, c + Vector2(0, s * 0.04), s * 0.9, faint, Color(1, 1, 1, 0.0))
			_:
				if kind.begins_with("item_"):
					Desenhos.item(self, kind.substr(5), c, s)
				else:
					_silhouette(kind, c, s, faint)

	func _seed(c: Vector2, s: float) -> void:
		# fruto do Cedrinho: semente com uma asa comprida
		var body := PackedVector2Array([c + Vector2(s * 0.18, 0), c + Vector2(s * 0.05, -s * 0.1), c + Vector2(-s * 0.08, 0), c + Vector2(s * 0.05, s * 0.1)])
		var wing := PackedVector2Array([c + Vector2(-s * 0.04, -s * 0.06), c + Vector2(-s * 0.42, -s * 0.16), c + Vector2(-s * 0.46, -s * 0.04), c + Vector2(-s * 0.04, s * 0.05)])
		draw_colored_polygon(wing, Color(0.66, 0.5, 0.32))
		draw_polyline(wing + PackedVector2Array([wing[0]]), Color(0.35, 0.24, 0.13), 1.5, true)
		for k in 4:
			var t := 0.2 + k * 0.2
			draw_line(c.lerp(c + Vector2(-s * 0.44, -s * 0.1), t) + Vector2(0, -s * 0.05), c.lerp(c + Vector2(-s * 0.44, -s * 0.1), t) + Vector2(0, s * 0.05), Color(0.45, 0.32, 0.18, 0.7), 1.0)
		draw_colored_polygon(body, Color(0.42, 0.26, 0.14))
		draw_polyline(body + PackedVector2Array([body[0]]), Color(0.25, 0.14, 0.07), 1.5, true)

	func _clay(c: Vector2, s: float) -> void:
		var pts := PackedVector2Array()
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for i in 18:
			var a := TAU * i / 18.0
			var r := s * 0.36 * rng.randf_range(0.82, 1.08)
			pts.append(c + Vector2(cos(a) * r * 1.25, sin(a) * r * 0.85 + s * 0.04))
		draw_colored_polygon(pts, Color(0.55, 0.3, 0.19))
		var hi := PackedVector2Array()
		for p in pts:
			hi.append(c + (p - c) * 0.55 + Vector2(-s * 0.06, -s * 0.08))
		draw_colored_polygon(hi, Color(0.68, 0.4, 0.26))
		draw_circle(c + Vector2(-s * 0.12, -s * 0.12), s * 0.06, Color(0.82, 0.56, 0.4, 0.8))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.3, 0.15, 0.09), 2.0, true)

	func _silhouette(k: String, c: Vector2, s: float, col: Color) -> void:
		var u := s / 100.0
		var P := func(arr: Array) -> PackedVector2Array:
			var out := PackedVector2Array()
			for p in arr:
				out.append(c + Vector2(p[0], p[1]) * u)
			return out
		match k:
			"bone":
				draw_colored_polygon(P.call([[-34, 8], [-30, -16], [-14, -30], [10, -30], [28, -16], [32, 8]]), col)
				draw_colored_polygon(P.call([[24, 2], [52, 10], [50, 18], [20, 14]]), col)
			"camisa":
				draw_colored_polygon(P.call([[-14, -36], [14, -36], [44, -22], [36, 0], [24, -6], [24, 40], [-24, 40], [-24, -6], [-36, 0], [-44, -22]]), col)
			"colete":
				draw_colored_polygon(P.call([[-30, -36], [-12, -36], [-6, -20], [6, -20], [12, -36], [30, -36], [34, 40], [-34, 40]]), col)
				for y in [-2, 16]:
					draw_rect(Rect2(c + Vector2(-26, y) * u, Vector2(18, 14) * u), Color(0, 0, 0, 0.25))
					draw_rect(Rect2(c + Vector2(8, y) * u, Vector2(18, 14) * u), Color(0, 0, 0, 0.25))
			"calca":
				draw_colored_polygon(P.call([[-24, -40], [24, -40], [28, 44], [8, 44], [0, -4], [-8, 44], [-28, 44]]), col)
			"botas":
				for dx in [-24, 16]:
					draw_colored_polygon(P.call([[dx - 4, -34], [dx + 10, -34], [dx + 12, 20], [dx + 26, 30], [dx + 26, 40], [dx - 6, 40]]), col)


## Botão da mochila no jogo: só o desenho da mochila, sem bola em volta.
class BackpackButton extends Button:
	const Desenhos := preload("res://scripts/ui/desenhos.gd")

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())

	func _draw() -> void:
		var c := size * 0.5
		var s := minf(size.x, size.y) * 0.92
		var col := Color(0.42, 0.45, 0.27) if not is_pressed() else Color(0.55, 0.58, 0.35)
		# sombra suave para destacar do cenário
		Desenhos.backpack(self, c + Vector2(2, 3), s, Color(0, 0, 0, 0.45), Color(0, 0, 0, 0))
		Desenhos.backpack(self, c, s, col, Color(0, 0, 0, 0.22))
