extends Node3D
## Mundo do jogo em 3D, visto de cima (câmera aérea seguindo o personagem).
## Terreno, lagoas, mato e árvores da Amazônia são montados em código.
## O tempo passa sozinho: dia, noite e chuva vêm da simulação do mundo.

const MundoSim := preload("res://scripts/mundo_sim.gd")
const Plantas := preload("res://scripts/plantas.gd")

const CELL := 2.0           # metros por célula da simulação
const HS := 0.8             # metros por unidade de altura da simulação
const SUB := 2              # subdivisões do terreno por célula
const SPEED := 4.2          # m/s andando
const CAM_OFFSET := Vector3(0, 15, 11)
const JOY_RADIUS := 70.0
const CHUNK := 8            # células por bloco de vegetação

const TERRAIN_SHADER := """
shader_type spatial;
uniform float wet = 0.0;
varying vec3 wpos;
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y); }
float fbm(vec2 p){ float s = 0.0; float a = 0.5; for(int i = 0; i < 4; i++){ s += noise(p) * a; p *= 2.03; a *= 0.5; } return s; }
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	vec3 c = COLOR.rgb * COLOR.rgb * 1.15;
	float big = fbm(wpos.xz * 0.12);
	float mid = fbm(wpos.xz * 0.9);
	float fine = noise(wpos.xz * 6.0);
	c *= 0.78 + big * 0.35 + mid * 0.15 + fine * 0.07;
	// folhas secas e terra escura espalhadas pelo chão da mata
	float litter = smoothstep(0.55, 0.75, noise(wpos.xz * 4.1 + 11.0)) * smoothstep(0.4, 0.7, noise(wpos.xz * 0.7));
	c = mix(c, vec3(0.10, 0.06, 0.03), litter * 0.5 * (1.0 - COLOR.a));
	c *= mix(1.0, 0.72, wet);
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.55, wet);
	SPECULAR = 0.25;
}
"""

const PLANT_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float wind = 0.12;
uniform float wet = 0.0;
uniform vec3 player_pos = vec3(0.0);
varying vec3 wp;
void vertex(){
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = COLOR.a * COLOR.a;
	float t = TIME * 1.7 + root.x * 0.31 + root.z * 0.23;
	float gust = 0.6 + 0.4 * sin(TIME * 0.37 + root.x * 0.02);
	VERTEX.x += sin(t) * wind * s * gust;
	VERTEX.z += cos(t * 0.83) * wind * 0.6 * s * gust;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment(){
	// abre um buraco nas copas entre a câmera e o personagem, para ele não sumir
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 ab = player_pos - cam;
	float h = clamp(dot(wp - cam, ab) / dot(ab, ab), 0.0, 1.0);
	float d = length(wp - (cam + ab * h));
	float cut = smoothstep(5.0, 3.0, d) * step(player_pos.y + 2.3, wp.y);
	float dither = fract(dot(floor(FRAGCOORD.xy), vec2(0.5, 0.25)) + 0.125);
	if (cut > dither + 0.05) { discard; }
	if (UV2.x > 0.5) {
		// desenho de um ramo com folhas dentro do cartão
		vec2 q = UV * 2.0 - 1.0;
		float m = 0.0;
		for (int k = 0; k < 5; k++) {
			float a = float(k) * 1.2566 + 0.4;
			vec2 dir = vec2(cos(a), sin(a));
			vec2 p = q - dir * 0.42;
			vec2 r = vec2(dot(p, dir), dot(p, vec2(-dir.y, dir.x)));
			m = max(m, 1.0 - length(r / vec2(0.5, 0.2)));
		}
		m = max(m, 1.0 - length(q / 0.3));
		if (m < 0.02) { discard; }
	}
	vec3 c = COLOR.rgb;
	c = mix(c * c * 1.4, c, 0.55);
	c *= mix(1.0, 0.8, wet);
	ALBEDO = c;
	ROUGHNESS = mix(0.82, 0.45, wet);
	SPECULAR = 0.35;
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
var _plant_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _water_mi: MeshInstance3D
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _cam: Camera3D
var _rain: CPUParticles3D
var _player: Node3D
var _limbs := {}

var _hud: CanvasLayer
var _clock: Label
var _loading: Label
var _loading_bg: ColorRect
var _joy_ui: Control

var _ready_world := false
var _face := 0.0
var _walk := 0.0
var _moving := false
var _rain_amount := 0.0
var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _water_level := PackedFloat32Array()


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
	_sky_mat.sky_top_color = Color(0.32, 0.52, 0.78)
	_sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.82)
	_sky_mat.ground_horizon_color = Color(0.5, 0.55, 0.5)
	_sky_mat.ground_bottom_color = Color(0.2, 0.25, 0.2)
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
	_env.fog_light_color = Color(0.7, 0.76, 0.8)
	_env.fog_density = 0.0025
	_env.fog_sky_affect = 0.4
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 55.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.light_energy = 1.2
	_sun.shadow_opacity = 0.8
	add_child(_sun)
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.55, 0.65, 0.95)
	_moon.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-30), 0)
	_moon.shadow_enabled = false
	add_child(_moon)

	_cam = Camera3D.new()
	_cam.fov = 50
	_cam.far = 220
	add_child(_cam)

	_rain = CPUParticles3D.new()
	_rain.amount = 1400
	_rain.lifetime = 0.9
	_rain.emitting = false
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(22, 0.5, 22)
	_rain.direction = Vector3(0.1, -1, 0)
	_rain.spread = 2
	_rain.initial_velocity_min = 24
	_rain.initial_velocity_max = 28
	_rain.gravity = Vector3(0, -9.8, 0)
	var drop := BoxMesh.new()
	drop.size = Vector3(0.015, 0.55, 0.015)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.8, 0.86, 0.92, 0.45)
	drop.material = dm
	_rain.mesh = drop
	add_child(_rain)

	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = _shader(TERRAIN_SHADER)
	_plant_mat = ShaderMaterial.new()
	_plant_mat.shader = _shader(PLANT_SHADER)
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
	_build_terrain()
	await _set_loading("Enchendo as lagoas…")
	_water_mi = MeshInstance3D.new()
	_water_mi.material_override = _water_mat
	_water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water_mi)
	var w: PackedFloat32Array = sim.take_water()
	if not w.is_empty():
		_update_water(w)
	await _set_loading("Plantando a floresta…")
	await _build_vegetation()
	_build_player()
	_player.position = _ground_pos(Vector2((sim.spawn.x + 0.5) * CELL, (sim.spawn.y + 0.5) * CELL))
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


func _terrain_color(x: float, z: float, h: float, slope: float) -> Color:
	var hn := h / (_max_h * HS)
	var green := clampf(_field_at(_moist, x, z) * 2.2 + _field_at(_gw, x, z) / MundoSim.GW_CAP * 0.6, 0.0, 1.0)
	var forest := Color(0.16, 0.20, 0.08)        # chão de mata, sombreado
	var grass := Color(0.24, 0.36, 0.10)
	var dry := Color(0.40, 0.40, 0.22)
	var mud := Color(0.22, 0.17, 0.10)
	var rock := Color(0.42, 0.40, 0.36)
	var c := dry.lerp(grass, smoothstep(0.0, 0.35, green + 0.1)).lerp(forest, smoothstep(0.55, 1.0, green))
	if green > 0.85: c = c.lerp(mud, (green - 0.85) * 3.0)
	if hn > 0.7: c = c.lerp(rock, smoothstep(0.7, 0.85, hn))
	c = c.lerp(rock.darkened(0.1), smoothstep(0.55, 0.9, slope))
	c.a = smoothstep(0.7, 0.85, hn)   # nas pedras não tem folha seca
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
	add_child(mi)


## Monta a superfície da água: lagoas, córregos e poças.
func _update_water(wat: PackedFloat32Array) -> void:
	var W := MundoSim.W; var H := MundoSim.H
	var lvl := PackedFloat32Array(); lvl.resize(W * H); lvl.fill(-1e9)
	for i in W * H:
		if wat[i] > 0.035:
			lvl[i] = (_ter[i] + wat[i]) * HS
	# estende a água um pouco por baixo da margem, para o terreno cortar a borda
	var ext := lvl.duplicate()
	for y in H:
		for x in W:
			var i := y * W + x
			if lvl[i] > -1e8:
				continue
			var best := -1e9
			if x > 0: best = maxf(best, lvl[i - 1])
			if x < W - 1: best = maxf(best, lvl[i + 1])
			if y > 0: best = maxf(best, lvl[i - W])
			if y < H - 1: best = maxf(best, lvl[i + W])
			ext[i] = best
	_water_level = lvl
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for y in H:
		for x in W:
			var i := y * W + x
			var L := ext[i]
			if L < -1e8:
				continue
			var corners := [Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y + 1)]
			var vs := []
			var cs := []
			for c: Vector2 in corners:
				# nível do canto: média dos vizinhos com água
				var s := 0.0; var n := 0
				for oy in [-1, 0]:
					for ox in [-1, 0]:
						var cx: int = int(c.x) + ox; var cy: int = int(c.y) + oy
						if cx >= 0 and cy >= 0 and cx < W and cy < H and ext[cy * W + cx] > -1e8:
							s += ext[cy * W + cx]; n += 1
				var lv := s / n if n > 0 else L
				var px: float = c.x * CELL; var pz: float = c.y * CELL
				vs.append(Vector3(px, lv, pz))
				cs.append(Color(1, 1, 1, maxf(0.0, lv - height_at(px, pz))))
			for t in [0, 1, 2, 0, 2, 3]:
				verts.append(vs[t]); cols.append(cs[t])
	if verts.is_empty():
		_water_mi.mesh = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var nrm := PackedVector3Array(); nrm.resize(verts.size()); nrm.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = nrm
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_water_mi.mesh = mesh


func _build_vegetation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	# modelos: algumas variações de cada planta
	var kinds := {
		"capim_alto": {"meshes": [], "range": 45.0, "shadow": false},
		"capim": {"meshes": [], "range": 45.0, "shadow": false},
		"samambaia": {"meshes": [], "range": 60.0, "shadow": false},
		"heliconia": {"meshes": [], "range": 70.0, "shadow": true},
		"arbusto": {"meshes": [], "range": 80.0, "shadow": true},
		"folhagem": {"meshes": [], "range": 60.0, "shadow": false},
		"acai": {"meshes": [], "range": 150.0, "shadow": true},
		"castanheira": {"meshes": [], "range": 200.0, "shadow": true},
		"cupuacu": {"meshes": [], "range": 120.0, "shadow": true},
		"bananeira": {"meshes": [], "range": 120.0, "shadow": true},
		"samauma": {"meshes": [], "range": 220.0, "shadow": true},
	}
	for k in 3:
		kinds.capim_alto.meshes.append(Plantas.capim(rng, true))
		kinds.capim.meshes.append(Plantas.capim(rng, false))
		kinds.acai.meshes.append(Plantas.acai(rng))
		kinds.cupuacu.meshes.append(Plantas.cupuacu(rng))
		kinds.bananeira.meshes.append(Plantas.bananeira(rng))
	for k in 2:
		kinds.samambaia.meshes.append(Plantas.samambaia(rng))
		kinds.heliconia.meshes.append(Plantas.heliconia(rng))
		kinds.arbusto.meshes.append(Plantas.arbusto(rng))
		kinds.folhagem.meshes.append(Plantas.folhagem(rng))
		kinds.castanheira.meshes.append(Plantas.castanheira(rng))
	kinds.samauma.meshes.append(Plantas.samauma(rng))
	await get_tree().process_frame

	var W := MundoSim.W; var H := MundoSim.H
	var spawn_p := Vector2((sim.spawn.x + 0.5) * CELL, (sim.spawn.y + 0.5) * CELL)
	var chunks_x := ceili(float(W) / CHUNK); var chunks_z := ceili(float(H) / CHUNK)
	var done := 0
	for cz in chunks_z:
		for cx in chunks_x:
			var lists := {}
			for name in kinds:
				lists[name] = []
				for m in kinds[name].meshes.size():
					lists[name].append([])
			for y in range(cz * CHUNK, mini((cz + 1) * CHUNK, H)):
				for x in range(cx * CHUNK, mini((cx + 1) * CHUNK, W)):
					var i := y * W + x
					if _water_level.size() == W * H and _water_level[i] > -1e8:
						continue
					var hn := _ter[i] / _max_h
					if hn > 0.86:
						continue
					var green := clampf(_moist[i] * 2.2 + _gw[i] / MundoSim.GW_CAP * 0.6, 0.0, 1.0)
					var rocky := smoothstep(0.7, 0.86, hn)
					var near_water := _moist[i] > 0.25
					# capim e mato baixo
					var n_grass := int(lerpf(2.0, 5.0, green) * (1.0 - rocky) + rng.randf())
					for g in n_grass:
						var kind := "capim_alto" if rng.randf() < 0.35 - green * 0.15 else "capim"
						_add(lists, kind, rng, x, y, 0.8, 1.3)
					if rng.randf() < 0.45 * (1.0 - rocky):
						var r := rng.randf()
						var kind := "samambaia"
						if r < 0.25: kind = "arbusto"
						elif r < 0.45: kind = "folhagem"
						elif r < 0.6 and green > 0.4: kind = "heliconia"
						_add(lists, kind, rng, x, y, 0.8, 1.25)
					# árvores
					var p := Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
					if p.distance_to(spawn_p) < 7.0:
						continue
					var tree_chance := lerpf(0.05, 0.16, green) * (1.0 - rocky)
					if rng.randf() < tree_chance:
						var r := rng.randf()
						var kind: String
						if near_water and r < 0.55: kind = "acai"
						elif r < 0.08 and near_water: kind = "samauma"
						elif r < 0.35: kind = "cupuacu"
						elif r < 0.55 and green > 0.3: kind = "bananeira"
						elif hn > 0.3 and r < 0.8: kind = "castanheira"
						else: kind = "acai" if green > 0.5 else "cupuacu"
						if kind == "samauma" and rng.randf() > 0.25:
							kind = "castanheira"
						_add(lists, kind, rng, x, y, 0.85, 1.15)
			for name in lists:
				for m in lists[name].size():
					var items: Array = lists[name][m]
					if items.is_empty():
						continue
					_make_multimesh(kinds[name].meshes[m], items, kinds[name].range, kinds[name].shadow)
			done += 1
			if done % 6 == 0:
				await _set_loading("Plantando a floresta… %d%%" % int(done * 100.0 / (chunks_x * chunks_z)))


func _add(lists: Dictionary, kind: String, rng: RandomNumberGenerator, x: int, y: int, smin: float, smax: float) -> void:
	var px := (x + rng.randf()) * CELL
	var pz := (y + rng.randf()) * CELL
	var s := rng.randf_range(smin, smax)
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
	var tint := Color(1, 1, 1).lerp(Color(rng.randf_range(0.8, 1.15), rng.randf_range(0.85, 1.15), rng.randf_range(0.8, 1.05)), 0.8)
	var variants: Array = lists[kind]
	variants[rng.randi() % variants.size()].append([Transform3D(b, Vector3(px, height_at(px, pz) - 0.05, pz)), tint])


func _make_multimesh(mesh: Mesh, items: Array, vis_range: float, shadow: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for k in items.size():
		mm.set_instance_transform(k, items[k][0])
		mm.set_instance_color(k, items[k][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _plant_mat
	mmi.visibility_range_end = vis_range
	mmi.visibility_range_end_margin = 8.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# ================== PERSONAGEM ==================

func _part(mesh: Mesh, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_player() -> void:
	_player = Node3D.new()
	add_child(_player)
	var body := Node3D.new()
	_player.add_child(body)
	var skin := Color(0.62, 0.44, 0.32)
	var shirt := Color(0.75, 0.40, 0.14)
	var pants := Color(0.18, 0.22, 0.28)
	var torso := CapsuleMesh.new(); torso.radius = 0.2; torso.height = 0.7
	_part(torso, shirt, Vector3(0, 1.2, 0), body)
	var head := SphereMesh.new(); head.radius = 0.14; head.height = 0.3
	_part(head, skin, Vector3(0, 1.68, 0), body)
	var hair := SphereMesh.new(); hair.radius = 0.15; hair.height = 0.18
	_part(hair, Color(0.1, 0.07, 0.05), Vector3(0, 1.76, -0.02), body)
	for side in [-1.0, 1.0]:
		var hip := Node3D.new(); hip.position = Vector3(0.1 * side, 0.9, 0); body.add_child(hip)
		var leg := CapsuleMesh.new(); leg.radius = 0.085; leg.height = 0.85
		_part(leg, pants, Vector3(0, -0.42, 0), hip)
		var sh := Node3D.new(); sh.position = Vector3(0.27 * side, 1.45, 0); body.add_child(sh)
		var arm := CapsuleMesh.new(); arm.radius = 0.06; arm.height = 0.62
		_part(arm, shirt, Vector3(0, -0.28, 0), sh)
		var hand := SphereMesh.new(); hand.radius = 0.055; hand.height = 0.11
		_part(hand, skin, Vector3(0, -0.6, 0), sh)
		_limbs["leg%d" % int(side)] = hip
		_limbs["arm%d" % int(side)] = sh
	_limbs["body"] = body


func _process(delta: float) -> void:
	_update_sky()
	if not _ready_world:
		return
	var w: PackedFloat32Array = sim.take_water()
	if not w.is_empty():
		_update_water(w)
	_move_player(delta)
	var h: float = sim.hour()
	_clock.text = "Dia %d · %02d:%02d%s" % [sim.day(), int(h), int(fmod(h, 1.0) * 60.0), " · Chovendo" if sim.raining else ""]


func _update_sky() -> void:
	if sim == null:
		return
	var h: float = sim.hour() if sim.is_ready else 7.0
	var target := 1.0 if (sim.is_ready and sim.raining) else 0.0
	_rain_amount = move_toward(_rain_amount, target, get_process_delta_time() * 0.3)
	# sol nasce às 6h e se põe às 18h
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
	_env.ambient_light_energy = lerpf(1.0, 0.5, night)
	_moon.light_energy = 0.35 * night * lerpf(1.0, 0.4, _rain_amount)
	_env.ambient_light_color = Color(0.62, 0.68, 0.66).lerp(Color(0.25, 0.3, 0.45), night)
	_env.fog_light_color = hor
	_env.fog_density = lerpf(0.0025, 0.012, _rain_amount)
	_terrain_mat.set_shader_parameter("wet", _rain_amount)
	_plant_mat.set_shader_parameter("wet", _rain_amount)
	_plant_mat.set_shader_parameter("wind", lerpf(0.1, 0.3, _rain_amount))
	_water_mat.set_shader_parameter("rain", _rain_amount)
	if _player:
		_plant_mat.set_shader_parameter("player_pos", _player.global_position)
	_rain.emitting = _rain_amount > 0.3
	if _player:
		_rain.global_position = _player.global_position + Vector3(0, 16, -4)


func _move_player(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if _joy_id >= 0:
		dir = _joy_vec
	_moving = dir.length() > 0.1
	var p := _player.position
	var cell := Vector2i(int(p.x / CELL), int(p.z / CELL))
	var depth := 0.0
	if _water_level.size() == MundoSim.W * MundoSim.H and cell.x >= 0 and cell.y >= 0 and cell.x < MundoSim.W and cell.y < MundoSim.H:
		depth = maxf(0.0, _water_level[cell.y * MundoSim.W + cell.x] - height_at(p.x, p.z))
	if _moving:
		var sp := SPEED * lerpf(1.0, 0.4, clampf(depth / 0.8, 0.0, 1.0))
		p.x += dir.x * sp * delta
		p.z += dir.y * sp * delta
		p.x = clampf(p.x, 1.0, MundoSim.W * CELL - 1.0)
		p.z = clampf(p.z, 1.0, MundoSim.H * CELL - 1.0)
		_face = lerp_angle(_face, atan2(dir.x, dir.y), minf(1.0, delta * 12.0))
		_walk += delta * sp * 2.2
	else:
		_walk = lerpf(_walk, roundf(_walk / PI) * PI, minf(1.0, delta * 8.0))
	p.y = height_at(p.x, p.z) - minf(depth, 0.9) * 0.6
	_player.position = p
	_player.rotation.y = _face
	var sw := sin(_walk) * (0.6 if _moving else 0.0)
	_limbs["leg-1"].rotation.x = sw
	_limbs["leg1"].rotation.x = -sw
	_limbs["arm-1"].rotation.x = -sw * 0.8
	_limbs["arm1"].rotation.x = sw * 0.8
	_limbs["body"].position.y = absf(cos(_walk)) * 0.04 if _moving else 0.0
	var target := _player.position + CAM_OFFSET
	_cam.position = _cam.position.lerp(target, minf(1.0, delta * 5.0)) if _cam.position.distance_to(target) < 30 else target
	_cam.look_at(_player.position + Vector3(0, 1.0, 0))


# ================== CONTROLE ==================

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _joy_id < 0 and e.position.x < get_viewport().get_visible_rect().size.x * 0.65:
			_joy_id = e.index
			_joy_origin = e.position
			_joy_vec = Vector2.ZERO
		elif not e.pressed and e.index == _joy_id:
			_joy_id = -1
			_joy_vec = Vector2.ZERO
		_joy_ui.queue_redraw()
	elif e is InputEventScreenDrag and e.index == _joy_id:
		_joy_vec = ((e.position - _joy_origin) / JOY_RADIUS).limit_length(1.0)
		_joy_ui.queue_redraw()


func _draw_joy() -> void:
	if _joy_id < 0:
		return
	_joy_ui.draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	_joy_ui.draw_circle(_joy_origin + _joy_vec * JOY_RADIUS, 28, Color(1, 0.54, 0.24, 0.7))
