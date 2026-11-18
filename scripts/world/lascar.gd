extends RefCounted
## Modelar pedra (lascar). A pedra é uma "lente": o contorno visto de cima (raio em
## cada ângulo) e a altura da face de cima e da face de baixo em anéis do centro até a
## beira. Cada batida no lugar certo solta uma lasca: o contorno e as faces ali perto
## descem na direção do formato da ferramenta (sem nunca passar dele), dos dois lados,
## como quem vira a pedra. No fim fica a pedra de machado, a lâmina de cavadeira ou a
## lâmina de serra, com o fio fino e cortante.
##
## Espaço da pedra (tamanho 1): X = comprimento, Y = para cima, Z = largura.
## Estado: PackedFloat32Array com [contorno N] + [cima (R+1) x N] + [baixo (R+1) x N].

const KINDS := {
	"pedra_machado": {"spots": 8, "nome": "Pedra de Machado"},
	"pedra_cavadeira": {"spots": 9, "nome": "Lâmina de Cavadeira"},
	"lamina_serra": {"spots": 12, "nome": "Lâmina de Serra"},
	"pedra_pa": {"spots": 10, "nome": "Lâmina de Pá"},
	"cunha": {"spots": 9, "nome": "Cunha de Pedra"},
	"pedra_marreta": {"spots": 7, "nome": "Pedra de Marreta"},
}
const N := 48                   # ângulos do contorno
const R := 5                    # anéis do centro até a beira
const SIZE := N + 2 * (R + 1) * N


static func _rho(k: int) -> float:
	return float(k) / R


static func _ang(j: int) -> float:
	return TAU * j / N


static func _ti(k: int, j: int) -> int:
	return N + k * N + ((j % N) + N) % N


static func _bi(k: int, j: int) -> int:
	return N + (R + 1) * N + k * N + ((j % N) + N) % N


# ================== PEDRA CRUA ==================

## Pedra crua do chão: arredondada, meio achatada, com calombos (cada uma diferente).
static func rock(seed_: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var st := PackedFloat32Array()
	st.resize(SIZE)
	var ax := rng.randf_range(0.55, 0.64)
	var az := rng.randf_range(0.42, 0.52)
	# contorno: elipse com calombos grandes e lascas pequenas (pedra de rio meio quebrada)
	var harm := []
	for k in 7:
		harm.append([rng.randf() * TAU, rng.randf_range(0.015, 0.06) / (1.0 + k * 0.35), k + 2])
	for j in N:
		var a := _ang(j)
		var r := 1.0 / sqrt(pow(cos(a) / ax, 2) + pow(sin(a) / az, 2))
		for hm in harm:
			r += float(hm[1]) * cos((a - float(hm[0])) * int(hm[2]))
		r *= 1.0 + rng.randf_range(-0.02, 0.02)
		st[j] = r
	# cima abaulado e irregular (faces e quinas), embaixo mais chato (assentado no chão)
	var ht := rng.randf_range(0.24, 0.32)
	var hb := rng.randf_range(0.1, 0.15)
	var tilt := Vector2(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.06, 0.06))
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	for k in R + 1:
		var rho := _rho(k)
		var prof := pow(maxf(0.0, 1.0 - rho * rho), 0.5)
		for j in N:
			var a := _ang(j)
			var x := cos(a) * rho
			var z := sin(a) * rho
			var bump := 1.0 + 0.16 * sin(a * 3.0 + float(ph[0])) * rho + 0.08 * sin(a * 7.0 + float(ph[1])) * rho \
				+ 0.06 * sin(x * 9.0 + z * 5.0 + float(ph[2]))
			var jit := rng.randf_range(-0.02, 0.02) * rho
			st[_ti(k, j)] = maxf(0.0, ht * prof * bump + (tilt.x * x + tilt.y * z) * 0.3 + jit)
			st[_bi(k, j)] = -hb * pow(prof, 0.35) * (1.0 + 0.1 * sin(a * 2.0 + float(ph[2])))
	return st


# ================== FORMATO DAS FERRAMENTAS ==================

## Limites do formato no ponto (x, z): Vector3(meio comprimento, grossura, largura).
static func _limits(kind: String, x: float, z: float) -> Vector3:
	match kind:
		"pedra_machado":
			# gota: estreita atrás (-x), larga no fio (+x); o fio afina até ficar cortante
			var a := 0.46
			var u := clampf((x + a) / (2.0 * a), 0.0, 1.0)
			var w := lerpf(0.11, 0.3, smoothstep(0.0, 0.8, u))
			var t := 0.15 * (1.0 - 0.85 * pow(smoothstep(0.35, 1.0, u), 1.2))
			return Vector3(a, maxf(t, 0.012), w)
		"pedra_cavadeira":
			# pá: larga e chata, com o fio reto e afiado na frente
			var a := 0.46
			var u := clampf((x + a) / (2.0 * a), 0.0, 1.0)
			var w := lerpf(0.2, 0.36, smoothstep(0.0, 0.45, u))
			var t := 0.09 * (1.0 - 0.8 * smoothstep(0.5, 1.0, u))
			return Vector3(a, maxf(t, 0.01), w)
		"pedra_pa":
			# pá: larga, arredondada na frente, fina na beira
			var a := 0.44
			var u := clampf((x + a) / (2.0 * a), 0.0, 1.0)
			var w := lerpf(0.16, 0.42, smoothstep(0.0, 0.45, u)) * sqrt(maxf(0.0, 1.0 - pow(maxf(u - 0.7, 0.0) / 0.3, 2.0) * 0.7))
			var t := 0.075 * (1.0 - 0.8 * smoothstep(0.45, 1.0, u))
			return Vector3(a, maxf(t, 0.008), maxf(w, 0.02))
		"lamina_serra":
			# lâmina comprida e fina; o lado +z afina e tem os dentes
			var a := 0.5
			var e := clampf(absf(x) / a, 0.0, 1.0)
			var w := 0.15 * sqrt(maxf(0.0, 1.0 - pow(e, 8.0)))       # pontas arredondadas
			if z > 0.0:
				w *= 1.0 - 0.2 * absf(sin(x / a * PI * 7.0))     # dentes
			var t := 0.05 * (1.0 - 0.7 * clampf(z / 0.15, 0.0, 1.0)) * (1.0 - 0.5 * pow(e, 3.0))
			return Vector3(a, maxf(t, 0.008), maxf(w, 0.012))
		"cunha":
			# cunha: costas retas e quadradas atrás (-x, onde a marreta bate), lados retos,
			# e só a frente (+x) afina até o fio reto que corta a madeira
			var a := 0.42
			var u := clampf((x + a) / (2.0 * a), 0.0, 1.0)
			var t := 0.15 * (1.0 - smoothstep(0.25, 1.0, u) * 0.93)
			return Vector3(a, maxf(t, 0.01), 0.2)
		"pedra_marreta":
			# cabeça de marreta: bloco grosso e comprido, pontas meio arredondadas (as faces de bater)
			var a := 0.4
			var e := clampf(absf(x) / a, 0.0, 1.0)
			var w := 0.24 * (1.0 - 0.15 * pow(e, 4.0))
			var t := 0.2 * (1.0 - 0.2 * pow(e, 4.0))
			return Vector3(a, t, w)
	return Vector3(0.5, 0.3, 0.4)


## Contorno do formato no ângulo a (raio até a beira, visto de cima): o maior raio
## que ainda fica dentro do formato (busca binária).
static func _outline(kind: String, a: float) -> float:
	var d := Vector2(cos(a), sin(a))
	var lo := 0.0
	var hi := 0.8
	for _it in 22:
		var r := (lo + hi) * 0.5
		var p := d * r
		var lim := _limits(kind, p.x, p.y)
		if absf(p.x) <= lim.x and absf(p.y) <= lim.z:
			lo = r
		else:
			hi = r
	return maxf(lo, 0.01)


static func target(kind: String, scale := 1.0) -> PackedFloat32Array:
	var st := PackedFloat32Array()
	st.resize(SIZE)
	for j in N:
		st[j] = _outline(kind, _ang(j)) * scale
	for k in R + 1:
		var taper := pow(maxf(0.0, 1.0 - pow(_rho(k), 2.2)), 0.45)
		if kind in ["cunha", "pedra_marreta"]:
			taper = 1.0          # faces e quinas retas (costas quadradas para bater)
		for j in N:
			var a := _ang(j)
			var x := cos(a) * st[j] / scale * _rho(k)
			var z := sin(a) * st[j] / scale * _rho(k)
			var t := _limits(kind, x, z).y * taper * scale
			st[_ti(k, j)] = t
			st[_bi(k, j)] = -t
	return st


## O formato tem que caber dentro da pedra crua: encolhe ele até caber.
static func fit_target(orig: PackedFloat32Array, kind: String) -> PackedFloat32Array:
	var t := target(kind)
	var k := 1.0
	for j in N:
		k = minf(k, orig[j] * 0.95 / t[j])
	for kk in R:
		for j in N:
			if t[_ti(kk, j)] > 0.0001:
				k = minf(k, maxf(orig[_ti(kk, j)], 0.001) * 0.95 / t[_ti(kk, j)])
				k = minf(k, maxf(-orig[_bi(kk, j)], 0.001) * 0.95 / t[_ti(kk, j)])
	k = maxf(k, 0.35)
	return target(kind, k)


# ================== LASCAR ==================

static func excess(cur: PackedFloat32Array, tgt: PackedFloat32Array) -> float:
	var e := 0.0
	for j in N:
		e += maxf(0.0, cur[j] - tgt[j]) * 2.0
	for k in R + 1:
		for j in N:
			e += maxf(0.0, cur[_ti(k, j)] - tgt[_ti(k, j)])
			e += maxf(0.0, tgt[_bi(k, j)] - cur[_bi(k, j)])
	return e


## Quanto uma lasca no lugar (k, j) tiraria (para escolher o próximo lugar).
static func _region(cur: PackedFloat32Array, tgt: PackedFloat32Array, k0: int, j0: int) -> float:
	var v := 0.0
	for dj in range(-3, 4):
		var j := j0 + dj
		for k in range(maxi(0, k0 - 2), mini(R, k0 + 2) + 1):
			v += maxf(0.0, cur[_ti(k, j)] - tgt[_ti(k, j)])
			v += maxf(0.0, tgt[_bi(k, j)] - cur[_bi(k, j)]) * 0.6
		if k0 >= R - 2:
			var jj := ((j % N) + N) % N
			v += maxf(0.0, cur[jj] - tgt[jj]) * 2.0
	return v


## Próximo lugar para bater: onde sobra mais pedra (índice k * N + j; k = R é a beira).
static func next_spot(cur: PackedFloat32Array, tgt: PackedFloat32Array) -> int:
	var best := -1
	var bv := 0.0
	for k in range(1, R + 1):
		for j in N:
			var v := _region(cur, tgt, k, j)
			if v > bv:
				bv = v
				best = k * N + j
	return best


## Solta uma lasca no lugar i: tira boa parte da sobra ali (não tudo de uma vez), com o
## fundo irregular como uma lasca de verdade; do outro lado da pedra também sai um pouco.
static func flake(cur: PackedFloat32Array, tgt: PackedFloat32Array, i: int, rng: RandomNumberGenerator) -> void:
	var k0 := i / N
	var j0 := i % N
	var bite := rng.randf_range(0.6, 0.85)
	for dj in range(-3, 4):
		var j := j0 + dj
		var wa := 1.0 - absf(dj) / 4.0
		for k in range(maxi(0, k0 - 2), mini(R, k0 + 2) + 1):
			var w := wa * (1.0 - absf(k - k0) / 3.0) * rng.randf_range(0.85, 1.1)
			var ti := _ti(k, j)
			var bi := _bi(k, j)
			cur[ti] = maxf(tgt[ti], cur[ti] - maxf(0.0, cur[ti] - tgt[ti]) * bite * w)
			cur[bi] = minf(tgt[bi], cur[bi] + maxf(0.0, tgt[bi] - cur[bi]) * bite * w * 0.75)
		if k0 >= R - 2:
			var jj := ((j % N) + N) % N
			cur[jj] = maxf(tgt[jj], cur[jj] - maxf(0.0, cur[jj] - tgt[jj]) * bite * wa)


## Ponto do lugar i na pedra (em cima, ou na beira), no espaço da pedra.
static func spot_point(cur: PackedFloat32Array, i: int) -> Vector3:
	var k := i / N
	var j := i % N
	var a := _ang(j)
	var r := cur[j] * _rho(k)
	var y := cur[_ti(k, j)] if k < R else (cur[_ti(k, j)] + cur[_bi(k, j)]) * 0.5
	return Vector3(cos(a) * r, y, sin(a) * r)


## Mais baixo da pedra (para encostar no chão).
static func bottom(cur: PackedFloat32Array) -> float:
	var m := 0.0
	for k in R + 1:
		for j in N:
			m = minf(m, cur[_bi(k, j)])
	return m


# ================== DESENHO ==================

static func _pos(cur: PackedFloat32Array, k: int, j: int, top: bool) -> Vector3:
	var a := _ang(j)
	var r := cur[((j % N) + N) % N] * _rho(k)
	var y: float
	if k >= R:
		y = (cur[_ti(R, j)] + cur[_bi(R, j)]) * 0.5     # a beira: as duas faces se encontram
	elif k == 0:
		var s := 0.0
		for jj in N:
			s += cur[_ti(0, jj)] if top else cur[_bi(0, jj)]
		y = s / N
	else:
		y = cur[_ti(k, j)] if top else cur[_bi(k, j)]
	return Vector3(cos(a) * r, y, sin(a) * r)


## Malha da pedra. orig: a pedra crua (onde já lascou fica mais clara, pedra nova).
## split: a pedra rachada em dois pedaços (afastados um do outro).
static func mesh(cur: PackedFloat32Array, orig: PackedFloat32Array, seed_: int, split := false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var base := Color(0.27, 0.265, 0.25).lerp(Color(0.3, 0.26, 0.2), rng.randf() * 0.6)    # cinza a sílex
	base = base.lerp(Color(0.2, 0.2, 0.21), rng.randf() * 0.5)
	base = base.darkened(rng.randf_range(0.0, 0.15))
	var fresh := base.lightened(0.1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crack_n := Vector3(rng.randf_range(-0.3, 0.3), 0.0, 1.0).normalized()
	for face in 2:
		var top := face == 0
		var ref := Vector3(0, -10.0, 0) if top else Vector3(0, 10.0, 0)
		for k in R:
			for j in N:
				var q := [_pos(cur, k, j, top), _pos(cur, k, j + 1, top), _pos(cur, k + 1, j + 1, top), _pos(cur, k + 1, j, top)]
				var cut := 0.0
				if orig.size() == cur.size():
					var idx := _ti(k + 1, j) if top else _bi(k + 1, j)
					cut = clampf(absf(orig[idx] - cur[idx]) * 14.0 + maxf(0.0, orig[j] - cur[j]) * 6.0, 0.0, 1.0)
				var h := absi(hash(Vector3i(k, j, face) + Vector3i(seed_, 0, 0))) % 1000
				var col := base.lerp(fresh, cut)
				if cut <= 0.05:
					# pedra crua: pintas escuras e claras, liquen cinza-esverdeado em cima, terra embaixo
					col = col.darkened(float(h % 100) * 0.0018).lightened(0.08 if h % 7 == 0 else 0.0)
					if top and h % 11 == 0 and k >= 1:
						col = col.lerp(Color(0.42, 0.45, 0.35), 0.45)
					if not top:
						col = col.lerp(Color(0.2, 0.15, 0.1), 0.45)
				else:
					col = col.darkened(float(h % 100) * 0.0012)
				# faces retas (pedra com quinas, não uma bolinha lisa)
				st.set_smooth_group(0xFFFFFFFF)
				for tri in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
					var a: Vector3 = tri[0]
					var b: Vector3 = tri[1]
					var c: Vector3 = tri[2]
					if (a - b).length() < 0.00001 or (a - c).length() < 0.00001:
						continue
					if split:
						var side := signf(((a + b + c) / 3.0).dot(crack_n) + 0.0001)
						a += crack_n * side * 0.06
						b += crack_n * side * 0.06
						c += crack_n * side * 0.06
					var cen := (a + b + c) / 3.0
					if (c - a).cross(b - a).dot(cen - ref) < 0.0:
						var t2 := b
						b = c
						c = t2
					st.set_color(col)
					st.add_vertex(a)
					st.add_vertex(b)
					st.add_vertex(c)
	# parede da beirada (onde a face de cima e a de baixo não se encontram: costas e
	# lados retos da cunha e da cabeça da marreta)
	for j in N:
		var a := _pos(cur, R, j, true)
		var b := _pos(cur, R, j + 1, true)
		var c := _pos(cur, R, j + 1, false)
		var d := _pos(cur, R, j, false)
		if a.y - d.y < 0.004 and b.y - c.y < 0.004:
			continue
		var out := Vector3(a.x + b.x, 0, a.z + b.z).normalized()
		var col := fresh.darkened(float(absi(hash(Vector2i(j, seed_))) % 100) * 0.0012)
		st.set_smooth_group(0xFFFFFFFF)
		for tri in [[a, b, c], [a, c, d]]:
			var p0: Vector3 = tri[0]
			var p1: Vector3 = tri[1]
			var p2: Vector3 = tri[2]
			if (p2 - p0).cross(p1 - p0).dot(out) < 0.0:
				var t2 := p1
				p1 = p2
				p2 = t2
			st.set_color(col)
			st.add_vertex(p0)
			st.add_vertex(p1)
			st.add_vertex(p2)
	st.index()
	st.generate_normals()
	return st.commit()


static var _mat: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.75
		_mat.metallic_specular = 0.25
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat


## Pedra trabalhada pronta (para o desenho no chão), no tamanho 1.
static func finished_mesh(kind: String, seed_: int) -> ArrayMesh:
	var o := rock(seed_)
	return mesh(fit_target(o, kind), o, seed_)


## Pedra pequena inteira no tamanho certo (a pedra de bater, na mão).
static func small_mesh(seed_: int, size: float) -> ArrayMesh:
	var r := rock(seed_)
	for i in r.size():
		r[i] *= size
	return mesh(r, r, seed_)


## Pedra de rio arredondada e lisa (a pedra de bater, na mão), tamanho = comprimento.
static func cobble_mesh(seed_: int, size: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var sm := SphereMesh.new()
	sm.radial_segments = 20
	sm.rings = 10
	var arr := sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	var ax := Vector3(0.5, rng.randf_range(0.3, 0.36), rng.randf_range(0.36, 0.42)) * size * 2.0
	var lobes := []
	for k in 3:
		lobes.append([Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.04, 0.09)])
	var base := Color(0.42, 0.41, 0.38).darkened(rng.randf_range(0.0, 0.2))
	for i in v.size():
		var d := v[i].normalized()
		var r := 1.0
		for lb in lobes:
			r += float(lb[1]) * pow(maxf(0.0, d.dot(lb[0] as Vector3)), 2.0)
		v[i] = Vector3(d.x * ax.x, d.y * ax.y, d.z * ax.z) * r * 0.5
		var spot := 0.5 + 0.5 * sin(d.x * 9.0 + d.z * 7.0 + seed_)
		cols.append(base.lerp(base.lightened(0.18), spot * 0.5).darkened(0.12 * maxf(0.0, -d.y)))
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.create_from(m, 0)
	st.generate_normals()
	return st.commit()
