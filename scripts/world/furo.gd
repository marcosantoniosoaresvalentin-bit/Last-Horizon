extends RefCounted
## Furo de verdade na madeira: o material da peça (casca e miolo) é trocado por um
## igual que não desenha nada dentro dos cilindros dos furos — dá para ver do outro
## lado — e um tubo de madeira faz a parede de dentro do furo. Com o pino batido, o
## pino aparece passando pelo furo (as duas pontas à mostra).
##
## Furo: [a, b, raio] (segmento do eixo do furo) no espaço do nó da peça.

const MAX := 8

const BARK_CODE := """
shader_type spatial;
uniform sampler2D alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float nscale = 1.2;
uniform vec4 ha[8];
uniform vec4 hb[8];
uniform int nh = 0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
float seg_d(vec3 p, vec3 a, vec3 b) {
	vec3 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	return length(p - (a + ab * t));
}
void fragment() {
	for (int i = 0; i < 8; i++) {
		if (i >= nh) { break; }
		if (seg_d(lp, ha[i].xyz, hb[i].xyz) < ha[i].w) { discard; }
	}
	ALBEDO = texture(alb, UV).rgb * tint.rgb;
	NORMAL_MAP = texture(nrm, UV).rgb;
	NORMAL_MAP_DEPTH = nscale;
	ROUGHNESS = 0.95;
}
"""

const WOOD_CODE := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 ha[8];
uniform vec4 hb[8];
uniform int nh = 0;
varying vec3 lp;
void vertex() {
	lp = VERTEX;
	COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
}
float seg_d(vec3 p, vec3 a, vec3 b) {
	vec3 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	return length(p - (a + ab * t));
}
void fragment() {
	for (int i = 0; i < 8; i++) {
		if (i >= nh) { break; }
		if (seg_d(lp, ha[i].xyz, hb[i].xyz) < ha[i].w) { discard; }
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
"""

static var _bark_sh: Shader
static var _wood_sh: Shader
static var _tube_mat: StandardMaterial3D
static var _pin_mat: StandardMaterial3D


static func _shaders() -> void:
	if _bark_sh == null:
		_bark_sh = Shader.new()
		_bark_sh.code = BARK_CODE
		_wood_sh = Shader.new()
		_wood_sh.code = WOOD_CODE


## Fura a peça: troca o material das malhas dela e põe a parede de dentro de cada furo.
## holes: [[a, b, raio]] no espaço de node. box_h: meia medida da peça (x comprido,
## y grosso, z largo), para o tubo de dentro ficar só onde tem madeira.
static func apply(node: Node3D, holes: Array, box_h: Vector3) -> void:
	if holes.is_empty():
		return
	_shaders()
	var hs := holes.slice(0, MAX)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		# os furos no espaço desta malha
		var inv := _rel(m, node).affine_inverse()
		var ha := PackedVector4Array()
		var hb := PackedVector4Array()
		for h in hs:
			var a: Vector3 = inv * (h[0] as Vector3)
			var b: Vector3 = inv * (h[1] as Vector3)
			ha.append(Vector4(a.x, a.y, a.z, float(h[2])))
			hb.append(Vector4(b.x, b.y, b.z, 0.0))
		while ha.size() < MAX:
			ha.append(Vector4.ZERO)
			hb.append(Vector4.ZERO)
		for si in m.mesh.get_surface_count():
			var src := m.get_active_material(si)
			var sm := ShaderMaterial.new()
			if src is StandardMaterial3D and (src as StandardMaterial3D).albedo_texture != null:
				var st := src as StandardMaterial3D
				sm.shader = _bark_sh
				sm.set_shader_parameter("alb", st.albedo_texture)
				sm.set_shader_parameter("nrm", st.normal_texture)
				sm.set_shader_parameter("tint", st.albedo_color)
				sm.set_shader_parameter("nscale", st.normal_scale)
			else:
				sm.shader = _wood_sh
			sm.set_shader_parameter("ha", ha)
			sm.set_shader_parameter("hb", hb)
			sm.set_shader_parameter("nh", hs.size())
			m.set_surface_override_material(si, sm)
	# a parede de dentro de cada furo (só a parte dentro da peça)
	for h in hs:
		var seg := _clip_box(h[0], h[1], box_h)
		if seg.is_empty():
			continue
		node.add_child(_tube(seg[0], seg[1], float(h[2])))


## Pino passando pelo furo, de a até b (as pontas aparecem dos dois lados).
static func pin_node(a: Vector3, b: Vector3) -> MeshInstance3D:
	if _pin_mat == null:
		_pin_mat = StandardMaterial3D.new()
		_pin_mat.albedo_color = Color(0.66, 0.5, 0.32)
		_pin_mat.roughness = 0.9
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.017
	cm.bottom_radius = 0.017
	cm.height = a.distance_to(b)
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = _pin_mat
	mi.transform = _along(a, b)
	return mi


static func _tube(a: Vector3, b: Vector3, r: float) -> MeshInstance3D:
	if _tube_mat == null:
		_tube_mat = StandardMaterial3D.new()
		_tube_mat.albedo_color = Color(0.32, 0.22, 0.13)
		_tube_mat.roughness = 1.0
		_tube_mat.cull_mode = BaseMaterial3D.CULL_FRONT       # só o lado de dentro
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 14
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	mi.material_override = _tube_mat
	mi.transform = _along(a, b)
	return mi


static func _along(a: Vector3, b: Vector3) -> Transform3D:
	var up := (b - a).normalized()
	var sd := up.cross(Vector3.FORWARD)
	if sd.length() < 0.1:
		sd = up.cross(Vector3.RIGHT)
	sd = sd.normalized()
	return Transform3D(Basis(sd, up, sd.cross(up)), (a + b) * 0.5)


## Pedaço do segmento a-b dentro da caixa centrada (meias medidas h), ou [].
static func _clip_box(a: Vector3, b: Vector3, h: Vector3) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for i in 3:
		if absf(d[i]) < 1e-6:
			if absf(a[i]) > h[i]:
				return []
			continue
		var u0 := (-h[i] - a[i]) / d[i]
		var u1 := (h[i] - a[i]) / d[i]
		if u0 > u1:
			var tt := u0
			u0 = u1
			u1 = tt
		t0 = maxf(t0, u0)
		t1 = minf(t1, u1)
		if t0 > t1:
			return []
	return [a + d * t0, a + d * t1]


static func _rel(n: Node, top: Node) -> Transform3D:
	var t := Transform3D()
	var c := n
	while c != top and c != null:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t
