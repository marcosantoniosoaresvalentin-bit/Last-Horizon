extends Node3D
## Mundo do jogo em 3D, em terceira pessoa.
## Mapa grande coberto de grama, com serra, lagoas e chuva automática.
## A grama só é montada perto do jogador, para o jogo rodar leve no celular.

const MundoSim := preload("res://scripts/mundo_sim.gd")

const CELL := 5.0            # metros por célula da simulação (mapa de 640 x 480 m)
const HS := 1.2              # metros por unidade de altura da simulação
const SUB := 2               # subdivisões do terreno por célula
const WALK_SPEED := 2.2
const RUN_SPEED := 5.5
const JOY_RADIUS := 70.0
const GRASS_CHUNK := 12.0    # tamanho de cada bloco de grama, em metros
const GRASS_RADIUS := 3      # blocos de grama em volta do jogador
const GRASS_PER_CHUNK := 200
const CAM_DIST := 4.2
const CHARACTER_FILE := "res://personagem/soldado.glbin"

const TERRAIN_SHADER := """
shader_type spatial;
uniform float wet = 0.0;
uniform sampler2D soil_a : filter_linear, repeat_disable;   // R argila, G areia, B umidade, A grama
uniform sampler2D soil_b : filter_linear, repeat_disable;   // R caulinita, G ilita, B esmectita
uniform vec2 world_size = vec2(640.0, 480.0);
varying vec3 wpos;
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p){ return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float noise(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y); }
float fbm(vec2 p){ float s = 0.0; float a = 0.5; for(int i = 0; i < 4; i++){ s += noise(p) * a; p *= 2.03; a *= 0.5; } return s; }
// rachaduras do barro seco (placas, como lama secando)
float cracks(vec2 p){
	vec2 g = floor(p); vec2 f = fract(p);
	float d1 = 8.0; float d2 = 8.0;
	for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec2 o = vec2(float(x), float(y));
		vec2 r = o + hash2(g + o) * 0.85 - f;
		float d = dot(r, r);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return 1.0 - smoothstep(0.0, 0.08, sqrt(d2) - sqrt(d1));
}
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	vec2 uv = wpos.xz / world_size;
	vec4 a = texture(soil_a, uv);
	vec4 b = texture(soil_b, uv);
	float rock = COLOR.a;
	float clay = a.r; float sand = a.g; float moist = a.b; float grass = a.a;
	vec3 kao = vec3(0.70, 0.45, 0.30);   // caulinita: latossolo vermelho-amarelo
	vec3 ili = vec3(0.52, 0.47, 0.38);   // ilita: marrom acinzentado
	vec3 sme = vec3(0.34, 0.31, 0.26);   // esmectita: cinza escuro
	float tsum = max(b.r + b.g + b.b, 0.01);
	vec3 clayc = (kao * b.r + ili * b.g + sme * b.b) / tsum;
	vec3 loam = vec3(0.34, 0.25, 0.17);
	vec3 sandc = vec3(0.74, 0.64, 0.47);
	vec3 soil = mix(loam, clayc, smoothstep(0.15, 0.6, clay));
	soil = mix(soil, sandc, sand * 0.8 * (1.0 - clay));
	float soaked = smoothstep(0.55, 0.95, moist);
	soil *= mix(1.0, 0.55, soaked);
	// barro seco racha; a esmectita racha em placas grandes e fundas
	float dry_clay = smoothstep(0.35, 0.7, clay) * (1.0 - soaked) * (1.0 - smoothstep(0.2, 0.6, grass));
	float cr = cracks(wpos.xz * mix(2.2, 0.9, b.b / tsum));
	soil = mix(soil, soil * 0.3, cr * dry_clay * (0.35 + 0.65 * b.b / tsum));
	// grama: verde com água no solo, cor de palha na seca
	vec3 green = vec3(0.26, 0.36, 0.13);
	vec3 straw = vec3(0.60, 0.54, 0.30);
	vec3 gc = mix(straw, green, smoothstep(0.15, 0.6, moist));
	float g = smoothstep(0.1, 0.6, grass) * (0.75 + 0.25 * noise(wpos.xz * 1.3));
	vec3 c = mix(soil, gc, g);
	c = mix(c, vec3(0.45, 0.43, 0.39), rock);
	c = c * c * 1.25;
	float big = fbm(wpos.xz * 0.05);
	float fine = noise(wpos.xz * 3.0) * 0.6 + noise(wpos.xz * 9.0) * 0.4;
	c *= 0.82 + big * 0.28 + fine * 0.12;
	float wetness = max(wet, soaked * (1.0 - g));
	c *= mix(1.0, 0.8, wet);
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.4, wetness);
	SPECULAR = mix(0.2, 0.45, wetness);
}
"""

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float wind = 0.12;
uniform float wet = 0.0;
uniform vec3 player_pos = vec3(0.0);
uniform float fade_start = 26.0;
uniform float fade_end = 34.0;
void vertex(){
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// a grama encolhe perto da borda da área desenhada, sem "pular" na tela
	float shrink = 1.0 - smoothstep(fade_start, fade_end, distance(root.xz, player_pos.xz));
	VERTEX.y *= shrink;
	float s = COLOR.a * COLOR.a;
	float t = TIME * 1.7 + root.x * 0.31 + root.z * 0.23;
	float gust = 0.6 + 0.4 * sin(TIME * 0.37 + root.x * 0.02);
	VERTEX.x += sin(t) * wind * s * gust;
	VERTEX.z += cos(t * 0.83) * wind * 0.6 * s * gust;
	// a grama se abre quando o personagem passa por cima
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 away = wp.xz - player_pos.xz;
	float push = (1.0 - smoothstep(0.0, 0.9, length(away))) * s;
	vec2 dw = normalize(away + vec2(0.001)) * push * 0.5;
	VERTEX += transpose(mat3(MODEL_MATRIX)) * vec3(dw.x, 0.0, dw.y);
}
void fragment(){
	vec3 c = COLOR.rgb;
	c = mix(c * c * 1.4, c, 0.5);
	c *= mix(1.0, 0.8, wet);
	ALBEDO = c;
	ROUGHNESS = mix(0.85, 0.5, wet);
	SPECULAR = 0.3;
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_always;
uniform float rain = 0.0;
uniform vec3 deep = vec3(0.012, 0.03, 0.025);
uniform vec3 shallow = vec3(0.09, 0.08, 0.04);
varying float depth;
varying vec3 wpos;
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y); }
float waves(vec2 p, float t){
	float h = noise(p * 0.9 + vec2(t * 0.35, t * 0.2)) * 0.5;
	h += noise(p * 2.3 - vec2(t * 0.25, -t * 0.4)) * 0.3;
	h += noise(p * 7.0 + vec2(t * 0.8, 0.0)) * 0.12 * (1.0 + rain * 3.0);
	// pingos de chuva
	vec2 cell = floor(p * 3.0); vec2 f = fract(p * 3.0) - 0.5;
	float ph = fract(t * 1.3 + hash(cell));
	float ring = sin((length(f) - ph * 0.5) * 40.0) * (1.0 - ph) * smoothstep(0.5, 0.0, length(f));
	h += ring * 0.08 * rain;
	return h;
}
void vertex(){
	depth = COLOR.a;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment(){
	float t = TIME;
	float e = 0.08;
	float h0 = waves(wpos.xz, t);
	vec3 nw = normalize(vec3(h0 - waves(wpos.xz + vec2(e, 0.0), t), e * 1.6, h0 - waves(wpos.xz + vec2(0.0, e), t)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float d = clamp(depth / 1.6, 0.0, 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(shallow, deep, sqrt(d)) + vec3(0.05, 0.07, 0.08) * fres;
	ALPHA = clamp(mix(0.45, 0.93, sqrt(d)) + fres * 0.15, 0.0, 1.0) * smoothstep(0.0, 0.12, depth);
	ROUGHNESS = 0.12;
	SPECULAR = 0.45;
}
"""

var sim: Node
var _ter := PackedFloat32Array()
var _moist := PackedFloat32Array()
var _gw := PackedFloat32Array()
var _max_h := 1.0

var _terrain_mat: ShaderMaterial
var _grass_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _water_mi: MeshInstance3D
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _cam: Camera3D
var _rain: CPUParticles3D

var _player: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _anim_now := ""

var _grass_meshes: Array[Mesh] = []
var _grass_chunks := {}          # Vector2i -> MultiMeshInstance3D
var _grass_center := Vector2i(-999, -999)
var _grass_queue: Array[Vector2i] = []

var _hud: CanvasLayer
var _clock: Label
var _soil_label: Label
var _soil_a: ImageTexture
var _soil_b: ImageTexture
var _soil_bytes := PackedByteArray()
var _soil_timer := 0.0
var _refresh_timer := 0.0
var _loading: Label
var _loading_bg: ColorRect
var _joy_ui: Control

var _ready_world := false
var _face := 0.0
var _rain_amount := 0.0
var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _look_id := -1
var _look_last := Vector2.ZERO
var _yaw := 0.0
var _pitch := 0.32
var _water_level := PackedFloat32Array()
var _corner_h := PackedFloat32Array()
var _water_timer := 0.0
var _water_task := -1
var _w_level := PackedFloat32Array()
var _w_arr := []


func _exit_tree() -> void:
	if _water_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_water_task)


func _ready() -> void:
	_build_hud()
	_build_environment()
	sim = MundoSim.new()
	add_child(sim)
	sim.world_ready.connect(_on_world_ready)


# ================== INTERFACE ==================

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_loading_bg = ColorRect.new()
	_loading_bg.color = Color(0.043, 0.059, 0.102)
	_loading_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(_loading_bg)
	_loading = Label.new()
	_loading.text = "Gerando o mundo…"
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading.add_theme_font_size_override("font_size", 30)
	_loading.add_theme_color_override("font_color", Color(0.91, 0.86, 0.77))
	_hud.add_child(_loading)

	_clock = Label.new()
	_clock.position = Vector2(24, 18)
	_clock.add_theme_font_size_override("font_size", 24)
	_clock.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_clock.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_clock.add_theme_constant_override("outline_size", 6)
	_clock.visible = false
	_hud.add_child(_clock)

	_soil_label = Label.new()
	_soil_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_soil_label.offset_top = -46
	_soil_label.offset_bottom = -14
	_soil_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_soil_label.add_theme_font_size_override("font_size", 18)
	_soil_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_soil_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_soil_label.add_theme_constant_override("outline_size", 5)
	_soil_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_soil_label)

	var menu := Button.new()
	menu.text = "Menu"
	menu.add_theme_font_size_override("font_size", 20)
	menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu.offset_left = -124
	menu.offset_top = 16
	menu.offset_right = -20
	menu.offset_bottom = 60
	menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	_hud.add_child(menu)

	_joy_ui = Control.new()
	_joy_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_joy_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_ui.draw.connect(_draw_joy)
	_hud.add_child(_joy_ui)


func _set_loading(text: String) -> void:
	_loading.text = text
	await get_tree().process_frame


# ================== AMBIENTE ==================

func _build_environment() -> void:
	_env = Environment.new()
	_sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.62, 0.68, 0.66)
	_env.ambient_light_energy = 1.0
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.05
	_env.fog_enabled = true
	_env.fog_density = 0.0018
	_env.fog_sky_affect = 0.5
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 18.0
	_sun.shadow_opacity = 0.75
	add_child(_sun)
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.55, 0.65, 0.95)
	_moon.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-30), 0)
	add_child(_moon)

	_cam = Camera3D.new()
	_cam.fov = 62
	_cam.near = 0.1
	_cam.far = 700
	add_child(_cam)

	_rain = CPUParticles3D.new()
	_rain.amount = 900
	_rain.lifetime = 0.8
	_rain.emitting = false
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(14, 0.5, 14)
	_rain.direction = Vector3(0.1, -1, 0)
	_rain.spread = 2
	_rain.initial_velocity_min = 22
	_rain.initial_velocity_max = 26
	var drop := BoxMesh.new()
	drop.size = Vector3(0.012, 0.45, 0.012)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.8, 0.86, 0.92, 0.4)
	drop.material = dm
	_rain.mesh = drop
	add_child(_rain)

	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = _shader(TERRAIN_SHADER)
	_grass_mat = ShaderMaterial.new()
	_grass_mat.shader = _shader(GRASS_SHADER)
	var fade_end := (GRASS_RADIUS + 0.2) * GRASS_CHUNK
	_grass_mat.set_shader_parameter("fade_end", fade_end)
	_grass_mat.set_shader_parameter("fade_start", fade_end - 9.0)
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = _shader(WATER_SHADER)


func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s


# ================== MUNDO ==================

func _on_world_ready() -> void:
	_ter = sim.ter0
	_moist = sim.moist0
	_gw = sim.gw0
	_max_h = sim.max_h
	await _set_loading("Moldando o terreno…")
	_apply_soil()
	_build_terrain()
	await _set_loading("Enchendo as lagoas…")
	_water_mi = MeshInstance3D.new()
	_water_mi.material_override = _water_mat
	_water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water_mi)
	var w: PackedFloat32Array = sim.take_water()
	if not w.is_empty():
		_update_water(w)
		while not WorkerThreadPool.is_task_completed(_water_task):
			await get_tree().process_frame
		_finish_water()
	await _set_loading("Chamando o personagem…")
	_build_player()
	_player.position = _ground_pos(Vector2((sim.spawn.x + 0.5) * CELL, (sim.spawn.y + 0.5) * CELL))
	_yaw = 0.0
	await _set_loading("Plantando a grama…")
	for k in 3:
		_grass_meshes.append(_make_grass_mesh(k))
	_update_grass(true)
	_loading.visible = false
	_loading_bg.visible = false
	_clock.visible = true
	_ready_world = true


## Altura do terreno (metros) num ponto do mundo.
func height_at(x: float, z: float) -> float:
	var u := clampf(x / CELL - 0.5, 0.0, MundoSim.W - 1.001)
	var v := clampf(z / CELL - 0.5, 0.0, MundoSim.H - 1.001)
	var i := int(u); var j := int(v)
	var fu := u - i; var fv := v - j
	fu = fu * fu * (3.0 - 2.0 * fu); fv = fv * fv * (3.0 - 2.0 * fv)
	var W := MundoSim.W
	var a := _ter[j * W + i]; var b := _ter[j * W + i + 1]
	var c := _ter[(j + 1) * W + i]; var d := _ter[(j + 1) * W + i + 1]
	return lerpf(lerpf(a, b, fu), lerpf(c, d, fu), fv) * HS


func _field_at(arr: PackedFloat32Array, x: float, z: float) -> float:
	var u := clampf(x / CELL - 0.5, 0.0, MundoSim.W - 1.001)
	var v := clampf(z / CELL - 0.5, 0.0, MundoSim.H - 1.001)
	var i := int(u); var j := int(v)
	var fu := u - i; var fv := v - j
	var W := MundoSim.W
	return lerpf(lerpf(arr[j * W + i], arr[j * W + i + 1], fu), lerpf(arr[(j + 1) * W + i], arr[(j + 1) * W + i + 1], fu), fv)


func _ground_pos(p: Vector2) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.y), p.y)


func _rockiness(h: float) -> float:
	return smoothstep(0.72, 0.86, h / (_max_h * HS))


func _terrain_color(x: float, z: float, h: float, slope: float) -> Color:
	var green := clampf(_field_at(_moist, x, z) * 2.2 + _field_at(_gw, x, z) / MundoSim.GW_CAP * 0.6, 0.0, 1.0)
	var grass := Color(0.24, 0.32, 0.12)
	var lush := Color(0.18, 0.28, 0.09)
	var mud := Color(0.25, 0.20, 0.12)
	var rock := Color(0.45, 0.43, 0.39)
	var c := grass.lerp(lush, smoothstep(0.3, 0.8, green))
	if green > 0.85: c = c.lerp(mud, (green - 0.85) * 3.0)
	var r := maxf(_rockiness(h), smoothstep(0.55, 0.85, slope))
	c = c.lerp(rock, r)
	c.a = r
	return c


func _build_terrain() -> void:
	var W := MundoSim.W; var H := MundoSim.H
	var nx := W * SUB + 1; var nz := H * SUB + 1
	var step := CELL / SUB
	var verts := PackedVector3Array(); verts.resize(nx * nz)
	var norms := PackedVector3Array(); norms.resize(nx * nz)
	var cols := PackedColorArray(); cols.resize(nx * nz)
	var hs := PackedFloat32Array(); hs.resize(nx * nz)
	for gz in nz:
		for gx in nx:
			hs[gz * nx + gx] = height_at(gx * step, gz * step)
	for gz in nz:
		for gx in nx:
			var k := gz * nx + gx
			var hl := hs[gz * nx + maxi(gx - 1, 0)]; var hr := hs[gz * nx + mini(gx + 1, nx - 1)]
			var hd := hs[maxi(gz - 1, 0) * nx + gx]; var hu := hs[mini(gz + 1, nz - 1) * nx + gx]
			var n := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			verts[k] = Vector3(gx * step, hs[k], gz * step)
			norms[k] = n
			cols[k] = _terrain_color(gx * step, gz * step, hs[k], 1.0 - n.y)
	var idx := PackedInt32Array(); idx.resize((nx - 1) * (nz - 1) * 6)
	var p := 0
	for gz in nz - 1:
		for gx in nx - 1:
			var a := gz * nx + gx
			idx[p] = a; idx[p + 1] = a + 1; idx[p + 2] = a + nx
			idx[p + 3] = a + 1; idx[p + 4] = a + nx + 1; idx[p + 5] = a + nx
			p += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _terrain_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ================== GRAMA ==================

## Touceira de grama: lâminas finas e curvas.
func _make_grass_mesh(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + variant
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades: int = [10, 8, 12][variant]
	for k in blades:
		var a := rng.randf() * TAU
		var r := rng.randf() * 0.35
		var base := Vector3(cos(a) * r, -0.04, sin(a) * r)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.1, 0.45)
		var h := rng.randf_range(0.25, 0.55) * (1.5 if variant == 1 else 1.0)
		var w := rng.randf_range(0.025, 0.04)
		var side := Vector3(-sin(a), 0, cos(a)) * w
		var root := Color(0.16, 0.24, 0.08, 0.0)
		var tip := Color(0.38, 0.50, 0.17).lerp(Color(0.52, 0.52, 0.25), rng.randf() * 0.5)
		tip.a = 1.0
		var mid := root.lerp(tip, 0.55); mid.a = 0.45
		var p1 := base + Vector3.UP * h * 0.55 + lean * h * 0.35
		var p2 := base + Vector3.UP * h + lean * h
		for tri in [[base - side, root], [base + side, root], [p1 + side * 0.7, mid],
				[base - side, root], [p1 + side * 0.7, mid], [p1 - side * 0.7, mid],
				[p1 - side * 0.7, mid], [p1 + side * 0.7, mid], [p2, tip]]:
			st.set_color(tri[1])
			st.add_vertex(tri[0])
	st.index()
	st.generate_normals()
	return st.commit()


func _update_grass(all_now := false) -> void:
	var c := Vector2i(floori(_player.position.x / GRASS_CHUNK), floori(_player.position.z / GRASS_CHUNK))
	if c != _grass_center:
		_grass_center = c
		var wanted := {}
		for dz in range(-GRASS_RADIUS, GRASS_RADIUS + 1):
			for dx in range(-GRASS_RADIUS, GRASS_RADIUS + 1):
				if dx * dx + dz * dz > (GRASS_RADIUS + 0.5) * (GRASS_RADIUS + 0.5):
					continue
				wanted[c + Vector2i(dx, dz)] = true
		for key in _grass_chunks.keys():
			if not wanted.has(key):
				_grass_chunks[key].queue_free()
				_grass_chunks.erase(key)
		_grass_queue.clear()
		for key in wanted:
			if not _grass_chunks.has(key):
				_grass_queue.append(key)
		_grass_queue.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	var budget := 999 if all_now else 2
	while budget > 0 and not _grass_queue.is_empty():
		_build_grass_chunk(_grass_queue.pop_front())
		budget -= 1


func _build_grass_chunk(key: Vector2i) -> void:
	var x0 := key.x * GRASS_CHUNK
	var z0 := key.y * GRASS_CHUNK
	if x0 < -GRASS_CHUNK or z0 < -GRASS_CHUNK or x0 > MundoSim.W * CELL or z0 > MundoSim.H * CELL:
		_grass_chunks[key] = Node3D.new()
		add_child(_grass_chunks[key])
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var per_mesh := [[], [], []]
	var W := MundoSim.W
	for k in GRASS_PER_CHUNK:
		var px := x0 + rng.randf() * GRASS_CHUNK
		var pz := z0 + rng.randf() * GRASS_CHUNK
		var variant := rng.randi() % 3
		var s := rng.randf_range(0.8, 1.35)
		var rot := rng.randf() * TAU
		var tint := Color(rng.randf_range(0.85, 1.15), rng.randf_range(0.9, 1.12), rng.randf_range(0.85, 1.05))
		if px < 0 or pz < 0 or px >= W * CELL or pz >= MundoSim.H * CELL:
			continue
		var h := height_at(px, pz)
		if _rockiness(h) > rng.randf() * 0.8 + 0.1:
			continue
		var cell := int(pz / CELL) * W + int(px / CELL)
		if _soil_bytes.size() == W * MundoSim.H * 4:
			var cov := _soil_bytes[cell * 4 + 3] / 255.0
			if rng.randf() > cov * 1.15:
				continue
			var moist := _soil_bytes[cell * 4 + 2] / 255.0
			tint = tint * Color(1, 1, 1).lerp(Color(1.45, 1.2, 0.75), 1.0 - smoothstep(0.15, 0.6, moist))
		if _water_level.size() == W * MundoSim.H and _water_level[cell] > h + 0.05:
			continue
		var b := Basis(Vector3.UP, rot).scaled(Vector3(s, s, s))
		per_mesh[variant].append([Transform3D(b, Vector3(px, h, pz)), tint])
	var holder := Node3D.new()
	for v in 3:
		var items: Array = per_mesh[v]
		if items.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _grass_meshes[v]
		mm.instance_count = items.size()
		for k in items.size():
			mm.set_instance_transform(k, items[k][0])
			mm.set_instance_color(k, items[k][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _grass_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)
	_grass_chunks[key] = holder
	add_child(holder)


# ================== PERSONAGEM ==================

func _build_player() -> void:
	_player = Node3D.new()
	add_child(_player)
	var bytes := FileAccess.get_file_as_bytes(CHARACTER_FILE)
	if not bytes.is_empty():
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_buffer(bytes, "", state) == OK:
			_model = doc.generate_scene(state)
	if _model == null:
		# reserva, caso o arquivo do personagem não esteja no celular
		_model = MeshInstance3D.new()
		var cap := CapsuleMesh.new(); cap.radius = 0.3; cap.height = 1.75
		_model.mesh = cap
		_model.position.y = 0.875
	_player.add_child(_model)
	var aps := _model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		_anim = aps[0]
		for n in ["Idle", "Walk", "Run"]:
			if _anim.has_animation(n):
				_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		_play("Idle")
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _play(name: String, speed := 1.0) -> void:
	if _anim == null or not _anim.has_animation(name):
		return
	if _anim_now != name:
		_anim.play(name, 0.25)
		_anim_now = name
	_anim.speed_scale = speed


func _process(delta: float) -> void:
	_update_sky(delta)
	if not _ready_world:
		return
	_finish_water()
	_water_timer -= delta
	if _water_timer <= 0.0:
		var w: PackedFloat32Array = sim.take_water()
		if not w.is_empty():
			_update_water(w)
			_water_timer = 3.0
	_move_player(delta)
	_update_grass()
	_grass_mat.set_shader_parameter("player_pos", _player.global_position)
	var h: float = sim.hour()
	_clock.text = "Dia %d · %02d:%02d · %s%s" % [sim.day(), int(h), int(fmod(h, 1.0) * 60.0), sim.season_name(), " · Chovendo" if sim.raining else ""]
	_soil_timer -= delta
	if _soil_timer <= 0.0:
		_soil_timer = 2.0
		_apply_soil()
		_soil_label.text = sim.soil_info(Vector2i(int(_player.position.x / CELL), int(_player.position.z / CELL)))
	# a grama vai sendo refeita aos poucos, acompanhando as estações
	_refresh_timer -= delta
	if _refresh_timer <= 0.0 and _grass_queue.is_empty() and not _grass_chunks.is_empty():
		_refresh_timer = 1.5
		var keys := _grass_chunks.keys()
		var key: Vector2i = keys[randi() % keys.size()]
		_grass_chunks[key].queue_free()
		_grass_chunks.erase(key)
		_build_grass_chunk(key)


## Atualiza as texturas do solo (argila, areia, umidade, grama e tipos de argila).
func _apply_soil() -> void:
	var soil: Array = sim.take_soil()
	if soil.is_empty():
		return
	_soil_bytes = soil[0]
	var ia := Image.create_from_data(MundoSim.W, MundoSim.H, false, Image.FORMAT_RGBA8, soil[0])
	var ib := Image.create_from_data(MundoSim.W, MundoSim.H, false, Image.FORMAT_RGBA8, soil[1])
	if _soil_a == null:
		_soil_a = ImageTexture.create_from_image(ia)
		_soil_b = ImageTexture.create_from_image(ib)
		_terrain_mat.set_shader_parameter("soil_a", _soil_a)
		_terrain_mat.set_shader_parameter("soil_b", _soil_b)
		_terrain_mat.set_shader_parameter("world_size", Vector2(MundoSim.W * CELL, MundoSim.H * CELL))
	else:
		_soil_a.update(ia)
		_soil_b.update(ib)


func _update_sky(delta: float) -> void:
	if sim == null:
		return
	var h: float = sim.hour() if sim.is_ready else 7.0
	var target := 1.0 if (sim.is_ready and sim.raining) else 0.0
	_rain_amount = move_toward(_rain_amount, target, delta * 0.3)
	var elev := sin((h - 6.0) / 12.0 * PI)
	var daylight := clampf(elev * 3.0 + 0.3, 0.0, 1.0)
	_sun.rotation = Vector3(-asin(clampf(elev, 0.12, 1.0)), deg_to_rad(35.0 + (h - 12.0) * 6.0), 0)
	var warm := clampf(1.0 - elev * 2.5, 0.0, 1.0)
	_sun.light_color = Color(1, 0.97, 0.9).lerp(Color(1.0, 0.62, 0.35), warm)
	_sun.light_energy = lerpf(0.0, 1.5, daylight) * lerpf(1.0, 0.35, _rain_amount)
	_sun.shadow_enabled = daylight > 0.2
	var night := 1.0 - daylight
	var top := Color(0.30, 0.50, 0.78).lerp(Color(0.42, 0.45, 0.5), _rain_amount).lerp(Color(0.02, 0.03, 0.08), night)
	var hor := Color(0.72, 0.78, 0.82).lerp(Color(0.95, 0.62, 0.4), warm * daylight).lerp(Color(0.58, 0.6, 0.62), _rain_amount).lerp(Color(0.04, 0.05, 0.1), night)
	_sky_mat.sky_top_color = top
	_sky_mat.sky_horizon_color = hor
	_sky_mat.ground_horizon_color = hor
	_sky_mat.ground_bottom_color = hor.darkened(0.5)
	_env.ambient_light_energy = lerpf(1.0, 0.5, night)
	_env.ambient_light_color = Color(0.62, 0.68, 0.66).lerp(Color(0.25, 0.3, 0.45), night)
	_moon.light_energy = 0.35 * night * lerpf(1.0, 0.4, _rain_amount)
	_env.fog_light_color = hor
	_env.fog_density = lerpf(0.0018, 0.012, _rain_amount)
	_terrain_mat.set_shader_parameter("wet", _rain_amount)
	_grass_mat.set_shader_parameter("wet", _rain_amount)
	_grass_mat.set_shader_parameter("wind", lerpf(0.1, 0.28, _rain_amount))
	_water_mat.set_shader_parameter("rain", _rain_amount)
	_rain.emitting = _rain_amount > 0.3
	if _player:
		_rain.global_position = _player.global_position + Vector3(0, 12, 0)


func _move_player(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if _joy_id >= 0:
		dir = _joy_vec
	var amount := minf(dir.length(), 1.0)
	var p := _player.position
	var cell := Vector2i(int(p.x / CELL), int(p.z / CELL))
	var depth := 0.0
	if _water_level.size() == MundoSim.W * MundoSim.H and cell.x >= 0 and cell.y >= 0 and cell.x < MundoSim.W and cell.y < MundoSim.H:
		depth = maxf(0.0, _water_level[cell.y * MundoSim.W + cell.x] - height_at(p.x, p.z))
	var water_slow := lerpf(1.0, 0.4, clampf(depth / 0.8, 0.0, 1.0))
	if amount > 0.12:
		# anda na direção para onde a câmera está olhando
		var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
		var right := Vector3(cos(_yaw), 0, -sin(_yaw))
		var move := (right * dir.x - fwd * dir.y).normalized()
		var running := amount > 0.85
		var sp := (RUN_SPEED if running else WALK_SPEED) * water_slow
		p += move * sp * delta
		p.x = clampf(p.x, 1.0, MundoSim.W * CELL - 1.0)
		p.z = clampf(p.z, 1.0, MundoSim.H * CELL - 1.0)
		_face = lerp_angle(_face, atan2(-move.x, -move.z), minf(1.0, delta * 10.0))
		_play("Run" if running else "Walk", water_slow)
	else:
		_play("Idle")
	p.y = height_at(p.x, p.z) - minf(depth, 0.9) * 0.5
	_player.position = p
	_player.rotation.y = _face

	# câmera em terceira pessoa, atrás do personagem
	var target := p + Vector3(0, 1.55, 0)
	var back := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	var cam_pos := target + back * CAM_DIST
	cam_pos.y = maxf(cam_pos.y, height_at(cam_pos.x, cam_pos.z) + 0.4)
	_cam.position = _cam.position.lerp(cam_pos, minf(1.0, delta * 12.0)) if _cam.position.distance_to(cam_pos) < 8.0 else cam_pos
	_cam.look_at(target + Vector3(0, 0.15, 0))


# ================== CONTROLE ==================
# Lado esquerdo da tela: andar (joystick). Lado direito: girar a câmera.

func _input(e: InputEvent) -> void:
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if e is InputEventScreenTouch:
		if e.pressed:
			if e.position.x < half and _joy_id < 0:
				_joy_id = e.index
				_joy_origin = e.position
				_joy_vec = Vector2.ZERO
			elif e.position.x >= half and _look_id < 0:
				_look_id = e.index
				_look_last = e.position
		else:
			if e.index == _joy_id:
				_joy_id = -1
				_joy_vec = Vector2.ZERO
			if e.index == _look_id:
				_look_id = -1
		_joy_ui.queue_redraw()
	elif e is InputEventScreenDrag:
		if e.index == _joy_id:
			_joy_vec = ((e.position - _joy_origin) / JOY_RADIUS).limit_length(1.0)
			_joy_ui.queue_redraw()
		elif e.index == _look_id:
			var d: Vector2 = e.position - _look_last
			_look_last = e.position
			_yaw -= d.x * 0.006
			_pitch = clampf(_pitch + d.y * 0.004, -0.15, 1.1)


func _draw_joy() -> void:
	if _joy_id < 0:
		return
	_joy_ui.draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	_joy_ui.draw_circle(_joy_origin + _joy_vec * JOY_RADIUS, 28, Color(1, 0.54, 0.24, 0.7))


## Monta a superfície da água em segundo plano, sem travar a tela.
func _update_water(wat: PackedFloat32Array) -> void:
	if _water_task >= 0:
		return
	_water_task = WorkerThreadPool.add_task(_water_arrays.bind(wat))


func _finish_water() -> void:
	if _water_task < 0 or not WorkerThreadPool.is_task_completed(_water_task):
		return
	WorkerThreadPool.wait_for_task_completion(_water_task)
	_water_task = -1
	_water_level = _w_level
	if _w_arr.is_empty():
		_water_mi.mesh = null
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _w_arr)
	_water_mi.mesh = mesh


## Calcula a malha da água: lagoas, córregos e poças.
func _water_arrays(wat: PackedFloat32Array) -> void:
	var W := MundoSim.W; var H := MundoSim.H
	var NONE := -1e9
	if _corner_h.is_empty():
		_corner_h.resize((W + 1) * (H + 1))
		for y in H + 1:
			for x in W + 1:
				_corner_h[y * (W + 1) + x] = height_at(x * CELL, y * CELL)
	var lvl := PackedFloat32Array(); lvl.resize(W * H); lvl.fill(NONE)
	var count := 0
	for i in W * H:
		if wat[i] > 0.035:
			lvl[i] = (_ter[i] + wat[i]) * HS
	# estende a água um pouco por baixo da margem, para o terreno cortar a borda
	var ext := lvl.duplicate()
	for y in H:
		for x in W:
			var i := y * W + x
			if lvl[i] > NONE:
				count += 1
				continue
			var best := NONE
			if x > 0 and lvl[i - 1] > best: best = lvl[i - 1]
			if x < W - 1 and lvl[i + 1] > best: best = lvl[i + 1]
			if y > 0 and lvl[i - W] > best: best = lvl[i - W]
			if y < H - 1 and lvl[i + W] > best: best = lvl[i + W]
			ext[i] = best
			if best > NONE:
				count += 1
	_w_level = lvl
	_w_arr = []
	if count == 0:
		return
	# nível em cada canto: média das células vizinhas que têm água
	var cw := W + 1
	var corner := PackedFloat32Array(); corner.resize(cw * (H + 1)); corner.fill(NONE)
	for y in H + 1:
		for x in cw:
			var s := 0.0; var n := 0
			if x > 0 and y > 0 and ext[(y - 1) * W + x - 1] > NONE: s += ext[(y - 1) * W + x - 1]; n += 1
			if x < W and y > 0 and ext[(y - 1) * W + x] > NONE: s += ext[(y - 1) * W + x]; n += 1
			if x > 0 and y < H and ext[y * W + x - 1] > NONE: s += ext[y * W + x - 1]; n += 1
			if x < W and y < H and ext[y * W + x] > NONE: s += ext[y * W + x]; n += 1
			if n > 0:
				corner[y * cw + x] = s / n
	var verts := PackedVector3Array(); verts.resize(count * 6)
	var cols := PackedColorArray(); cols.resize(count * 6)
	var nrm := PackedVector3Array(); nrm.resize(count * 6); nrm.fill(Vector3.UP)
	var k := 0
	for y in H:
		for x in W:
			if ext[y * W + x] <= NONE:
				continue
			var c00 := y * cw + x; var c10 := c00 + 1; var c01 := c00 + cw; var c11 := c01 + 1
			var p00 := Vector3(x * CELL, corner[c00], y * CELL)
			var p10 := Vector3((x + 1) * CELL, corner[c10], y * CELL)
			var p01 := Vector3(x * CELL, corner[c01], (y + 1) * CELL)
			var p11 := Vector3((x + 1) * CELL, corner[c11], (y + 1) * CELL)
			var d00 := Color(1, 1, 1, maxf(0.0, corner[c00] - _corner_h[c00]))
			var d10 := Color(1, 1, 1, maxf(0.0, corner[c10] - _corner_h[c10]))
			var d01 := Color(1, 1, 1, maxf(0.0, corner[c01] - _corner_h[c01]))
			var d11 := Color(1, 1, 1, maxf(0.0, corner[c11] - _corner_h[c11]))
			verts[k] = p00; cols[k] = d00
			verts[k + 1] = p10; cols[k + 1] = d10
			verts[k + 2] = p11; cols[k + 2] = d11
			verts[k + 3] = p00; cols[k + 3] = d00
			verts[k + 4] = p11; cols[k + 4] = d11
			verts[k + 5] = p01; cols[k + 5] = d01
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_NORMAL] = nrm
	_w_arr = arr
