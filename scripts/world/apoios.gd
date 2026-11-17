extends Node3D
## Forquilhas (cavaletes em X) e toras apoiadas nelas para trabalhar.
##
## A forquilha é feita de 2 galhos cruzados em X e amarrados com cipó no meio.
## Com duas forquilhas no chão, a tora do ombro pode ser apoiada em cima delas,
## deitada na altura da cintura: é ali que a madeira vai ser trabalhada.

const GalhoGeo := preload("res://scripts/world/galho_geo.gd")
const TOP := 0.3                 # altura do cruzamento do X
const ALPHA := 1.0               # abertura das pernas (rad, a partir da vertical): V largo em cima
const LEG_R := 0.06              # grossura do galho da forquilha (raio)
const HEAD := 0.36               # quanto cada galho passa do cruzamento (as pontas do V)
const SLICE := 0.05              # grossura da rodela cortada da ponta (m)
const MIN_OVER := 0.4            # quanto a ponta precisa passar da forquilha para dar de cortar
const FIX_OVER := 0.55           # onde a forquilha fica depois de mudada de lugar
const GAP_MIN := 0.6             # forquilhas nem perto demais...
const GAP_SPARE := 0.5           # ...nem longe demais: sobra pelo menos isso da tora fora delas

var forks: Array = []            # {x, z, yaw}
var rested: Array = []           # {log (dados da tora), a, b (índices das forquilhas), off (centro da tora a partir do meio delas)}
var _jogo: Node
var _arv: Node
var _nodes: Array = []
var _mat: StandardMaterial3D
var _wood: StandardMaterial3D


func build(jogo: Node, arvores: Node, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.95
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wood = GalhoGeo.wood_material()
	if save_path != "":
		_load(save_path)
	_rebuild()


# ================== FORQUILHAS ==================

func place(pos: Vector3, yaw: float) -> void:
	forks.append({"x": pos.x, "z": pos.z, "yaw": yaw})
	_rebuild()


func _busy(i: int) -> bool:
	for r in rested:
		if int(r.a) == i or int(r.b) == i:
			return true
	return false


## Forquilha livre (sem tora em cima) mais perto, ou -1.
func nearest_fork(pos: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach
	for i in forks.size():
		if _busy(i):
			continue
		var f: Dictionary = forks[i]
		var d := Vector2(float(f.x) - pos.x, float(f.z) - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func take_fork(i: int) -> void:
	forks.remove_at(i)
	for r in rested:
		if int(r.a) > i:
			r.a = int(r.a) - 1
		if int(r.b) > i:
			r.b = int(r.b) - 1
	_rebuild()


## Par de forquilhas livres perto do jogador que dá para apoiar uma tora de
## comprimento L (a distância entre elas tem que caber na tora). [a, b] ou [].
func pair_for(pos: Vector3, length: float) -> Array:
	var best := []
	var bd := 3.0
	for i in forks.size():
		if _busy(i):
			continue
		for j in range(i + 1, forks.size()):
			if _busy(j):
				continue
			var A: Dictionary = forks[i]
			var B: Dictionary = forks[j]
			var gap := Vector2(float(A.x) - float(B.x), float(A.z) - float(B.z)).length()
			if gap < GAP_MIN or gap > length - GAP_SPARE:
				continue
			var mid := Vector2((float(A.x) + float(B.x)) * 0.5, (float(A.z) + float(B.z)) * 0.5)
			var d := Vector2(pos.x, pos.z).distance_to(mid)
			if d < bd:
				bd = d
				best = [i, j]
	return best


## Apoia a tora nas duas forquilhas (elas viram de lado para a tora encaixar no X).
func rest(fl: Dictionary, a: int, b: int) -> void:
	var A: Dictionary = forks[a]
	var B: Dictionary = forks[b]
	var yaw := atan2(float(B.z) - float(A.z), float(B.x) - float(A.x))   # o X fica de lado para a tora
	A.yaw = yaw
	B.yaw = yaw
	rested.append({"log": fl, "a": a, "b": b, "off": 0.0})
	_rebuild()


## Tora apoiada mais perto (índice) ou -1.
func nearest_rested(pos: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach
	for i in rested.size():
		var A := end_point(i, -1)
		var B := end_point(i, 1)
		var ab := Vector2(B.x - A.x, B.z - A.z)
		var t := clampf(Vector2(pos.x - A.x, pos.z - A.z).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var c := Vector2(A.x, A.z) + ab * t
		var d := Vector2(c.x - pos.x, c.y - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func take_rested(i: int) -> Dictionary:
	var fl: Dictionary = rested[i].log
	rested.remove_at(i)
	_rebuild()
	return fl


func _fork_pos(f: Dictionary) -> Vector3:
	return Vector3(float(f.x), _jogo.surface_at(float(f.x), float(f.z)), float(f.z))


## Centro da tora no chão (só x e z), a partir do meio das forquilhas.
func _rest_center(r: Dictionary) -> Vector3:
	var A := _fork_pos(forks[int(r.a)])
	var B := _fork_pos(forks[int(r.b)])
	var d := Vector3(B.x - A.x, 0, B.z - A.z).normalized()
	var c := (A + B) * 0.5 + d * float(r.get("off", 0.0))
	return Vector3(c.x, 0, c.z)


## Altura do eixo da tora em cima de uma forquilha: a tora de raio r encaixa no V
## de cima do X, encostando nos dois galhos (sem entrar na madeira).
func _rest_height(fork_ground: float, r: float) -> float:
	return fork_ground + TOP + (r + LEG_R) / sin(ALPHA) + 0.01


## Tudo sobre a tora apoiada i: centro (no eixo), direção (da forquilha a para a b),
## comprimento, raio e quanto cada ponta passa da forquilha ("over" [-1] = lado a, [1] = lado b).
func info(i: int) -> Dictionary:
	var r: Dictionary = rested[i]
	var A := _fork_pos(forks[int(r.a)])
	var B := _fork_pos(forks[int(r.b)])
	var gap := Vector2(B.x - A.x, B.z - A.z).length()
	var off := float(r.get("off", 0.0))
	var L: float = _arv.free_log_length(r.log)
	# raio da tora bem em cima de cada forquilha (a ponta do pé da árvore é mais grossa)
	var ra: float = _arv.free_log_radius_at(r.log, 0.5 + (-gap * 0.5 - off) / L)
	var rb: float = _arv.free_log_radius_at(r.log, 0.5 + (gap * 0.5 - off) / L)
	var A3 := Vector3(A.x, _rest_height(A.y, ra), A.z)
	var B3 := Vector3(B.x, _rest_height(B.y, rb), B.z)
	var dir := (B3 - A3).normalized()
	var c := A3.lerp(B3, (gap * 0.5 + off) / maxf(gap, 0.01))
	return {"center": c, "dir": dir, "L": L, "rad": _arv.free_log_radius(r.log), "rmax": _arv.free_log_max_radius(r.log),
		"gap": gap, "over": {-1: L * 0.5 - off - gap * 0.5, 1: L * 0.5 + off - gap * 0.5}}


## Lado da tora apoiada onde dá para cortar a rodela (a ponta passa bem da forquilha):
## o mais perto do jogador. 0 se nenhum.
func slice_side(i: int, pos: Vector3) -> int:
	var inf := info(i)
	var best := 0
	var bd := 1e9
	for e in [-1, 1]:
		if float(inf.over[e]) < MIN_OVER:
			continue
		var d := pos.distance_to(end_point(i, e))
		if d < bd:
			bd = d
			best = e
	return best


## Ponta da tora (no eixo) do lado e.
func end_point(i: int, e: int) -> Vector3:
	var inf := info(i)
	return inf.center + inf.dir * float(e) * float(inf.L) * 0.5


## Onde a lâmina corta a rodela (no eixo, a SLICE da ponta).
func slice_point(i: int, e: int) -> Vector3:
	var inf := info(i)
	return inf.center + inf.dir * float(e) * (float(inf.L) * 0.5 - SLICE)


## Plano para mudar a forquilha de lugar quando nenhuma ponta passa o suficiente:
## {fork: índice, to: posição nova} ou {} se a tora está curta demais.
func fix_plan(i: int, pos: Vector3) -> Dictionary:
	var r: Dictionary = rested[i]
	var inf := info(i)
	var best := {}
	var bd := 1e9
	for e in [-1, 1]:
		var fi := int(r.b) if e > 0 else int(r.a)
		var other := int(r.a) if e > 0 else int(r.b)
		var to: Vector3 = inf.center + inf.dir * float(e) * (float(inf.L) * 0.5 - FIX_OVER)
		var o: Dictionary = forks[other]
		if Vector2(to.x - float(o.x), to.z - float(o.z)).length() < 0.5:
			continue
		var f: Dictionary = forks[fi]
		var d := pos.distance_to(Vector3(float(f.x), pos.y, float(f.z)))
		if d < bd:
			bd = d
			best = {"fork": fi, "to": Vector3(to.x, 0, to.z), "e": e}
	return best


## Muda a forquilha de lugar (a tora em cima continua onde está).
func move_fork(i: int, fi: int, to: Vector3) -> void:
	var r: Dictionary = rested[i]
	var keep := _rest_center(r)
	forks[fi].x = to.x
	forks[fi].z = to.z
	var A := _fork_pos(forks[int(r.a)])
	var B := _fork_pos(forks[int(r.b)])
	var mid := (A + B) * 0.5
	r.off = Vector3(keep.x - mid.x, 0, keep.z - mid.z).dot(Vector3(B.x - A.x, 0, B.z - A.z).normalized())
	_rebuild()


## Uma ida e volta da serra na ponta da tora apoiada (lado e). Corte lento: tora grossa
## pede muitas passadas. Quando solta a rodela, a tora fica 5 cm mais curta e devolve
## o raio da rodela; senão devolve 0.
func slice_stroke(i: int, e: int) -> float:
	var r: Dictionary = rested[i]
	var fl: Dictionary = r.log
	var rad: float = _arv.free_log_end_radius(fl, e)
	var need := clampi(int(round(8.0 + rad * 40.0)), 10, 26)
	var en: Dictionary = fl.get("entalhe", {})
	if en.is_empty() or int(en.e) != e:
		en = {"e": e, "hits": 0, "need": need, "serra": true}
	en.hits = int(en.hits) + 1
	if int(en.hits) < need:
		fl["entalhe"] = en
		_rebuild()
		return 0.0
	fl.erase("entalhe")
	_arv.shorten_free_log(fl, e, SLICE, 0.5)     # serra de pedra: acabamento irregular
	r.off = float(r.get("off", 0.0)) - float(e) * SLICE * 0.5
	_rebuild()
	return rad


# ================== COLISÃO ==================

func push_out(p: Vector3) -> Vector3:
	# duas passadas: empurrar para fora de uma coisa não pode jogar para dentro da outra
	for _k in 2:
		for f in forks:
			# o X no chão: uma linha de pé a pé (de lado para a tora)
			var yaw := float(f.yaw)
			var across := Vector2(-sin(yaw), cos(yaw))
			var half := TOP * tan(ALPHA) + 0.05
			p = _push_seg(p, Vector2(float(f.x), float(f.z)) - across * half, Vector2(float(f.x), float(f.z)) + across * half, 0.32)
		for i in rested.size():
			var inf := info(i)
			var A := end_point(i, -1)
			var B := end_point(i, 1)
			p = _push_seg(p, Vector2(A.x, A.z), Vector2(B.x, B.z), float(inf.rmax) + 0.3)
	return p


static func _push_seg(p: Vector3, A: Vector2, B: Vector2, lim: float) -> Vector3:
	var ab := B - A
	var t := clampf(Vector2(p.x - A.x, p.z - A.y).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	var c := A + ab * t
	var d := Vector2(p.x, p.z) - c
	if d.length() < lim:
		var n := d.normalized() if d.length() > 0.001 else Vector2(-ab.y, ab.x).normalized()
		p.x = c.x + n.x * lim
		p.z = c.y + n.y * lim
	return p


# ================== DESENHO ==================

func _rebuild() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if not forks.is_empty():
		var bd := GalhoGeo.Builder.new()
		for f in forks:
			_fork_geo(bd, f)
		var mi := MeshInstance3D.new()
		mi.mesh = bd.commit()
		mi.set_surface_override_material(0, _arv.bark_material())
		if mi.mesh.get_surface_count() > 1:
			mi.set_surface_override_material(1, _wood)
		add_child(mi)
		_nodes.append(mi)
	for i in rested.size():
		var r: Dictionary = rested[i]
		var n: Node3D = _arv.free_log_node(r.log)
		add_child(n)
		_nodes.append(n)
		var inf := info(i)
		# a tora encaixa no V de cima do X
		n.transform = Transform3D(Basis(Quaternion(Vector3.RIGHT, inf.dir)), inf.center)


## Forquilha em X: dois galhos grossos com casca, cruzados e amarrados com cipó.
## O X fica de lado para a tora; as pontas de cima formam o V onde a tora deita.
func _fork_geo(bd, f: Dictionary) -> void:
	_fork_geo_at(bd, _fork_pos(f), float(f.yaw), absi(hash(Vector2(float(f.x), float(f.z)))))


## Forquilha sem a tora, em volta da origem (para a prévia de onde ela vai ficar).
func preview_mesh() -> ArrayMesh:
	var bd := GalhoGeo.Builder.new()
	_fork_geo_at(bd, Vector3.ZERO, 0.0, 7)
	return bd.commit()


func _fork_geo_at(bd, c: Vector3, yaw: float, hs: int) -> void:
	var across := Vector3(-sin(yaw), 0, cos(yaw))
	var along := Vector3(cos(yaw), 0, sin(yaw))
	var x := c + Vector3.UP * TOP
	for k in 2:
		var sgn := 1.0 if k == 0 else -1.0
		var dir := (-across * sgn * sin(ALPHA) + Vector3.UP * cos(ALPHA)).normalized()
		var off := along * 0.055 * sgn             # um galho na frente do outro
		var foot := x + off - dir * (TOP / cos(ALPHA) + 0.06)
		var head := x + off + dir * HEAD
		var bp: Array = GalhoGeo.bent_points(foot, head, LEG_R * 1.1, LEG_R * 0.8, 8, 0.025, hs + k * 7)
		bd.tube(bp[0], bp[1], [false, true])
		# um toquinho de galho cortado saindo de um dos galhos
		var t := 0.35 + 0.2 * k
		var base: Vector3 = (bp[0] as Array)[int(t * 8)]
		var stub_dir := (dir + along * sgn * 0.9 + Vector3.UP * 0.3).normalized()
		bd.tube([base, base + stub_dir * 0.09], [LEG_R * 0.45, LEG_R * 0.4], [false, true], {}, 6)
	# amarração de cipó no cruzamento: voltas em X
	for k in 5:
		var ang := (k - 2) * 0.35
		var ring := []
		var rr := []
		for j in 13:
			var a := TAU * j / 12.0
			var axis := (along * cos(a) * (LEG_R + 0.062) + (Vector3.UP.rotated(along, ang)) * sin(a) * (LEG_R + 0.018))
			ring.append(x + axis)
			rr.append(0.011)
		bd.color_tube(ring, rr, Color(0.3, 0.25, 0.13).darkened(0.12 * (k % 2)))


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "forquilhas": forks, "toras": rested}))
		f.close()


func _load(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		forks = d.get("forquilhas", [])
		rested = d.get("toras", [])
