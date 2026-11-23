extends RefCounted
## A decomposição de um bicho morto (e dos pedaços dele: carne, buchada, patas, cabeça).
##
## Pelo tempo desde a morte (horas do jogo), em estágios que se emendam:
##   0 fresco (o primeiro dia), 1 inchado (os gases: a barriga estufa, a pele esverdeia,
##   as moscas chegam), 2 ativo (a pele estoura, as bicheiras comendo a carne aberta, o
##   líquido escuro no chão, mosca demais), 3 avançado (quase só couro seco, osso
##   aparecendo), 4 seco (só os ossos, brancos, por meses).
## O que os urubus comem soma no "consumo" (0 inteiro .. 1 sem carne): adianta tudo.
##
## O desenho: por cima do material do bicho, uma segunda passada (transparente) que
## escurece/esverdeia a pele e pinta onde a carne já foi comida (carne podre, as
## bicheiras mexendo, o osso no fundo). Sem carne: o corpo some e fica o esqueleto
## (feito dos ossos do próprio esqueleto da vaca, na posição em que ela morreu).

const VacaModelo := preload("res://scripts/world/vaca_modelo.gd")

const H_INCHA := 24.0             # horas: começa a inchar
const H_ATIVO := 72.0             # estoura: bicheiras
const H_AVANC := 240.0            # 10 dias: quase só couro e osso
const H_SECO := 480.0             # 20 dias: só ossos

const SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
uniform float est = 0.0;
uniform float cons = 0.0;
uniform float esc = 1.0;
uniform float infla = 0.0;
uniform float semente = 0.0;
varying vec3 p;
void vertex() {
	p = VERTEX;
	VERTEX += NORMAL * infla;
}
float hh(vec3 q) { return fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float ruido(vec3 q) {
	vec3 i = floor(q); vec3 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hh(i), hh(i + vec3(1,0,0)), f.x), mix(hh(i + vec3(0,1,0)), hh(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hh(i + vec3(0,0,1)), hh(i + vec3(1,0,1)), f.x), mix(hh(i + vec3(0,1,1)), hh(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 q) {
	return ruido(q) * 0.55 + ruido(q * 2.1 + 3.7) * 0.3 + ruido(q * 4.3 + 7.1) * 0.15;
}
void fragment() {
	vec3 q = p * esc + vec3(semente);
	float n = fbm(q * 2.2);
	float n2 = ruido(q * 7.0);
	// a pele: escurece, esverdeia quando incha, seca e fica couro escuro no fim
	// (manchas: a pele não muda igual em tudo; a barriga e onde encosta no chão primeiro)
	float mancha = smoothstep(0.3, 0.7, fbm(q * 1.3 + 4.0));
	vec3 c = mix(vec3(0.2, 0.21, 0.12), vec3(0.08, 0.065, 0.045), smoothstep(1.8, 3.2, est));
	c = mix(c, vec3(0.24, 0.28, 0.12), smoothstep(0.7, 1.4, est) * (1.0 - smoothstep(2.0, 2.8, est)) * 0.7);
	float a = (smoothstep(0.3, 1.5, est) * (0.35 + 0.35 * mancha) + smoothstep(1.8, 3.2, est) * 0.35) * (0.75 + 0.25 * n2);
	// molhada (o líquido escorrendo) no estouro
	float molhado = smoothstep(1.7, 2.1, est) * (1.0 - smoothstep(2.8, 3.3, est)) * mancha;
	float rough = mix(mix(0.6, 0.25, molhado), 0.95, smoothstep(2.5, 3.5, est));
	// as bicheiras: do estouro até secar
	float mb = smoothstep(1.6, 2.1, est) * (1.0 - smoothstep(3.0, 3.5, est));
	// onde a carne já foi (comida pelas bicheiras e pelos urubus)
	float borda = cons * 1.12 - n;
	if (borda > 0.0) {
		// a carne aberta: vermelha escura e molhada no começo, depois marrom e seca
		vec3 carne = mix(vec3(0.3, 0.06, 0.04), vec3(0.14, 0.045, 0.03), smoothstep(1.2, 3.0, est));
		carne = mix(carne, vec3(0.11, 0.08, 0.055), smoothstep(2.8, 3.6, est));
		carne *= 0.8 + 0.4 * n2;
		// bem no fundo (onde já não tem quase nada): o osso aparece, em manchas
		float fundo = smoothstep(0.32, 0.5, borda);
		float costela = smoothstep(0.86, 0.97, abs(sin(q.y * 3.14159 / 0.09 + n * 2.0)));
		float osso = fundo * costela * smoothstep(0.4, 0.55, ruido(q * 3.0 + 9.0)) * 0.85;
		c = mix(carne, vec3(0.78, 0.72, 0.6) * (0.85 + 0.15 * n2), osso);
		a = 1.0;
		rough = mix(0.3, 0.9, smoothstep(2.6, 3.4, est));
	} else {
		// fora do buraco as bicheiras só na beirada
		mb *= 1.0 - smoothstep(0.0, 0.1, -borda);
	}
	// as bicheiras andam em bolos (montes brancos mexendo), não espalhadas
	mb *= smoothstep(0.45, 0.6, ruido(q * 3.5 + vec3(TIME * 0.02)));
	if (mb > 0.0) {
		vec3 qm = q * 55.0 + vec3(0.0, TIME * 0.25, TIME * 0.15);
		float blob = ruido(qm) * 0.7 + ruido(q * 140.0 + vec3(TIME * 0.6)) * 0.3;
		float bi = smoothstep(0.6, 0.7, blob) * mb;
		c = mix(c, vec3(0.93, 0.89, 0.76) * (0.85 + 0.15 * n2), bi);
		a = max(a, bi);
		rough = mix(rough, 0.35, bi);
	}
	if (a < 0.01) { discard; }
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
"""

static var _sh: Shader = null
static var _osso_mat: StandardMaterial3D = null
static var _escuro_mat: StandardMaterial3D = null
static var _mosca_mesh: QuadMesh = null
static var _mosca_mat: StandardMaterial3D = null
static var _mancha_mat: StandardMaterial3D = null


## O estágio (0..4, contínuo) pelas horas desde a morte; k acelera (bicho pequeno, sol).
static func estagio(h: float, cons: float, k := 1.0) -> float:
	var t := h * k
	var e := 0.0
	if t < H_INCHA:
		e = t / H_INCHA * 0.6
	elif t < H_ATIVO:
		e = 0.6 + (t - H_INCHA) / (H_ATIVO - H_INCHA) * 1.4
	elif t < H_AVANC:
		e = 2.0 + (t - H_ATIVO) / (H_AVANC - H_ATIVO)
	elif t < H_SECO:
		e = 3.0 + (t - H_AVANC) / (H_SECO - H_AVANC)
	else:
		e = 4.0
	# comido pelos urubus: a carne acaba antes (vira osso mais cedo)
	if cons >= 0.999:
		e = maxf(e, 3.9)
	return e


## Quanto da carne as bicheiras (e o tempo) já levaram, sem contar os urubus.
static func consumo_tempo(h: float, k := 1.0) -> float:
	var t := h * k
	if t < H_ATIVO:
		return 0.0
	if t < H_AVANC:
		return (t - H_ATIVO) / (H_AVANC - H_ATIVO) * 0.6
	return minf(1.0, 0.6 + (t - H_AVANC) / (H_SECO - H_AVANC) * 0.4)


## A passada de podre por cima de todas as malhas do nó (uma vez); devolve os materiais.
static func cobre(node: Node3D, pular_chifre := true) -> Array:
	if node.has_meta("podre_mats"):
		return node.get_meta("podre_mats")
	if _sh == null:
		_sh = Shader.new()
		_sh.code = SHADER
	var out := []
	var semente := float(absi(hash(node.get_instance_id())) % 97)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.has_meta("ossada") or m.name == "tampa":
			continue
		if pular_chifre and m.material_override != null and m.material_override == VacaModelo._mat_chifre():
			continue
		var pm := ShaderMaterial.new()
		pm.shader = _sh
		var esc := m.global_transform.basis.get_scale().x
		pm.set_shader_parameter("esc", esc)
		pm.set_shader_parameter("infla", 0.004 / maxf(esc, 1e-4))
		pm.set_shader_parameter("semente", semente)
		var pos := false
		if m.material_override != null:
			var d: Material = m.material_override.duplicate()
			if d.next_pass == null:
				d.next_pass = pm
				m.material_override = d
				pos = true
		else:
			for k in m.mesh.get_surface_count():
				var base: Material = m.get_surface_override_material(k)
				if base == null:
					base = m.mesh.surface_get_material(k)
				if base == null:
					continue
				var d2: Material = base.duplicate()
				if d2.next_pass != null:
					continue                     # (já tem outra passada: o couro sendo tirado)
				d2.next_pass = pm
				m.set_surface_override_material(k, d2)
				pos = true
		if pos:
			out.append(pm)
	node.set_meta("podre_mats", out)
	return out


static func atualiza(node: Node3D, est: float, cons: float) -> void:
	for pm in cobre(node):
		(pm as ShaderMaterial).set_shader_parameter("est", est)
		(pm as ShaderMaterial).set_shader_parameter("cons", cons)


static func osso_mat() -> StandardMaterial3D:
	if _osso_mat == null:
		_osso_mat = StandardMaterial3D.new()
		_osso_mat.albedo_color = Color(0.66, 0.61, 0.5)
		_osso_mat.roughness = 0.95
		_osso_mat.metallic_specular = 0.1
		_escuro_mat = StandardMaterial3D.new()
		_escuro_mat.albedo_color = Color(0.1, 0.08, 0.06)
		_escuro_mat.roughness = 1.0
	return _osso_mat


# ---------- o esqueleto ----------

## Um tubo (cilindro afinando) de a até b.
static func _tubo(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, lados := 7) -> void:
	var d := b - a
	if d.length() < 1e-7:
		return
	var z := d.normalized()
	var x := z.cross(Vector3(0.31, 0.77, 0.55)).normalized()
	var y := z.cross(x)
	for i in lados:
		var a0 := TAU * i / lados
		var a1 := TAU * (i + 1) / lados
		var n0 := x * cos(a0) + y * sin(a0)
		var n1 := x * cos(a1) + y * sin(a1)
		var q := [a + n0 * ra, b + n0 * rb, b + n1 * rb, a + n1 * ra]
		var nn := [n0, n0, n1, n1]
		for t in [0, 1, 2, 0, 2, 3]:
			st.set_normal(nn[t])
			st.add_vertex(q[t])
	# as pontas (a cabeça do osso, mais grossa: um tampinha)
	for e in [[a, -z, ra * 1.25], [b, z, rb * 1.25]]:
		var c: Vector3 = e[0]
		var nz: Vector3 = e[1]
		var r: float = e[2]
		for i in lados:
			var a0 := TAU * i / lados
			var a1 := TAU * (i + 1) / lados
			st.set_normal(nz)
			st.add_vertex(c + nz * r * 0.6)
			st.set_normal((x * cos(a0) + y * sin(a0)).normalized())
			st.add_vertex(c + (x * cos(a0) + y * sin(a0)) * r)
			st.set_normal((x * cos(a1) + y * sin(a1)).normalized())
			st.add_vertex(c + (x * cos(a1) + y * sin(a1)) * r)


## Uma caixa: centro, eixos (com o meio-tamanho já multiplicado).
static func _caixa(st: SurfaceTool, c: Vector3, ex: Vector3, ey: Vector3, ez: Vector3) -> void:
	var faces := [[ex, ey, ez], [-ex, ez, ey], [ey, ez, ex], [-ey, ex, ez], [ez, ex, ey], [-ez, ey, ex]]
	for f in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var q := [c + nrm + u + v, c + nrm - u + v, c + nrm - u - v, c + nrm + u - v]
		for t in [0, 1, 2, 0, 2, 3]:
			st.set_normal(nrm.normalized())
			st.add_vertex(q[t])


## O esqueleto da vaca (no espaço do esqueleto, na pose de agora). Feito na posição de
## descanso do modelo e levado para a pose osso a osso. sem = partes que já não estão
## (cortes: "cabeca", "pe_td"...).
static func esqueleto_vaca(sk: Skeleton3D, sem: Array) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sd := SurfaceTool.new()            # o escuro (os buracos dos olhos e do nariz)
	sd.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xf := {}
	for i in sk.get_bone_count():
		xf[sk.get_bone_name(i)] = sk.get_bone_global_pose(i) * sk.get_bone_global_rest(i).affine_inverse()
	var R := func(osso: String, q: Vector3) -> Vector3:
		return (xf.get(osso, Transform3D.IDENTITY) as Transform3D) * q
	var rest := func(osso: String) -> Vector3:
		return sk.get_bone_global_rest(sk.find_bone(osso)).origin
	var osso_y := func(y: float) -> String:
		if y < -0.024:
			return "Neck"
		if y < -0.009:
			return "Shoulders"
		if y < 0.01:
			return "Torso"
		if y < 0.022:
			return "Hips"
		return "Back"
	# a espinha: pescoço, peito, lombo e sacro (pontos na posição de descanso)
	var linha := [Vector3(0, -0.0372, 0.0455), Vector3(0, -0.028, 0.0365), Vector3(0, -0.0185, 0.0365),
		Vector3(0, -0.005, 0.0405), Vector3(0, 0.0175, 0.0415), Vector3(0, 0.0225, 0.0405), Vector3(0, 0.0275, 0.0405)]
	var passo := 0.0022
	for k in linha.size() - 1:
		var a: Vector3 = linha[k]
		var b: Vector3 = linha[k + 1]
		var n := maxi(1, int(a.distance_to(b) / passo))
		for i in n:
			var p: Vector3 = a.lerp(b, (float(i) + 0.5) / n)
			var ob: String = osso_y.call(p.y) if p.y > -0.034 else "Head"
			var dirv := (b - a).normalized()
			var r := 0.0011 if p.y < -0.019 else (0.0012 if p.y < 0.012 else 0.0013)
			# o corpo da vértebra (um carretel)
			_tubo(st, R.call(ob, p - dirv * passo * 0.38), R.call(ob, p + dirv * passo * 0.38), r, r)
			# o espinho para cima: alto na cernelha, baixo no lombo
			var alto := 0.0
			if p.y > -0.02 and p.y < 0.026:
				alto = lerpf(0.0045, 0.0016, clampf((p.y + 0.014) / 0.03, 0.0, 1.0))
			elif p.y <= -0.02:
				alto = 0.0012
			if alto > 0.0:
				var topo := p + Vector3(0, 0.0012, alto)
				_caixa(st, R.call(ob, (p + topo) * 0.5), (R.call(ob, Vector3(0.00025, 0, 0)) - R.call(ob, Vector3.ZERO)),
					(R.call(ob, Vector3(0, passo * 0.28, 0)) - R.call(ob, Vector3.ZERO)), (R.call(ob, topo) - R.call(ob, p)) * 0.5)
			# no lombo: as asas (processos para os lados)
			if p.y > 0.008 and p.y < 0.024:
				for sg in [-1.0, 1.0]:
					_tubo(st, R.call(ob, p), R.call(ob, p + Vector3(sg * 0.0036, 0, -0.0003)), 0.0005, 0.00035, 5)
	# o rabo
	var rab := ["Back", "Tail1", "Tail2", "Tail3", "Tail4"]
	var pts_r := [Vector3(0, 0.0275, 0.0405), rest.call("Tail1") + Vector3(0, 0, -0.002), rest.call("Tail2"), rest.call("Tail3"), rest.call("Tail4")]
	pts_r.append((pts_r[4] as Vector3) + ((pts_r[4] as Vector3) - (pts_r[3] as Vector3)) * 1.3)
	for k in 5:
		var a2: Vector3 = pts_r[k]
		var b2: Vector3 = pts_r[k + 1]
		var n2 := maxi(1, int(a2.distance_to(b2) / 0.0018))
		var ob2: String = rab[k]
		for i in n2:
			var r2 := lerpf(0.0009, 0.0003, (float(k) + float(i) / n2) / 5.0)
			var q0 := a2.lerp(b2, (float(i) + 0.1) / n2)
			var q1 := a2.lerp(b2, (float(i) + 0.8) / n2)
			_tubo(st, R.call(ob2, q0), R.call(ob2, q1), r2, r2 * 0.9, 5)
	# as costelas: 13 de cada lado, curvas, as 8 da frente vão até o esterno
	for i in 13:
		var y0 := lerpf(-0.0165, 0.011, float(i) / 12.0)
		var ob3: String = osso_y.call(y0)
		var W := lerpf(0.0078, 0.0095, sin(float(i) / 12.0 * PI * 0.9))
		var zt := lerpf(0.0372, 0.0405, float(i) / 12.0)
		var verd := i < 8
		var zb := lerpf(0.0118, 0.0135, float(i) / 7.0) if verd else lerpf(0.016, 0.024, float(i - 8) / 4.0)
		var tmax := 1.0 if verd else lerpf(0.85, 0.6, float(i - 8) / 4.0)
		for sg in [-1.0, 1.0]:
			var ant := Vector3.ZERO
			for j in 9:
				var t := float(j) / 8.0 * tmax
				var th := t * PI
				var q: Vector3 = Vector3(sg * (0.0012 + W * pow(sin(th), 0.75)) * (1.0 - 0.75 * t * t * (1.0 if verd else 0.0) * 0.0),
					y0 + 0.0035 * t, zt + (zb - zt) * (1.0 - cos(th)) * 0.5)
				if verd and j == 8:
					q.x = sg * 0.0013
				var w := R.call(ob3, q) as Vector3
				if j > 0:
					_tubo(st, ant, w, 0.0005, 0.0005, 5)
				ant = w
	# o esterno
	_tubo(st, R.call("Shoulders", Vector3(0, -0.019, 0.0122)), R.call("Torso", Vector3(0, 0.0005, 0.0128)), 0.0008, 0.0006)
	# a bacia: as asas do ílio, a junta do quadril e o ísquio
	for sg in [-1.0, 1.0]:
		var asa := Vector3(sg * 0.0085, 0.0155, 0.0395)
		var junta := Vector3(sg * 0.0074, 0.022, 0.0275)
		var isq := Vector3(sg * 0.004, 0.0295, 0.0345)
		_tubo(st, R.call("Hips", Vector3(0, 0.017, 0.041)), R.call("Hips", asa), 0.0008, 0.001)
		_tubo(st, R.call("Hips", asa), R.call("Hips", junta), 0.0011, 0.0009)
		_tubo(st, R.call("Back", junta), R.call("Back", isq), 0.0009, 0.0011)
		_tubo(st, R.call("Back", isq), R.call("Back", Vector3(0, 0.0275, 0.039)), 0.0006, 0.0006)
	# as pernas: a escápula, o braço e a canela; o fêmur e a canela de trás
	for e in [["_R", -1.0, "pe_fd", "pe_td"], ["_L", 1.0, "pe_fe", "pe_te"]]:
		var s: String = e[0]
		var sg2: float = e[1]
		var ombro: Vector3 = rest.call("FrontUpLeg" + s)
		var topo_e := Vector3(sg2 * 0.0062, -0.0145, 0.039)
		var w_e := (R.call("FrontLeg" + s, topo_e) as Vector3) - (R.call("FrontLeg" + s, ombro) as Vector3)
		var lat := (R.call("FrontLeg" + s, Vector3(0.0018, 0, 0)) as Vector3) - (R.call("FrontLeg" + s, Vector3.ZERO) as Vector3)
		var pla := (R.call("FrontLeg" + s, Vector3(0, 0.0016, 0)) as Vector3) - (R.call("FrontLeg" + s, Vector3.ZERO) as Vector3)
		_caixa(st, (R.call("FrontLeg" + s, ombro) as Vector3) + w_e * 0.5, lat * 0.15, pla, w_e * 0.5)
		_tubo(st, R.call("FrontUpLeg" + s, ombro), R.call("FrontUpLeg" + s, rest.call("FrontLowLeg" + s)), 0.0009, 0.0008)
		if not (str(e[2]) in sem):
			_tubo(st, R.call("FrontLowLeg" + s, rest.call("FrontLowLeg" + s)), R.call("FrontLowLeg" + s, rest.call("FrontFoot" + s) + Vector3(0, 0, 0.0012)), 0.0006, 0.0005)
		_tubo(st, R.call("BackUpLeg" + s, rest.call("BackUpLeg" + s)), R.call("BackUpLeg" + s, rest.call("BackLowLeg" + s)), 0.001, 0.0009)
		if not (str(e[3]) in sem):
			_tubo(st, R.call("BackLowLeg" + s, rest.call("BackLowLeg" + s)), R.call("BackLowLeg" + s, rest.call("BackFoot" + s) + Vector3(0, 0, 0.0012)), 0.0007, 0.0005)
	# a caveira: o crânio afinando até o focinho, a mandíbula, os buracos dos olhos e do nariz
	if not ("cabeca" in sem):
		var B := Vector3(0, -0.038, 0.0465)
		var F := Vector3(0, -0.0525, 0.0338)
		var ax := (F - B)
		var up := Vector3(0, ax.z, -ax.y).normalized() * -1.0
		if up.z < 0.0:
			up = -up
		var nseg := 6
		for i in nseg:
			var t0 := float(i) / nseg
			var t1 := float(i + 1) / nseg
			var c0 := B.lerp(F, (t0 + t1) * 0.5)
			var lar := lerpf(0.0037, 0.0017, (t0 + t1) * 0.5)
			var alt := lerpf(0.0032, 0.0013, (t0 + t1) * 0.5)
			var hx: Vector3 = (R.call("Head", c0 + Vector3(lar, 0, 0)) as Vector3) - (R.call("Head", c0) as Vector3)
			var hy: Vector3 = (R.call("Head", c0 + up * alt) as Vector3) - (R.call("Head", c0) as Vector3)
			var hz: Vector3 = (R.call("Head", c0 + ax / nseg * 0.55) as Vector3) - (R.call("Head", c0) as Vector3)
			_caixa(st, R.call("Head", c0), hx, hy, hz)
		for sg in [-1.0, 1.0]:
			_tubo(st, R.call("Head", Vector3(sg * 0.0028, -0.0395, 0.0418)), R.call("Head", Vector3(sg * 0.0012, -0.052, 0.0318)), 0.0005, 0.0004, 5)
			_caixa(sd, R.call("Head", Vector3(sg * 0.0034, -0.0425, 0.0448)),
				(R.call("Head", Vector3(0.0006, 0, 0)) as Vector3) - (R.call("Head", Vector3.ZERO) as Vector3),
				(R.call("Head", Vector3(0, 0.0011, 0)) as Vector3) - (R.call("Head", Vector3.ZERO) as Vector3),
				(R.call("Head", Vector3(0, 0, 0.0011)) as Vector3) - (R.call("Head", Vector3.ZERO) as Vector3))
			_caixa(sd, R.call("Head", Vector3(sg * 0.0007, -0.0532, 0.0345)),
				(R.call("Head", Vector3(0.0004, 0, 0)) as Vector3) - (R.call("Head", Vector3.ZERO) as Vector3),
				(R.call("Head", Vector3(0, 0.0005, 0)) as Vector3) - (R.call("Head", Vector3.ZERO) as Vector3),
				(R.call("Head", Vector3(0, 0, 0.0006)) as Vector3) - (R.call("Head", Vector3.ZERO) as Vector3))
	var mi := MeshInstance3D.new()
	mi.name = "ossada"
	mi.set_meta("ossada", true)
	var am: ArrayMesh = st.commit()
	sd.commit(am)
	mi.mesh = am
	mi.set_surface_override_material(0, osso_mat())
	if am.get_surface_count() > 1:
		mi.set_surface_override_material(1, _escuro_mat)
	return mi


## Os ossos de um bicho sem esqueleto de vaca (tamanduá, macaco, arara, cobra): a espinha
## ao comprido do corpo, as costelas e a caveira, do tamanho dele (no mundo).
static func ossada_generica(aabb: AABB, frente: Vector3, chao_y: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := aabb.get_center()
	frente.y = 0.0
	frente = frente.normalized() if frente.length() > 0.01 else Vector3.FORWARD
	var lado := frente.cross(Vector3.UP).normalized()
	var L := maxf(aabb.size.x, aabb.size.z) * 0.45
	var W := minf(aabb.size.x, aabb.size.z) * 0.25
	var y := chao_y + maxf(W * 0.35, 0.02)
	var r := clampf(L * 0.03, 0.004, 0.03)
	var a := Vector3(c.x, y, c.z) - frente * L
	var b := Vector3(c.x, y, c.z) + frente * L * 0.8
	var n := 14
	for i in n:
		_tubo(st, a.lerp(b, (i + 0.1) / n), a.lerp(b, (i + 0.85) / n), r, r, 5)
	for i in 7:
		var p := a.lerp(b, 0.45 + i * 0.05)
		for sg in [-1.0, 1.0]:
			var ant := p
			for j in 1 + 4:
				var t := float(j) / 4.0
				var q: Vector3 = p + lado * sg * W * sin(t * PI * 0.8) + Vector3.DOWN * (y - chao_y) * t
				_tubo(st, ant, q, r * 0.5, r * 0.5, 4)
				ant = q
	_caixa(st, b + frente * L * 0.12, lado * r * 2.2, Vector3.UP * r * 1.8, frente * L * 0.12)
	var mi := MeshInstance3D.new()
	mi.name = "ossada"
	mi.set_meta("ossada", true)
	mi.mesh = st.commit()
	mi.material_override = osso_mat()
	return mi


# ---------- as moscas e a mancha no chão ----------

static func moscas(r: float) -> CPUParticles3D:
	if _mosca_mesh == null:
		_mosca_mesh = QuadMesh.new()
		_mosca_mesh.size = Vector2(0.012, 0.009)
		_mosca_mat = StandardMaterial3D.new()
		_mosca_mat.albedo_color = Color(0.04, 0.04, 0.05)
		_mosca_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mosca_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_mosca_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mosca_mesh.material = _mosca_mat
	var p := CPUParticles3D.new()
	p.name = "moscas"
	p.mesh = _mosca_mesh
	p.amount = 24
	p.lifetime = 1.4
	p.local_coords = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = r
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.1
	p.angular_velocity_min = 0.0
	p.damping_min = 0.2
	p.damping_max = 0.8
	p.tangential_accel_min = -3.0
	p.tangential_accel_max = 3.0
	p.radial_accel_min = -2.0
	p.radial_accel_max = -0.5
	p.emitting = false
	return p


## A mancha escura do líquido no chão (embaixo da carcaça que estourou).
static func mancha(r: float) -> MeshInstance3D:
	if _mancha_mat == null:
		_mancha_mat = StandardMaterial3D.new()
		_mancha_mat.albedo_color = Color(0.08, 0.06, 0.035, 0.85)
		_mancha_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mancha_mat.roughness = 0.35
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 20
	var rng := RandomNumberGenerator.new()
	rng.seed = int(r * 1000.0)
	var rs := []
	for i in n:
		rs.append(r * rng.randf_range(0.7, 1.15))
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(cos(a1), 0, sin(a1)) * float(rs[(i + 1) % n]))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(cos(a0), 0, sin(a0)) * float(rs[i]))
	var mi := MeshInstance3D.new()
	mi.name = "mancha"
	mi.mesh = st.commit()
	mi.material_override = _mancha_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
