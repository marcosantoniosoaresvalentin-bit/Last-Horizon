extends Node
## Contas dos jogadores, salvas no próprio celular, num arquivo de texto
## (user://contas.txt), uma conta por linha, separada por TAB:
##   nome_da_conta  email  apelido  criada_em  uid  sal  senha_embaralhada
## A senha nunca é gravada: só o resultado embaralhado (SHA-256 com sal, repetido).
## Não há verificação de nome ou e-mail repetido.
##
## - Na primeira vez que o jogo abre, é obrigatório criar uma conta (ou entrar).
## - A sessão fica salva em user://conta.json; o jogo não pede login de novo.
## - Apelido no jogo: muda nas Configurações.
##
## As funções de conta são "await" (para poder trocar por um servidor depois sem
## mudar as telas): adicione este nó na cena e chame  var r = await conta.entrar(...)
## O resultado é um Dictionary com "ok" (true/false) e, se der errado, "erro".

const SESSION := "user://conta.json"
const ACCOUNTS := "user://contas.txt"
const HASH_ROUNDS := 4000
const NAME_MIN := 3
const NAME_MAX := 20
const HEADER := "# Last Horizon - contas deste celular\n# nome_da_conta\temail\tapelido\tcriada_em\tuid\tsal\tsenha_embaralhada\n"


# ================== SESSÃO ==================

static func configured() -> bool:
	return true


static func session() -> Dictionary:
	if not FileAccess.file_exists(SESSION):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SESSION))
	return d if d is Dictionary and str(d.get("uid", "")) != "" else {}


static func logged_in() -> bool:
	return not session().is_empty()


## O jogo precisa mostrar a tela de conta antes do menu?
static func needs_login() -> bool:
	return not logged_in()


static func _save(d: Dictionary) -> void:
	var f := FileAccess.open(SESSION, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()


static func sair() -> void:
	if FileAccess.file_exists(SESSION):
		DirAccess.remove_absolute(SESSION)


# ================== VALIDAÇÃO ==================

static func nome_invalido(nome: String) -> String:
	var n := _limpo(nome)
	if n.length() < NAME_MIN:
		return "O nome da conta precisa ter pelo menos %d caracteres." % NAME_MIN
	if n.length() > NAME_MAX:
		return "O nome da conta pode ter no máximo %d caracteres." % NAME_MAX
	return ""


static func apelido_invalido(nome: String) -> String:
	var n := _limpo(nome)
	if n.length() < NAME_MIN:
		return "O apelido precisa ter pelo menos %d caracteres." % NAME_MIN
	if n.length() > NAME_MAX:
		return "O apelido pode ter no máximo %d caracteres." % NAME_MAX
	return ""


## Tira TAB, quebra de linha e espaços das pontas (o arquivo usa TAB e linha).
static func _limpo(s: String) -> String:
	return s.replace("\t", " ").replace("\n", " ").replace("\r", " ").strip_edges()


static func _hash(senha: String, sal: String) -> String:
	var h := (sal + ":" + senha).sha256_text()
	for i in HASH_ROUNDS:
		h = (h + sal).sha256_text()
	return h


static func _rand_hex(bytes: int) -> String:
	return Crypto.new().generate_random_bytes(bytes).hex_encode()


# ================== ARQUIVO ==================

static func _ler() -> Array:
	var linhas := []
	if not FileAccess.file_exists(ACCOUNTS):
		return linhas
	for line in FileAccess.get_file_as_string(ACCOUNTS).split("\n", false):
		if line.begins_with("#") or line.strip_edges() == "":
			continue
		var p := line.split("\t")
		if p.size() >= 7:
			linhas.append(p)
	return linhas


static func _gravar(linhas: Array) -> bool:
	var text := HEADER
	for p in linhas:
		text += "\t".join(p) + "\n"
	var tmp := ACCOUNTS + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return DirAccess.rename_absolute(tmp, ACCOUNTS) == OK


# ================== AÇÕES ==================

func criar_conta(email: String, senha: String, nome: String) -> Dictionary:
	await get_tree().process_frame
	email = _limpo(email).to_lower()
	nome = _limpo(nome)
	var uid := _rand_hex(8)
	var sal := _rand_hex(8)
	var agora := Time.get_datetime_string_from_system().left(10)
	var linhas := _ler()
	linhas.append(PackedStringArray([nome, email, nome, agora, uid, sal, _hash(senha, sal)]))
	if not _gravar(linhas):
		return {"ok": false, "erro": "GRAVAR"}
	_save({"uid": uid, "email": email, "conta": nome, "nome": nome})
	return {"ok": true}


func entrar(email: String, senha: String) -> Dictionary:
	await get_tree().process_frame
	email = _limpo(email).to_lower()
	var linhas := _ler()
	# a conta mais nova com esse e-mail e essa senha
	for i in range(linhas.size() - 1, -1, -1):
		var p: PackedStringArray = linhas[i]
		if p[1] == email and _hash(senha, p[5]) == p[6]:
			_save({"uid": p[4], "email": p[1], "conta": p[0], "nome": p[2]})
			return {"ok": true}
	return {"ok": false, "erro": "INVALID_LOGIN_CREDENTIALS"}


## Troca o apelido no jogo.
func trocar_apelido(apelido: String) -> Dictionary:
	await get_tree().process_frame
	apelido = _limpo(apelido)
	var s := session()
	if s.is_empty():
		return {"ok": false, "erro": "SEM_SESSAO"}
	var linhas := _ler()
	for i in linhas.size():
		var p: PackedStringArray = linhas[i]
		if p[4] == str(s.uid):
			p[2] = apelido
			linhas[i] = p
	_gravar(linhas)
	s["nome"] = apelido
	_save(s)
	return {"ok": true}


# ================== MENSAGENS ==================

static func mensagem(erro: String) -> String:
	match erro:
		"INVALID_LOGIN_CREDENTIALS": return "E-mail ou senha incorretos (a conta precisa ter sido criada neste celular)."
		"GRAVAR": return "Não foi possível salvar a conta no celular. Tente de novo."
		"SEM_SESSAO": return "Sua sessão acabou. Entre na conta de novo."
	return "Não deu certo (%s). Tente de novo." % erro
