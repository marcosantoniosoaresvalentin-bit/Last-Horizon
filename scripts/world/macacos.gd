extends Node3D
## Macacos-prego: bandos que vivem da palmeira bacaba e espalham os caroços dela.
##
## - Um depende do outro: o macaco come os frutos maduros (outubro a dezembro) e solta
##   os caroços longe, onde passa; é assim que a bacaba nasce em lugar novo.
## - O ano todo o bando precisa de bacaba adulta por perto (frutos, flores, o miolo e os
##   bichinhos que vivem na copa): sem bacaba ao alcance, passa fome e vão morrendo.
## - Sobem em qualquer árvore ou palmeira (para comer, dormir e fugir).
## - Reprodução: de outubro a março as fêmeas adultas (4 anos ou mais) bem alimentadas
##   podem emprenhar; a gestação dura uns 5 a 6 meses e nasce um filhote só. O filhote
##   anda agarrado nas costas da mãe nos primeiros 6 meses. Com fome, perde a gestação.
## Perto do jogador, os macacos aparecem: andam de quatro, sobem nos troncos e sentam.

const Modelo := preload("res://scripts/world/macaco_modelo.gd")
const Sons := preload("res://scripts/sons.gd")
const RANGE := 200.0          # até onde o bando procura bacaba (m)
const EAT_RANGE := 120.0      # de onde come frutos no dia
const STARVE_DAYS := 15       # dias sem bacaba até começarem a morrer
const SPLIT := 18             # bando grande demais se divide em dois (não tem limite de macacos)
const SHOW := 80.0            # perto assim do jogador o bando aparece

## Bando: {x, z (árvore onde está), fome (dias sem comida),
##   membros: [{id, nasc (dia), sexo ("f"/"m"), gravida_ate (dia do parto ou -1), mae (id ou -1)}]}
var troops: Array = []
var last_day := 0
var _jogo: Node
var _arv: Node
var _cip: Node
var _bac: Node
var _rng := RandomNumberGenerator.new()
var _agents := {}             # índice do bando -> [agentes]
var _next_id := 1
var _call_t := {}             # bando -> segundos até o próximo assobio de contato
var _alarm_t := {}            # bando -> espera até poder dar alarme de novo
var _cur := -1                # bando sendo animado agora
const ADULT_F := 1460         # dias: fêmea pode ter filhote a partir dos 4 anos
const CARRY_DAYS := 180       # filhote nas costas da mãe


func build(jogo: Node, arvores: Node, cipos: Node, bacabas: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_cip = cipos
	_bac = bacabas
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 7717
	last_day = int(jogo.sim.elapsed_days())
	if save_path == "" or not _load(save_path):
		_generate()
	else:
		_move_to_bacaba()


## Bando de jogo antigo (que vivia do cipó) sem bacaba por perto: muda para a bacaba
## adulta mais perto.
func _move_to_bacaba() -> void:
	var adults: Array = _bac.adult_palms()
	for t in troops:
		var best = null
		var bd := 1e9
		for p in adults:
			var d := Vector2(float(p.x) - float(t.x), float(p.z) - float(t.z)).length()
			if d < bd:
				bd = d
				best = p
		if best != null and bd > RANGE * 0.8:
			t.x = float(best.x)
			t.z = float(best.z)
			t.fome = 0


func _generate() -> void:
	var adults: Array = _bac.adult_palms()
	if adults.is_empty():
		return
	# dois bandos onde tem mais bacaba adulta junto
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
			mem.append(_member(last_day - _rng.randi_range(600, 6000), -1))
		# uma mãe já com filhote nas costas
		for m in mem:
			if m.sexo == "f" and last_day - int(m.nasc) >= ADULT_F:
				mem.append(_member(last_day - _rng.randi_range(20, 120), int(m.id)))
				break
		troops.append({"x": float(best.x), "z": float(best.z), "fome": 0, "membros": mem})


func _member(nasc: int, mae: int) -> Dictionary:
	_next_id += 1
	return {"id": _next_id, "nasc": nasc, "sexo": "f" if _rng.randf() < 0.5 else "m", "gravida_ate": -1, "mae": mae}


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
	var adults: Array = _bac.adult_palms()
	var month := _month(day)
	var fruit: bool = _bac.ripe_season(day)
	var keep := []
	for t in troops:
		var near := []
		for pl in adults:
			if Vector2(float(pl.x) - float(t.x), float(pl.z) - float(t.z)).length() < RANGE:
				near.append(pl)
		# fome: sem bacaba adulta ao alcance; aí o bando sai procurando (anda uns 2 km
		# no dia, na direção da bacaba adulta mais perto, em qualquer canto do mapa)
		if near.is_empty():
			t.fome = int(t.fome) + 1
			var alvo = null
			var bd := 1e18
			for pl in adults:
				var d2 := Vector2(float(pl.x) - float(t.x), float(pl.z) - float(t.z)).length_squared()
				if d2 < bd:
					bd = d2
					alvo = pl
			if alvo != null:
				var v := Vector2(float(alvo.x) - float(t.x), float(alvo.z) - float(t.z))
				var passo := minf(v.length(), 2000.0)
				var np := Vector2(float(t.x), float(t.z)) + v.normalized() * passo
				t.x = np.x
				t.z = np.y
		else:
			t.fome = 0
		var mem: Array = t.membros
		if int(t.fome) > STARVE_DAYS and not mem.is_empty() and _rng.randf() < 0.12:
			# morreu de fome (os filhotes primeiro)
			var young := 0
			for i in mem.size():
				if int(mem[i].nasc) > int(mem[young].nasc):
					young = i
			mem.remove_at(young if _rng.randf() < 0.6 else _rng.randi() % mem.size())
		if not mem.is_empty() and _rng.randf() < 0.0003 * mem.size():
			mem.remove_at(_rng.randi() % mem.size())          # velhice, doença, gavião...
		var breeding := month >= 10 or month <= 3
		var born := []
		for m in mem:
			var ga := int(m.get("gravida_ate", -1))
			if ga >= 0:
				if int(t.fome) > STARVE_DAYS:
					m.gravida_ate = -1                         # com fome, perde a gestação
				elif day >= ga:
					m.gravida_ate = -1
					born.append(_member(day, int(m.id)))       # nasce um filhote só
				continue
			if breeding and str(m.get("sexo", "")) == "f" and day - int(m.nasc) >= ADULT_F and int(t.fome) == 0 \
					and not _has_baby(mem, int(m.id), day) \
					and _rng.randf() < 0.008:
				m.gravida_ate = day + _rng.randi_range(150, 180)   # gestação de 5 a 6 meses
		mem.append_array(born)
		if mem.is_empty():
			continue          # o bando acabou
		# muda de lugar todo dia (andam uns 1 a 3 km): vai para uma bacaba, ou para
		# uma árvore qualquer perto dela (sobem em qualquer uma)
		if not near.is_empty():
			var pl: Dictionary = near[_rng.randi() % near.size()]
			t.x = float(pl.x)
			t.z = float(pl.z)
			if _rng.randf() < 0.4:
				var opts := []
				for p in _arv.plants:
					if int(p[5]) != 2 and _arv.height_of(p, day) >= 6.0 \
							and Vector2(float(p[0]) - float(pl.x), float(p[1]) - float(pl.z)).length() < 30.0:
						opts.append(p)
				if not opts.is_empty():
					var tr: Array = opts[_rng.randi() % opts.size()]
					t.x = float(tr[0])
					t.z = float(tr[1])
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
					_bac.drop_seed(float(pl.x) + cos(a) * d, float(pl.z) + sin(a) * d, day)
		# bando grande demais: uma parte sai e forma outro bando (vai para outra bacaba)
		if mem.size() > SPLIT:
			var sai := []
			for k in mem.size() / 2:
				sai.append(mem.pop_back())
			var dest: Dictionary = adults[_rng.randi() % adults.size()] if not adults.is_empty() else {"x": t.x, "z": t.z}
			keep.append({"x": float(dest.x), "z": float(dest.z), "fome": 0, "membros": sai})
		keep.append(t)
	troops = keep


func _has_baby(mem: Array, mid: int, day: int) -> bool:
	for c in mem:
		if int(c.get("mae", -1)) == mid and day - int(c.nasc) < 365:
			return true
	return false


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
	for p in _bac.palms:
		if absf(float(p.x) - x) < 0.05 and absf(float(p.z) - z) < 0.05 and int(p.morta) < 0 and _bac.trunk_h(p) > 2.0:
			return p
	return null


# a árvore (Array) ou a palmeira (Dictionary) onde o macaco sobe
func _host_ok(h) -> bool:
	if h is Dictionary:
		return _bac.alive(h)
	return h != null and int(h[5]) != 2


func _host_point(h, y: float, ang: float, out := 0.0) -> Vector3:
	if h is Dictionary:
		return _bac.trunk_point(h, y, ang, out)
	return _arv.trunk_point(h, y, ang, out)


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
	var ride := -1
	if age < CARRY_DAYS:
		ride = int(m.get("mae", -1))
	return {"node": n, "pos": p, "state": "sentar", "timer": _rng.randf_range(1.0, 6.0), "goal": p, "h": 0.0, "ang": 0.0, "top": 0.0,
		"id": int(m.get("id", -1)), "ride": ride}


func _ground_spot(t: Dictionary) -> Vector3:
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(1.5, 6.0)
	var x := float(t.x) + cos(a) * r
	var z := float(t.z) + sin(a) * r
	return Vector3(x, _jogo.surface_at(x, z), z)


## Movimento de cada macaco (chamado todo quadro).
func update(delta: float) -> void:
	_agents_sync()
	var pp: Vector3 = _jogo._player.global_position
	for i in _agents:
		var t: Dictionary = troops[int(i)]
		var host = _tree_at(float(t.x), float(t.z))
		if host == null:
			# a árvore do bando caiu: muda para a árvore em pé mais perto
			var best = null
			var bd := 1e9
			for p in _arv.plants:
				if int(p[5]) == 2 or _arv.height_of(p, last_day) < 6.0:
					continue
				var d := Vector2(float(p[0]) - float(t.x), float(p[1]) - float(t.z)).length()
				if d < bd and d > 3.0:
					bd = d
					best = p
			if best != null:
				t.x = float(best[0])
				t.z = float(best[1])
		_cur = int(i)
		_calls(int(i), delta)
		var by_id := {}
		for a in _agents[i]:
			by_id[int(a.id)] = a
		for a in _agents[i]:
			var mom = by_id.get(int(a.ride))
			if mom != null:
				# filhote nas costas da mãe
				var n: Node3D = a.node
				var bp: Node3D = (mom.node as Node3D).back_point
				n.global_transform = bp.global_transform.scaled_local(n.scale)
				n.mode = "ride"
				a.pos = n.global_position
				continue
			_agent_step(a, t, host, pp, delta)


func _agent_step(a: Dictionary, t: Dictionary, host, pp: Vector3, delta: float) -> void:
	var n: Node3D = a.node
	a.timer = float(a.timer) - delta
	var pos: Vector3 = a.pos
	# jogador muito perto: foge para o tronco e sobe
	if str(a.state) in ["sentar", "andar"] and Vector2(pos.x - pp.x, pos.z - pp.z).length() < 3.5 and host != null:
		_start_climb(a, host)
		_alarm(pos)
	# a árvore em que estava foi derrubada: pula para o chão e foge
	var mine = a.get("tree")
	var mine_ok: bool = _host_ok(mine)
	if not mine_ok and str(a.state) in ["subir", "descer", "no_alto", "ate_tronco"]:
		var away := Vector3(pos.x - float(t.x), 0, pos.z - float(t.z))
		if away.length() < 0.05:
			away = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
		a.vel = away.normalized() * _rng.randf_range(1.5, 3.0) + Vector3.UP * 1.5
		a.state = "cair"
		if _rng.randf() < 0.5:
			Sons.play_at(self, "macaco_guincho", pos, 0.0, _rng.randf_range(0.9, 1.15), 120.0, 8.0)   # susto: a árvore caiu
	match str(a.state):
		"cair":
			var v: Vector3 = a.vel
			v.y -= 9.8 * delta
			pos += v * delta
			a.vel = v
			var gy: float = _jogo.surface_at(pos.x, pos.z)
			n.mode = "climb"
			if pos.y <= gy:
				pos.y = gy
				# foge correndo para longe de onde a árvore caiu
				var far := Vector3(pos.x - float(t.x), 0, pos.z - float(t.z)).normalized() * 12.0
				a.goal = Vector3(pos.x + far.x, 0, pos.z + far.z)
				a.goal.y = _jogo.surface_at(a.goal.x, a.goal.z)
				a.state = "andar"
		"andar":
			var to: Vector3 = a.goal - pos
			to.y = 0.0
			var sp := 3.0 if to.length() > 6.0 else (1.6 if to.length() > 4.0 else 1.0)
			if to.length() < 0.15:
				a.state = "sentar"
				a.timer = _rng.randf_range(3.0, 9.0)
			else:
				var stp := minf(to.length(), sp * delta)
				pos += to.normalized() * stp
				pos.y = _jogo.surface_at(pos.x, pos.z)
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
				pos.y = _jogo.surface_at(pos.x, pos.z)
				n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 10.0))
			n.mode = "walk"
			n.speed = 2.2
		"subir", "descer":
			if not mine_ok:
				a.state = "andar"
				a.goal = _ground_spot(t)
			else:
				host = mine
				var up := str(a.state) == "subir"
				a.h = clampf(float(a.h) + (1.0 if up else -1.0) * 1.1 * delta, 0.0, float(a.top))
				pos = _host_point(host, float(a.h) + 0.15, float(a.ang), 0.12)
				var c: Vector3 = _host_point(host, float(a.h) + 0.15, float(a.ang), 0.0)
				var face := c - pos
				n.rotation = Vector3(0, atan2(-face.x, -face.z), 0)
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
	if str(a.state) in ["andar", "sentar", "ate_tronco"]:
		# o corpo acompanha a inclinação do chão
		var e := 0.2
		var nx: float = (_jogo.surface_at(pos.x + e, pos.z) - _jogo.surface_at(pos.x - e, pos.z)) / (2.0 * e)
		var nz: float = (_jogo.surface_at(pos.x, pos.z + e) - _jogo.surface_at(pos.x, pos.z - e)) / (2.0 * e)
		var up := Vector3(-nx, 1.0, -nz).normalized()
		var yaw := n.rotation.y
		n.basis = (Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw)).scaled(n.scale)


## Sons: o bando conversa com assobios de contato de vez em quando (procurando comida,
## para não se perder um do outro); de noite fica quieto. Na época da bacaba madura, mais
## trinados (estão comendo juntos). Alarme só quando o jogador chega perto.
func _calls(i: int, delta: float) -> void:
	_alarm_t[i] = maxf(0.0, float(_alarm_t.get(i, 0.0)) - delta)
	var h: float = _jogo.sim.hour()
	if h < 5.8 or h > 18.3:
		return
	var t := float(_call_t.get(i, _rng.randf_range(3.0, 10.0))) - delta
	if t <= 0.0:
		var list: Array = _agents[i]
		var who: Dictionary = list[_rng.randi() % list.size()]
		if int(who.get("ride", -1)) < 0:
			var trill: bool = _rng.randf() < (0.4 if _bac.ripe_season(last_day) else 0.2)
			Sons.play_at(self, "macaco_trinado" if trill else "macaco_assobio", who.pos + Vector3.UP * 0.4,
				0.0, _rng.randf_range(0.92, 1.1), 110.0, 7.0)
		t = _rng.randf_range(7.0, 24.0)
		if _jogo.sim.raining:
			t *= 2.5                  # na chuva quase não chamam
	_call_t[i] = t


func _alarm(pos: Vector3) -> void:
	if float(_alarm_t.get(_cur, 0.0)) > 0.0:
		return
	_alarm_t[_cur] = _rng.randf_range(10.0, 16.0)
	Sons.play_at(self, "macaco_alarme", pos + Vector3.UP * 0.4, 0.0, _rng.randf_range(0.95, 1.08), 140.0, 9.0)


func _start_climb(a: Dictionary, host) -> void:
	a.tree = host
	var pos: Vector3 = a.pos
	var hx: float = float(host.x) if host is Dictionary else float(host[0])
	var hz: float = float(host.z) if host is Dictionary else float(host[1])
	var ang := atan2(pos.z - hz, pos.x - hx) + _rng.randf_range(-0.5, 0.5)
	a.ang = ang
	a.h = 0.0
	if host is Dictionary:
		a.top = maxf(1.5, _bac.trunk_h(host) - _rng.randf_range(0.3, 0.6))   # sobe até a copa (onde ficam os cachos)
	else:
		a.top = clampf(_arv.height_of(host, last_day) * _rng.randf_range(0.25, 0.55), 2.0, 9.0)
	a.goal = _host_point(host, 0.15, ang, 0.35)
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
	for t in troops:
		for m in t.membros:
			if not m.has("id"):
				_next_id += 1
				m.id = _next_id
				m.sexo = "f" if _rng.randf() < 0.5 else "m"
				m.gravida_ate = -1
				m.mae = -1
			_next_id = maxi(_next_id, int(m.id))
	last_day = mini(int(d.get("dia", last_day)), last_day)
	return true
