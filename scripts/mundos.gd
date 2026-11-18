extends RefCounted
## Mundos salvos no celular. Cada mundo fica numa pasta user://mundos/<id>/ com:
##   mundo.json   nome, semente, datas e a data do jogo onde parou
##   mundo.dat    estado da simulação (terreno, água, solo, argila, tempo)
##   jogador.json posição do personagem e mochila

const ROOT := "user://mundos"
const MAX_NAME := 24


static func dir(id: String) -> String:
	return ROOT + "/" + id


## Todos os mundos, o jogado mais recentemente primeiro.
static func list() -> Array:
	var out := []
	var d := DirAccess.open(ROOT)
	if d == null:
		return out
	for id in d.get_directories():
		if id.begins_with("mp_"):
			continue          # cópia de mundo de outro jogador (multiplayer)
		var m := read_meta(id)
		if not m.is_empty():
			out.append(m)
	out.sort_custom(func(a, b): return int(a.get("ultimo", 0)) > int(b.get("ultimo", 0)))
	return out


static func read_meta(id: String) -> Dictionary:
	var p := dir(id) + "/mundo.json"
	if not FileAccess.file_exists(p):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not data is Dictionary:
		return {}
	data["id"] = id
	return data


static func write_meta(id: String, meta: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir(id))
	var m := meta.duplicate()
	m.erase("id")
	var f := FileAccess.open(dir(id) + "/mundo.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(m, "\t"))
		f.close()


## Cria um mundo novo (só os dados; o terreno é gerado ao entrar pela primeira vez).
static func create(world_name: String) -> String:
	var now := int(Time.get_unix_time_from_system())
	var id := "%d_%05d" % [now, randi() % 100000]
	write_meta(id, {
		"nome": world_name.strip_edges().left(MAX_NAME),
		"semente": randi_range(1, 2000000000),
		"criado": now,
		"ultimo": now,
		"data": "",
	})
	return id


static func delete(id: String) -> void:
	var p := dir(id)
	var d := DirAccess.open(p)
	if d:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(p)


## Atualiza a hora em que foi jogado e a data do jogo onde parou.
static func touch(id: String, game_date: String) -> void:
	var m := read_meta(id)
	if m.is_empty():
		return
	m["ultimo"] = int(Time.get_unix_time_from_system())
	m["data"] = game_date
	write_meta(id, m)


static func default_name() -> String:
	var used := {}
	for m in list():
		used[str(m.get("nome", ""))] = true
	var n := 1
	while used.has("Mundo %d" % n):
		n += 1
	return "Mundo %d" % n


## "agora mesmo", "há 5 min", "há 3 h", "há 2 dias"
static func ago(unix: int) -> String:
	var s := int(Time.get_unix_time_from_system()) - unix
	if s < 60:
		return "agora mesmo"
	if s < 3600:
		return "há %d min" % (s / 60)
	if s < 86400:
		return "há %d h" % (s / 3600)
	var d := s / 86400
	return "há %d dia%s" % [d, "" if d == 1 else "s"]
