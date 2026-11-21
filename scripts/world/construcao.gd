extends Node3D
## Construção livre: as peças de madeira (toras, meias toras, tábuas grandes e pequenas)
## são postas uma a uma onde o jogador quiser — em cima das toras fincadas, umas em
## cima das outras, encostadas, inclinadas — desde que fiquem apoiadas de verdade:
## a peça precisa encostar em alguma coisa (chão, tora fincada ou outra peça) nas
## duas metades do comprimento (viga em cima de duas estacas, tábua deitada no
## assoalho, tábua em pé com o pé no chão e encostada na viga, caibro com o pé na
## parede e a ponta na cumeeira...). E não pode entrar dentro de outra peça.
##
## Cada peça: {log: dados da madeira, p: [x,y,z] centro, q: [x,y,z,w] rotação}.
## No modelo da madeira o comprimento é o eixo X, a grossura o Y e a largura o Z.

const Furo := preload("res://scripts/world/furo.gd")

var pieces: Array = []
var _jogo: Node
var _arv: Node
var _bur: Node
var _nodes: Array = []

const TOUCH := 0.04            # perto assim conta como encostado (m)
const SINK := 0.025            # o quanto pode "entrar" na outra peça (encaixe)


func build(jogo: Node, arvores: Node, buracos: Node, save_path := "") -> void:
	_jogo = jogo
	_arv = arvores
	_bur = buracos
	if save_path != "":
		_load(save_path)
	_rebuild()


# ================== CAIXAS (PEÇAS E ESTACAS) ==================

## Meia medida da madeira nos 3 eixos dela (comprimento, grossura, largura).
func half_ext(fl: Dictionary) -> Vector3:
	var L: float = _arv.free_log_length(fl)
	if fl.has("cil"):
		var e: Vector2 = _arv._sec_ext(fl)
		var r := maxf(float(fl.cil.ra), float(fl.cil.rb))
		return Vector3(L * 0.5, maxf(r * e.x, 0.01), maxf(r * e.y, 0.01))
	var rr: float = _arv.free_log_max_radius(fl) * 0.9
	return Vector3(L * 0.5, rr, rr)


func piece_box(pc: Dictionary) -> Dictionary:
	var q := Quaternion(float(pc.q[0]), float(pc.q[1]), float(pc.q[2]), float(pc.q[3]))
	return {"c": Vector3(float(pc.p[0]), float(pc.p[1]), float(pc.p[2])), "b": Basis(q), "h": half_ext(pc.log), "piece": pc}


## Todas as caixas: as peças e as toras fincadas (em pé).
func boxes() -> Array:
	var out := []
	for pc in pieces:
		out.append(piece_box(pc))
	if _bur:
		for po in _bur.posts:
			var L: float = _arv.free_log_length(po.log)
			var r: float = _arv.free_log_radius(po.log)
			var gy: float = _jogo.surface_at(float(po.x), float(po.z))
			var b := Basis(Vector3.UP, float(po.yaw)) * Basis(Quaternion(Vector3.RIGHT, Vector3.UP))
			out.append({"c": Vector3(float(po.x), gy - float(po.d) + L * 0.5, float(po.z)), "b": b, "h": Vector3(L * 0.5, r, r), "post": po})
	return out


static func _local(bx: Dictionary, p: Vector3) -> Vector3:
	var b: Basis = bx.b
	var d: Vector3 = p - (bx.c as Vector3)
	return Vector3(d.dot(b.x), d.dot(b.y), d.dot(b.z))


## Distância de um ponto até a caixa (0 dentro).
static func _dist(bx: Dictionary, p: Vector3) -> float:
	var l := _local(bx, p)
	var h: Vector3 = bx.h
	return Vector3(maxf(absf(l.x) - h.x, 0.0), maxf(absf(l.y) - h.y, 0.0), maxf(absf(l.z) - h.z, 0.0)).length()


## As duas caixas se cruzam? (teste dos eixos separadores)
static func _overlap(a: Dictionary, b: Dictionary) -> bool:
	var A: Basis = a.b
	var B: Basis = b.b
	var ha: Vector3 = a.h
	var hb: Vector3 = b.h
	var t: Vector3 = (b.c as Vector3) - (a.c as Vector3)
	var axes := [A.x, A.y, A.z, B.x, B.y, B.z]
	for i in 3:
		for j in 3:
			var c: Vector3 = (axes[i] as Vector3).cross(axes[3 + j])
			if c.length_squared() > 1e-6:
				axes.append(c.normalized())
	for ax in axes:
		var L: Vector3 = ax
		var ra := ha.x * absf(A.x.dot(L)) + ha.y * absf(A.y.dot(L)) + ha.z * absf(A.z.dot(L))
		var rb := hb.x * absf(B.x.dot(L)) + hb.y * absf(B.y.dot(L)) + hb.z * absf(B.z.dot(L))
		if absf(t.dot(L)) > ra + rb:
			return false
	return true


## Raio contra a caixa: distância e normal da face, ou {}.
static func _ray_box(bx: Dictionary, o: Vector3, d: Vector3, maxd: float) -> Dictionary:
	var lo := _local(bx, o)
	var b: Basis = bx.b
	var ld := Vector3(d.dot(b.x), d.dot(b.y), d.dot(b.z))
	var h: Vector3 = bx.h
	var tmin := 0.0
	var tmax := maxd
	var nrm := Vector3.ZERO
	for i in 3:
		if absf(ld[i]) < 1e-6:
			if absf(lo[i]) > h[i]:
				return {}
			continue
		var t1 := (-h[i] - lo[i]) / ld[i]
		var t2 := (h[i] - lo[i]) / ld[i]
		var s := -1.0
		if t1 > t2:
			var tt := t1
			t1 = t2
			t2 = tt
			s = 1.0
		if t1 > tmin:
			tmin = t1
			var n := Vector3.ZERO
			n[i] = s
			nrm = n
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return {}
	if nrm == Vector3.ZERO:
		return {}
	return {"t": tmin, "n": (b * nrm).normalized()}


## Do olho para a frente: onde bate (peça, estaca ou chão). {p, n, box} ou {}.
func raycast(o: Vector3, d: Vector3, maxd := 6.0) -> Dictionary:
	var best := {}
	var bt := maxd
	for bx in boxes():
		if (bx.c as Vector3).distance_to(o) > maxd + (bx.h as Vector3).length():
			continue
		var r := _ray_box(bx, o, d, bt)
		if not r.is_empty() and float(r.t) < bt:
			bt = float(r.t)
			best = {"p": o + d * bt, "n": r.n, "box": bx}
	# chão: anda pelo raio até passar para baixo do terreno
	var step := 0.05
	var t := 0.0
	while t < bt:
		var p := o + d * t
		if p.y <= _jogo.height_at(p.x, p.z):
			return {"p": p, "n": Vector3.UP, "box": {}}
		t += step
	return best


# ================== ONDE A PEÇA PODE FICAR ==================

## Testa a peça fl com rotação b no centro c. {ok, why}
func check(fl: Dictionary, b: Basis, c: Vector3, skip = null, support_only := false) -> Dictionary:
	var h := half_ext(fl)
	var g := {"c": c, "b": b, "h": h}
	var core := {"c": c, "b": b, "h": (h - Vector3.ONE * SINK).max(Vector3.ONE * 0.004)}
	var near := []
	for bx in boxes():
		if skip != null and bx.get("piece") == skip:
			continue
		if (bx.c as Vector3).distance_to(c) > h.length() + (bx.h as Vector3).length() + 0.2:
			continue
		near.append(bx)
		if support_only:
			continue
		var bc := {"c": bx.c, "b": bx.b, "h": ((bx.h as Vector3) - Vector3.ONE * 0.01).max(Vector3.ONE * 0.004)}
		if _overlap(core, bc):
			return {"ok": false, "why": "Bate em outra peça."}
	# não pode ficar enterrada
	for sx in ([] if support_only else [-1.0, 1.0]):
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p: Vector3 = c + b.x * h.x * sx + b.y * (h.y - SINK) * sy + b.z * (h.z - SINK) * sz
				if p.y < _jogo.height_at(p.x, p.z) - 0.12:
					return {"ok": false, "why": "Fica enterrada no chão."}
	# onde encosta: pontos na casca da peça, ao longo do comprimento
	var lo := false
	var hi := false
	var n := 13
	# peça deitada só se apoia por baixo (encostar a ponta no lado da estaca não segura);
	# em pé ou inclinada pode se encostar de lado
	var lying := absf(b.x.y) < 0.5
	var down_k := 1 if absf(b.y.y) >= absf(b.z.y) else 2          # o eixo da peça que aponta para baixo
	var down_s := -signf((b[down_k] as Vector3).y)
	var cross := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]
	var joint_u := {}                # caixa encostada (madeira) -> lista dos u onde encosta
	for i in n:
		var u := lerpf(-1.0, 1.0, float(i) / (n - 1))
		for cs in cross:
			var p: Vector3 = c + b.x * h.x * u + b.y * h.y * cs.x + b.z * h.z * cs.y
			var touch: bool = p.y - float(_jogo.height_at(p.x, p.z)) < 0.05
			var wood_i := -1
			for bi in near.size():
				if _dist(near[bi], p) < TOUCH:
					touch = true
					wood_i = bi
					break
			if touch and lying:
				var side_v: float = cs.x if down_k == 1 else cs.y
				# só a face de baixo apoia; o lado só vale encostado numa estaca fincada
				# (presa nela com pino)
				if side_v * down_s <= 0.0 and not (wood_i >= 0 and (near[wood_i] as Dictionary).has("post")):
					touch = false
			if touch and wood_i >= 0:
				if not joint_u.has(wood_i):
					joint_u[wood_i] = []
				joint_u[wood_i].append(u)
			if touch:
				if u <= -0.25:
					lo = true
				if u >= 0.25:
					hi = true
				if absf(u) < 0.25 and h.x < 0.3:
					lo = true          # pecinha curta: encostar no meio já segura
					hi = true
	# estaca fincada encostada em qualquer ponto (presa nela): conta sempre, no
	# ponto exato do comprimento (os pontos de teste podem passar do lado da estaca fina)
	var grown := {"c": c, "b": b, "h": h + Vector3.ONE * TOUCH}
	for bi in near.size():
		var nb: Dictionary = near[bi]
		if not nb.has("post") or not _overlap(grown, nb):
			continue
		var u2 := clampf(((nb.c as Vector3) - c).dot(b.x) / maxf(h.x, 0.001), -1.0, 1.0)
		if u2 <= -0.25:
			lo = true
		if u2 >= 0.25:
			hi = true
		if not joint_u.has(bi):
			joint_u[bi] = [u2]
	if not (lo and hi):
		return {"ok": false, "why": "Não fica apoiada: precisa encostar nas duas metades.", "juntas": []}
	# pinos: um em cada madeira em que encosta (no meio de onde encosta), sem limite:
	# 2 troncos embaixo = 2 pinos, 5 troncos = 5 pinos
	var juntas := []
	for k in joint_u:
		var us: Array = joint_u[k]
		var m := 0.0
		for v in us:
			m += float(v)
		juntas.append(snappedf(m / us.size(), 0.01))
	juntas.sort()
	return {"ok": true, "why": "", "juntas": juntas}


## Acha o lugar da peça perto de onde o olho bateu: encosta a face na superfície e
## escorrega no comprido até ficar apoiada. {ok, c, why}
func _find_place_b(fl: Dictionary, b: Basis, hit: Dictionary) -> Dictionary:
	var h := half_ext(fl)
	var n: Vector3 = hit.n
	var hb0: Dictionary = hit.box
	# mirou o lado de uma estaca ou viga perto do topo, com a peça deitada: vai em cima
	if not hb0.is_empty() and n.y < 0.5 and absf(b.x.y) < 0.5:
		var bb: Basis = hb0.b
		var hh: Vector3 = hb0.h
		var e_up := hh.x * absf(bb.x.y) + hh.y * absf(bb.y.y) + hh.z * absf(bb.z.y)
		var topy: float = (hb0.c as Vector3).y + e_up
		var is_post := absf(bb.x.y) > 0.8
		if (hit.p as Vector3).y > topy - (0.45 if is_post else 0.15):
			var tp: Vector3 = hit.p
			if is_post:
				tp = hb0.c
			hit = {"p": Vector3(tp.x, topy, tp.z), "n": Vector3.UP, "box": hb0}
			n = Vector3.UP
	var ext := h.x * absf(b.x.dot(n)) + h.y * absf(b.y.dot(n)) + h.z * absf(b.z.dot(n))
	var c: Vector3 = (hit.p as Vector3) + n * (ext - 0.004)
	if absf(b.x.y) < 0.5 and n.y > 0.7:
		# deitada (mesmo um pouco inclinada) em cima de algo: a face de baixo passa pelo
		# ponto onde mirou, assim ao escorregar no comprido ela continua encostada
		var k := 1 if absf(b.y.y) >= absf(b.z.y) else 2
		var ax: Vector3 = b[k]
		c = (hit.p as Vector3) + ax * signf(ax.y) * (h[k] - 0.004)
	# viga em cima da estaca/peça: centra a largura em cima dela
	var hb: Dictionary = hit.box
	if not hb.is_empty() and n.y > 0.7:
		var side := (b.z - n * b.z.dot(n))
		if side.length() > 0.3:
			side = side.normalized()
			var off := ((hb.c as Vector3) - c).dot(side)
			var lim: float = (hb.h as Vector3).y + (hb.h as Vector3).z
			if absf(off) < lim:
				c += side * off
	# escorrega no comprido; de todas as posições que ficam apoiadas, fica no meio
	# (a viga fica centrada entre as estacas, não pendurada numa ponta)
	var first := {}
	var steps := int(h.x / 0.08)
	var oks := []
	for k in range(-steps, steps + 1):
		var o := float(k) * 0.08
		var r := check(fl, b, c + b.x * o)
		if bool(r.ok):
			oks.append(o)
		elif first.is_empty() or k == 0:
			first = r
	if oks.is_empty():
		return {"ok": false, "c": c, "why": str(first.get("why", ""))}
	# o pedaço seguido de posições boas mais perto de onde mira
	var best := []
	var run := []
	var bd := 1e9
	for i in oks.size():
		if not run.is_empty() and float(oks[i]) - float(run[run.size() - 1]) > 0.081:
			var dd := absf((float(run[0]) + float(run[run.size() - 1])) * 0.5)
			if dd < bd:
				bd = dd
				best = run
			run = []
		run.append(oks[i])
	var dd2 := absf((float(run[0]) + float(run[run.size() - 1])) * 0.5)
	if dd2 < bd:
		best = run
	var mid := snappedf((float(best[0]) + float(best[best.size() - 1])) * 0.5, 0.08)
	if not best.has(mid):
		mid = float(best[best.size() / 2])
	return {"ok": true, "c": c + b.x * mid, "why": ""}


## Lugar da peça (sem inclinar sozinha: estacas de alturas diferentes precisam ser
## cortadas no nível com o machado). {ok, c, b, why}
func find_place(fl: Dictionary, b: Basis, hit: Dictionary) -> Dictionary:
	var r := _find_place_b(fl, b, hit)
	if not bool(r.ok) and absf(b.x.y) < 0.5:
		# estacas de alturas diferentes: tenta a viga em cima de cada estaca vizinha
		# (a mais baixa), passando do lado da mais alta (amarrada no lado dela)
		var side := Vector3(b.z.x, 0, b.z.z)
		var L := half_ext(fl).x * 2.0
		if side.length() > 0.3:
			side = side.normalized()
			var cands := []
			for bx in boxes():
				if not bx.has("post"):
					continue
				var d := Vector2((bx.c as Vector3).x - (hit.p as Vector3).x, (bx.c as Vector3).z - (hit.p as Vector3).z).length()
				if d < L:
					cands.append([d, bx])
			cands.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
			var done := false
			for cd in cands:
				var pb: Dictionary = cd[1]
				var top := (pb.c as Vector3) + (pb.b as Basis).x * (pb.h as Vector3).x
				for lat in [0.0, 0.21, -0.21]:
					var h2 := {"p": top + side * float(lat), "n": Vector3.UP, "box": pb if lat == 0.0 else {}}
					var r2 := _find_place_b(fl, b, h2)
					if bool(r2.ok):
						r = r2
						done = true
						break
				if done:
					break
	r.b = b
	r.juntas = (check(fl, b, r.c).get("juntas", []) as Array) if bool(r.ok) else []
	return r


func add(fl: Dictionary, b: Basis, c: Vector3, juntas := []) -> void:
	fl.erase("em_pe")
	fl.erase("racha")
	var q := b.get_rotation_quaternion()
	# cada encosto em madeira é um lugar de pino (ainda sem pino: o jogador bate depois)
	var pinos := []
	for u in juntas:
		pinos.append([float(u), 0])      # 0 sem nada, 1 furado, 2 com o pino
	pieces.append({"log": fl, "p": [c.x, c.y, c.z], "q": [q.x, q.y, q.z, q.w], "pinos": pinos})
	_rebuild()


## Peça que o olho está mirando (para desmontar), ou {}.
func aimed_piece(o: Vector3, d: Vector3, maxd := 3.0) -> Dictionary:
	var best := {}
	var bt := maxd
	for pc in pieces:
		var bx := piece_box(pc)
		var r := _ray_box(bx, o, d, bt)
		if not r.is_empty() and float(r.t) < bt:
			bt = float(r.t)
			best = pc
	return best


## Alguma peça está em cima desta (encostada e mais alta)?
func carrying_others(pc: Dictionary) -> bool:
	var me := piece_box(pc)
	for o in pieces:
		if o == pc:
			continue
		var ob := piece_box(o)
		if (ob.c as Vector3).y <= (me.c as Vector3).y + 0.02:
			continue
		var grown := {"c": me.c, "b": me.b, "h": (me.h as Vector3) + Vector3.ONE * TOUCH}
		if _overlap(grown, ob):
			return true
	return false


## Depois que some uma estaca ou peça (cupim): o que ficou sem apoio cai no chão,
## e o que estava em cima cai junto. Devolve quantas peças caíram.
func settle() -> int:
	var fell := 0
	var changed := true
	while changed:
		changed = false
		for pc in pieces.duplicate():
			var bx := piece_box(pc)
			var r := check(pc.log, bx.b, bx.c, pc, true)
			if bool(r.ok):
				continue
			pieces.erase(pc)
			var ax: Vector3 = (bx.b as Basis).x
			var yaw := atan2(-ax.z, ax.x) if Vector2(ax.x, ax.z).length() > 0.1 else randf() * TAU
			_arv.drop_log(pc.log, bx.c, yaw)
			fell += 1
			changed = true
	if fell > 0:
		_rebuild()
	return fell


func remove_piece(pc: Dictionary) -> Dictionary:
	pieces.erase(pc)
	_rebuild()
	return pc.log


# ================== ANDAR EM CIMA E ESBARRAR ==================

## Topo da construção embaixo do jogador (para andar no assoalho), ou -1e9.
func support_y(x: float, z: float, feet: float) -> float:
	var best := -1e9
	var o := Vector3(x, feet + 0.45, z)
	for pc in pieces:
		var bx := piece_box(pc)
		if Vector2((bx.c as Vector3).x - x, (bx.c as Vector3).z - z).length() > (bx.h as Vector3).length() + 0.3:
			continue
		var r := _ray_box(bx, o, Vector3.DOWN, 3.0)
		if r.is_empty():
			continue
		var y := o.y - float(r.t)
		if (r.n as Vector3).y > 0.5 and y > best:
			best = y
	return best


## Não atravessa as paredes e vigas (o que está na altura do corpo).
func push_out(p: Vector3, feet: float) -> Vector3:
	for pc in pieces:
		var bx := piece_box(pc)
		var c: Vector3 = bx.c
		var h: Vector3 = bx.h
		if Vector2(c.x - p.x, c.z - p.z).length() > h.length() + 0.5:
			continue
		var b: Basis = bx.b
		# altura do corpo encostando: dos joelhos (passa por cima do que é baixo) à cabeça
		for yy in [feet + 0.34, feet + 0.8, feet + 1.25, feet + 1.65]:
			var q := Vector3(p.x, yy, p.z)
			var l := _local(bx, q)
			var R := 0.25
			var inside := true
			var best_i := -1
			var best_pen := 1e9
			for i in 3:
				var ax: Vector3 = b[i]
				var horiz := Vector2(ax.x, ax.z).length()
				var lim: float = h[i] + R * horiz
				if absf(l[i]) >= lim:
					inside = false
					break
				var pen: float = lim - absf(l[i])
				if horiz > 0.3 and pen < best_pen:
					best_pen = pen
					best_i = i
			if inside and best_i >= 0:
				var ax2: Vector3 = b[best_i]
				var hv := Vector3(ax2.x, 0, ax2.z)
				var push := hv.normalized() * signf(l[best_i] if absf(l[best_i]) > 1e-4 else 1.0) * best_pen / Vector2(ax2.x, ax2.z).length()
				p.x += push.x
				p.z += push.z
				break
	return p


# ================== DESENHO E SALVAR ==================

func _rebuild() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	for pc in pieces:
		var n: Node3D = _arv.free_log_node(pc.log)
		add_child(n)
		var bx := piece_box(pc)
		n.transform = Transform3D(bx.b, bx.c)
		_nodes.append(n)

	# furos: atravessam a peça e entram no apoio de baixo (que também fica furado)
	var segs := []
	for pc in pieces:
		for pn in pc.get("pinos", []):
			if int(pn[1]) >= 1:
				segs.append(pin_seg(pc, float(pn[0])))
	if not segs.is_empty():
		for i in pieces.size():
			var pc: Dictionary = pieces[i]
			var bx := piece_box(pc)
			var inv := Transform3D(bx.b, bx.c).affine_inverse()
			var holes := []
			for sg in segs:
				var a: Vector3 = inv * (sg[0] as Vector3)
				var b: Vector3 = inv * (sg[1] as Vector3)
				if not Furo._clip_box(a, b, (bx.h as Vector3) + Vector3.ONE * 0.01).is_empty():
					holes.append([a, b, 0.022])
			if not holes.is_empty():
				Furo.apply(_nodes[i], holes, bx.h)
	# pinos batidos: aparecem passando pelo furo
	for pc in pieces:
		for pn in pc.get("pinos", []):
			if int(pn[1]) < 2:
				continue
			var sg := pin_seg(pc, float(pn[0]))
			var up: Vector3 = ((sg[1] as Vector3) - (sg[0] as Vector3)).normalized()
			var pm := Furo.pin_node(sg[0], (sg[1] as Vector3) - up * 0.012)     # batido até o fim: rente à madeira
			add_child(pm)
			_nodes.append(pm)
	# o barro já passado nas peças
	for pc in pieces:
		for e in pc.get("barro", []):
			var mp := _mud_patch(pc, e)
			add_child(mp)
			_nodes.append(mp)


# ================== REBOCO DE BARRO ==================
# Em cada peça, a face virada para o jogador é dividida em pedaços (~35 cm) no
# comprido; cada pedaço recebe uma camada de barro (com fibra) por vez.

const REBOCO_PASSO := 0.35

func _reboco_n(h: Vector3) -> int:
	return maxi(1, int(round(h.x * 2.0 / REBOCO_PASSO)))


## Pedaços de face que ainda não têm barro, virados para "from": [{pc, u, k, s, pos, n}]
func reboco_spots(from: Vector3, reach := 3.2) -> Array:
	var out := []
	for pc in pieces:
		var bx := piece_box(pc)
		var c: Vector3 = bx.c
		if Vector2(c.x - from.x, c.z - from.z).length() > reach + (bx.h as Vector3).x:
			continue
		var b: Basis = bx.b
		var h: Vector3 = bx.h
		var to := (from + Vector3.UP * 1.0) - c
		# a face (lado ou cima) mais virada para o jogador; a de baixo não
		var best_k := -1
		var best_s := 1.0
		var bd := 0.15
		for k in [1, 2]:
			for sg in [-1.0, 1.0]:
				var nrm: Vector3 = (b[k] as Vector3) * sg
				if nrm.y < -0.6:
					continue
				var d := nrm.dot(to.normalized())
				if d > bd:
					bd = d
					best_k = k
					best_s = sg
		if best_k < 0:
			continue
		var nrm2: Vector3 = (b[best_k] as Vector3) * best_s
		var done: Array = pc.get("barro", [])
		var n := _reboco_n(h)
		for i in n:
			var u := -1.0 + (2.0 * i + 1.0) / n
			var has := false
			for e in done:
				if absf(float(e[0]) - u) < 0.01 and int(e[1]) == best_k and float(e[2]) == best_s:
					has = true
					break
			if has:
				continue
			var pos := c + b.x * (u * h.x) + nrm2 * h[best_k]
			if Vector2(pos.x - from.x, pos.z - from.z).length() > reach:
				continue
			out.append({"pc": pc, "u": u, "k": best_k, "s": best_s, "pos": pos, "n": nrm2})
	return out


func add_barro(pc: Dictionary, u: float, k: int, sg: float) -> void:
	if not pc.has("barro"):
		pc["barro"] = []
	pc.barro.append([u, k, sg, int(_jogo.sim.elapsed_days())])
	_rebuild()


## A madeira está toda coberta de barro? As duas faces largas (as de cima/de lado,
## não a de baixo, que fica apoiada) com todos os pedaços rebocados. Aí o cupim não
## come; se sobrou algum pedaço de madeira à vista, come.
func coberta(pc: Dictionary) -> bool:
	var done: Array = pc.get("barro", [])
	if done.is_empty():
		return false
	var bx := piece_box(pc)
	var b: Basis = bx.b
	var h: Vector3 = bx.h
	var n := _reboco_n(h)
	var t := 1 if h.y <= h.z else 2          # a espessura: as faces largas olham para esse lado
	for sg in [-1.0, 1.0]:
		var nrm: Vector3 = (b[t] as Vector3) * sg
		if nrm.y < -0.6:
			continue                          # a de baixo (apoiada) não conta
		var cnt := 0
		for e in done:
			if int(e[1]) == t and float(e[2]) == sg:
				cnt += 1
		if cnt < n:
			return false
	return true


var _dia_barro := -1


## Uma vez por dia: o barro vai secando (redesenha se tiver barro).
func dia(day: int) -> void:
	if day == _dia_barro:
		return
	_dia_barro = day
	for pc in pieces:
		if not (pc.get("barro", []) as Array).is_empty():
			_rebuild()
			return


const SECA_DIAS := 6             # o barro leva uns 6 dias para secar de todo

static var _mud_mats := {}


## O barro em cada estágio: molhado (escuro, brilhando, liso), secando (mais claro,
## fosco) e seco (claro, áspero, todo rachado). A cor de cada ponto (vértice) dá as
## manchas, os sulcos da mão e as fibras de buriti aparecendo.
static func _mud_material(stage: int) -> StandardMaterial3D:
	if _mud_mats.has(stage):
		return _mud_mats[stage]
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	var nt := NoiseTexture2D.new()
	var tn := FastNoiseLite.new()
	tn.frequency = 0.05
	tn.fractal_octaves = 4
	nt.noise = tn
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 3.0 + stage * 2.5
	m.normal_enabled = true
	m.normal_texture = nt
	m.uv1_scale = Vector3(1.6, 1.6, 1.6)
	# manchas e grãos (areia, pedrinha) do barro
	var at := NoiseTexture2D.new()
	var an := FastNoiseLite.new()
	an.frequency = 0.07
	an.fractal_octaves = 3
	an.seed = 17
	at.noise = an
	at.width = 256
	at.height = 256
	at.seamless = true
	var ag := Gradient.new()
	ag.offsets = PackedFloat32Array([0.0, 0.45, 0.55, 1.0])
	ag.colors = PackedColorArray([Color(0.78, 0.76, 0.74), Color(0.95, 0.94, 0.92), Color(1, 1, 1), Color(1.08, 1.06, 1.02)])
	at.color_ramp = ag
	m.albedo_texture = at
	match stage:
		0:
			m.albedo_color = Color(0.2, 0.15, 0.11)
			m.roughness = 0.38
			m.metallic_specular = 0.35
		1:
			m.albedo_color = Color(0.3, 0.24, 0.18)
			m.roughness = 0.8
			m.metallic_specular = 0.15
		2:
			m.albedo_color = Color(0.34, 0.28, 0.21)
			m.roughness = 0.95
			m.metallic_specular = 0.06
		_:
			# seco: claro e as rachaduras (placas de células com a borda escura e funda)
			var ct := NoiseTexture2D.new()
			var cn := FastNoiseLite.new()
			cn.noise_type = FastNoiseLite.TYPE_CELLULAR
			cn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
			cn.cellular_jitter = 1.0
			cn.frequency = 0.035
			ct.noise = cn
			ct.width = 256
			ct.height = 256
			ct.seamless = true
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.035, 0.07, 0.5, 1.0])
			g.colors = PackedColorArray([Color(0.06, 0.05, 0.04), Color(0.12, 0.1, 0.08), Color(0.3, 0.25, 0.19), Color(0.33, 0.28, 0.21), Color(0.36, 0.3, 0.23)])
			ct.color_ramp = g
			m.albedo_texture = ct
			var cnt := NoiseTexture2D.new()
			cnt.noise = cn
			cnt.width = 256
			cnt.height = 256
			cnt.seamless = true
			cnt.as_normal_map = true
			cnt.bump_strength = 5.0
			m.normal_texture = cnt
			m.roughness = 1.0
			m.metallic_specular = 0.04
	_mud_mats[stage] = m
	return m


## A placa de barro grudada na face: grossa e abaulada, com a beira irregular, os
## sulcos da mão que espalhou e as fibras aparecendo. As placas vizinhas se encostam
## e passam um pouco da quina (a madeira some debaixo do barro, como casa de taipa).
func _mud_patch(pc: Dictionary, e: Array) -> Node3D:
	var bx := piece_box(pc)
	var b: Basis = bx.b
	var h: Vector3 = bx.h
	var c: Vector3 = bx.c
	var k := int(e[1])
	var sg := float(e[2])
	var u := float(e[0])
	var n := _reboco_n(h)
	var other := 2 if k == 1 else 1
	var nrm: Vector3 = (b[k] as Vector3) * sg
	var along: Vector3 = b.x
	var side: Vector3 = b[other]
	var la := h.x * 2.0 / n * 0.62
	var ls: float = h[other] * 1.05
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seed := int(absf(u * 1000.0)) + k * 7 + int(sg) * 3 + int(absf(c.x * 13.0 + c.z * 7.0))
	var nz := FastNoiseLite.new()
	nz.seed = seed
	nz.frequency = 1.6
	var nz2 := FastNoiseLite.new()
	nz2.seed = seed + 11
	nz2.frequency = 7.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var age := SECA_DIAS
	if e.size() > 3:
		age = int(_jogo.sim.elapsed_days()) - int(e[3])
	var stage := 0 if age < 1 else (1 if age < 3 else (2 if age < SECA_DIAS else 3))
	var NA := 12
	var NS := 7
	var base := c + along * (u * h.x) + nrm * h[k]
	var sw := rng.randf_range(-0.8, 0.8)           # direção das passadas da mão
	var grid := []
	var cols := []
	for i in NA + 1:
		var row := []
		var crow := []
		for j in NS + 1:
			var a := lerpf(-1.0, 1.0, float(i) / NA)
			var bb := lerpf(-1.0, 1.0, float(j) / NS)
			var ra := absf(a)
			var rb := absf(bb)
			var n1 := nz.get_noise_2d(a * 2.0 + u * 5.0, bb * 2.0)
			var n2 := nz2.get_noise_2d(a * 3.0, bb * 3.0)
			# beira irregular: a placa vai afinando até a madeira
			var edge := 1.0 - smoothstep(0.62 + 0.25 * n1, 1.0, maxf(ra, rb * 0.9))
			var stroke := sin((a * 2.4 + bb * sw) * 6.0 + n1 * 3.0) * 0.0035
			var thick := 0.012 + 0.018 * (1.0 - a * a * 0.3) * (1.0 - bb * bb * 0.5) + n1 * 0.008 + n2 * 0.003 + stroke
			thick = maxf(0.0015, thick * edge + 0.002)
			var off := nrm * thick
			# passando da quina: dobra para o lado (por cima do canto da madeira)
			var sb := clampf(bb, -1.0, 1.0)
			var pos := base + along * (a * la) + side * (sb * ls)
			if rb > 0.92:
				pos -= nrm * (rb - 0.92) * 0.35 * h[k] * 2.0
			row.append(pos + off)
			var tone := n2 * 0.18 + stroke * 18.0
			var col := Color(1, 1, 1).darkened(clampf(-tone, 0.0, 0.3)).lightened(clampf(tone, 0.0, 0.15))
			if stage >= 2:
				col = col.lightened(0.08 * (1.0 - edge))       # a beira fina seca primeiro (mais clara)
			crow.append(col)
		grid.append(row)
		cols.append(crow)
	for i in NA:
		for j in NS:
			var q := [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
			var cq := [cols[i][j], cols[i + 1][j], cols[i + 1][j + 1], cols[i][j + 1]]
			var uvq := [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var A: Vector3 = q[tri[0]]
				var B: Vector3 = q[tri[1]]
				var C: Vector3 = q[tri[2]]
				var ord: Array = tri
				if (B - A).cross(C - A).dot(nrm) < 0.0:
					ord = [tri[0], tri[2], tri[1]]
				for idx in ord:
					var uvv: Vector2 = uvq[idx]
					st.set_color(cq[idx])
					st.set_uv(Vector2(uvv.x * la * 2.0 / NA, uvv.y * ls * 2.0 / NS) * 0.9 + Vector2(u * 0.7 + c.x * 0.13, k * 0.3 + c.z * 0.11))
					st.add_vertex(q[idx])
	# as fibras de buriti aparecendo no barro (fiapos claros, umas pontas soltas)
	var fcol := Color(1.7, 1.5, 1.05) if stage < 3 else Color(1.6, 1.42, 1.0)
	for f in 7:
		var a0 := rng.randf_range(-0.75, 0.75)
		var b0 := rng.randf_range(-0.7, 0.7)
		var ang := rng.randf() * TAU
		var L := rng.randf_range(0.25, 0.6)
		var pa := base + along * (a0 * la) + side * (b0 * ls)
		var dir := (along * cos(ang) + side * sin(ang)).normalized()
		var p1 := pa + dir * L * minf(la, ls)
		var lift: float = 0.012 + 0.018 * (1.0 - a0 * a0 * 0.3) * (1.0 - b0 * b0 * 0.5) + 0.004
		var wv := dir.cross(nrm).normalized() * 0.0012
		var o := nrm * lift
		for v in [pa - wv + o, p1 - wv + o, p1 + wv + o, pa - wv + o, p1 + wv + o, pa + wv + o]:
			st.set_color(fcol)
			st.set_uv(Vector2(0.5, 0.5))
			st.add_vertex(v)
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mud_material(stage)
	return mi


## O furo do pino: do topo da peça (no ponto u) atravessando ela e entrando uns 12 cm
## no apoio de baixo. [fundo, topo]
func pin_seg(pc: Dictionary, u: float) -> Array:
	var bx := piece_box(pc)
	var b: Basis = bx.b
	var h: Vector3 = bx.h
	var k := 1 if absf(b.y.y) >= absf(b.z.y) else 2
	var top := pin_pos(pc, u)
	var c: Vector3 = (bx.c as Vector3) + b.x * (u * h.x)
	var down := (c - top).normalized()
	if down.length() < 0.5:
		down = Vector3.DOWN
	var depth: float = h[k] * 2.0 + 0.12
	return [top + down * depth, top - down * 0.01]


static var _pmat: StandardMaterial3D


static func _pin_mat() -> StandardMaterial3D:
	if _pmat == null:
		_pmat = StandardMaterial3D.new()
		_pmat.albedo_color = Color(0.62, 0.47, 0.3)
		_pmat.roughness = 0.9
	return _pmat


## Onde vai o pino (em cima da peça, no ponto u do comprimento).
func pin_pos(pc: Dictionary, u: float) -> Vector3:
	var bx := piece_box(pc)
	var b: Basis = bx.b
	var h: Vector3 = bx.h
	var k := 1 if absf(b.y.y) >= absf(b.z.y) else 2
	var up: Vector3 = b[k] * signf((b[k] as Vector3).y if absf((b[k] as Vector3).y) > 0.01 else 1.0)
	if absf(b.x.y) > 0.7:
		# peça em pé: o pino entra de lado, perto de onde ela encosta
		up = b.y
	return (bx.c as Vector3) + b.x * (u * h.x) + up * h[k]


## Pinos que faltam bater perto: [{pc, k, pos}]
func pin_targets(pos: Vector3, reach := 2.6) -> Array:
	var out := []
	for pc in pieces:
		var pns: Array = pc.get("pinos", [])
		for k in pns.size():
			if int(pns[k][1]) >= 2:
				continue
			var w := pin_pos(pc, float(pns[k][0]))
			if Vector2(w.x - pos.x, w.z - pos.z).length() < reach and absf(w.y - pos.y - 0.9) < 2.2:
				out.append({"pc": pc, "k": k, "pos": w, "stage": int(pns[k][1])})
	return out


func pin_done(pc: Dictionary, k: int) -> void:
	set_stage(pc, k, 2)


func set_stage(pc: Dictionary, k: int, st: int) -> void:
	pc.pinos[k][1] = st
	_rebuild()


func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "pecas": pieces}))
		f.close()


func _load(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		pieces = d.get("pecas", [])
		for pc in pieces:
			if pc.has("amarras"):
				# versão antiga (amarrada com cipó): os lugares viram pinos já batidos
				var pns := []
				for u in pc.amarras:
					pns.append([float(u), 2])
				pc["pinos"] = pns
				pc.erase("amarras")
			for pn in pc.get("pinos", []):
				if pn[1] is bool:
					pn[1] = 2 if pn[1] else 0
