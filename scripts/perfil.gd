extends RefCounted
## Perfil do jogador neste celular: apelido no jogo e personagem escolhido.
## Com conta, o apelido vem da conta (users/<uid>.apelido).

const Conta := preload("res://scripts/conta.gd")
const PATH := "user://perfil.json"
const OLD_SKIN := "user://personagem.txt"
const MAX_NAME := 20


static func _read() -> Dictionary:
	if FileAccess.file_exists(PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary:
			return data
	var d := {}
	if FileAccess.file_exists(OLD_SKIN):
		d["skin"] = FileAccess.get_file_as_string(OLD_SKIN).strip_edges()
	return d


static func _write(d: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "\t"))
		f.close()


static func nome() -> String:
	# com conta, o nome que vale é o apelido salvo na conta
	var c := Conta.session()
	if not c.is_empty() and str(c.get("nome", "")) != "":
		return str(c.nome)
	return str(_read().get("nome", "Sobrevivente"))


static func set_nome(n: String) -> void:
	var d := _read()
	d["nome"] = n.strip_edges().left(MAX_NAME)
	_write(d)


static func skin() -> String:
	var s := str(_read().get("skin", "homem"))
	return s if s in ["homem", "mulher"] else "homem"


## Modo de teste: fabricar sem gastar, pedra fica pronta na hora, madeira corta
## numa batida e as ferramentas não gastam. Só neste celular.
static func teste() -> bool:
	return bool(_read().get("teste", false))


static func set_teste(on: bool) -> void:
	var d := _read()
	d["teste"] = on
	_write(d)


## Câmera em terceira pessoa (atrás do personagem) neste celular.
static func terceira() -> bool:
	return bool(_read().get("terceira", false))


static func set_terceira(on: bool) -> void:
	var d := _read()
	d["terceira"] = on
	_write(d)


## O Livro do Sobrevivente já abriu sozinho uma vez neste celular.
static func livro_visto() -> bool:
	return bool(_read().get("livro_visto", false))


static func set_livro_visto() -> void:
	var d := _read()
	d["livro_visto"] = true
	_write(d)


static func set_skin(s: String) -> void:
	var d := _read()
	d["skin"] = s
	_write(d)
