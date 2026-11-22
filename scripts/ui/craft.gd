extends Control
## Tela de craft (no estilo da imagem de referência): categorias, receitas,
## ingredientes, resultado e o peso da mochila em cima.
##
## Esta é a tela do craft de mão: poucas receitas. O craft de verdade vai ser
## feito nas bancadas (a mesma tela, com a lista de receitas da bancada).
## Se o item feito não couber na mochila, ele cai no chão do lado do jogador.

signal closed

const Mochila := preload("res://scripts/ui/mochila.gd")
const Itens := preload("res://scripts/itens.gd")
const Desenhos := preload("res://scripts/ui/desenhos.gd")

const C_TEXT := Color(0.93, 0.92, 0.89)
const C_DIM := Color(0.68, 0.67, 0.64)
const C_RED := Color(0.86, 0.13, 0.12)
const C_GREEN := Color(0.18, 0.78, 0.33)
const C_ORANGE := Color(0.98, 0.66, 0.2)
const C_PANEL := Color(0.07, 0.065, 0.06, 0.88)
const C_LINE := Color(1, 1, 1, 0.16)

var _game: Node
var receitas: Array = Itens.RECEITAS_MAO   # a bancada vai passar a lista dela aqui
var titulo_sub := "CRIE ITENS E SOBREVIVA"
var _cat := "Tudo"
var _sel := 0
var _qtd := 1
var _cat_btns := {}
var _list: VBoxContainer
var _weight_label: Label
var _weight_bar: ProgressBar
var _d_name: Label
var _d_desc: Label
var _d_icon: Control
var _ing_slots: Array = []
var _res_icon: Control
var _res_qtd: Label
var _qtd_label: Label
var _peso: Label
var _msg: Label
var _craft_btn: Button
var _detail: Control
var _empty: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Mochila._load_font()
	_build()


func abrir(game: Node) -> void:
	_game = game
	_fill_list()
	_refresh()


func fechar() -> void:
	closed.emit()
	queue_free()


func _gui_input(_e: InputEvent) -> void:
	accept_event()


# ---------- rolar a lista passando o dedo em cima dos itens ----------
var _scrolls: Array = []          # listas que rolam com o dedo (sem a barra do lado)
var _drag := {}                   # {sc, idx, start, moved}
var _just_dragged := false        # o dedo arrastou: o toque não escolhe o item


func _input(e: InputEvent) -> void:
	if (e is InputEventMouseButton or e is InputEventMouseMotion) and e.device == InputEvent.DEVICE_ID_EMULATION:
		return              # o mouse "de mentira" que o celular cria a partir do toque
	var pos := Vector2.INF
	var idx := -2
	if e is InputEventScreenTouch:
		pos = e.position
		idx = e.index
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
		idx = -1
	if pos != Vector2.INF:
		if e.pressed:
			_just_dragged = false
			for sc in _scrolls:
				if (sc as Control).is_visible_in_tree() and (sc as Control).get_global_rect().has_point(pos):
					_drag = {"sc": sc, "idx": idx, "start": pos, "last": pos, "moved": false}
					break
		elif not _drag.is_empty() and int(_drag.idx) == idx:
			if bool(_drag.moved):
				get_tree().create_timer(0.15).timeout.connect(func(): _just_dragged = false)
			_drag = {}
		return
	if _drag.is_empty():
		return
	var p := Vector2.INF
	if e is InputEventScreenDrag and e.index == int(_drag.idx):
		p = e.position
	elif e is InputEventMouseMotion and int(_drag.idx) == -1:
		p = e.position
	if p == Vector2.INF:
		return
	if not bool(_drag.moved) and absf(p.y - (_drag.start as Vector2).y) > 14.0:
		_drag.moved = true
		_just_dragged = true       # já arrastou: soltar o dedo não escolhe o item
	if bool(_drag.moved):
		var sc: ScrollContainer = _drag.sc
		sc.scroll_vertical = int(sc.scroll_vertical - (p.y - (_drag.last as Vector2).y))
	_drag.last = p


func _drag_list(sc: ScrollContainer) -> void:
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER    # rola com o dedo em cima dos itens
	_scrolls.append(sc)


# ================== MONTAGEM ==================

func _label(text: String, size_px: int, color := C_TEXT, bold := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Mochila._font_bold if bold else Mochila._font)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel(title: String) -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Mochila._box(C_PANEL, C_LINE, 2, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	if title != "":
		var t := _label(title, 26)
		t.custom_minimum_size = Vector2(0, 40)
		var mc := MarginContainer.new()
		mc.add_theme_constant_override("margin_left", 14)
		mc.add_child(t)
		v.add_child(mc)
		var line := ColorRect.new()
		line.color = C_LINE
		line.custom_minimum_size = Vector2(0, 2)
		v.add_child(line)
	return [p, v]


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + k, 20)
	mc.add_theme_constant_override("margin_top", 10)
	mc.add_theme_constant_override("margin_bottom", 12)
	add_child(mc)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	mc.add_child(root)

	# ---------- cabeçalho ----------
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, 84)
	head.add_theme_constant_override("separation", 16)
	root.add_child(head)
	var logo_icon := Mochila.LogoIcon.new()
	logo_icon.custom_minimum_size = Vector2(84, 80)
	head.add_child(logo_icon)
	var logo := VBoxContainer.new()
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	logo.add_theme_constant_override("separation", -14)
	head.add_child(logo)
	logo.add_child(_label("LAST", 38))
	logo.add_child(_label("HORIZON", 38, C_RED))
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.5)
	sep.custom_minimum_size = Vector2(2, 64)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sep)
	var title := VBoxContainer.new()
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.add_theme_constant_override("separation", -6)
	head.add_child(title)
	title.add_child(_label("CRAFT", 50))
	title.add_child(_label(titulo_sub, 19, C_DIM, false))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	var wbox := PanelContainer.new()
	wbox.add_theme_stylebox_override("panel", Mochila._box(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), 0, 6))
	wbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(wbox)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 6)
	wbox.add_child(wv)
	var wh := HBoxContainer.new()
	wh.add_theme_constant_override("separation", 14)
	wv.add_child(wh)
	var wi := Mochila.WeightIcon.new()
	wi.custom_minimum_size = Vector2(42, 42)
	wh.add_child(wi)
	_weight_label = _label("0.0 / 30.0 KG", 30)
	wh.add_child(_weight_label)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(270, 14)
	_weight_bar.add_theme_stylebox_override("background", Mochila._box(Color(0, 0, 0, 0.6), Color(1, 1, 1, 0.45), 2, 5))
	_weight_bar.add_theme_stylebox_override("fill", Mochila._box(C_GREEN, Color(0, 0, 0, 0), 0, 4))
	wv.add_child(_weight_bar)

	# ---------- corpo ----------
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	# categorias
	var cp := _panel("CATEGORIAS")
	cp[0].custom_minimum_size = Vector2(250, 0)
	body.add_child(cp[0])
	var cscroll := ScrollContainer.new()
	cscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_drag_list(cscroll)
	cp[1].add_child(cscroll)
	var cl := VBoxContainer.new()
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cl.add_theme_constant_override("separation", 2)
	cscroll.add_child(cl)
	for c in Itens.CATEGORIAS:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 50)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "          " + str(c)
		b.add_theme_font_override("font", Mochila._font_bold)
		b.add_theme_font_size_override("font_size", 23)
		b.add_theme_color_override("font_color", C_DIM)
		b.add_theme_color_override("font_pressed_color", C_TEXT)
		b.add_theme_color_override("font_hover_pressed_color", C_TEXT)
		b.add_theme_color_override("font_hover_color", C_TEXT)
		b.add_theme_stylebox_override("normal", Mochila._box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4))
		b.add_theme_stylebox_override("hover", Mochila._box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 4))
		b.add_theme_stylebox_override("pressed", Mochila._box(Color(0.72, 0.1, 0.09, 0.92), Color(0, 0, 0, 0), 0, 4))
		b.add_theme_stylebox_override("hover_pressed", Mochila._box(Color(0.78, 0.12, 0.1, 0.95), Color(0, 0, 0, 0), 0, 4))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var ic := CatIcon.new()
		ic.kind = str(c)
		ic.position = Vector2(12, 7)
		ic.size = Vector2(36, 36)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		b.pressed.connect(func():
			if _just_dragged:
				b.set_pressed_no_signal(str(c) == _cat)
				return
			_pick_cat(str(c)))
		cl.add_child(b)
		_cat_btns[c] = b

	# receitas
	var rp := _panel("RECEITAS")
	rp[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rp[0].size_flags_stretch_ratio = 1.0
	body.add_child(rp[0])
	var rscroll := ScrollContainer.new()
	rscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_drag_list(rscroll)
	rp[1].add_child(rscroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	rscroll.add_child(_list)

	# detalhe da receita
	var dp := _panel("")
	dp[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dp[0].size_flags_stretch_ratio = 1.55
	body.add_child(dp[0])
	var dmc := MarginContainer.new()
	dmc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top"]:
		dmc.add_theme_constant_override("margin_" + k, 16)
	dmc.add_theme_constant_override("margin_bottom", 10)
	dp[1].add_child(dmc)
	_empty = _label("", 22, C_DIM, false)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dmc.add_child(_empty)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	dmc.add_child(dv)
	_detail = dv
	_d_name = _label("", 32)
	_d_name.clip_text = true
	_d_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dv.add_child(_d_name)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	dv.add_child(top)
	_d_icon = ItemIcon.new()
	_d_icon.custom_minimum_size = Vector2(130, 110)
	top.custom_minimum_size = Vector2(0, 140)
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_d_icon)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(tv)
	_d_desc = _label("", 19, C_TEXT, false)
	_fixed(_d_desc, 3, 84)
	tv.add_child(_d_desc)
	_peso = _label("", 18, C_DIM, false)
	_fixed(_peso, 2, 58)
	_peso.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	tv.add_child(_peso)
	var line := ColorRect.new()
	line.color = C_LINE
	line.custom_minimum_size = Vector2(0, 2)
	dv.add_child(line)
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 14)
	dv.add_child(mid)
	var ingv := VBoxContainer.new()
	ingv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ingv.add_theme_constant_override("separation", 6)
	mid.add_child(ingv)
	ingv.add_child(_label("INGREDIENTES", 22))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	ingv.add_child(grid)
	for i in 8:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(70, 62)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.clip_contents = true
		slot.add_theme_stylebox_override("panel", Mochila._box(Color(0.03, 0.03, 0.03, 0.75), Color(1, 1, 1, 0.22), 2, 6))
		var ic := ItemIcon.new()
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(ic)
		var q := _label("", 18)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		q.clip_text = true
		q.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		q.add_theme_constant_override("outline_size", 4)
		slot.add_child(q)
		grid.add_child(slot)
		_ing_slots.append([ic, q])
	var vline := ColorRect.new()
	vline.color = C_LINE
	vline.custom_minimum_size = Vector2(2, 0)
	mid.add_child(vline)
	var resv := VBoxContainer.new()
	resv.custom_minimum_size = Vector2(150, 0)
	resv.add_theme_constant_override("separation", 4)
	mid.add_child(resv)
	var rt := _label("RESULTADO", 22)
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resv.add_child(rt)
	_res_icon = ItemIcon.new()
	_res_icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_res_icon.custom_minimum_size = Vector2(130, 80)
	resv.add_child(_res_icon)
	_res_qtd = _label("x1", 28)
	_res_qtd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resv.add_child(_res_qtd)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	dv.add_child(bottom)
	var minus := _round_btn("−")
	minus.pressed.connect(func(): _set_qtd(_qtd - 1))
	bottom.add_child(minus)
	_qtd_label = _label("1", 28)
	_qtd_label.custom_minimum_size = Vector2(70, 0)
	_qtd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_qtd_label)
	var plus := _round_btn("+")
	plus.pressed.connect(func(): _set_qtd(_qtd + 1))
	bottom.add_child(plus)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	bottom.add_child(gap)
	_craft_btn = Button.new()
	_craft_btn.text = "CRAFT"
	_craft_btn.custom_minimum_size = Vector2(250, 62)
	_craft_btn.add_theme_font_override("font", Mochila._font_bold)
	_craft_btn.add_theme_font_size_override("font_size", 34)
	_craft_btn.add_theme_color_override("font_color", C_TEXT)
	_craft_btn.add_theme_color_override("font_disabled_color", Color(C_TEXT, 0.35))
	_craft_btn.add_theme_stylebox_override("normal", Mochila._box(Color(0.72, 0.1, 0.09), Color(1, 0.35, 0.3, 0.7), 2, 6))
	_craft_btn.add_theme_stylebox_override("hover", Mochila._box(Color(0.8, 0.13, 0.11), Color(1, 0.45, 0.4, 0.8), 2, 6))
	_craft_btn.add_theme_stylebox_override("pressed", Mochila._box(Color(0.55, 0.07, 0.06), Color(1, 0.35, 0.3, 0.7), 2, 6))
	_craft_btn.add_theme_stylebox_override("disabled", Mochila._box(Color(0.25, 0.08, 0.07, 0.8), Color(1, 1, 1, 0.12), 2, 6))
	_craft_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_craft_btn.pressed.connect(_do_craft)
	bottom.add_child(_craft_btn)
	_msg = _label("", 18, C_DIM, false)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fixed(_msg, 1, 28)
	dv.add_child(_msg)

	# ---------- voltar ----------
	var bar := HBoxContainer.new()
	root.add_child(bar)
	var back := Button.new()
	back.text = "  ‹   VOLTAR"
	back.custom_minimum_size = Vector2(320, 58)
	back.add_theme_font_override("font", Mochila._font_bold)
	back.add_theme_font_size_override("font_size", 32)
	back.add_theme_color_override("font_color", C_TEXT)
	back.add_theme_stylebox_override("normal", Mochila._box(Color(0.07, 0.07, 0.07, 0.9), Color(1, 1, 1, 0.3), 2, 10))
	back.add_theme_stylebox_override("hover", Mochila._box(Color(0.13, 0.13, 0.13, 0.9), Color(1, 1, 1, 0.5), 2, 10))
	back.add_theme_stylebox_override("pressed", Mochila._box(Color(0.2, 0.14, 0.08, 0.95), Color(1, 0.62, 0.25), 2, 10))
	back.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	back.pressed.connect(fechar)
	bar.add_child(back)


func _round_btn(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(54, 54)
	b.add_theme_font_override("font", Mochila._font_bold)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_stylebox_override("normal", Mochila._box(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.5), 2, 27))
	b.add_theme_stylebox_override("hover", Mochila._box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.7), 2, 27))
	b.add_theme_stylebox_override("pressed", Mochila._box(Color(1, 1, 1, 0.15), Color(1, 1, 1, 0.8), 2, 27))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


# ================== RECEITAS ==================

func _visible_recipes() -> Array:
	var out := []
	for r in receitas:
		if _cat == "Tudo" or str(Itens.ITENS.get(r.id, {}).get("cat", "Diversos")) == _cat:
			out.append(r)
	return out


func _pick_cat(c: String) -> void:
	_cat = c
	_sel = 0
	_qtd = 1
	_fill_list()
	_refresh()


func _fixed(l: Label, lines: int, h: float) -> void:
	# tamanho fixo: o texto quebra até "lines" linhas e o resto é cortado com "…"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = lines
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.custom_minimum_size = Vector2(10, h)
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	for k in _cat_btns:
		_cat_btns[k].set_pressed_no_signal(k == _cat)
	var rs := _visible_recipes()
	for i in rs.size():
		var r: Dictionary = rs[i]
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 86)
		b.add_theme_stylebox_override("normal", Mochila._box(Color(0.1, 0.095, 0.09, 0.9), Color(1, 1, 1, 0.1), 2, 6))
		b.add_theme_stylebox_override("hover", Mochila._box(Color(0.14, 0.13, 0.12, 0.92), Color(1, 1, 1, 0.2), 2, 6))
		b.add_theme_stylebox_override("pressed", Mochila._box(Color(0.14, 0.09, 0.08, 0.95), C_RED, 3, 6))
		b.add_theme_stylebox_override("hover_pressed", Mochila._box(Color(0.14, 0.09, 0.08, 0.95), C_RED, 3, 6))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.add_theme_constant_override("separation", 10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var ic := ItemIcon.new()
		ic.id = str(r.id)
		ic.custom_minimum_size = Vector2(96, 0)
		h.add_child(ic)
		var tv := VBoxContainer.new()
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tv)
		var nm := _label(Itens.nome(r.id), 23)
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tv.add_child(nm)
		var d := _label("%s kg" % Itens.kg_txt(Itens.kg(r.id)), 16, C_DIM, false)
		d.clip_text = true
		d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tv.add_child(d)
		b.pressed.connect(func():
			if _just_dragged:
				b.set_pressed_no_signal(i == _sel)
				return
			_sel = i
			_qtd = 1
			_refresh())
		_list.add_child(b)


func _short(id: String) -> String:
	var d := str(Itens.ITENS.get(id, {}).get("desc", ""))
	var dot := d.find(".")
	return d.substr(0, dot + 1) if dot > 0 else d


func _have(id: String) -> int:
	return int(_game.item_qtd(id)) if _game else 0


func _max_craft(r: Dictionary) -> int:
	if _game and bool(_game.teste):
		return 99
	var m := 99
	for ing in r.ingredientes:
		m = mini(m, _have(str(ing[0])) / int(ing[1]))
	return m


func _set_qtd(q: int) -> void:
	_qtd = clampi(q, 1, 20)
	_refresh()


func _refresh() -> void:
	var total: float = _game._bag_total() if _game else 0.0
	var cap: float = _game.BAG_MAX if _game else 30.0
	_weight_label.text = "%.1f / %.1f KG" % [total, cap]
	_weight_bar.max_value = cap
	_weight_bar.value = total
	var fs: StyleBoxFlat = Mochila._box(C_GREEN if total < cap * 0.75 else (C_ORANGE if total < cap * 0.95 else C_RED), Color(0, 0, 0, 0), 0, 4)
	_weight_bar.add_theme_stylebox_override("fill", fs)
	var rs := _visible_recipes()
	for i in _list.get_child_count():
		(_list.get_child(i) as Button).set_pressed_no_signal(i == _sel)
	if rs.is_empty():
		_detail.visible = false
		_empty.visible = true
		_empty.text = "Nenhuma receita de %s aqui." % _cat.to_lower()
		return
	_detail.visible = true
	_empty.visible = false
	_sel = clampi(_sel, 0, rs.size() - 1)
	var r: Dictionary = rs[_sel]
	var id := str(r.id)
	_d_name.text = Itens.nome(id).to_upper()
	_d_desc.text = ""                  # sem descrição de ajuda
	_d_icon.id = id
	_d_icon.queue_redraw()
	_res_icon.id = id
	_res_icon.queue_redraw()
	var made := int(r.qtd) * _qtd
	_res_qtd.text = "x%d" % made
	_qtd_label.text = str(_qtd)
	var ok := true
	var used_kg := 0.0
	for i in _ing_slots.size():
		var ic = _ing_slots[i][0]
		var q: Label = _ing_slots[i][1]
		if i < r.ingredientes.size():
			var ing: Array = r.ingredientes[i]
			var need := int(ing[1]) * _qtd
			var have := _have(str(ing[0]))
			ic.id = str(ing[0])
			q.text = "%d / %d" % [have, need]
			q.add_theme_color_override("font_color", C_GREEN if have >= need else C_RED)
			if have < need and not (_game and bool(_game.teste)):
				ok = false
			used_kg += Itens.kg(str(ing[0])) * need
		else:
			ic.id = ""
			q.text = ""
		ic.queue_redraw()
	# peso: quanto o item pesa e se vai caber na mochila (o que não couber vai para o chão)
	var each := Itens.kg(id)
	var after := total - (used_kg if ok else 0.0) + each * made
	var txt := "Peso: %s kg" % Itens.kg_txt(each * made)
	if after <= cap + 0.0001:
		_peso.text = txt + " · cabe na mochila (fica %s / %d kg)" % [Itens.kg_txt(after), int(cap)]
		_peso.add_theme_color_override("font_color", C_GREEN)
	else:
		_peso.text = txt + " · não cabe: o que sobrar cai no chão"
		_peso.add_theme_color_override("font_color", C_ORANGE)
	_craft_btn.disabled = not ok
	if ok:
		_msg.text = ""
	else:
		_msg.text = "Faltam ingredientes."
		_msg.add_theme_color_override("font_color", C_DIM)


func _do_craft() -> void:
	var rs := _visible_recipes()
	if rs.is_empty() or _game == null:
		return
	var r: Dictionary = rs[_sel]
	if _max_craft(r) < _qtd:
		return
	if not bool(_game.teste):
		for ing in r.ingredientes:
			_game.remove_item(str(ing[0]), int(ing[1]) * _qtd)
	var made := int(r.qtd) * _qtd
	var dropped: int = _game.add_item(str(r.id), made)
	if dropped > 0:
		_msg.text = "Feito! Mochila cheia: %d %s caiu no chão." % [dropped, Itens.nome(r.id).to_lower()]
		_msg.add_theme_color_override("font_color", C_ORANGE)
	else:
		_msg.text = "Feito! +%d %s na mochila." % [made, Itens.nome(r.id).to_lower()]
		_msg.add_theme_color_override("font_color", C_GREEN)
	_qtd = 1
	var keep := _msg.text
	_refresh()
	_msg.text = keep


# ================== DESENHOS ==================

class ItemIcon extends Control:
	const Desenhos := preload("res://scripts/ui/desenhos.gd")
	var id := ""

	func _draw() -> void:
		if id == "":
			return
		var s := minf(size.x, size.y) * 0.8
		Desenhos.item(self, id, size * 0.5, s)


## Ícones das categorias, em traço branco simples.
class CatIcon extends Control:
	var kind := ""

	func _draw() -> void:
		var c := size * 0.5
		var u := minf(size.x, size.y) / 100.0
		var col := Color(0.93, 0.92, 0.89)
		var P := func(arr: Array) -> PackedVector2Array:
			var out := PackedVector2Array()
			for p in arr:
				out.append(c + Vector2(p[0], p[1]) * u)
			return out
		match kind:
			"Tudo":
				draw_colored_polygon(P.call([[-40, -30], [-4, -30], [-4, -12], [-40, -12]]), col)
				draw_line(c + Vector2(-14, -12) * u, c + Vector2(30, 40) * u, col, 9 * u)
			"Armas":
				draw_line(c + Vector2(-44, 10) * u, c + Vector2(40, -14) * u, col, 9 * u)
				draw_colored_polygon(P.call([[-20, 6], [-10, 4], [-14, 30], [-24, 30]]), col)
			"Munição":
				for x in [-26, 0, 26]:
					draw_rect(Rect2(c + Vector2(x - 8, -16) * u, Vector2(16, 50) * u), col)
					draw_colored_polygon(P.call([[x - 8, -16], [x, -36], [x + 8, -16]]), col)
			"Equipamentos":
				draw_colored_polygon(P.call([[-30, -38], [-12, -38], [-6, -24], [6, -24], [12, -38], [30, -38], [34, 40], [-34, 40]]), col)
			"Ferramentas":
				draw_line(c + Vector2(-36, 36) * u, c + Vector2(20, -20) * u, col, 10 * u)
				draw_arc(c + Vector2(26, -26) * u, 16 * u, PI * 0.9, PI * 2.4, 12, col, 9 * u)
			"Construção":
				draw_colored_polygon(P.call([[-42, -4], [0, -42], [42, -4]]), col)
				draw_rect(Rect2(c + Vector2(-30, -4) * u, Vector2(60, 42) * u), col)
				draw_rect(Rect2(c + Vector2(-8, 12) * u, Vector2(16, 26) * u), Color(0.1, 0.1, 0.1))
			"Recursos":
				draw_colored_polygon(P.call([[0, -40], [36, -20], [36, 22], [0, 42], [-36, 22], [-36, -20]]), col)
				draw_line(c + Vector2(0, 0) * u, c + Vector2(0, 42) * u, Color(0.1, 0.1, 0.1), 3 * u)
				draw_line(c + Vector2(0, 0) * u, c + Vector2(36, -20) * u, Color(0.1, 0.1, 0.1), 3 * u)
				draw_line(c + Vector2(0, 0) * u, c + Vector2(-36, -20) * u, Color(0.1, 0.1, 0.1), 3 * u)
			"Itens Médicos":
				draw_rect(Rect2(c + Vector2(-40, -26) * u, Vector2(80, 60) * u), col)
				draw_rect(Rect2(c + Vector2(-6, -16) * u, Vector2(12, 40) * u), Color(0.1, 0.1, 0.1))
				draw_rect(Rect2(c + Vector2(-20, -2) * u, Vector2(40, 12) * u), Color(0.1, 0.1, 0.1))
			_:
				for x in [-26, 0, 26]:
					draw_circle(c + Vector2(x, 0) * u, 7 * u, col)
