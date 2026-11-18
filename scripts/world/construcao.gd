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
				# (amarrado nela com cipó)
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
	# estaca fincada encostada em qualquer ponto (amarrada nela): conta sempre, no
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
	# amarrações: uma em cada madeira em que encosta (no meio de onde encosta), até 4
	var juntas := []
	for k in joint_u:
		var us: Array = joint_u[k]
		var m := 0.0
		for v in us:
			m += float(v)
		juntas.append(snappedf(m / us.size(), 0.01))
	juntas.sort()
	if juntas.size() > 4:
		juntas = [juntas[0], juntas[1], juntas[juntas.size() - 2], juntas[juntas.size() - 1]]
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
	pieces.append({"log": fl, "p": [c.x, c.y, c.z], "q": [q.x, q.y, q.z, q.w], "amarras": juntas})
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
		var am: Array = pc.get("amarras", [])
		if not am.is_empty():
			var mi := MeshInstance3D.new()
			mi.mesh = _lash_mesh(bx.h, am)
			mi.material_override = _lash_mat()
			n.add_child(mi)


static var _lmat: StandardMaterial3D


static func _lash_mat() -> StandardMaterial3D:
	if _lmat == null:
		_lmat = StandardMaterial3D.new()
		_lmat.vertex_color_use_as_albedo = true
		_lmat.vertex_color_is_srgb = true
		_lmat.roughness = 0.9
	return _lmat


## As voltas de cipó em volta da peça em cada amarração (no eixo da peça: x é o
## comprido): umas voltas retas apertadas e duas cruzadas, por cima da madeira.
static func _lash_mesh(h: Vector3, juntas: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ry := h.y + 0.008
	var rz := h.z + 0.008
	var tube := 0.0065
	for ju in juntas:
		var x0 := float(ju) * h.x
		var turns := []
		for t in 4:
			turns.append([x0 + (t - 1.5) * 0.017, 0.0])
		turns.append([x0, 0.045])           # as duas cruzadas (em X)
		turns.append([x0, -0.045])
		var ti := 0
		for tr in turns:
			var xc := float(tr[0])
			var lean := float(tr[1])
			var col := Color(0.2, 0.15, 0.07).darkened(0.1 * (ti % 2))
			var segs := 14
			var pts := []
			for k in segs + 1:
				var a := TAU * k / segs
				# a volta inclinada vai de um lado ao outro no comprido (o X)
				pts.append(Vector3(xc + lean * sin(a) * 1.4, cos(a) * ry, sin(a) * rz))
			for k in segs:
				var A: Vector3 = pts[k]
				var B: Vector3 = pts[k + 1]
				var out := Vector3(0, A.y, A.z).normalized()
				var side := Vector3(1, 0, 0) * tube
				var up := out * tube
				for v in [A - side, B - side, B + side, A - side, B + side, A + side, A + up, B + up, B - side, A + up, B - side, A - side]:
					st.set_color(col)
					st.add_vertex(v)
			ti += 1
	st.generate_normals()
	return st.commit()


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
