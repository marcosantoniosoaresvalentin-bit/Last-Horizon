extends Node3D
## Forquilhas (cavaletes em X) e toras apoiadas nelas para trabalhar.
##
## A forquilha é feita de 2 galhos cruzados em X e amarrados com cipó no meio.
## Com duas forquilhas no chão, a tora do ombro pode ser apoiada em cima delas,
## deitada na altura da cintura: é ali que a madeira vai ser trabalhada.

const TOP := 0.62                # altura do cruzamento do X (onde a tora encosta)

var forks: Array = []            # {x, z, yaw}
var rested: Array = []           # {log (dados da tora), a, b (índices das forquilhas)}
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
			if gap < 0.5 or gap > length - 0.15:
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
	rested.append({"log": fl, "a": a, "b": b})
	_rebuild()


## Tora apoiada mais perto (índice) ou -1.
func nearest_rested(pos: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach
	for i in rested.size():
		var c := _rest_center(rested[i])
		var d := Vector2(c.x - pos.x, c.z - pos.z).length()
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
	return (_fork_top(forks[int(r.a)]) + _fork_top(forks[int(r.b)])) * 0.5


# ================== COLISÃO ==================

func push_out(p: Vector3) -> Vector3:
	for f in forks:
		var d := Vector2(p.x - float(f.x), p.z - float(f.z))
		var l := d.length()
		if l < 0.45:
			var n := d / l if l > 0.001 else Vector2(1, 0)
			p.x = float(f.x) + n.x * 0.45
			p.z = float(f.z) + n.y * 0.45
	for r in rested:
		var A := _fork_top(forks[int(r.a)])
		var B := _fork_top(forks[int(r.b)])
		var ab := Vector2(B.x - A.x, B.z - A.z)
		var t := clampf(Vector2(p.x - A.x, p.z - A.z).dot(ab) / maxf(ab.length_squared(), 0.0001), -0.3, 1.3)
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
	for r in rested:
		var n: Node3D = _arv.free_log_node(r.log)
		add_child(n)
		_nodes.append(n)
		var A := _fork_top(forks[int(r.a)])
		var B := _fork_top(forks[int(r.b)])
		var rad: float = _arv.free_log_radius(r.log)
		var dir := (B - A).normalized()
		# a tora encaixa no V de cima do X
		n.transform = Transform3D(Basis(Quaternion(Vector3.RIGHT, dir)), (A + B) * 0.5 + Vector3.UP * rad * 0.75)


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
