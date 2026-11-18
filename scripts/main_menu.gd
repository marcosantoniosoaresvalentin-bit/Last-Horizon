extends Control
## Menu principal.
## Barra no lado esquerdo com as seções:
##   Mundos         lista dos mundos salvos, "+ Novo mundo" no canto superior direito
##   Skin           os dois personagens em 3D para escolher
##   Configurações  nome de usuário
## Também avisa se o jogo fechou sozinho da última vez, e em que momento.

const Diag := preload("res://scripts/diagnostico.gd")
const Updater := preload("res://scripts/updater.gd")
const Mundos := preload("res://scripts/mundos.gd")
const Perfil := preload("res://scripts/perfil.gd")
const Conta := preload("res://scripts/conta.gd")
const Rede := preload("res://scripts/rede.gd")

const PASSO_NOME := {
	"gerando mundo": "a geração do mundo",
	"moldando terreno": "a montagem do terreno",
	"enchendo lagoas": "a montagem das lagoas",
	"carregando personagem": "o carregamento do personagem",
	"plantando grama": "a montagem da grama",
	"plantando arvores": "a montagem da floresta",
	"entrando no mundo": "a entrada no mundo",
	"jogando": "o jogo",
}

const C_BONE := Color(0.91, 0.86, 0.77)
const C_DIM := Color(0.62, 0.58, 0.51)
const C_EMBER := Color(1.0, 0.541, 0.239)
const C_PANEL := Color(0.055, 0.067, 0.086, 0.86)
const C_CARD := Color(0.10, 0.11, 0.13, 0.92)
const C_LINE := Color(0.91, 0.86, 0.77, 0.14)
const C_DANGER := Color(0.85, 0.32, 0.27)

const SKINS := [["homem", "Masculino"], ["mulher", "Feminino"]]

var _crash_text := ""
var _nav := {}                 # nome da seção -> botão
var _content: Control
var _page: Control
var _overlay: Control
var _name_label: Label
var _skin_view: SubViewport
var _skin_pivots := {}
var _skin_buttons := {}
var _conta: Node


func _ready() -> void:
	Updater.mark_ok()   # esta versão abriu direitinho
	if Conta.needs_login():
		get_tree().change_scene_to_file.call_deferred("res://scenes/conta.tscn")
		return
	_conta = Conta.new()
	add_child(_conta)
	var last := Diag.ultimo()
	if not Diag.PASSOS_OK.has(last):
		_crash_text = "O jogo fechou sozinho da última vez, durante %s." % PASSO_NOME.get(last, last)
	else:
		Diag.limpar_erros()
	Diag.marcar("menu")
	theme = _make_theme()
	_build_layout()
	_show("Mundos")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		Diag.marcar("ok")
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		Diag.marcar("menu")


# ================== ESTRUTURA ==================

func _build_layout() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# barra lateral
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(270, 0)
	side.add_theme_stylebox_override("panel", _box(C_PANEL, 0, Color(0, 0, 0, 0)))
	root.add_child(side)
	var sm := MarginContainer.new()
	for k in ["left", "right", "top", "bottom"]:
		sm.add_theme_constant_override("margin_" + k, 22)
	side.add_child(sm)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	sm.add_child(sv)

	var title := Label.new()
	title.text = "LAST\nHORIZON"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", C_BONE)
	title.add_theme_constant_override("line_spacing", -8)
	sv.add_child(title)
	var sub := Label.new()
	sub.text = "SOBREVIVÊNCIA ONLINE"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", C_EMBER)
	sv.add_child(sub)
	sv.add_child(_spacer(18))

	for sec in ["Mundos", "Multiplayer", "Skin", "Configurações"]:
		var b := Button.new()
		b.text = sec
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 58)
		b.add_theme_font_size_override("font_size", 24)
		b.add_theme_stylebox_override("normal", _box(Color(0, 0, 0, 0), 8))
		b.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.05), 8))
		b.add_theme_stylebox_override("pressed", _box(Color(1, 0.541, 0.239, 0.16), 8, C_EMBER, 0, 4))
		b.add_theme_stylebox_override("hover_pressed", _box(Color(1, 0.541, 0.239, 0.2), 8, C_EMBER, 0, 4))
		b.add_theme_color_override("font_pressed_color", C_BONE)
		b.add_theme_color_override("font_hover_pressed_color", C_BONE)
		b.add_theme_color_override("font_color", C_DIM)
		b.pressed.connect(_show.bind(sec))
		sv.add_child(b)
		_nav[sec] = b

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(fill)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", C_DIM)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(_name_label)
	var ver := Label.new()
	var build := Updater.current_build()
	ver.text = "v%s (build %d)" % [ProjectSettings.get_setting("application/config/version", "0.0.0"), build]
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color", Color(C_DIM, 0.7))
	sv.add_child(ver)
	_update_name_label()

	# área da seção
	var cm := MarginContainer.new()
	cm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]:
		cm.add_theme_constant_override("margin_" + k, 26)
	root.add_child(cm)
	_content = cm


func _show(section: String) -> void:
	for k in _nav:
		_nav[k].set_pressed_no_signal(k == section)
	_close_overlay()
	if _page:
		_page.queue_free()
	_skin_view = null
	_skin_pivots.clear()
	_skin_buttons.clear()
	var rede: Node = Rede.get_rede(get_tree())
	rede.procurar(section == "Multiplayer")
	match section:
		"Mundos": _page = _page_worlds()
		"Multiplayer": _page = _page_multi()
		"Skin": _page = _page_skin()
		_: _page = _page_settings()
	_content.add_child(_page)


func _page_frame(title_text: String, right: Control = null) -> Array:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	var head := HBoxContainer.new()
	var t := Label.new()
	t.text = title_text
	t.add_theme_font_size_override("font_size", 38)
	t.add_theme_color_override("font_color", C_BONE)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if right:
		head.add_child(right)
	v.add_child(head)
	return [v, head]


# ================== MUNDOS ==================

func _page_worlds() -> Control:
	var add := _button("+  Novo mundo", true)
	add.custom_minimum_size = Vector2(230, 56)
	add.pressed.connect(_ask_new_world)
	var fr := _page_frame("Mundos", add)
	var v: VBoxContainer = fr[0]

	if _crash_text != "":
		v.add_child(_note(_crash_text, Color(1.0, 0.62, 0.45)))

	var worlds := Mundos.list()
	if worlds.is_empty():
		var empty := VBoxContainer.new()
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		empty.add_theme_constant_override("separation", 14)
		var a := Label.new()
		a.text = "Você ainda não tem nenhum mundo."
		a.add_theme_font_size_override("font_size", 26)
		a.add_theme_color_override("font_color", C_BONE)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(a)
		var b := Label.new()
		b.text = "Toque em  +  Novo mundo  para criar o primeiro.\nCada mundo fica salvo no celular, do jeito que você deixou."
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", C_DIM)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(b)
		v.add_child(empty)
		return v

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for m in worlds:
		list.add_child(_world_card(m))
	return v


func _world_card(m: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(C_CARD, 10, C_LINE, 1))
	var mc := MarginContainer.new()
	for k in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + k, 20)
	for k in ["top", "bottom"]:
		mc.add_theme_constant_override("margin_" + k, 14)
	card.add_child(mc)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	mc.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	h.add_child(info)
	var n := Label.new()
	n.text = str(m.get("nome", "Mundo"))
	n.add_theme_font_size_override("font_size", 26)
	n.add_theme_color_override("font_color", C_BONE)
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(n)
	var d := Label.new()
	var date := str(m.get("data", ""))
	var when := "jogado " + Mundos.ago(int(m.get("ultimo", 0)))
	d.text = (date + "  ·  " + when) if date != "" else ("Mundo novo  ·  criado " + Mundos.ago(int(m.get("criado", 0))))
	d.add_theme_font_size_override("font_size", 16)
	d.add_theme_color_override("font_color", C_DIM)
	info.add_child(d)
	var del := _button("Apagar")
	del.custom_minimum_size = Vector2(110, 52)
	del.add_theme_color_override("font_color", C_DANGER)
	del.pressed.connect(_ask_delete.bind(m))
	h.add_child(del)
	var play := _button("Jogar", true)
	play.custom_minimum_size = Vector2(140, 52)
	play.pressed.connect(_enter_world.bind(str(m.id)))
	h.add_child(play)
	return card


func _ask_new_world(multi := false) -> void:
	var box := _dialog("Novo mundo")
	var hint := Label.new()
	hint.text = "Dê um nome ao seu mundo. Ele é gerado na hora e fica salvo para você voltar quando quiser."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 17)
	hint.add_theme_color_override("font_color", C_DIM)
	box.add_child(hint)
	var edit := LineEdit.new()
	edit.text = Mundos.default_name()
	edit.placeholder_text = "Nome do mundo"
	edit.max_length = Mundos.MAX_NAME
	edit.custom_minimum_size = Vector2(0, 58)
	edit.add_theme_font_size_override("font_size", 24)
	edit.select_all_on_focus = true
	box.add_child(edit)
	var err := _note("", C_DANGER)
	err.visible = false
	box.add_child(err)
	var create := func():
		var nm := edit.text.strip_edges()
		if nm == "":
			err.text = "Escreva um nome para o mundo."
			err.visible = true
			return
		var id := Mundos.create(nm)
		if multi:
			_mp_host(id, nm)
		else:
			_enter_world(id)
	edit.text_submitted.connect(func(_t): create.call())
	_dialog_buttons(box, "Criar mundo", create)
	edit.call_deferred("grab_focus")


func _ask_delete(m: Dictionary) -> void:
	var box := _dialog("Apagar mundo")
	var t := Label.new()
	t.text = "Apagar \"%s\"? Tudo o que aconteceu nesse mundo será perdido, e isso não pode ser desfeito." % str(m.get("nome", ""))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", 19)
	t.add_theme_color_override("font_color", C_BONE)
	box.add_child(t)
	var do_delete := func():
		Mundos.delete(str(m.id))
		_show("Mundos")
	_dialog_buttons(box, "Apagar", do_delete, true)


func _enter_world(id: String) -> void:
	Engine.set_meta("mundo", id)
	Engine.set_meta("personagem", Perfil.skin())
	Diag.marcar("gerando mundo")
	get_tree().change_scene_to_file("res://scenes/jogo3d.tscn")


# ================== MULTIPLAYER ==================

var _mp_list: VBoxContainer

func _page_multi() -> Control:
	var rede: Node = Rede.get_rede(get_tree())
	if rede.modo != "":
		rede.parar()
	rede.procurar(true)
	var fr := _page_frame("Multiplayer")
	var v: VBoxContainer = fr[0]
	v.add_child(_note("Jogue junto com quem está na mesma internet (mesma Wi-Fi). Abra um mundo seu, ou entre no mundo de alguém da lista.", C_DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	# mundos de outros jogadores na rede
	var h1 := Label.new()
	h1.text = "Mundos abertos na sua rede"
	h1.add_theme_font_size_override("font_size", 24)
	h1.add_theme_color_override("font_color", C_EMBER)
	body.add_child(h1)
	_mp_list = VBoxContainer.new()
	_mp_list.add_theme_constant_override("separation", 10)
	body.add_child(_mp_list)
	_mp_fill()
	if not rede.lista_mudou.is_connected(_mp_fill):
		rede.lista_mudou.connect(_mp_fill)
	# abrir um mundo meu
	body.add_child(_spacer(10))
	var h2row := HBoxContainer.new()
	var h2 := Label.new()
	h2.text = "Abrir um mundo seu"
	h2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h2.add_theme_font_size_override("font_size", 24)
	h2.add_theme_color_override("font_color", C_EMBER)
	h2row.add_child(h2)
	var add := _button("+  Criar mundo", true)
	add.custom_minimum_size = Vector2(220, 52)
	add.pressed.connect(_ask_new_world.bind(true))
	h2row.add_child(add)
	body.add_child(h2row)
	for m in Mundos.list():
		body.add_child(_mp_world_card(m))
	# entrar pelo número (se a lista não achar)
	body.add_child(_spacer(10))
	var ipr := HBoxContainer.new()
	ipr.add_theme_constant_override("separation", 10)
	var ip := LineEdit.new()
	ip.placeholder_text = "Ou digite o IP do outro celular (ex.: 192.168.0.12)"
	ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip.custom_minimum_size = Vector2(0, 52)
	ip.add_theme_font_size_override("font_size", 18)
	ipr.add_child(ip)
	var go := _button("Entrar")
	go.custom_minimum_size = Vector2(140, 52)
	go.pressed.connect(func():
		if ip.text.strip_edges() != "":
			_mp_join(ip.text.strip_edges(), Rede.PORT_GAME, "o mundo"))
	ipr.add_child(go)
	body.add_child(ipr)
	var ips: Array = rede.meus_ips()
	if not ips.is_empty():
		body.add_child(_note("O IP deste celular: " + ", ".join(ips), C_DIM))
	return v


func _mp_fill() -> void:
	if _mp_list == null or not is_instance_valid(_mp_list):
		return
	for c in _mp_list.get_children():
		c.queue_free()
	var rede: Node = Rede.get_rede(get_tree())
	if rede.achados.is_empty():
		_mp_list.add_child(_note("Procurando mundos na rede… (o outro jogador precisa abrir o mundo dele aqui no Multiplayer)", C_DIM))
		return
	for k in rede.achados:
		var d: Dictionary = rede.achados[k]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _box(C_CARD, 10, C_LINE, 1))
		var mc := MarginContainer.new()
		for kk in ["left", "right"]:
			mc.add_theme_constant_override("margin_" + kk, 20)
		for kk in ["top", "bottom"]:
			mc.add_theme_constant_override("margin_" + kk, 12)
		card.add_child(mc)
		var h := HBoxContainer.new()
		mc.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var n := Label.new()
		n.text = str(d.get("nome", "Mundo"))
		n.add_theme_font_size_override("font_size", 24)
		n.add_theme_color_override("font_color", C_BONE)
		info.add_child(n)
		var sub := Label.new()
		sub.text = "Dono: %s   ·   %d/%d jogadores" % [str(d.get("dono", "?")), int(d.get("n", 1)), int(d.get("max", 8))]
		sub.add_theme_font_size_override("font_size", 17)
		sub.add_theme_color_override("font_color", C_DIM)
		info.add_child(sub)
		var play := _button("Jogar", true)
		play.custom_minimum_size = Vector2(140, 52)
		play.disabled = int(d.get("n", 1)) >= int(d.get("max", 8))
		play.pressed.connect(_mp_join.bind(str(d.ip), int(d.get("porta", Rede.PORT_GAME)), str(d.get("nome", "o mundo"))))
		h.add_child(play)
		_mp_list.add_child(card)


func _mp_world_card(m: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(C_CARD, 10, C_LINE, 1))
	var mc := MarginContainer.new()
	for k in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + k, 20)
	for k in ["top", "bottom"]:
		mc.add_theme_constant_override("margin_" + k, 12)
	card.add_child(mc)
	var h := HBoxContainer.new()
	mc.add_child(h)
	var n := Label.new()
	n.text = str(m.get("nome", "Mundo"))
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.add_theme_font_size_override("font_size", 22)
	n.add_theme_color_override("font_color", C_BONE)
	h.add_child(n)
	var open := _button("Abrir para jogar junto", true)
	open.custom_minimum_size = Vector2(250, 50)
	open.pressed.connect(_mp_host.bind(str(m.id), str(m.get("nome", "Mundo"))))
	h.add_child(open)
	return card


func _mp_host(id: String, nome: String) -> void:
	var rede: Node = Rede.get_rede(get_tree())
	rede.procurar(false)
	if not rede.abrir_mundo(id, nome):
		var box := _dialog("Não deu para abrir")
		box.add_child(_note("Não conseguiu abrir o mundo na rede. Feche e abra o jogo e tente de novo.", C_DIM))
		_dialog_buttons(box, "Ok", _close_overlay)
		return
	_enter_world(id)


func _mp_join(ip: String, porta: int, nome: String) -> void:
	var rede: Node = Rede.get_rede(get_tree())
	var box := _dialog("Entrando")
	var msg := _note("Conectando em \"%s\" e baixando o mundo…" % nome, C_DIM)
	box.add_child(msg)
	var cancel := _button("Cancelar")
	cancel.custom_minimum_size = Vector2(150, 54)
	cancel.pressed.connect(func():
		rede.parar()
		_close_overlay()
		rede.procurar(true))
	box.add_child(cancel)
	if not rede.entrar(ip, porta):
		msg.text = "Não deu para conectar nesse endereço."
		return
	var ok := func(id: String):
		_enter_world(id)
	var bad := func(m: String):
		if is_instance_valid(msg):
			msg.text = m
	rede.conectou_e_baixou.connect(ok, CONNECT_ONE_SHOT)
	rede.falhou.connect(bad, CONNECT_ONE_SHOT)
	# sem resposta em 12 s: desiste
	get_tree().create_timer(12.0).timeout.connect(func():
		if rede.modo == "convidado" and rede.mundo_id != "mp_convidado" and is_instance_valid(msg):
			rede.parar()
			msg.text = "O outro celular não respondeu. Vocês estão na mesma Wi-Fi?")


# ================== SKIN ==================

func _page_skin() -> Control:
	var fr := _page_frame("Skin")
	var v: VBoxContainer = fr[0]
	v.add_child(_note("Toque no personagem para escolher. Ele é usado em todos os mundos.", C_DIM))

	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _box(Color(0.03, 0.04, 0.05, 0.75), 12, C_LINE, 1))
	v.add_child(frame)
	var holder := Control.new()
	holder.clip_contents = true
	frame.add_child(holder)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(svc)
	_skin_view = SubViewport.new()
	_skin_view.own_world_3d = true
	_skin_view.msaa_3d = Viewport.MSAA_2X
	svc.add_child(_skin_view)

	var loading := Label.new()
	loading.text = "Carregando personagens…"
	loading.set_anchors_preset(Control.PRESET_CENTER)
	loading.add_theme_font_size_override("font_size", 20)
	loading.add_theme_color_override("font_color", C_DIM)
	holder.add_child(loading)

	# metade esquerda e direita: cada uma é um botão invisível sobre o personagem
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	holder.add_child(row)
	for opt in SKINS:
		var b := Button.new()
		b.flat = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("normal", _box(Color(0, 0, 0, 0), 0))
		b.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.03), 0))
		b.add_theme_stylebox_override("pressed", _box(Color(1, 1, 1, 0.05), 0))
		b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), 0))
		b.pressed.connect(_pick_skin.bind(opt[0]))
		var tag := Label.new()
		tag.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		tag.offset_top = -64
		tag.offset_bottom = -16
		tag.offset_left = -150
		tag.offset_right = 150
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 22)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tag)
		row.add_child(b)
		_skin_buttons[opt[0]] = tag
	_refresh_skin_tags()
	# monta a cena 3D no quadro seguinte, para a tela aparecer antes
	_build_skin_scene.call_deferred(loading)
	return v


func _build_skin_scene(loading: Label) -> void:
	await get_tree().process_frame
	if _skin_view == null or not is_instance_valid(_skin_view):
		return
	var world := Node3D.new()
	_skin_view.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.045, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.68)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.3
	key.light_color = Color(1.0, 0.93, 0.84)
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(1.0, 0.6, 0.35)
	world.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 34
	cam.position = Vector3(0, 1.05, 5.4)
	world.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))

	var xs := {"homem": -0.85, "mulher": 0.85}
	for opt in SKINS:
		var who: String = opt[0]
		var pivot := Node3D.new()
		pivot.position = Vector3(xs[who], 0, 0)
		world.add_child(pivot)
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.55
		cyl.bottom_radius = 0.55
		cyl.height = 0.04
		disc.mesh = cyl
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.12, 0.13, 0.15)
		dm.emission_enabled = true
		dm.emission = Color(0, 0, 0)
		disc.material_override = dm
		disc.position.y = -0.02
		pivot.add_child(disc)
		var body := _load_character(who)
		if body:
			pivot.add_child(body)
		_skin_pivots[who] = [pivot, dm]
		await get_tree().process_frame
		if _skin_view == null or not is_instance_valid(_skin_view):
			return
	if is_instance_valid(loading):
		loading.queue_free()
	_refresh_skin_tags()


static func _load_character(who: String) -> Node3D:
	var bytes := FileAccess.get_file_as_bytes("res://personagem/%s.glbin" % who)
	if bytes.is_empty():
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_buffer(bytes, "", state) != OK:
		return null
	var body: Node3D = doc.generate_scene(state)
	if body == null:
		return null
	for old in body.find_children("*", "AnimationPlayer", true, false):
		old.queue_free()
	var anim := AnimationPlayer.new()
	body.add_child(anim)
	anim.root_node = NodePath("..")
	var a: Animation = load("res://personagem/%s_parado.tres" % who)
	if a:
		a = a.duplicate()
		a.loop_mode = Animation.LOOP_LINEAR
		var lib := AnimationLibrary.new()
		lib.add_animation("Idle", a)
		anim.add_animation_library("", lib)
		anim.play("Idle")
	return body


func _process(delta: float) -> void:
	# o personagem escolhido gira devagar; o outro fica de frente
	var chosen := Perfil.skin()
	for who in _skin_pivots:
		var pivot: Node3D = _skin_pivots[who][0]
		if not is_instance_valid(pivot):
			continue
		if who == chosen:
			pivot.rotation.y += delta * 0.6
		else:
			pivot.rotation.y = lerp_angle(pivot.rotation.y, 0.0, minf(1.0, delta * 4.0))


func _pick_skin(who: String) -> void:
	Perfil.set_skin(who)
	_refresh_skin_tags()


func _refresh_skin_tags() -> void:
	var chosen := Perfil.skin()
	for opt in SKINS:
		var who: String = opt[0]
		if _skin_buttons.has(who):
			var tag: Label = _skin_buttons[who]
			tag.text = ("✓  %s" % opt[1]) if who == chosen else opt[1]
			tag.add_theme_color_override("font_color", C_EMBER if who == chosen else C_DIM)
		if _skin_pivots.has(who):
			var dm: StandardMaterial3D = _skin_pivots[who][1]
			dm.emission = Color(0.9, 0.42, 0.15) * 0.8 if who == chosen else Color(0, 0, 0)


# ================== CONFIGURAÇÕES ==================

func _page_settings() -> Control:
	var fr := _page_frame("Configurações")
	var v: VBoxContainer = fr[0]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(C_CARD, 10, C_LINE, 1))
	v.add_child(card)
	var mc := MarginContainer.new()
	for k in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + k, 22)
	card.add_child(mc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	mc.add_child(box)
	var l := Label.new()
	l.text = "Apelido no jogo"
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", C_BONE)
	box.add_child(l)
	box.add_child(_note("É como você aparece dentro do jogo. Pode ser qualquer nome, até igual ao de outro jogador, e você muda quando quiser.", C_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var edit := LineEdit.new()
	edit.text = Perfil.nome()
	edit.max_length = Perfil.MAX_NAME
	edit.placeholder_text = "Seu apelido"
	edit.custom_minimum_size = Vector2(0, 56)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 22)
	row.add_child(edit)
	var save := _button("Salvar", true)
	save.custom_minimum_size = Vector2(140, 56)
	row.add_child(save)
	var msg := _note("", C_DIM)
	box.add_child(msg)
	var do_save := func():
		var n := edit.text.strip_edges()
		var problema := Conta.apelido_invalido(n)
		if problema != "":
			msg.text = problema
			msg.add_theme_color_override("font_color", C_DANGER)
			return
		if Conta.logged_in():
			save.disabled = true
			msg.text = "Salvando na sua conta…"
			msg.add_theme_color_override("font_color", C_DIM)
			var r: Dictionary = await _conta.trocar_apelido(n)
			if not is_instance_valid(save):
				return
			save.disabled = false
			if not r.ok:
				msg.text = Conta.mensagem(str(r.erro))
				msg.add_theme_color_override("font_color", C_DANGER)
				return
		Perfil.set_nome(n)
		edit.text = Perfil.nome()
		msg.text = "Apelido salvo."
		msg.add_theme_color_override("font_color", Color(0.6, 0.85, 0.5))
		_update_name_label()
	save.pressed.connect(do_save)
	edit.text_submitted.connect(func(_t): do_save.call())

	var s := Conta.session()
	if not s.is_empty():
		var acc := PanelContainer.new()
		acc.add_theme_stylebox_override("panel", _box(C_CARD, 10, C_LINE, 1))
		v.add_child(acc)
		var am := MarginContainer.new()
		for k in ["left", "right", "top", "bottom"]:
			am.add_theme_constant_override("margin_" + k, 22)
		acc.add_child(am)
		var ah := HBoxContainer.new()
		ah.add_theme_constant_override("separation", 12)
		am.add_child(ah)
		var ai := VBoxContainer.new()
		ai.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ah.add_child(ai)
		var at := Label.new()
		at.text = "Conta"
		at.add_theme_font_size_override("font_size", 22)
		ai.add_child(at)
		var conta_nome := str(s.get("conta", ""))
		if conta_nome != "":
			ai.add_child(_note("Nome da conta: %s" % conta_nome, C_BONE))
		ai.add_child(_note(str(s.get("email", "")), C_DIM))
		var out := _button("Sair da conta")
		out.custom_minimum_size = Vector2(190, 54)
		out.add_theme_color_override("font_color", C_DANGER)
		out.pressed.connect(_ask_logout)
		ah.add_child(out)
	return v


func _ask_logout() -> void:
	var box := _dialog("Sair da conta")
	var t := Label.new()
	t.text = "Para jogar de novo, você vai precisar entrar com seu e-mail e senha. Os mundos salvos neste celular continuam aqui."
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", 19)
	box.add_child(t)
	var do_out := func():
		Conta.sair()
		get_tree().change_scene_to_file("res://scenes/conta.tscn")
	_dialog_buttons(box, "Sair", do_out, true)


func _update_name_label() -> void:
	if _name_label:
		_name_label.text = "Jogando como\n" + Perfil.nome()


# ================== JANELAS ==================

func _dialog(title_text: String) -> VBoxContainer:
	_close_overlay()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.6)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", _box(Color(0.07, 0.08, 0.1, 0.98), 14, C_LINE, 1))
	center.add_child(panel)
	var mc := MarginContainer.new()
	for k in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + k, 26)
	panel.add_child(mc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	mc.add_child(box)
	var t := Label.new()
	t.text = title_text
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", C_BONE)
	box.add_child(t)
	return box


func _dialog_buttons(box: VBoxContainer, ok_text: String, on_ok: Callable, danger := false) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var cancel := _button("Cancelar")
	cancel.custom_minimum_size = Vector2(150, 54)
	cancel.pressed.connect(_close_overlay)
	row.add_child(cancel)
	var ok := _button(ok_text, not danger)
	ok.custom_minimum_size = Vector2(180, 54)
	if danger:
		ok.add_theme_stylebox_override("normal", _box(Color(C_DANGER, 0.85), 8))
		ok.add_theme_stylebox_override("hover", _box(C_DANGER, 8))
		ok.add_theme_stylebox_override("pressed", _box(Color(C_DANGER, 0.7), 8))
		ok.add_theme_color_override("font_color", Color(1, 1, 1))
	ok.pressed.connect(on_ok)
	row.add_child(ok)


func _close_overlay() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


# ================== ESTILO ==================

static func _make_theme() -> Theme:
	var th := Theme.new()
	th.set_color("font_color", "Label", C_BONE)
	th.set_font_size("font_size", "Button", 22)
	th.set_stylebox("normal", "Button", _box(Color(1, 1, 1, 0.06), 8, C_LINE, 1))
	th.set_stylebox("hover", "Button", _box(Color(1, 1, 1, 0.1), 8, C_LINE, 1))
	th.set_stylebox("pressed", "Button", _box(Color(1, 1, 1, 0.14), 8, C_LINE, 1))
	th.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), 8, Color(C_EMBER, 0.6), 2))
	th.set_color("font_color", "Button", C_BONE)
	th.set_color("font_hover_color", "Button", C_BONE)
	th.set_color("font_pressed_color", "Button", C_BONE)
	th.set_stylebox("normal", "LineEdit", _box(Color(0, 0, 0, 0.35), 8, C_LINE, 1, 0, 14))
	th.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0.35), 8, C_EMBER, 2, 0, 14))
	th.set_color("font_color", "LineEdit", C_BONE)
	th.set_color("font_placeholder_color", "LineEdit", Color(C_DIM, 0.6))
	th.set_color("caret_color", "LineEdit", C_EMBER)
	return th


static func _button(text: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	if accent:
		b.add_theme_stylebox_override("normal", _box(C_EMBER, 8))
		b.add_theme_stylebox_override("hover", _box(C_EMBER.lightened(0.1), 8))
		b.add_theme_stylebox_override("pressed", _box(C_EMBER.darkened(0.15), 8))
		b.add_theme_color_override("font_color", Color(0.1, 0.06, 0.03))
		b.add_theme_color_override("font_hover_color", Color(0.1, 0.06, 0.03))
		b.add_theme_color_override("font_pressed_color", Color(0.1, 0.06, 0.03))
	return b


func _note(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", color)
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func _box(bg: Color, radius := 8, border := Color(0, 0, 0, 0), border_w := 0, left_bar := 0, pad := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	if left_bar > 0:
		sb.border_width_left = left_bar
		sb.border_color = border
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
