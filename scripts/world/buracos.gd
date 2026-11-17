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
var _pit_mat: StandardMaterial3D


func build(jogo: Node, arvores: Node, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_soil_mat = StandardMaterial3D.new()
	_soil_mat.vertex_color_use_as_albedo = true
	_soil_mat.vertex_color_is_srgb = true
	_soil_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_soil_mat.roughness = 1.0
	_soil_mat.metallic_specular = 0.0
	# o fundo do buraco não pega luz do céu: fica escuro de verdade
	_pit_mat = StandardMaterial3D.new()
	_pit_mat.vertex_color_use_as_albedo = true
	_pit_mat.vertex_color_is_srgb = true
	_pit_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if save_path != "":
		_load(save_path)
	_rebuild()


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
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pit := SurfaceTool.new()
	pit.begin(Mesh.PRIMITIVE_TRIANGLES)
	for h in holes:
		_hole_geo(st, pit, h)
	for pair in [[st, _soil_mat], [pit, _pit_mat]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (pair[0] as SurfaceTool).commit()
		mi.material_override = pair[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


## Buraco: a boca escura (mais escura no meio, quanto mais fundo), a borda de terra
## solta e o montinho de terra tirada do lado. Se tem tora fincada, a terra fica socada em volta.
func _hole_geo(st: SurfaceTool, pit: SurfaceTool, h: Dictionary) -> void:
	var x := float(h.x)
	var z := float(h.z)
	var r := float(h.r)
	var d := float(h.d)
	var filled := int(h.get("tora", -1)) >= 0
	var seg := 16
	var rim := Color(0.2, 0.14, 0.085)
	var deep := clampf(d / 0.4, 0.0, 1.0)
	var dark := Color(0.12, 0.085, 0.05).lerp(Color(0.012, 0.009, 0.006), deep)
	if filled:
		dark = Color(0.2, 0.15, 0.09)
	var hsh := absi(hash(Vector2(x, z)))
	var ring := []
	var ring_out := []
	for k in seg:
		var a := TAU * k / seg
		var rr := r * (0.9 + 0.2 * float((hsh >> (k % 16)) % 10) / 10.0)
		var p := Vector2(x + cos(a) * rr, z + sin(a) * rr)
		ring.append(Vector3(p.x, _jogo.height_at(p.x, p.y) + 0.015, p.y))
		var po := Vector2(x + cos(a) * rr * 1.45, z + sin(a) * rr * 1.45)
		ring_out.append(Vector3(po.x, _jogo.height_at(po.x, po.y) + 0.02, po.y))
	var center := Vector3(x, _jogo.height_at(x, z) + 0.012, z)
	var mid_c := dark.lerp(rim, 0.25)
	for k in seg:
		var k2 := (k + 1) % seg
		var m0: Vector3 = center.lerp(ring[k], 0.6)
		var m1: Vector3 = center.lerp(ring[k2], 0.6)
		_tri(pit, center, m0, m1, dark, dark, dark)
		_tri(pit, m0, ring[k], ring[k2], dark, mid_c, mid_c)
		_tri(pit, m0, ring[k2], m1, dark, mid_c, dark)
		# borda de terra solta
		_tri(st, ring[k], ring_out[k], ring_out[k2], mid_c, rim, rim)
		_tri(st, ring[k], ring_out[k2], ring[k2], mid_c, rim, mid_c)
	if filled:
		return
	# montinho da terra tirada, do lado
	var vol := PI * r * r * d
	var mh := clampf(vol * 6.0, 0.03, 0.3)
	var mr := clampf(r * 1.2 + vol * 2.0, 0.15, 0.6)
	var a0 := float(hsh % 628) / 100.0
	var mc := Vector2(x + cos(a0) * (r * 1.5 + mr * 0.8), z + sin(a0) * (r * 1.5 + mr * 0.8))
	var top := Vector3(mc.x, _jogo.height_at(mc.x, mc.y) + mh, mc.y)
	var base := []
	for k in 10:
		var a := TAU * k / 10.0
		var rr := mr * (0.8 + 0.3 * float((hsh >> k) % 7) / 7.0)
		var pp := Vector2(mc.x + cos(a) * rr, mc.y + sin(a) * rr)
		base.append(Vector3(pp.x, _jogo.height_at(pp.x, pp.y) + 0.01, pp.y))
	var soil := Color(0.27, 0.19, 0.11)
	for k in 10:
		var k2 := (k + 1) % 10
		var midp: Vector3 = (base[k] + base[k2] + top * 2.0) * 0.25
		midp.y += mh * 0.15
		_tri(st, base[k], midp, base[k2], soil.darkened(0.1), soil, soil.darkened(0.1))
		_tri(st, midp, top, base[k2], soil, soil.lightened(0.08), soil.darkened(0.1))
		_tri(st, base[k], top, midp, soil.darkened(0.1), soil.lightened(0.08), soil)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	st.set_normal(n)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.add_vertex(c)


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
