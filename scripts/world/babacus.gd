extends Node3D
## Babaçu (Attalea speciosa): a palmeira da terra firme e das capoeiras.
##
## - Pindova: a planta nova fica uns 10 anos só com as folhas saindo do chão (sem tronco),
##   folhas compridas (penadas) quase em pé, abrindo em leque.
## - Adulta: tronco reto e grosso (de 6 até uns 16 m), a copa de folhas penadas grandes
##   erguidas e arqueadas; floresce de janeiro a abril e os cachos de coco crescem verdes
##   (junho a setembro) e amadurecem marrons (outubro a dezembro); os cocos maduros caem
##   de outubro a março e ficam no chão.
## - As folhas verdes são cortadas da pindova com o machado (cada uma leva duas
##   machadadas): caem inteiras no chão e dão para pegar (forrar o chão, cobrir). A pindova
##   fica com uma folha a menos e solta outra nova com o tempo.

const MundoSim := preload("res://scripts/mundo_sim.gd")
const START_PALMS := 240
const MAX_PALMS := 420
const PINDOVA_DAYS := 365 * 10     # uns 10 anos sem tronco
const ADULT_DAYS := 365 * 11       # dá cacho a partir dos 11 anos
const TRUNK_R := 0.22
const VIEW := 240.0
const CHAO_VIEW := 70.0
const VARIANTS := 3
const SECA_CHANCE := 1.0 / 70.0    # cada adulta solta uma folha seca a cada uns 70 dias
const SECA_PIND := 1.0 / 150.0     # a pindova bem menos
const SECA_DAYS := 220             # a folha seca no chão apodrece em uns 7 meses
const SECA_MAX := 600
const COCO_DAYS := 300             # o coco no chão dura uns 10 meses
const COCO_MAX := 900

var palms: Array = []              # {x, z, nasc, hmax, vig, var, rot}
var secas: Array = []              # folhas verdes cortadas no chão: [x, z, giro, escala, dia]
var cocos: Array = []              # cocos no chão: [x, z, giro, dia]
var last_day := 0
var _jogo: Node
var _arv: Node
var _rng := RandomNumberGenerator.new()
var _crowns: Array = []            # copas das adultas (variantes)
var _pindovas: Array = []          # pindovas: [variante][quantas folhas] -> malha
const PIND_FOLHAS := [6, 7, 8]     # folhas de uma pindova inteira (por variante)
const FOLHA_DIAS := 45             # a pindova solta uma folha nova a cada mês e meio
const VERDE_DIAS := 60             # a folha cortada no chão seca e some em uns 2 meses
var _seca_mesh: ArrayMesh
var _trunk_mesh: ArrayMesh
var _cacho_verde: ArrayMesh
var _cacho_maduro: ArrayMesh
var _coco_mesh: ArrayMesh
var _mat: StandardMaterial3D
var _nodes: Array = []
var _grid := {}


func build(jogo: Node, arvores: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_rng.seed = (seed_ if seed_ != 0 else randi()) + 7717
	last_day = int(jogo.sim.elapsed_days())
	_make_assets()
	if save_path == "" or not _load(save_path):
		_generate()
	palms = palms.filter(func(p): return not _arv._in_sea(float(p.x), float(p.z)))
	_rebuild()


func tick() -> void:
	var day := int(_jogo.sim.elapsed_days())
	if day <= last_day:
		return
	var n := 0
	while last_day < day and n < 400:
		last_day += 1
		n += 1
		_process_day(last_day)
	last_day = day
	_rebuild()


static func month_of(day: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(MundoSim.start_unix() + day * 86400)
	return int(d.month)


## Cachos: verdes de junho a setembro, maduros de outubro a dezembro.
static func cacho_de(day: int) -> int:
	var m := month_of(day)
	if m >= 6 and m <= 9:
		return 1
	if m >= 10:
		return 2
	return 0


## Os cocos maduros caem de outubro a março.
static func queda(day: int) -> bool:
	var m := month_of(day)
	return m >= 10 or m <= 3


func trunk_h(p: Dictionary, day := -1) -> float:
	if day < 0:
		day = last_day
	var age := float(day - int(p.nasc))
	if age <= PINDOVA_DAYS:
		return 0.0
	return minf(0.8 + (age - PINDOVA_DAYS) / 365.0 * 0.35 * float(p.vig), float(p.hmax))


func is_adult(p: Dictionary, day := -1) -> bool:
	if day < 0:
		day = last_day
	return day - int(p.nasc) >= ADULT_DAYS


## O tamanho da pindova (cresce até a hora de formar o tronco).
func pindova_scale(p: Dictionary, day := -1) -> float:
	if day < 0:
		day = last_day
	return clampf(0.15 + float(day - int(p.nasc)) / float(PINDOVA_DAYS) * 0.85, 0.15, 1.0)


func _spot_ok(x: float, z: float) -> bool:
	if not _arv._ground_ok(x, z):
		return false
	var c := Vector2i(int(x / _jogo.CELL), int(z / _jogo.CELL))
	if c.x < 1 or c.y < 1 or c.x >= MundoSim.W - 1 or c.y >= MundoSim.H - 1:
		return false
	# terra firme: longe da água e do mar (nada de areia de praia)
	if float(_jogo.sim.wat[c.y * MundoSim.W + c.x]) > 0.02:
		return false
	for k in 8:
		var a := TAU * k / 8.0
		if _arv._in_sea(x + cos(a) * 18.0, z + sin(a) * 18.0):
			return false
	for p in palms:
		if Vector2(float(p.x) - x, float(p.z) - z).length() < (5.0 if is_adult(p) else 2.5):
			return false
	return true


func _new_palm(x: float, z: float, born: int) -> Dictionary:
	return {"x": x, "z": z, "nasc": born, "hmax": _rng.randf_range(6.0, 16.0), "vig": _rng.randf_range(0.8, 1.2),
		"var": _rng.randi() % VARIANTS, "rot": _rng.randf() * TAU}


func _generate() -> void:
	# os babaçuais: manchas na terra firme (onde o ruído é alto tem muito)
	var nz := FastNoiseLite.new()
	nz.seed = _rng.randi()
	nz.frequency = 0.006
	var W: float = MundoSim.W * _jogo.CELL
	var H: float = MundoSim.H * _jogo.CELL
	var tries := 0
	while palms.size() < START_PALMS and tries < 12000:
		tries += 1
		var x := _rng.randf_range(6.0, W - 6.0)
		var z := _rng.randf_range(6.0, H - 6.0)
		if nz.get_noise_2d(x, z) * 0.5 + 0.5 < 0.45 + _rng.randf() * 0.55:
			continue
		if not _spot_ok(x, z):
			continue
		var r := _rng.randf()
		var age: int
		if r < 0.45:
			age = _rng.randi_range(60, PINDOVA_DAYS)
		else:
			age = _rng.randi_range(ADULT_DAYS, 365 * 70)
		palms.append(_new_palm(x, z, last_day - age))
	# já tem folha seca e coco pelo chão
	for p in palms:
		if is_adult(p) and queda(last_day):
			for k in _rng.randi_range(0, 8):
				_soltar_coco(p, last_day - _rng.randi_range(0, 60))


func _soltar_seca(p: Dictionary, day: int) -> void:
	if secas.size() >= SECA_MAX:
		return
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(1.0, 4.5) if is_adult(p) else _rng.randf_range(0.5, 2.0)
	var x := float(p.x) + cos(a) * d
	var z := float(p.z) + sin(a) * d
	secas.append([snappedf(x, 0.01), snappedf(z, 0.01), snappedf(a + _rng.randf_range(-0.6, 0.6), 0.01),
		snappedf(_rng.randf_range(0.75, 1.0) * (1.0 if is_adult(p) else 0.7), 0.01), day, _rng.randi() % VARIANTS])


func _soltar_coco(p: Dictionary, day: int) -> void:
	if cocos.size() >= COCO_MAX:
		return
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(0.6, 3.2)
	cocos.append([snappedf(float(p.x) + cos(a) * d, 0.01), snappedf(float(p.z) + sin(a) * d, 0.01), snappedf(_rng.randf() * TAU, 0.01), day])


func _process_day(day: int) -> void:
	secas = secas.filter(func(s): return day - int(s[4]) < VERDE_DIAS)
	cocos = cocos.filter(func(c): return day - int(c[3]) < COCO_DAYS)
	var cai := queda(day) and cacho_de(day) != 1
	var novas := []
	for p in palms:
		if is_adult(p, day):
			if cai and _rng.randf() < 0.35:
				for k in _rng.randi_range(1, 4):
					_soltar_coco(p, day)
		elif p.has("folhas") and int(p.folhas) < folhas_max(p) and _rng.randf() < 1.0 / FOLHA_DIAS:
			p.folhas = int(p.folhas) + 1
	# um coco que ficou no chão às vezes brota (vira pindova)
	if palms.size() < MAX_PALMS and not cocos.is_empty() and _rng.randf() < 0.02:
		var c: Array = cocos[_rng.randi() % cocos.size()]
		if _spot_ok(float(c[0]), float(c[1])):
			novas.append(_new_palm(float(c[0]), float(c[1]), day))
	palms.append_array(novas)


# ================== CORTAR E PEGAR ==================

func folhas_max(p: Dictionary) -> int:
	return int(PIND_FOLHAS[int(p.var)])


func folhas_de(p: Dictionary) -> int:
	return int(p.get("folhas", folhas_max(p)))


## A pindova (sem tronco, já grandinha) mais perto, com folha para cortar, ou {}.
func pindova_near(pos: Vector3, reach: float) -> Dictionary:
	var best := {}
	var bd := reach
	for p in palms:
		if is_adult(p) or pindova_scale(p) < 0.35:
			continue
		var d := Vector2(float(p.x) - pos.x, float(p.z) - pos.z).length()
		if d < bd:
			bd = d
			best = p
	return best


## Uma machadada no talo da folha; na segunda a folha cai inteira no chão (devolve true).
func golpe_folha(p: Dictionary, de: Vector3) -> bool:
	p["golpes"] = int(p.get("golpes", 0)) + 1
	if int(p.golpes) < 2:
		return false
	p.golpes = 0
	p["folhas"] = folhas_de(p) - 1
	# a folha cai deitada para o lado de quem cortou
	var dir := Vector2(de.x - float(p.x), de.z - float(p.z))
	var a := dir.angle() + _rng.randf_range(-0.7, 0.7) if dir.length() > 0.1 else _rng.randf() * TAU
	var L := 2.2 * pindova_scale(p)
	secas.append([snappedf(float(p.x) + cos(a) * L, 0.01), snappedf(float(p.z) + sin(a) * L, 0.01), snappedf(a, 0.01),
		snappedf(clampf(pindova_scale(p) * 0.95, 0.5, 1.0), 0.01), last_day])
	_rebuild()
	return true


# ================== PEGAR ==================

## A folha seca de babaçu mais perto (índice) ou -1.
func seca_near(pos: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach
	for i in secas.size():
		var s: Array = secas[i]
		var d := Vector2(float(s[0]) - pos.x, float(s[1]) - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func take_seca(i: int) -> void:
	if i >= 0 and i < secas.size():
		secas.remove_at(i)
		_rebuild()


func coco_near(pos: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach
	for i in cocos.size():
		var c: Array = cocos[i]
		var d := Vector2(float(c[0]) - pos.x, float(c[1]) - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func take_coco(i: int) -> void:
	if i >= 0 and i < cocos.size():
		cocos.remove_at(i)
		_rebuild()


## Pôr uma folha seca no chão (largada da mochila).
func put_seca(x: float, z: float, giro: float) -> void:
	secas.append([snappedf(x, 0.01), snappedf(z, 0.01), snappedf(giro, 0.01), 0.9, last_day])
	_rebuild()


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
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_grid.clear()
	var crowns := []
	var pinds := []
	for v in VARIANTS:
		crowns.append([])
		var porq := []
		for k in int(PIND_FOLHAS[v]) + 1:
			porq.append([])
		pinds.append(porq)
	var trunks := []
	var cv := []
	var cm := []
	var cacho := cacho_de(last_day)
	for p in palms:
		var x := float(p.x)
		var z := float(p.z)
		var gy: float = _jogo.ground_at(x, z)
		var rot := Basis(Vector3.UP, float(p.rot))
		if is_adult(p):
			var th := trunk_h(p)
			var s := clampf(0.75 + th / 20.0, 0.75, 1.15)
			trunks.append(Transform3D(rot.scaled(Vector3(1.0, th, 1.0)), Vector3(x, gy - 0.1, z)))
			crowns[int(p.var)].append(Transform3D(rot.scaled(Vector3.ONE * s), Vector3(x, gy + th, z)))
			if cacho > 0:
				for k in 2 + int(p.var) % 2:
					var a := float(p.rot) + k * 2.3
					var b := Basis(Vector3.UP, a)
					var t := Transform3D(b, Vector3(x, gy + th - 0.35, z) + b * Vector3(0.35, 0, 0))
					(cv if cacho == 1 else cm).append(t)
			var k2 := Vector2i(floori(x / 8.0), floori(z / 8.0))
			if not _grid.has(k2):
				_grid[k2] = []
			_grid[k2].append(Vector3(x, z, TRUNK_R + 0.25))
		else:
			var ps := pindova_scale(p)
			var nf := clampi(folhas_de(p), 0, folhas_max(p))
			pinds[int(p.var)][nf].append(Transform3D(rot.scaled(Vector3.ONE * ps), Vector3(x, gy - 0.05, z)))
	for v in VARIANTS:
		_add_mm(_crowns[v], crowns[v], VIEW, true)
		for k in range(1, (pinds[v] as Array).size()):
			_add_mm(_pindovas[v][k], pinds[v][k], VIEW * 0.6, true)
	_add_mm(_trunk_mesh, trunks, VIEW, true)
	_add_mm(_cacho_verde, cv, 120.0, true)
	_add_mm(_cacho_maduro, cm, 120.0, true)
	# no chão: as folhas secas e os cocos
	var sx := []
	for s in secas:
		var gx: float = _jogo.ground_at(float(s[0]), float(s[1]))
		sx.append(Transform3D(Basis(Vector3.UP, float(s[2])).scaled(Vector3.ONE * float(s[3])), Vector3(float(s[0]), gx + 0.02, float(s[1]))))
	_add_mm(_seca_mesh, sx, CHAO_VIEW, false)
	var cx := []
	for c in cocos:
		var gc: float = _jogo.ground_at(float(c[0]), float(c[1]))
		cx.append(Transform3D(Basis(Vector3.UP, float(c[2])) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(float(c[0]), gc + 0.045, float(c[1]))))
	_add_mm(_coco_mesh, cx, 45.0, false)


func _add_mm(mesh: Mesh, xs: Array, view: float, shadow: bool) -> void:
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
	mi.material_override = _mat
	mi.visibility_range_end = view
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_nodes.append(mi)


# ================== MODELOS ==================

func _make_assets() -> void:
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.85
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rng := RandomNumberGenerator.new()
	for v in VARIANTS:
		rng.seed = 900 + v * 31
		_crowns.append(_coroa(rng, 15 + v, 6.2))
		var porq := [null]
		for k in range(1, int(PIND_FOLHAS[v]) + 1):
			rng.seed = 1900 + v * 17
			porq.append(_pindova(rng, int(PIND_FOLHAS[v]), k))
		_pindovas.append(porq)
	rng.seed = 77
	_seca_mesh = _folha_seca(rng)
	_trunk_mesh = _tronco()
	_cacho_verde = _cacho(Color(0.36, 0.42, 0.18), rng)
	_cacho_maduro = _cacho(Color(0.42, 0.28, 0.14), rng)
	_coco_mesh = _coco()


## Uma folha penada: a raque arqueando e os folíolos estreitos dos dois lados, caídos em V.
## base: onde sai; dir: para onde aponta (horizontal); elev: o ângulo de subida; L: tamanho.
static func _folha(st: SurfaceTool, base: Vector3, dir: Vector3, elev: float, L: float, verde: Color, rng: RandomNumberGenerator, seca := false, deitada := false) -> void:
	var n := 34
	var lado := Vector3.UP.cross(dir).normalized()
	var pts := []
	for i in n + 1:
		var t := float(i) / n
		var p: Vector3
		if deitada:
			p = base + dir * (t * L) + Vector3.UP * (sin(t * PI) * 0.04)
		else:
			# sobe e arqueia: o ângulo vai caindo pela ponta
			var a := elev - t * t * (elev + 0.35)
			p = base + dir * (cos(a * 0.5 + elev * 0.5) * t * L * 0.95) + Vector3.UP * (sin(elev) * t * L - t * t * L * 0.38 * (1.0 if elev < 1.25 else 0.2))
		pts.append(p)
	# a raque (fina)
	var cr := verde.darkened(0.25) if not seca else Color(0.55, 0.43, 0.26)
	for i in n:
		var a2: Vector3 = pts[i]
		var b2: Vector3 = pts[i + 1]
		var w := 0.03 * (1.0 - float(i) / n) + 0.008
		st.set_color(cr)
		st.add_vertex(a2 - lado * w)
		st.add_vertex(a2 + lado * w)
		st.add_vertex(b2 + lado * w)
		st.set_color(cr)
		st.add_vertex(a2 - lado * w)
		st.add_vertex(b2 + lado * w)
		st.add_vertex(b2 - lado * w)
	# os folíolos
	for i in range(3, n):
		var t := float(i) / n
		var p0: Vector3 = pts[i]
		var tg := ((pts[mini(i + 1, n)] as Vector3) - (pts[i - 1] as Vector3)).normalized()
		var comp := L * 0.2 * sin(PI * (0.15 + t * 0.85)) + 0.1
		var cor := verde.lerp(verde.lightened(0.15), rng.randf()) if not seca else Color(0.66, 0.53, 0.33).lerp(Color(0.78, 0.66, 0.44), rng.randf())
		for sd in [-1.0, 1.0]:
			var cai: float = -0.35 if not deitada else 0.0
			var dl: Vector3 = (lado * sd + Vector3.UP * cai + tg * 0.35).normalized()
			if deitada:
				dl = (lado * sd + tg * 0.4).normalized()
			var p1: Vector3 = p0 + dl * comp
			var pm: Vector3 = p0 + dl * comp * 0.45
			var wv := tg * 0.045
			# o folíolo: estreito na base, largo no meio, fino na ponta
			st.set_color(cor)
			st.add_vertex(p0)
			st.add_vertex(pm + wv)
			st.add_vertex(pm - wv)
			st.set_color(cor)
			st.add_vertex(pm - wv)
			st.add_vertex(pm + wv)
			st.add_vertex(p1)


func _coroa(rng: RandomNumberGenerator, n: int, L: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verde := Color(0.24, 0.42, 0.16)
	for i in n:
		var az := TAU * i / n + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(az), 0, sin(az))
		# as do meio quase em pé, as de fora mais abertas
		var elev := lerpf(1.35, 0.55, float(i % 5) / 4.0) + rng.randf_range(-0.1, 0.1)
		_folha(st, Vector3.ZERO + dir * 0.15, dir, elev, L * rng.randf_range(0.8, 1.05), verde.darkened(rng.randf_range(0.0, 0.15)), rng)
	# as bainhas velhas em volta do topo do tronco
	for i in 7:
		var az2 := TAU * i / 7.0
		var d2 := Vector3(cos(az2), 0, sin(az2))
		var c := Color(0.36, 0.28, 0.18)
		st.set_color(c)
		st.add_vertex(d2 * 0.22 + Vector3.DOWN * 0.6)
		st.add_vertex(d2.rotated(Vector3.UP, 0.5) * 0.22 + Vector3.DOWN * 0.6)
		st.add_vertex(d2 * 0.35 + Vector3.UP * 0.2)
	st.generate_normals()
	return st.commit()


## A pindova com "tem" das suas n folhas (as cortadas faltam; a de dentro fica).
func _pindova(rng: RandomNumberGenerator, n: int, tem: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verde := Color(0.26, 0.45, 0.17)
	for i in n:
		var az := TAU * i / n + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(az), 0, sin(az))
		var elev := rng.randf_range(1.15, 1.42)
		var L := rng.randf_range(3.2, 4.6)
		var tom := rng.randf_range(0.0, 0.15)
		if i >= tem:
			continue
		_folha(st, dir * 0.05, dir, elev, L, verde.darkened(tom), rng)
	st.generate_normals()
	return st.commit()


func _folha_seca(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_folha(st, Vector3(-2.2, 0, 0), Vector3.RIGHT, 0.0, 4.4, Color(0.17, 0.3, 0.1), rng, false, true)
	st.generate_normals()
	return st.commit()


## O tronco: 1 m de altura (o resto é a escala), com os anéis das folhas que caíram.
func _tronco() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lados := 12
	var anel := 16
	for j in anel:
		var y0 := float(j) / anel
		var y1 := float(j + 1) / anel
		var r0 := TRUNK_R * (1.12 - y0 * 0.18)
		var r1 := TRUNK_R * (1.12 - y1 * 0.18)
		var c := Color(0.27, 0.24, 0.2).darkened(0.12 * float(j % 2))
		for k in lados:
			var a0 := TAU * k / lados
			var a1 := TAU * (k + 1) / lados
			var q := [Vector3(cos(a0) * r0, y0, sin(a0) * r0), Vector3(cos(a1) * r0, y0, sin(a1) * r0),
				Vector3(cos(a1) * r1, y1, sin(a1) * r1), Vector3(cos(a0) * r1, y1, sin(a0) * r1)]
			for jj in [0, 2, 1, 0, 3, 2]:
				st.set_color(c)
				st.add_vertex(q[jj])
	st.generate_normals()
	return st.commit()


## O cacho pendurado: o pedúnculo e os cocos ovais apertados.
func _cacho(cor: Color, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 70:
		var t := float(i) / 70.0
		var a := t * TAU * 9.0
		var r := 0.12 * sin(PI * clampf(t * 1.1, 0.0, 1.0)) + 0.03
		var c := Vector3(cos(a) * r + 0.25 * t, -0.2 - t * 0.9, sin(a) * r)
		_ovo(st, c, Vector3(0.035, 0.055, 0.035), cor.darkened(rng.randf_range(0.0, 0.2)))
	st.generate_normals()
	return st.commit()


static func _ovo(st: SurfaceTool, c: Vector3, r: Vector3, cor: Color) -> void:
	var la := 4
	var lo := 6
	for i in la:
		var t0 := PI * i / la
		var t1 := PI * (i + 1) / la
		for k in lo:
			var p0 := TAU * k / lo
			var p1 := TAU * (k + 1) / lo
			var q := [Vector3(sin(t0) * cos(p0), cos(t0), sin(t0) * sin(p0)), Vector3(sin(t0) * cos(p1), cos(t0), sin(t0) * sin(p1)),
				Vector3(sin(t1) * cos(p1), cos(t1), sin(t1) * sin(p1)), Vector3(sin(t1) * cos(p0), cos(t1), sin(t1) * sin(p0))]
			for jj in [0, 1, 2, 0, 2, 3]:
				st.set_color(cor)
				st.add_vertex(c + (q[jj] as Vector3) * r)


func _coco() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ovo(st, Vector3.ZERO, Vector3(0.045, 0.065, 0.045), Color(0.4, 0.27, 0.14))
	st.generate_normals()
	return st.commit()


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"palms": palms, "secas": secas, "cocos": cocos, "last_day": last_day}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary or not d.has("palms"):
		return false
	palms = d.palms
	secas = d.get("secas", [])
	cocos = d.get("cocos", [])
	last_day = maxi(int(d.get("last_day", last_day)), 0)
	return true
