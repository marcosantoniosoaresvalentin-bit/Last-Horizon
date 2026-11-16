extends Node
## Contas dos jogadores, guardadas num arquivo de texto no GitHub (contas.txt,
## repositório privado; ver conta_config.gd). Uma conta por linha, separada por TAB:
##   nome_da_conta  email  apelido  criada_em  uid  sal  senha_embaralhada
## A senha nunca é gravada: só o resultado embaralhado (SHA-256 com sal, repetido).
##
## - Nome da conta: ÚNICO e fixo ("Marcão", "marcao" e "MARCAO" são o mesmo nome).
## - E-mail: ÚNICO.
## - Apelido no jogo: livre, pode repetir entre jogadores e mudar quando quiser.
## - A sessão fica salva em user://conta.json; o jogo não pede login de novo.
##
## As funções que falam com o GitHub são "await": adicione este nó na cena
## (add_child) e chame, por exemplo:  var r = await conta.entrar(email, senha)
## O resultado é um Dictionary com "ok" (true/false) e, se der errado, "erro".

const Config := preload("res://scripts/conta_config.gd")
const SESSION := "user://conta.json"
const TIMEOUT := 20.0
const HASH_ROUNDS := 4000
const HEADER := "# Last Horizon - contas (não editar à mão com o jogo aberto)\n# nome_da_conta\temail\tapelido\tcriada_em\tuid\tsal\tsenha_embaralhada\n"


# ================== SESSÃO SALVA ==================

static func _token() -> String:
	var t := OS.get_environment("LH_CONTAS_TOKEN")   # para testes
	if t != "":
		return t
	if FileAccess.file_exists(Config.TOKEN_PATH):
		return FileAccess.get_file_as_string(Config.TOKEN_PATH).strip_edges()
	return ""


static func configured() -> bool:
	return _token() != ""


static func session() -> Dictionary:
	if not FileAccess.file_exists(SESSION):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SESSION))
	return d if d is Dictionary and str(d.get("uid", "")) != "" else {}


static func logged_in() -> bool:
	return not session().is_empty()


## O jogo precisa mostrar a tela de conta antes do menu?
static func needs_login() -> bool:
	return configured() and not logged_in()


static func _save(d: Dictionary) -> void:
	var f := FileAccess.open(SESSION, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()


static func sair() -> void:
	if FileAccess.file_exists(SESSION):
		DirAccess.remove_absolute(SESSION)


# ================== NOMES ==================

const NAME_MIN := 3
const NAME_MAX := 20
const _ACCENTS := {"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a", "é": "e", "ê": "e", "è": "e", "ë": "e",
	"í": "i", "ì": "i", "î": "i", "ï": "i", "ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
	"ú": "u", "ù": "u", "û": "u", "ü": "u", "ç": "c", "ñ": "n"}


## Explica o que está errado com o nome da conta, ou "" se estiver bom.
static func nome_invalido(nome: String) -> String:
	if nome.length() < NAME_MIN:
		return "O nome da conta precisa ter pelo menos %d caracteres." % NAME_MIN
	if nome.length() > NAME_MAX:
		return "O nome da conta pode ter no máximo %d caracteres." % NAME_MAX
	if chave_nome(nome).length() != nome.length():
		return "Use só letras, números, _ . ou - (sem espaços)."
	return ""


## Forma usada para comparar nomes: minúsculo, sem acento, só letras, números, _ . -
static func chave_nome(nome: String) -> String:
	var out := ""
	for ch in nome.to_lower():
		ch = _ACCENTS.get(ch, ch)
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch in ["_", ".", "-"]:
			out += ch
	return out


## Apelido: de 3 a 20 caracteres, qualquer letra, pode ter espaço e repetir.
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
	var c := Crypto.new()
	return c.generate_random_bytes(bytes).hex_encode()


# ================== ARQUIVO NO GITHUB ==================

func _url() -> String:
	var base := OS.get_environment("LH_GH_BASE")   # para testes: servidor local no lugar do GitHub
	if base == "":
		base = "https://api.github.com/"
	return base + "repos/%s/%s/contents/%s" % [Config.OWNER, Config.REPO, Config.FILE]


func _request(method: int, body := "") -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var headers := ["Authorization: Bearer " + _token(), "Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2022-11-28", "User-Agent: LastHorizon"]
	if body != "":
		headers.append("Content-Type: application/json")
	var err := http.request(_url(), headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "erro": "SEM_CONEXAO"}
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "erro": "SEM_CONEXAO"}
	var data = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return {"ok": res[1] >= 200 and res[1] < 300, "codigo": res[1], "data": data if data is Dictionary else {}}


## Lê o arquivo de contas: {"ok", "linhas": Array[PackedStringArray], "sha"}
func _ler() -> Dictionary:
	var r := await _request(HTTPClient.METHOD_GET)
	if not r.ok:
		if int(r.get("codigo", 0)) == 404:
			return {"ok": true, "linhas": [], "sha": ""}   # arquivo ainda não existe
		return {"ok": false, "erro": _erro_http(r)}
	var b64 := str(r.data.get("content", "")).replace("\n", "")
	var text := Marshalls.base64_to_utf8(b64) if b64 != "" else ""
	var linhas := []
	for line in text.split("\n", false):
		if line.begins_with("#") or line.strip_edges() == "":
			continue
		var p := line.split("\t")
		if p.size() >= 7:
			linhas.append(p)
	return {"ok": true, "linhas": linhas, "sha": str(r.data.get("sha", ""))}


## Grava o arquivo. Se outra pessoa gravou no meio tempo, devolve CONFLITO.
func _gravar(linhas: Array, sha: String, msg: String) -> Dictionary:
	var text := HEADER
	for p in linhas:
		text += "\t".join(p) + "\n"
	var body := {"message": msg, "content": Marshalls.utf8_to_base64(text)}
	if sha != "":
		body["sha"] = sha
	var r := await _request(HTTPClient.METHOD_PUT, JSON.stringify(body))
	if r.ok:
		return {"ok": true}
	if int(r.get("codigo", 0)) in [409, 422]:
		return {"ok": false, "erro": "CONFLITO"}
	return {"ok": false, "erro": _erro_http(r)}


static func _erro_http(r: Dictionary) -> String:
	if r.has("erro"):
		return str(r.erro)
	match int(r.get("codigo", 0)):
		401, 403: return "SERVIDOR_CONTAS"
		429: return "MUITOS_ACESSOS"
	return "ERRO_%d" % int(r.get("codigo", 0))


static func _achar(linhas: Array, col: int, valor: String) -> int:
	for i in linhas.size():
		var v: String = linhas[i][col]
		if (col == 0 and chave_nome(v) == valor) or (col == 1 and v.to_lower() == valor):
			return i
	return -1


# ================== AÇÕES ==================

## O nome está livre? {"ok": true, "livre": bool}
func nome_livre(nome: String) -> Dictionary:
	var f := await _ler()
	if not f.ok:
		return f
	return {"ok": true, "livre": _achar(f.linhas, 0, chave_nome(nome)) < 0}


func criar_conta(email: String, senha: String, nome: String) -> Dictionary:
	email = _limpo(email).to_lower()
	nome = _limpo(nome)
	# tenta algumas vezes, caso outra pessoa esteja criando conta no mesmo instante
	for tentativa in 4:
		var f := await _ler()
		if not f.ok:
			return f
		if _achar(f.linhas, 0, chave_nome(nome)) >= 0:
			return {"ok": false, "erro": "NOME_EM_USO"}
		if _achar(f.linhas, 1, email) >= 0:
			return {"ok": false, "erro": "EMAIL_EXISTS"}
		var uid := _rand_hex(8)
		var sal := _rand_hex(8)
		var agora := Time.get_datetime_string_from_system(true).left(10)
		var linhas: Array = f.linhas.duplicate()
		linhas.append(PackedStringArray([nome, email, nome, agora, uid, sal, _hash(senha, sal)]))
		var g := await _gravar(linhas, f.sha, "Nova conta: " + nome)
		if g.ok:
			_save({"uid": uid, "email": email, "conta": nome, "nome": nome})
			return {"ok": true}
		if g.erro != "CONFLITO":
			return g
		await get_tree().create_timer(0.4 + randf() * 0.8).timeout
	return {"ok": false, "erro": "CONFLITO"}


func entrar(email: String, senha: String) -> Dictionary:
	email = _limpo(email).to_lower()
	var f := await _ler()
	if not f.ok:
		return f
	var i := _achar(f.linhas, 1, email)
	if i < 0:
		return {"ok": false, "erro": "INVALID_LOGIN_CREDENTIALS"}
	var p: PackedStringArray = f.linhas[i]
	if _hash(senha, p[5]) != p[6]:
		return {"ok": false, "erro": "INVALID_LOGIN_CREDENTIALS"}
	_save({"uid": p[4], "email": p[1], "conta": p[0], "nome": p[2]})
	return {"ok": true}


## Troca o apelido no jogo (pode ser igual ao de outros jogadores).
func trocar_apelido(apelido: String) -> Dictionary:
	apelido = _limpo(apelido)
	var s := session()
	if s.is_empty():
		return {"ok": false, "erro": "SEM_SESSAO"}
	for tentativa in 4:
		var f := await _ler()
		if not f.ok:
			return f
		var linhas: Array = f.linhas.duplicate()
		var i := -1
		for k in linhas.size():
			if linhas[k][4] == str(s.uid):
				i = k
		if i < 0:
			return {"ok": false, "erro": "SEM_SESSAO"}
		var p: PackedStringArray = linhas[i]
		p[2] = apelido
		linhas[i] = p
		var g := await _gravar(linhas, f.sha, "Apelido: " + str(s.get("conta", "")))
		if g.ok:
			s["nome"] = apelido
			_save(s)
			return {"ok": true}
		if g.erro != "CONFLITO":
			return g
		await get_tree().create_timer(0.4 + randf() * 0.8).timeout
	return {"ok": false, "erro": "CONFLITO"}


# ================== MENSAGENS ==================

static func mensagem(erro: String) -> String:
	match erro:
		"NOME_EM_USO": return "Nome da conta já em uso. Escolha outro."
		"EMAIL_EXISTS": return "Já existe uma conta com esse e-mail. Use a aba Entrar."
		"INVALID_LOGIN_CREDENTIALS": return "E-mail ou senha incorretos."
		"SEM_CONEXAO": return "Sem conexão com a internet. Verifique e tente de novo."
		"SERVIDOR_CONTAS": return "O servidor de contas não aceitou o acesso. Avise o dono do jogo."
		"MUITOS_ACESSOS": return "Muitas pessoas usando agora. Espere um pouco e tente de novo."
		"CONFLITO": return "Muitas contas sendo criadas ao mesmo tempo. Tente de novo."
		"SEM_SESSAO": return "Sua sessão acabou. Entre na conta de novo."
	return "Não deu certo (%s). Tente de novo." % erro
