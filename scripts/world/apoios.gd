extends Node3D
## Forquilhas (cavaletes em X) e toras apoiadas nelas para trabalhar.
##
## A forquilha é feita de 2 galhos cruzados em X e amarrados com cipó no meio.
## Com duas forquilhas no chão, a tora do ombro pode ser apoiada em cima delas,
## deitada na altura da cintura: é ali que a madeira vai ser trabalhada.

const TOP := 0.62                # altura do cruzamento do X (onde a tora encosta)
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


func build(jogo: Node, arvores: Node, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.95
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	var yaw := atan2(float(B.z) - float(A.z), float(B.x) - float(A.x))
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


func _fork_top(f: Dictionary) -> Vector3:
	return Vector3(float(f.x), _jogo.surface_at(float(f.x), float(f.z)) + TOP, float(f.z))


func _rest_center(r: Dictionary) -> Vector3:
	var A := _fork_top(forks[int(r.a)])
	var B := _fork_top(forks[int(r.b)])
	return (A + B) * 0.5 + (B - A).normalized() * float(r.get("off", 0.0))


## Tudo sobre a tora apoiada i: centro (no eixo), direção (da forquilha a para a b),
## comprimento, raio e quanto cada ponta passa da forquilha ("over" [-1] = lado a, [1] = lado b).
func info(i: int) -> Dictionary:
	var r: Dictionary = rested[i]
	var A := _fork_top(forks[int(r.a)])
	var B := _fork_top(forks[int(r.b)])
	var dir := (B - A).normalized()
	var gap := Vector2(B.x - A.x, B.z - A.z).length()
	var off := float(r.get("off", 0.0))
	var L: float = _arv.free_log_length(r.log)
	var rad: float = _arv.free_log_radius(r.log)
	var c := (A + B) * 0.5 + dir * off + Vector3.UP * rad * 0.75
	return {"center": c, "dir": dir, "L": L, "rad": rad, "gap": gap,
		"over": {-1: L * 0.5 - off - gap * 0.5, 1: L * 0.5 + off - gap * 0.5}}


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
	var A := _fork_top(forks[int(r.a)])
	var B := _fork_top(forks[int(r.b)])
	r.off = (keep - (A + B) * 0.5).dot((B - A).normalized())
	_rebuild()


## Uma machadada na ponta da tora apoiada (lado e). Quando solta a rodela, a tora
## fica 5 cm mais curta e devolve o raio da rodela; senão devolve 0.
func slice_hit(i: int, e: int) -> float:
	var r: Dictionary = rested[i]
	var fl: Dictionary = r.log
	var rad: float = _arv.free_log_end_radius(fl, e)
	var need := clampi(int(round(2.0 + rad * 12.0)), 3, 7)
	var en: Dictionary = fl.get("entalhe", {})
	if en.is_empty() or int(en.e) != e:
		en = {"e": e, "hits": 0, "need": need}
	en.hits = int(en.hits) + 1
	if int(en.hits) < need:
		fl["entalhe"] = en
		_rebuild()
		return 0.0
	fl.erase("entalhe")
	_arv.shorten_free_log(fl, e, SLICE)
	r.off = float(r.get("off", 0.0)) - float(e) * SLICE * 0.5
	_rebuild()
	return rad


# ================== COLISÃO ==================

func push_out(p: Vector3) -> Vector3:
	for f in forks:
		var d := Vector2(p.x - float(f.x), p.z - float(f.z))
		var l := d.length()
		if l < 0.45:
			var n := d / l if l > 0.001 else Vector2(1, 0)
			p.x = float(f.x) + n.x * 0.45
			p.z = float(f.z) + n.y * 0.45
	for i in rested.size():
		var r: Dictionary = rested[i]
		var A := end_point(i, -1)
		var B := end_point(i, 1)
		var ab := Vector2(B.x - A.x, B.z - A.z)
		var t := clampf(Vector2(p.x - A.x, p.z - A.z).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var c := Vector2(A.x, A.z) + ab * t
		var d := Vector2(p.x, p.z) - c
		var lim: float = _arv.free_log_radius(r.log) + 0.3
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
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for f in forks:
			_fork_geo(st, f)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mat
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


## Forquilha em X: dois galhos cruzados e amarrados com cipó no cruzamento.
func _fork_geo(st: SurfaceTool, f: Dictionary) -> void:
	var c := Vector3(float(f.x), _jogo.surface_at(float(f.x), float(f.z)), float(f.z))
	var yaw := float(f.yaw)
	# o X fica de lado em relação à tora (que vai na direção yaw)
	var across := Vector3(-sin(yaw), 0, cos(yaw))
	var along := Vector3(cos(yaw), 0, sin(yaw))
	var bark := Color(0.32, 0.24, 0.16)
	for sgn in [1.0, -1.0]:
		var foot: Vector3 = c + across * 0.36 * sgn + along * 0.03 * sgn
		var head: Vector3 = c + Vector3.UP * (TOP + 0.38) - across * 0.25 * sgn - along * 0.03 * sgn
		foot.y = _jogo.surface_at(foot.x, foot.z) - 0.04
		_tube(st, foot, head, 0.03, 0.022, bark.darkened(0.08 if sgn > 0 else 0.0))
		# ponta cortada clara em cima
		_tube(st, head, head + (head - foot).normalized() * 0.01, 0.022, 0.02, Color(0.62, 0.5, 0.33))
	# amarração de cipó no cruzamento
	var x := c + Vector3.UP * TOP
	for k in 4:
		var a := Vector3.UP * (0.02 * (k - 1.5))
		_tube(st, x + a - along * 0.045, x + a + along * 0.045, 0.035, 0.035, Color(0.2, 0.22, 0.1).darkened(0.1 * (k % 2)))


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, col: Color) -> void:
	var d := (b - a).normalized()
	var s1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var s2 := d.cross(s1).normalized()
	st.set_color(col)
	var n := 7
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var o0 := s1 * cos(a0) + s2 * sin(a0)
		var o1 := s1 * cos(a1) + s2 * sin(a1)
		for v in [a + o0 * ra, b + o0 * rb, b + o1 * rb, a + o0 * ra, b + o1 * rb, a + o1 * ra]:
			st.add_vertex(v)


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
