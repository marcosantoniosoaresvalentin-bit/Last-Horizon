extends Node3D
## Tamanduá-bandeira: o predador dos cupins.
##
## Vida (um dia de cada vez, mesmo longe do jogador):
## - Solitário e andarilho: não tem lugar fixo. Anda pelo mapa todo de cupinzeiro em
##   cupinzeiro: come nos que estão em volta de onde chegou (de cada um só um pouco: fica
##   um minuto e vai embora antes dos soldados juntarem) e, satisfeito ou sem comida ali,
##   escolhe outro destino (mais um que não visitou faz tempo), andando uns 3 km por dia.
## - Não tem limite de quantos: a comida (os cupins), a velhice e (depois) os predadores
##   é que controlam. Sem cupim por perto passa fome; muita fome, morre.
## - Cruza no fim das chuvas (março a maio); a gestação é de uns 190 dias, então o
##   filhote (um só) nasce no começo das chuvas, junto da revoada dos cupins.
## - O filhote anda nas costas da mãe uns 6 meses (deitado em cima, a faixa preta dele
##   em cima da dela) e segue a mãe até uns 10 meses; adulto com 2 anos e meio.
##   Vive uns 15 anos.
##
## Rotina (perto do jogador):
## - Ativo de manhã cedo e de tardinha até a noite; no calor do meio do dia e de
##   madrugada dorme deitado, enrolado no próprio rabo.
## - Ativo: anda devagar, focinho no chão cheirando, de cupinzeiro em cupinzeiro;
##   em cada um cava com a unha da frente, enfia o focinho no buraco e passa a língua.
## - Gente chegando perto demais: levanta nas patas de trás com os braços abertos
##   (as unhas) e depois vai embora a galope.

const Modelo := preload("res://scripts/world/tamandua_modelo.gd")

const START := 4
const PASSO_DIA := 3000.0        # m que anda num dia indo para o próximo cupinzeiro
const COME_R := 35.0             # come nos cupinzeiros até essa distância de onde está
const ADULT := 913              # dias (2,5 anos)
const GEST := 190
const CARRY := 180              # nas costas da mãe
const INDEP := 300              # segue a mãe até aqui
const LIFE := 5475             # uns 15 anos
const HOME := 140.0             # raio da área de cada um (m)
const SHOW := 90.0              # perto assim do jogador aparece
const WALK := 0.45              # m/s
const RUN := 2.2

var bichos: Array = []          # {id, sexo, nasc, x, z, mae, prenhe, fome, vida}
var last_day := 0
var _next_id := 1
var _jogo: Node
var _arv: Node
var _cup: Node
var _rng := RandomNumberGenerator.new()
var _agents := {}               # id -> {node, modo, alvo, t, fase, yaw, comeu, ...}


func build(jogo: Node, arvores: Node, cupins: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_cup = cupins
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 9191
	last_day = int(jogo.sim.elapsed_days())
	if save_path == "" or not _load(save_path):
		_generate()


func count() -> int:
	return bichos.size()


func _generate() -> void:
	var cols: Array = _cup.colonies
	if cols.is_empty():
		return
	for k in START:
		var c: Dictionary = cols[_rng.randi() % cols.size()]
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(4.0, 15.0)
		var b := _novo("f" if k % 2 == 0 else "m", last_day - _rng.randi_range(ADULT + 100, 3500), float(c.x) + cos(a) * r, float(c.z) + sin(a) * r, -1)
		bichos.append(b)


func _novo(sexo: String, nasc: int, x: float, z: float, mae: int) -> Dictionary:
	var b := {"id": _next_id, "sexo": sexo, "nasc": nasc, "x": x, "z": z, "mae": mae, "prenhe": -1, "fome": 0,
		"vida": LIFE + _rng.randi_range(-900, 700)}
	_next_id += 1
	return b


func _find(id: int) -> Dictionary:
	for b in bichos:
		if int(b.id) == id:
			return b
	return {}


func age(b: Dictionary) -> int:
	return last_day - int(b.nasc)


# ================== UM DIA ==================

func tick() -> void:
	var day := int(_jogo.sim.elapsed_days())
	if day <= last_day:
		return
	var n := 0
	while last_day < day and n < 120:
		last_day += 1
		_day(last_day)
		n += 1
	last_day = day


static func _month(day: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(preload("res://scripts/mundo_sim.gd").start_unix() + day * 86400)
	return int(d.month)


func _day(day: int) -> void:
	var month := _month(day)
	var keep := []
	var born := []
	var cols: Array = _cup.colonies
	for b in bichos:
		var ag := day - int(b.nasc)
		if ag > int(b.vida):
			continue                           # morreu de velho
		var mae := _find(int(b.mae)) if int(b.mae) >= 0 and ag < INDEP else {}
		if int(b.mae) >= 0 and ag < CARRY and mae.is_empty():
			continue                           # filhote pequeno sem a mãe não vive
		if not mae.is_empty():
			b.x = float(mae.x) + 0.8
			b.z = float(mae.z)
			keep.append(b)
			continue
		# come: um pouco de cada cupinzeiro em volta de onde está
		var need := 0.0015 if ag >= ADULT else 0.0007
		var got := 0.0
		var p := Vector2(float(b.x), float(b.z))
		for i in cols.size():
			var c: Dictionary = cols[i]
			if float(c.pop) <= 0.05 or got >= need:
				continue
			if p.distance_to(Vector2(float(c.x), float(c.z))) < COME_R:
				var bite := minf(need - got, float(c.pop) * 0.01)       # o dia de comida tirado dali
				_cup.eat_colony(i, bite)
				got += bite
				_visitou(b, i, day)
		if got >= need * 0.5:
			b.fome = 0
		else:
			b.fome = int(b.fome) + 1
			if int(b.fome) > 40:
				continue                           # morreu de fome
		# satisfeito ou sem comida aqui: segue viagem para outro cupinzeiro (no mapa todo)
		if not _agents.has(int(b.id)):
			var dest := int(b.get("dest", -1))
			var chegou: bool = dest >= 0 and dest < cols.size() and p.distance_to(Vector2(float(cols[dest].x), float(cols[dest].z))) < COME_R
			# chegou: fica uns dias comendo ali (vai embora quando a comida fraca ou dá vontade)
			if chegou and got >= need * 0.9 and _rng.randf() < 0.6:
				pass
			elif dest < 0 or dest >= cols.size() or float(cols[dest].pop) <= 0.05 or chegou:
				dest = _novo_destino(b, day)
				b["dest"] = dest
			if dest >= 0:
				var c3: Dictionary = cols[dest]
				var v := Vector2(float(c3.x), float(c3.z)) - p
				var np := p + v.normalized() * minf(v.length(), PASSO_DIA * _rng.randf_range(0.5, 1.0))
				b.x = np.x
				b.z = np.y
		# cria: cruza março-maio, nasce ~190 dias depois
		if str(b.sexo) == "f" and ag >= ADULT:
			if int(b.prenhe) >= 0:
				if day - int(b.prenhe) >= GEST:
					b.prenhe = -1
					var f := _novo("f" if _rng.randf() < 0.5 else "m", day, float(b.x), float(b.z), int(b.id))
					born.append(f)
			elif month >= 3 and month <= 5 and not _has_pup(b, day) and _male_adult(day):
				if _rng.randf() < 0.05:
					b.prenhe = day
		keep.append(b)
	keep.append_array(born)
	bichos = keep
	# filhote que cresceu deixa a mãe
	for b in bichos:
		if int(b.mae) >= 0 and day - int(b.nasc) >= INDEP:
			b.mae = -1


## O próximo cupinzeiro para onde vai: qualquer um do mapa com cupim, preferindo os mais
## perto e os que não visitou faz tempo (assim anda o mapa todo, sem lugar fixo).
func _novo_destino(b: Dictionary, day: int) -> int:
	var cols: Array = _cup.colonies
	var p := Vector2(float(b.x), float(b.z))
	var vis: Dictionary = b.get("vis", {})
	var tot := 0.0
	var pesos := []
	for i in cols.size():
		var c: Dictionary = cols[i]
		var w := 0.0
		if float(c.pop) > 0.15:
			var d := p.distance_to(Vector2(float(c.x), float(c.z)))
			if d >= COME_R:
				w = float(c.pop) / (1.0 + d / 600.0)
				var ult := int(vis.get(str(i), -9999))
				if day - ult < 20:
					w *= 0.05                 # passou lá faz pouco: quase nunca volta logo
		pesos.append(w)
		tot += w
	if tot <= 0.0:
		return -1
	var r := _rng.randf() * tot
	for i in pesos.size():
		r -= float(pesos[i])
		if r <= 0.0:
			return i
	return pesos.size() - 1


func _visitou(b: Dictionary, i: int, day: int) -> void:
	if not b.has("vis"):
		b["vis"] = {}
	b.vis[str(i)] = day
	if (b.vis as Dictionary).size() > 30:
		var velho := ""
		var vd := 1 << 30
		for k in b.vis:
			if int(b.vis[k]) < vd:
				vd = int(b.vis[k])
				velho = k
		(b.vis as Dictionary).erase(velho)


func _has_pup(b: Dictionary, day: int) -> bool:
	for o in bichos:
		if int(o.mae) == int(b.id) and day - int(o.nasc) < INDEP:
			return true
	return false


func _male_adult(day: int) -> bool:
	for o in bichos:
		if str(o.sexo) == "m" and day - int(o.nasc) >= ADULT:
			return true
	return false


# ================== NA TELA ==================

## Ativo de manhã cedo e de tardinha/noite; dorme no calor e de madrugada.
func _awake(h: float) -> bool:
	return (h >= 5.5 and h < 10.5) or (h >= 16.0 and h < 23.0)


func update(delta: float) -> void:
	if _jogo == null or _jogo._player == null:
		return
	var pp: Vector3 = _jogo._player.position
	var h: float = _jogo.sim.hour()
	# quem aparece / some
	for b in bichos:
		var id := int(b.id)
		var near := Vector2(float(b.x) - pp.x, float(b.z) - pp.z).length() < SHOW
		var carried := int(b.mae) >= 0 and age(b) < CARRY
		if near and not _agents.has(id) and not carried:
			_spawn(b)
		elif not near and _agents.has(id):
			(_agents[id].node as Node3D).queue_free()
			_agents.erase(id)
	for id in _agents.keys():
		var b := _find(id)
		if b.is_empty():
			(_agents[id].node as Node3D).queue_free()
			_agents.erase(id)
			continue
		_step(b, _agents[id], pp, h, delta)


func _spawn(b: Dictionary) -> void:
	var ag := age(b)
	var s := clampf(lerpf(0.45, 1.0, float(ag) / ADULT), 0.45, 1.0)
	var node := Modelo.build(s)
	add_child(node)
	var a := {"node": node, "modo": "parado", "alvo": Vector3.ZERO, "t": _rng.randf() * 10.0, "fase": 0.0,
		"yaw": _rng.randf() * TAU, "timer": _rng.randf_range(1.0, 4.0), "visto": {}, "s": s}
	_agents[int(b.id)] = a
	node.position = Vector3(float(b.x), _jogo.height_at(float(b.x), float(b.z)), float(b.z))
	node.rotation.y = a.yaw
	# filhote nas costas
	for o in bichos:
		if int(o.mae) == int(b.id) and age(o) < CARRY:
			var pup := Modelo.build(0.42)
			pup.name = "filhote"
			node.add_child(pup)
			pup.position = Vector3(-0.08, 0.66 / s, 0.0)
			pup.scale = Vector3.ONE * (0.42 / s)
			Modelo.pose(pup, "parado", 0.0, 0.0)


func _step(b: Dictionary, a: Dictionary, pp: Vector3, h: float, delta: float) -> void:
	var node: Node3D = a.node
	a.t = float(a.t) + delta
	var pos := Vector3(float(b.x), 0, float(b.z))
	var dist_p := Vector2(pos.x - pp.x, pos.z - pp.z).length()
	var modo := str(a.modo)
	var mae := _find(int(b.mae)) if int(b.mae) >= 0 else {}
	# medo de gente
	if modo != "defesa" and modo != "fugir":
		if (modo == "dormir" and dist_p < 2.2) or (modo != "dormir" and dist_p < 3.5):
			_set_modo(a, "defesa")
			a.timer = 2.5
			a.yaw = atan2(-(pp.z - pos.z), pp.x - pos.x)
	match modo:
		"defesa":
			a.timer = float(a.timer) - delta
			if float(a.timer) <= 0.0:
				var away := Vector3(pos.x - pp.x, 0, pos.z - pp.z).normalized()
				a.alvo = pos + away * 18.0
				_set_modo(a, "fugir")
		"fugir":
			if _walk(b, a, RUN, delta):
				_set_modo(a, "parado")
				a.timer = 3.0
		"dormir":
			if _awake(h) or not mae.is_empty() and str(_agent_modo(int(mae.id))) != "dormir":
				_set_modo(a, "parado")
				a.timer = 2.0
		"comer":
			a.timer = float(a.timer) - delta
			if float(a.timer) <= 0.0:
				a.visto[int(a.col)] = float(a.t)
				_set_modo(a, "parado")
				a.timer = _rng.randf_range(1.0, 3.0)
		"andar":
			if _walk(b, a, WALK, delta):
				if a.has("col") and int(a.col) >= 0:
					_set_modo(a, "comer")
					a.timer = _rng.randf_range(25.0, 45.0)        # um minuto de jogo no cupinzeiro
					var ci := int(a.col)
					if ci < _cup.colonies.size():
						_cup.eat_colony(ci, 0.0005)
						var c: Dictionary = _cup.colonies[ci]
						a.yaw = atan2(-(float(c.z) - pos.z), float(c.x) - pos.x)
				else:
					_set_modo(a, "parado")
					a.timer = _rng.randf_range(2.0, 6.0)
		_:   # parado: decide o que fazer
			a.timer = float(a.timer) - delta
			if float(a.timer) <= 0.0:
				if not _awake(h):
					_set_modo(a, "dormir")
				elif not mae.is_empty():
					var mp := Vector3(float(mae.x), 0, float(mae.z))
					a.alvo = mp + Vector3(-0.9, 0, 0.6)
					a.col = -1
					_set_modo(a, "andar")
				else:
					_choose_target(b, a)
	# filhote: segue a mãe de perto
	if not mae.is_empty() and str(a.modo) == "andar":
		a.alvo = Vector3(float(mae.x), 0, float(mae.z)) + Vector3(-0.9, 0, 0.6)
	# posição e pose
	var y: float = _jogo.surface_at(float(b.x), float(b.z))
	node.position = Vector3(float(b.x), y, float(b.z))
	node.rotation.y = lerp_angle(node.rotation.y, float(a.yaw), minf(1.0, delta * 4.0))
	var anim := str(a.modo)
	if anim == "fugir":
		anim = "correr"
	Modelo.pose(node, anim, float(a.fase), float(a.t))


func _agent_modo(id: int) -> String:
	return str(_agents[id].modo) if _agents.has(id) else "parado"


func _set_modo(a: Dictionary, m: String) -> void:
	a.modo = m


## Próximo cupinzeiro (o mais perto que não visitou faz pouco), ou um passeio.
func _choose_target(b: Dictionary, a: Dictionary) -> void:
	var p := Vector2(float(b.x), float(b.z))
	var best := -1
	var bd := 1e9
	for i in _cup.colonies.size():
		var c: Dictionary = _cup.colonies[i]
		if float(c.pop) <= 0.05:
			continue
		if a.visto.has(i) and float(a.t) - float(a.visto[i]) < 240.0:
			continue
		var d := p.distance_to(Vector2(float(c.x), float(c.z)))
		if d < 60.0 and d < bd:
			bd = d
			best = i
	if best >= 0:
		var c: Dictionary = _cup.colonies[best]
		var sz: Vector2 = _cup._mound_size(c)
		var holes: Array = _cup._mound_holes(c)
		# vai até um buraco baixo do cupinzeiro
		var ang := _rng.randf() * TAU
		for hh in holes:
			if float(hh[1]) < 0.3:
				ang = float(hh[0])
				break
		var hp := Vector3(float(c.x) + cos(ang) * (sz.y + 0.75), 0, float(c.z) + sin(ang) * (sz.y + 0.75))
		a.alvo = hp
		a.col = best
	else:
		# nenhum cupinzeiro aqui perto: segue viagem (para o destino dele no mapa)
		var dest := int(b.get("dest", -1))
		if dest < 0 or dest >= _cup.colonies.size():
			dest = _novo_destino(b, last_day)
			b["dest"] = dest
		var ang := _rng.randf() * TAU
		var to := Vector2(p.x + cos(ang) * 10.0, p.y + sin(ang) * 10.0)
		if dest >= 0:
			var cd: Dictionary = _cup.colonies[dest]
			var v := Vector2(float(cd.x), float(cd.z)) - p
			to = p + v.normalized() * minf(v.length(), 25.0)
		a.alvo = Vector3(to.x, 0, to.y)
		a.col = -1
	_set_modo(a, "andar")


## Anda até o alvo; true quando chegou. Desvia da água funda.
func _walk(b: Dictionary, a: Dictionary, speed: float, delta: float) -> bool:
	var pos := Vector3(float(b.x), 0, float(b.z))
	var to: Vector3 = a.alvo
	var d := Vector3(to.x - pos.x, 0, to.z - pos.z)
	var L := d.length()
	if L < 0.15:
		return true
	var dir := d / L
	var stp := minf(L, speed * float(a.s) * delta)
	var np := pos + dir * stp
	var c: Vector2i = _cup._cell(np.x, np.z)
	var sim = _jogo.sim
	var i: int = c.y * sim.W + c.x
	if float(sim.wat[i]) > 0.05 or float(sim.ter[i]) < sim.SEA + 0.3:
		return true                               # não entra na água: desiste do caminho
	b.x = np.x
	b.z = np.z
	a.yaw = atan2(-dir.z, dir.x)
	a.fase = float(a.fase) + stp / (0.32 * float(a.s)) * PI
	return false


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "dia": last_day, "prox": _next_id, "bichos": bichos}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	bichos = d.get("bichos", [])
	_next_id = int(d.get("prox", 1))
	last_day = mini(int(d.get("dia", last_day)), last_day)
	for b in bichos:
		for k in ["id", "nasc", "mae", "prenhe", "fome", "vida"]:
			b[k] = int(b[k])
	return true
