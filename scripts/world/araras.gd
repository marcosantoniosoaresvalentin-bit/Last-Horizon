extends Node3D
## Araras-canindé (Ara ararauna): vivem em bando, em casais para a vida toda.
##
## Comida: frutos da bacaba (maduros de outubro a dezembro), do buriti (dezembro a
## junho: elas roem a casca de escamas e comem a polpa amarela, pousadas nos cachos) e
## do cipó-titica (dezembro a fevereiro); no resto do ano, flores, frutos verdes e o
## miolo das palmeiras, sempre perto de bacaba, buriti ou cipó adulto. Sem nada disso
## por perto passam fome. Elas espalham os caroços: a bacaba (junto com os macacos), o
## buriti (nasce se cair em chão encharcado) e o cipó (só elas).
##
## Dia: dormem juntas numa árvore alta; ao clarear saem gritando em bando (os casais
## voam lado a lado), comem de manhã, descansam no calor, comem de novo à tarde e
## voltam para o dormitório antes de escurecer. No pouso ficam quietas, só um resmungo
## de vez em quando; voando gritam para o bando não se perder; com gente perto, alarme.
##
## Reprodução (agosto a janeiro): o casal procura um oco no alto de uma palmeira morta
## ou de uma árvore grande/morrendo. A fêmea bota 1 a 3 ovos (quase sempre 2 ou 3) e
## choca uns 26 dias; o macho traz comida para ela. Os filhotes ficam no oco uns 90 dias
## (os pais trazem comida o dia todo) e então voam e entram no bando. Com 3 anos já podem
## formar casal.

const Modelo := preload("res://scripts/world/arara_modelo.gd")
const Sons := preload("res://scripts/sons.gd")
# (sem limite de araras: os ocos para o ninho, a comida, a velhice e o gavião controlam)
const ADULT_DAYS := 1095          # 3 anos
const INCUB_DAYS := 26
const NEST_DAYS := 90
const STARVE_DAYS := 25
const VIEW := 280.0               # até onde aparecem (voando dá para ver longe)
const SPEED := 12.0               # m/s voando (uns 45 km/h)
const REAL_S_PER_HOUR := 20.0     # 1 hora do jogo = 20 s de verdade (dia de 8 min)
const CRUISE := 16.0              # quanto voam acima das copas (m)

## Ave: {id, nasc (dia), sexo ("f"/"m"), par (id do par ou -1)}
var birds: Array = []
var _aperto := 0.0                # araras a mais do que a comida aguenta (0 = sobra comida)
## Ninho: {x, z (árvore ou palmeira), tipo ("bur": buriti seco), h (altura do oco), ang,
##   f (fêmea), m (macho), ovos, posto (dia), eclode (dia), filhotes, voa (dia)}
var nests: Array = []
## Ocos já usados (ficam marcados no tronco): [x, z, tipo, h, ang]
var holes: Array = []
var roost := Vector2(-1, -1)      # árvore onde o bando dorme
var fome := 0
var last_day := 0
var _jogo: Node
var _arv: Node
var _bac: Node
var _bur: Node = null                # buritis (o tronco seco é o ninho preferido da arara)
var _cip: Node
var _rng := RandomNumberGenerator.new()
var _next_id := 1
var _plans := {}                  # unidade (id da ave ou do casal) -> [paradas]
var _units := []                  # [{ids: [..], key}]
var _agents := {}                 # id -> {node, ...}
var _hole_nodes: Array = []
var _snd := {}                    # unidade -> segundos até poder gritar de novo
var _alarm_cd := {}
var _plan_hour := -1


func build(jogo: Node, arvores: Node, bacabas: Node, cipos: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_bac = bacabas
	_cip = cipos
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 9911
	last_day = int(jogo.sim.elapsed_days())
	if save_path == "" or not _load(save_path):
		_generate()
	_make_plans()
	_draw_holes()


func _generate() -> void:
	# um bando de uns 12: casais adultos e alguns jovens
	for k in 5:
		var f := _new_bird(last_day - _rng.randi_range(1300, 9000), "f")
		var m := _new_bird(last_day - _rng.randi_range(1300, 9000), "m")
		f.par = int(m.id)
		m.par = int(f.id)
	for k in _rng.randi_range(2, 4):
		_new_bird(last_day - _rng.randi_range(120, 1000), "f" if _rng.randf() < 0.5 else "m")
	_pick_roost()


func _new_bird(nasc: int, sexo: String) -> Dictionary:
	_next_id += 1
	var b := {"id": _next_id, "nasc": nasc, "sexo": sexo, "par": -1}
	birds.append(b)
	return b


## Morreu (picada de cobra comendo no chão, gavião...). O par fica sozinho.
func matar(id: int) -> void:
	var b = _bird(id)
	if b == null:
		return
	var pb = _bird(int(b.par))
	if pb != null:
		pb.par = -1
	birds.erase(b)


func _bird(id: int):
	for b in birds:
		if int(b.id) == id:
			return b
	return null


static func _month(day: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(preload("res://scripts/mundo_sim.gd").start_unix() + day * 86400)
	return int(d.month)


static func cipo_season(day: int) -> bool:
	var m := _month(day)
	return m == 12 or m <= 2


static func breeding_season(day: int) -> bool:
	var m := _month(day)
	return m >= 8 or m == 1


func _pick_roost() -> void:
	# a árvore viva mais alta perto do meio de onde tem comida
	var food := _food_points()
	var c := Vector2(320, 240)
	if not food.is_empty():
		c = Vector2.ZERO
		for p in food:
			c += p
		c /= food.size()
	var best = null
	var bs := -1e9
	for p in _arv.plants:
		if int(p[5]) != 0:
			continue
		var h: float = _arv.height_of(p, last_day)
		if h < 14.0:
			continue
		var d := Vector2(float(p[0]), float(p[1])).distance_to(c)
		var sc := h - d * 0.05
		if sc > bs:
			bs = sc
			best = p
	if best != null:
		roost = Vector2(float(best[0]), float(best[1]))


func _bur_adults() -> Array:
	if _bur == null:
		return []
	return _bur.palms.filter(func(p): return _bur.is_adult(p))


func _food_points() -> Array:
	var out := []
	for p in _bac.adult_palms():
		out.append(Vector2(float(p.x), float(p.z)))
	for p in _bur_adults():
		out.append(Vector2(float(p.x), float(p.z)))
	for pl in _cip.adult_plants():
		out.append(Vector2(float(pl.x), float(pl.z)))
	return out


# ================== DIA A DIA ==================

func tick() -> void:
	var day := int(_jogo.sim.elapsed_days())
	if day <= last_day:
		return
	while last_day < day:
		last_day += 1
		_day(last_day)
	_make_plans()
	_draw_holes()


func _day(day: int) -> void:
	var palms: Array = _bac.adult_palms()
	var vines: Array = _cip.adult_plants()
	var burs: Array = _bur_adults()
	fome = fome + 1 if palms.is_empty() and vines.is_empty() and burs.is_empty() else 0
	# a comida que tem dá para quantas araras (as palmeiras e os cipós adultos): passou
	# disso, falta comida para todas: nascem menos e as mais fracas morrem
	var cabe := maxf(4.0, (palms.size() + burs.size()) * 0.12 + vines.size() * 0.3)
	_aperto = clampf((birds.size() - cabe) / cabe, 0.0, 2.0)
	# morrendo: fome, velhice, gavião
	var keep := []
	for b in birds:
		var dead := _rng.randf() < 0.00012
		if fome > STARVE_DAYS and _rng.randf() < 0.03:
			dead = true
		if _aperto > 0.0 and _rng.randf() < 0.004 * _aperto:
			dead = true                       # comida não dá para todas
		if day - int(b.nasc) > 365 * 45 and _rng.randf() < 0.002:
			dead = true
		if dead:
			var pb = _bird(int(b.par))
			if pb != null:
				pb.par = -1
			continue
		keep.append(b)
	birds = keep
	if roost.x < 0 or _tree_at(roost) == null:
		_pick_roost()
	# comem e espalham os caroços
	if _bac.ripe_season(day) and not palms.is_empty():
		for b in birds:
			if _rng.randf() < 0.06:
				var src: Dictionary = palms[_rng.randi() % palms.size()]
				var a := _rng.randf() * TAU
				var d := _rng.randf_range(30.0, 400.0)    # voam longe com o fruto no bico
				_bac.drop_seed(float(src.x) + cos(a) * d, float(src.z) + sin(a) * d, day)
	if _bur and _bur.fruit_season(day) and not burs.is_empty():
		for b in birds:
			if _rng.randf() < 0.05:
				var src: Dictionary = burs[_rng.randi() % burs.size()]
				var a := _rng.randf() * TAU
				var d := _rng.randf_range(20.0, 300.0)
				_bur.drop_seed(float(src.x) + cos(a) * d, float(src.z) + sin(a) * d)
	if cipo_season(day) and not vines.is_empty():
		for b in birds:
			if _rng.randf() < 0.08:
				var src: Dictionary = vines[_rng.randi() % vines.size()]
				var a := _rng.randf() * TAU
				var d := _rng.randf_range(20.0, 300.0)
				_cip.drop_seed(float(src.x) + cos(a) * d, float(src.z) + sin(a) * d, day)
	# no chão comem as sementes de andiroba caídas (mais arara, menos semente sobra)
	var cup = _jogo._cupins
	if cup and not birds.is_empty():
		var chance := 0.06 * clampf(birds.size() / 15.0, 0.2, 2.0)
		for a in cup.andirobas:
			if int(a.sem) > 1 and _rng.randf() < chance:
				a.sem = int(a.sem) - 1
	# formam casais (para a vida toda)
	var single_f := []
	var single_m := []
	for b in birds:
		if int(b.par) < 0 and day - int(b.nasc) >= ADULT_DAYS:
			(single_f if b.sexo == "f" else single_m).append(b)
	if not single_f.is_empty() and not single_m.is_empty() and _rng.randf() < 0.02:
		var f: Dictionary = single_f[0]
		var m: Dictionary = single_m[0]
		f.par = int(m.id)
		m.par = int(f.id)
	_nest_day(day)


func _nest_day(day: int) -> void:
	# casais procuram oco e botam
	if breeding_season(day) and _month(day) <= 11 and _month(day) >= 8 and fome == 0 and _rng.randf() > _aperto:
		for f in birds:
			if f.sexo != "f" or int(f.par) < 0 or _nest_of(int(f.id)) != null:
				continue
			if _rng.randf() > 0.025:
				continue
			var spot := _find_cavity()
			if spot.is_empty():
				continue
			var r := _rng.randf()
			var eggs := 1 if r < 0.15 else (2 if r < 0.6 else 3)
			spot.merge({"f": int(f.id), "m": int(f.par), "ovos": eggs, "posto": day, "eclode": day + INCUB_DAYS,
				"filhotes": 0, "voa": -1})
			nests.append(spot)
			var hk := [spot.x, spot.z, spot.tipo, spot.h, spot.ang]
			if not holes.has(hk):
				holes.append(hk)
	var keep := []
	for n in nests:
		var host = _host(n)
		if host == null:
			continue                 # a árvore caiu: perdeu o ninho
		if _bird(int(n.f)) == null:
			continue                 # a mãe morreu
		if int(n.voa) < 0 and day >= int(n.eclode):
			var ok := 0
			for k in int(n.ovos):
				if _rng.randf() < 0.8:
					ok += 1
			if ok == 0:
				continue
			n.filhotes = ok
			n.ovos = 0
			n.voa = day + NEST_DAYS
		if int(n.filhotes) > 0 and fome > 5 and _rng.randf() < 0.05:
			n.filhotes = int(n.filhotes) - 1
		if int(n.voa) >= 0 and int(n.filhotes) <= 0:
			continue
		if int(n.voa) >= 0 and day >= int(n.voa):
			# os filhotes voam e entram no bando
			for k in int(n.filhotes):
				_new_bird(int(n.eclode), "f" if _rng.randf() < 0.5 else "m")
			continue
		keep.append(n)
	nests = keep


func _nest_of(fid: int):
	for n in nests:
		if int(n.f) == fid or int(n.m) == fid:
			return n
	return null


## Oco bom: perto do topo de um buriti seco (só nele), perto de comida e longe de
## outro ninho.
func _find_cavity() -> Dictionary:
	var food := _food_points()
	var cands := []
	# só no buriti seco (tronco morto de pé), como a arara-canindé de verdade
	if _bur:
		for p in _bur.snags():
			cands.append({"x": float(p.x), "z": float(p.z), "tipo": "bur", "h": _bur.trunk_h(p) - _rng.randf_range(0.5, 1.2)})
	cands.shuffle()
	for c in cands:
		var near := false
		for f in food:
			if Vector2(c.x, c.z).distance_to(f) < 250.0:
				near = true
				break
		if not near and not food.is_empty():
			continue
		var crowded := false
		for n in nests:
			if Vector2(float(n.x), float(n.z)).distance_to(Vector2(c.x, c.z)) < 40.0:
				crowded = true
		if crowded:
			continue
		c.ang = _rng.randf() * TAU
		return c
	return {}


func _host(n):
	if str(n.tipo) == "bur":
		if _bur == null:
			return null
		for p in _bur.palms:
			if absf(float(p.x) - float(n.x)) < 0.05 and absf(float(p.z) - float(n.z)) < 0.05 and not p.has("toco"):
				return p
		return null
	if str(n.tipo) == "bac":
		for p in _bac.palms:
			if absf(float(p.x) - float(n.x)) < 0.05 and absf(float(p.z) - float(n.z)) < 0.05:
				return p
		return null
	return _tree_at(Vector2(float(n.x), float(n.z)))


func _tree_at(v: Vector2):
	for p in _arv.plants:
		if absf(float(p[0]) - v.x) < 0.05 and absf(float(p[1]) - v.y) < 0.05 and int(p[5]) != 2:
			return p
	return null


# ================== PLANO DO DIA (onde cada um está a cada hora) ==================

## Unidades que voam juntas: cada casal é uma unidade; jovens e solteiros, sozinhos.
func _make_plans() -> void:
	_units.clear()
	_plans.clear()
	var done := {}
	for b in birds:
		if done.has(int(b.id)):
			continue
		var ids := [int(b.id)]
		done[int(b.id)] = true
		if int(b.par) >= 0 and _bird(int(b.par)) != null:
			ids.append(int(b.par))
			done[int(b.par)] = true
		_units.append({"ids": ids, "key": int(ids[0])})
	var rng := RandomNumberGenerator.new()
	rng.seed = last_day * 7919 + 17
	var site := _feeding_site(rng)
	var roost_p: Array = _perch_tree(roost, rng) if roost.x >= 0 else []
	if roost_p.is_empty():
		for k in 4:
			roost_p.append(_site_perch(site, rng))
	for u in _units:
		var key: int = u.key
		var nest = null
		for id in u.ids:
			if nest == null:
				nest = _nest_of(int(id))
		var stops := []        # [hora de chegada, {pos, nest?}]
		if nest != null:
			var npos := _nest_perch(nest, false)
			var hole := _nest_perch(nest, true)
			stops.append([0.0, npos])
			for h in [6.4, 9.6, 12.8, 16.0]:
				var food := _site_perch(site, rng)
				stops.append([h + rng.randf_range(-0.3, 0.3), food])
				stops.append([h + rng.randf_range(1.0, 1.6), npos])
			u.nest = nest
			u.hole = hole
		else:
			stops.append([0.0, roost_p[rng.randi() % roost_p.size()]])
			var t := 6.0 + rng.randf_range(0.0, 0.5)
			while t < 17.3:
				var chao := _ground_spot(rng) if rng.randf() < 0.35 else {}
				stops.append([t, chao if not chao.is_empty() else _site_perch(site, rng)])
				t += rng.randf_range(0.8, 2.2)
			stops.append([17.5 + rng.randf_range(0.0, 0.6), roost_p[rng.randi() % roost_p.size()]])
		_plans[key] = stops


func _feeding_site(rng: RandomNumberGenerator) -> Array:
	# onde tem fruto agora: bacaba madura, cipó com fruto; senão qualquer bacaba ou cipó adulto
	var trees := []
	if _bac.ripe_season(last_day):
		for p in _bac.adult_palms():
			trees.append({"bac": p})
	if _bur and _bur.fruit_season(last_day):
		for p in _bur_adults():
			trees.append({"bur": p})
	if trees.is_empty() and cipo_season(last_day):
		for pl in _cip.adult_plants():
			var host = _cip._host_of(pl)
			if host != null:
				trees.append({"arv": host})
	if trees.is_empty():
		for p in _bac.adult_palms():
			trees.append({"bac": p})
		for p in _bur_adults():
			trees.append({"bur": p})
	if trees.is_empty():
		for p in _arv.plants:
			if int(p[5]) == 0 and _arv.height_of(p, last_day) > 10.0:
				trees.append({"arv": p})
	if trees.is_empty():
		return []
	# uma moita: a planta sorteada e as que comem perto dela
	var c: Dictionary = trees[rng.randi() % trees.size()]
	var cp := _tree_xz(c)
	var site := []
	for t in trees:
		if _tree_xz(t).distance_to(cp) < 60.0:
			site.append(t)
	return site


static func _tree_xz(t: Dictionary) -> Vector2:
	if t.has("bac"):
		return Vector2(float(t.bac.x), float(t.bac.z))
	if t.has("bur"):
		return Vector2(float(t.bur.x), float(t.bur.z))
	return Vector2(float(t.arv[0]), float(t.arv[1]))


## Um lugar no alto da copa para pousar.
func _crown_spot(t: Dictionary, rng: RandomNumberGenerator) -> Vector3:
	var xz := _tree_xz(t)
	var gy: float = _jogo.height_at(xz.x, xz.y)
	var a := rng.randf() * TAU
	if t.has("bac"):
		var th: float = _bac.trunk_h(t.bac)
		var r := rng.randf_range(0.5, 1.6)
		return Vector3(xz.x + cos(a) * r, gy + th + 0.7 + r * 0.25, xz.y + sin(a) * r)
	if t.has("bur"):
		# pousada no cacho de frutos, embaixo da copa (como a arara comendo buriti)
		var bp: Dictionary = t.bur
		var top: float = gy + float(_bur.trunk_h(bp)) - 0.1
		var rot := float(bp.get("rot", 0.0))
		var nf := 2 + int(absf(sin(float(bp.x) * 2.3 + float(bp.z) * 5.1)) * 2.99)
		var k := rng.randi() % nf
		var ca := rot + k * TAU / nf + 0.4
		var b := Basis(Vector3.UP, ca)
		var cacho := Vector3(xz.x, top, xz.y) + b * Vector3(0.45, -0.25, 0)
		if _bur.fruit_season(last_day) and rng.randf() < 0.8:
			return cacho + b * Vector3(0.12, 0.05, 0)
		var rr := rng.randf_range(0.8, 2.0)
		return Vector3(xz.x + cos(a) * rr, top + 0.5 + rr * 0.2, xz.y + sin(a) * rr)
	var h: float = _arv.height_of(t.arv, last_day)
	var r := rng.randf_range(0.0, h * 0.13)
	return Vector3(xz.x + cos(a) * r, gy + h * 0.94 - r * 0.4, xz.y + sin(a) * r)


## Comer no chão: as sementes de andiroba caídas (janeiro a junho) e as frutinhas no pé
## do cipó (mais de dezembro a fevereiro). {} se não tem nada no chão agora.
func _ground_spot(rng: RandomNumberGenerator) -> Dictionary:
	var opts := []
	var cup = _jogo._cupins
	if cup:
		for i in cup.andirobas.size():
			var a: Dictionary = cup.andirobas[i]
			if int(a.sem) > 0:
				opts.append({"x": float(a.x), "z": float(a.z), "r": 3.0})
	if cipo_season(last_day) or rng.randf() < 0.25:
		for pl in _cip.adult_plants():
			opts.append({"x": float(pl.x), "z": float(pl.z), "r": 2.0})
	if opts.is_empty():
		return {}
	var o: Dictionary = opts[rng.randi() % opts.size()]
	var a2 := rng.randf() * TAU
	var r := rng.randf_range(0.8, float(o.r))
	var x := float(o.x) + cos(a2) * r
	var z := float(o.z) + sin(a2) * r
	return {"pos": Vector3(x, _jogo.height_at(x, z) + 0.01, z), "chao": true, "yaw": rng.randf() * TAU}


func _site_perch(site: Array, rng: RandomNumberGenerator) -> Dictionary:
	if site.is_empty():
		return {"pos": Vector3(320, 40, 240)}
	return {"pos": _crown_spot(site[rng.randi() % site.size()], rng)}


func _perch_tree(v: Vector2, rng: RandomNumberGenerator) -> Array:
	var p = _tree_at(v)
	if p == null:
		return [{"pos": Vector3(v.x, _jogo.height_at(v.x, v.y) + 20.0, v.y)}]
	var out := []
	for k in 6:
		out.append({"pos": _crown_spot({"arv": p}, rng)})
	return out


## Pouso do lado do oco (ou dentro dele, só a cabeça para fora).
func _nest_perch(n: Dictionary, inside: bool) -> Dictionary:
	var host = _host(n)
	var ang := float(n.ang)
	var h := float(n.h)
	var p: Vector3
	var c: Vector3
	if host == null:
		p = Vector3(float(n.x), _jogo.height_at(float(n.x), float(n.z)) + h, float(n.z))
		c = p
	elif str(n.tipo) == "bac":
		p = _bac.trunk_point(host, h, ang, 0.0 if inside else 0.12)
		c = _bac.trunk_point(host, h, ang, -1.0)
	elif str(n.tipo) == "bur":
		p = _bur.trunk_point(host, h, ang, 0.0 if inside else 0.12)
		c = _bur.trunk_point(host, h, ang, -1.0)
	else:
		p = _arv.trunk_point(host, h, ang, 0.0 if inside else 0.14)
		c = _arv.trunk_point(host, h, ang, -1.0)
	var out := (p - Vector3(c.x, p.y, c.z)).normalized()
	if inside:
		return {"pos": p - out * 0.12 + Vector3.UP * -0.02, "face": out, "nest": true}
	return {"pos": p + Vector3.UP * 0.35 + out.cross(Vector3.UP) * 0.1, "face": out}


## Onde a unidade está agora: {pos, mode, yaw, flying}.
func _unit_state(u: Dictionary, h: float) -> Dictionary:
	var stops: Array = _plans.get(int(u.key), [])
	if stops.is_empty():
		return {}
	var cur: Dictionary = stops[0][1]
	for i in range(1, stops.size()):
		var t0: float = stops[i][0]
		var prev: Dictionary = stops[i - 1][1]
		var nxt: Dictionary = stops[i][1]
		var dist: float = (nxt.pos as Vector3).distance_to(prev.pos)
		var dur := dist / SPEED / REAL_S_PER_HOUR + 0.02
		if h < t0:
			break
		if h < t0 + dur:
			var k := (h - t0) / dur
			var a: Vector3 = prev.pos
			var b: Vector3 = nxt.pos
			var top := maxf(a.y, b.y) + minf(CRUISE, dist * 0.25)
			var p := a.lerp(b, k)
			p.y = lerpf(a.y, b.y, k) + (top - lerpf(a.y, b.y, k)) * sin(k * PI)
			var dir := b - a
			return {"pos": p, "mode": "glide" if k > 0.82 or (k > 0.4 and k < 0.55) else "fly", "yaw": atan2(-dir.x, -dir.z),
				"flying": true, "k": k, "dist": dist}
		cur = nxt
	return {"pos": cur.pos, "mode": "chao" if cur.has("chao") else "perch", "yaw": float(cur.get("yaw", u.get("yaw", 0.0))), "flying": false, "stop": cur}


# ================== NA TELA ==================

func update(delta: float) -> void:
	if _units.is_empty():
		return
	var h: float = _jogo.sim.hour()
	var pp: Vector3 = _jogo._player.global_position
	var seen := {}
	for u in _units:
		var st := _unit_state(u, h)
		if st.is_empty():
			continue
		var ids: Array = u.ids
		var key: int = u.key
		var near: bool = (st.pos as Vector3).distance_to(pp) < VIEW
		_unit_sounds(u, st, pp, delta)
		for j in ids.size():
			var id: int = ids[j]
			var b = _bird(id)
			if b == null:
				continue
			var pos: Vector3 = st.pos
			var mode: String = st.mode
			var yaw: float = st.yaw
			var nest = u.get("nest")
			if nest != null and b.sexo == "f" and int(nest.voa) < 0:
				# chocando: a fêmea fica no oco o tempo todo, só a cabeça aparece
				var hole: Dictionary = u.hole
				pos = hole.pos
				mode = "nest"
				yaw = atan2(-hole.face.x, -hole.face.z)
			elif st.flying:
				# o casal voa lado a lado
				var side := Vector3(cos(yaw), 0, -sin(yaw)) * (0.9 if j == 1 else 0.0)
				pos += side + Vector3(0, sin(h * 40.0 + j) * 0.15, 0)
			elif j == 1:
				pos += Vector3(0.35, 0.0, 0.15)
			if not near:
				continue
			seen[id] = true
			var ag = _agents.get(id)
			if ag == null:
				var n := Modelo.new()
				var age := float(last_day - int(b.nasc))
				var s := clampf(0.8 + age / 600.0, 0.8, 1.0)
				n.scale = Vector3(s, s, s)
				add_child(n)
				ag = {"node": n}
				_agents[id] = ag
			var node: Node3D = ag.node
			node.mode = mode
			node.visible = true
			node.global_position = pos
			node.rotation = Vector3(0, lerp_angle(node.rotation.y, yaw, minf(1.0, delta * 6.0)), 0)
			if mode == "nest":
				node.global_position = pos - Vector3.UP * 0.06     # a cabeça bem na boca do oco
	# filhotes grandes espiando no oco
	for u in _units:
		var nest = u.get("nest")
		if nest == null or int(nest.voa) < 0 or int(nest.filhotes) <= 0:
			continue
		var age := last_day - int(nest.eclode)
		var id := -1000 - int(u.key)
		var hole: Dictionary = u.hole
		if age > 55 and (hole.pos as Vector3).distance_to(pp) < VIEW * 0.5 and fmod(h, 1.0) < 0.45:
			seen[id] = true
			var ag = _agents.get(id)
			if ag == null:
				var n := Modelo.new()
				n.scale = Vector3(0.75, 0.75, 0.75)
				add_child(n)
				ag = {"node": n}
				_agents[id] = ag
			ag.node.mode = "nest"
			ag.node.global_position = (hole.pos as Vector3) - Vector3.UP * 0.07
			ag.node.rotation = Vector3(0, atan2(-hole.face.x, -hole.face.z), 0)
	for id in _agents.keys():
		if not seen.has(id):
			(_agents[id].node as Node3D).queue_free()
			_agents.erase(id)
	# o plano do dia é refeito de hora em hora (árvore que caiu, ninho novo)
	if int(h) != _plan_hour:
		_plan_hour = int(h)
		_check_plans()


func _check_plans() -> void:
	for u in _units:
		var nest = u.get("nest")
		if nest != null and _host(nest) == null:
			_make_plans()
			return


## Sons com motivo: voando gritam (contato do bando); na saída do dormitório, alvoroço;
## pousadas, um resmungo de vez em quando comendo; com o jogador perto, alarme e fogem.
func _unit_sounds(u: Dictionary, st: Dictionary, pp: Vector3, delta: float) -> void:
	var key: int = u.key
	var t := float(_snd.get(key, _rng.randf_range(0.5, 4.0))) - delta
	var pos: Vector3 = st.pos
	var d := pos.distance_to(pp)
	_alarm_cd[key] = maxf(0.0, float(_alarm_cd.get(key, 0.0)) - delta)
	if not st.flying and _assustou(st, pos, pp) and float(_alarm_cd[key]) <= 0.0 and _jogo.sim.hour() > 5.5 and _jogo.sim.hour() < 18.6:
		_alarm_cd[key] = _rng.randf_range(12.0, 20.0)
		Sons.play_at(self, "arara_alarme", pos, 0.0, _rng.randf_range(0.95, 1.06), 320.0, 22.0)
		_flee(u, pos)
		_snd[key] = _rng.randf_range(2.0, 4.0)
		return
	if t <= 0.0 and d < 330.0:
		if st.flying:
			Sons.play_at(self, "arara_voo", pos, 0.0, _rng.randf_range(0.92, 1.08), 330.0, 25.0)
			t = _rng.randf_range(2.2, 5.5)
		else:
			var h: float = _jogo.sim.hour()
			if h > 6.0 and h < 17.8 and not (h > 11.0 and h < 14.5):
				if _rng.randf() < 0.35:
					Sons.play_at(self, "arara_resmungo", pos, 0.0, _rng.randf_range(0.92, 1.08), 90.0, 6.0)
			t = _rng.randf_range(25.0, 70.0)
	_snd[key] = t


## Só se assusta com o jogador bem perto (ou fazendo barulho perto): no alto da árvore,
## quem passa embaixo não incomoda; no chão comendo, deixa chegar a uns 5 m. Machado,
## serra ou martelada perto: voa.
func _assustou(st: Dictionary, pos: Vector3, pp: Vector3) -> bool:
	var hd := Vector2(pos.x - pp.x, pos.z - pp.z).length()
	var alto := pos.y - pp.y
	var barulho: bool = bool(_jogo._chopping) or bool(_jogo._sawing) or bool(_jogo.get("_swing_on"))
	var chao := (st.get("stop", {}) as Dictionary).has("chao")
	if chao:
		return hd < 4.5 or (barulho and hd < 14.0)
	if alto > 6.0:
		return barulho and hd < 10.0          # lá no alto: só o barulho perto espanta
	return hd < 4.0 or (barulho and hd < 12.0)


## Assustada: voa para outra árvore longe dali (o ninho ela não larga).
func _flee(u: Dictionary, pos: Vector3) -> void:
	if u.get("nest") != null:
		return
	var stops: Array = _plans.get(int(u.key), [])
	var h: float = _jogo.sim.hour()
	var best = null
	var a := _rng.randf() * TAU
	for p in _arv.plants:
		if int(p[5]) != 0 or _arv.height_of(p, last_day) < 10.0:
			continue
		var d := Vector2(float(p[0]) - pos.x, float(p[1]) - pos.z).length()
		if d > 50.0 and d < 140.0:
			best = p
			if _rng.randf() < 0.3:
				break
	if best == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(h * 1000.0) + int(u.key)
	var spot := {"pos": _crown_spot({"arv": best}, rng)}
	var keep := []
	for s in stops:
		if float(s[0]) <= h:
			keep.append(s)
	keep.append([h, spot])
	for s in stops:
		if float(s[0]) > h + 1.0:
			keep.append(s)
	_plans[int(u.key)] = keep


## O oco aparece no tronco: buraco escuro com a borda gasta.
func _draw_holes() -> void:
	for n in _hole_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_hole_nodes.clear()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var keep := []
	for hk in holes:
		var n := {"x": hk[0], "z": hk[1], "tipo": hk[2], "h": hk[3], "ang": hk[4]}
		var host = _host(n)
		if host == null:
			continue
		keep.append(hk)
		var hole := _nest_perch(n, true)
		var out: Vector3 = hole.face
		var p: Vector3 = (hole.pos as Vector3) + out * 0.12
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var right := out.cross(Vector3.UP).normalized()
		var segs := 18
		var seed_ := float(hash(Vector2(float(n.x), float(n.z)))) * 0.0001
		# boca do oco: oval irregular (lascada), um lábio de madeira gasta em volta,
		# e o túnel entrando no tronco, escurecendo até o fundo
		var mouth := []
		for k in segs + 1:
			var a := float(k) / segs * TAU
			var wob := 1.0 + 0.16 * sin(a * 3.0 + seed_) + 0.08 * sin(a * 7.0 + seed_ * 2.0)
			mouth.append(Vector2(cos(a) * 0.07 * wob, sin(a) * 0.095 * wob))
		# (tudo um pouco para fora da casca: o lábio de madeira gasta fica saliente e o
		# escuro de dentro vai fechando até o preto do fundo)
		var layers := [[1.55, 0.0, Color(0.16, 0.13, 0.10)], [1.15, 0.03, Color(0.30, 0.23, 0.16)],
			[0.95, 0.026, Color(0.10, 0.075, 0.055)], [0.7, 0.016, Color(0.03, 0.022, 0.018)], [0.4, 0.012, Color(0.008, 0.006, 0.005)]]
		for L in layers.size() - 1:
			var A: Array = layers[L]
			var B: Array = layers[L + 1]
			for k in segs:
				var q := []
				for e in [[A, k], [A, k + 1], [B, k + 1], [B, k]]:
					var lay: Array = e[0]
					var m: Vector2 = mouth[e[1]] * float(lay[0])
					q.append(p + right * m.x + Vector3.UP * m.y + out * float(lay[1]))
				var cols := [A[2], A[2], B[2], B[2]]
				for idx in [0, 2, 1, 0, 3, 2]:
					st.set_normal(out)
					st.set_color(cols[idx])
					st.add_vertex(q[idx])
		# fundo
		var back: Array = layers[layers.size() - 1]
		var cb: Vector3 = p + out * float(back[1])
		for k in segs:
			var m0: Vector2 = mouth[k] * float(back[0])
			var m1: Vector2 = mouth[k + 1] * float(back[0])
			for v in [cb, cb + right * m1.x + Vector3.UP * m1.y, cb + right * m0.x + Vector3.UP * m0.y]:
				st.set_normal(out)
				st.set_color(Color(0.008, 0.006, 0.005))
				st.add_vertex(v)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.visibility_range_end = 120.0
		add_child(mi)
		_hole_nodes.append(mi)
	holes = keep


func count() -> int:
	return birds.size()


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "dia": last_day, "aves": birds, "ninhos": nests, "ocos": holes,
			"dormitorio": [roost.x, roost.y], "fome": fome, "prox": _next_id}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	birds = d.get("aves", [])
	nests = d.get("ninhos", [])
	# versão nova: ninho só em buriti seco (os das outras árvores saem)
	nests = nests.filter(func(n): return str(n.get("tipo", "")) == "bur")
	holes = d.get("ocos", [])
	holes = holes.filter(func(hk): return str(hk[2]) == "bur")
	var r = d.get("dormitorio", [-1, -1])
	roost = Vector2(float(r[0]), float(r[1]))
	fome = int(d.get("fome", 0))
	_next_id = int(d.get("prox", 1))
	for b in birds:
		b.id = int(b.id)
		b.par = int(b.par)
		_next_id = maxi(_next_id, int(b.id))
	last_day = mini(int(d.get("dia", last_day)), last_day)
	return true
