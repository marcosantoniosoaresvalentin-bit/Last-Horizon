extends Node3D
## Barro feito no chão: o balde de terra despejado vira um monte (a terra da escavação).
## Com a enxada na mão aparece o olho no monte: "Abrir" faz uma cova no meio (a terra
## do meio vai para a beira). Aí joga água (meio balde de cada vez): enche a cova e
## o que sobra escorre pelos lados do monte, molhando a terra em fios. Põe as fibras
## de buriti e mistura com a enxada (os losangos, bater e puxar): onde a enxada mexe,
## a terra vira barro (outra cor, liso e brilhando). Pronto, dá para encher o balde de
## barro; barro do balde despejado no chão vira outro monte de barro.

const RES := 0.2                 # a grade da escavação
const JUNTA := 0.8               # terra jogada até essa distância do meio cai no mesmo monte
const ABRIR_GOLPES := 3          # enxadadas para abrir a cova
const AGUA_POR_TERRA := 0.5      # meio balde de água para cada balde de terra
const MIX_HITS := 2              # puxadas da enxada em cada lugar
const MIX_SPOTS := 5

var montes: Array = []           # {x, z, terra, aberto, agua, fibra, mix[], pronto, baldes, cav}
var _jogo: Node
var _escav: Node
var _nodes := []
var _soil_mat: Material
var _gloss_mat: StandardMaterial3D
var _pool_mat: StandardMaterial3D
var _fib_mat: StandardMaterial3D
var _anim_t := 0.0


func build(jogo: Node, escav: Node, soil_mat: Material, save_path := "") -> void:
	_jogo = jogo
	_escav = escav
	_soil_mat = soil_mat
	_gloss_mat = StandardMaterial3D.new()
	_gloss_mat.vertex_color_use_as_albedo = true
	_gloss_mat.vertex_color_is_srgb = true
	_gloss_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_gloss_mat.roughness = 0.16
	_gloss_mat.metallic_specular = 0.55
	_gloss_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pool_mat = StandardMaterial3D.new()
	_pool_mat.vertex_color_use_as_albedo = true
	_pool_mat.vertex_color_is_srgb = true
	_pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_mat.roughness = 0.06
	_pool_mat.metallic_specular = 0.5
	_pool_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fib_mat = StandardMaterial3D.new()
	_fib_mat.vertex_color_use_as_albedo = true
	_fib_mat.vertex_color_is_srgb = true
	_fib_mat.roughness = 0.75
	_fib_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if save_path != "":
		_load(save_path)
	_rebuild()


# ================== ESTADO ==================

## O monte mais perto de pos (pelo meio), até r; -1 se nenhum.
func near(pos: Vector3, r := 1.4) -> int:
	var best := -1
	var bd := r
	for i in montes.size():
		var m: Dictionary = montes[i]
		var d := Vector2(float(m.x) - pos.x, float(m.z) - pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func center(i: int) -> Vector3:
	var m: Dictionary = montes[i]
	return Vector3(float(m.x), _escav.ground_at(float(m.x), float(m.z)), float(m.z))


## Despejou terra (ou barro) do balde em pos: junta no monte que já tem ali ou faz outro.
func add(pos: Vector3, tipo: String, vol: float) -> void:
	var cheio: float = _jogo.BALDE_KG / float(_jogo.DENS.get(tipo, 1500.0))
	var n := clampf(vol / cheio, 0.0, 1.2)
	if n < 0.05:
		return
	var i := near(pos, JUNTA)
	if i < 0:
		var mx := []
		for _k in MIX_SPOTS:
			mx.append(0)
		montes.append({"x": snappedf(pos.x, 0.001), "z": snappedf(pos.z, 0.001), "terra": 0.0, "aberto": 0, "agua": 0.0,
			"fibra": false, "mix": mx, "pronto": false, "baldes": 0.0, "cav": 0.0})
		i = montes.size() - 1
	var m: Dictionary = montes[i]
	var tot := float(m.terra) + float(m.baldes)
	# o meio do monte vai para onde caiu mais terra
	if tot > 0.0:
		m.x = snappedf(lerpf(float(m.x), pos.x, n / (tot + n)), 0.001)
		m.z = snappedf(lerpf(float(m.z), pos.z, n / (tot + n)), 0.001)
	else:
		m.x = snappedf(pos.x, 0.001)
		m.z = snappedf(pos.z, 0.001)
	if tipo == "barro":
		if bool(m.pronto) or float(m.terra) <= 0.0:
			m.pronto = true
			m.baldes = float(m.baldes) + n
		else:
			# barro em cima de terra que ainda não virou barro: conta como terra já molhada
			m.terra = float(m.terra) + n
			m.agua = float(m.agua) + n * AGUA_POR_TERRA
	else:
		if bool(m.pronto):
			# terra seca jogada em cima do barro pronto: tem que molhar e misturar de novo
			m.terra = float(m.baldes) + n
			m.agua = float(m.baldes) * AGUA_POR_TERRA
			m.baldes = 0.0
			m.pronto = false
			m.aberto = ABRIR_GOLPES
			for k in MIX_SPOTS:
				m.mix[k] = 0
		else:
			m.terra = float(m.terra) + n
	m.erase("_R")
	_rebuild()


func need_agua(m: Dictionary) -> float:
	return float(m.terra) * AGUA_POR_TERRA


func fibras_need(m: Dictionary) -> int:
	return maxi(2, ceili(float(m.terra) * 1.25))


## O que falta fazer: abrir, agua, fibra, mexer, pronto
func stage(i: int) -> String:
	var m: Dictionary = montes[i]
	if bool(m.pronto):
		return "pronto"
	if int(m.aberto) < ABRIR_GOLPES:
		return "abrir"
	if float(m.agua) < need_agua(m) - 0.02:
		return "agua"
	if not bool(m.fibra):
		return "fibra"
	return "mexer"


## Raio do monte (até onde a terra jogada subiu o chão).
func radius(i: int) -> float:
	var m: Dictionary = montes[i]
	if m.has("_R"):
		return float(m._R)
	var cx := roundi(float(m.x) / RES)
	var cz := roundi(float(m.z) / RES)
	var rr := 0.0
	for ix in range(cx - 7, cx + 8):
		for iz in range(cz - 7, cz + 8):
			if float(_escav.d.get(Vector2i(ix, iz), 0.0)) > 0.004:
				rr = maxf(rr, Vector2(ix * RES - float(m.x), iz * RES - float(m.z)).length())
	m["_R"] = clampf(rr + RES * 0.55, 0.34, 1.45)
	return float(m._R)


func _rim_r(i: int) -> float:
	return clampf(radius(i) * 0.42, 0.15, 0.3)


## Os lugares de mexer: o meio e quatro em volta, na terra molhada.
func mix_spots(i: int) -> Array:
	var c := center(i)
	var rs := _rim_r(i) * 0.95
	var out := [c]
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var p := c + Vector3(cos(a), 0, sin(a)) * rs
		p.y = _escav.ground_at(p.x, p.z)
		out.append(p)
	for k in out.size():
		out[k] = (out[k] as Vector3) + Vector3.UP * 0.03
	return out


## Uma enxadada abrindo a cova. Devolve true quando a cova ficou aberta.
func abrir_hit(i: int) -> bool:
	var m: Dictionary = montes[i]
	m.aberto = mini(ABRIR_GOLPES, int(m.aberto) + 1)
	m.cav = float(m.cav) + _escav.crater(center(i), 0.025)
	m.erase("_R")
	_rebuild()
	return int(m.aberto) >= ABRIR_GOLPES


## Água na cova (b = quanto de balde). O que sobra escorre pelos lados.
func add_agua(i: int, b: float) -> void:
	var m: Dictionary = montes[i]
	m.agua = float(m.agua) + b
	m["_t"] = 0.0           # começa a escorrer agora
	_rebuild()


func add_fibra(i: int) -> void:
	montes[i].fibra = true
	_rebuild()


func mix_hit(i: int, k: int) -> bool:
	var m: Dictionary = montes[i]
	m.mix[k] = mini(MIX_HITS, int(m.mix[k]) + 1)
	var all := true
	for v in m.mix:
		if int(v) < MIX_HITS:
			all = false
	if all and not bool(m.pronto):
		m.pronto = true
		m.baldes = float(m.terra)
		m.terra = 0.0
		m.agua = 0.0
		# o barro misturado assenta num monte redondo (a cova some)
		if float(m.cav) > 0.0:
			_escav.crater(center(i), -float(m.cav))
			m.cav = 0.0
		m.erase("_R")
	_rebuild()
	return all


func mix_progress(i: int) -> float:
	var m: Dictionary = montes[i]
	if bool(m.pronto):
		return 1.0
	var t := 0
	for v in m.mix:
		t += int(v)
	return float(t) / float(MIX_SPOTS * MIX_HITS)


## Enche o balde com o barro do monte: devolve quanto de balde (0 se não tem).
func take(i: int) -> float:
	var m: Dictionary = montes[i]
	if not bool(m.pronto) or float(m.baldes) < 0.05:
		return 0.0
	var b := minf(1.0, float(m.baldes))
	var left := float(m.baldes) - b
	_escav.scale_pile(center(i), radius(i), left / float(m.baldes) if left > 0.05 else 0.0)
	if left <= 0.05:
		montes.remove_at(i)
	else:
		m.baldes = left
		m.erase("_R")
	_rebuild()
	return b


## O monte foi cavado embora (com a pá)? Some.
func check() -> void:
	var gone := []
	for i in montes.size():
		var m: Dictionary = montes[i]
		var cx := roundi(float(m.x) / RES)
		var cz := roundi(float(m.z) / RES)
		var top := 0.0
		for ix in range(cx - 2, cx + 3):
			for iz in range(cz - 2, cz + 3):
				top = maxf(top, float(_escav.d.get(Vector2i(ix, iz), 0.0)))
		if top < 0.006:
			gone.append(i)
	if gone.is_empty():
		return
	gone.reverse()
	for i in gone:
		montes.remove_at(i)
	_rebuild()


# ================== DESENHO ==================

func _process(delta: float) -> void:
	var any := false
	for m in montes:
		if m.has("_t") and float(m._t) < 9.0:
			m._t = float(m._t) + delta
			any = true
	if any:
		_anim_t -= delta
		if _anim_t <= 0.0:
			_anim_t = 0.1
			_rebuild()


func _rebuild() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes = []
	for i in montes.size():
		var nd := _monte_node(i)
		if nd:
			add_child(nd)
			_nodes.append(nd)


static func _h01(a: float) -> float:
	return fposmod(sin(a * 12.9898) * 43758.5453, 1.0)


## Um monte: a terra por cima do chão de terra jogada (com a cova e a beira), a terra
## molhada e o barro (cor própria), o brilho da água escorrendo e do barro molhado,
## a poça na cova e as fibras.
func _monte_node(i: int) -> Node3D:
	var m: Dictionary = montes[i]
	var cx := float(m.x)
	var cz := float(m.z)
	var R := radius(i)
	var rr := _rim_r(i)
	var openf := float(m.aberto) / ABRIR_GOLPES
	var mixp := mix_progress(i)
	var pronto := bool(m.pronto)
	var need := maxf(need_agua(m), 0.01)
	var wetf := 1.0 if pronto else clampf(float(m.agua) / need, 0.0, 1.0)
	var t_pour := float(m.get("_t", 99.0))
	var seed := int(absf(cx * 37.0 + cz * 91.0)) % 9973
	var nz := FastNoiseLite.new()
	nz.seed = seed
	nz.frequency = 6.0
	var nz2 := FastNoiseLite.new()
	nz2.seed = seed + 5
	nz2.frequency = 22.0
	var rim_h := 0.05 * openf * (1.0 - 0.9 * mixp)
	var sp: Array = mix_spots(i) if not pronto else []
	# os fios de água escorrendo pela terra (direções fixas de cada monte)
	var streaks := []
	var nstr := 5 + seed % 3
	for s in nstr:
		streaks.append([TAU * (float(s) + _h01(seed + s * 3.1) * 0.7) / nstr, 0.03 + _h01(seed + s * 7.7) * 0.03, _h01(seed + s * 1.3) * 6.0])
	var flow := smoothstep(0.0, 4.0, t_pour)            # até onde a água chegou
	var running := 1.0 - smoothstep(3.5, 9.0, t_pour)   # ainda correndo (brilha)
	var reach := rr + (R - rr + 0.05) * flow
	# campos em cada ponto: h (altura a mais), wet, mud, sheen (água correndo)
	var field := func(x: float, z: float) -> Array:
		var dx := x - cx
		var dz := z - cz
		var r := sqrt(dx * dx + dz * dz)
		var ang := atan2(dz, dx)
		var u := r / R
		var n1 := nz.get_noise_2d(dx * 3.0, dz * 3.0)
		var n2 := nz2.get_noise_2d(dx * 3.0, dz * 3.0)
		# a beira da cova: a terra tirada do meio, encaroçada
		var h := 0.009
		h += rim_h * exp(-pow((r - rr) / (0.07 + rr * 0.15), 2.0)) * (0.75 + 0.5 * n1)
		h += rim_h * 0.35 * n2 * smoothstep(rr * 1.5, rr * 0.5, r)
		h -= 0.045 * smoothstep(0.8, 1.0, u)               # na borda, por baixo do chão
		var wet := 0.0
		var sheen := 0.0
		if float(m.agua) > 0.0 or pronto:
			wet = smoothstep(rr * 1.05, rr * 0.7, r) * wetf     # a cova molhada
			for s in streaks:
				var a0: float = s[0] + sin(r * 11.0 + float(s[2])) * 0.22
				var da := absf(wrapf(ang - a0, -PI, PI)) * r
				var w: float = float(s[1]) * (1.0 + r * 0.6)
				if da < w and r < reach:
					var k := (1.0 - da / w) * smoothstep(reach, reach - 0.08, r)
					wet = maxf(wet, k)
					sheen = maxf(sheen, k * running)
			# a terra vai chupando a água: o monte todo fica úmido aos poucos
			wet = maxf(wet, wetf * 0.45 * smoothstep(1.0, 0.4, u) * smoothstep(0.0, 6.0, t_pour if t_pour < 50.0 else 6.0))
		var mud := 0.0
		if pronto:
			mud = smoothstep(1.0, 0.85, u)
		else:
			for k in sp.size():
				var q: Vector3 = sp[k]
				var dd := Vector2(x - q.x, z - q.z).length()
				mud = maxf(mud, float(m.mix[k]) / MIX_HITS * smoothstep(0.24, 0.05, dd))
			mud = maxf(mud, mixp * 0.6 * smoothstep(rr * 1.6, rr * 0.8, r))
		# barro: liso, com as marcas da enxada (sulcos)
		h += mud * (0.006 + 0.004 * sin((dx * 0.7 + dz * 0.7) * 70.0 + n1 * 3.0) + 0.004 * n1)
		if pronto:
			h += 0.03 * (1.0 - u * u) * smoothstep(1.0, 0.7, u)       # barro assentado, redondo
		return [h, wet, mud, sheen]
	var g := 0.035
	var N := int(ceil(R / g))
	var soil := Color(0.33, 0.24, 0.16)
	var wet_c := Color(0.2, 0.135, 0.085)
	var mud_c := Color(0.27, 0.215, 0.165)            # barro: mais cinza, cor própria
	var pts := {}
	var cols := {}
	var gl := {}
	for a in range(-N, N + 1):
		for b in range(-N, N + 1):
			var x := cx + a * g
			var z := cz + b * g
			if Vector2(a * g, b * g).length() > R + g:
				continue
			var f: Array = field.call(x, z)
			var y: float = _escav.ground_at(x, z) - 0.015 + float(f[0])
			pts[Vector2i(a, b)] = Vector3(x, y, z)
			var tone := nz2.get_noise_2d(x * 9.0, z * 9.0)
			var c := soil.darkened(maxf(-tone, 0.0) * 0.2).lightened(maxf(tone, 0.0) * 0.1)
			c = c.lerp(wet_c, float(f[1]) * 0.85)
			c = c.lerp(mud_c.darkened(0.12 * float(f[1]) + tone * 0.08), float(f[2]))
			cols[Vector2i(a, b)] = c
			gl[Vector2i(a, b)] = clampf(maxf(float(f[3]) * 0.6, maxf(float(f[1]) * 0.16, float(f[2]) * 0.42)), 0.0, 0.7)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sg := SurfaceTool.new()
	sg.begin(Mesh.PRIMITIVE_TRIANGLES)
	var anyg := false
	for a in range(-N, N):
		for b in range(-N, N):
			var ks := [Vector2i(a, b), Vector2i(a + 1, b), Vector2i(a + 1, b + 1), Vector2i(a, b + 1)]
			var ok := true
			for k in ks:
				if not pts.has(k):
					ok = false
			if not ok:
				continue
			var gq := 0.0
			for k in ks:
				gq = maxf(gq, float(gl[k]))
			for idx in [0, 2, 1, 0, 3, 2]:
				var k: Vector2i = ks[idx]
				st.set_color(cols[k])
				st.add_vertex(pts[k])
			if gq > 0.02:
				anyg = true
				for idx in [0, 2, 1, 0, 3, 2]:
					var k: Vector2i = ks[idx]
					sg.set_color(Color(0.09, 0.065, 0.045, float(gl[k])))
					sg.set_normal(Vector3.UP)
					sg.add_vertex(pts[k] + Vector3.UP * 0.0025)
	var root := Node3D.new()
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _soil_mat
	root.add_child(mi)
	if anyg:
		var gi := MeshInstance3D.new()
		gi.mesh = sg.commit()
		gi.material_override = _gloss_mat
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(gi)
	# a poça na cova: enche com a água e vai sumindo (escorre e a terra chupa; mexendo vira barro)
	if not pronto and float(m.agua) > 0.0 and openf > 0.0:
		var fill := wetf * (1.0 - mixp) * lerpf(1.0, 0.7, smoothstep(0.5, 6.0, minf(t_pour, 6.0)))
		if fill > 0.03:
			var c0 := Vector3(cx, _escav.ground_at(cx, cz) - 0.015 + 0.009, cz)
			var lvl := c0.y + 0.008 + rim_h * 0.75 * fill
			var pr := rr * (0.55 + 0.4 * fill)
			var ps := SurfaceTool.new()
			ps.begin(Mesh.PRIMITIVE_TRIANGLES)
			var segs := 28
			var col := Color(0.2, 0.14, 0.085, 0.9)
			for s in segs:
				var a1 := TAU * s / segs
				var a2 := TAU * (s + 1) / segs
				var r1 := pr * (1.0 + 0.12 * nz.get_noise_2d(cos(a1) * 2.0, sin(a1) * 2.0))
				var r2 := pr * (1.0 + 0.12 * nz.get_noise_2d(cos(a2) * 2.0, sin(a2) * 2.0))
				for v in [Vector3(cx, lvl, cz), Vector3(cx + cos(a2) * r2, lvl, cz + sin(a2) * r2), Vector3(cx + cos(a1) * r1, lvl, cz + sin(a1) * r1)]:
					ps.set_color(col)
					ps.set_normal(Vector3.UP)
					ps.add_vertex(v)
			var pm := MeshInstance3D.new()
			pm.mesh = ps.commit()
			pm.material_override = _pool_mat
			pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(pm)
	# as fibras: fios finos e compridos, embaraçados; mexendo, afundam no barro
	if bool(m.fibra) or (pronto and float(m.baldes) > 0.0):
		var fs := SurfaceTool.new()
		fs.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed * 3 + 1
		var nf := int(60.0 * (1.0 - mixp * 0.85)) if not pronto else 9
		for k in nf:
			var a0 := rng.randf() * TAU
			var r0 := sqrt(rng.randf()) * (rr * 1.1 if not pronto else R * 0.7)
			var p0 := Vector2(cx + cos(a0) * r0, cz + sin(a0) * r0)
			var ang := rng.randf() * TAU
			var L := rng.randf_range(0.15, 0.42) * (1.0 if not pronto else 0.25)
			var seg := 9
			var prev := Vector3.INF
			var fc := Color(0.78, 0.7, 0.48).darkened(rng.randf() * 0.2 + mixp * 0.35)
			for s2 in seg + 1:
				var t := float(s2) / seg
				ang += rng.randf_range(-0.35, 0.35)
				var pxz := p0 + Vector2(cos(ang), sin(ang)) * L * t
				var ff: Array = field.call(pxz.x, pxz.y)
				var y: float = _escav.ground_at(pxz.x, pxz.y) - 0.015 + float(ff[0]) + 0.003 + sin(t * 9.0 + k) * 0.002
				if pronto:
					y += t * 0.012                       # pontinha saindo do barro
				var pt := Vector3(pxz.x, y, pxz.y)
				if prev != Vector3.INF:
					var dv := pt - prev
					var sd := Vector3(-dv.z, 0, dv.x).normalized() * 0.0014
					for v in [prev - sd, pt - sd, pt + sd, prev - sd, pt + sd, prev + sd]:
						fs.set_color(fc)
						fs.set_normal(Vector3.UP)
						fs.add_vertex(v)
				prev = pt
		var fi := MeshInstance3D.new()
		fi.mesh = fs.commit()
		fi.material_override = _fib_mat
		fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fi)
	return root


# ================== SALVAR ==================

func save(path: String) -> void:
	var out := []
	for m in montes:
		var e := {}
		for k in m:
			if not str(k).begins_with("_"):
				e[k] = m[k]
		out.append(e)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"versao": 1, "montes": out}))
		f.close()


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not j is Dictionary:
		return false
	var old := montes
	montes = []
	for e in j.get("montes", []):
		if not e is Dictionary:
			continue
		var mx := []
		for k in MIX_SPOTS:
			mx.append(int((e.get("mix", []) as Array)[k]) if k < (e.get("mix", []) as Array).size() else 0)
		var m := {"x": float(e.get("x", 0.0)), "z": float(e.get("z", 0.0)), "terra": float(e.get("terra", 0.0)),
			"aberto": int(e.get("aberto", 0)), "agua": float(e.get("agua", 0.0)), "fibra": bool(e.get("fibra", false)),
			"mix": mx, "pronto": bool(e.get("pronto", false)), "baldes": float(e.get("baldes", 0.0)), "cav": float(e.get("cav", 0.0))}
		# a água que estava escorrendo aqui continua (veio de outro jogador)
		for o in old:
			if absf(float(o.x) - float(m.x)) < 0.01 and absf(float(o.z) - float(m.z)) < 0.01:
				if o.has("_t"):
					m["_t"] = o._t
				if float(m.agua) > float(o.agua) + 0.01:
					m["_t"] = 0.0              # o outro jogador jogou água agora
		montes.append(m)
	return true
