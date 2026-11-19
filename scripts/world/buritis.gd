extends Node3D
## Buriti (Mauritia flexuosa): a palmeira dos brejos, das veredas e da beira dos rios.
## Nasce em chão encharcado, em grupos (os buritizais). Tronco alto, reto e cinza, com
## os anéis das folhas que caíram; no alto, folhas enormes em LEQUE: um talo comprido
## e grosso que termina numa "mão" aberta de dezenas de lâminas pregueadas, com as
## pontas caídas. As folhas velhas secam e ficam penduradas, marrons, embaixo da copa.
## Os adultos dão cachos compridos de frutos marrom-avermelhados (cobertos de
## escamas), que amadurecem nas chuvas (dezembro a junho).
##
## Quando morre (velho), a copa cai e o topo do tronco quebra: fica o tronco seco de pé
## por anos, escuro e com a ponta lascada — e é nele que a arara-canindé faz o ninho,
## num oco perto do topo (ver araras.gd).
##
## Planta: {x, z, nasc (dia), hmax (m), var, rot, morta (dia ou -1)}

const MundoSim := preload("res://scripts/mundo_sim.gd")
const TOCO_H := 0.95
const TOCO_DAYS := 1100          # o toco do buriti derrubado apodrece em uns 3 anos
const REACH_H := 2.15            # do chão o braço (com a faca) alcança o talo até essa altura
const START := 230
const MAX_PALMS := 420
const ROSETTE_DAYS := 2190       # 6 anos só com as folhas no chão (sem tronco)
const ADULT_DAYS := 3650         # dá cacho a partir dos 10 anos
const TRUNK_R := 0.2
const CHUNK := 80.0
const VIEW := 260.0
const CROWN_VARIANTS := 3
const BARK_ALB := "res://texturas/bacaba_casca.imagem"
const BARK_NRM := "res://texturas/bacaba_casca_n.imagem"
const BARK_W := 0.9
const BARK_H := 1.2
const OLD_DAYS := 365 * 60       # depois disso pode morrer de velho
const SNAG_DAYS := 365 * 12      # o tronco seco fica de pé uns 12 anos e cai

var palms: Array = []
var last_day := 0
var _jogo: Node
var _arv: Node
var _rng := RandomNumberGenerator.new()
var _crowns: Array = []
var _crown_params: Array = []     # por variante: as folhas [{az, elev, pet, R, col, seed, seca}]
var _leaf_meshes := {}            # (variante, folha) -> malha da folha sozinha (para cair)
var _cacho_mesh: ArrayMesh
var _leaf_mat: StandardMaterial3D
var _trunk_mat: StandardMaterial3D
var _dead_mat: StandardMaterial3D
var _nodes: Array = []
var secas: Array = []             # folhas secas caídas no chão: [x, z, variante, folha, giro, escala, dia]
var _seca_nodes: Array = []
var drop_hook := Callable()       # o jogo mostra a folha seca caindo (perto do jogador)
const SECA_CHANCE := 1.0 / 80.0   # cada buriti solta uma folha seca a cada uns 80 dias
const SECA_DAYS := 150            # a folha seca no chão apodrece em uns 5 meses
const SECA_MAX := 700
var _grid := {}
var _last_month := -1


func build(jogo: Node, arvores: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 7717
	last_day = int(jogo.sim.elapsed_days())
	_make_assets(seed_)
	_arv.extra_barks["buriti"] = _trunk_mat
	_arv.extra_barks["buriti_seco"] = _dead_mat
	if save_path == "" or not _load(save_path):
		_generate()
	palms = palms.filter(func(p): return not _arv._in_sea(float(p.x), float(p.z)))
	_rebuild()


func count() -> int:
	return palms.size()


# ================== ONDE NASCE ==================

## Quão bom para buriti: chão encharcado ou perto de rio/lagoa. 0 = não serve.
func _wet_score(x: float, z: float) -> float:
	var sim = _jogo.sim
	var cell: float = _jogo.CELL
	if _arv._in_sea(x, z):
		return 0.0
	if x < 6.0 or z < 6.0 or x > MundoSim.W * cell - 6.0 or z > MundoSim.H * cell - 6.0:
		return 0.0
	var cx := int(x / cell)
	var cz := int(z / cell)
	var ci := cz * MundoSim.W + cx
	if float(sim.wat[ci]) > 0.15 or float(sim.bed[ci]) > 0.3:
		return 0.0                    # dentro do rio ou da lagoa funda não
	if float(sim.ter[ci]) < sim.SEA + 0.4:
		return 0.0                    # praia
	var gw := float(sim.ground_water(Vector2i(cx, cz)))
	# água perto (rio, lagoa, brejo) num raio de umas 2 células
	var near := 0.0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var k := clampi(cz + dz, 0, MundoSim.H - 1) * MundoSim.W + clampi(cx + dx, 0, MundoSim.W - 1)
			if float(sim.wat[k]) > 0.03 or float(sim.bed[k]) > 0.3:
				near = maxf(near, 1.0 - Vector2(dx, dz).length() / 3.2)
	return clampf(maxf(gw, near), 0.0, 1.0)


func _spot_ok(x: float, z: float) -> bool:
	if _wet_score(x, z) < 0.45:
		return false
	for p in palms:
		if Vector2(float(p.x) - x, float(p.z) - z).length() < 3.2:
			return false
	for t in _arv.plants:
		if int(t[5]) == 2:
			continue
		if Vector2(float(t[0]) - x, float(t[1]) - z).length() < 1.8 + _arv.height_of(t, last_day) * 0.05:
			return false
	return true


func _new_palm(x: float, z: float, born: int) -> Dictionary:
	return {"x": x, "z": z, "nasc": born, "hmax": _rng.randf_range(15.0, 26.0), "var": _rng.randi() % CROWN_VARIANTS,
		"rot": _rng.randf() * TAU, "morta": -1}


## Buritizais: grupos em volta de lugares encharcados.
func _generate() -> void:
	var W: float = MundoSim.W * _jogo.CELL
	var H: float = MundoSim.H * _jogo.CELL
	var tries := 0
	while palms.size() < START and tries < 3000:
		tries += 1
		var cx := _rng.randf_range(10.0, W - 10.0)
		var cz := _rng.randf_range(10.0, H - 10.0)
		if _wet_score(cx, cz) < 0.6:
			continue
		var n := _rng.randi_range(5, 18)
		for k in n * 3:
			if n <= 0 or palms.size() >= START:
				break
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * 16.0
			var x := cx + cos(a) * r
			var z := cz + sin(a) * r
			if not _spot_ok(x, z):
				continue
			var age: int
			var q := _rng.randf()
			if q < 0.25:
				age = _rng.randi_range(60, ROSETTE_DAYS)
			elif q < 0.4:
				age = _rng.randi_range(ROSETTE_DAYS, ADULT_DAYS)
			else:
				age = _rng.randi_range(ADULT_DAYS, 365 * 80)
			var np := _new_palm(x, z, last_day - age)
			# em todo buritizal tem algum tronco seco de pé (onde as araras fazem ninho)
			if age > ADULT_DAYS * 2 and _rng.randf() < 0.12:
				np.morta = last_day - _rng.randi_range(60, SNAG_DAYS - 400)
				if int(np.morta) == -1:
					np.morta = -2
			palms.append(np)
			n -= 1


# ================== CRESCER ==================

func trunk_h(p: Dictionary, day := -1) -> float:
	if p.has("toco"):
		return TOCO_H
	if dead(p):
		return _alive_h(p, int(p.morta)) * 0.86       # morto: o topo quebrou
	return _alive_h(p, last_day if day < 0 else day)


func _alive_h(p: Dictionary, day: int) -> float:
	var d := day - int(p.nasc)
	if d < ROSETTE_DAYS:
		return 0.0
	# uns 40 cm por ano até a altura dela
	return minf(float(p.hmax), (d - ROSETTE_DAYS) / 365.0 * 0.4)


func crown_scale(p: Dictionary) -> float:
	var d := last_day - int(p.nasc)
	return clampf(0.25 + d / float(ADULT_DAYS) * 0.75, 0.25, 1.0)


func is_adult(p: Dictionary) -> bool:
	return last_day - int(p.nasc) >= ADULT_DAYS and not dead(p) and not p.has("toco")


static func month_of(day: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(MundoSim.start_unix() + day * 86400)
	return int(d.month)


func dead(p: Dictionary) -> bool:
	return int(p.get("morta", -1)) != -1           # (o dia pode ser negativo: morreu antes do começo)


## Ponto na casca do tronco na altura y (para o oco do ninho e o pouso das araras).
func trunk_point(p: Dictionary, y: float, ang: float, out := 0.0) -> Vector3:
	var x := float(p.x)
	var z := float(p.z)
	var r := TRUNK_R * 0.95 + out
	return Vector3(x + cos(ang) * r, _jogo.height_at(x, z) + y, z + sin(ang) * r)


## ================== SUBIR, CORTAR FOLHAS E DERRUBAR ==================

func trunk_r(p: Dictionary) -> float:
	if p.has("toco"):
		return float(p.get("toco_r", TRUNK_R))
	return TRUNK_R * lerpf(0.7, 1.0, clampf(trunk_h(p) / 8.0, 0.0, 1.0))


## O buriti mais perto (de pé, ou broto com folhas).
func palm_near(pos: Vector3, reach: float) -> Dictionary:
	var best := {}
	var bd := reach
	for p in palms:
		if p.has("toco"):
			continue
		var d := Vector2(float(p.x) - pos.x, float(p.z) - pos.z).length()
		if d < bd:
			bd = d
			best = p
	return best


## Folhas que dá para cortar estando no chão (buriti pequeno).
func reach_leaves(p: Dictionary) -> Array:
	var gy: float = _jogo.height_at(float(p.x), float(p.z))
	return leaves_of(p).filter(func(lf): return float(lf.cut.y) - gy < REACH_H)


## Pequeno: alguma folha verde está ao alcance do chão (não precisa subir).
func is_small(p: Dictionary) -> bool:
	return not reach_leaves(p).is_empty()


func can_fell(p: Dictionary) -> bool:
	return not p.has("toco") and trunk_h(p) >= 0.8


## Machadas para derrubar (o buriti é fibroso e mole por dentro: vai rápido).
func hits_to_fell(p: Dictionary) -> int:
	return clampi(int(round(4.0 + trunk_r(p) * 30.0)), 5, 11)


func add_hit(p: Dictionary, side: float) -> int:
	if int(p.get("golpes", 0)) == 0:
		p["lado_corte"] = side
	p["golpes"] = int(p.get("golpes", 0)) + 1
	_rebuild()
	return int(p.golpes)


## Derruba: o buriti vira toco. Devolve como ele era (para a queda e a tora no chão).
func fell(p: Dictionary) -> Dictionary:
	var info := {"x": float(p.x), "z": float(p.z), "h": trunk_h(p), "r": trunk_r(p), "rot": float(p.get("rot", 0.0)),
		"v": int(p.get("var", 0)) % CROWN_VARIANTS, "s": crown_scale(p), "morta": dead(p),
		"folhas": leaves_of(p).map(func(lf): return int(lf.li)), "cortadas": (p.get("cortadas", []) as Array).duplicate(),
		"gy": float(_jogo.height_at(float(p.x), float(p.z)))}
	p["toco_r"] = info.r
	p["toco"] = last_day
	for k in ["golpes", "cortadas", "corte_dia", "lado_corte"]:
		p.erase(k)
	_rebuild()
	return info


## Folhas verdes que dá para cortar: [{li, cut (ponto no talo), base}]
func leaves_of(p: Dictionary) -> Array:
	if dead(p) or p.has("toco"):
		return []
	var v := int(p.get("var", 0)) % CROWN_VARIANTS
	var prm: Array = _crown_params[v]
	var xf := crown_xf(p)
	var cut: Array = p.get("cortadas", [])
	var out := []
	for i in prm.size():
		var lp: Dictionary = prm[i]
		if bool(lp.seca) or cut.has(i) or cut.has(float(i)):
			continue
		var az := float(lp.az)
		var o := Vector3(cos(az), 0, sin(az))
		var el := float(lp.elev)
		var dir := (o * cos(el) + Vector3.UP * sin(el)).normalized()
		var base := o * 0.12
		out.append({"li": i, "cut": xf * (base + dir * 0.7), "base": xf * base})
	return out


func crown_xf(p: Dictionary) -> Transform3D:
	var gy: float = _jogo.height_at(float(p.x), float(p.z))
	var s := crown_scale(p)
	return Transform3D(Basis(Vector3.UP, float(p.get("rot", 0.0))).scaled(Vector3(s, s, s)), Vector3(float(p.x), gy + trunk_h(p) - 0.1, float(p.z)))


## Como a folha fica deitada no chão: o talo na horizontal, a mão aberta deitada.
func leaf_lying_basis(v: int, li: int, yaw: float) -> Basis:
	var lp: Dictionary = _crown_params[v][li]
	var az := float(lp.az)
	var el := float(lp.elev)
	var tan := Vector3(-sin(az), 0, cos(az))
	# tira a subida do talo (gira no eixo de lado) e depois gira no chão
	return Basis(Vector3.UP, yaw) * Basis(tan, el) * Basis(Vector3.UP, 0.0)


func cut_leaf(p: Dictionary, li: int) -> void:
	if not p.has("cortadas"):
		p["cortadas"] = []
	p.cortadas.append(li)
	p["corte_dia"] = last_day
	_rebuild()


## ================== FOLHAS SECAS QUE CAEM SOZINHAS ==================

## Índices das folhas secas (a "saia") da copa desse buriti.
func dry_leaves_of(p: Dictionary) -> Array:
	var v := int(p.get("var", 0)) % CROWN_VARIANTS
	var out := []
	for i in (_crown_params[v] as Array).size():
		if bool(_crown_params[v][i].seca):
			out.append(i)
	return out


## Onde a folha seca deita: para fora do tronco, do lado em que ela pendia.
func seca_land(p: Dictionary, li: int) -> Vector3:
	var v := int(p.get("var", 0)) % CROWN_VARIANTS
	var az := float(_crown_params[v][li].az) + float(p.get("rot", 0.0))
	var r := _rng.randf_range(0.6, 1.8) * maxf(crown_scale(p), 0.4)
	var x := float(p.x) + cos(-az) * r
	var z := float(p.z) + sin(-az) * r
	return Vector3(x, _jogo.height_at(x, z), z)


func add_seca(p: Dictionary, li: int, land: Vector3, yaw: float) -> void:
	secas.append([land.x, land.z, int(p.get("var", 0)) % CROWN_VARIANTS, li, yaw, crown_scale(p), last_day])
	while secas.size() > SECA_MAX:
		secas.pop_front()
	_rebuild_secas()


## O meio da folha deitada (o talo começa no ponto da folha; a mão abre lá na frente).
func _seca_mid(e: Array) -> Vector2:
	var v := int(e[2])
	var li := int(e[3])
	var lp: Dictionary = _crown_params[v][li]
	var az := float(lp.az)
	var o := Vector3(cos(az), 0, sin(az))
	var el := float(lp.elev)
	var dir := (o * cos(el) + Vector3.UP * sin(el)).normalized()
	var m: Vector3 = leaf_lying_basis(v, li, float(e[4])) * (dir * (float(lp.pet) + float(lp.R) * 0.4) * float(e[5]))
	return Vector2(float(e[0]) + m.x, float(e[1]) + m.z)


func seca_near(pos: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach
	for i in secas.size():
		var a := Vector2(float(secas[i][0]), float(secas[i][1]))
		var b := _seca_mid(secas[i])
		var q := Vector2(pos.x, pos.z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := q.distance_to(a + ab * t)          # perto de qualquer ponto do talo à mão
		if d < bd:
			bd = d
			best = i
	return best


func take_seca(i: int) -> void:
	secas.remove_at(i)
	_rebuild_secas()


func _rebuild_secas() -> void:
	for n in _seca_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_seca_nodes.clear()
	var groups := {}
	for e in secas:
		var v := int(e[2])
		var li := int(e[3])
		var k := v * 100 + li
		if not groups.has(k):
			groups[k] = []
		var s := float(e[5])
		var x := float(e[0])
		var z := float(e[1])
		var b: Basis = leaf_lying_basis(v, li, float(e[4])).scaled(Vector3(s, s, s))
		groups[k].append(Transform3D(b, Vector3(x, _jogo.height_at(x, z) + 0.04, z)))
	for k in groups:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = leaf_mesh(int(k) / 100, int(k) % 100)
		mm.instance_count = (groups[k] as Array).size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, groups[k][i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _leaf_mat
		mi.visibility_range_end = 90.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_seca_nodes.append(mi)


## As araras (ou a água) levam o fruto: se cair em chão encharcado, nasce buriti.
func drop_seed(x: float, z: float) -> void:
	if palms.size() < MAX_PALMS and _rng.randf() < 0.25 and _spot_ok(x, z):
		palms.append(_new_palm(x, z, last_day))


## Troncos secos de pé (para as araras): os que ainda têm uns 6 m ou mais.
func snags() -> Array:
	return palms.filter(func(p): return dead(p) and trunk_h(p) > 6.0)


## Frutos maduros nas chuvas (dezembro a junho).
static func fruit_season(day: int) -> bool:
	var m := month_of(day)
	return m >= 12 or m <= 6


func tick() -> void:
	var day := int(_jogo.sim.elapsed_days())
	if day <= last_day:
		return
	var n := 0
	while last_day < day and n < 120:
		last_day += 1
		n += 1
		# morre de velho (raramente antes); o tronco seco cai depois de anos
		var keep := []
		for p in palms:
			if p.has("toco"):
				if last_day - int(p.toco) > TOCO_DAYS:
					continue
			elif dead(p):
				if last_day - int(p.morta) > SNAG_DAYS:
					continue
			else:
				var ag := last_day - int(p.nasc)
				var risk := 1.0 / (365.0 * 400.0) + (1.0 / (365.0 * 25.0) if ag > OLD_DAYS else 0.0)
				if ag > ADULT_DAYS and _rng.randf() < risk:
					p.morta = last_day
			keep.append(p)
		palms = keep
		# as folhas secas da saia caem sozinhas (a última do dia aparece caindo)
		for p in palms:
			if p.has("toco") or dead(p) or _rng.randf() > SECA_CHANCE:
				continue
			var dl := dry_leaves_of(p)
			if dl.is_empty():
				continue
			var li: int = dl[_rng.randi() % dl.size()]
			var land := seca_land(p, li)
			var yaw := _rng.randf() * TAU
			if last_day == day and drop_hook.is_valid() and bool(drop_hook.call(p, li, land, yaw)):
				continue           # o jogo mostra caindo e põe no chão quando ela deitar
			secas.append([land.x, land.z, int(p.get("var", 0)) % CROWN_VARIANTS, li, yaw, crown_scale(p), last_day])
		# a folha seca no chão apodrece
		secas = secas.filter(func(e): return last_day - int(e[6]) < SECA_DAYS)
		while secas.size() > SECA_MAX:
			secas.pop_front()
		# os frutos caem perto (e a água leva): de vez em quando nasce buriti novo
		if palms.size() < MAX_PALMS and _rng.randf() < 0.02 and fruit_season(last_day):
			var adults := palms.filter(func(p): return is_adult(p))
			if not adults.is_empty():
				var mae: Dictionary = adults[_rng.randi() % adults.size()]
				var a := _rng.randf() * TAU
				var r := _rng.randf_range(3.0, 14.0)
				var x := float(mae.x) + cos(a) * r
				var z := float(mae.z) + sin(a) * r
				if _spot_ok(x, z):
					palms.append(_new_palm(x, z, last_day))
	last_day = day
	_rebuild_secas()
	# folha nova brota no lugar das cortadas (uma a cada uns 2 meses)
	for p in palms:
		var cl: Array = p.get("cortadas", [])
		if not cl.is_empty() and day - int(p.get("corte_dia", day)) > 60:
			cl.pop_front()
			p["corte_dia"] = day
	var m := month_of(day)
	if m != _last_month:
		_last_month = m
		_rebuild()               # cresce e muda a época dos frutos


# ================== ESBARRAR ==================

func push_out(p: Vector3) -> Vector3:
	var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for t in _grid.get(k + Vector2i(dx, dz), []):
				var d := Vector2(p.x - t.x, p.z - t.y)
				var l := d.length()
				if l < t.z:
					var n := d / l if l > 0.001 else Vector2(1, 0)
					p.x = t.x + n.x * t.z
					p.z = t.y + n.y * t.z
	return p


# ================== NA TELA ==================

func _rebuild() -> void:
	_rebuild_secas()
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_grid.clear()
	var chunks := {}
	var fruit := fruit_season(last_day)
	for p in palms:
		var x := float(p.x)
		var z := float(p.z)
		var c := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
		if not chunks.has(c):
			chunks[c] = {"tr": [], "dt": [], "cr": {}, "fr": []}
		var ch: Dictionary = chunks[c]
		var gy: float = _jogo.height_at(x, z)
		var h := trunk_h(p)
		var rot := float(p.get("rot", 0.0))
		var r := float(p.get("toco_r", 0.2)) if p.has("toco") else TRUNK_R * lerpf(0.7, 1.0, clampf(h / 8.0, 0.0, 1.0))
		if p.has("toco"):
			ch.tr.append([x, gy, z, h, r, rot])
			_toco_cap(Vector3(x, gy + h + 0.1, z), r * 0.9, last_day - int(p.toco))
			continue
		if int(p.get("golpes", 0)) > 0:
			_notch(p, Vector3(x, gy, z), r)
		if h > 0.05:
			(ch.dt if dead(p) else ch.tr).append([x, gy, z, h, r, rot])
			var gk := Vector2i(floori(x / 8.0), floori(z / 8.0))
			if not _grid.has(gk):
				_grid[gk] = []
			_grid[gk].append(Vector3(x, z, r + 0.28))
		if dead(p):
			continue                 # tronco seco: sem copa
		var s := crown_scale(p)
		var top := Vector3(x, gy + h - 0.1, z)
		var v := int(p.get("var", 0)) % CROWN_VARIANTS
		var cut: Array = p.get("cortadas", [])
		if cut.is_empty():
			if not ch.cr.has(v):
				ch.cr[v] = []
			ch.cr[v].append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), top))
		else:
			# copa com folhas cortadas: malha própria (sem as que caíram)
			var sk := {}
			for li in cut:
				sk[int(li)] = true
			var mi := MeshInstance3D.new()
			mi.mesh = _crown_mesh(_crown_params[v], sk)
			mi.material_override = _leaf_mat
			mi.visibility_range_end = VIEW
			add_child(mi)
			mi.transform = Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), top)
			_nodes.append(mi)
		if fruit and is_adult(p):
			var nf := 2 + int(absf(sin(x * 2.3 + z * 5.1)) * 2.99)
			for k in nf:
				var a := rot + k * TAU / nf + 0.4
				var b := Basis(Vector3.UP, a)
				ch.fr.append(Transform3D(b, top + b * Vector3(0.35, -0.25, 0)))
	for c in chunks:
		var ch: Dictionary = chunks[c]
		for kind in ["tr", "dt"]:
			if (ch[kind] as Array).is_empty():
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = _trunks_mesh(ch[kind], kind == "dt")
			mi.material_override = _trunk_mat if kind == "tr" else _dead_mat
			mi.visibility_range_end = VIEW
			add_child(mi)
			_nodes.append(mi)
		for v in ch.cr:
			_add_mm(_crowns[v], _leaf_mat, ch.cr[v], VIEW, true)
		_add_mm(_cacho_mesh, _leaf_mat, ch.fr, 110.0, false)


## O topo cortado do toco: madeira clara e fibrosa (escurece com os dias).
func _toco_cap(c: Vector3, r: float, age: int) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.03
	cm.radial_segments = 14
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.76, 0.58).lerp(Color(0.4, 0.33, 0.25), clampf(age / 300.0, 0.0, 1.0))
	m.roughness = 1.0
	mi.material_override = m
	add_child(mi)
	mi.position = c - Vector3.UP * 0.1
	_nodes.append(mi)


## O talho do machado no tronco (cresce a cada machadada), do lado de quem corta:
## uma faixa curva colada na casca, madeira clara nas bordas e o fundo escuro no meio.
func _notch(p: Dictionary, base: Vector3, r: float) -> void:
	var f := clampf(float(p.get("golpes", 0)) / float(hits_to_fell(p)), 0.0, 1.0)
	var ang := float(p.get("lado_corte", 0.0))
	var th := 0.35 + 0.75 * f                    # meia abertura (rad) em volta do tronco
	var hh := 0.05 + 0.06 * f
	var rows := [[-hh, Color(0.62, 0.52, 0.36)], [-hh * 0.35, Color(0.8, 0.68, 0.48)], [0.0, Color(0.28, 0.2, 0.12)],
		[hh * 0.35, Color(0.88, 0.77, 0.56)], [hh, Color(0.7, 0.6, 0.42)]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	var cy := base.y + 1.0
	for i in rows.size() - 1:
		for k in n:
			var a0 := ang - th + 2.0 * th * k / n
			var a1 := ang - th + 2.0 * th * (k + 1) / n
			# perto das pontas o talho afina (fecha em ponta)
			var e0 := sin(PI * float(k) / n)
			var e1 := sin(PI * float(k + 1) / n)
			var y0: float = rows[i][0]
			var y1: float = rows[i + 1][0]
			var rr := r * 1.025
			var q := [Vector3(base.x + cos(a0) * rr, cy + y0 * e0, base.z + sin(a0) * rr), Vector3(base.x + cos(a1) * rr, cy + y0 * e1, base.z + sin(a1) * rr),
				Vector3(base.x + cos(a1) * rr, cy + y1 * e1, base.z + sin(a1) * rr), Vector3(base.x + cos(a0) * rr, cy + y1 * e0, base.z + sin(a0) * rr)]
			var cols := [rows[i][1], rows[i][1], rows[i + 1][1], rows[i + 1][1]]
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_color(cols[idx])
				st.add_vertex(q[idx])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)
	_nodes.append(mi)


func _add_mm(mesh: Mesh, mat: Material, xs: Array, view: float, shadow: bool) -> void:
	if xs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if mat:
		mi.material_override = mat
	mi.visibility_range_end = view
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_nodes.append(mi)


# ================== MODELOS ==================

func _make_assets(seed_: int) -> void:
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.vertex_color_use_as_albedo = true
	_leaf_mat.vertex_color_is_srgb = true
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_mat.roughness = 0.7
	_trunk_mat = StandardMaterial3D.new()
	_trunk_mat.albedo_texture = _load_tex(BARK_ALB, Color(0.6, 0.6, 0.58))
	_trunk_mat.albedo_color = Color(0.55, 0.54, 0.51)          # cinza
	_trunk_mat.normal_enabled = true
	_trunk_mat.normal_texture = _load_tex(BARK_NRM, Color(0.5, 0.5, 1.0))
	_trunk_mat.normal_scale = 0.9
	_trunk_mat.roughness = 0.9
	_trunk_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_dead_mat = _trunk_mat.duplicate()
	_dead_mat.albedo_color = Color(0.4, 0.36, 0.31)        # seco: cinza-pardo, mais escuro
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ + 9911
	for v in CROWN_VARIANTS:
		var prm := _crown_params_gen(rng)
		_crown_params.append(prm)
		_crowns.append(_crown_mesh(prm, {}))
	_cacho_mesh = _make_cacho(rng)


static func _load_tex(path: String, fallback: Color) -> Texture2D:
	var img := Image.new()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or img.load_jpg_from_buffer(bytes) != OK:
		img = Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(fallback)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Troncos (retos, grossos, base um pouco mais larga) de um pedaço do mapa.
func _trunks_mesh(list: Array, broken := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 14
	for t in list:
		var x: float = t[0]
		var gy: float = t[1]
		var z: float = t[2]
		var h: float = t[3]
		var r: float = t[4]
		var rot: float = t[5]
		var rows := [[-0.3, 1.35], [0.1, 1.2], [0.6, 1.02], [h * 0.5, 1.0], [h + 0.1, 0.9]]
		var vofs := fmod(rot * 3.7, 1.0)
		var reps := maxf(1.0, roundf(TAU * r / BARK_W))
		for i in rows.size() - 1:
			var y0: float = rows[i][0]
			var y1: float = rows[i + 1][0]
			var r0: float = r * float(rows[i][1])
			var r1: float = r * float(rows[i + 1][1])
			for k in sides:
				var a0 := rot + float(k) / sides * TAU
				var a1 := rot + float(k + 1) / sides * TAU
				var u0 := float(k) / sides * reps
				var u1 := float(k + 1) / sides * reps
				var q := [Vector3(x + cos(a0) * r0, gy + y0, z + sin(a0) * r0), Vector3(x + cos(a1) * r0, gy + y0, z + sin(a1) * r0),
					Vector3(x + cos(a1) * r1, gy + y1, z + sin(a1) * r1), Vector3(x + cos(a0) * r1, gy + y1, z + sin(a0) * r1)]
				var uv := [Vector2(u0, vofs - y0 / BARK_H), Vector2(u1, vofs - y0 / BARK_H), Vector2(u1, vofs - y1 / BARK_H), Vector2(u0, vofs - y1 / BARK_H)]
				var nn := [Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a0), 0, sin(a0))]
				for tri in [[0, 1, 2], [0, 2, 3]]:
					var A: Vector3 = q[tri[0]]
					var B: Vector3 = q[tri[1]]
					var C: Vector3 = q[tri[2]]
					var ord: Array = tri
					if (C - A).cross(B - A).dot(nn[tri[0]]) < 0.0:
						ord = [tri[0], tri[2], tri[1]]
					for idx in ord:
						st.set_normal(nn[idx])
						st.set_uv(uv[idx])
						st.add_vertex(q[idx])
	if broken:
		# o topo quebrado: lascas de fibra em pé, irregulares, em volta da boca do tronco
		for t in list:
			var x2: float = t[0]
			var gy2: float = t[1]
			var z2: float = t[2]
			var top: float = gy2 + float(t[3]) + 0.1
			var r2: float = float(t[4]) * 0.9
			var rng := RandomNumberGenerator.new()
			rng.seed = int(x2 * 13.0 + z2 * 7.0)
			for k in 16:
				var a0 := TAU * k / 16.0
				var a1 := TAU * (k + 1) / 16.0
				var hh := rng.randf_range(0.03, 0.35)
				var p0 := Vector3(x2 + cos(a0) * r2, top, z2 + sin(a0) * r2)
				var p1 := Vector3(x2 + cos(a1) * r2, top, z2 + sin(a1) * r2)
				var pt := Vector3(x2 + cos((a0 + a1) * 0.5) * r2 * 0.92, top + hh, z2 + sin((a0 + a1) * 0.5) * r2 * 0.92)
				var nn := Vector3(cos((a0 + a1) * 0.5), 0.2, sin((a0 + a1) * 0.5)).normalized()
				for v in [p0, p1, pt]:
					st.set_normal(nn)
					st.set_uv(Vector2(0.5, 0.5))
					st.add_vertex(v)
			# a boca escura (o miolo apodrecido, oco)
			for k in 12:
				var a0 := TAU * k / 12.0
				var a1 := TAU * (k + 1) / 12.0
				for v in [Vector3(x2, top - 0.25, z2), Vector3(x2 + cos(a1) * r2 * 0.85, top, z2 + sin(a1) * r2 * 0.85), Vector3(x2 + cos(a0) * r2 * 0.85, top, z2 + sin(a0) * r2 * 0.85)]:
					st.set_normal(Vector3.UP)
					st.set_uv(Vector2(0.02, 0.02))
					st.add_vertex(v)
	st.generate_tangents()
	return st.commit()


## Copa: 12 a 16 folhas em leque. Cada uma: talo comprido (2,5 a 3,5 m) e grosso, a
## "mão" aberta de umas 40 lâminas pregueadas (vinco para cima, vinco para baixo)
## em quase meia volta, de 1,5 a 2 m, com as pontas caindo. As folhas mais velhas
## (as de baixo) caem para fora; as secas ficam penduradas, marrons.
func _crown_params_gen(rng: RandomNumberGenerator) -> Array:
	var out := []
	var n := rng.randi_range(12, 16)
	for i in n:
		var age := float(i % 4) / 3.0                # 0 nova (em pé), 1 velha (caída)
		var green := Color(0.1, 0.2, 0.06).lerp(Color(0.15, 0.26, 0.08), rng.randf())
		out.append({"az": TAU * i / n + rng.randf_range(-0.2, 0.2), "elev": lerpf(1.25, 0.15, age) + rng.randf_range(-0.12, 0.12),
			"pet": rng.randf_range(2.5, 3.5), "R": rng.randf_range(1.5, 2.0), "col": green, "seed": rng.randi(), "seca": false})
	# folhas secas penduradas embaixo da copa (a "saia")
	for i in rng.randi_range(3, 6):
		out.append({"az": rng.randf() * TAU, "elev": -1.25 + rng.randf_range(-0.15, 0.1), "pet": rng.randf_range(1.8, 2.6),
			"R": rng.randf_range(0.9, 1.3), "col": Color(0.3, 0.2, 0.11).darkened(rng.randf() * 0.2), "seed": rng.randi(), "seca": true})
	return out


## A copa com as folhas dos parâmetros (menos as cortadas, em skip).
func _crown_mesh(prm: Array, skip: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in prm.size():
		if skip.has(i):
			continue
		_leaf_into(st, prm[i])
	st.generate_normals()
	return st.commit()


func _leaf_into(st: SurfaceTool, lp: Dictionary) -> void:
	var r2 := RandomNumberGenerator.new()
	r2.seed = int(lp.seed)
	var az := float(lp.az)
	_frond(st, Vector3(cos(az), 0, sin(az)), float(lp.elev), float(lp.pet), float(lp.R), lp.col, r2, bool(lp.seca))


## A folha sozinha (no espaço da copa), para mostrar ela caindo e no chão.
func leaf_mesh(v: int, li: int) -> ArrayMesh:
	var k := v * 100 + li
	if not _leaf_meshes.has(k):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_leaf_into(st, _crown_params[v][li])
		st.generate_normals()
		_leaf_meshes[k] = st.commit()
	return _leaf_meshes[k]


## Uma folha em leque: o talo sai do topo do tronco na direção out, subindo elev
## (rad); na ponta do talo abre a mão de lâminas.
func _frond(st: SurfaceTool, out: Vector3, elev: float, pet_len: float, R: float, col: Color, rng: RandomNumberGenerator, seca := false) -> void:
	var dir := (out * cos(elev) + Vector3.UP * sin(elev)).normalized()
	var p0 := Vector3.ZERO + out * 0.12
	# talo levemente curvo (cai um pouco na ponta)
	var segs := 6
	var prev := p0
	var pet_col := col.darkened(0.15)
	for k in segs:
		var t := float(k + 1) / segs
		var p := p0 + dir * pet_len * t + Vector3.DOWN * (0.25 * t * t * pet_len / 3.0) * (0.0 if seca else 1.0)
		_tube(st, prev, p, lerpf(0.045, 0.025, t), pet_col)
		prev = p
	var H := prev                                   # onde abre o leque
	var tip_dir := (H - (p0 + dir * pet_len * 0.8)).normalized()
	# plano do leque: continua o talo (costapalmado) e abre para os lados
	var side := tip_dir.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var fan_up := side.cross(tip_dir).normalized()
	var nseg := 38 if not seca else 22
	var spread := deg_to_rad(100.0) if not seca else deg_to_rad(35.0)   # a seca fica fechada
	for s in nseg:
		var th := lerpf(-spread, spread, (s + 0.5) / nseg)
		var d := (tip_dir * cos(th) + side * sin(th)).normalized()
		var w := 0.085 * R
		var pleat := 0.035 if s % 2 == 0 else -0.035
		var pts := 5
		var prev_l := H + d * 0.12 - side.cross(d).normalized() * 0.0
		var nrm := d.cross(fan_up).normalized()
		var leaf_col := col.lightened(0.08 * float(s % 2)).darkened(rng.randf() * 0.08)
		for k in pts:
			var t := float(k + 1) / pts
			var L := R * (0.95 + 0.1 * sin(s * 2.3))
			# a lâmina sai do leque e a ponta (o último terço) cai e se divide
			var droop := pow(maxf(0.0, t - 0.55) / 0.45, 1.6) * 0.45 * L
			if seca:
				droop = t * 0.3 * L
			var cpos := H + d * (0.12 + L * t) + fan_up * pleat * (1.0 - t) + Vector3.DOWN * droop
			var hw := w * (1.0 - t * 0.85)
			var a1 := prev_l
			var b1 := cpos
			for v in [a1 - nrm * hw, b1 - nrm * hw * 0.85, b1 + nrm * hw * 0.85, a1 - nrm * hw, b1 + nrm * hw * 0.85, a1 + nrm * hw]:
				st.set_color(leaf_col)
				st.add_vertex(v)
			# o vinco (meia lâmina dobrada para cima): dá o relevo pregueado
			for v in [a1, b1, b1 + fan_up * pleat * 0.6]:
				st.set_color(leaf_col.darkened(0.12))
				st.add_vertex(v)
			prev_l = cpos


## Cacho de buriti: um eixo comprido pendurado com dezenas de frutos ovais
## marrom-avermelhados (escamosos).
func _make_cacho(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3.ZERO
	var bot := Vector3(0.25, -1.6, 0.0)
	_tube(st, top, bot, 0.03, Color(0.36, 0.3, 0.18))
	for k in 46:
		var t := rng.randf_range(0.25, 1.0)
		var a := rng.randf() * TAU
		var c := top.lerp(bot, t) + Vector3(cos(a), rng.randf_range(-0.05, 0.05), sin(a)) * rng.randf_range(0.06, 0.18)
		var col := Color(0.42, 0.16, 0.08).lerp(Color(0.3, 0.12, 0.06), rng.randf())
		_fruit(st, c, 0.035, col)
	st.generate_normals()
	return st.commit()


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := (b - a).normalized()
	var s1 := d.cross(Vector3.UP)
	if s1.length() < 0.1:
		s1 = d.cross(Vector3.RIGHT)
	s1 = s1.normalized()
	var s2 := d.cross(s1).normalized()
	var n := 6
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var o0 := (s1 * cos(a0) + s2 * sin(a0)) * r
		var o1 := (s1 * cos(a1) + s2 * sin(a1)) * r
		for v in [a + o0, b + o0, b + o1, a + o0, b + o1, a + o1]:
			st.set_color(col)
			st.add_vertex(v)


static func _fruit(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	for i in 4:
		for j in 6:
			var q := []
			for dd in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var th := PI * float(i + dd[0]) / 4.0
				var ph := TAU * float(j + dd[1]) / 6.0
				q.append(c + Vector3(sin(th) * cos(ph), cos(th) * 1.25, sin(th) * sin(ph)) * r)
			var cc := col.darkened(0.12 * float((i + j) % 2))     # as escamas
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(cc)
				st.add_vertex(q[k])


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "dia": last_day, "palmeiras": palms, "secas": secas}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	palms = d.get("palmeiras", [])
	secas = d.get("secas", [])
	for p in palms:
		for k in ["degraus", "lado"]:
			(p as Dictionary).erase(k)
	last_day = mini(int(d.get("dia", last_day)), last_day)
	return true
