extends Node3D
## Macaco-prego (Sapajus): modelo feito em código, com pelagem de verdade (camadas de
## fios: "shell fur") e as animações (andar de quatro, subir no tronco, sentar e comer).
##
## Corpo uns 40 cm, rabo uns 40 cm. Pelo marrom com as costas mais escuras, braços,
## pernas e rabo quase pretos, o "boné" preto em cima da cabeça, rosto e peito claros
## (creme), cara e mãos de pele escura sem pelo. A frente do macaco é -Z.

const FUR_LAYERS := 7

var mode := "walk"          # "walk", "sit", "climb", "ride"
var speed := 0.0            # m/s (para o passo)
var _t := randf() * 10.0
var _body: Node3D
var _head: Node3D
var _limbs := {}            # "fl", "fr", "bl", "br" -> [ombro/quadril, cotovelo/joelho]
var _tail: Array = []
var _eat := 0.0             # comendo: mão na boca
var back_point: Node3D      # onde o filhote vai nas costas

static var _fur_shader: Shader
static var _fur_mat: ShaderMaterial
static var _built := {}       # parte -> ArrayMesh do pelo (feito uma vez, todos os macacos usam)
var _building := {}           # parte -> SurfaceTool (só no primeiro macaco)
var _part_of := {}            # Node3D -> nome da parte
static var _skin_mat: StandardMaterial3D
static var _eye_mat: StandardMaterial3D
static var _sphere: SphereMesh
static var _caps := {}

const FUR_CODE := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform float density = 380.0;
// cor do pelo vem na cor do vértice; UV2.x = camada (0 pele, 1 ponta), UV2.y = tamanho do fio
varying vec3 objp;
varying float layer;
float h(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453); }
void vertex() {
	objp = VERTEX;
	layer = UV2.x;
	float fur_len = UV2.y;
	VERTEX += NORMAL * layer * fur_len * 0.55;
	// os fios caem um pouco para baixo e para trás (penteados)
	VERTEX.y -= layer * layer * fur_len * 0.5;
	VERTEX.z += layer * layer * fur_len * 0.4;
}
void fragment() {
	vec3 c = floor(objp * density);
	float n = h(c);
	float n2 = h(c + 17.0);
	if (layer > 0.01 && n < layer * 0.92) { discard; }
	// mais escuro perto da pele (sombra entre os fios), pontas mais claras
	vec3 base = COLOR.rgb * mix(0.75, 1.15, n2);
	float ao = mix(0.35, 1.0, layer);
	ALBEDO = base * ao * mix(1.0, 1.15, layer * layer);
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	BACKLIGHT = base * 0.25 * layer;
}
"""


static func _setup() -> void:
	if _fur_shader != null:
		return
	_fur_shader = Shader.new()
	_fur_shader.code = FUR_CODE
	_fur_mat = ShaderMaterial.new()
	_fur_mat.shader = _fur_shader
	_skin_mat = StandardMaterial3D.new()
	_skin_mat.albedo_color = Color(0.42, 0.3, 0.24)
	_skin_mat.roughness = 0.6
	_skin_mat.metallic_specular = 0.35
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.09, 0.05, 0.02)
	_eye_mat.roughness = 0.05
	_eye_mat.metallic_specular = 1.0
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 16
	_sphere.rings = 10


static func _cap_mesh(length: float, r: float) -> CapsuleMesh:
	var key := "%.3f_%.3f" % [length, r]
	if not _caps.has(key):
		var cm := CapsuleMesh.new()
		cm.radius = r
		cm.height = length + 2.0 * r
		cm.radial_segments = 12
		cm.rings = 4
		_caps[key] = cm
	return _caps[key]


## Peça peluda: a malha copiada várias vezes (camadas), cada camada um pouco para fora.
## Tudo de uma parte do corpo vira uma malha só.
func _furry(parent: Node3D, mesh: Mesh, xf: Transform3D, col: Color, length: float) -> void:
	var part: String = _part_of[parent]
	if _built.has(part):
		return
	if not _building.has(part):
		var stn := SurfaceTool.new()
		stn.begin(Mesh.PRIMITIVE_TRIANGLES)
		_building[part] = stn
	var st: SurfaceTool = _building[part]
	var arr: Array = mesh.surface_get_arrays(0) if mesh is ArrayMesh else mesh.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var ids: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if ids.is_empty():
		ids = PackedInt32Array(range(vs.size()))
	var cs = arr[Mesh.ARRAY_COLOR]
	var nb := xf.basis.inverse().transposed()
	for k in FUR_LAYERS:
		var layer := float(k) / (FUR_LAYERS - 1)
		for i in ids:
			st.set_color(col if cs == null or (cs as PackedColorArray).is_empty() else (cs as PackedColorArray)[i])
			st.set_uv2(Vector2(layer, length))
			st.set_normal((nb * ns[i]).normalized())
			st.add_vertex(xf * vs[i])


## Corpo liso, de uma peça só: anéis em elipse ao longo de Z, ligados (sem "bolinhas").
## prof: [[z, y, rx, ry, cor de cima, cor de baixo], ...]
static func _loft(prof: Array, seg := 16) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	for pr in prof:
		var ring := []
		for j in seg + 1:
			var a := TAU * j / seg
			var p := Vector3(cos(a) * float(pr[2]), float(pr[1]) + sin(a) * float(pr[3]), float(pr[0]))
			var n := Vector3(cos(a) / float(pr[2]), sin(a) / float(pr[3]), 0).normalized()
			var t := smoothstep(-0.6, 0.6, sin(a))
			ring.append([p, n, (pr[5] as Color).lerp(pr[4] as Color, t)])
		rings.append(ring)
	var add := func(v: Array) -> void:
		st.set_color(v[2])
		st.set_normal(v[1])
		st.add_vertex(v[0])
	for i in rings.size() - 1:
		for j in seg:
			var a: Array = rings[i][j]
			var b: Array = rings[i][j + 1]
			var c: Array = rings[i + 1][j + 1]
			var d: Array = rings[i + 1][j]
			for tri in [[a, b, c], [a, c, d]]:
				var pa: Vector3 = tri[0][0]
				var pb: Vector3 = tri[1][0]
				var pc: Vector3 = tri[2][0]
				var out: Vector3 = (tri[0][1] as Vector3) + (tri[1][1] as Vector3) + (tri[2][1] as Vector3)
				if (pc - pa).cross(pb - pa).dot(out) < 0.0:
					tri = [tri[0], tri[2], tri[1]]
				for v in tri:
					add.call(v)
	# pontas fechadas
	for e in [0, rings.size() - 1]:
		var ring: Array = rings[e]
		var cen := Vector3.ZERO
		for v in ring:
			cen += v[0] as Vector3
		cen /= ring.size()
		var nz := Vector3(0, 0, -1.0 if e == 0 else 1.0)
		if float(prof[0][0]) > float(prof[prof.size() - 1][0]):
			nz = -nz
		for j in seg:
			var tri := [[cen, nz, ring[j][2]], ring[j], ring[j + 1]]
			var pa: Vector3 = tri[0][0]
			var pb: Vector3 = tri[1][0]
			var pc: Vector3 = tri[2][0]
			if (pc - pa).cross(pb - pa).dot(nz) < 0.0:
				tri = [tri[0], tri[2], tri[1]]
			for v in tri:
				add.call([v[0], nz, v[2]])
	return st.commit()


func _part(parent: Node3D, name: String) -> void:
	_part_of[parent] = name


## Acabou de montar: cada parte ganha a malha do pelo.
func _finish_fur() -> void:
	for n in _part_of:
		var part: String = _part_of[n]
		if not _built.has(part) and _building.has(part):
			_built[part] = (_building[part] as SurfaceTool).commit()
	_building.clear()
	for n in _part_of:
		var part: String = _part_of[n]
		if not _built.has(part):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _built[part]
		mi.material_override = _fur_mat
		(n as Node3D).add_child(mi)


func _ball(parent: Node3D, pos: Vector3, size: Vector3, col: Color, fur := 0.012) -> void:
	_furry(parent, _sphere, Transform3D(Basis().scaled(size), pos), col, fur)


static func _skin(parent: Node3D, pos: Vector3, size: Vector3, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere
	mi.material_override = mat if mat != null else _skin_mat
	mi.scale = size
	mi.position = pos
	parent.add_child(mi)
	return mi


## Pedaço de pata pendurado para baixo (-Y) a partir do pivô.
func _limb(parent: Node3D, length: float, r: float, col: Color) -> void:
	# pata afinando (músculo em cima, fina embaixo), ao longo de -Y
	var key := "pata_%.3f_%.3f_%s" % [length, r, col.to_html()]
	if not _caps.has(key):
		var c2 := col.darkened(0.15)
		_caps[key] = _loft([[r * 0.4, 0.0, r * 0.6, r * 0.6, col, c2], [0.0, 0.0, r * 1.05, r, col, c2],
			[-length * 0.3, 0.0, r * 1.0, r * 0.95, col, c2], [-length * 0.75, 0.0, r * 0.78, r * 0.72, col, c2],
			[-length - r * 0.3, 0.0, r * 0.62, r * 0.58, col, c2], [-length - r * 0.85, 0.0, r * 0.25, r * 0.25, col, c2]])
	_furry(parent, _caps[key], Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO), col, 0.009)


func _ready() -> void:
	_setup()
	var brown := Color(0.27, 0.19, 0.12)
	var back := Color(0.2, 0.14, 0.09)
	var dark := Color(0.08, 0.06, 0.05)
	var cream := Color(0.62, 0.52, 0.38)
	_body = Node3D.new()
	add_child(_body)
	_part(_body, "corpo")
	# tronco: quadril e peito, deitado ao longo de Z (de quatro)
	# tronco liso de uma peça: rabo -> quadril -> cintura -> peito -> pescoço;
	# costas escuras em cima, barriga marrom, peito creme na frente
	var belly := brown.lerp(cream, 0.2)
	_furry(_body, _loft([
		[0.24, 0.035, 0.022, 0.022, back, back],
		[0.2, 0.025, 0.052, 0.055, back, brown],
		[0.13, 0.008, 0.074, 0.076, back, belly],
		[0.05, 0.0, 0.07, 0.072, back, belly],
		[-0.03, 0.002, 0.074, 0.08, brown, belly],
		[-0.1, 0.008, 0.08, 0.082, brown, cream],
		[-0.15, 0.022, 0.066, 0.066, brown, cream],
		[-0.19, 0.045, 0.044, 0.046, brown, cream],
		[-0.215, 0.06, 0.032, 0.034, brown, cream]], 18), Transform3D.IDENTITY, brown, 0.014)
	back_point = Node3D.new()
	back_point.position = Vector3(0, 0.1, 0.02)
	_body.add_child(back_point)
	# pescoço e cabeça
	_head = Node3D.new()
	_head.position = Vector3(0, 0.07, -0.21)
	_body.add_child(_head)
	_part(_head, "cabeca")
	_ball(_head, Vector3.ZERO, Vector3(0.105, 0.1, 0.105), brown, 0.012)
	_ball(_head, Vector3(0, 0.035, 0.006), Vector3(0.096, 0.05, 0.095), dark, 0.016)       # boné preto
	_ball(_head, Vector3(0, -0.006, -0.022), Vector3(0.094, 0.088, 0.06), cream, 0.008)      # pelo claro em volta do rosto
	_skin(_head, Vector3(0, -0.012, -0.05), Vector3(0.058, 0.064, 0.036))                   # cara sem pelo
	_skin(_head, Vector3(0, -0.03, -0.062), Vector3(0.034, 0.028, 0.026))                    # focinho
	_skin(_head, Vector3(0, 0.01, -0.06), Vector3(0.05, 0.012, 0.016))                      # sobrancelha
	for sx in [-1.0, 1.0]:
		_skin(_head, Vector3(sx * 0.014, -0.003, -0.066), Vector3(0.011, 0.01, 0.006), _eye_mat)
		_skin(_head, Vector3(sx * 0.006, -0.032, -0.075), Vector3(0.005, 0.004, 0.003), _eye_mat)   # narina
		_ball(_head, Vector3(sx * 0.05, 0.004, 0.006), Vector3(0.022, 0.03, 0.012), brown, 0.004)  # orelha
	# patas: ombro/quadril -> cotovelo/joelho; mãos e pés de pele escura
	for key in ["fl", "fr", "bl", "br"]:
		var front: bool = key.begins_with("f")
		var sx := -1.0 if key.ends_with("l") else 1.0
		var top := Node3D.new()
		top.position = Vector3(sx * 0.058, -0.03, -0.11 if front else 0.13)
		_body.add_child(top)
		_part(top, key + "0")
		_limb(top, 0.1, 0.026 if front else 0.032, brown if front else back)
		var low := Node3D.new()
		low.position = Vector3(0, -0.1, 0)
		top.add_child(low)
		_part(low, key + "1")
		_limb(low, 0.095, 0.02, dark)
		_skin(low, Vector3(0, -0.105, -0.014), Vector3(0.034, 0.02, 0.05))
		_limbs[key] = [top, low]
	# rabo: 6 pedaços, grosso e peludo, quase preto
	var parent: Node3D = _body
	var pos := Vector3(0, 0.035, 0.2)
	for k in 6:
		var seg := Node3D.new()
		seg.position = pos
		parent.add_child(seg)
		_part(seg, "rabo%d" % k)
		var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 0.037))
		_furry(seg, _cap_mesh(0.07, 0.02 - k * 0.0018), xf, dark if k > 1 else back, 0.012)
		_tail.append(seg)
		parent = seg
		pos = Vector3(0, 0, 0.075)
	_finish_fur()


func _process(delta: float) -> void:
	_t += delta
	match mode:
		"walk":
			_pose_walk()
		"climb":
			_pose_climb()
		"ride":
			_pose_ride()
		_:
			_pose_sit(delta)
	if mode == "walk" or mode == "sit":
		_sit_on_ground()


## Apoia no chão: o ponto mais baixo (mãos, pés, barriga) fica bem na altura do chão
## (nem dentro da terra, nem flutuando).
func _sit_on_ground() -> void:
	var inv := global_transform.affine_inverse()
	var lo := 1e9
	for key in _limbs:
		var low: Node3D = _limbs[key][1]
		lo = minf(lo, (inv * (low.global_transform * Vector3(0, -0.12, 0))).y)
	for z in [0.13, 0.03, -0.08]:
		lo = minf(lo, (inv * (_body.global_transform * Vector3(0, -0.07, z))).y)
	if lo < 1e8:
		_body.position.y -= lo / maxf(scale.y, 0.01)


func _set_limb(key: String, a: float, b: float) -> void:
	var l: Array = _limbs[key]
	(l[0] as Node3D).rotation = Vector3(a, 0, 0)
	(l[1] as Node3D).rotation = Vector3(b, 0, 0)


## De quatro: patas em diagonal juntas, corpo balança um pouco; o rabo em S para cima.
func _pose_walk() -> void:
	var f := _t * (2.0 + speed * 4.5)
	var amp := clampf(speed * 0.6, 0.08, 0.7)
	_body.position = Vector3(0, 0.215 + absf(sin(f)) * 0.015 * amp, 0)
	_body.rotation = Vector3(0, 0, sin(f) * 0.03 * amp)
	_head.rotation = Vector3(0.1 + sin(_t * 0.7) * 0.1, sin(_t * 0.5) * 0.3, 0)
	_set_limb("fl", sin(f) * amp, -0.2 - maxf(0.0, -sin(f)) * amp)
	_set_limb("br", sin(f) * amp, 0.3 + maxf(0.0, -sin(f)) * amp)
	_set_limb("fr", -sin(f) * amp, -0.2 - maxf(0.0, sin(f)) * amp)
	_set_limb("bl", -sin(f) * amp, 0.3 + maxf(0.0, sin(f)) * amp)
	for k in _tail.size():
		(_tail[k] as Node3D).rotation = Vector3(-0.55 if k == 0 else 0.25, sin(_t * 1.5 + k) * 0.15, 0)


## Subindo no tronco: corpo em pé, colado na casca, braços e pernas alternando.
func _pose_climb() -> void:
	var f := _t * 5.0
	_body.position = Vector3.ZERO
	_body.rotation = Vector3(PI * 0.5 - 0.1, 0, 0)
	_head.rotation = Vector3(-1.0, 0, 0)
	_set_limb("fl", 1.6 + sin(f) * 0.5, -0.6)
	_set_limb("fr", 1.6 - sin(f) * 0.5, -0.6)
	_set_limb("bl", 1.2 - sin(f) * 0.5, 0.8)
	_set_limb("br", 1.2 + sin(f) * 0.5, 0.8)
	for k in _tail.size():
		(_tail[k] as Node3D).rotation = Vector3(-0.3 if k < 3 else 0.6, sin(_t + k) * 0.1, 0)


## Sentado: corpo em pé, pernas dobradas na frente, de vez em quando leva a mão à boca
## (comendo fruta), olha em volta; o rabo enrola no chão/galho.
func _pose_sit(delta: float) -> void:
	_eat = move_toward(_eat, 1.0 if fmod(_t, 4.0) < 1.6 else 0.0, delta * 3.0)
	_body.position = Vector3(0, 0.16, 0.05)
	_body.rotation = Vector3(1.15, 0, 0)
	_head.rotation = Vector3(-1.0, sin(_t * 0.6) * 0.6, 0)
	_set_limb("bl", 2.2, -2.0)
	_set_limb("br", 2.2, -2.0)
	_set_limb("fl", 0.9, -0.4)
	_set_limb("fr", lerpf(0.9, 2.3, _eat), lerpf(-0.4, -2.2, _eat) + sin(_t * 9.0) * 0.08 * _eat)
	for k in _tail.size():
		(_tail[k] as Node3D).rotation = Vector3(0.9 if k == 0 else 0.25, 0.35, 0)


## Filhote agarrado nas costas da mãe: deitado, abraçando ela.
func _pose_ride() -> void:
	_body.position = Vector3(0, 0.02, 0)
	_body.rotation = Vector3.ZERO
	_head.rotation = Vector3(0.2, sin(_t * 0.8) * 0.4, 0)
	for k in ["fl", "fr"]:
		_set_limb(k, 1.2, -1.4)
	for k in ["bl", "br"]:
		_set_limb(k, -0.9, 1.6)
	for k in _tail.size():
		(_tail[k] as Node3D).rotation = Vector3(0.15, 0.2, 0)
