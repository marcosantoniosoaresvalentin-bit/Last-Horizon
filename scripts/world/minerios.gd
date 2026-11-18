extends Node
## Minérios e sílex: depósitos formados pela geologia da ilha, escondidos debaixo da terra.
##
## Os depósitos são criados uma vez só, com o mundo (é o resultado de milhões de anos),
## seguindo a rocha de cada região, o relevo, a água e o intemperismo:
##  - Formação ferrífera (faixas dentro do gnaisse e do xisto): corpos compridos de
##    HEMATITA perto de cima (onde a água e o ar já oxidaram) que viram MAGNETITA mais
##    fundo (o minério original, preto e pesado).
##  - Contato do granito com o gnaisse/xisto: lentes de MAGNETITA, fundas.
##  - Platôs e encostas suaves muito intemperizados: couraça de GOETHITA (a "canga"
##    amarelo-amarronzada) logo abaixo do solo; nas baixadas encharcadas, bolsões de
##    goethita de brejo.
##  - Calcário (dentro das planícies de sedimento antigo): camadas com NÓDULOS DE SÍLEX,
##    horizontais; onde o morro corta a camada, ela fica rasa na encosta.
##  - Falhas (fraturas) nas serras de granito, gnaisse e xisto: algumas tiveram água quente
##    circulando e deixaram VEIOS DE COBRE: CALCOPIRITA embaixo e, perto da superfície,
##    onde a água da chuva e o ar alteraram o veio, MALAQUITA (verde); no topo do veio, o
##    "chapéu de ferro" de goethita. Em volta do veio, a rocha fica alterada (esbranquiçada
##    e esverdeada), o que só dá para ver cavando.
##  - Cascalho dos leitos e baixadas: pedaços que a erosão trouxe das rochas de cima
##    (sílex, pedrinhas de hematita e goethita), enterrados no sedimento.
## Nada fica na superfície: tudo está a pelo menos uns 35 cm de terra.
##
## Com o tempo do jogo (a cada mês), a chuva e a erosão soltam um pouquinho dos
## depósitos rasos das encostas e a enxurrada leva os pedaços morro abaixo, até onde a
## água perde força; lá ficam enterrados no sedimento. É pouco por mês: não se forma
## jazida grande em meses, só cascalho aos poucos.

const MundoSim := preload("res://scripts/mundo_sim.gd")
const MINERAIS := ["hematita", "magnetita", "goetita", "silex", "malaquita", "calcopirita"]
## Cor de cada um na parede do buraco
const COR := {"hematita": Color(0.52, 0.16, 0.10), "magnetita": Color(0.12, 0.12, 0.13), "goetita": Color(0.62, 0.42, 0.16),
	"silex": Color(0.30, 0.31, 0.33), "malaquita": Color(0.16, 0.52, 0.32), "calcopirita": Color(0.62, 0.55, 0.24),
	"alterada": Color(0.66, 0.68, 0.58)}
const MIN_DEPTH := 0.35
const GRID := 16.0
const PIECE_PER_SAMPLE := 0.8       # pedaços por amostra dentro de minério puro

var bodies: Array = []              # corpos de minério (ver _body)
var strata: Array = []              # camadas de sílex no calcário: [topo, base, densidade, semente]
var _lime: FastNoiseLite
var placers := {}                   # célula (int) -> {mineral: kg} de cascalho enterrado
var mined := {}                     # Vector2i (grade de 0,2 m) -> y mais fundo já tirado
var frac := {}                      # mineral -> pedaço fracionado que sobrou
var last_month := -1
var _jogo: Node
var _sim: Node
var _grid := {}
var _rng := RandomNumberGenerator.new()
var _seed := 1


func build(jogo: Node, seed_: int, save_path := "") -> void:
	_jogo = jogo
	_sim = jogo.sim
	_seed = seed_ if seed_ != 0 else 4242
	_rng.seed = _seed + 7331
	_lime = FastNoiseLite.new()
	_lime.seed = _seed + 12
	_lime.frequency = 0.035
	if save_path == "" or not _load(save_path):
		_generate()
	_index()
	last_month = int(_sim.elapsed_days()) / 30 if last_month < 0 else last_month


# ================== GERAÇÃO (tempo geológico) ==================

func _cell(i: int) -> Vector2:
	return Vector2((i % MundoSim.W + 0.5) * _jogo.CELL, (i / MundoSim.W + 0.5) * _jogo.CELL)


func _surf(x: float, z: float) -> float:
	return _jogo.surface_at(x, z)


func _slope(i: int) -> float:
	var W := MundoSim.W
	var x := i % W
	var y := i / W
	var t: PackedFloat32Array = _sim.ter
	var hx: float = t[y * W + mini(W - 1, x + 1)] - t[y * W + maxi(0, x - 1)]
	var hy: float = t[mini(MundoSim.H - 1, y + 1) * W + x] - t[maxi(0, y - 1) * W + x]
	return Vector2(hx, hy).length() * _jogo.HS / (2.0 * _jogo.CELL)


func _land(i: int) -> bool:
	return float(_sim.ter[i]) > MundoSim.SEA + 0.8


func _generate() -> void:
	var W := MundoSim.W
	var H := MundoSim.H
	var N := W * H
	var rock: PackedByteArray = _sim.rock_name
	var nz := FastNoiseLite.new()
	nz.seed = _seed + 11
	nz.frequency = 0.05
	# --- 1. formação ferrífera: faixas no gnaisse/xisto, ao longo de uma direção (a "foliação")
	var strike := _rng.randf() * PI
	var sdir := Vector2(cos(strike), sin(strike))
	var bif_cells := []
	for i in N:
		if not _land(i) or rock[i] < 2:
			continue
		var p := _cell(i)
		var across := p.dot(Vector2(-sdir.y, sdir.x)) / 55.0 + nz.get_noise_2dv(p * 0.3) * 0.6
		if absf(sin(across * PI)) < 0.12:
			bif_cells.append(i)
	bif_cells.shuffle()
	var nbif := clampi(bif_cells.size() / 18, 0, 9)
	for k in nbif:
		var p: Vector2 = _cell(bif_cells[k]) + Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2))
		var size := _size_class()
		var a: float = [10.0, 22.0, 45.0][size] * _rng.randf_range(0.8, 1.2)
		var b: float = a * _rng.randf_range(0.18, 0.3)
		var top := _surf(p.x, p.y) - _rng.randf_range(0.6, 2.5)
		var th: float = [2.5, 4.5, 7.0][size] * _rng.randf_range(0.8, 1.2)
		var ox := top - _rng.randf_range(2.5, 4.5)          # abaixo disso a hematita vira magnetita
		_body("hematita", "lente", p, a, b, strike, top, maxf(top - th, ox), _rng.randf_range(0.55, 0.9))
		if top - th < ox:
			_body("magnetita", "lente", p, a * 0.9, b * 0.9, strike, ox, top - th, _rng.randf_range(0.5, 0.85))
	# --- 2. contato do granito: lentes de magnetita
	var contact := []
	for i in N:
		if not _land(i) or rock[i] != 1:
			continue
		var x := i % W
		var y := i / W
		for o in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)]:
			var xx: int = clampi(x + o.x, 0, W - 1)
			var yy: int = clampi(y + o.y, 0, H - 1)
			if rock[yy * W + xx] in [2, 3]:
				contact.append(i)
				break
	contact.shuffle()
	for k in clampi(contact.size() / 25, 0, 4):
		var p: Vector2 = _cell(contact[k])
		var size := _size_class()
		var a: float = [6.0, 12.0, 20.0][size]
		var top := _surf(p.x, p.y) - _rng.randf_range(2.5, 5.0)
		_body("magnetita", "lente", p, a, a * _rng.randf_range(0.4, 0.8), _rng.randf() * PI, top, top - [2.0, 3.5, 5.0][size], _rng.randf_range(0.5, 0.85))
	# --- 3. canga de goethita nos platôs intemperizados; goethita de brejo nas baixadas
	var later := FastNoiseLite.new()
	later.seed = _seed + 13
	later.frequency = 0.07
	for i in N:
		if not _land(i):
			continue
		var p := _cell(i)
		var s := _slope(i)
		var hn: float = float(_sim.ter[i]) / maxf(float(_sim.max_h), 1.0)
		var weathered: float = float(_sim.kao[i]) * (1.0 - clampf(s * 2.0, 0.0, 1.0))
		if hn > 0.2 and s < 0.18 and weathered > 0.35 and later.get_noise_2dv(p) > 0.15:
			var top := _surf(p.x, p.y) - _rng.randf_range(0.4, 1.1)
			var jit := Vector2(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.5, 1.5))
			_body("goetita", "lente", p + jit, _rng.randf_range(3.5, 5.5), _rng.randf_range(3.0, 5.0), _rng.randf() * PI, top, top - _rng.randf_range(0.5, 1.6), _rng.randf_range(0.35, 0.75))
		elif float(_sim.wetmem[i]) > 0.45 and later.get_noise_2dv(p + Vector2(300, 0)) > 0.3:
			var top := _surf(p.x, p.y) - _rng.randf_range(0.4, 0.9)
			_body("goetita", "lente", p, _rng.randf_range(2.0, 5.0), _rng.randf_range(1.5, 4.0), _rng.randf() * PI, top, top - _rng.randf_range(0.2, 0.6), _rng.randf_range(0.3, 0.6))
	# --- 4. calcário com camadas de nódulos de sílex
	var lime_cells := []
	for i in N:
		if _land(i) and _is_lime(_cell(i).x, _cell(i).y):
			lime_cells.append(i)
	if not lime_cells.is_empty():
		# camadas horizontais (estratos): altura absoluta de cada uma
		var base := 1e9
		var topy := -1e9
		for i in lime_cells:
			var y: float = _surf(_cell(i).x, _cell(i).y)
			base = minf(base, y)
			topy = maxf(topy, y)
		var y0 := base - 2.0
		while y0 < topy:
			y0 += _rng.randf_range(1.2, 3.0)
			strata.append([y0 + 0.14, y0 - 0.14, _rng.randf_range(0.18, 0.55), _rng.randi() % 100000])
	# --- 5. falhas com veios de cobre
	var hard := []
	for i in N:
		if _land(i) and rock[i] >= 1 and float(_sim.ter[i]) / maxf(float(_sim.max_h), 1.0) > 0.3:
			hard.append(i)
	hard.shuffle()
	var nf := clampi(hard.size() / 120, 0, 6)
	for k in nf:
		var c: Vector2 = _cell(hard[k])
		var ang := _rng.randf() * PI
		var L := _rng.randf_range(40.0, 160.0)
		var A := c - Vector2(cos(ang), sin(ang)) * L * 0.5
		var B := c + Vector2(cos(ang), sin(ang)) * L * 0.5
		if _rng.randf() < 0.45:
			continue                        # falha que não teve água quente: sem cobre
		# o veio é mineralizado em trechos (bolsões ao longo da falha)
		var pieces := _rng.randi_range(1, 4)
		for q in pieces:
			var t0 := _rng.randf_range(0.0, 0.8)
			var t1 := minf(1.0, t0 + _rng.randf_range(0.1, 0.35))
			var pa := A.lerp(B, t0)
			var pb := A.lerp(B, t1)
			var mid := pa.lerp(pb, 0.5)
			var gy := _surf(mid.x, mid.y)
			var w := _rng.randf_range(0.4, 1.8)
			var front := gy - _rng.randf_range(2.5, 4.5)         # até aqui a chuva alterou o veio
			_body("goetita", "veio", pa, w, 0.0, 0.0, gy - MIN_DEPTH, gy - 0.9, 0.5, pb)       # chapéu de ferro
			_body("malaquita", "veio", pa, w, 0.0, 0.0, gy - 0.9, front, _rng.randf_range(0.35, 0.7), pb)
			_body("calcopirita", "veio", pa, w * 0.8, 0.0, 0.0, front, gy - _rng.randf_range(9.0, 14.0), _rng.randf_range(0.4, 0.75), pb)
			_body("alterada", "veio", pa, w + 2.5, 0.0, 0.0, gy - MIN_DEPTH, gy - 12.0, 1.0, pb)   # halo de rocha alterada
	# --- 6. cascalho antigo nos leitos e baixadas, com o que veio de cima
	_initial_placers()


## Tamanho da jazida: muitas pequenas, algumas médias, poucas grandes.
## Calcário: manchas dentro das planícies de sedimento antigo.
func _is_lime(x: float, z: float) -> bool:
	var ci := int(z / _jogo.CELL) * MundoSim.W + int(x / _jogo.CELL)
	if ci < 0 or ci >= _sim.rock_name.size() or _sim.rock_name[ci] != 0:
		return false
	return _lime.get_noise_2d(x, z) > 0.12


func _size_class() -> int:
	var r := _rng.randf()
	return 0 if r < 0.55 else (1 if r < 0.88 else 2)


func _body(m: String, kind: String, p: Vector2, a: float, b: float, ang: float, top: float, bot: float, g: float, p2 := Vector2.ZERO) -> void:
	bodies.append({"m": m, "k": kind, "x": p.x, "z": p.y, "a": a, "b": b, "ang": ang, "top": top, "bot": bot, "g": g,
		"x2": p2.x, "z2": p2.y, "s": _rng.randi() % 100000})


func _initial_placers() -> void:
	# os leitos (muita água passando) e as baixadas guardam o cascalho de milênios
	var N := MundoSim.W * MundoSim.H
	for i in N:
		if not _land(i):
			continue
		var channel: bool = float(_sim.drain[i]) >= float(_sim.drain_min) - 0.4
		if not channel or _slope(i) > 0.12:
			continue
		var src := _upstream_sources(i)
		for m in src:
			var kg: float = float(src[m]) * _rng.randf_range(20.0, 120.0)
			if kg > 0.5:
				_add_placer(i, m, kg)


## O que tem morro acima (até ~80 m) que a água poderia ter trazido.
func _upstream_sources(i: int) -> Dictionary:
	var p := _cell(i)
	var h: float = _sim.ter[i]
	var out := {}
	# sílex: calcário morro acima com camada perto da superfície
	if not strata.is_empty():
		var n := 0
		for k in 24:
			var a := k * 0.7
			var q := p + Vector2(cos(a), sin(a)) * (10.0 + k * 3.0)
			var qi := int(q.y / _jogo.CELL) * MundoSim.W + int(q.x / _jogo.CELL)
			if qi >= 0 and qi < _sim.ter.size() and float(_sim.ter[qi]) > h + 0.5 and _is_lime(q.x, q.y):
				n += 1
		if n > 0:
			out["silex"] = n / 24.0 * 0.6
	for b in bodies:
		if not b.m in ["silex", "hematita", "goetita", "magnetita"]:
			continue
		var c := Vector2(float(b.x), float(b.z))
		var d := c.distance_to(p)
		if d > 80.0:
			continue
		var ci := int(c.y / _jogo.CELL) * MundoSim.W + int(c.x / _jogo.CELL)
		if ci < 0 or ci >= _sim.ter.size() or float(_sim.ter[ci]) <= h + 0.5:
			continue
		var m: String = "goetita" if b.m == "magnetita" else b.m       # a magnetita que rola vira óxido
		out[m] = minf(0.6, float(out.get(m, 0.0)) + float(b.g) * (1.0 - d / 80.0) * 0.12)
	return out


func _add_placer(i: int, m: String, kg: float) -> void:
	if not placers.has(i):
		placers[i] = {}
	placers[i][m] = float(placers[i].get(m, 0.0)) + kg


func _index() -> void:
	_grid.clear()
	for bi in bodies.size():
		var b: Dictionary = bodies[bi]
		var r := maxf(float(b.a), float(b.b)) + 2.0
		var x0 := minf(float(b.x), float(b.x2) if b.k == "veio" else float(b.x)) - r
		var x1 := maxf(float(b.x), float(b.x2) if b.k == "veio" else float(b.x)) + r
		var z0 := minf(float(b.z), float(b.z2) if b.k == "veio" else float(b.z)) - r
		var z1 := maxf(float(b.z), float(b.z2) if b.k == "veio" else float(b.z)) + r
		for gx in range(floori(x0 / GRID), floori(x1 / GRID) + 1):
			for gz in range(floori(z0 / GRID), floori(z1 / GRID) + 1):
				var key := Vector2i(gx, gz)
				if not _grid.has(key):
					_grid[key] = []
				_grid[key].append(bi)


# ================== O QUE TEM NUM PONTO ==================

static func _h(x: float, y: float, z: float, s: int) -> float:
	var v := sin(x * 12.9898 + y * 78.233 + z * 37.719 + float(s) * 0.0137) * 43758.5453
	return v - floor(v)


func _inside(b: Dictionary, x: float, y: float, z: float) -> float:
	var top := float(b.top)
	var bot := float(b.bot)
	if y > top + 0.4 or y < bot - 0.4:
		return 0.0
	var s := int(b.s)
	var wob := sin(x * 0.35 + s) * 0.18 + sin(z * 0.41 - s * 0.7) * 0.18 + sin((x + z) * 1.3 + s) * 0.06
	match str(b.k):
		"lente":
			var dx := x - float(b.x)
			var dz := z - float(b.z)
			var ca := cos(float(b.ang))
			var sa := sin(float(b.ang))
			var u := (dx * ca + dz * sa) / float(b.a)
			var v := (-dx * sa + dz * ca) / float(b.b)
			var r := u * u + v * v
			if r > 1.0 + wob:
				return 0.0
			# a lente afina nas bordas
			var thick := (top - bot) * sqrt(maxf(0.0, 1.0 - r / (1.0 + wob)))
			var mid := (top + bot) * 0.5
			if absf(y - mid) > thick * 0.5:
				return 0.0
			return float(b.g)
		"camada", "nodulos":
			if absf(x - float(b.x)) > float(b.a) + wob * 2.0 or absf(z - float(b.z)) > float(b.b) + wob * 2.0:
				return 0.0
			var wy := (sin(x * 0.21 + s) + sin(z * 0.17)) * 0.12           # a camada ondula um pouco
			if y > top + wy or y < bot + wy:
				return 0.0
			if b.k == "nodulos":
				# nódulos: bolotas espalhadas na camada (voxels de 30 cm)
				var hv := _h(floor(x / 0.3), floor(y / 0.3), floor(z / 0.3), s)
				return 1.0 if hv < float(b.g) else 0.0
			return float(b.g)
		"veio":
			var A := Vector2(float(b.x), float(b.z))
			var B := Vector2(float(b.x2), float(b.z2))
			var p := Vector2(x, z)
			var ab := B - A
			var t := clampf((p - A).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			var d := p.distance_to(A + ab * t)
			# o veio engrossa e afina; as pontas acabam
			var w := float(b.a) * 0.5 * (0.7 + wob * 1.5) * smoothstep(0.0, 0.12, t) * smoothstep(1.0, 0.88, t)
			if d > w or y > top or y < bot:
				return 0.0
			return float(b.g)
	return 0.0


## Mineral num ponto (y absoluto): [nome, teor] ou ["", 0].
func mineral_at(x: float, y: float, z: float) -> Array:
	var gy := _surf(x, z)
	if gy - y < MIN_DEPTH:
		return ["", 0.0]
	var best := ""
	var bg := 0.0
	for bi in _grid.get(Vector2i(floori(x / GRID), floori(z / GRID)), []):
		var b: Dictionary = bodies[bi]
		if b.m == "alterada":
			continue
		var g := _inside(b, x, y, z)
		if g > bg:
			bg = g
			best = b.m
	if best == "" and not strata.is_empty() and _is_lime(x, z):
		for st in strata:
			var wy := (sin(x * 0.21 + float(st[3])) + sin(z * 0.17)) * 0.12
			if y <= float(st[0]) + wy and y >= float(st[1]) + wy:
				if _h(floor(x / 0.3), floor(y / 0.3), floor(z / 0.3), int(st[3])) < float(st[2]):
					best = "silex"
					bg = 1.0
				break
	if best == "":
		# cascalho enterrado no sedimento (entre 20 e 80 cm)
		var ci := int(z / _jogo.CELL) * MundoSim.W + int(x / _jogo.CELL)
		var pl = placers.get(ci)
		var depth := gy - y
		if pl != null and depth > 0.2 and depth < 0.8:
			for m in pl:
				# kg espalhados em 25 m² x 0,6 m de cascalho
				var conc := clampf(float(pl[m]) / 150.0, 0.0, 0.6)
				if _h(floor(x / 0.25), floor(y / 0.25), floor(z / 0.25), hash(m)) < conc and conc > bg:
					best = m
					bg = conc
	return [best, bg]


## Cor da terra nesse ponto (parede do buraco): alpha = quanto aparece.
func tint_at(x: float, y: float, z: float) -> Color:
	var mt := mineral_at(x, y, z)
	if mt[0] != "":
		var c: Color = COR[mt[0]]
		c.a = clampf(0.45 + float(mt[1]) * 0.5, 0.0, 0.9)
		return c
	# rocha alterada em volta dos veios de cobre
	if _surf(x, z) - y >= MIN_DEPTH:
		for bi in _grid.get(Vector2i(floori(x / GRID), floori(z / GRID)), []):
			var b: Dictionary = bodies[bi]
			if b.m == "alterada" and _inside(b, x, y, z) > 0.0:
				var c2: Color = COR.alterada
				c2.a = 0.4
				return c2
	return Color(0, 0, 0, 0)


## A pá tirou a terra entre y_old e y_new em volta de "at": devolve {mineral: pedaços}.
func extract(at: Vector3, y_old: float, y_new: float) -> Dictionary:
	var got := {}
	if y_new >= y_old - 0.005:
		return got
	var offs := [Vector2.ZERO, Vector2(0.18, 0), Vector2(-0.18, 0), Vector2(0, 0.18), Vector2(0, -0.18)]
	for o in offs:
		var x: float = at.x + o.x
		var z: float = at.z + o.y
		var key := Vector2i(roundi(x / 0.2), roundi(z / 0.2))
		var floor_y := float(mined.get(key, 1e9))
		var top := minf(y_old, floor_y)          # o que já foi tirado não conta de novo
		if y_new >= top:
			continue
		mined[key] = minf(floor_y, y_new)
		# amostra o pedaço de terra novo em 2 alturas
		for f in [0.3, 0.75]:
			var y := lerpf(top, y_new, f)
			var mt := mineral_at(x, y, z)
			if mt[0] == "":
				continue
			var amount := float(mt[1]) * PIECE_PER_SAMPLE * 0.5 * clampf((top - y_new) / 0.2, 0.3, 1.5)
			frac[mt[0]] = float(frac.get(mt[0], 0.0)) + amount
	for m in frac.keys():
		var n := int(floor(float(frac[m])))
		if n > 0:
			got[m] = n
			frac[m] = float(frac[m]) - n
	return got


# ================== EROSÃO COM O TEMPO DO JOGO ==================

## Chamado todo dia: uma vez por mês a chuva solta um pouco dos depósitos rasos das
## encostas e a enxurrada leva morro abaixo.
func tick() -> void:
	var month := int(_sim.elapsed_days()) / 30
	if month <= last_month:
		return
	while last_month < month:
		last_month += 1
		_erode_month()


func _erode_month() -> void:
	var wet: float = _sim.wetness()
	if wet < 0.15:
		return                     # na seca quase não tem enxurrada
	# encostas de calcário com camada de sílex rasa: alguns nódulos se soltam e rolam
	if not strata.is_empty():
		for k in 40:
			var i: int = _rng.randi() % _sim.ter.size()
			var p := _cell(i)
			if not _land(i) or _slope(i) < 0.2 or not _is_lime(p.x, p.y):
				continue
			var gy := _surf(p.x, p.y)
			for st in strata:
				if gy - float(st[0]) < 1.2 and gy - float(st[0]) > 0.0:
					var dest := _downhill_trap(i)
					if dest >= 0:
						_add_placer(dest, "silex", wet * float(st[2]) * _rng.randf_range(0.3, 1.2))
					break
	for b in bodies:
		if not b.m in ["silex", "hematita", "goetita", "malaquita"]:
			continue
		var p := Vector2(float(b.x), float(b.z))
		if b.k == "veio":
			p = p.lerp(Vector2(float(b.x2), float(b.z2)), 0.5)
		var gy := _surf(p.x, p.y)
		if gy - float(b.top) > 1.5:
			continue               # funda demais: a chuva não alcança
		var ci := int(p.y / _jogo.CELL) * MundoSim.W + int(p.x / _jogo.CELL)
		if ci < 0 or ci >= _sim.ter.size() or _slope(ci) < 0.15:
			continue               # só nas encostas a água arranca
		var kg := wet * float(b.g) * _rng.randf_range(0.05, 0.4)     # centenas de gramas por mês
		if b.m == "malaquita":
			kg *= 0.2              # mole: quase toda se desfaz no caminho
		var dest := _downhill_trap(ci)
		if dest >= 0:
			_add_placer(dest, b.m, kg)


## Segue a descida mais forte até onde a água perde força (plano, sedimento ou lagoa).
func _downhill_trap(i: int) -> int:
	var W := MundoSim.W
	var t: PackedFloat32Array = _sim.ter
	var cur := i
	for step in 60:
		var x := cur % W
		var y := cur / W
		var best := cur
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			var xx: int = x + o.x
			var yy: int = y + o.y
			if xx < 0 or yy < 0 or xx >= W or yy >= MundoSim.H:
				continue
			var j: int = yy * W + xx
			if t[j] < t[best]:
				best = j
		if best == cur:
			break
		cur = best
		if not _land(cur):
			return -1              # foi para o mar
		if _slope(cur) < 0.06 or float(_sim.deposit[cur]) > 0.2 or float(_sim.bed[cur]) > 0.3:
			return cur
	return cur


# ================== SALVAR ==================

func save(path: String) -> void:
	var m := []
	for k in mined:
		m.append([k.x, k.y, snappedf(float(mined[k]), 0.001)])
	var pl := {}
	for i in placers:
		pl[str(i)] = placers[i]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "corpos": bodies, "estratos": strata, "cascalho": pl, "tirado": m, "resto": frac, "mes": last_month}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	bodies = d.get("corpos", [])
	strata = d.get("estratos", [])
	for b in bodies:
		b.s = int(b.s)
	placers = {}
	var pl: Dictionary = d.get("cascalho", {})
	for k in pl:
		placers[int(k)] = pl[k]
	mined = {}
	for e in d.get("tirado", []):
		mined[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	frac = d.get("resto", {})
	last_month = int(d.get("mes", -1))
	return true
