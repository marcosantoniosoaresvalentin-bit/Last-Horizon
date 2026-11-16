extends Node3D
## Árvores do mundo: Cedrinho (Erisma uncinatum), madeira da Amazônia muito usada para
## tábuas, ripas, forro e mata-junta.
##
## O modelo é construído aqui mesmo, em código (sem arquivo 3D):
## - tronco reto e cilíndrico de 15 a 30 m, mais fino em cima, com pequenas sapopemas
##   (raízes em aba) na base e casca acinzentada com fissuras;
## - galhos grossos só no alto;
## - copa larga e um pouco achatada, feita de cachos de folhas que balançam com o vento.
##
## As árvores ficam em manchas de floresta, fora da água, do fundo das lagoas, das pedras
## e da clareira onde o jogador começa. Ficam sempre no mesmo lugar em cada mundo (semente).
## O jogador não atravessa os troncos (push_out).

const MundoSim := preload("res://scripts/mundo_sim.gd")

const VARIANTS := 3            # modelos diferentes, para a floresta não parecer clonada
const CHUNK := 64.0            # metros de cada bloco de árvores (para o celular desenhar só o que está perto)
const VIEW_DIST := 190.0       # até onde as árvores aparecem
const TRUNK_HIT := 0.75        # raio do tronco para o jogador não atravessar
const MAX_TREES := 900

var trees: Array[Vector4] = []     # x, z, escala, variante
var _grid := {}                    # Vector2i (célula de 8 m) -> índices de árvores
var _meshes: Array = []            # [Mesh do tronco, Mesh da copa] por variante
var _bark: Material
var _leaves: Material


# ================== MONTAGEM ==================

## jogo = o nó do jogo3d (usa height_at, _rockiness, CELL e sim).
func build(jogo: Node, seed_: int) -> void:
	_make_materials()
	for v in VARIANTS:
		_meshes.append(_make_tree(seed_ * 7 + v * 101 + 3))
	_place(jogo, seed_)
	_make_instances(jogo)


func _place(jogo: Node, seed_: int) -> void:
	var sim = jogo.sim
	var cell: float = jogo.CELL
	var W := MundoSim.W
	var H := MundoSim.H
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ if seed_ != 0 else randi()
	var forest := FastNoiseLite.new()
	forest.seed = rng.randi()
	forest.frequency = 0.012
	forest.fractal_octaves = 3
	var spawn := Vector2((sim.spawn.x + 0.5) * cell, (sim.spawn.y + 0.5) * cell)
	var tries := 0
	while trees.size() < MAX_TREES and tries < 30000:
		tries += 1
		var x := rng.randf_range(4.0, W * cell - 4.0)
		var z := rng.randf_range(4.0, H * cell - 4.0)
		# manchas de floresta: muita árvore em alguns lugares, quase nada em outros
		var f := forest.get_noise_2d(x, z) * 0.5 + 0.5
		if rng.randf() > smoothstep(0.42, 0.72, f) * 0.95 + 0.02:
			continue
		if Vector2(x, z).distance_to(spawn) < 18.0:
			continue
		var ci := int(z / cell) * W + int(x / cell)
		if sim.bed[ci] > 0.3 or sim.wat[ci] > 0.03 or sim.deposit[ci] > 0.1:
			continue
		var h: float = jogo.height_at(x, z)
		if jogo._rockiness(h) > 0.3:
			continue
		# terreno muito inclinado não segura árvore grande
		var slope := absf(jogo.height_at(x + 2.0, z) - jogo.height_at(x - 2.0, z)) + absf(jogo.height_at(x, z + 2.0) - jogo.height_at(x, z - 2.0))
		if slope > 2.6:
			continue
		if _near(x, z, 5.5):
			continue
		var s := rng.randf_range(0.6, 1.1)
		_add(Vector4(x, z, s, rng.randi() % VARIANTS))


func _add(t: Vector4) -> void:
	var key := Vector2i(floori(t.x / 8.0), floori(t.y / 8.0))
	if not _grid.has(key):
		_grid[key] = []
	_grid[key].append(trees.size())
	trees.append(t)


func _near(x: float, z: float, r: float) -> bool:
	var k := Vector2i(floori(x / 8.0), floori(z / 8.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for i in _grid.get(k + Vector2i(dx, dz), []):
				var t: Vector4 = trees[i]
				if Vector2(t.x - x, t.y - z).length_squared() < r * r:
					return true
	return false


func _make_instances(jogo: Node) -> void:
	var chunks := {}
	for t in trees:
		var key := Vector2i(floori(t.x / CHUNK), floori(t.y / CHUNK))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(t)
	for key in chunks:
		var list: Array = chunks[key]
		for v in VARIANTS:
			var mine := list.filter(func(t): return int(t.w) == v)
			if mine.is_empty():
				continue
			for part in 2:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = _meshes[v][part]
				mm.instance_count = mine.size()
				for i in mine.size():
					var t: Vector4 = mine[i]
					var y: float = jogo.height_at(t.x, t.y) - 0.15
					var rot := fmod(t.x * 12.9898 + t.y * 78.233, TAU)
					var b := Basis(Vector3.UP, rot).scaled(Vector3(t.z, t.z, t.z))
					mm.set_instance_transform(i, Transform3D(b, Vector3(t.x, y, t.y)))
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.material_override = _bark if part == 0 else _leaves
				mmi.visibility_range_end = VIEW_DIST
				mmi.visibility_range_end_margin = 20.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				add_child(mmi)


## O jogador não atravessa os troncos: empurra a posição para fora.
func push_out(p: Vector3) -> Vector3:
	var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for i in _grid.get(k + Vector2i(dx, dz), []):
				var t: Vector4 = trees[i]
				var r := TRUNK_HIT * t.z + 0.3
				var d := Vector2(p.x - t.x, p.z - t.y)
				var l := d.length()
				if l < r:
					var n := d / l if l > 0.001 else Vector2(1, 0)
					p.x = t.x + n.x * r
					p.z = t.y + n.y * r
	return p


# ================== MATERIAIS ==================

func _make_materials() -> void:
	# casca: cinza-amarronzada, com fissuras compridas no sentido do tronco
	var bn := FastNoiseLite.new()
	bn.seed = 5
	bn.frequency = 0.05
	bn.fractal_octaves = 4
	bn.noise_type = FastNoiseLite.TYPE_CELLULAR
	bn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	ramp.colors = PackedColorArray([Color(0.07, 0.055, 0.045), Color(0.17, 0.14, 0.11), Color(0.27, 0.23, 0.19)])
	var alb := NoiseTexture2D.new()
	alb.width = 256
	alb.height = 512
	alb.seamless = true
	alb.noise = bn
	alb.color_ramp = ramp
	var nrm := NoiseTexture2D.new()
	nrm.width = 256
	nrm.height = 512
	nrm.seamless = true
	nrm.noise = bn
	nrm.as_normal_map = true
	nrm.bump_strength = 10.0
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = alb
	bark.normal_enabled = true
	bark.normal_texture = nrm
	bark.normal_scale = 1.2
	bark.roughness = 0.95
	bark.uv1_scale = Vector3(1.0, 1.0, 1.0)
	_bark = bark

	var sh := Shader.new()
	sh.code = LEAF_SHADER
	var lm := ShaderMaterial.new()
	lm.shader = sh
	lm.set_shader_parameter("leaf_tex", _leaf_texture())
	_leaves = lm


const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap;
varying float sway_h;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(VERTEX.y - 10.0, 0.0);
	float t = TIME * 1.1 + wp.x * 0.05 + wp.z * 0.04;
	VERTEX.x += sin(t) * 0.025 * h;
	VERTEX.z += cos(t * 0.8) * 0.02 * h;
	VERTEX += NORMAL * sin(TIME * 3.0 + wp.x * 0.7 + wp.y * 0.3) * 0.05;
}
void fragment() {
	vec4 c = texture(leaf_tex, UV);
	if (c.a < 0.45) { discard; }
	ALBEDO = c.rgb * COLOR.rgb;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.18, 0.28, 0.08);
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
"""


## Textura de um cacho de folhas (folhas simples, ovais, verde-escuras), desenhada aqui.
func _leaf_texture() -> ImageTexture:
	var S := 256
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for k in 140:
		var cx := rng.randf_range(20, S - 20)
		var cy := rng.randf_range(20, S - 20)
		# mais folhas no meio do cacho
		var to_c := Vector2(S * 0.5 - cx, S * 0.5 - cy)
		if to_c.length() > S * 0.46 and rng.randf() < 0.7:
			continue
		var ang := rng.randf() * TAU
		var L := rng.randf_range(16, 28)
		var Wd := L * rng.randf_range(0.36, 0.46)
		var base := Color(0.07, 0.17, 0.05).lerp(Color(0.16, 0.29, 0.08), rng.randf())
		var dirv := Vector2(cos(ang), sin(ang))
		var perp := Vector2(-dirv.y, dirv.x)
		var r := int(L) + 2
		for py in range(maxi(0, int(cy) - r), mini(S, int(cy) + r)):
			for px in range(maxi(0, int(cx) - r), mini(S, int(cx) + r)):
				var d := Vector2(px - cx, py - cy)
				var u := d.dot(dirv) / L
				var v := d.dot(perp) / Wd
				var q := u * u + v * v
				if q <= 1.0:
					var shade := 0.82 + 0.25 * (1.0 - q) - absf(v) * 0.1
					var col := base * shade
					if absf(v) < 0.08 and absf(u) < 0.85:
						col = col.lightened(0.18)   # nervura do meio
					col.a = 1.0
					img.set_pixel(px, py, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ================== MODELO DA ÁRVORE ==================

## Devolve [malha do tronco e galhos, malha da copa].
func _make_tree(seed_: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var H := rng.randf_range(22.0, 28.0)          # altura do tronco até a copa
	var r0 := rng.randf_range(0.42, 0.52)         # raio do tronco no chão
	var lean := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_axis := func(h: float) -> Vector3:
		var t := h / H
		return Vector3(lean.x * t * t + sin(h * 0.21) * 0.08, h, lean.y * t * t + cos(h * 0.17) * 0.08)
	# tronco, com sapopemas na base
	var SEG := 14
	var RINGS := 22
	var fin_phase := rng.randf() * TAU
	var fins := 5
	for ri in RINGS + 1:
		var h := H * pow(float(ri) / RINGS, 1.35)
		var c: Vector3 = trunk_axis.call(h)
		var taper := lerpf(r0, r0 * 0.42, h / H)
		var flare := 1.0 + 0.55 * exp(-h * 1.4)
		for si in SEG + 1:
			var a := TAU * si / SEG
			var fin := pow(maxf(0.0, cos(a * fins + fin_phase)), 8.0) * maxf(0.0, 1.0 - h / 1.8) * 1.1
			var r := taper * flare + fin
			var pos := c + Vector3(cos(a) * r, 0, sin(a) * r)
			st.set_normal(Vector3(cos(a), 0.15, sin(a)).normalized())
			st.set_uv(Vector2(float(si) / SEG * 2.0, h / 3.0))
			st.add_vertex(pos)
	for ri in RINGS:
		for si in SEG:
			var a := ri * (SEG + 1) + si
			var b := a + SEG + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	var vbase := (RINGS + 1) * (SEG + 1)

	# galhos grossos no alto, saindo do tronco para fora e para cima
	var tips: Array[Vector3] = []
	var nb := rng.randi_range(5, 7)
	for bi in nb:
		var h0 := H * rng.randf_range(0.66, 0.9)
		var start: Vector3 = trunk_axis.call(h0)
		var ang := TAU * bi / nb + rng.randf_range(-0.3, 0.3)
		var up := rng.randf_range(0.55, 0.9)
		var length := rng.randf_range(4.5, 7.0)
		var dirv := Vector3(cos(ang), up, sin(ang)).normalized()
		var tip := start + dirv * length
		tips.append(tip)
		vbase = _branch(st, vbase, start, tip, r0 * 0.38, r0 * 0.12)
		# um galho menor saindo do meio
		var mid := start.lerp(tip, 0.55)
		var side := Vector3(cos(ang + 0.9), up + 0.2, sin(ang + 0.9)).normalized()
		var tip2 := mid + side * length * 0.45
		tips.append(tip2)
		vbase = _branch(st, vbase, mid, tip2, r0 * 0.16, r0 * 0.06)
	tips.append(trunk_axis.call(H))
	st.generate_tangents()
	var trunk := st.commit()

	# copa: cachos de folhas (cartões cruzados) em volta da ponta dos galhos e em cima
	var cs := SurfaceTool.new()
	cs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top: Vector3 = trunk_axis.call(H)
	var crown_c := top + Vector3(0, 2.0, 0)
	var crown_r := Vector3(rng.randf_range(7.0, 9.0), rng.randf_range(3.2, 4.2), rng.randf_range(7.0, 9.0))
	var ci := 0
	for k in 95:
		var p: Vector3
		if k < tips.size() * 5:
			var tip: Vector3 = tips[k % tips.size()]
			p = tip + Vector3(rng.randf_range(-2.2, 2.2), rng.randf_range(-0.6, 1.6), rng.randf_range(-2.2, 2.2))
		else:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 1), rng.randf_range(-1, 1)).normalized()
			p = crown_c + d * crown_r * rng.randf_range(0.55, 1.0)
		var outward := (p - crown_c) / crown_r
		outward = (outward + Vector3(0, 0.6, 0)).normalized()
		var size := rng.randf_range(2.6, 3.8)
		var tint := Color(1, 1, 1).lerp(Color(0.8, 0.95, 0.75), rng.randf())
		for q in 2:
			var yaw := rng.randf() * TAU + q * PI * 0.5
			var tilt := rng.randf_range(-0.5, 0.5)
			var bs := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
			var ax := bs.x * size * 0.5
			var ay := bs.y * size * 0.5
			var quad := [p - ax - ay, p + ax - ay, p + ax + ay, p - ax + ay]
			var uvq := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			for vi in 4:
				cs.set_color(tint)
				cs.set_normal(outward)
				cs.set_uv(uvq[vi])
				cs.add_vertex(quad[vi])
			cs.add_index(ci)
			cs.add_index(ci + 1)
			cs.add_index(ci + 2)
			cs.add_index(ci)
			cs.add_index(ci + 2)
			cs.add_index(ci + 3)
			ci += 4
	var crown := cs.commit()
	return [trunk, crown]


## Um galho como um cilindro afinando, de 'a' até 'b'. Devolve o próximo índice livre.
func _branch(st: SurfaceTool, vbase: int, a: Vector3, b: Vector3, ra: float, rb: float) -> int:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(axis).normalized()
	var SEG := 7
	var RINGS := 4
	for ri in RINGS + 1:
		var t := float(ri) / RINGS
		var c := a.lerp(b, t) + up * sin(t * PI) * 0.25
		var r := lerpf(ra, rb, t)
		for si in SEG + 1:
			var ang := TAU * si / SEG
			var n := (side * cos(ang) + up * sin(ang)).normalized()
			st.set_normal(n)
			st.set_uv(Vector2(float(si) / SEG, t * 2.0))
			st.add_vertex(c + n * r)
	for ri in RINGS:
		for si in SEG:
			var i0 := vbase + ri * (SEG + 1) + si
			var i1 := i0 + SEG + 1
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i0 + 1)
			st.add_index(i0 + 1)
			st.add_index(i1)
			st.add_index(i1 + 1)
	return vbase + (RINGS + 1) * (SEG + 1)
