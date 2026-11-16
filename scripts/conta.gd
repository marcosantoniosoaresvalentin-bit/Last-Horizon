extends Node
## Contas dos jogadores, com o Firebase Authentication (API REST).
##
## - Criar conta: e-mail, senha e nome de usuário (o nome vai no perfil da conta).
## - Entrar: e-mail e senha. Esqueci a senha: o Firebase manda um e-mail.
## - A sessão fica salva em user://conta.json; o jogo não pede login de novo.
## - Trocar o nome: atualiza na conta (precisa de internet).
## - Nome de usuário único: cada nome é reservado no Firestore (coleção "usernames",
##   documento = nome normalizado). "Marcão", "marcao" e "MARCAO" são o mesmo nome.
##   As regras de segurança do Firestore garantem que ninguém pega um nome já reservado.
##
## As funções que falam com o servidor são "await": adicione este nó na cena
## (add_child) e chame, por exemplo:  var r = await conta.entrar(email, senha)
## O resultado é um Dictionary com "ok" (true/false) e, se der errado, "erro".

const Config := preload("res://scripts/conta_config.gd")
const SESSION := "user://conta.json"
const TIMEOUT := 15.0


# ================== SESSÃO SALVA ==================

## Para testes: LH_AUTH_BASE aponta para um servidor local no lugar do Firebase.
static func _base() -> String:
	return OS.get_environment("LH_AUTH_BASE")


static func configured() -> bool:
	return (Config.API_KEY != "" and Config.PROJECT_ID != "") or _base() != ""


static func session() -> Dictionary:
	if not FileAccess.file_exists(SESSION):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SESSION))
	return d if d is Dictionary and str(d.get("refresh", "")) != "" else {}


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


# ================== NOME DE USUÁRIO ==================

const NAME_MIN := 3
const NAME_MAX := 20
const _ACCENTS := {"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a", "é": "e", "ê": "e", "è": "e", "ë": "e",
	"í": "i", "ì": "i", "î": "i", "ï": "i", "ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
	"ú": "u", "ù": "u", "û": "u", "ü": "u", "ç": "c", "ñ": "n"}


## Explica o que está errado com o nome, ou "" se estiver bom.
static func nome_invalido(nome: String) -> String:
	if nome.length() < NAME_MIN:
		return "O nome de usuário precisa ter pelo menos %d caracteres." % NAME_MIN
	if nome.length() > NAME_MAX:
		return "O nome de usuário pode ter no máximo %d caracteres." % NAME_MAX
	var key := chave_nome(nome)
	if key.length() != nome.length():
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


# ================== SERVIDOR ==================

func _auth_url(method: String) -> String:
	var base := _base()
	if base != "":
		return base + "v1/accounts:" + method + "?key=teste"
	return "https://identitytoolkit.googleapis.com/v1/accounts:%s?key=%s" % [method, Config.API_KEY]


func _token_url() -> String:
	var base := _base()
	if base != "":
		return base + "v1/token?key=teste"
	return "https://securetoken.googleapis.com/v1/token?key=" + Config.API_KEY


func _fs_url(path: String) -> String:
	var base := _base()
	if base != "":
		return base + "v1/projects/teste/databases/(default)/documents/" + path
	return "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s" % [Config.PROJECT_ID, path]


func _post(url: String, body: String, content_type := "application/json", method := HTTPClient.METHOD_POST, token := "") -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var headers := ["Content-Type: " + content_type]
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "erro": "SEM_CONEXAO"}
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "erro": "SEM_CONEXAO"}
	var data = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if res[1] == 200 and data is Dictionary:
		data["ok"] = true
		return data
	var msg := "ERRO_%d" % res[1]
	if data is Dictionary and data.get("error") is Dictionary:
		msg = str(data.error.get("message", msg))
	return {"ok": false, "erro": msg, "codigo": res[1]}


func _json(method: String, body: Dictionary) -> Dictionary:
	return await _post(_auth_url(method), JSON.stringify(body))


## O nome está livre? {"ok": true, "livre": bool}
func nome_livre(nome: String) -> Dictionary:
	var r := await _post(_fs_url("usernames/" + chave_nome(nome)), "", "application/json", HTTPClient.METHOD_GET)
	if r.ok:
		return {"ok": true, "livre": false}
	if int(r.get("codigo", 0)) == 404:
		return {"ok": true, "livre": true}
	return r


## Reserva o nome para esta conta. Falha com NOME_EM_USO se alguém já tiver.
func _reservar(id_token: String, uid: String, nome: String) -> Dictionary:
	var body := {"fields": {"uid": {"stringValue": uid}, "nome": {"stringValue": nome}}}
	var r := await _post(_fs_url("usernames?documentId=" + chave_nome(nome)), JSON.stringify(body),
		"application/json", HTTPClient.METHOD_POST, id_token)
	if not r.ok and int(r.get("codigo", 0)) in [409, 403]:
		return {"ok": false, "erro": "NOME_EM_USO"}
	return r


func _liberar(id_token: String, key: String) -> void:
	await _post(_fs_url("usernames/" + key), "", "application/json", HTTPClient.METHOD_DELETE, id_token)


func criar_conta(email: String, senha: String, nome: String) -> Dictionary:
	var livre := await nome_livre(nome)
	if not livre.ok:
		return livre
	if not livre.livre:
		return {"ok": false, "erro": "NOME_EM_USO"}
	var r := await _json("signUp", {"email": email, "password": senha, "returnSecureToken": true})
	if not r.ok:
		return r
	var res := await _reservar(str(r.idToken), str(r.localId), nome)
	if not res.ok:
		# alguém pegou o nome no mesmo instante: desfaz a conta para o e-mail poder ser usado de novo
		await _json("delete", {"idToken": r.idToken})
		return res
	var u := await _json("update", {"idToken": r.idToken, "displayName": nome, "returnSecureToken": true})
	var refresh := str(u.get("refreshToken", r.refreshToken)) if u.ok else str(r.refreshToken)
	_save({"uid": r.localId, "email": r.get("email", email), "nome": nome, "refresh": refresh})
	return {"ok": true}


func entrar(email: String, senha: String) -> Dictionary:
	var r := await _json("signInWithPassword", {"email": email, "password": senha, "returnSecureToken": true})
	if not r.ok:
		return r
	var nome := str(r.get("displayName", ""))
	if nome == "":
		nome = email.get_slice("@", 0).left(20)
	_save({"uid": r.localId, "email": r.get("email", email), "nome": nome, "refresh": r.refreshToken})
	return {"ok": true}


func esqueci_senha(email: String) -> Dictionary:
	return await _json("sendOobCode", {"requestType": "PASSWORD_RESET", "email": email})


## Pede um token novo ao servidor (o token de acesso dura só 1 hora).
func _id_token() -> Dictionary:
	var s := session()
	if s.is_empty():
		return {"ok": false, "erro": "SEM_SESSAO"}
	var body := "grant_type=refresh_token&refresh_token=" + str(s.refresh).uri_encode()
	var r := await _post(_token_url(), body, "application/x-www-form-urlencoded")
	if r.ok:
		s["refresh"] = r.get("refresh_token", s.refresh)
		_save(s)
	return r


func trocar_nome(nome: String) -> Dictionary:
	var t := await _id_token()
	if not t.ok:
		return t
	var old_key := chave_nome(str(session().get("nome", "")))
	var new_key := chave_nome(nome)
	if new_key != old_key:
		var res := await _reservar(str(t.id_token), str(t.get("user_id", session().get("uid", ""))), nome)
		if not res.ok:
			return res
	var r := await _json("update", {"idToken": t.id_token, "displayName": nome, "returnSecureToken": true})
	if r.ok and new_key != old_key and old_key != "":
		await _liberar(str(t.id_token), old_key)
	if r.ok:
		var s := session()
		s["nome"] = nome
		if r.has("refreshToken"):
			s["refresh"] = r.refreshToken
		_save(s)
	return r


# ================== MENSAGENS ==================

static func mensagem(erro: String) -> String:
	var e := erro.get_slice(" ", 0)
	match e:
		"NOME_EM_USO": return "Nome de usuário já em uso. Escolha outro."
		"EMAIL_EXISTS": return "Já existe uma conta com esse e-mail. Use a aba Entrar."
		"INVALID_EMAIL", "MISSING_EMAIL": return "Esse e-mail não é válido."
		"WEAK_PASSWORD", "MISSING_PASSWORD": return "A senha precisa ter pelo menos 6 caracteres."
		"EMAIL_NOT_FOUND", "INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS": return "E-mail ou senha incorretos."
		"USER_DISABLED": return "Essa conta foi desativada."
		"TOO_MANY_ATTEMPTS_TRY_LATER": return "Muitas tentativas. Espere alguns minutos e tente de novo."
		"SEM_CONEXAO": return "Sem conexão com a internet. Verifique e tente de novo."
		"OPERATION_NOT_ALLOWED", "PASSWORD_LOGIN_DISABLED": return "O login por e-mail não está ativado no servidor."
		"TOKEN_EXPIRED", "INVALID_REFRESH_TOKEN", "USER_NOT_FOUND", "SEM_SESSAO": return "Sua sessão expirou. Entre na conta de novo."
	return "Não deu certo (%s). Tente de novo." % erro
