extends RefCounted
## Perfil do jogador neste celular: nome de usuário e personagem escolhido.
## (Quando as contas online estiverem ligadas, o nome também vai para a conta.)

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
	return str(_read().get("nome", "Sobrevivente"))


static func set_nome(n: String) -> void:
	var d := _read()
	d["nome"] = n.strip_edges().left(MAX_NAME)
	_write(d)


static func skin() -> String:
	var s := str(_read().get("skin", "homem"))
	return s if s in ["homem", "mulher"] else "homem"


static func set_skin(s: String) -> void:
	var d := _read()
	d["skin"] = s
	_write(d)
