extends RefCounted
## Olaria: as peças de barro feitas no torno. Cada peça tem um perfil (o contorno de
## fora, de baixo até a boca: [raio, altura] em metros) e quantas bolas de argila
## limpa leva. No torno, o bolo de argila vai virando a peça: centraliza (fica redondo
## e liso), abre o buraco no meio, sobe as paredes e dá a forma.

const PECAS := {
	"vasilha_barro": {"nome": "Vasilha", "argila": 1, "grossura": 0.009,
		"perfil": [[0.045, 0.0], [0.075, 0.02], [0.095, 0.05], [0.105, 0.08], [0.108, 0.09]]},
	"garrafa_barro": {"nome": "Garrafa", "argila": 2, "grossura": 0.008,
		"perfil": [[0.04, 0.0], [0.066, 0.03], [0.072, 0.1], [0.068, 0.15], [0.045, 0.19], [0.021, 0.22], [0.018, 0.26], [0.023, 0.275]]},
	"moringa_barro": {"nome": "Cabaça (moringa)", "argila": 2, "grossura": 0.008,
		"perfil": [[0.05, 0.0], [0.092, 0.035], [0.112, 0.085], [0.104, 0.135], [0.07, 0.17], [0.032, 0.195], [0.027, 0.23], [0.034, 0.245]]},
	"bacia_barro": {"nome": "Bacia", "argila": 3, "grossura": 0.011,
		"perfil": [[0.08, 0.0], [0.13, 0.025], [0.17, 0.06], [0.19, 0.09], [0.197, 0.1]]},
	"filtro_barro": {"nome": "Filtro de barro", "argila": 4, "grossura": 0.012,
		"perfil": [[0.085, 0.0], [0.115, 0.04], [0.125, 0.12], [0.122, 0.22], [0.115, 0.27], [0.12, 0.29]]},
}

const ORDEM := ["vasilha_barro", "garrafa_barro", "moringa_barro", "bacia_barro", "filtro_barro"]

## As etapas no torno: [nome, para onde passar o dedo (1 = para baixo, -1 = para cima), vezes]
const ETAPAS := [
	["Centralizar", 1, 3],
	["Abrir o buraco", 1, 2],
	["Subir as paredes", -1, 4],
	["Dar a forma", -1, 3],
]

const N := 14


## O contorno de fora da peça pronta, em N pontos de baixo até a boca.
static func perfil_final(id: String) -> Array:
	var pf: Array = PECAS[id].perfil
	var top := float(pf[-1][1])
	var out := []
	for i in N:
		var y := top * float(i) / (N - 1)
		var r := float(pf[0][0])
		for k in pf.size() - 1:
			var a: Array = pf[k]
			var b: Array = pf[k + 1]
			if y >= float(a[1]) and y <= float(b[1]):
				var t := (y - float(a[1])) / maxf(0.0001, float(b[1]) - float(a[1]))
				t = t * t * (3.0 - 2.0 * t)
				r = lerpf(float(a[0]), float(b[0]), t)
				break
		out.append(Vector2(r, y))
	return out


## O bolo de argila (as bolas juntas): meio achatado.
static func perfil_bolo(id: String) -> Array:
	var k := pow(float(PECAS[id].argila), 1.0 / 3.0)
	var R := 0.07 * k
	var H := 0.075 * k
	var out := []
	for i in N:
		var h := float(i) / (N - 1)
		out.append(Vector2(R * sqrt(maxf(0.0, 1.0 - pow(h, 2.2))) + 0.004, H * h))
	return out


## Monta a malha da peça no estado de agora. et: progresso de cada etapa (0 a 1).
## Até centralizar, o bolo é torto (balança ao girar); aberto, tem o buraco; subindo
## as paredes e dando forma, vai do bolo até a peça pronta.
static func malha(id: String, et: Array, seed_: int = 1) -> ArrayMesh:
	var c := float(et[0])
	var o := float(et[1])
	var s := float(et[2]) * 0.65 + float(et[3]) * 0.35
	var a := perfil_bolo(id)
	var b := perfil_final(id)
	var outer := []
	for i in N:
		outer.append((a[i] as Vector2).lerp(b[i], s))
	var th := float(PECAS[id].grossura) * lerpf(2.5, 1.0, s)
	var top_y: float = (outer[-1] as Vector2).y
	var hole := o > 0.0
	var depth := o * 0.55 * top_y + s * 0.45 * top_y         # o buraco vai descendo
	var bottom_in := maxf(top_y - depth, float(PECAS[id].grossura) * 1.2)
	var segs := 36
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wob := func(r: float, ang: float, y: float) -> float:
		# torto antes de centralizar
		return r * (1.0 + (1.0 - c) * 0.16 * sin(ang * 2.0 + float(seed_) + y * 25.0) + (1.0 - c) * 0.07 * sin(ang * 5.0 + y * 40.0))
	# o perfil completo: fundo (centro) -> de fora até a boca -> beirada -> de dentro até o fundo de dentro
	var prof := [Vector2(0.0, 0.0)]
	for v in outer:
		prof.append(v)
	if hole:
		var rim: Vector2 = outer[-1]
		var ri := maxf(rim.x - th, 0.004)
		prof.append(Vector2(ri, rim.y))
		for i in range(N - 2, -1, -1):
			var v2: Vector2 = outer[i]
			if v2.y < bottom_in:
				break
			prof.append(Vector2(maxf(v2.x - th, 0.004), v2.y))
		prof.append(Vector2(0.0, bottom_in))
	else:
		prof.append(Vector2(0.0, top_y))
	var rings := []
	for v in prof:
		var ring := []
		for k in segs:
			var ang := TAU * k / segs
			var r: float = wob.call((v as Vector2).x, ang, (v as Vector2).y)
			ring.append(Vector3(cos(ang) * r, (v as Vector2).y, sin(ang) * r))
		rings.append(ring)
	for i in rings.size() - 1:
		for k in segs:
			var k2 := (k + 1) % segs
			var q := [rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]]
			for idx in [0, 2, 1, 0, 3, 2]:
				var p: Vector3 = q[idx]
				st.set_uv(Vector2(float(k) / segs * 4.0, p.y * 10.0))
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()


static var _mat: StandardMaterial3D


## Barro molhado no torno (liso, brilhando um pouco).
static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.42, 0.22, 0.13)
		_mat.roughness = 0.45
		_mat.metallic_specular = 0.25
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var nt := NoiseTexture2D.new()
		var tn := FastNoiseLite.new()
		tn.frequency = 0.05
		nt.noise = tn
		nt.width = 128
		nt.height = 128
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 1.2
		_mat.normal_enabled = true
		_mat.normal_texture = nt
	return _mat


## O desenho da peça (ícone): a silhueta de lado, com a boca.
static func icone(ci: CanvasItem, id: String, c: Vector2, s: float) -> void:
	var pf := perfil_final(id)
	var top: float = (pf[-1] as Vector2).y
	var wmax := 0.0
	for v in pf:
		wmax = maxf(wmax, (v as Vector2).x)
	var k := s * 0.8 / maxf(top, wmax * 2.0)
	var base := c + Vector2(0, top * k * 0.5)
	var poly := PackedVector2Array()
	for v in pf:
		poly.append(base + Vector2(-(v as Vector2).x * k, -(v as Vector2).y * k))
	for i in range(pf.size() - 1, -1, -1):
		var v2: Vector2 = pf[i]
		poly.append(base + Vector2(v2.x * k, -v2.y * k))
	ci.draw_colored_polygon(poly, Color(0.62, 0.33, 0.2))
	# o lado da luz e a boca
	var rim: Vector2 = pf[-1]
	ci.draw_line(base + Vector2(-rim.x * k * 0.6, -top * k * 0.55), base + Vector2(-rim.x * k * 0.3, -top * k * 0.15), Color(0.78, 0.5, 0.34), 3.0, true)
	var mouth := PackedVector2Array()
	for i in 17:
		var a := TAU * i / 16.0
		mouth.append(base + Vector2(cos(a) * rim.x * k, -top * k + sin(a) * rim.x * k * 0.25))
	ci.draw_colored_polygon(mouth, Color(0.25, 0.12, 0.07))
	ci.draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0.12, 0.08, 0.05), 2.0, true)
