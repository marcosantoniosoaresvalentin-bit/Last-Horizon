extends RefCounted
## Machado na mão e a animação de cortar árvore.
##
## O personagem só tem animações de parado/andando/correndo, então o golpe do
## machado é feito em código: depois da animação normal, os dois braços levantam
## o machado por cima da cabeça e descem com força no tronco.


## Modelo 3D do machado de pedra, como os antigos: um galho como cabo, uma pedra
## lascada encaixada perto da ponta e amarrada com cipó (voltas em cima e embaixo
## da pedra e cruzando por cima dela). O cabo vai de y = 0 (ponta de baixo) até
## 0,64 m; a pedra fica perto de y = 0,52 e o fio aponta para +Z.
static func axe_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_haft(st, rng)
	_stone(st, rng)
	_lashing(st, rng)
	st.generate_normals()
	return st.commit()


## Cabo: galho torto com casca, nós e a ponta cortada clara.
static func _haft(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var rings := 18
	var sides := 9
	var top_y := 0.64
	var pts := []
	for i in rings + 1:
		var t := float(i) / rings
		var y := t * top_y
		# curvinha natural do galho
		var c := Vector3(sin(t * 2.6) * 0.012 - 0.006, y, cos(t * 1.9) * 0.006)
		var r := lerpf(0.019, 0.016, t)
		if absf(t - 0.33) < 0.04:
			r += 0.004       # um nó no galho
		var ring := []
		for k in sides:
			var a := TAU * k / sides
			var bump := rng.randf_range(-0.0015, 0.0015)
			ring.append(c + Vector3(cos(a), 0, sin(a)) * (r + bump))
		pts.append(ring)
	for i in rings:
		for k in sides:
			var k2 := (k + 1) % sides
			var shade := rng.randf_range(0.92, 1.06)
			var bark := Color(0.2, 0.13, 0.075) * shade
			if (k + i) % 5 == 0:
				bark = Color(0.13, 0.09, 0.05)   # fissura escura da casca
			bark.a = 1.0
			_quad(st, pts[i][k], pts[i][k2], pts[i + 1][k2], pts[i + 1][k], bark)
	# pontas cortadas (madeira clara)
	var wood := Color(0.6, 0.46, 0.28)
	for end in [0, rings]:
		var ring: Array = pts[end]
		var c := Vector3.ZERO
		for p in ring:
			c += p
		c /= ring.size()
		for k in sides:
			var k2 := (k + 1) % sides
			st.set_color(wood)
			if end == 0:
				st.add_vertex(c); st.add_vertex(ring[k]); st.add_vertex(ring[k2])
			else:
				st.add_vertex(c); st.add_vertex(ring[k2]); st.add_vertex(ring[k])


## Pedra lascada: grossa atrás, afinando até o fio; facetas irregulares de lascamento.
static func _stone(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var cy := 0.52
	var cols := 7      # de trás (z = -0.045) até o fio (z = 0.16)
	var rows := 6      # ao longo da altura
	var grid := []
	for i in cols + 1:
		var u := float(i) / cols
		var z := lerpf(-0.045, 0.16, u)
		# formato de gota: nuca estreita e arredondada, fio largo
		var half_h := lerpf(0.028, 0.07, pow(u, 0.7)) + sin(u * PI) * 0.006
		var thick := lerpf(0.026, 0.002, pow(u, 0.8))  # afina até o fio
		var col := []
		for j in rows + 1:
			var v := float(j) / rows * 2.0 - 1.0
			var y := cy + v * half_h * (1.0 - 0.18 * u * v * v) + rng.randf_range(-0.003, 0.003)
			var bulge := thick * (1.0 - 0.55 * v * v)
			var jit := rng.randf_range(-0.006, 0.006) * (1.0 - u * 0.7)
			# fio curvo (mais para fora no meio) e nuca arredondada
			var zz := z - 0.028 * v * v * u - 0.02 * v * v * (1.0 - u) * (1.0 - u)
			col.append([Vector3(bulge + jit, y, zz + rng.randf_range(-0.003, 0.003) * (1.0 - u)),
				Vector3(-bulge - jit * 0.7, y, zz + rng.randf_range(-0.003, 0.003) * (1.0 - u))])
		grid.append(col)
	var base := Color(0.13, 0.135, 0.12)      # basalto escuro, meio esverdeado
	for side in 2:
		for i in cols:
			for j in rows:
				var a: Vector3 = grid[i][j][side]
				var b: Vector3 = grid[i + 1][j][side]
				var c: Vector3 = grid[i + 1][j + 1][side]
				var d: Vector3 = grid[i][j + 1][side]
				# cada lasca com um tom; perto do fio a pedra é mais clara (gasta de amolar)
				var tone := rng.randf_range(0.85, 1.15)
				var col := base * tone
				if rng.randf() < 0.25:
					col = col.lerp(Color(0.2, 0.15, 0.1), 0.5)   # manchas de ferrugem da pedra
				col = col.lerp(Color(0.3, 0.3, 0.28), smoothstep(0.65, 1.0, float(i) / cols))
				col.a = 1.0
				if side == 0:
					_quad(st, a, b, c, d, col)
				else:
					_quad(st, d, c, b, a, col)
	# bordas: em cima, embaixo, a nuca e o fio
	var edge_c := Color(0.34, 0.34, 0.31)
	for i in cols:
		for j in [0, rows]:
			var a0: Vector3 = grid[i][j][0]
			var a1: Vector3 = grid[i][j][1]
			var b0: Vector3 = grid[i + 1][j][0]
			var b1: Vector3 = grid[i + 1][j][1]
			if j == 0:
				_quad(st, a1, b1, b0, a0, base * 0.9)
			else:
				_quad(st, a0, b0, b1, a1, base * 0.9)
	for j in rows:
		var n0: Vector3 = grid[0][j][0]
		var n1: Vector3 = grid[0][j][1]
		var m0: Vector3 = grid[0][j + 1][0]
		var m1: Vector3 = grid[0][j + 1][1]
		_quad(st, n0, m0, m1, n1, base * 0.85)
		var e0: Vector3 = grid[cols][j][0]
		var e1: Vector3 = grid[cols][j][1]
		var f0: Vector3 = grid[cols][j + 1][0]
		var f1: Vector3 = grid[cols][j + 1][1]
		_quad(st, e1, f1, f0, e0, edge_c)


## Amarração de cipó: voltas apertadas no cabo, embaixo e em cima da pedra, e um
## "X" cruzando por cima da pedra dos dois lados.
static func _lashing(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var vine := Color(0.17, 0.19, 0.08)
	var r := 0.0042
	# voltas embaixo da pedra
	_helix(st, 0.455, 0.478, 0.0225, 3.2, r, vine, rng)
	# voltas em cima da pedra
	_helix(st, 0.565, 0.588, 0.021, 3.0, r, vine.darkened(0.08), rng)
	# o "X" por cima da pedra, dos dois lados
	for sx in [1.0, -1.0]:
		var x: float = sx * 0.03
		var path1 := [Vector3(x * 0.8, 0.47, -0.022), Vector3(x, 0.50, 0.0), Vector3(x * 0.95, 0.535, 0.022), Vector3(x * 0.8, 0.572, 0.012)]
		var path2 := [Vector3(x * 0.8, 0.47, 0.016), Vector3(x, 0.505, 0.022), Vector3(x * 0.95, 0.54, 0.0), Vector3(x * 0.8, 0.572, -0.02)]
		_tube(st, path1, r, vine.lightened(0.05), rng)
		_tube(st, path2, r, vine, rng)
	# pontinha do cipó solta, depois do nó
	_tube(st, [Vector3(0.02, 0.45, 0.012), Vector3(0.03, 0.43, 0.03), Vector3(0.028, 0.415, 0.05)], r * 0.8, vine.darkened(0.15), rng)


static func _helix(st: SurfaceTool, y0: float, y1: float, rad: float, turns: float, r: float, col: Color, rng: RandomNumberGenerator) -> void:
	var path := []
	var n := int(turns * 12)
	for i in n + 1:
		var t := float(i) / n
		var a := t * turns * TAU
		path.append(Vector3(cos(a) * rad - 0.004, lerpf(y0, y1, t), sin(a) * rad * 1.15))
	_tube(st, path, r, col, rng)


## Tubo seguindo um caminho (o cipó).
static func _tube(st: SurfaceTool, path: Array, r: float, col: Color, rng: RandomNumberGenerator) -> void:
	var sides := 5
	var rings := []
	for i in path.size():
		var p: Vector3 = path[i]
		var d: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var a := d.cross(Vector3.UP)
		if a.length() < 0.1:
			a = d.cross(Vector3.RIGHT)
		a = a.normalized()
		var b := d.cross(a).normalized()
		var ring := []
		for k in sides:
			var ang := TAU * k / sides
			ring.append(p + (a * cos(ang) + b * sin(ang)) * r)
		rings.append(ring)
	for i in rings.size() - 1:
		var c := col * rng.randf_range(0.85, 1.12)
		c.a = 1.0
		for k in sides:
			var k2 := (k + 1) % sides
			_quad(st, rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k2], c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


## Cavadeira dos antigos: cabo comprido de galho (1,2 m) e, na ponta, uma lâmina
## larga de pedra lascada (como uma pá) amarrada com cipó. Cabo de y = 0 (ponta de
## cima, onde a mão segura) até 1,2 m; a lâmina vai até ~1,45 m (o fio em +Y).
static func digger_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7171
	_digger_haft(st, rng)
	_digger_blade(st, rng)
	# amarração de cipó: voltas no cabo e laçadas passando pela pedra
	var vine := Color(0.17, 0.19, 0.08)
	_helix(st, 1.05, 1.13, 0.024, 4.0, 0.0045, vine, rng)
	for sx in [1.0, -1.0]:
		_tube(st, [Vector3(sx * 0.02, 1.1, 0.012), Vector3(sx * 0.03, 1.16, 0.018), Vector3(sx * 0.024, 1.2, 0.0), Vector3(sx * 0.03, 1.16, -0.018), Vector3(sx * 0.02, 1.1, -0.012)], 0.004, vine.lightened(0.06), rng)
	st.generate_normals()
	return st.commit()


## Serra de pedra (dos antigos, para dois): um cabo comprido de galho (1,3 m) com um
## pegador em pé em cada ponta, e no meio uma lâmina de pedra lascada com dentes
## (como a da foto), encaixada embaixo do cabo e amarrada com cipó.
## Cabo de y = 0 até y = 1,3; os dentes apontam para +Z (para baixo, serrando) e os
## pegadores para -Z (para cima).
const SAW_LEN := 1.3
const SAW_TEETH := 0.097          # dos dentes até o meio do cabo
const Lascar := preload("res://scripts/world/lascar.gd")

static func saw_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9393
	var bark := Color(0.3, 0.22, 0.14)
	# cabo: galho meio torto, com casca
	var path := []
	for i in 15:
		var t := i / 14.0
		path.append(Vector3(sin(t * 3.1) * 0.006, t * SAW_LEN, cos(t * 2.3) * 0.005))
	_tube_r(st, path, 0.021, 0.018, bark, 9, rng)
	# pontas cortadas (madeira clara)
	for y in [0.0, SAW_LEN]:
		_disc(st, Vector3(0, y, 0), 0.019, Color(0.6, 0.46, 0.28))
	# pegadores em pé, um em cada ponta (um jogador de cada lado da tora)
	for y in [0.07, SAW_LEN - 0.07]:
		_tube_r(st, [Vector3(0, y, 0.01), Vector3(0.004, y + 0.004, -0.07), Vector3(0, y, -0.15)], 0.017, 0.015, bark.darkened(0.08), 7, rng)
		_helix(st, y - 0.03, y + 0.03, 0.024, 2.5, 0.0038, Color(0.17, 0.19, 0.08), rng)
	# lâmina de pedra lascada com dentes (a mesma lâmina que sai da modelagem de pedra),
	# encaixada embaixo do cabo: comprimento ao longo do cabo, dentes para +Z
	var blade: ArrayMesh = Lascar.mesh(Lascar.target("lamina_serra"), Lascar.rock(31), 31)
	var bx := Transform3D(Basis(Vector3(0, 0.6, 0), Vector3(-0.22, 0, 0), Vector3(0, 0, 0.3)), Vector3(0, 0.65, 0.052))
	st.append_from(blade, 0, bx)
	# amarração de cipó prendendo a lâmina no cabo
	for y in [0.4, 0.52, 0.65, 0.78, 0.9]:
		var ring := []
		for k in 13:
			var a := TAU * k / 12.0
			ring.append(Vector3(cos(a) * 0.028, y + k * 0.0015, 0.012 + sin(a) * 0.042))
		_tube(st, ring, 0.004, Color(0.17, 0.19, 0.08), rng)
	st.generate_normals()
	return st.commit()


static func _tube_r(st: SurfaceTool, path: Array, ra: float, rb: float, col: Color, sides: int, rng: RandomNumberGenerator) -> void:
	var rings := []
	for i in path.size():
		var p: Vector3 = path[i]
		var d: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var a := d.cross(Vector3.FORWARD if absf(d.z) < 0.9 else Vector3.RIGHT).normalized()
		var b := d.cross(a).normalized()
		var r := lerpf(ra, rb, float(i) / maxf(path.size() - 1, 1))
		var ring := []
		for k in sides:
			var ang := TAU * k / sides
			ring.append(p + (a * cos(ang) + b * sin(ang)) * r)
		rings.append(ring)
	for i in rings.size() - 1:
		var c := col * rng.randf_range(0.88, 1.1)
		c.a = 1.0
		for k in sides:
			var k2 := (k + 1) % sides
			_quad(st, rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k2], c)


static func _disc(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		st.set_color(col)
		st.add_vertex(c)
		st.add_vertex(c + Vector3(cos(a0) * r, 0, sin(a0) * r))
		st.add_vertex(c + Vector3(cos(a1) * r, 0, sin(a1) * r))


## Cabo da cavadeira: galho reto e comprido, com casca (y = 0 até 1,22).
static func _digger_haft(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	# cabo: galho reto e comprido, com casca
	var sides := 8
	var rings := 22
	var haft_len := 1.22
	var pts := []
	for i in rings + 1:
		var t := float(i) / rings
		var c := Vector3(sin(t * 2.2) * 0.008, t * haft_len, cos(t * 1.7) * 0.005)
		var r := lerpf(0.02, 0.018, t)
		var ring := []
		for k in sides:
			var a := TAU * k / sides
			ring.append(c + Vector3(cos(a), 0, sin(a)) * (r + rng.randf_range(-0.0012, 0.0012)))
		pts.append(ring)
	for i in rings:
		for k in sides:
			var k2 := (k + 1) % sides
			var bark := Color(0.2, 0.13, 0.075) * rng.randf_range(0.92, 1.06)
			if (k + i) % 5 == 0:
				bark = Color(0.13, 0.09, 0.05)
			bark.a = 1.0
			_quad(st, pts[i][k], pts[i][k2], pts[i + 1][k2], pts[i + 1][k], bark)
	var wood := Color(0.6, 0.46, 0.28)
	var cap0: Array = pts[0]
	for k in sides:
		st.set_color(wood)
		st.add_vertex(Vector3.ZERO); st.add_vertex(cap0[k]); st.add_vertex(cap0[(k + 1) % sides])


## Lâmina de pedra da cavadeira: estreita onde encaixa no cabo e larga no fio (forma
## de pá), de y = 1,12 até 1,46 (o fio em +Y).
static func _digger_blade(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var y0 := 1.12
	var y1 := 1.46
	var cols := 7
	var rows := 6
	var grid := []
	for i in cols + 1:
		var u := float(i) / cols                        # 0 no cabo, 1 no fio
		var y := lerpf(y0, y1, u)
		var half_w := lerpf(0.035, 0.085, pow(u, 0.8))
		var thick := lerpf(0.016, 0.002, pow(u, 1.2))
		var col := []
		for j in rows + 1:
			var v := float(j) / rows * 2.0 - 1.0
			var x := v * half_w + rng.randf_range(-0.004, 0.004) * (1.0 - u * 0.5)
			var yy := y - 0.025 * v * v * u + rng.randf_range(-0.003, 0.003)   # fio curvo
			var b := thick * (1.0 - 0.6 * v * v) + rng.randf_range(-0.002, 0.002)
			col.append([Vector3(x, yy, b), Vector3(x, yy, -b)])
		grid.append(col)
	var stone := Color(0.42, 0.38, 0.3)
	for side in 2:
		for i in cols:
			for j in rows:
				var a: Vector3 = grid[i][j][side]
				var b: Vector3 = grid[i + 1][j][side]
				var c: Vector3 = grid[i + 1][j + 1][side]
				var d: Vector3 = grid[i][j + 1][side]
				var cc := stone * rng.randf_range(0.85, 1.15)
				cc = cc.lerp(Color(0.6, 0.56, 0.47), smoothstep(0.7, 1.0, float(i) / cols))
				cc.a = 1.0
				if side == 0:
					_quad(st, a, b, c, d, cc)
				else:
					_quad(st, d, c, b, a, cc)
	for i in cols:
		for j in [0, rows]:
			_quad(st, grid[i][j][0], grid[i + 1][j][0], grid[i + 1][j][1], grid[i][j][1], stone * 0.8)
	for j in rows:
		_quad(st, grid[cols][j][0], grid[cols][j + 1][0], grid[cols][j + 1][1], grid[cols][j][1], Color(0.62, 0.58, 0.5))
		_quad(st, grid[0][j][1], grid[0][j + 1][1], grid[0][j + 1][0], grid[0][j][0], stone * 0.8)


## Pedra trabalhada sozinha (a que sai da modelagem e vai na ferramenta), deitada:
## a parte fina para cima/baixo, comprimento em X, tamanho 1 no comprimento.
static func worked_stone_mesh(kind: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	var xf := Transform3D.IDENTITY
	match kind:
		"pedra_machado":
			rng.seed = 4242
			# a mesma sequência do machado: o cabo antes da pedra (para sair igual)
			var tmp := SurfaceTool.new()
			tmp.begin(Mesh.PRIMITIVE_TRIANGLES)
			_haft(tmp, rng)
			_stone(st, rng)
			# pedra do machado: z = comprimento (nuca -> fio), y = altura, x = grossura
			var k := 1.0 / 0.21
			xf = Transform3D(Basis(Vector3(0, k, 0), Vector3(0, 0, k), Vector3(k, 0, 0)), Vector3.ZERO) * Transform3D(Basis(), Vector3(0, -0.52, -0.058))
		"pedra_cavadeira":
			rng.seed = 7171
			var tmp := SurfaceTool.new()
			tmp.begin(Mesh.PRIMITIVE_TRIANGLES)
			_digger_haft(tmp, rng)
			_digger_blade(st, rng)
			# lâmina: y = comprimento (cabo -> fio), x = largura, z = grossura
			var k := 1.0 / 0.36
			xf = Transform3D(Basis(Vector3(0, 0, k), Vector3(k, 0, 0), Vector3(0, k, 0)), Vector3.ZERO) * Transform3D(Basis(), Vector3(0, -1.29, 0))
		_:
			var blade: ArrayMesh = Lascar.mesh(Lascar.target("lamina_serra"), Lascar.rock(31), 31)
			return blade
	st.generate_normals()
	var m := st.commit()
	var out := SurfaceTool.new()
	out.begin(Mesh.PRIMITIVE_TRIANGLES)
	out.append_from(m, 0, xf)
	out.generate_normals()
	return out.commit()


static func axe_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Pose do machado, aplicada por cima da animação normal do personagem.
##  - carregando: o machado na mão direita, mão fechada no cabo, apontando para baixo.
##  - golpe: as duas mãos fechadas no cabo; o machado vai para trás do ombro direito
##    e vem de lado, na horizontal, batendo na lateral do tronco.
## Os braços são colocados com cinemática inversa (ombro, cotovelo e pulso), para as
## mãos ficarem exatamente em cima do cabo.
class ChopPose extends SkeletonModifier3D:
	const SWING_TIME := 0.8       # segundos por machadada
	const HIT_AT := 0.55          # momento da machadada em que a lâmina bate no tronco
	const GRIP_LOW := 0.03        # mão esquerda: bem na ponta do cabo (só no golpe)
	const GRIP_HIGH := 0.115      # mão direita: quase na ponta, deixando lugar para a esquerda
	var player: Node3D            # para saber para onde o personagem está virado
	var axe: Node3D               # o machado
	var holding := false          # machado equipado
	var swinging := false         # dando uma machadada agora
	var ready_pose := false            # duas mãos no cabo, esperando o próximo toque
	var phase := 0.0
	var vertical := false         # golpe de cima para baixo (cortar tora deitada)
	var down_hit := -42.0         # onde o golpe de cima para baixo para (graus): -42 chão, -16 cintura
	var sawing := false           # serrando (vai e vem com a serra de pedra)
	var saw_phase := 0.0          # 0 a 1: uma ida e volta
	var saw_point := Vector3.ZERO # onde a serra corta (no mundo, em cima da tora)
	var saw_depth := 0.0          # quanto o corte já desceu (m)
	var knapping := false         # agachado batendo uma pedra na outra (modelando)
	var knap_point := Vector3.ZERO  # onde bate (no mundo)
	var knap_lift := 0.35         # 0 = encostou na pedra do chão, 1 = levantada
	var digging := false          # cavando com a cavadeira
	var crouch := 0.0             # 0 em pé, 1 agachado (pegar ou largar a tora)
	var moving := false           # andando/correndo (o jogo avisa)
	var tool := "machado"         # ferramenta na mão: "machado" ou "cavadeira"
	var grip_low := GRIP_LOW
	var grip_high := GRIP_HIGH
	var carry_grip := GRIP_HIGH
	var _carry_cal := {}          # ferramenta -> pegada gravada parado (mão no antebraço, ferramenta na mão)
	var log_node: Node3D = null   # tora no ombro
	var log_r := 0.2
	var _b := {}
	var thumb_axis := Vector3.BACK
	var thumb_angs := [1.0, 0.9, 0.7]

	func _bone(n: String) -> int:
		if not _b.has(n):
			_b[n] = get_skeleton().find_bone(n) if get_skeleton() else -1
		return _b[n]

	## Ângulo do golpe (graus): 0 = machado apontando para a frente (no tronco);
	## negativo = para o lado direito/trás (preparando).
	static func swing_angle(p: float) -> float:
		if p < 0.4:
			return lerpf(-25.0, -118.0, smoothstep(0.0, 1.0, p / 0.4))   # leva o machado para trás do ombro
		if p < HIT_AT:
			var t := (p - 0.4) / (HIT_AT - 0.4)
			return lerpf(-118.0, 0.0, t * t)                              # vem com força, de lado
		if p < 0.65:
			return lerpf(0.0, -9.0, (p - HIT_AT) / (0.65 - HIT_AT))       # tranco da batida
		return lerpf(-9.0, -25.0, smoothstep(0.0, 1.0, (p - 0.65) / 0.35))

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or player == null:
			return
		var to_skel := sk.global_transform.affine_inverse()
		var tb := to_skel.basis
		var up: Vector3 = (tb * Vector3.UP).normalized()
		var fwd: Vector3 = (tb * -player.global_transform.basis.z).normalized()
		var right: Vector3 = (tb * player.global_transform.basis.x).normalized()
		if crouch > 0.001:
			_crouch(sk, up, fwd, right)
		if log_node:
			if axe:
				axe.visible = false
			_carry_log(sk, up, fwd, right)
			return
		if knapping and holding:
			if axe:
				axe.visible = true
			_close_fingers(sk, "Right")
			_close_fingers(sk, "Left")
			_knap(sk, up, fwd, right)
			return
		if axe:
			axe.visible = holding
		if not holding:
			return
		_close_fingers(sk, "Right")
		if sawing:
			_close_fingers(sk, "Left")
			_saw(sk, up, fwd, right)
			return
		if swinging or ready_pose:
			_close_fingers(sk, "Left")
			if digging:
				_two_hands_dig(sk, up, fwd, right, phase if swinging else 0.0)
			elif vertical:
				_two_hands_down(sk, up, fwd, right, down_angle(phase, down_hit) if swinging else -30.0)
			else:
				_two_hands(sk, up, fwd, right, swing_angle(phase) if swinging else -25.0)
		else:
			_carry(sk, up, fwd, right)

	## Ângulo do golpe de cima para baixo (graus de elevação do cabo):
	## 115 = machado lá em cima, atrás da cabeça; -42 = batendo na tora no chão.
	static func down_angle(p: float, hit := -42.0) -> float:
		var rest := maxf(-30.0, hit + 4.0)
		if p < 0.4:
			return lerpf(rest, 115.0, smoothstep(0.0, 1.0, p / 0.4))
		if p < HIT_AT:
			var t := (p - 0.4) / (HIT_AT - 0.4)
			return lerpf(115.0, hit, t * t)
		if p < 0.65:
			return lerpf(hit, hit + 8.0, (p - HIT_AT) / (0.65 - HIT_AT))
		return lerpf(hit + 8.0, rest, smoothstep(0.0, 1.0, (p - 0.65) / 0.35))

	# ---------- modelar pedra: as duas mãos seguram a pedra de bater e descem no ponto ----------
	func _knap(sk: Skeleton3D, up: Vector3, fwd: Vector3, right: Vector3) -> void:
		var pt: Vector3 = sk.global_transform.affine_inverse() * knap_point
		var hammer := pt + up * (0.06 + 0.28 * knap_lift) - fwd * 0.03
		for side in ["Right", "Left"]:
			var out := right if side == "Right" else -right
			var sb := _bone(side + "Arm")
			if sb < 0:
				continue
			var sh := sk.get_bone_global_pose(sb).origin
			var wrist := hammer + out * 0.06 + up * 0.05 - fwd * 0.07
			_ik(sk, side + "Arm", side + "ForeArm", side + "Hand", wrist, sh - up * 0.3 + out * 0.7 + fwd * 0.2)
		_set_tool(sk, Transform3D(Basis(), hammer))

	# ---------- serrar: vai e vem, a mão direita no pegador e a esquerda no cabo ----------
	func _saw(sk: Skeleton3D, up: Vector3, fwd: Vector3, right: Vector3) -> void:
		var pt: Vector3 = sk.global_transform.affine_inverse() * saw_point
		# a serra vai do personagem até o corte (deitada, na horizontal)
		var flat := pt - up * pt.dot(up)
		var dir := flat.normalized() if flat.length() > 0.05 else fwd
		var stroke := sin(saw_phase * TAU) * 0.14     # + empurra (a serra vai para longe)
		var bar_mid := pt + up * (SAW_TEETH - saw_depth)
		var base := bar_mid - dir * (SAW_LEN * 0.5) + dir * stroke
		# o corpo vai junto: inclina para a frente quando empurra
		_rot_global(sk, "Spine1", right, -0.22 - stroke * 0.9)
		# as duas mãos fechadas no cabo, perto da ponta (do lado de dentro do pegador)
		_hand_on(sk, "Right", base + dir * 0.13, dir, _orth(-up * 0.4 + right * 0.5, dir), up, right)
		_hand_on(sk, "Left", base + dir * 0.31, dir, _orth(-up * 0.4 - right * 0.5, dir), up, -right)
		_set_tool(sk, _tool_xf(base, dir, -up))

	# ---------- cavar: levanta a cavadeira e crava no chão, depois alavanca ----------
	func _two_hands_dig(sk: Skeleton3D, up: Vector3, fwd: Vector3, right: Vector3, p: float) -> void:
		var lift := 0.0     # quanto a ferramenta sobe
		var tilt := -78.0   # inclinação do cabo (graus; -90 = de pé)
		if p < 0.4:
			lift = smoothstep(0.0, 1.0, p / 0.4) * 0.28
			tilt = lerpf(-74.0, -70.0, p / 0.4)
		elif p < HIT_AT:
			var t := (p - 0.4) / (HIT_AT - 0.4)
			lift = lerpf(0.28, -0.08, t * t)               # crava
			tilt = lerpf(-70.0, -80.0, t)
		elif p < 0.8:
			var t := (p - HIT_AT) / (0.8 - HIT_AT)
			lift = -0.08
			tilt = lerpf(-80.0, -62.0, smoothstep(0.0, 1.0, t))   # alavanca a terra
		else:
			var t := (p - 0.8) / 0.2
			lift = lerpf(-0.08, 0.0, t)
			tilt = lerpf(-62.0, -74.0, t)
		var e := deg_to_rad(tilt)
		var dir := (fwd * cos(e) + up * sin(e)).normalized()
		var edge := fwd
		# a ponta de cima do cabo (onde as mãos seguram) fica na altura do peito
		var tip_ground := fwd * 0.62 + up * (-0.04)
		var base := tip_ground - dir * 1.42 + up * lift
		_rot_global(sk, "Spine1", right, -0.2 if p > 0.45 and p < 0.8 else -0.08)
		var fingers := _orth(-up * 0.3 + fwd * 0.7, dir)
		_hand_on(sk, "Right", base + dir * grip_high, dir, fingers, up, right)
		_hand_on(sk, "Left", base + dir * grip_low, dir, fingers, up, -right)
		_set_tool(sk, _tool_xf(base, dir, edge))

	# ---------- golpe de cima para baixo (tora no chão) ----------
	func _two_hands_down(sk: Skeleton3D, up: Vector3, fwd: Vector3, right: Vector3, e_deg: float) -> void:
		var e := deg_to_rad(e_deg)
		var dir := (fwd * cos(e) + up * sin(e)).normalized()
		var edge := _orth(fwd * sin(e) - up * cos(e), dir)
		var low := clampf(-e_deg / 42.0, 0.0, 1.0)
		var chest := up * (1.12 - low * 0.12) + fwd * 0.06
		var e2 := e * 0.8
		var base := chest + (fwd * cos(e2) + up * sin(e2)).normalized() * 0.24 - right * 0.03
		# o corpo dobra para a frente na batida e estica ao levantar
		_rot_global(sk, "Spine1", right, lerpf(0.1, -0.38, low) if e_deg < 60.0 else 0.1)
		var out := Vector3(base.x - chest.x, 0, base.z - chest.z)
		var fingers := _orth(-up * 0.4 + out.normalized() * 0.5 - fwd * 0.3, dir)
		_hand_on(sk, "Right", base + dir * grip_high, dir, fingers, up, right)
		_hand_on(sk, "Left", base + dir * grip_low, dir, fingers, up, -right)
		_place_axe(sk, base, dir, edge)

	# ---------- agachar: o quadril desce e os joelhos dobram com os pés no chão ----------
	func _crouch(sk: Skeleton3D, up: Vector3, fwd: Vector3, right: Vector3) -> void:
		var hb := _bone("Hips")
		if hb < 0:
			return
		var feet := {}
		for side in ["Left", "Right"]:
			var fb := _bone(side + "Foot")
			if fb >= 0:
				feet[side] = sk.get_bone_global_pose(fb)
		var hp := sk.get_bone_global_pose(hb)
		hp.origin += -up * 0.42 * crouch - fwd * 0.08 * crouch
		sk.set_bone_global_pose(hb, hp)
		_rot_global(sk, "Spine", right, -0.6 * crouch)
		_rot_global(sk, "Spine1", right, -0.25 * crouch)
		for side in feet:
			var foot: Transform3D = feet[side]
			# o joelho dobra para onde o pé aponta (senão o tornozelo torce)
			var toe_b := _bone(side + "ToeBase")
			var toe_dir := fwd
			if toe_b >= 0:
				toe_dir = sk.get_bone_global_pose(toe_b).origin - foot.origin
				toe_dir -= up * toe_dir.dot(up)
				toe_dir = toe_dir.normalized() if toe_dir.length() > 0.001 else fwd
			_ik(sk, side + "UpLeg", side + "Leg", side + "Foot", foot.origin, foot.origin + toe_dir * 1.2 + up * 0.5)
			var fp := sk.get_bone_global_pose(_bone(side + "Foot"))
			fp.basis = foot.basis
			sk.set_bone_global_pose(_bone(side + "Foot"), fp)

	# ---------- tora no ombro ----------
	func _carry_log(sk: Skeleton3D, up: Vector3, fwd: Vector3, right: Vector3) -> void:
		var sb := _bone("RightArm")
		if sb < 0:
			return
		var sh := sk.get_bone_global_pose(sb).origin
		# a tora deitada em cima do ombro direito, ao longo do caminho (um pouco inclinada)
		var center := sh + up * (log_r + 0.02) + right * 0.05
		var axis := (fwd + up * 0.08).normalized()
		# mão direita segura a tora por baixo, um pouco à frente do ombro
		var grip := center + axis * 0.32 - up * log_r * 0.75 + right * 0.04
		_close_fingers(sk, "Right")
		var g := _grip_rotate("Right", sk, -right, up)
		if not g.is_empty():
			_ik(sk, "RightArm", "RightForeArm", "RightHand", grip - g.offset, sh - up * 0.6 + right * 0.6)
			var hp := sk.get_bone_global_pose(_bone("RightHand"))
			hp.basis = g.basis
			sk.set_bone_global_pose(_bone("RightHand"), hp)
		var gx := sk.global_transform * Transform3D(Basis(Quaternion(Vector3.RIGHT, axis)), center)
		gx.basis = gx.basis.orthonormalized()
		log_node.global_transform = gx

	# ---------- carregando com uma mão ----------
	func _carry(sk: Skeleton3D, up: Vector3, fwd: Vector3, right: Vector3) -> void:
		# antebraço um pouco dobrado, como quem segura peso
		_rot_global(sk, "RightForeArm", right, deg_to_rad(20.0))
		var fa := _bone("RightForeArm")
		var hb := _bone("RightHand")
		if fa < 0 or hb < 0:
			return
		var fa_g := sk.get_bone_global_pose(fa)
		# Depois de gravada (parado), a pegada não muda: a mão fica firme no antebraço e a
		# ferramenta presa na mão, mesmo com o braço balançando na corrida.
		if _carry_cal.has(tool):
			var cal: Dictionary = _carry_cal[tool]
			var hp := sk.get_bone_global_pose(hb)
			hp.basis = (fa_g.basis.orthonormalized() * cal.hand).scaled(hp.basis.get_scale())
			sk.set_bone_global_pose(hb, hp)
			var hg := sk.get_bone_global_pose(hb)
			var t2: Transform3D = Transform3D(hg.basis.orthonormalized(), hg.origin) * cal.tool
			_set_tool(sk, _avoid_body(sk, t2, t2 * Vector3(0, carry_grip, 0)))
			return
		# pulso reto: os dedos seguem a linha do antebraço; o cabo sai da mão para a frente
		var arm_dir := (sk.get_bone_global_pose(hb).origin - fa_g.origin).normalized()
		var want := fwd * 0.9 - up * 0.3 if tool == "machado" else fwd * 0.75 - up * 0.45 + right * 0.45
		if tool == "serra":
			want = fwd * 1.0 - up * 0.12 + right * 0.15   # serra deitada, segura pelo meio do cabo
		var handle := _orth(want, arm_dir)
		var g := _grip_rotate("Right", sk, handle, arm_dir)
		if g.is_empty():
			return
		var hp := sk.get_bone_global_pose(hb)
		hp.basis = g.basis
		sk.set_bone_global_pose(hb, hp)
		var center: Vector3 = hp.origin + g.offset
		var edge := _orth(-up if tool in ["machado", "serra"] else fwd, handle)
		var txf := _tool_xf(center - handle * carry_grip, handle, edge)
		_set_tool(sk, _avoid_body(sk, txf, center))
		if not moving:
			var hg := sk.get_bone_global_pose(hb)
			var hand_xf := Transform3D(hg.basis.orthonormalized(), hg.origin)
			_carry_cal[tool] = {"hand": fa_g.basis.orthonormalized().inverse() * hg.basis.orthonormalized(),
				"tool": hand_xf.affine_inverse() * txf}

	# ---------- golpe com as duas mãos ----------
	func _two_hands(sk: Skeleton3D, up: Vector3, fwd: Vector3, right: Vector3, ang_deg: float) -> void:
		var a := deg_to_rad(ang_deg)
		# direção do cabo: horizontal, girando em volta do corpo (levemente para baixo na batida)
		var dir := (fwd * cos(a) - right * sin(a)).normalized()
		var lift := 0.18 * clampf(-ang_deg / 118.0, 0.0, 1.0)
		dir = (dir + up * (lift - 0.12)).normalized()
		# para onde a lâmina vai (o fio aponta para o lado do movimento)
		var edge := _orth(-fwd * sin(a) - right * cos(a), dir)
		var chest := up * (1.08 + lift * 0.6) + fwd * 0.08
		var base := chest + (fwd * cos(a * 0.75) - right * sin(a * 0.75)).normalized() * 0.2 - right * 0.04
		# o tronco gira junto com o machado
		_rot_global(sk, "Spine1", up, a * 0.22)
		_rot_global(sk, "Spine2", up, a * 0.12)
		# os dedos fecham por cima do cabo, apontando para baixo e para fora do corpo
		var out := (base - chest)
		out.y = 0.0
		var fingers := _orth(-up * 0.75 + out.normalized() * 0.6, dir)
		# mão direita quase na ponta, esquerda bem na ponta
		_hand_on(sk, "Right", base + dir * grip_high, dir, fingers, up, right)
		_hand_on(sk, "Left", base + dir * grip_low, dir, fingers, up, -right)
		_place_axe(sk, base, dir, edge)

	static func _orth(v: Vector3, axis: Vector3) -> Vector3:
		var o := v - axis * v.dot(axis)
		return o.normalized() if o.length() > 0.0001 else axis.cross(Vector3.UP).normalized()

	## Mede a mão de verdade (pelos ossos): de onde é o mindinho para o indicador
	## (por onde o cabo atravessa), para onde os dedos apontam e o centro da mão
	## fechada (o centro do círculo que o dedo do meio faz ao dobrar).
	## Devolve a rotação que deixa o cabo passando por dentro da mão:
	## {basis: orientação nova da mão, offset: do pulso até o centro do punho}.
	func _grip_rotate(side: String, sk: Skeleton3D, handle: Vector3, fingers: Vector3) -> Dictionary:
		var hb := _bone(side + "Hand")
		var i1 := _bone(side + "HandIndex1")
		var p1 := _bone(side + "HandPinky1")
		var m1 := _bone(side + "HandMiddle1")
		var m2 := _bone(side + "HandMiddle2")
		var m3 := _bone(side + "HandMiddle3")
		if hb < 0 or i1 < 0 or p1 < 0 or m1 < 0 or m2 < 0 or m3 < 0:
			return {}
		var hp := sk.get_bone_global_pose(hb)
		var w := hp.origin
		var across := (sk.get_bone_global_pose(i1).origin - sk.get_bone_global_pose(p1).origin).normalized()
		var M1 := sk.get_bone_global_pose(m1).origin
		var M2 := sk.get_bone_global_pose(m2).origin
		var M3 := sk.get_bone_global_pose(m3).origin
		var f_cur := _orth(M1 - w, across)
		var cur := Basis(across, f_cur, across.cross(f_cur))
		var f_des := _orth(fingers, handle)
		var des := Basis(handle, f_des, handle.cross(f_des))
		var r := des * cur.inverse()
		var center := _circumcenter(M1, M2, M3)
		return {"basis": r * hp.basis, "offset": r * (center - w)}

	static func _circumcenter(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
		var ab := b - a
		var ac := c - a
		var n := ab.cross(ac)
		var n2 := n.length_squared()
		if n2 < 1e-12:
			return (a + b + c) / 3.0
		return a + (n.cross(ab) * ac.length_squared() + ac.cross(n) * ab.length_squared()) / (2.0 * n2)

	## Põe uma mão fechada no cabo: gira a mão para o cabo passar por dentro do punho
	## e leva o braço (cinemática inversa) até o pulso ficar no lugar certo.
	func _hand_on(sk: Skeleton3D, side: String, grip: Vector3, along: Vector3, fingers: Vector3, up: Vector3, out: Vector3) -> void:
		var hb := _bone(side + "Hand")
		if hb < 0:
			return
		var g := _grip_rotate(side, sk, along, fingers)
		if g.is_empty():
			return
		var wrist: Vector3 = grip - g.offset
		var sh := sk.get_bone_global_pose(_bone(side + "Arm")).origin
		var pole := sh - up * 0.8 + out * 0.5
		_ik(sk, side + "Arm", side + "ForeArm", side + "Hand", wrist, pole)
		# pulso reto: os dedos seguem a linha do antebraço (refaz o braço com essa mão)
		var fa := sk.get_bone_global_pose(_bone(side + "ForeArm")).origin
		var arm_dir := (sk.get_bone_global_pose(hb).origin - fa).normalized()
		var f2 := (_orth(arm_dir, along) * 0.75 + _orth(fingers, along) * 0.25).normalized()
		var g2 := _grip_rotate(side, sk, along, f2)
		if not g2.is_empty():
			g = g2
			_ik(sk, side + "Arm", side + "ForeArm", side + "Hand", grip - g.offset, pole)
		var hp := sk.get_bone_global_pose(hb)
		hp.basis = g.basis
		sk.set_bone_global_pose(hb, hp)

	## Cinemática inversa de dois ossos (ombro-cotovelo-pulso).
	func _ik(sk: Skeleton3D, upper: String, lower: String, end: String, target: Vector3, pole: Vector3) -> void:
		var ub := _bone(upper)
		var lb := _bone(lower)
		var eb := _bone(end)
		if ub < 0 or lb < 0 or eb < 0:
			return
		var gu := sk.get_bone_global_pose(ub)
		var gl := sk.get_bone_global_pose(lb)
		var ge := sk.get_bone_global_pose(eb)
		var s := gu.origin
		var la := (gl.origin - s).length()
		var lb_len := (ge.origin - gl.origin).length()
		var to_t := target - s
		var d := clampf(to_t.length(), 0.05, la + lb_len - 0.002)
		var dir := to_t.normalized()
		var cos_a := clampf((la * la + d * d - lb_len * lb_len) / (2.0 * la * d), -1.0, 1.0)
		var sin_a := sqrt(1.0 - cos_a * cos_a)
		var pd := pole - s
		pd = (pd - dir * pd.dot(dir))
		if pd.length() < 0.001:
			pd = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
		pd = pd.normalized()
		var elbow := s + (dir * cos_a + pd * sin_a) * la
		var q1 := Quaternion((gl.origin - s).normalized(), (elbow - s).normalized())
		gu.basis = Basis(q1) * gu.basis
		sk.set_bone_global_pose(ub, gu)
		gl = sk.get_bone_global_pose(lb)
		ge = sk.get_bone_global_pose(eb)
		var tgt := s + dir * d
		var q2 := Quaternion((ge.origin - gl.origin).normalized(), (tgt - gl.origin).normalized())
		gl.basis = Basis(q2) * gl.basis
		sk.set_bone_global_pose(lb, gl)

	func _rot_global(sk: Skeleton3D, bone: String, axis: Vector3, ang: float) -> void:
		var b := _bone(bone)
		if b < 0:
			return
		var g := sk.get_bone_global_pose(b)
		g.basis = Basis(axis, ang) * g.basis
		sk.set_bone_global_pose(b, g)

	## Dedos fechados em volta do cabo (cada falange dobra no próprio eixo X).
	func _close_fingers(sk: Skeleton3D, side: String) -> void:
		for f in ["Index", "Middle", "Ring", "Pinky"]:
			var angs := [1.15, 1.35, 0.9]
			for k in 3:
				var b := _bone("%sHand%s%d" % [side, f, k + 1])
				if b < 0:
					continue
				sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * Quaternion(Vector3.RIGHT, angs[k]))
		for k in 3:
			var b := _bone("%sHandThumb%d" % [side, k + 1])
			if b < 0:
				continue
			# o polegar dobra por cima do cabo (na mão esquerda o eixo é espelhado)
			var ang: float = thumb_angs[k] * (1.0 if side == "Right" else -1.0)
			sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * Quaternion(thumb_axis.normalized(), ang))

	## Machado: base do cabo em "base", cabo apontando para "handle", fio para "edge"
	## (tudo no espaço do esqueleto).
	func _place_axe(sk: Skeleton3D, base: Vector3, handle: Vector3, edge: Vector3) -> void:
		_set_tool(sk, _tool_xf(base, handle, edge))

	## Não deixa a ferramenta entrar no corpo: testa pontos ao longo do cabo e da lâmina
	## contra o tronco, o quadril e as pernas; se algum entra, gira a ferramenta em volta
	## da mão até sair.
	func _avoid_body(sk: Skeleton3D, txf: Transform3D, pivot: Vector3) -> Transform3D:
		var caps := []
		var pairs := [["Hips", "Spine2", 0.17], ["Spine2", "Neck", 0.16],
			["LeftUpLeg", "LeftLeg", 0.1], ["LeftLeg", "LeftFoot", 0.075],
			["RightUpLeg", "RightLeg", 0.1], ["RightLeg", "RightFoot", 0.075]]
		for pr in pairs:
			var a := _bone(pr[0])
			var b := _bone(pr[1])
			if a >= 0 and b >= 0:
				caps.append([sk.get_bone_global_pose(a).origin, sk.get_bone_global_pose(b).origin, float(pr[2])])
		var length := 0.62 if tool == "machado" else 1.45
		var t := txf
		for it in 10:
			var worst := 0.0
			var wp := Vector3.ZERO
			var wn := Vector3.ZERO
			for k in 13:
				var y := lerpf(-0.06, length, float(k) / 12.0)
				for side in [0.0, 0.08, -0.06]:
					var pt: Vector3 = t * Vector3(0, y, side if y > length * 0.75 else 0.0)
					for c in caps:
						var A: Vector3 = c[0]
						var B: Vector3 = c[1]
						var ab := B - A
						var u := clampf((pt - A).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
						var q := A + ab * u
						var d := pt - q
						var pen: float = float(c[2]) + 0.02 - d.length()
						if pen > worst:
							worst = pen
							wp = pt
							wn = d.normalized() if d.length() > 0.0001 else Vector3.RIGHT
			if worst <= 0.0:
				break
			var arm := wp - pivot
			if arm.length() < 0.05:
				break
			var axis := arm.cross(wn)
			if axis.length() < 0.0001:
				break
			var ang := atan2(worst + 0.01, arm.length())
			var rot := Basis(axis.normalized(), ang)
			t = Transform3D(rot * t.basis, pivot + rot * (t.origin - pivot))
		return t

	## Ferramenta no espaço do esqueleto: base do cabo, direção do cabo e do fio.
	static func _tool_xf(base: Vector3, handle: Vector3, edge: Vector3) -> Transform3D:
		var y := handle.normalized()
		var z := (edge - y * edge.dot(y)).normalized()
		var x := y.cross(z).normalized()
		return Transform3D(Basis(x, y, z), base)

	func _set_tool(sk: Skeleton3D, txf: Transform3D) -> void:
		if axe == null:
			return
		var gx := sk.global_transform * txf
		gx.basis = gx.basis.orthonormalized()
		axe.global_transform = gx

	## Onde a lâmina está (no mundo): para mostrar as lascas e o corte no tronco.
	func blade_point() -> Vector3:
		if axe == null:
			return Vector3.ZERO
		return axe.global_transform * Vector3(0, 0.52, 0.16)
