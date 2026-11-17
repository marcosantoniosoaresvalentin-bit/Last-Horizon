extends RefCounted
## Modelos 3D do balde de madeira e da rodela de tora.
##
## Balde (como o da foto): ripas em pé em volta de um fundo redondo (a rodela),
## um pouco mais largo em cima, apertadas com três pares de aros de cipó.
## Duas ripas mais altas com um furo seguram a alça de cipó trançado.
## Medidas em metros; o fundo do balde fica em y = 0.

const STAVES := 18
const H := 0.34            # altura das ripas
const R_BOT := 0.15        # raio embaixo
const R_TOP := 0.175       # raio em cima
const T := 0.016           # grossura das ripas
const EAR := 0.09          # quanto as duas ripas da alça passam da boca

static var _cache: Mesh
static var _mat: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.92
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat


static func _r_at(y: float) -> float:
	return lerpf(R_BOT, R_TOP, clampf(y / H, 0.0, 1.0))


static func mesh() -> Mesh:
	if _cache:
		return _cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var gap := 0.006           # fresta entre as ripas (dá para ver a madeira de dentro)
	for k in STAVES:
		var a0 := TAU * k / STAVES + gap / R_BOT * 0.5
		var a1 := TAU * (k + 1) / STAVES - gap / R_BOT * 0.5
		var ear := k == 0 or k == STAVES / 2
		var top := H + (EAR if ear else rng.randf_range(-0.012, 0.008))
		var bot := rng.randf_range(-0.012, 0.0)
		var tone := rng.randf_range(-0.05, 0.05)
		var outside := Color(0.19 + tone * 0.6, 0.155 + tone * 0.6, 0.115 + tone * 0.5)
		var inside := outside.darkened(0.35)
		_stave(st, a0, a1, bot, top, outside, inside, ear)
	# fundo (a rodela) um pouco acima da base das ripas
	_disc(st, Vector3(0, 0.025, 0), R_BOT - 0.004, 0.025, Color(0.42, 0.32, 0.21), Color(0.3, 0.22, 0.14))
	# aros de cipó: dois em cima, dois no meio, dois embaixo (meio tortos, como na foto)
	for y in [0.3, 0.27, 0.19, 0.16, 0.06, 0.035]:
		_hoop(st, y, rng.randf_range(-0.012, 0.012), 0.0085, Color(0.4, 0.3, 0.17), rng)
	# alça de cipó trançado passando pelos furos das duas ripas altas
	_handle(st)
	st.generate_normals()
	_cache = st.commit()
	return _cache


static func _stave(st: SurfaceTool, a0: float, a1: float, y0: float, y1: float, out_c: Color, in_c: Color, ear: bool) -> void:
	var n := 3
	for i in n:
		var aa := lerpf(a0, a1, float(i) / n)
		var ab := lerpf(a0, a1, float(i + 1) / n)
		var top_a := y1
		var top_b := y1
		if ear:
			# a ponta da ripa da alça é arredondada
			top_a = y1 - absf(float(i) / n - 0.5) * 0.04
			top_b = y1 - absf(float(i + 1) / n - 0.5) * 0.04
		var ra0 := _r_at(y0)
		var ra1 := _r_at(y1)
		var o00 := Vector3(cos(aa) * ra0, y0, sin(aa) * ra0)
		var o01 := Vector3(cos(aa) * ra1, top_a, sin(aa) * ra1)
		var o10 := Vector3(cos(ab) * ra0, y0, sin(ab) * ra0)
		var o11 := Vector3(cos(ab) * ra1, top_b, sin(ab) * ra1)
		var ia := Vector3(cos(aa), 0, sin(aa)) * T
		var ib := Vector3(cos(ab), 0, sin(ab)) * T
		# veio da madeira: faixas um pouco mais escuras
		var g := 0.04 if i == 1 else 0.0
		_quad(st, o00, o10, o11, o01, out_c.darkened(g))
		_quad(st, o00 - ia, o01 - ia, o11 - ib, o10 - ib, in_c)
		_quad(st, o01, o11, o11 - ib, o01 - ia, out_c.lightened(0.12))   # topo (madeira cortada)
		_quad(st, o00, o00 - ia, o10 - ib, o10, in_c)
		if i == 0:
			_quad(st, o00, o01, o01 - ia, o00 - ia, in_c.darkened(0.2))
		if i == n - 1:
			_quad(st, o10, o10 - ib, o11 - ib, o11, in_c.darkened(0.2))


static func _hoop(st: SurfaceTool, y: float, tilt: float, r: float, col: Color, rng: RandomNumberGenerator) -> void:
	var seg := 40
	var pts := []
	for i in seg + 1:
		var a := TAU * i / seg
		var yy := y + sin(a) * tilt
		var rr := _r_at(yy) + r * 0.9
		pts.append(Vector3(cos(a) * rr, yy, sin(a) * rr))
	for i in seg:
		var c := col.darkened(0.05 if (i / 3) % 2 == 0 else 0.0)
		_tube(st, pts[i], pts[i + 1], r, r, c)
	# a ponta do cipó amarrada, sobrando um pouco
	var a := rng.randf() * TAU
	var p0 := Vector3(cos(a) * (_r_at(y) + r), y, sin(a) * (_r_at(y) + r))
	_tube(st, p0, p0 + Vector3(-sin(a), -0.6, cos(a)).normalized() * 0.05, r * 0.8, r * 0.5, col.darkened(0.15))


## Alça: três fios de cipó trançados, num arco que sai do furo de uma ripa alta para a outra.
static func _handle(st: SurfaceTool) -> void:
	var y0 := H + EAR - 0.035
	var rr := R_TOP + T * 0.5
	var A := Vector3(rr, y0, 0)
	var B := Vector3(-rr, y0, 0)
	var rise := 0.2
	var seg := 48
	var center := []
	for i in seg + 1:
		var t := float(i) / seg
		var p := A.lerp(B, t)
		p.y += sin(t * PI) * rise
		center.append(p)
	for strand in 3:
		var prev := Vector3.ZERO
		for i in seg + 1:
			var t := float(i) / seg
			var c: Vector3 = center[i]
			var tang: Vector3 = (center[mini(i + 1, seg)] - center[maxi(i - 1, 0)]).normalized()
			var side := Vector3(0, 0, 1)
			var nrm := tang.cross(side).normalized()
			var ph := t * TAU * 7.0 + strand * TAU / 3.0
			var p := c + (side * cos(ph) + nrm * sin(ph)) * 0.0065
			if i > 0:
				var col := Color(0.36, 0.27, 0.15).darkened(0.12 * strand)
				_tube(st, prev, p, 0.0055, 0.0055, col)
			prev = p
	# o laço por dentro do furo de cada ripa
	for e in [A, B]:
		var out := Vector3(signf(e.x), 0, 0)
		_tube(st, e - out * 0.03, e + out * 0.025, 0.008, 0.008, Color(0.32, 0.24, 0.14))
		_tube(st, e + out * 0.025, e + out * 0.02 + Vector3(0, -0.035, 0), 0.007, 0.006, Color(0.32, 0.24, 0.14))


## Rodela de tora: cilindro baixinho com casca em volta e madeira com anéis nas faces.
static func rodela_mesh(r: float, th: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_disc(st, Vector3.ZERO, r, th, Color(0.38, 0.28, 0.17), Color(0.22, 0.16, 0.1), true)
	st.generate_normals()
	return st.commit()


static func _disc(st: SurfaceTool, c: Vector3, r: float, th: float, wood: Color, bark: Color, rings := false) -> void:
	var seg := 28
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var w0 := 1.0 + sin(a0 * 3.0) * 0.03
		var w1 := 1.0 + sin(a1 * 3.0) * 0.03
		var p0 := Vector3(cos(a0) * r * w0, 0, sin(a0) * r * w0)
		var p1 := Vector3(cos(a1) * r * w1, 0, sin(a1) * r * w1)
		var top := Vector3(0, th * 0.5, 0)
		# faces de madeira, com anéis (cores em faixas)
		var nr := 4 if rings else 1
		for k in nr:
			var f0 := float(k) / nr
			var f1 := float(k + 1) / nr
			var col := wood.darkened(0.045 * (k % 2)) if rings else wood
			for sgn in [1.0, -1.0]:
				var y: Vector3 = top * sgn
				# serra de pedra: a face fica ondulada, com marcas do vai e vem
				var j := func(a: float, f: float) -> Vector3:
					if not rings:
						return Vector3.ZERO
					return Vector3(0, (sin(a * 5.0 + f * 9.0 + sgn) * 0.5 + sin(f * 23.0 + a * 2.0) * 0.5) * th * 0.22 * f, 0)
				_quad(st, c + y + p0 * f0 + j.call(a0, f0), c + y + p1 * f0 + j.call(a1, f0), c + y + p1 * f1 + j.call(a1, f1), c + y + p0 * f1 + j.call(a0, f1), col if k < nr - 1 or not rings else col.lerp(bark, 0.25))
		# casca em volta
		_quad(st, c - top + p0, c - top + p1, c + top + p1, c + top + p0, bark.darkened(0.08 * (i % 2)))


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	st.set_color(col)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, col: Color) -> void:
	var d := (b - a).normalized()
	var s1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var s2 := d.cross(s1).normalized()
	st.set_color(col)
	var n := 6
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var o0 := s1 * cos(a0) + s2 * sin(a0)
		var o1 := s1 * cos(a1) + s2 * sin(a1)
		for v in [a + o0 * ra, b + o0 * rb, b + o1 * rb, a + o0 * ra, b + o1 * rb, a + o1 * ra]:
			st.add_vertex(v)
