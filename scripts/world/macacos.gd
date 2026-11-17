extends Node3D
## Macacos-prego: bandos que vivem do cipó-titica e espalham as sementes dele.
##
## - Um depende do outro: o macaco come os frutos (dezembro a fevereiro) e solta as
##   sementes longe, onde passa; é o único jeito do cipó nascer em lugar novo.
## - O ano todo o bando precisa de cipó adulto por perto (frutos, brotos e folhas):
##   sem cipó ao alcance, passa fome e os macacos vão morrendo.
## - Bando bem alimentado tem filhotes (em novembro).
## Perto do jogador, os macacos aparecem: andam de quatro, sobem nos troncos e sentam.

const Modelo := preload("res://scripts/world/macaco_modelo.gd")
const RANGE := 200.0          # até onde o bando procura cipó (m)
const EAT_RANGE := 120.0      # de onde come frutos no dia
const STARVE_DAYS := 15       # dias sem cipó até começarem a morrer
const MAX_TROOP := 14
const SHOW := 80.0            # perto assim do jogador o bando aparece

## Bando: {x, z (árvore onde está), fome (dias sem comida), membros: [{nasc (dia)}]}
var troops: Array = []
var last_day := 0
var _jogo: Node
var _arv: Node
var _cip: Node
var _rng := RandomNumberGenerator.new()
var _agents := {}             # índice do bando -> [agentes]


func build(jogo: Node, arvores: Node, cipos: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_cip = cipos
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 7717
	last_day = int(jogo.sim.elapsed_days())
	if save_path == "" or not _load(save_path):
		_generate()


func _generate() -> void:
	var adults: Array = _cip.adult_plants()
	if adults.is_empty():
		return
	# dois bandos onde tem mais cipó adulto junto
	var used := []
	for b in 2:
		var best = null
		var bn := -1
		for pl in adults:
			var ok := true
			for u in used:
				if Vector2(float(pl.x) - u.x, float(pl.z) - u.y).length() < 150.0:
					ok = false
			if not ok:
				continue
			var n := 0
			for q in adults:
				if Vector2(float(q.x) - float(pl.x), float(q.z) - float(pl.z)).length() < RANGE:
					n += 1
			if n > bn:
				bn = n
				best = pl
		if best == null:
			break
		used.append(Vector2(float(best.x), float(best.z)))
		var mem := []
		for k in _rng.randi_range(6, 9):
			mem.append({"nasc": last_day - _rng.randi_range(200, 6000)})
		troops.append({"x": float(best.x), "z": float(best.z), "fome": 0, "membros": mem})


func tick() -> void:
	var day := int(_jogo.sim.elapsed_days())
	if day <= last_day:
		return
	while last_day < day:
		last_day += 1
		_day(last_day)
	_agents_sync(true)


static func _month(day: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(preload("res://scripts/mundo_sim.gd").start_unix() + day * 86400)
	return int(d.month)


func _day(day: int) -> void:
	var adults: Array = _cip.adult_plants()
	var month := _month(day)
	var fruit := month == 12 or month <= 2
	var keep := []
	for t in troops:
		var near := []
		for pl in adults:
			if Vector2(float(pl.x) - float(t.x), float(pl.z) - float(t.z)).length() < RANGE:
				near.append(pl)
		# fome: sem cipó adulto ao alcance
		if near.is_empty():
			t.fome = int(t.fome) + 1
		else:
			t.fome = 0
		var mem: Array = t.membros
		if int(t.fome) > STARVE_DAYS and not mem.is_empty() and _rng.randf() < 0.12:
			mem.remove_at(_rng.randi() % mem.size())          # morreu de fome
		if not mem.is_empty() and _rng.randf() < 0.0003 * mem.size():
			mem.remove_at(_rng.randi() % mem.size())          # velhice, doença, gavião...
		# filhotes em novembro, se o bando está bem alimentado
		if month == 11 and int(t.fome) == 0 and mem.size() >= 2 and mem.size() < MAX_TROOP \
				and near.size() >= mem.size() / 2 and _rng.randf() < 0.02:
			mem.append({"nasc": day})
		if mem.is_empty():
			continue          # o bando acabou
		# muda de árvore: vai para uma que tem cipó (andam uns 1 a 3 km por dia)
		if not near.is_empty():
			var pl: Dictionary = near[_rng.randi() % near.size()]
			var host = _cip._host_of(pl)
			if host != null:
				t.x = float(host[0])
				t.z = float(host[1])
		# época dos frutos: comem e soltam as sementes pelo caminho
		if fruit:
			for pl in near:
				if Vector2(float(pl.x) - float(t.x), float(pl.z) - float(t.z)).length() > EAT_RANGE:
					continue
				var bites := 0
				for m in mem.size():
					if _rng.randf() < 0.012:
						bites += 1
				for k in bites:
					var a := _rng.randf() * TAU
					var d := _rng.randf_range(10.0, 80.0)
					_cip.drop_seed(float(pl.x) + cos(a) * d, float(pl.z) + sin(a) * d, day)
		keep.append(t)
	troops = keep


func count() -> int:
	var n := 0
	for t in troops:
		n += (t.membros as Array).size()
	return n


# ================== NA TELA ==================

func _tree_at(x: float, z: float):
	for p in _arv.plants:
		if absf(float(p[0]) - x) < 0.05 and absf(float(p[1]) - z) < 0.05 and int(p[5]) != 2:
			return p
	return null


## Põe e tira os macacos da tela conforme a distância do jogador.
func _agents_sync(day_changed := false) -> void:
	var pp: Vector3 = _jogo._player.global_position
	for i in troops.size():
		var t: Dictionary = troops[i]
		var d := Vector2(float(t.x) - pp.x, float(t.z) - pp.z).length()
		var have := _agents.has(i)
		if d < SHOW and not have:
			var list := []
			for m in t.membros:
				list.append(_new_agent(t, m))
			_agents[i] = list
		elif d > SHOW + 25.0 and have:
			for a in _agents[i]:
				(a.node as Node3D).queue_free()
			_agents.erase(i)
		elif have and (_agents[i] as Array).size() != (t.membros as Array).size():
			for a in _agents[i]:
				(a.node as Node3D).queue_free()
			_agents.erase(i)
		elif have and day_changed:
			for a in _agents[i]:
				a.state = "andar"
				a.goal = _ground_spot(t)
	for k in _agents.keys():
		if int(k) >= troops.size():
			for a in _agents[k]:
				(a.node as Node3D).queue_free()
			_agents.erase(k)


func _new_agent(t: Dictionary, m: Dictionary) -> Dictionary:
	var n := Modelo.new()
	add_child(n)
	var age := float(last_day - int(m.nasc))
	var s := clampf(0.55 + age / 1500.0, 0.55, 1.0)
	n.scale = Vector3(s, s, s)
	var p := _ground_spot(t)
	n.global_position = p
	return {"node": n, "pos": p, "state": "sentar", "timer": _rng.randf_range(1.0, 6.0), "goal": p, "h": 0.0, "ang": 0.0, "top": 0.0}


func _ground_spot(t: Dictionary) -> Vector3:
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(1.5, 6.0)
	var x := float(t.x) + cos(a) * r
	var z := float(t.z) + sin(a) * r
	return Vector3(x, _jogo.height_at(x, z), z)


## Movimento de cada macaco (chamado todo quadro).
func update(delta: float) -> void:
	_agents_sync()
	var pp: Vector3 = _jogo._player.global_position
	for i in _agents:
		var t: Dictionary = troops[int(i)]
		var host = _tree_at(float(t.x), float(t.z))
		for a in _agents[i]:
			_agent_step(a, t, host, pp, delta)


func _agent_step(a: Dictionary, t: Dictionary, host, pp: Vector3, delta: float) -> void:
	var n: Node3D = a.node
	a.timer = float(a.timer) - delta
	var pos: Vector3 = a.pos
	# jogador muito perto: foge para o tronco e sobe
	if str(a.state) in ["sentar", "andar"] and Vector2(pos.x - pp.x, pos.z - pp.z).length() < 3.5 and host != null:
		_start_climb(a, host)
	match str(a.state):
		"andar":
			var to: Vector3 = a.goal - pos
			to.y = 0.0
			var sp := 1.6 if to.length() > 4.0 else 1.0
			if to.length() < 0.15:
				a.state = "sentar"
				a.timer = _rng.randf_range(3.0, 9.0)
			else:
				var stp := minf(to.length(), sp * delta)
				pos += to.normalized() * stp
				pos.y = _jogo.height_at(pos.x, pos.z)
				n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 8.0))
			n.mode = "walk"
			n.speed = sp
		"sentar":
			n.mode = "sit"
			if float(a.timer) <= 0.0:
				if host != null and _rng.randf() < 0.45:
					_start_climb(a, host)
				else:
					a.state = "andar"
					a.goal = _ground_spot(t)
		"ate_tronco":
			var to: Vector3 = a.goal - pos
			to.y = 0.0
			if to.length() < 0.1:
				a.state = "subir"
			else:
				pos += to.normalized() * minf(to.length(), 2.2 * delta)
				pos.y = _jogo.height_at(pos.x, pos.z)
				n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 10.0))
			n.mode = "walk"
			n.speed = 2.2
		"subir", "descer":
			if host == null:
				a.state = "andar"
				a.goal = _ground_spot(t)
			else:
				var up := str(a.state) == "subir"
				a.h = clampf(float(a.h) + (1.0 if up else -1.0) * 1.1 * delta, 0.0, float(a.top))
				pos = _arv.trunk_point(host, float(a.h) + 0.15, float(a.ang), 0.12)
				var c: Vector3 = _arv.trunk_point(host, float(a.h) + 0.15, float(a.ang), 0.0)
				var face := c - pos
				n.rotation.y = atan2(-face.x, -face.z)
				n.mode = "climb"
				if up and float(a.h) >= float(a.top) - 0.01:
					a.state = "no_alto"
					a.timer = _rng.randf_range(6.0, 16.0)
				elif not up and float(a.h) <= 0.01:
					a.state = "andar"
					a.goal = _ground_spot(t)
		"no_alto":
			n.mode = "climb"
			if float(a.timer) <= 0.0 and Vector2(pos.x - pp.x, pos.z - pp.z).length() > 4.0:
				a.state = "descer"
	a.pos = pos
	n.global_position = pos


func _start_climb(a: Dictionary, host: Array) -> void:
	var pos: Vector3 = a.pos
	var ang := atan2(pos.z - float(host[1]), pos.x - float(host[0])) + _rng.randf_range(-0.5, 0.5)
	a.ang = ang
	a.h = 0.0
	a.top = clampf(_arv.height_of(host, last_day) * _rng.randf_range(0.25, 0.55), 2.0, 9.0)
	a.goal = _arv.trunk_point(host, 0.15, ang, 0.35)
	a.goal.y = 0.0
	a.state = "ate_tronco"


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "dia": last_day, "bandos": troops}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	troops = d.get("bandos", [])
	last_day = mini(int(d.get("dia", last_day)), last_day)
	return true
