extends Control
## Tela de conta: aparece antes do menu enquanto o jogador não tem conta neste celular.
## Abas "Entrar" e "Criar conta". Criar conta pede nome de usuário, e-mail e senha.

const Conta := preload("res://scripts/conta.gd")
const Perfil := preload("res://scripts/perfil.gd")
const Menu := preload("res://scripts/main_menu.gd")

const C_BONE := Color(0.91, 0.86, 0.77)
const C_DIM := Color(0.62, 0.58, 0.51)
const C_EMBER := Color(1.0, 0.541, 0.239)
const C_DANGER := Color(0.95, 0.42, 0.36)
const C_OK := Color(0.6, 0.85, 0.5)
const C_LINE := Color(0.91, 0.86, 0.77, 0.14)

var _conta: Node
var _tabs := {}
var _form: VBoxContainer
var _msg: Label
var _busy := false
var _mode := "criar"
var _fields := {}
var _submit: Button


func _ready() -> void:
	theme = _theme()
	_conta = Conta.new()
	add_child(_conta)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	panel.add_theme_stylebox_override("panel", Menu._box(Color(0.055, 0.067, 0.086, 0.94), 14, C_LINE, 1))
	center.add_child(panel)
	var mc := MarginContainer.new()
	for k in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + k, 34)
	for k in ["top", "bottom"]:
		mc.add_theme_constant_override("margin_" + k, 26)
	panel.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	mc.add_child(v)

	var title := Label.new()
	title.text = "LAST HORIZON"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	v.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	for t in [["criar", "Criar conta"], ["entrar", "Entrar"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_stylebox_override("normal", Menu._box(Color(1, 1, 1, 0.04), 8))
		b.add_theme_stylebox_override("hover", Menu._box(Color(1, 1, 1, 0.08), 8))
		b.add_theme_stylebox_override("pressed", Menu._box(Color(1, 0.541, 0.239, 0.18), 8, C_EMBER, 2))
		b.add_theme_stylebox_override("hover_pressed", Menu._box(Color(1, 0.541, 0.239, 0.22), 8, C_EMBER, 2))
		b.add_theme_color_override("font_color", C_DIM)
		b.add_theme_color_override("font_pressed_color", C_BONE)
		b.add_theme_color_override("font_hover_pressed_color", C_BONE)
		b.pressed.connect(_set_mode.bind(t[0]))
		tabs.add_child(b)
		_tabs[t[0]] = b

	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 10)
	v.add_child(_form)

	_msg = Label.new()
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_font_size_override("font_size", 17)
	v.add_child(_msg)
	_set_mode("criar")


func _set_mode(mode: String) -> void:
	if _busy:
		_tabs[_mode].set_pressed_no_signal(true)
		return
	_mode = mode
	for k in _tabs:
		_tabs[k].set_pressed_no_signal(k == mode)
	for c in _form.get_children():
		c.queue_free()
	_fields.clear()
	_say("")
	if mode == "criar":
		_field("nome", "Nome da conta (só seu, ninguém pode repetir)", "Letras, números, _ . -  (sem espaços)", false, Conta.NAME_MAX)
	_field("email", "E-mail", "seu@email.com", false, 120)
	_field("senha", "Senha", "Pelo menos 6 caracteres" if mode == "criar" else "Sua senha", true, 64)
	_submit = Menu._button("Criar conta" if mode == "criar" else "Entrar", true)
	_submit.custom_minimum_size = Vector2(0, 58)
	_submit.add_theme_font_size_override("font_size", 24)
	_submit.pressed.connect(_go)
	_form.add_child(_submit)
	if mode == "entrar":
		var forgot := Button.new()
		forgot.text = "Esqueci minha senha"
		forgot.flat = true
		forgot.add_theme_font_size_override("font_size", 17)
		forgot.add_theme_color_override("font_color", C_DIM)
		forgot.pressed.connect(_forgot)
		_form.add_child(forgot)
	var first: LineEdit = _fields.values()[0]
	first.call_deferred("grab_focus")


func _field(key: String, label: String, placeholder: String, secret: bool, max_len: int) -> void:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", C_DIM)
	_form.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_form.add_child(row)
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, 54)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 22)
	if key == "email":
		e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	elif secret:
		e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	e.text_submitted.connect(func(_t): _next_or_go(key))
	row.add_child(e)
	if secret:
		var eye := Button.new()
		eye.text = "Mostrar"
		eye.toggle_mode = true
		eye.custom_minimum_size = Vector2(110, 54)
		eye.add_theme_font_size_override("font_size", 17)
		eye.toggled.connect(func(on: bool):
			e.secret = not on
			eye.text = "Ocultar" if on else "Mostrar")
		row.add_child(eye)
	_fields[key] = e


func _next_or_go(key: String) -> void:
	var keys := _fields.keys()
	var i := keys.find(key)
	if i >= 0 and i < keys.size() - 1:
		(_fields[keys[i + 1]] as LineEdit).grab_focus()
	else:
		_go()


func _val(key: String) -> String:
	return (_fields[key] as LineEdit).text.strip_edges() if _fields.has(key) else ""


func _go() -> void:
	if _busy:
		return
	var email := _val("email").to_lower()
	var senha := (_fields["senha"] as LineEdit).text
	if _mode == "criar":
		var problema := Conta.nome_invalido(_val("nome"))
		if problema != "":
			_say(problema, C_DANGER)
			return
	if not _email_ok(email):
		_say("Escreva um e-mail válido, como nome@gmail.com.", C_DANGER)
		return
	if senha.length() < 6:
		_say("A senha precisa ter pelo menos 6 caracteres.", C_DANGER)
		return
	_set_busy(true, "Criando sua conta…" if _mode == "criar" else "Entrando…")
	var r: Dictionary
	if _mode == "criar":
		r = await _conta.criar_conta(email, senha, _val("nome"))
	else:
		r = await _conta.entrar(email, senha)
	_set_busy(false)
	if not r.ok:
		_say(Conta.mensagem(str(r.erro)), C_DANGER)
		return
	var s := Conta.session()
	Perfil.set_nome(str(s.get("nome", "")))
	_say("Bem-vindo, %s!" % str(s.get("nome", "")), C_OK)
	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _forgot() -> void:
	if _busy:
		return
	var email := _val("email").to_lower()
	if not _email_ok(email):
		_say("Escreva o seu e-mail no campo acima e toque de novo em \"Esqueci minha senha\".", C_DANGER)
		return
	_set_busy(true, "Enviando…")
	var r: Dictionary = await _conta.esqueci_senha(email)
	_set_busy(false)
	if r.ok:
		_say("Se existir uma conta com esse e-mail, chegou uma mensagem para criar uma senha nova. Veja também o spam.", C_OK)
	else:
		_say(Conta.mensagem(str(r.erro)), C_DANGER)


static func _email_ok(e: String) -> bool:
	var at := e.find("@")
	return at > 0 and e.find(".", at) > at + 1 and not e.ends_with(".") and not e.contains(" ")


func _set_busy(on: bool, text := "") -> void:
	_busy = on
	if _submit:
		_submit.disabled = on
	for e in _fields.values():
		(e as LineEdit).editable = not on
	if on:
		_say(text, C_DIM)


func _say(text: String, color := C_DIM) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", color)
	_msg.visible = text != ""


func _theme() -> Theme:
	return Menu._make_theme()
