extends Node3D
## Máquinas e sistemas construídos por PROJETO (planta): o jogador escolhe o projeto,
## põe a planta no chão (só o desenho, em azul) e vai trazendo cada madeira — ela vai
## para o lugar dela na planta — e a lâmina; depois amarra cada junta com cipó.
## Pronta, a máquina funciona.
##
## Serra de pedal (só em dupla): um pisa no pedal (a lâmina sobe e desce: o pedal puxa
## para baixo pelo cipó e a vara de mola lá em cima puxa de volta para cima) e o outro
## empurra a tora pela mesa contra a lâmina. Os dentes da lâmina ficam virados para a
## tora que chega (do lado da mesa), longe da vara de mola e da armação de levantar.
## A tora sai do outro lado aberta em tábuas.
##
## Medidas no espaço da máquina: x = caminho da tora (ela entra pelo +x e sai pelo -x,
## a lâmina fica em x = 0), z = de lado, y = para cima.

const Arvores := preload("res://scripts/world/arvores.gd")

const TIPOS := {
	"serra_pedal": {
		"nome": "Serra de Pedal",
		"desc": "Serraria de madeira movida a pé. Um jogador pisa no pedal e a lâmina sobe e desce; o outro empurra a tora pela mesa contra a serra. A tora sai aberta em tábuas. Só funciona em dupla.",
		"lamina": Vector3(0.0, 1.32, 0.0),
		# [tipo da madeira, comprimento (m), centro, deitada ao longo de "x"/"z" ou "y" (em pé), raio]
		"pecas": [
			["meia", 3.0, Vector3(0.0, 0.1, 0.45), "x", 0.13],      # 0 base esquerda
			["meia", 3.0, Vector3(0.0, 0.1, -0.45), "x", 0.13],     # 1 base direita
			["meia", 1.25, Vector3(-1.2, 0.28, 0.0), "z", 0.12],    # 2 travessa do pedal
			["meia", 1.25, Vector3(1.25, 0.28, 0.0), "z", 0.12],    # 3 travessa da mesa
			["tora", 2.3, Vector3(0.0, 1.32, 0.45), "y", 0.09],     # 4 coluna esquerda
			["tora", 2.3, Vector3(0.0, 1.32, -0.45), "y", 0.09],    # 5 coluna direita
			["meia", 1.25, Vector3(0.0, 2.52, 0.0), "z", 0.12],     # 6 travessa de cima
			["tora", 2.6, Vector3(-0.8, 2.68, 0.0), "x", 0.05],     # 7 vara de mola
			["tora", 0.6, Vector3(1.25, 0.66, 0.3), "y", 0.07],     # 8 pé da mesa
			["tora", 0.6, Vector3(1.25, 0.66, -0.3), "y", 0.07],    # 9 pé da mesa
			["meia", 2.2, Vector3(1.0, 1.0, 0.3), "x", 0.1],        # 10 trilho da mesa
			["meia", 2.2, Vector3(1.0, 1.0, -0.3), "x", 0.1],       # 11 trilho da mesa
			["tabua", 0.9, Vector3(0.6, 1.09, 0.0), "z", 0.17],     # 12 tábua da mesa
			["tabua", 0.9, Vector3(1.65, 1.09, 0.0), "z", 0.17],    # 13 tábua da mesa
			["tabua", 0.9, Vector3(-1.2, 0.4, 0.0), "z", 0.17],     # 14 pedal
		],
		# [peças que a junta prende, ponto]
		"amarras": [
			[[0, 4], Vector3(0.0, 0.26, 0.45)], [[1, 5], Vector3(0.0, 0.26, -0.45)],
			[[4, 6], Vector3(0.0, 2.5, 0.45)], [[5, 6], Vector3(0.0, 2.5, -0.45)],
			[[6, 7], Vector3(0.0, 2.62, 0.0)],
			[[0, 2], Vector3(-1.2, 0.22, 0.45)], [[1, 2], Vector3(-1.2, 0.22, -0.45)],
			[[0, 3], Vector3(1.25, 0.22, 0.45)], [[1, 3], Vector3(1.25, 0.22, -0.45)],
			[[3, 8], Vector3(1.25, 0.4, 0.3)], [[3, 9], Vector3(1.25, 0.4, -0.3)],
			[[8, 10], Vector3(1.25, 0.95, 0.3)], [[9, 11], Vector3(1.25, 0.95, -0.3)],
			[[10, 11, 12], Vector3(0.6, 1.06, 0.0)], [[10, 11, 13], Vector3(1.65, 1.06, 0.0)],
			[[2, 14], Vector3(-1.2, 0.36, 0.0)],
		],
		"area": Rect2(-1.6, -0.6, 3.7, 1.2),     # no chão (x, z)
	},
}

const NOMES := {"tora": "tora redonda", "meia": "meia tora (tora rachada ao meio)", "tabua": "tábua"}
const BOARD_T := 0.05            # grossura das tábuas que a serra tira (m)

var plantas: Array = []          # {tipo, x, y, z, yaw, pecas: [bool], amarras: [bool], lamina, tora, prog}
var inputs := {}                 # quem está mexendo: id -> {mi, pedal, emp, t}
var _jogo: Node
var _arv: Node
var _nodes := {}                 # índice da planta -> {root, lamina}
var _ghost_mat: StandardMaterial3D
var _mark_mat: StandardMaterial3D
var _lash_mat: StandardMaterial3D
var _steel_mat: StandardMaterial3D
var _bob := 0.0


func build(jogo: Node, arvores: Node, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.albedo_color = Color(0.35, 0.65, 1.0, 0.32)
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mark_mat = StandardMaterial3D.new()
	_mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark_mat.albedo_color = Color(1.0, 0.82, 0.2)
	_lash_mat = StandardMaterial3D.new()
	_lash_mat.vertex_color_use_as_albedo = true
	_lash_mat.vertex_color_is_srgb = true
	_lash_mat.roughness = 0.9
	_steel_mat = StandardMaterial3D.new()
	_steel_mat.albedo_color = Color(0.55, 0.56, 0.58)
	_steel_mat.metallic = 0.6
	_steel_mat.roughness = 0.45
	_steel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if save_path != "":
		_load(save_path)
	_rebuild()


# ================== PLANTA ==================

static func info(tipo: String) -> Dictionary:
	return TIPOS.get(tipo, {})


## Quanto de cada coisa o projeto pede: {tora: n, meia: n, tabua: n, cipo: n, lamina: 1}
static func needs(tipo: String) -> Dictionary:
	var t: Dictionary = TIPOS[tipo]
	var out := {"tora": 0, "meia": 0, "tabua": 0}
	for pc in t.pecas:
		out[pc[0]] = int(out[pc[0]]) + 1
	out["cipo"] = (t.amarras as Array).size()
	out["lamina"] = 1
	return out


func add_planta(tipo: String, x: float, z: float, yaw: float) -> void:
	var t: Dictionary = TIPOS[tipo]
	var pcs := []
	for _p in t.pecas:
		pcs.append(false)
	var am := []
	for _a in t.amarras:
		am.append(false)
	plantas.append({"tipo": tipo, "x": x, "y": _jogo.surface_at(x, z), "z": z, "yaw": yaw, "pecas": pcs, "amarras": am,
		"lamina": false, "tora": {}, "prog": 0.0})
	_rebuild()


func xform(mi: int) -> Transform3D:
	var p: Dictionary = plantas[mi]
	return Transform3D(Basis(Vector3.UP, float(p.yaw)), Vector3(float(p.x), float(p.y), float(p.z)))


static func slot_basis(dir: String) -> Basis:
	match dir:
		"z": return Basis(Vector3.UP, PI * 0.5)
		"y": return Basis(Vector3.BACK, PI * 0.5)
	return Basis()


## A madeira que a peça da planta usa (no tamanho dela).
static func slot_log(pc: Array) -> Dictionary:
	var kind := str(pc[0])
	var L := float(pc[1])
	var r := float(pc[4])
	var sec := Arvores.circle_sec()
	if kind == "meia":
		sec = Arvores.split_sec(sec, false)[0]
	elif kind == "tabua":
		var h: Array = Arvores.split_sec(sec, false)
		sec = Arvores.split_sec(h[0], true)[0]
	return {"cil": {"L": L, "ra": r, "rb": r}, "sec": sec, "pos": [0, 0, 0], "yaw": 0.0, "dia": 0, "v": 0, "s": 1.0, "h0": 0.0, "h1": 1.0, "bot": {}, "top": {}}


## Que tipo de madeira é essa: "tora" (redonda), "meia" (rachada grossa) ou "tabua".
func kind_of(fl: Dictionary) -> String:
	if not fl.has("sec"):
		return "tora"
	# pela área da seção (círculo inteiro = 3,14): inteira, metade, ou menos (tábua)
	var area: float = Arvores._poly_area(fl.sec)
	if area > 2.6:
		return "tora"
	if area > 1.15:
		return "meia"
	return "tabua"


func planta_near(pos: Vector3, reach := 3.0) -> int:
	var best := -1
	var bd := reach
	for i in plantas.size():
		var p: Dictionary = plantas[i]
		var d := Vector2(float(p.x) - pos.x, float(p.z) - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func done_count(mi: int) -> int:
	var n := 0
	for b in plantas[mi].pecas:
		if bool(b):
			n += 1
	return n


func pronta(mi: int) -> bool:
	var p: Dictionary = plantas[mi]
	if not bool(p.lamina):
		return false
	for b in p.pecas:
		if not bool(b):
			return false
	for b in p.amarras:
		if not bool(b):
			return false
	return true


## A peça vazia da planta para essa madeira (a mais perto do jogador), ou {i: -1, why}.
func slot_for(mi: int, fl: Dictionary, pos: Vector3) -> Dictionary:
	var p: Dictionary = plantas[mi]
	var t: Dictionary = TIPOS[p.tipo]
	var kind := kind_of(fl)
	var L: float = _arv.free_log_length(fl)
	var r: float = _arv.free_log_max_radius(fl)
	var best := -1
	var bd := 1e9
	var short := 0.0
	var any_kind := false
	var xf := xform(mi)
	for i in (t.pecas as Array).size():
		if bool(p.pecas[i]):
			continue
		var pc: Array = t.pecas[i]
		if str(pc[0]) != kind:
			continue
		any_kind = true
		if L < float(pc[1]) * 0.85:
			short = maxf(short, float(pc[1]))
			continue
		if kind == "tora" and r > float(pc[4]) * 2.6:
			continue                   # tora grossa demais para essa peça
		var w := xf * (pc[2] as Vector3)
		var d := Vector2(w.x - pos.x, w.z - pos.z).length()
		if d < bd:
			bd = d
			best = i
	if best >= 0:
		return {"i": best}
	if not any_kind:
		return {"i": -1, "why": "A planta não precisa de mais %s." % NOMES.get(kind, kind)}
	if short > 0.0:
		return {"i": -1, "why": "Essa madeira é curta: essa peça precisa de %.1f m." % short}
	return {"i": -1, "why": "Essa tora é grossa demais para as peças que faltam (precisa ser fina)."}


func fill_slot(mi: int, si: int) -> void:
	plantas[mi].pecas[si] = true
	_rebuild()


## Juntas que já dá para amarrar (as peças delas estão no lugar) e ainda não foram.
func joint_near(pos: Vector3, reach := 1.7) -> Array:
	var best := []
	var bd := reach
	for mi in plantas.size():
		var p: Dictionary = plantas[mi]
		var t: Dictionary = TIPOS[p.tipo]
		var xf := xform(mi)
		for ji in (t.amarras as Array).size():
			if bool(p.amarras[ji]) or not _joint_open(mi, ji):
				continue
			var w := xf * (t.amarras[ji][1] as Vector3)
			var d := Vector2(w.x - pos.x, w.z - pos.z).length()
			if d < bd:
				bd = d
				best = [mi, ji]
	return best


func joint_point(mi: int, ji: int) -> Vector3:
	var t: Dictionary = TIPOS[plantas[mi].tipo]
	return xform(mi) * (t.amarras[ji][1] as Vector3)


func _joint_open(mi: int, ji: int) -> bool:
	var p: Dictionary = plantas[mi]
	var t: Dictionary = TIPOS[p.tipo]
	for si in t.amarras[ji][0]:
		if not bool(p.pecas[int(si)]):
			return false
	return true


func tie(mi: int, ji: int) -> void:
	plantas[mi].amarras[ji] = true
	_rebuild()


func pending_joints(mi: int) -> int:
	var n := 0
	for b in plantas[mi].amarras:
		if not bool(b):
			n += 1
	return n


# ================== A SERRA FUNCIONANDO ==================

## Lugar de cada um na serra: "pedal" (atrás, do lado do pedal), "mesa" (na ponta da
## mesa, empurrando) ou "".
func role_at(mi: int, pos: Vector3) -> String:
	var l := xform(mi).affine_inverse() * pos
	if l.x < -1.0 and l.x > -2.6 and absf(l.z) < 1.2:
		return "pedal"
	if l.x > 1.4 and l.x < 3.6 and absf(l.z) < 1.2:
		return "mesa"
	return ""


## Põe a tora na mesa (do lado de fora, pronta para empurrar).
func load_log(mi: int, fl: Dictionary) -> void:
	plantas[mi].tora = fl
	plantas[mi].prog = 0.0
	_rebuild()


## Quem manda no corte (o dono do mundo, ou quem joga sozinho): soma o pedal e o
## empurrão de todo mundo. A lâmina só corta com o pedal andando E a tora empurrada.
func update(delta: float, authority: bool, solo_ok: bool) -> void:
	_bob += delta
	var now := Time.get_ticks_msec()
	for mi in plantas.size():
		var p: Dictionary = plantas[mi]
		var pedal := 0.0
		var emp := 0.0
		for id in inputs.keys():
			var inp: Dictionary = inputs[id]
			if now - int(inp.t) > 600:
				inputs.erase(id)
				continue
			if int(inp.mi) != mi:
				continue
			pedal = maxf(pedal, float(inp.pedal))
			emp = maxf(emp, float(inp.emp))
		if solo_ok and emp > 0.0 and pedal <= 0.0:
			pedal = emp                 # modo de teste: sozinho a serra pedala sola
		p["_pedal"] = pedal
		# a lâmina sobe e desce no ritmo do pedal (só desenho, em todo celular)
		var nd: Dictionary = _nodes.get(mi, {})
		if nd.has("lamina") and is_instance_valid(nd.lamina):
			var ph := float(p.get("_ph", 0.0)) + delta * clampf(pedal, 0.0, 3.0) * 7.0
			p["_ph"] = ph
			(nd.lamina as Node3D).position = (TIPOS[p.tipo].lamina as Vector3) + Vector3(0, sin(ph) * 0.12, 0)
		if nd.has("tora") and is_instance_valid(nd.tora) and not (p.tora as Dictionary).is_empty():
			(nd.tora as Node3D).position = _log_pos(mi)
		if not authority or (p.tora as Dictionary).is_empty() or not pronta(mi):
			continue
		var rate := minf(pedal, emp)
		if rate <= 0.02:
			continue
		var L: float = _arv.free_log_length(p.tora)
		var r: float = _arv.free_log_max_radius(p.tora)
		# madeira grossa demora mais (anda uns 8 cm por segundo numa tora de 20 cm)
		p.prog = float(p.prog) + rate * delta * 0.08 / maxf(r / 0.1, 0.6) / L
		if float(p.prog) >= 1.0:
			_finish_cut(mi)


## Onde a tora está na mesa (centro dela, no espaço da máquina).
func _log_pos(mi: int) -> Vector3:
	var p: Dictionary = plantas[mi]
	var L: float = _arv.free_log_length(p.tora)
	var r: float = _arv.free_log_max_radius(p.tora)
	# começa com a ponta encostando na lâmina e vai passando para o -x
	var x := L * 0.5 + 0.02 - float(p.prog) * L
	return Vector3(x, 1.12 + r, 0.0)


## Terminou de passar: a tora vira tábuas (e as duas costaneiras com casca) do lado de lá.
func _finish_cut(mi: int) -> void:
	var p: Dictionary = plantas[mi]
	var fl: Dictionary = p.tora
	p.tora = {}
	p.prog = 0.0
	var pieces := rip(fl)
	var xf := xform(mi)
	var k := 0
	for pc in pieces:
		var at := xf * Vector3(-1.9 - _arv.free_log_length(pc) * 0.0, 0.0, -0.4 + k * 0.28)
		_arv.drop_log(pc, at + Vector3(0, 0.2, 0), float(p.yaw))
		k += 1
	_rebuild()
	if _jogo.has_method("_show_toast"):
		_jogo._show_toast("A serra abriu a tora em %d peças (tábuas e costaneiras)!" % pieces.size())


## Abre a madeira em fatias de BOARD_T de grossura (cortes paralelos, na vertical da
## seção deitada): o meio sai tábua, as beiradas saem costaneiras com casca.
func rip(fl: Dictionary) -> Array:
	var sec: Dictionary = fl.sec if fl.has("sec") else Arvores.circle_sec()
	var cil: Dictionary
	if fl.has("cil"):
		cil = (fl.cil as Dictionary).duplicate()
	else:
		var L: float = _arv.free_log_length(fl)
		cil = {"L": L, "ra": _arv.free_log_radius_at(fl, 0.02), "rb": _arv.free_log_radius_at(fl, 0.98)}
	var r := maxf(float(cil.ra), float(cil.rb))
	var t := BOARD_T / maxf(r, 0.01)
	var mn := 1e9
	var mx := -1e9
	for q in sec.pts:
		mn = minf(mn, float(q[0]))
		mx = maxf(mx, float(q[0]))
	var out := []
	var a := mn
	while a < mx - 0.0001:
		var b := minf(a + t, mx)
		if mx - b < t * 0.35:
			b = mx                      # a última lasca fina vai junto
		var poly := _band(sec.pts, a, b)
		if poly.size() >= 3:
			out.append({"cil": cil.duplicate(), "sec": Arvores._lay_flat(poly, sec.ax), "v": int(fl.get("v", 0)), "s": 1.0,
				"h0": 0.0, "h1": 1.0, "bot": {}, "top": {}, "pos": [0, 0, 0], "yaw": 0.0, "dia": int(fl.get("dia", 0))})
		a = b
	return out


## Pedaço da seção entre z = a e z = b (cortes da serra: arestas novas são face serrada).
static func _band(pts_in: Array, a: float, b: float) -> Array:
	var poly := []
	for q in pts_in:
		poly.append([float(q[0]), float(q[1]), int(q[2])])
	poly = _clip(poly, a, 1.0)
	poly = _clip(poly, b, -1.0)
	return poly


## Corta o polígono [z, y, tipo da aresta que sai] pela reta z = v, ficando do lado
## s*(z - v) >= 0. A aresta nova (o corte) é do tipo 1 (madeira).
static func _clip(poly: Array, v: float, s: float) -> Array:
	var out := []
	var n := poly.size()
	if n < 3:
		return out
	for k in n:
		var P: Array = poly[k]
		var Q: Array = poly[(k + 1) % n]
		var inP: bool = s * (float(P[0]) - v) >= 0.0
		var inQ: bool = s * (float(Q[0]) - v) >= 0.0
		if inP:
			out.append([P[0], P[1], P[2]])
		if inP != inQ:
			var f := (v - float(P[0])) / (float(Q[0]) - float(P[0]))
			var I := [v, lerpf(float(P[1]), float(Q[1]), f)]
			if inP:
				# saindo: do ponto de corte segue pelo corte (madeira)
				out.append([I[0], I[1], 1])
			else:
				# entrando: do ponto de corte segue a aresta original
				out.append([I[0], I[1], P[2]])
	return out


# ================== ESBARRAR ==================

func push_out(p: Vector3) -> Vector3:
	for mi in plantas.size():
		if done_count(mi) < 3:
			continue
		var t: Dictionary = TIPOS[plantas[mi].tipo]
		var ar: Rect2 = t.area
		var xf := xform(mi)
		var l := xf.affine_inverse() * p
		var R := 0.25
		if l.x > ar.position.x - R and l.x < ar.end.x + R and l.z > ar.position.y - R and l.z < ar.end.y + R:
			var pens := [l.x - (ar.position.x - R), ar.end.x + R - l.x, l.z - (ar.position.y - R), ar.end.y + R - l.z]
			var k := 0
			for i in 4:
				if float(pens[i]) < float(pens[k]):
					k = i
			match k:
				0: l.x = ar.position.x - R
				1: l.x = ar.end.x + R
				2: l.z = ar.position.y - R
				3: l.z = ar.end.y + R
			var w := xf * l
			p.x = w.x
			p.z = w.z
	return p


# ================== DESENHO ==================

func _rebuild() -> void:
	for k in _nodes:
		var nd: Dictionary = _nodes[k]
		if is_instance_valid(nd.root):
			(nd.root as Node).queue_free()
	_nodes.clear()
	for mi in plantas.size():
		var p: Dictionary = plantas[mi]
		var t: Dictionary = TIPOS[p.tipo]
		var root := Node3D.new()
		add_child(root)
		root.transform = xform(mi)
		var nd := {"root": root}
		for si in (t.pecas as Array).size():
			var pc: Array = t.pecas[si]
			var b := slot_basis(str(pc[3]))
			if bool(p.pecas[si]):
				var n: Node3D = _arv.free_log_node(slot_log(pc))
				root.add_child(n)
				n.transform = Transform3D(b, pc[2])
			else:
				var mi2 := MeshInstance3D.new()
				var bm := BoxMesh.new()
				var r := float(pc[4])
				bm.size = Vector3(float(pc[1]), r * (2.0 if str(pc[0]) == "tora" else (1.0 if str(pc[0]) == "meia" else 0.5)), r * 2.0)
				mi2.mesh = bm
				mi2.material_override = _ghost_mat
				mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(mi2)
				mi2.transform = Transform3D(b, pc[2])
		# juntas: amarradas (voltas de cipó) ou esperando (bolinha amarela)
		for ji in (t.amarras as Array).size():
			var at: Vector3 = t.amarras[ji][1]
			if bool(p.amarras[ji]):
				var lm := MeshInstance3D.new()
				lm.mesh = _lash_mesh()
				lm.material_override = _lash_mat
				lm.position = at
				root.add_child(lm)
			elif _joint_open(mi, ji):
				var mk := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.06
				sm.height = 0.12
				mk.mesh = sm
				mk.material_override = _mark_mat
				mk.position = at
				root.add_child(mk)
		# a lâmina (dentes virados para a mesa, +x)
		if bool(p.lamina):
			var lam := MeshInstance3D.new()
			lam.mesh = _blade_mesh()
			lam.material_override = _steel_mat
			lam.position = t.lamina
			root.add_child(lam)
			nd["lamina"] = lam
		else:
			var gl := MeshInstance3D.new()
			var gb := BoxMesh.new()
			gb.size = Vector3(0.14, 1.1, 0.01)
			gl.mesh = gb
			gl.material_override = _ghost_mat
			gl.position = t.lamina
			root.add_child(gl)
		# pronta: os cipós do pedal até a lâmina e da lâmina até a vara de mola
		if pronta(mi):
			_rope(root, Vector3(0.0, 1.32 + 0.55, 0.0), Vector3(0.45, 2.66, 0.0))
			_rope(root, Vector3(0.0, 1.32 - 0.55, 0.0), Vector3(-1.2, 0.46, 0.35))
		# a tora na mesa
		if not (p.tora as Dictionary).is_empty():
			var tn: Node3D = _arv.free_log_node(p.tora)
			root.add_child(tn)
			tn.position = _log_pos(mi)
			nd["tora"] = tn
		_nodes[mi] = nd


func _rope(root: Node3D, a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.008
	cm.bottom_radius = 0.008
	cm.height = a.distance_to(b)
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.2, 0.1)
	mi.material_override = m
	root.add_child(mi)
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.1:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	mi.transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)


## Lâmina de pedra/ferro: tira comprida em pé, com os dentes na beira que olha para a mesa.
static func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var H := 1.1
	var W := 0.1
	var T := 0.006
	for zz in [-T, T]:
		for v in [Vector3(-W * 0.5, -H * 0.5, zz), Vector3(W * 0.5, -H * 0.5, zz), Vector3(W * 0.5, H * 0.5, zz),
				Vector3(-W * 0.5, -H * 0.5, zz), Vector3(W * 0.5, H * 0.5, zz), Vector3(-W * 0.5, H * 0.5, zz)]:
			st.add_vertex(v)
	# dentes (triângulos) na beira +x, inclinados para baixo (cortam descendo)
	var n := 22
	for k in n:
		var y0 := -H * 0.5 + H * k / n
		var y1 := -H * 0.5 + H * (k + 1) / n
		for v in [Vector3(W * 0.5, y0, 0), Vector3(W * 0.5, y1, 0), Vector3(W * 0.5 + 0.025, y0 + 0.004, 0)]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func _lash_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.2, 0.15, 0.07)
	for ring in 3:
		var basis: Basis = [Basis(), Basis(Vector3.RIGHT, PI * 0.5), Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5)][ring]
		for turn in 3:
			var rr := 0.1 + turn * 0.008
			var segs := 14
			for k in segs:
				var a0 := TAU * k / segs
				var a1 := TAU * (k + 1) / segs
				var p0: Vector3 = basis * Vector3(cos(a0) * rr, (turn - 1) * 0.014, sin(a0) * rr)
				var p1: Vector3 = basis * Vector3(cos(a1) * rr, (turn - 1) * 0.014, sin(a1) * rr)
				var w: Vector3 = basis * Vector3(0, 0.006, 0)
				for v in [p0 - w, p1 - w, p1 + w, p0 - w, p1 + w, p0 + w]:
					st.set_color(col.darkened(0.1 * turn))
					st.add_vertex(v)
	st.generate_normals()
	return st.commit()


# ================== SALVAR ==================

func save(path: String) -> void:
	var out := []
	for p in plantas:
		var c: Dictionary = {}
		for k in p:
			if not str(k).begins_with("_"):
				c[k] = p[k]
		c.prog = snappedf(float(c.prog), 0.01)
		out.append(c)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "plantas": out}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return false
	var old := plantas
	plantas = d.get("plantas", [])
	# o ritmo da lâmina continua (é só desenho)
	for i in mini(old.size(), plantas.size()):
		if (old[i] as Dictionary).has("_ph"):
			plantas[i]["_ph"] = old[i]._ph
	return true
