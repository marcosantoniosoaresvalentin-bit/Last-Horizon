extends RefCounted
## Geometria de galho com casca de verdade (o mesmo material das árvores), pontas
## cortadas com a madeira clara e, se pedir, o entalhe do machado.
##
## Duas superfícies: 0 = casca (UV para a textura de casca), 1 = madeira (cor nos vértices).
## Use com Arvores.bark_material() na superfície 0 e um material de cor de vértice na 1.

const WOOD_LIGHT := Color(0.5, 0.38, 0.23)
const WOOD_DARK := Color(0.36, 0.25, 0.14)


## Centro do galho do modelo da árvore no ponto t (0 a 1), igual ao Arvores._cyl.
static func branch_center(a: Vector3, b: Vector3, t: float, bend := 0.25) -> Vector3:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(axis).normalized()
	return a.lerp(b, t) + up * sin(t * PI) * bend


class Builder:
	var bark := SurfaceTool.new()
	var wood := SurfaceTool.new()
	var _has_wood := false
	var _has_bark := false

	func _init() -> void:
		bark.begin(Mesh.PRIMITIVE_TRIANGLES)
		wood.begin(Mesh.PRIMITIVE_TRIANGLES)

	## Tubo por uma linha de pontos, com raio em cada ponto.
	## caps: [ponta inicial, ponta final] (true = mostra a madeira cortada).
	## notch: {i (índice do ponto), dir (lado de onde vem o machado), depth (0 a 1), w (largura em pontos)}
	func tube(pts: Array, radii: Array, caps := [false, false], notch := {}, seg := 9) -> void:
		var n := pts.size()
		if n < 2:
			return
		var rings := []
		var vlen := 0.0
		var prev_side := Vector3.ZERO
		for k in n:
			var p: Vector3 = pts[k]
			var d: Vector3
			if k == 0:
				d = (pts[1] - pts[0]) as Vector3
			elif k == n - 1:
				d = (pts[n - 1] - pts[n - 2]) as Vector3
			else:
				d = (pts[k + 1] - pts[k - 1]) as Vector3
			d = d.normalized()
			var side: Vector3
			if prev_side == Vector3.ZERO:
				side = d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
			else:
				side = (prev_side - d * prev_side.dot(d)).normalized()
			prev_side = side
			var up := side.cross(d).normalized()
			if k > 0:
				vlen += ((pts[k] as Vector3) - (pts[k - 1] as Vector3)).length()
			var r := float(radii[k])
			var ring := []
			for si in seg + 1:
				var a := TAU * si / seg
				var o := side * cos(a) + up * sin(a)
				var cut := 0.0
				if not notch.is_empty():
					var dk := absf(float(k) - float(notch.i))
					var w := float(notch.get("w", 1.0))
					if dk <= w:
						var facing := o.dot(notch.dir as Vector3)
						if facing > 0.05:
							cut = float(notch.depth) * (1.0 - dk / (w + 0.5)) * smoothstep(0.05, 0.75, facing)
				ring.append([p + o * r * (1.0 - cut), Vector2(float(si) / seg, vlen / 0.9), o, cut])
			rings.append(ring)
		for k in n - 1:
			for si in seg:
				var q := [rings[k][si], rings[k][si + 1], rings[k + 1][si + 1], rings[k + 1][si]]
				var deep := (float(q[0][3]) + float(q[1][3]) + float(q[2][3]) + float(q[3][3])) * 0.25
				if deep > 0.06:
					_has_wood = true
					var col := WOOD_LIGHT.lerp(WOOD_DARK, clampf(deep, 0.0, 1.0) * 0.6)
					_quad_wood([q[0][0], q[1][0], q[2][0], q[3][0]], (q[0][2] as Vector3), col)
				else:
					_quad_bark(q)
		for e in 2:
			if not caps[e]:
				continue
			var ring: Array = rings[0] if e == 0 else rings[n - 1]
			var c: Vector3 = pts[0] if e == 0 else pts[n - 1]
			var out: Vector3 = ((pts[0] - pts[1]) if e == 0 else (pts[n - 1] - pts[n - 2])).normalized()
			_has_wood = true
			for si in seg:
				var a0: Vector3 = ring[si][0]
				var a1: Vector3 = ring[si + 1][0]
				var mid0 := c.lerp(a0, 0.55)
				var mid1 := c.lerp(a1, 0.55)
				_tri_wood(c, mid0, mid1, out, WOOD_DARK.lerp(WOOD_LIGHT, 0.5))
				_tri_wood(mid0, a0, a1, out, WOOD_LIGHT)
				_tri_wood(mid0, a1, mid1, out, WOOD_LIGHT)

	## Tubo fino colorido (cipó, amarração), na superfície de cor dos vértices.
	func color_tube(pts: Array, radii: Array, col: Color, seg := 5) -> void:
		_has_wood = true
		for k in pts.size() - 1:
			var a: Vector3 = pts[k]
			var b: Vector3 = pts[k + 1]
			var d := (b - a).normalized()
			var s1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
			var s2 := d.cross(s1).normalized()
			var ra := float(radii[k])
			var rb := float(radii[k + 1])
			for j in seg:
				var a0 := TAU * j / seg
				var a1 := TAU * (j + 1) / seg
				var o0 := s1 * cos(a0) + s2 * sin(a0)
				var o1 := s1 * cos(a1) + s2 * sin(a1)
				var c := col.darkened(0.1 * (j % 2))
				_quad_wood([a + o0 * ra, a + o1 * ra, b + o1 * rb, b + o0 * rb], o0 + o1, c)

	func _quad_bark(q: Array) -> void:
		var out: Vector3 = (q[0][2] as Vector3) + (q[2][2] as Vector3)
		var tris := [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]
		for t in tris:
			var a: Vector3 = t[0][0]
			var b: Vector3 = t[1][0]
			var c: Vector3 = t[2][0]
			var order := [t[0], t[1], t[2]]
			if (c - a).cross(b - a).dot(out) < 0.0:
				order = [t[0], t[2], t[1]]
			_has_bark = true
			for v in order:
				bark.set_normal(v[2])
				bark.set_uv(v[1])
				bark.add_vertex(v[0])

	func _quad_wood(vs: Array, out: Vector3, col: Color) -> void:
		_tri_wood(vs[0], vs[1], vs[2], out, col)
		_tri_wood(vs[0], vs[2], vs[3], out, col)

	func _tri_wood(a: Vector3, b: Vector3, c: Vector3, out: Vector3, col: Color) -> void:
		wood.set_color(col)
		if (c - a).cross(b - a).dot(out) < 0.0:
			var t := b
			b = c
			c = t
		wood.add_vertex(a)
		wood.add_vertex(b)
		wood.add_vertex(c)

	func commit() -> ArrayMesh:
		if not _has_bark:
			# superfície 0 tem que ser a casca: um triângulo vazio segura o lugar
			for k in 3:
				bark.set_uv(Vector2.ZERO)
				bark.set_normal(Vector3.UP)
				bark.add_vertex(Vector3.ZERO)
		var mesh := bark.commit()
		if _has_wood:
			wood.generate_normals()
			mesh = wood.commit(mesh)
		return mesh

	func has_wood() -> bool:
		return _has_wood


## Pontos de um galho torto, de a até b, com raios afinando de ra para rb.
static func bent_points(a: Vector3, b: Vector3, ra: float, rb: float, n: int, wobble: float, seed_: int) -> Array:
	var pts := []
	var radii := []
	var d := (b - a)
	var side := d.cross(Vector3.UP)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(d.normalized()).normalized()
	for k in n + 1:
		var t := float(k) / n
		var w := sin(t * PI) * wobble
		var p := a.lerp(b, t) + side * sin(t * 4.0 + seed_ * 1.7) * w + up * cos(t * 3.0 + seed_) * w * 0.6
		pts.append(p)
		radii.append(lerpf(ra, rb, t) * (1.0 + 0.06 * sin(t * 13.0 + seed_)))
	return [pts, radii]


## Material da madeira cortada (cor dos vértices).
static func wood_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
