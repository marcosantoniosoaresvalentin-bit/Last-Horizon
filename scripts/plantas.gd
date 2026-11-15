extends RefCounted
## Catálogo de plantas da Amazônia, montadas em 3D direto no código.
## Cor do vértice: RGB é a cor; o alfa diz quanto aquela parte balança com o vento.

# ---------- montador de malhas ----------

class Mesher:
	var st := SurfaceTool.new()

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var card := false
	var uv := Vector2.ZERO

	func v(p: Vector3, c: Color) -> void:
		st.set_color(c)
		st.set_uv(uv)
		st.set_uv2(Vector2(1.0 if card else 0.0, 0.0))
		st.add_vertex(p)

	## Cartões de folhas espalhados na superfície de uma copa (o desenho das folhas é feito no shader).
	func leaf_cards(center: Vector3, radius: Vector3, count: int, size: float, col: Color, sway: float, rng: RandomNumberGenerator) -> void:
		card = true
		for k in count:
			var d := Vector3(rng.randfn(), rng.randfn() * 0.8 + 0.25, rng.randfn()).normalized()
			var p := center + d * radius * rng.randf_range(0.8, 1.08)
			var n := d
			var t1 := n.cross(Vector3(rng.randf() - 0.5, 1.0, rng.randf() - 0.5)).normalized()
			var t2 := n.cross(t1).normalized()
			var sz := size * rng.randf_range(0.75, 1.25)
			var c := col.lightened(rng.randf_range(-0.12, 0.12))
			c = c.darkened(0.3 * clampf(-d.y, 0.0, 1.0))
			c.a = sway
			var a := p - t1 * sz - t2 * sz; var b := p + t1 * sz - t2 * sz
			var cc := p + t1 * sz + t2 * sz; var dd := p - t1 * sz + t2 * sz
			uv = Vector2(0, 0); v(a, c); uv = Vector2(1, 0); v(b, c); uv = Vector2(1, 1); v(cc, c)
			uv = Vector2(0, 0); v(a, c); uv = Vector2(1, 1); v(cc, c); uv = Vector2(0, 1); v(dd, c)
		card = false
		uv = Vector2.ZERO

	func tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
		v(a, ca); v(b, cb); v(c, cc)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, cab: Color, ccd: Color) -> void:
		# a,b embaixo; c,d em cima
		tri(a, b, c, cab, cab, ccd)
		tri(a, c, d, cab, ccd, ccd)

	## Tubo por uma lista de pontos (tronco, caule, galho).
	func tube(pts: Array, radii: Array, sides: int, col_a: Color, col_b: Color, sway_a: float, sway_b: float) -> void:
		var rings := []
		for k in pts.size():
			var p: Vector3 = pts[k]
			var dir: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
			var side := dir.cross(Vector3.FORWARD if absf(dir.y) > 0.9 else Vector3.UP).normalized()
			var up := side.cross(dir).normalized()
			var ring := []
			for s in sides:
				var a := TAU * s / sides
				ring.append(p + (side * cos(a) + up * sin(a)) * float(radii[k]))
			rings.append(ring)
		for k in pts.size() - 1:
			var t0 := float(k) / (pts.size() - 1)
			var t1 := float(k + 1) / (pts.size() - 1)
			var c0 := col_a.lerp(col_b, t0); c0.a = lerpf(sway_a, sway_b, t0)
			var c1 := col_a.lerp(col_b, t1); c1.a = lerpf(sway_a, sway_b, t1)
			for s in sides:
				var s2 := (s + 1) % sides
				quad(rings[k][s], rings[k][s2], rings[k + 1][s2], rings[k + 1][s], c0, c1)

	## Copa de folhas: esfera irregular.
	func blob(center: Vector3, radius: Vector3, col: Color, sway: float, seed_v: int, rough := 0.28, detail := 1) -> void:
		var verts := _ico(detail)
		for f in range(0, verts.size(), 3):
			var ps := []
			var cs := []
			for k in 3:
				var d: Vector3 = verts[f + k]
				var n := _hash3(d * 7.3 + Vector3(seed_v, seed_v * 0.37, 0))
				var p := center + d * radius * (1.0 + (n - 0.5) * rough * 2.0)
				ps.append(p)
				var c := col.darkened(0.25 * (1.0 - (d.y * 0.5 + 0.5)))   # mais escuro embaixo
				c = c.lightened((n - 0.5) * 0.15)
				c.a = sway
				cs.append(c)
			tri(ps[0], ps[1], ps[2], cs[0], cs[1], cs[2])

	## Esfera pequena (fruta).
	func ball(center: Vector3, r: float, col: Color, sway: float, stretch := 1.0) -> void:
		var verts := _ico(0)
		var c := col
		c.a = sway
		for f in range(0, verts.size(), 3):
			var a: Vector3 = verts[f]; var b: Vector3 = verts[f + 1]; var d: Vector3 = verts[f + 2]
			var s := Vector3(r, r * stretch, r)
			tri(center + a * s, center + b * s, center + d * s, c.darkened(0.15 * (1 - a.y)), c.darkened(0.15 * (1 - b.y)), c.darkened(0.15 * (1 - d.y)))

	## Folha: tira curva que se afina nas pontas.
	func leaf(base: Vector3, dir: Vector3, length: float, width: float, lift: float, droop: float, col: Color, tip: Color, sway: float, segs := 5) -> void:
		dir = dir.normalized()
		var side := dir.cross(Vector3.UP).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var prev_l: Vector3; var prev_r: Vector3; var prev_c: Color
		for k in segs + 1:
			var t := float(k) / segs
			var p := base + dir * length * t + Vector3.UP * (lift * sin(t * PI * 0.5) * length - droop * t * t * length)
			var w := width * sin(clampf(t * 1.1, 0.0, 1.0) * PI) * 0.5 + 0.004
			var l := p - side * w
			var r := p + side * w + Vector3.UP * w * 0.25
			var c := col.lerp(tip, t)
			c.a = sway * (0.3 + 0.7 * t)
			if k > 0:
				quad(prev_l, prev_r, r, l, prev_c, c)
			prev_l = l; prev_r = r; prev_c = c

	## Folha de palmeira: talo arqueado com folíolos pendurados dos dois lados.
	func frond(base: Vector3, dir: Vector3, length: float, droop: float, col: Color, sway: float, leaflets := 14) -> void:
		dir = dir.normalized()
		var side := dir.cross(Vector3.UP).normalized()
		var pts := []
		for k in leaflets + 1:
			var t := float(k) / leaflets
			pts.append(base + dir * length * t + Vector3.UP * (0.35 * sin(t * PI * 0.6) * length - droop * t * t * length))
		var stem := col.darkened(0.3)
		stem.a = sway
		for k in leaflets:
			var t := float(k + 1) / leaflets
			var p: Vector3 = pts[k + 1]
			var ln := lerpf(0.75, 0.25, t) * length * 0.45
			for sgn in [-1.0, 1.0]:
				var tipp: Vector3 = p + side * sgn * ln * 0.55 + Vector3.DOWN * ln * 0.75 + dir * ln * 0.25
				var c := col.lightened(0.08 * sin(k * 1.7))
				c.a = sway * (0.4 + 0.6 * t)
				var ct := c.darkened(0.1); ct.a = sway
				tri(pts[k], p, tipp, c, c, ct)
		# talo central
		for k in leaflets:
			var a: Vector3 = pts[k]; var b: Vector3 = pts[k + 1]
			quad(a - side * 0.03, a + side * 0.03, b + side * 0.02, b - side * 0.02, stem, stem)

	func commit() -> ArrayMesh:
		st.index()
		st.generate_normals()
		return st.commit()

	static func _hash3(p: Vector3) -> float:
		return fposmod(sin(p.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453, 1.0)

	static var _ico_cache := {}
	static func _ico(sub: int) -> Array:
		if _ico_cache.has(sub):
			return _ico_cache[sub]
		var t := (1.0 + sqrt(5.0)) / 2.0
		var vs := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
		var fs := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
			[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
			[6, 2, 10], [8, 6, 7], [9, 8, 1]]
		var tris := []
		for f in fs:
			tris.append_array([vs[f[0]].normalized(), vs[f[1]].normalized(), vs[f[2]].normalized()])
		for s in sub:
			var nt := []
			for i in range(0, tris.size(), 3):
				var a: Vector3 = tris[i]; var b: Vector3 = tris[i + 1]; var c: Vector3 = tris[i + 2]
				var ab := ((a + b) * 0.5).normalized(); var bc := ((b + c) * 0.5).normalized(); var ca := ((c + a) * 0.5).normalized()
				nt.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
			tris = nt
		_ico_cache[sub] = tris
		return tris


# ---------- cores ----------
const BARK := Color(0.33, 0.25, 0.18, 0)
const BARK_LIGHT := Color(0.42, 0.38, 0.32, 0)
const LEAF_DARK := Color(0.12, 0.30, 0.09)
const LEAF := Color(0.20, 0.42, 0.12)
const LEAF_LIGHT := Color(0.32, 0.50, 0.16)


static func _bend_path(base: Vector3, height: float, bend: Vector3, segs: int) -> Array:
	var pts := []
	for k in segs + 1:
		var t := float(k) / segs
		pts.append(base + Vector3.UP * height * t + bend * t * t)
	return pts


# ---------- árvores ----------

## Açaizeiro: palmeira fina e alta, com cachos de açaí roxo.
static func acai(rng: RandomNumberGenerator) -> ArrayMesh:
	var m := Mesher.new()
	var h := rng.randf_range(9.0, 14.0)
	var bend := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 1.2
	var pts := _bend_path(Vector3.ZERO, h, bend, 7)
	var radii := []
	for k in pts.size(): radii.append(lerpf(0.13, 0.09, float(k) / 7))
	m.tube(pts, radii, 6, Color(0.42, 0.40, 0.33, 0), Color(0.35, 0.42, 0.25, 0.25), 0.0, 0.25)
	var top: Vector3 = pts[-1]
	for k in 9:
		var a := TAU * k / 9 + rng.randf() * 0.3
		m.frond(top, Vector3(cos(a), rng.randf_range(0.1, 0.5), sin(a)), rng.randf_range(2.6, 3.4), 0.55, LEAF.lerp(LEAF_LIGHT, rng.randf() * 0.5), 1.0, 12)
	for k in 3:
		var a := TAU * k / 3 + 0.5
		var c := top + Vector3(cos(a) * 0.35, -0.7, sin(a) * 0.35)
		m.ball(c, 0.32, Color(0.22, 0.06, 0.20), 0.4, 1.4)   # cacho de açaí
		m.ball(c + Vector3(0, -0.25, 0), 0.24, Color(0.18, 0.04, 0.17), 0.4, 1.3)
	return m.commit()


## Castanheira: tronco reto e altíssimo, copa larga lá em cima, ouriços.
static func castanheira(rng: RandomNumberGenerator) -> ArrayMesh:
	var m := Mesher.new()
	var h := rng.randf_range(20.0, 28.0)
	var pts := _bend_path(Vector3.ZERO, h, Vector3(rng.randf_range(-.6, .6), 0, rng.randf_range(-.6, .6)), 6)
	m.tube(pts, [0.9, 0.7, 0.62, 0.55, 0.48, 0.4, 0.3], 8, BARK_LIGHT, BARK_LIGHT.darkened(0.2), 0.0, 0.05)
	var top: Vector3 = pts[-1]
	for k in 4:  # galhos
		var a := TAU * k / 4 + rng.randf()
		var end := top + Vector3(cos(a) * 4.5, 2.0, sin(a) * 4.5)
		m.tube([top + Vector3(0, -2, 0), top + Vector3(cos(a) * 2, 0.8, sin(a) * 2), end], [0.35, 0.25, 0.15], 5, BARK, BARK, 0.05, 0.15)
		m.blob(end + Vector3(0, 0.6, 0), Vector3(3.0, 1.8, 3.0), LEAF_DARK.darkened(0.3), 0.3, rng.randi() % 1000, 0.3, 1)
		m.leaf_cards(end + Vector3(0, 0.6, 0), Vector3(3.4, 2.1, 3.4), 70, 0.9, LEAF_DARK.lerp(LEAF, rng.randf()), 0.35, rng)
	m.blob(top + Vector3(0, 2.6, 0), Vector3(3.8, 2.2, 3.8), LEAF_DARK.darkened(0.3), 0.25, rng.randi() % 1000, 0.3, 1)
	m.leaf_cards(top + Vector3(0, 2.6, 0), Vector3(4.3, 2.5, 4.3), 90, 1.0, LEAF_DARK.lerp(LEAF, 0.4), 0.3, rng)
	for k in 6:
		var a := rng.randf() * TAU
		m.ball(top + Vector3(cos(a) * 3.5, 0.4, sin(a) * 3.5), 0.22, Color(0.36, 0.24, 0.12), 0.3)
	return m.commit()


## Cupuaçuzeiro: árvore baixa e cheia, com cupuaçus marrons pendurados.
static func cupuacu(rng: RandomNumberGenerator) -> ArrayMesh:
	var m := Mesher.new()
	var h := rng.randf_range(3.0, 4.5)
	var pts := _bend_path(Vector3.ZERO, h, Vector3(rng.randf_range(-.4, .4), 0, rng.randf_range(-.4, .4)), 4)
	m.tube(pts, [0.2, 0.17, 0.15, 0.12, 0.1], 6, BARK, BARK, 0.0, 0.1)
	var top: Vector3 = pts[-1]
	for k in 5:
		var a := TAU * k / 5 + rng.randf()
		var off := Vector3(cos(a) * 1.6, rng.randf_range(-0.5, 1.0), sin(a) * 1.6)
		m.blob(top + off, Vector3(1.5, 1.2, 1.5), LEAF_DARK.darkened(0.25), 0.35, rng.randi() % 1000)
		m.leaf_cards(top + off, Vector3(1.8, 1.4, 1.8), 34, 0.55, LEAF.lerp(LEAF_DARK, rng.randf()), 0.45, rng)
	for k in 7:
		var a := rng.randf() * TAU
		var p := top + Vector3(cos(a) * 1.9, -1.4 + rng.randf() * 0.4, sin(a) * 1.9)
		m.ball(p, 0.13, Color(0.42, 0.29, 0.16), 0.3, 1.6)
	return m.commit()


## Bananeira: caule grosso e folhas enormes, com cacho de banana.
static func bananeira(rng: RandomNumberGenerator) -> ArrayMesh:
	var m := Mesher.new()
	var h := rng.randf_range(2.6, 3.6)
	var pts := _bend_path(Vector3.ZERO, h, Vector3.ZERO, 3)
	m.tube(pts, [0.22, 0.19, 0.16, 0.14], 7, Color(0.36, 0.42, 0.22, 0), Color(0.42, 0.50, 0.24, 0.1), 0.0, 0.15)
	var top: Vector3 = pts[-1]
	for k in 8:
		var a := TAU * k / 8 + rng.randf() * 0.4
		var leaf_col := Color(0.26, 0.48, 0.14).lerp(Color(0.40, 0.42, 0.18), rng.randf() * 0.35)
		m.leaf(top, Vector3(cos(a), rng.randf_range(0.4, 1.0), sin(a)), rng.randf_range(2.0, 2.7), 0.62, 0.5, 0.6, leaf_col, leaf_col.lightened(0.1), 1.0, 7)
	var bunch := top + Vector3(0.45, -0.6, 0)
	m.tube([top + Vector3(0.1, 0, 0), bunch + Vector3(0, 0.4, 0), bunch], [0.04, 0.04, 0.03], 4, Color(0.35, 0.4, 0.2, 0), Color(0.35, 0.4, 0.2, 0), 0.2, 0.3)
	for k in 5:
		m.ball(bunch + Vector3(0, -k * 0.13, 0), 0.2 - k * 0.02, Color(0.62, 0.66, 0.18).lerp(Color(0.85, 0.75, 0.2), rng.randf() * 0.5), 0.3, 0.6)
	m.ball(bunch + Vector3(0, -0.85, 0), 0.1, Color(0.45, 0.12, 0.2), 0.4, 1.6)  # coração da bananeira
	return m.commit()


## Samaúma: a gigante da floresta, com sapopemas (raízes em tábua) e copa em guarda-chuva.
static func samauma(rng: RandomNumberGenerator) -> ArrayMesh:
	var m := Mesher.new()
	var h := rng.randf_range(26.0, 34.0)
	var pts := _bend_path(Vector3.ZERO, h, Vector3.ZERO, 6)
	m.tube(pts, [1.5, 1.1, 0.95, 0.85, 0.75, 0.6, 0.45], 9, Color(0.55, 0.52, 0.46, 0), Color(0.48, 0.45, 0.40, 0), 0.0, 0.03)
	for k in 6:  # sapopemas
		var a := TAU * k / 6 + rng.randf() * 0.4
		var d := Vector3(cos(a), 0, sin(a))
		m.quad(d * 1.0 + Vector3(0, -0.2, 0), d * 4.0 + Vector3(0, -0.2, 0), d * 1.0 + Vector3(0, 5.0, 0), d * 1.0 + Vector3(0, 5.0, 0), BARK_LIGHT, BARK_LIGHT)
		var s := d.cross(Vector3.UP) * 0.12
		m.quad(d * 1.0 + s + Vector3(0, -0.2, 0), d * 4.0 + s + Vector3(0, -0.2, 0), d * 1.0 + s + Vector3(0, 5.0, 0), d * 1.0 + s + Vector3(0, 5.0, 0), BARK_LIGHT, BARK_LIGHT)
	var top: Vector3 = pts[-1]
	for k in 6:
		var a := TAU * k / 6 + rng.randf()
		var end := top + Vector3(cos(a) * 8.0, 1.5, sin(a) * 8.0)
		m.tube([top + Vector3(0, -3, 0), top + Vector3(cos(a) * 4, 0.5, sin(a) * 4), end], [0.5, 0.35, 0.2], 5, BARK_LIGHT, BARK_LIGHT, 0.0, 0.1)
		m.blob(end + Vector3(0, 1.0, 0), Vector3(3.6, 1.5, 3.6), LEAF_DARK.darkened(0.3), 0.25, rng.randi() % 1000, 0.3, 1)
		m.leaf_cards(end + Vector3(0, 1.0, 0), Vector3(4.0, 1.75, 4.0), 70, 0.95, LEAF.lerp(LEAF_DARK, rng.randf()), 0.3, rng)
	m.blob(top + Vector3(0, 2.0, 0), Vector3(4.3, 1.9, 4.3), LEAF_DARK.darkened(0.3), 0.2, rng.randi() % 1000)
	m.leaf_cards(top + Vector3(0, 2.0, 0), Vector3(4.8, 2.2, 4.8), 90, 1.0, LEAF_DARK.lerp(LEAF, 0.3), 0.25, rng)
	return m.commit()


# ---------- mato ----------

## Touceira de capim.
static func capim(rng: RandomNumberGenerator, tall: bool) -> ArrayMesh:
	var m := Mesher.new()
	var n := 9 if tall else 12
	for k in n:
		var a := rng.randf() * TAU
		var r := rng.randf() * 0.28
		var base := Vector3(cos(a) * r, -0.05, sin(a) * r)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.15, 0.5)
		var h := rng.randf_range(0.5, 1.0) if tall else rng.randf_range(0.18, 0.38)
		var w := 0.035 if tall else 0.05
		var side := Vector3(-sin(a), 0, cos(a)) * w
		var c0 := Color(0.10, 0.20, 0.05, 0.0)
		var tip := Color(0.42, 0.55, 0.18).lerp(Color(0.55, 0.52, 0.25), rng.randf() * (0.6 if tall else 0.3))
		var mid := c0.lerp(tip, 0.6); mid.a = 0.4
		tip.a = 1.0
		var p1 := base + Vector3.UP * h * 0.5 + lean * h * 0.3
		var p2 := base + Vector3.UP * h + lean * h
		m.quad(base - side, base + side, p1 + side * 0.7, p1 - side * 0.7, c0, mid)
		m.tri(p1 - side * 0.7, p1 + side * 0.7, p2, mid, mid, tip)
	return m.commit()


## Samambaia: folhas arqueadas saindo do chão.
static func samambaia(rng: RandomNumberGenerator) -> ArrayMesh:
	var m := Mesher.new()
	for k in 9:
		var a := TAU * k / 9 + rng.randf() * 0.4
		m.frond(Vector3.ZERO, Vector3(cos(a), 0.9, sin(a)), rng.randf_range(0.9, 1.3), 0.9, Color(0.20, 0.42, 0.12), 0.8, 10)
	return m.commit()


## Helicônia: folhas largas e flores vermelhas e amarelas em zigue-zague.
static func heliconia(rng: RandomNumberGenerator) -> ArrayMesh:
	var m := Mesher.new()
	for k in 5:
		var a := TAU * k / 5 + rng.randf()
		var stem_top := Vector3(cos(a) * 0.2, rng.randf_range(1.0, 1.6), sin(a) * 0.2)
		m.tube([Vector3(cos(a) * 0.1, 0, sin(a) * 0.1), stem_top], [0.025, 0.02], 4, Color(0.2, 0.35, 0.1, 0), Color(0.2, 0.35, 0.1, 0.5), 0.0, 0.5)
		m.leaf(stem_top, Vector3(cos(a), 0.5, sin(a)), rng.randf_range(0.8, 1.1), 0.32, 0.4, 0.5, Color(0.17, 0.40, 0.10), Color(0.25, 0.48, 0.14), 0.9, 5)
	for k in 2:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * 0.25, 1.3, sin(a) * 0.25)
		for b in 5:
			var red := Color(0.85, 0.12, 0.08); red.a = 0.6
			var yel := Color(0.95, 0.75, 0.1); yel.a = 0.6
			var q := p + Vector3(0, -b * 0.13, 0)
			var sgn := 1.0 if b % 2 == 0 else -1.0
			m.tri(q, q + Vector3(0.18 * sgn, -0.02, 0.04), q + Vector3(0, -0.14, 0), red, yel, red)
	return m.commit()


## Arbusto de folhas.
static func arbusto(rng: RandomNumberGenerator) -> ArrayMesh:
	var m := Mesher.new()
	for k in 3:
		var off := Vector3(rng.randf_range(-.5, .5), rng.randf_range(0.5, 0.9), rng.randf_range(-.5, .5))
		m.blob(off, Vector3(0.6, 0.5, 0.6), LEAF_DARK.darkened(0.2), 0.5, rng.randi() % 1000, 0.35)
		m.leaf_cards(off, Vector3(0.75, 0.6, 0.75), 16, 0.32, LEAF.lerp(LEAF_LIGHT, rng.randf() * 0.5), 0.5, rng)
	return m.commit()


## Taioba / costela-de-adão: folhas largas em forma de coração.
static func folhagem(rng: RandomNumberGenerator) -> ArrayMesh:
	var m := Mesher.new()
	for k in 6:
		var a := TAU * k / 6 + rng.randf() * 0.5
		var stem := Vector3(cos(a) * 0.35, rng.randf_range(0.5, 0.8), sin(a) * 0.35)
		m.tube([Vector3.ZERO, stem], [0.02, 0.015], 4, Color(0.2, 0.36, 0.12, 0), Color(0.2, 0.36, 0.12, 0.4), 0.0, 0.4)
		m.leaf(stem, Vector3(cos(a), 0.2, sin(a)), rng.randf_range(0.6, 0.85), 0.55, 0.3, 0.7, Color(0.12, 0.34, 0.08), Color(0.2, 0.44, 0.12), 0.9, 5)
	return m.commit()
