extends Node3D
## Buracos cavados com a cavadeira e toras fincadas neles (a base das construções).
##
## - Cada golpe da cavadeira no mesmo lugar aprofunda o buraco (até 80 cm).
##   Cavando um pouco ao lado abre outro buraco encostado: dá para fazer vários,
##   um do lado do outro, ou um buraco mais largo.
##   A terra tirada fica num montinho do lado.
## - Com uma tora no ombro perto de um buraco, dá para fincar a tora em pé: a parte
##   de baixo fica enterrada no buraco e o resto fica para fora da terra.

const MAX_DEPTH := 0.8
const STEP := 0.1               # cada golpe aprofunda 10 cm
const MAX_HOLES := 400

var holes: Array = []           # {x, z, d (fundura, m), r (raio), tora (índice do esteio ou -1)}
var posts: Array = []           # toras fincadas: {log (dados da tora), x, z, d (enterrada), yaw}
var _jogo: Node
var _arv: Node
var _nodes: Array = []
var _soil_mat: StandardMaterial3D
var changed_hook := Callable()   # avisa o jogo quando os buracos mudam (para recortar o chão)


func build(jogo: Node, arvores: Node, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_soil_mat = _make_soil_material()
	if save_path != "":
		_load(save_path)
	_rebuild()


## Terra com textura (grãos, torrões e relevo), aplicada de todos os lados (triplanar).
## A cor de cada ponto (mais escura no fundo, faixas de camadas) multiplica a textura.
static func _make_soil_material() -> StandardMaterial3D:
	var n := FastNoiseLite.new()
	n.seed = 31
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.09
	n.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([Color(0.48, 0.42, 0.36), Color(0.66, 0.59, 0.5), Color(0.8, 0.72, 0.62)])
	var alb := NoiseTexture2D.new()
	alb.width = 256
	alb.height = 256
	alb.seamless = true
	alb.noise = n
	alb.color_ramp = ramp
	var nrm := NoiseTexture2D.new()
	nrm.width = 256
	nrm.height = 256
	nrm.seamless = true
	nrm.noise = n
	nrm.as_normal_map = true
	nrm.bump_strength = 6.0
	var m := StandardMaterial3D.new()
	m.albedo_texture = alb
	m.normal_enabled = true
	m.normal_texture = nrm
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(3, 3, 3)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.metallic_specular = 0.0
	return m


## Buracos abertos perto de um ponto, para o chão e o capim não serem desenhados neles:
## [Vector4(x, z, raio da abertura, 0)], no máximo n.
func open_holes_near(pos: Vector3, n: int) -> Array:
	var list := []
	for h in holes:
		if int(h.get("tora", -1)) >= 0:
			continue
		var d := Vector2(float(h.x) - pos.x, float(h.z) - pos.z).length()
		if d < 80.0:
			list.append([d, Vector4(float(h.x), float(h.z), float(h.r) * 0.88, 0.0)])
	list.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	for i in mini(n, list.size()):
		out.append(list[i][1])
	return out


# ================== CAVAR ==================

## Um golpe da cavadeira no ponto pos. Devolve a fundura do buraco (m).
func dig_at(pos: Vector3) -> float:
	var best := -1
	var bd := 0.22
	for i in holes.size():
		var h: Dictionary = holes[i]
		if int(h.get("tora", -1)) >= 0:
			continue
		var d := Vector2(float(h.x) - pos.x, float(h.z) - pos.z).length()
		if d < bd:
			bd = d
			best = i
	if best < 0:
		if holes.size() >= MAX_HOLES:
			return 0.0
		holes.append({"x": pos.x, "z": pos.z, "d": STEP, "r": 0.17, "tora": -1})
		best = holes.size() - 1
	else:
		var h: Dictionary = holes[best]
		h.d = minf(float(h.d) + STEP, MAX_DEPTH)
		h.r = minf(float(h.r) + 0.012, 0.26)
	_rebuild()
	return float(holes[best].d)


## Buraco aberto (sem tora) mais perto, com fundura mínima (ou -1).
func hole_near(pos: Vector3, reach: float, min_depth := 0.2) -> int:
	var best := -1
	var bd := reach
	for i in holes.size():
		var h: Dictionary = holes[i]
		if int(h.get("tora", -1)) >= 0 or float(h.d) < min_depth:
			continue
		var d := Vector2(float(h.x) - pos.x, float(h.z) - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


## Finca a tora em pé no buraco.
func plant(i: int, fl: Dictionary, yaw: float) -> void:
	var h: Dictionary = holes[i]
	posts.append({"log": fl, "x": float(h.x), "z": float(h.z), "d": float(h.d), "yaw": yaw})
	h.tora = posts.size() - 1
	_rebuild()


# ================== COLISÃO ==================

## O jogador não atravessa as toras fincadas.
func push_out(p: Vector3) -> Vector3:
	for po in posts:
		var r: float = _arv.free_log_radius(po.log) + 0.28
		var d := Vector2(p.x - float(po.x), p.z - float(po.z))
		var l := d.length()
		if l < r:
			var n := d / l if l > 0.001 else Vector2(1, 0)
			p.x = float(po.x) + n.x * r
			p.z = float(po.z) + n.y * r
	return p


# ================== DESENHO ==================

func _rebuild() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if holes.is_empty() and posts.is_empty():
		if changed_hook.is_valid():
			changed_hook.call()
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for h in holes:
		_hole_geo(st, h)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _soil_mat
	add_child(mi)
	_nodes.append(mi)
	for po in posts:
		var n: Node3D = _arv.free_log_node(po.log)
		add_child(n)
		_nodes.append(n)
		var L: float = _arv.free_log_length(po.log)
		var gy: float = _jogo.height_at(float(po.x), float(po.z))
		# em pé: o eixo da tora (que é +X) vira para cima; a ponta de baixo no fundo do buraco
		n.transform = Transform3D(Basis(Vector3.UP, float(po.yaw)) * Basis(Quaternion(Vector3.RIGHT, Vector3.UP)),
			Vector3(float(po.x), gy - float(po.d) + L * 0.5, float(po.z)))
	if changed_hook.is_valid():
		changed_hook.call()


## Cor da terra numa fundura (m abaixo da superfície): camada escura de cima (húmus),
## depois terra amarelada/avermelhada, com faixas; e mais escura no fundo (pouca luz).
static func _soil_color(depth: float, hole_d: float, k: int) -> Color:
	var top := Color(0.2, 0.15, 0.1)
	var sub := Color(0.36, 0.26, 0.17)
	var c := top.lerp(sub, smoothstep(0.05, 0.3, depth))
	c = c.darkened(0.08 * float(int(depth * 14.0) % 2))           # faixas das camadas
	c = c.darkened(0.06 * float((k * 7) % 3) / 2.0)
	var shade := clampf(depth / maxf(hole_d, 0.05), 0.0, 1.0)
	return c.darkened(0.55 * shade * shade + 0.1)                  # o fundo pega pouca luz


## Buraco de verdade: paredes de terra descendo até o fundo (o chão é recortado na
## boca), borda de terra solta e o monte de terra tirada do lado. Com tora fincada,
## a terra fica socada em volta da tora.
func _hole_geo(st: SurfaceTool, h: Dictionary) -> void:
	var x := float(h.x)
	var z := float(h.z)
	var r := float(h.r)
	var d := float(h.d)
	var filled := int(h.get("tora", -1)) >= 0
	var seg := 18
	var hsh := absi(hash(Vector2(x, z)))
	var gy: float = _jogo.height_at(x, z)
	var rims := []
	for k in seg + 1:
		var a := TAU * k / seg
		var rr := r * (0.92 + 0.16 * float((hsh >> (k % 18)) % 10) / 10.0)
		var p := Vector2(x + cos(a) * rr, z + sin(a) * rr)
		rims.append([a, rr, _jogo.height_at(p.x, p.y), p])
	if filled:
		# terra socada em volta da tora
		var c := Vector3(x, gy + 0.03, z)
		for k in seg:
			var A: Array = rims[k]
			var B: Array = rims[k + 1]
			var pa := Vector3(A[3].x, float(A[2]) + 0.02, A[3].y)
			var pb := Vector3(B[3].x, float(B[2]) + 0.02, B[3].y)
			_tri(st, c, pa, pb, Color(0.3, 0.22, 0.14), Color(0.34, 0.25, 0.16), Color(0.34, 0.25, 0.16))
		return
	# paredes: de cima (na altura do chão) até o fundo, afinando um pouco; anéis no meio
	var levels := 5
	for k in seg:
		var A: Array = rims[k]
		var B: Array = rims[k + 1]
		for l in levels:
			var t0 := float(l) / levels
			var t1 := float(l + 1) / levels
			var pts := []
			for pair in [[A, t0], [B, t0], [B, t1], [A, t1]]:
				var rim: Array = pair[0]
				var t: float = pair[1]
				var a: float = rim[0]
				var rad: float = float(rim[1]) * lerpf(1.0, 0.82, t)
				var top: float = rim[2]
				var bottom := gy - d
				var y := lerpf(top + 0.01, bottom, t)
				var wob := 0.012 * sin(a * 5.0 + t * 9.0 + float(hsh % 7))
				pts.append([Vector3(x + cos(a) * (rad + wob), y, z + sin(a) * (rad + wob)), top - y])
			var c0 := _soil_color(pts[0][1], d, k)
			var c1 := _soil_color(pts[1][1], d, k + 1)
			var c2 := _soil_color(pts[2][1], d, k + 1)
			var c3 := _soil_color(pts[3][1], d, k)
			_tri(st, pts[0][0], pts[1][0], pts[2][0], c0, c1, c2, true, Vector3(x, 0, z))
			_tri(st, pts[0][0], pts[2][0], pts[3][0], c0, c2, c3, true, Vector3(x, 0, z))
	# fundo do buraco (terra solta, escura)
	var bc := Vector3(x, gy - d - 0.01, z)
	var dark := _soil_color(d, d, 0).darkened(0.1)
	for k in seg:
		var A: Array = rims[k]
		var B: Array = rims[k + 1]
		var pa := Vector3(x + cos(float(A[0])) * float(A[1]) * 0.82, gy - d, z + sin(float(A[0])) * float(A[1]) * 0.82)
		var pb := Vector3(x + cos(float(B[0])) * float(B[1]) * 0.82, gy - d, z + sin(float(B[0])) * float(B[1]) * 0.82)
		_tri(st, bc, pa, pb, dark.darkened(0.15), dark, dark)
	# borda: terra solta pisada em volta da boca
	var loose := Color(0.27, 0.2, 0.13)
	for k in seg:
		var A: Array = rims[k]
		var B: Array = rims[k + 1]
		var ia := Vector3(A[3].x, float(A[2]) + 0.012, A[3].y)
		var ib := Vector3(B[3].x, float(B[2]) + 0.012, B[3].y)
		var oa2 := Vector2(x + cos(float(A[0])) * float(A[1]) * 1.5, z + sin(float(A[0])) * float(A[1]) * 1.5)
		var ob2 := Vector2(x + cos(float(B[0])) * float(B[1]) * 1.5, z + sin(float(B[0])) * float(B[1]) * 1.5)
		var oa := Vector3(oa2.x, _jogo.height_at(oa2.x, oa2.y) + 0.02, oa2.y)
		var ob := Vector3(ob2.x, _jogo.height_at(ob2.x, ob2.y) + 0.02, ob2.y)
		_tri(st, ia, oa, ob, loose.darkened(0.15), loose, loose)
		_tri(st, ia, ob, ib, loose.darkened(0.15), loose, loose.darkened(0.15))
	# monte da terra tirada, do lado: redondo, com torrões
	var vol := PI * r * r * d
	var mh := clampf(vol * 5.0, 0.04, 0.32)
	var mr := clampf(r * 1.1 + vol * 2.2, 0.18, 0.65)
	var a0 := float(hsh % 628) / 100.0
	var mc := Vector2(x + cos(a0) * (r * 1.6 + mr * 0.8), z + sin(a0) * (r * 1.6 + mr * 0.8))
	var ms := 14
	var rings := 4
	var grid := []
	for i in rings + 1:
		var t := float(i) / rings
		var row := []
		for k in ms + 1:
			var a := TAU * k / ms
			var bump := 1.0 + 0.18 * sin(a * 3.0 + float(hsh % 5)) + 0.1 * sin(a * 7.0)
			var rad := mr * (1.0 - t) * bump
			var p := Vector2(mc.x + cos(a) * rad, mc.y + sin(a) * rad)
			var hgt := mh * sqrt(maxf(0.0, 1.0 - (1.0 - t) * (1.0 - t))) * (0.9 + 0.2 * float((hsh >> ((i * 3 + k) % 20)) % 5) / 5.0)
			row.append(Vector3(p.x, _jogo.height_at(p.x, p.y) + 0.01 + hgt, p.y))
		grid.append(row)
	var soil := Color(0.31, 0.23, 0.15)
	for i in rings:
		for k in ms:
			var c_a := soil.darkened(0.12 * float((i + k) % 2))
			_tri(st, grid[i][k], grid[i][k + 1], grid[i + 1][k + 1], c_a, c_a, soil)
			_tri(st, grid[i][k], grid[i + 1][k + 1], grid[i + 1][k], c_a, soil, soil)


## Triângulo com cor por ponto. inward: a normal aponta para o meio do buraco (paredes).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, inward := false, center := Vector3.ZERO) -> void:
	var n := (b - a).cross(c - a).normalized()
	if inward:
		var mid := (a + b + c) / 3.0
		var to_c := Vector3(center.x - mid.x, 0, center.z - mid.z)
		if n.dot(to_c) < 0.0:
			n = -n
	elif n.y < 0.0:
		n = -n
	for pair in [[a, ca], [b, cb], [c, cc]]:
		st.set_normal(n)
		st.set_color(pair[1])
		st.add_vertex(pair[0])


# ================== SALVAR ==================

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "buracos": holes, "toras": posts}))
		f.close()


func _load(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		holes = d.get("buracos", [])
		posts = d.get("toras", [])
