extends Node3D
## Mundo do jogo em 3D, em terceira pessoa.
## Mapa grande coberto de grama, com serra, lagoas e chuva automática.
## A grama só é montada perto do jogador, para o jogo rodar leve no celular.

const MundoSim := preload("res://scripts/mundo_sim.gd")
const Diag := preload("res://scripts/diagnostico.gd")
const Mundos := preload("res://scripts/mundos.gd")
const Perfil := preload("res://scripts/perfil.gd")
const Calendario := preload("res://scripts/ui/calendario.gd")
const Mochila := preload("res://scripts/ui/mochila.gd")
const Arvores := preload("res://scripts/world/arvores.gd")
const Itens := preload("res://scripts/itens.gd")
const Corte := preload("res://scripts/world/corte.gd")
const Craft := preload("res://scripts/ui/craft.gd")
const Icones := preload("res://scripts/ui/icones.gd")
const Cipos := preload("res://scripts/world/cipos.gd")
const Buracos := preload("res://scripts/world/buracos.gd")
const SAVE_EVERY := 60.0     # salva o mundo a cada minuto

const CELL := 5.0            # metros por célula da simulação (mapa de 640 x 480 m)
const HS := 1.2              # metros por unidade de altura da simulação
var SUB := 2                 # subdivisões do terreno por célula
const WALK_SPEED := 2.2
const RUN_SPEED := 5.5
const JOY_RADIUS := 70.0
const GRASS_CHUNK := 12.0    # tamanho de cada bloco de grama, em metros
var GRASS_RADIUS := 3        # blocos de grama em volta do jogador
var GRASS_PER_CHUNK := 200
const CAM_DIST := 4.2
const ANIMS := {"Idle": "parado", "Walk": "andando", "Run": "correndo"}

const TERRAIN_SHADER := """
shader_type spatial;
uniform float wet = 0.0;
uniform sampler2D soil_a : filter_linear, repeat_disable;   // R jazida de argila, G areia, B umidade do solo, A grama
uniform sampler2D soil_b : filter_linear, repeat_disable;   // R leito de lagoa, G umidade da superfície, B filete de enxurrada
uniform vec2 world_size = vec2(640.0, 480.0);
// buracos cavados perto do jogador: (x, z, raio, 0). O chão não é desenhado dentro deles.
uniform vec4 holes[32];
uniform int hole_n = 0;
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
	for (int i = 0; i < hole_n; i++) {
		if (distance(wpos.xz, holes[i].xy) < holes[i].z) { discard; }
	}
	vec2 uv = wpos.xz / world_size;
	vec4 a = texture(soil_a, uv);
	vec4 b = texture(soil_b, uv);
	float rock = COLOR.a;
	float clay = a.r; float sand = a.g; float moist = a.b; float grass = a.a;
	float bed = smoothstep(0.3, 0.7, b.r);    // leito de lagoa (com ou sem água)
	float surf = b.g;                          // umidade da superfície
	vec3 loam = vec3(0.34, 0.25, 0.17);
	vec3 sandc = vec3(0.74, 0.64, 0.47);
	vec3 clayc = vec3(0.56, 0.30, 0.19);       // terra avermelhada da jazida de argila
	vec3 mud = vec3(0.31, 0.27, 0.21);         // lama do fundo
	vec3 soil = mix(loam, sandc, sand * 0.8);
	float patch = smoothstep(0.15, 0.55, clay + (noise(wpos.xz * 0.45) - 0.5) * 0.35);
	soil = mix(soil, clayc, patch * (1.0 - bed));
	soil = mix(soil, mud, bed);
	float soaked = smoothstep(0.5, 0.9, surf);
	soil *= mix(1.0, 0.55, soaked);
	// fundo de lagoa que secou: a lama clareia e racha em placas
	float dry_bed = bed * (1.0 - smoothstep(0.25, 0.6, surf)) * (1.0 - smoothstep(0.2, 0.6, grass));
	float cr = cracks(wpos.xz * 1.1);
	soil = mix(soil, soil * 1.35 + vec3(0.04, 0.035, 0.02), dry_bed * 0.6);
	soil = mix(soil, soil * 0.28, cr * dry_bed);
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
	// filete de enxurrada: trilha estreita e sinuosa de água rasa correndo
	float wob = (noise(wpos.xz * 0.35) - 0.5) * 0.55 + (noise(wpos.xz * 1.6 + vec2(0.0, TIME * 0.6)) - 0.5) * 0.12;
	float run = smoothstep(0.7, 0.8, b.b + wob);
	float glint = noise(wpos.xz * 2.5 - vec2(TIME * 0.9, TIME * 0.4));
	// a água da enxurrada desce barrenta
	c = mix(c, vec3(0.27, 0.19, 0.11) + glint * 0.07, run * 0.85);
	ALBEDO = c;
	ROUGHNESS = mix(mix(0.95, 0.4, wetness), 0.04, run);
	SPECULAR = mix(mix(0.2, 0.45, wetness), 0.7, run);
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
uniform vec4 holes[32];
uniform int hole_n = 0;
void vertex(){
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// não cresce capim dentro dos buracos (nem logo na beira)
	for (int i = 0; i < hole_n; i++) {
		if (distance(root.xz, holes[i].xy) < holes[i].z * 1.35) { VERTEX *= 0.0; }
	}
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
uniform vec3 mud = vec3(0.36, 0.26, 0.15);
varying float depth;
varying float murk;
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
	murk = COLOR.r;
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
	// barro: enxurrada marrom; lagoa e rio ficam só um pouco sujos depois da chuva
	float m = clamp(murk, 0.0, 1.0) * (0.85 + noise(wpos.xz * 0.15 + vec2(t * 0.02, 0.0)) * 0.3);
	vec3 clean = mix(shallow, deep, sqrt(d));
	vec3 muddy = mud * mix(1.0, 0.55, sqrt(d));
	ALBEDO = mix(clean, muddy, clamp(m, 0.0, 1.0) * 0.9) + vec3(0.05, 0.07, 0.08) * fres;
	ALPHA = clamp(mix(0.45, 0.93, sqrt(d)) + m * 0.3 + fres * 0.15, 0.0, 1.0) * smoothstep(0.0, 0.06, depth);
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

# coleta de argila
const BAG_MAX := 30.0
var _bag := 0.0                  # kg de argila na mochila
var _dig_btn: Button
var _dig_bar: ProgressBar
var _inv_label: Label
var _toast: Label
var _toast_t := 0.0
var _dig_check := 0.0
var _digging := false
var _dig_t := 0.0
var _dig_need := 1.0
var _dig_info := {}
var _dig_cell := Vector2i.ZERO
var _loading: Label
var _loading_bg: ColorRect
var _joy_ui: Control

var _ready_world := false
var _play_time := 0.0
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
var _world_id := ""
var _cal: Control = null
var _bag_ui: Control = null
var _arvores: Node3D = null
var _seeds := 0                  # sementes de Cedrinho na mochila
var _seed_btn: Button
var _seed_check := 0.0
var _save_timer := SAVE_EVERY
# itens, ferramenta na mão e corte de árvore
var _itens := {}                 # id -> quantidade (machado, pedra...)
var _mao := ""                   # ferramenta equipada
var _chao: Array = []            # itens soltos no chão: {id, qtd, x, z, node}
var _craft_ui: Control = null
var _chop_pose: Node = null
var _axe_node: Node3D = null
var _chop_btn: Button
var _pick_btn: Button
var _act_check := 0.0
var _chopping := false
var _chop_tree = null
var _chop_t := 0.0
var _swing_on := false
var _chop_log := {}               # cortando uma tora deitada (em vez de árvore em pé)
var _jump_btn: Button
var _log_btn: Button
var _vine_btn: Button
var _cipos: Node3D = null
var _buracos: Node3D = null
var _plant_btn: Button
var _chop_hole := false           # cavando com a cavadeira
var _holes_t := 0.0
var _carry := {}                  # tora no ombro (dados da tora)
var _carry_node: Node3D = null
var _carry_kg := 0.0
var _crouch_job := ""             # "pegar" ou "largar" enquanto agacha
var _crouch_t := 0.0
var _crouch_target := {}
var _pending_carry := {}
var _vy := 0.0                    # velocidade vertical (pulo)
var _air := false
var _swing_queued := false
var _chop_idle := 0.0
const DEEP := 0.05        # água parada funda o bastante para virar poça ou lagoa na tela; a rasa só molha o chão


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_world()
		Diag.marcar("ok")
	elif what == NOTIFICATION_APPLICATION_RESUMED and _ready_world:
		Diag.marcar("jogando")


func _exit_tree() -> void:
	_save_player()
	Diag.marcar("menu")
	if _water_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_water_task)


func _ready() -> void:
	Diag.marcar("gerando mundo")
	_build_hud()
	_build_environment()
	sim = MundoSim.new()
	_world_id = str(Engine.get_meta("mundo", ""))
	var meta := Mundos.read_meta(_world_id) if _world_id != "" else {}
	if not meta.is_empty():
		sim.save_dir = Mundos.dir(_world_id)
		sim.world_seed = int(meta.get("semente", 0))
		if FileAccess.file_exists(sim.save_dir + "/mundo.dat"):
			_loading.text = "Carregando %s…" % str(meta.get("nome", "o mundo"))
	else:
		_world_id = ""
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

	_inv_label = _hud_label(Vector2(24, 54), 19)
	_toast = _hud_label(Vector2(0, 0), 22)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 90
	_toast.offset_left = -400
	_toast.offset_right = 400
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_dig_btn = Icones.IconButton.new()
	_dig_btn.text = "Pegar argila"
	_dig_btn.add_theme_font_size_override("font_size", 22)
	_dig_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dig_btn.offset_left = -430
	_dig_btn.offset_top = -146
	_dig_btn.offset_right = -300
	_dig_btn.offset_bottom = -16
	_dig_btn.visible = false
	_dig_btn.pressed.connect(_start_dig)
	_hud.add_child(_dig_btn)

	_seed_btn = Icones.IconButton.new()
	_seed_btn.text = "Pegar semente"
	_seed_btn.add_theme_font_size_override("font_size", 22)
	_seed_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_seed_btn.offset_left = -430
	_seed_btn.offset_top = -286
	_seed_btn.offset_right = -300
	_seed_btn.offset_bottom = -156
	_seed_btn.visible = false
	_seed_btn.pressed.connect(_pick_seed)
	_hud.add_child(_seed_btn)

	_chop_btn = Icones.IconButton.new()
	_chop_btn.text = "Cortar"
	_chop_btn.add_theme_font_size_override("font_size", 22)
	_chop_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_chop_btn.offset_left = -290
	_chop_btn.offset_top = -146
	_chop_btn.offset_right = -160
	_chop_btn.offset_bottom = -16
	_chop_btn.visible = false
	_chop_btn.pressed.connect(_start_chop)
	_hud.add_child(_chop_btn)

	_jump_btn = Icones.IconButton.new()
	_jump_btn.text = "Pular"
	_jump_btn.add_theme_font_size_override("font_size", 22)
	_jump_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_jump_btn.offset_left = -150
	_jump_btn.offset_top = -146
	_jump_btn.offset_right = -30
	_jump_btn.offset_bottom = -16
	_jump_btn.pressed.connect(_jump)
	_hud.add_child(_jump_btn)

	_plant_btn = Icones.IconButton.new()
	_plant_btn.text = "Fincar tora"
	_plant_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_plant_btn.offset_left = -150
	_plant_btn.offset_top = -426
	_plant_btn.offset_right = -30
	_plant_btn.offset_bottom = -296
	_plant_btn.visible = false
	_plant_btn.pressed.connect(_plant_log)
	_hud.add_child(_plant_btn)

	_vine_btn = Icones.IconButton.new()
	_vine_btn.text = "Coletar cipó"
	_vine_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_vine_btn.offset_left = -430
	_vine_btn.offset_top = -426
	_vine_btn.offset_right = -300
	_vine_btn.offset_bottom = -296
	_vine_btn.visible = false
	_vine_btn.pressed.connect(_collect_vine)
	_hud.add_child(_vine_btn)

	_log_btn = Icones.IconButton.new()
	_log_btn.add_theme_font_size_override("font_size", 22)
	_log_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_log_btn.offset_left = -290
	_log_btn.offset_top = -286
	_log_btn.offset_right = -160
	_log_btn.offset_bottom = -156
	_log_btn.visible = false
	_log_btn.pressed.connect(_log_action)
	_hud.add_child(_log_btn)

	_pick_btn = Icones.IconButton.new()
	_pick_btn.add_theme_font_size_override("font_size", 22)
	_pick_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_pick_btn.offset_left = -150
	_pick_btn.offset_top = -286
	_pick_btn.offset_right = -30
	_pick_btn.offset_bottom = -156
	_pick_btn.visible = false
	_pick_btn.pressed.connect(_pick_ground)
	_hud.add_child(_pick_btn)

	_dig_bar = ProgressBar.new()
	_dig_bar.set_anchors_preset(Control.PRESET_CENTER)
	_dig_bar.offset_left = -160
	_dig_bar.offset_right = 160
	_dig_bar.offset_top = 70
	_dig_bar.offset_bottom = 92
	_dig_bar.show_percentage = false
	_dig_bar.visible = false
	_hud.add_child(_dig_bar)

	var menu := Icones.IconButton.new()
	menu.show_caption = false
	menu.text = "Menu"
	menu.add_theme_font_size_override("font_size", 20)
	menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu.offset_left = -96
	menu.offset_top = 6
	menu.offset_right = -20
	menu.offset_bottom = 72
	menu.pressed.connect(func():
		_save_world()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	_hud.add_child(menu)

	# por enquanto o calendário abre por este botão; depois vai ser um item da mochila
	var cal_btn := Icones.IconButton.new()
	cal_btn.show_caption = false
	cal_btn.text = "Calendário"
	cal_btn.add_theme_font_size_override("font_size", 20)
	cal_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	cal_btn.offset_left = -190
	cal_btn.offset_top = 6
	cal_btn.offset_right = -110
	cal_btn.offset_bottom = 72
	cal_btn.pressed.connect(_open_calendar)
	_hud.add_child(cal_btn)

	# botão da mochila: só o desenho da mochila, sem bola em volta
	var bag_btn: Button = Mochila.BackpackButton.new()
	bag_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bag_btn.offset_left = -280
	bag_btn.offset_top = 8
	bag_btn.offset_right = -200
	bag_btn.offset_bottom = 70
	bag_btn.pressed.connect(_open_backpack)
	_hud.add_child(bag_btn)

	# craft de mão (poucas receitas; o craft de verdade vai ser nas bancadas)
	var craft_btn := Icones.IconButton.new()
	craft_btn.show_caption = false
	craft_btn.text = "Craft"
	craft_btn.add_theme_font_size_override("font_size", 20)
	craft_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	craft_btn.offset_left = -370
	craft_btn.offset_top = 6
	craft_btn.offset_right = -290
	craft_btn.offset_bottom = 72
	craft_btn.pressed.connect(_open_craft)
	_hud.add_child(craft_btn)
	_inv_label.visible = false   # o que tem na mochila aparece na tela da mochila

	_joy_ui = Control.new()
	_joy_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_joy_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_ui.draw.connect(_draw_joy)
	_hud.add_child(_joy_ui)
	_update_inventory()


func _hud_label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(l)
	return l


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
	Diag.marcar("moldando terreno")
	await _set_loading("Moldando o terreno…")
	_apply_soil()
	_build_terrain()
	Diag.marcar("enchendo lagoas")
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
	Diag.marcar("carregando personagem")
	await _set_loading("Chamando o personagem…")
	_build_player()
	_player.position = _ground_pos(Vector2((sim.spawn.x + 0.5) * CELL, (sim.spawn.y + 0.5) * CELL))
	_yaw = 0.0
	_load_player()
	Diag.marcar("plantando grama")
	await _set_loading("Plantando a grama…")
	for k in 3:
		_grass_meshes.append(_make_grass_mesh(k))
	_update_grass(true)
	Diag.marcar("plantando arvores")
	await _set_loading("Crescendo a floresta…")
	var t0 := Time.get_ticks_msec()
	_arvores = Arvores.new()
	add_child(_arvores)
	_arvores.build(self, int(sim.world_seed), Mundos.dir(_world_id) + "/arvores.json" if _world_id != "" else "")
	print("árvores: %d plantas em %d ms" % [_arvores.plants.size(), Time.get_ticks_msec() - t0])
	_cipos = Cipos.new()
	add_child(_cipos)
	_cipos.build(self, _arvores, int(sim.world_seed), Mundos.dir(_world_id) + "/cipos.json" if _world_id != "" else "")
	_arvores.fell_hook = _cipos.attach_falling
	_arvores.fall_done_hook = _cipos._rebuild
	_buracos = Buracos.new()
	add_child(_buracos)
	_buracos.changed_hook = _update_holes
	_buracos.build(self, _arvores, Mundos.dir(_world_id) + "/buracos.json" if _world_id != "" else "")
	if not _pending_carry.is_empty():
		_hold_log(_pending_carry)
		_pending_carry = {}
	_loading.visible = false
	_loading_bg.visible = false
	# hora e dia não aparecem na tela (o calendário vai mostrar a data)
	_ready_world = true
	Diag.marcar("entrando no mundo")


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
	# o "corpo" é um nó separado para o personagem poder se abaixar sem girar o resto
	_model = Node3D.new()
	_player.add_child(_model)
	var body: Node3D = null
	var who: String = Engine.get_meta("personagem", Perfil.skin())
	var bytes := FileAccess.get_file_as_bytes("res://personagem/%s.glbin" % who)
	if not bytes.is_empty():
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_buffer(bytes, "", state) == OK:
			body = doc.generate_scene(state)
	if body == null:
		# reserva, caso o arquivo do personagem não esteja no celular
		var cap := MeshInstance3D.new()
		var cm := CapsuleMesh.new(); cm.radius = 0.3; cm.height = 1.7
		cap.mesh = cm
		cap.position.y = 0.85
		_model.add_child(cap)
		return
	body.rotation.y = PI        # o modelo vem olhando para trás
	_model.add_child(body)
	for old in body.find_children("*", "AnimationPlayer", true, false):
		old.queue_free()
	# animações do Mixamo convertidas para o esqueleto deste personagem
	_anim = AnimationPlayer.new()
	body.add_child(_anim)
	_anim.root_node = NodePath("..")
	var lib := AnimationLibrary.new()
	for n in ANIMS:
		var a: Animation = load("res://personagem/%s_%s.tres" % [who, ANIMS[n]])
		if a:
			a.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation(n, a)
	_anim.add_animation_library("", lib)
	_play("Idle")
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# machado na mão e golpe feito em código (por cima da animação)
	var axe := MeshInstance3D.new()
	axe.mesh = Corte.axe_mesh()
	axe.material_override = Corte.axe_material()
	axe.visible = false
	add_child(axe)
	_axe_node = axe
	var sks := body.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		var pose = Corte.ChopPose.new()
		pose.player = _player
		pose.axe = axe
		sks[0].add_child(pose)
		_chop_pose = pose


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
	if _arvores:
		_arvores.tick()   # quando vira o dia: sementes, brotos, crescimento
		if _cipos:
			_cipos.tick()
	_save_timer -= delta
	if _save_timer <= 0.0:
		_save_world()
	if _play_time < 15.0:
		_play_time += delta
		if _play_time >= 15.0:
			Diag.marcar("jogando")
	_grass_mat.set_shader_parameter("player_pos", _player.global_position)
	var h: float = sim.hour()
	_clock.text = "%d de %s de %d · %02d:%02d · %s%s" % [sim.day(), sim.month_name(), sim.year(), int(h), int(fmod(h, 1.0) * 60.0), sim.season_name(), " · Chovendo" if sim.raining else ""]
	_soil_timer -= delta
	if _soil_timer <= 0.0:
		_soil_timer = 2.0
		_apply_soil()
		# a informação do solo não aparece mais na tela
	_update_dig(delta)
	_seed_check -= delta
	if _seed_check <= 0.0 and _arvores:
		_seed_check = 0.25
		_seed_btn.visible = _arvores.nearest_seed(_player.position, 1.6) >= 0
	_update_chop(delta)
	_update_crouch(delta)
	_holes_t -= delta
	if _holes_t <= 0.0:
		_holes_t = 1.0
		_update_holes()
	# a grama vai sendo refeita aos poucos, acompanhando as estações
	_refresh_timer -= delta
	if _refresh_timer <= 0.0 and _grass_queue.is_empty() and not _grass_chunks.is_empty():
		_refresh_timer = 1.5
		var keys := _grass_chunks.keys()
		var key: Vector2i = keys[randi() % keys.size()]
		_grass_chunks[key].queue_free()
		_grass_chunks.erase(key)
		_build_grass_chunk(key)


# ================== SALVAMENTO ==================

func _game_date() -> String:
	if sim == null or not sim.is_ready:
		return ""
	return "%d de %s de %d" % [sim.day(), sim.month_name(), sim.year()]


## Salva o mundo (na thread da simulação) e o jogador.
func _save_world() -> void:
	_save_timer = SAVE_EVERY
	if _world_id == "" or not _ready_world:
		return
	sim.request_save()
	_save_player()
	if _arvores:
		_arvores.save(Mundos.dir(_world_id) + "/arvores.json")
	if _cipos:
		_cipos.save(Mundos.dir(_world_id) + "/cipos.json")
	if _buracos:
		_buracos.save(Mundos.dir(_world_id) + "/buracos.json")
	Mundos.touch(_world_id, _game_date())


func _save_player() -> void:
	if _world_id == "" or not _ready_world or _player == null:
		return
	var p := _player.position
	var chao := []
	for g in _chao:
		chao.append({"id": g.id, "qtd": g.qtd, "x": g.x, "z": g.z})
	var data := {"x": p.x, "z": p.z, "face": _face, "yaw": _yaw, "pitch": _pitch, "argila": _bag, "sementes": _seeds,
		"itens": _itens, "mao": _mao, "chao": chao, "tora": _carry, "ganhou_cavadeira": true}
	var f := FileAccess.open(Mundos.dir(_world_id) + "/jogador.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func _load_player() -> void:
	# todo mapa novo começa com um machado de pedra na mochila
	_itens = {"machado": 1, "cavadeira": 1}
	if _world_id == "" or not sim.loaded_from_save:
		return
	var path := Mundos.dir(_world_id) + "/jogador.json"
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return
	if d.has("itens") and d.itens is Dictionary:
		_itens = {}
		for k in d.itens:
			if Itens.ITENS.has(k) and int(d.itens[k]) > 0:
				_itens[k] = int(d.itens[k])
		# a cavadeira chegou numa atualização: quem já jogava ganha uma para testar
		if not bool(d.get("ganhou_cavadeira", false)) and not _itens.has("cavadeira"):
			_itens["cavadeira"] = 1
	if d.has("chao") and d.chao is Array:
		for g in d.chao:
			if g is Dictionary and Itens.ITENS.has(str(g.get("id", ""))):
				_add_ground(str(g.id), int(g.get("qtd", 1)), float(g.get("x", 0.0)), float(g.get("z", 0.0)))
	equip(str(d.get("mao", "")))
	var tora = d.get("tora", {})
	if tora is Dictionary and tora.has("v"):
		_pending_carry = tora      # volta com a tora no ombro (depois que as árvores carregam)
	var x := clampf(float(d.get("x", _player.position.x)), 1.0, MundoSim.W * CELL - 1.0)
	var z := clampf(float(d.get("z", _player.position.z)), 1.0, MundoSim.H * CELL - 1.0)
	_player.position = _ground_pos(Vector2(x, z))
	_face = float(d.get("face", 0.0))
	_yaw = float(d.get("yaw", 0.0))
	_pitch = float(d.get("pitch", _pitch))
	_bag = clampf(float(d.get("argila", 0.0)), 0.0, BAG_MAX)
	_seeds = maxi(0, int(d.get("sementes", 0)))
	_update_inventory()


# ================== COLETA DE ARGILA ==================

static func _kg(v: float) -> String:
	return ("%.1f" % v).replace(".", ",")


func _bag_total() -> float:
	var t := _bag + _seeds * Arvores.SEED_KG
	for id in _itens:
		t += Itens.kg(id) * int(_itens[id])
	return t


func item_qtd(id: String) -> int:
	if id == "semente":
		return _seeds
	return int(_itens.get(id, 0))


func remove_item(id: String, qtd: int) -> void:
	if id == "semente":
		_seeds = maxi(0, _seeds - qtd)
		return
	var n := int(_itens.get(id, 0)) - qtd
	if n > 0:
		_itens[id] = n
	else:
		_itens.erase(id)
		if _mao == id:
			equip("")


## Põe itens na mochila; o que não couber cai no chão do lado do jogador.
## Devolve quantos foram para o chão.
func add_item(id: String, qtd: int) -> int:
	var kg := Itens.kg(id)
	var fit := qtd
	if kg > 0.0:
		fit = clampi(int(floor((BAG_MAX - _bag_total()) / kg + 0.0001)), 0, qtd)
	if fit > 0:
		if id == "semente":
			_seeds += fit
		else:
			_itens[id] = int(_itens.get(id, 0)) + fit
	if qtd - fit > 0:
		drop_item(id, qtd - fit, false)
	return qtd - fit


## Solta itens no chão na frente do jogador (from_bag: tira da mochila).
func drop_item(id: String, qtd: int, from_bag := true) -> void:
	if from_bag:
		qtd = mini(qtd, item_qtd(id))
		if qtd <= 0:
			return
		remove_item(id, qtd)
	var fwd := Vector3(-sin(_face), 0, -cos(_face))
	var side := Vector3(cos(_face), 0, -sin(_face)) * randf_range(-0.3, 0.3)
	var pos := _player.position + fwd * 0.7 + side
	_add_ground(id, qtd, pos.x, pos.z)


func _add_ground(id: String, qtd: int, x: float, z: float) -> void:
	var node := Node3D.new()
	add_child(node)
	if id == "machado":
		var mi := MeshInstance3D.new()
		mi.mesh = Corte.axe_mesh()
		mi.material_override = Corte.axe_material()
		node.add_child(mi)
		mi.rotation = Vector3(PI * 0.5, randf() * TAU, 0)
		mi.position.y = 0.04
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.12, 0.18)
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.4, 0.33)
		mi.material_override = mat
		mi.position.y = 0.06
		node.add_child(mi)
	node.position = Vector3(x, height_at(x, z), z)
	_chao.append({"id": id, "qtd": qtd, "x": x, "z": z, "node": node})


func _nearest_ground(r: float) -> int:
	var best := -1
	var bd := r
	for i in _chao.size():
		var g: Dictionary = _chao[i]
		var d := Vector2(float(g.x) - _player.position.x, float(g.z) - _player.position.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func _pick_ground() -> void:
	var i := _nearest_ground(1.8)
	if i < 0:
		return
	var g: Dictionary = _chao[i]
	var kg := Itens.kg(str(g.id))
	var fit := int(g.qtd)
	if kg > 0.0:
		fit = mini(fit, int(floor((BAG_MAX - _bag_total()) / kg + 0.0001)))
	if fit <= 0:
		_show_toast("A mochila está cheia (%d kg)." % int(BAG_MAX))
		return
	if str(g.id) == "semente":
		_seeds += fit
	else:
		_itens[g.id] = int(_itens.get(g.id, 0)) + fit
	g.qtd = int(g.qtd) - fit
	if int(g.qtd) <= 0:
		g.node.queue_free()
		_chao.remove_at(i)
	_show_toast("+%d %s" % [fit, Itens.nome(str(g.id))])
	_act_check = 0.0


## Equipa uma ferramenta da mochila na mão ("" guarda).
## Só uma ferramenta na mão de cada vez (equipar outra guarda a anterior).
func equip(id: String) -> void:
	_mao = id if id != "" and item_qtd(id) > 0 else ""
	if _chopping:
		_cancel_chop()
	if _chop_pose:
		_chop_pose.holding = _mao in ["machado", "cavadeira"]
		_chop_pose.tool = _mao if _mao != "" else "machado"
		if _mao == "cavadeira":
			_chop_pose.grip_low = 0.04
			_chop_pose.grip_high = 0.4
			_chop_pose.carry_grip = 0.5
		else:
			_chop_pose.grip_low = Corte.ChopPose.GRIP_LOW
			_chop_pose.grip_high = Corte.ChopPose.GRIP_HIGH
			_chop_pose.carry_grip = Corte.ChopPose.GRIP_HIGH
	if _axe_node is MeshInstance3D:
		(_axe_node as MeshInstance3D).mesh = Corte.digger_mesh() if _mao == "cavadeira" else Corte.axe_mesh()
	_act_check = 0.0


func _update_inventory() -> void:
	if _bag_total() <= 0.0:
		_inv_label.text = ""
		return
	_inv_label.text = "Mochila: argila %s kg  (%s/%d kg)" % [_kg(_bag), _kg(_bag_total()), int(BAG_MAX)]


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_t = 3.5


func _player_depth() -> float:
	var p := _player.position
	var cell := Vector2i(int(p.x / CELL), int(p.z / CELL))
	if _water_level.size() != MundoSim.W * MundoSim.H or cell.x < 0 or cell.y < 0 or cell.x >= MundoSim.W or cell.y >= MundoSim.H:
		return 0.0
	return maxf(0.0, _water_level[cell.y * MundoSim.W + cell.x] - height_at(p.x, p.z))


## Pega a semente mais perto do chão e põe na mochila.
func _pick_seed() -> void:
	if _arvores == null:
		return
	var i: int = _arvores.nearest_seed(_player.position, 1.6)
	if i < 0:
		return
	if _bag_total() + Arvores.SEED_KG > BAG_MAX:
		_show_toast("A mochila está cheia.")
		return
	_arvores.take_seed(i)
	_seeds += 1
	_show_toast("+1 semente de Cedrinho (%d na mochila)" % _seeds)
	_seed_check = 0.0


## Mochila: soltar uma semente no chão (pode brotar sozinha) ou plantar (pega mais fácil).
func put_seed_from_bag(plant: bool) -> bool:
	if _seeds <= 0 or _arvores == null:
		return false
	var fwd := Vector3(-sin(_face), 0, -cos(_face))
	var pos := _player.position + fwd * (0.6 if plant else 0.3)
	if plant and not _arvores.can_plant(pos.x, pos.z):
		_show_toast("Não dá para plantar aqui (água, pedra ou terra ruim).")
		return false
	_arvores.put_seed(pos.x, pos.z, plant)
	_seeds -= 1
	if plant:
		_show_toast("Você plantou uma semente de Cedrinho. Deve brotar em uns 100 dias.")
	return true


func _update_dig(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	if _digging:
		_dig_t += delta
		_dig_bar.value = _dig_t / _dig_need * 100.0
		if _dig_t >= _dig_need:
			_finish_dig()
		return
	_dig_check -= delta
	if _dig_check > 0.0:
		return
	_dig_check = 0.3
	var cell := Vector2i(int(_player.position.x / CELL), int(_player.position.z / CELL))
	var d: Dictionary = sim.soil_data(cell)
	var ok: bool = not d.is_empty() and d.clay >= 0.35 and _player_depth() < 0.8
	_dig_btn.visible = ok
	if ok:
		_dig_btn.text = "Pegar argila"


func _start_dig() -> void:
	if _digging:
		return
	if _bag_total() >= BAG_MAX - 0.05:
		_show_toast("A mochila está cheia (%d kg)." % int(BAG_MAX))
		return
	_dig_cell = Vector2i(int(_player.position.x / CELL), int(_player.position.z / CELL))
	_dig_info = sim.soil_data(_dig_cell)
	if _dig_info.is_empty() or _dig_info.clay < 0.35:
		return
	var wet: bool = _dig_info.moist > 0.55 or _dig_info.water > 0.02
	_dig_info["wet"] = wet
	# barro mole sai rápido; torrão seco e duro demora
	_dig_need = 1.3 if wet else 2.6
	_dig_t = 0.0
	_digging = true
	_dig_btn.visible = false
	_dig_bar.visible = true
	_dig_bar.value = 0
	_play("Idle", 0.6)
	if _model:
		_model.rotation.x = 0.45


func _cancel_dig() -> void:
	_digging = false
	_dig_bar.visible = false
	if _model:
		_model.rotation.x = 0.0


func _finish_dig() -> void:
	_cancel_dig()
	var d := _dig_info
	var wet: bool = d.wet
	var purity: float = clampf(1.0 - d.sand * 0.6, 0.3, 1.0)
	var kg: float = 2.0 * d.clay * (1.3 if wet else 0.7) * purity
	kg = minf(kg, BAG_MAX - _bag_total())
	_bag += kg
	# cada punhado gasta a argila da beira; ela volta a se formar devagar
	sim.dig(_dig_cell, kg * 0.04)
	_update_inventory()
	var state := "molhada, macia" if wet else "seca, em torrões"
	_show_toast("+%s kg de argila (%s, %d%% pura)" % [_kg(kg), state, int(purity * 100)])
	_dig_check = 0.0


# ================== CORTE DE ÁRVORE ==================



## Mostra os botões "Cortar" e "Pegar ...". Cada toque em "Cortar" é uma machadada:
## o personagem segura o machado com as duas mãos e bate de lado no tronco.
func _update_chop(delta: float) -> void:
	var pose = _chop_pose
	if _chopping:
		if _swing_on:
			var before := _chop_t / Corte.ChopPose.SWING_TIME
			_chop_t += delta
			var ph := _chop_t / Corte.ChopPose.SWING_TIME
			if before < Corte.ChopPose.HIT_AT and ph >= Corte.ChopPose.HIT_AT:
				_chop_hit()
				if not _chopping:
					return
			if ph >= 1.0:
				_swing_on = false
				_chop_idle = 0.0
				if _swing_queued:
					_swing_queued = false
					_begin_swing()
			if pose:
				pose.phase = minf(ph, 1.0)
		else:
			# parado com o machado nas duas mãos; se demorar, volta a carregar com uma mão
			_chop_idle += delta
			if _chop_idle > 2.5:
				_cancel_chop()
		return
	_act_check -= delta
	if _act_check > 0.0:
		return
	_act_check = 0.25
	var gi := _nearest_ground(1.8)
	_pick_btn.visible = gi >= 0
	if gi >= 0:
		_pick_btn.text = "Pegar %s" % Itens.nome(str(_chao[gi].id)).to_lower()
	_chop_btn.visible = false
	_update_log_btn()
	if _mao == "cavadeira" and not _digging and not _air and _carry.is_empty() and _crouch_job == "" and _player_depth() < 0.3:
		_chop_btn.visible = true
		_chop_btn.text = "Cavar"
	if _mao == "machado" and _arvores != null and not _digging and not _air and _carry.is_empty() and _crouch_job == "":
		if _arvores.nearest_standing(_player.position, 1.3) != null:
			_chop_btn.visible = true
			_chop_btn.text = "Cortar"
		elif not _arvores.log_target(_player.position, 1.6).is_empty():
			_chop_btn.visible = true
			_chop_btn.text = "Cortar tora"


# ================== PEGAR, CARREGAR E LARGAR TORA ==================

func _update_log_btn() -> void:
	if _arvores == null:
		return
	_vine_btn.visible = _cipos != null and _carry.is_empty() and _crouch_job == "" and not _chopping and not _cipos.harvest_target(_player.position, 1.6).is_empty()
	if _crouch_job != "" or _chopping or _air:
		_log_btn.visible = false
		return
	if not _carry.is_empty():
		_log_btn.visible = true
		_log_btn.text = "Largar tora"
		_plant_btn.visible = _buracos != null and _buracos.hole_near(_front(0.6), 0.9) >= 0
		return
	_plant_btn.visible = false
	var t: Dictionary = _arvores.pick_target(_player.position, 1.3)
	_log_btn.visible = not t.is_empty()
	if not t.is_empty():
		_log_btn.text = "Pegar tora"


func _log_action() -> void:
	if _crouch_job != "" or _chopping or _air or _arvores == null:
		return
	if not _carry.is_empty():
		_crouch_job = "largar"
		_crouch_t = 0.0
		return
	var t: Dictionary = _arvores.pick_target(_player.position, 1.3)
	if t.is_empty():
		return
	var kg: float = _arvores.free_log_kg(t.log)
	if _digging:
		_cancel_dig()
	_crouch_target = t
	_crouch_job = "pegar"
	_crouch_t = 0.0
	# vira para a tora
	var c: Vector3 = t.center
	_face = atan2(-(c.x - _player.position.x), -(c.z - _player.position.z))


## Arranca uma raiz aérea madura de cipó-titica (coleta limitada: a planta não morre).
func _collect_vine() -> void:
	if _cipos == null or _crouch_job != "" or not _carry.is_empty():
		return
	var pl: Dictionary = _cipos.harvest_target(_player.position, 1.6)
	if pl.is_empty():
		return
	var why: String = _cipos.harvest(pl)
	if why != "":
		_show_toast(why)
		return
	var dropped := add_item("cipo", 1)
	_show_toast("+1 cipó-titica" + (" (mochila cheia: caiu no chão)" if dropped > 0 else ""))
	_face = atan2(-(float(pl.x) - _player.position.x), -(float(pl.z) - _player.position.z))
	_crouch_job = "puxar"
	_crouch_t = 0.0


## Agacha, pega (ou larga) a tora embaixo e levanta: 1,1 s no total.
func _update_crouch(delta: float) -> void:
	if _crouch_job == "" or _chop_pose == null:
		return
	var before := _crouch_t
	_crouch_t += delta
	var T := 1.1
	var mid := 0.5
	_chop_pose.crouch = smoothstep(0.0, mid, _crouch_t) if _crouch_t < mid else 1.0 - smoothstep(mid, T, _crouch_t)
	if before < mid and _crouch_t >= mid:
		if _crouch_job == "puxar":
			pass
		elif _crouch_job == "fincar":
			_buracos.plant(int(_crouch_target.buraco), _carry, _face)
			_carry = {}
			if _carry_node:
				_carry_node.queue_free()
			_carry_node = null
			_chop_pose.log_node = null
			_show_toast("Tora fincada!")
		elif _crouch_job == "pegar":
			var fl: Dictionary = _arvores.take_log(_crouch_target)
			_hold_log(fl)
		else:
			var fwd := Vector3(-sin(_face), 0, -cos(_face))
			var r: float = _arvores.free_log_radius(_carry)
			var c := _player.position + fwd * (r + 0.55)
			_arvores.drop_log(_carry, c, _face)
			_carry = {}
			if _carry_node:
				_carry_node.queue_free()
			_carry_node = null
			_chop_pose.log_node = null
	if _crouch_t >= T:
		_crouch_job = ""
		_chop_pose.crouch = 0.0
		_act_check = 0.0


## Recorta o chão e o capim nos buracos abertos perto do jogador.
func _update_holes() -> void:
	if _buracos == null or _player == null:
		return
	var list: Array = _buracos.open_holes_near(_player.position, 32)
	var arr := []
	for v in list:
		arr.append(v)
	while arr.size() < 32:
		arr.append(Vector4(-9999, -9999, 0, 0))
	for m in [_terrain_mat, _grass_mat]:
		m.set_shader_parameter("holes", arr)
		m.set_shader_parameter("hole_n", list.size())


func _front(dist: float) -> Vector3:
	return _player.position + Vector3(-sin(_face), 0, -cos(_face)) * dist


## Finca a tora do ombro no buraco que está na frente (fica em pé, base das construções).
func _plant_log() -> void:
	if _carry.is_empty() or _crouch_job != "" or _buracos == null:
		return
	var i: int = _buracos.hole_near(_front(0.6), 0.9)
	if i < 0:
		return
	var h: Dictionary = _buracos.holes[i]
	_face = atan2(-(float(h.x) - _player.position.x), -(float(h.z) - _player.position.z))
	_crouch_target = {"buraco": i}
	_crouch_job = "fincar"
	_crouch_t = 0.0


func _hold_log(fl: Dictionary) -> void:
	_carry = fl
	_carry_kg = _arvores.free_log_kg(fl)
	_carry_node = _arvores.free_log_node(fl)
	add_child(_carry_node)
	if _chop_pose:
		_chop_pose.log_node = _carry_node
		_chop_pose.log_r = _arvores.free_log_radius(fl)


## Pulo: sobe uns 60 cm (dá para passar por cima de uma tora ou subir nela).
func _jump() -> void:
	if _air or _chopping or _digging or not _carry.is_empty() or _crouch_job != "":
		return
	_air = true
	_vy = 4.2


## Toque no botão "Cortar": uma machadada (se já está no meio de uma, guarda a próxima).
func _start_chop() -> void:
	if (_mao != "machado" and _mao != "cavadeira") or _arvores == null:
		return
	if _chopping:
		if _swing_on:
			_swing_queued = true
		else:
			_begin_swing()
		return
	if _mao == "cavadeira":
		if _digging:
			_cancel_dig()
		_chop_hole = true
		_chop_tree = null
		_chop_log = {}
		_chopping = true
		_swing_queued = false
		_play("Idle", 0.5)
		if _chop_pose:
			_chop_pose.digging = true
			_chop_pose.vertical = false
			_chop_pose.ready_pose = true
		_begin_swing()
		return
	var t = _arvores.nearest_standing(_player.position, 1.3)
	_chop_log = {}
	if t == null:
		var lg: Dictionary = _arvores.log_target(_player.position, 1.6)
		if lg.is_empty():
			return
		_chop_log = lg
	if _digging:
		_cancel_dig()
	_chop_tree = t
	_chopping = true
	if _chop_pose:
		_chop_pose.vertical = not _chop_log.is_empty()
	_swing_queued = false
	_play("Idle", 0.5)
	if _chop_pose:
		_chop_pose.ready_pose = true
	_begin_swing()


func _begin_swing() -> void:
	_swing_on = true
	_chop_t = 0.0
	_chop_idle = 0.0
	if _chop_pose:
		_chop_pose.swinging = true
		_chop_pose.phase = 0.0


## A lâmina bateu no tronco: conta a machadada, marca o corte e solta lascas.
func _chop_hit() -> void:
	if _chop_hole:
		var at := _front(0.62)
		var d: float = _buracos.dig_at(at)
		_dirt(at)
		_show_toast("Buraco com %d cm de fundura" % int(round(d * 100.0)) if d < Buracos.MAX_DEPTH else "O buraco já está bem fundo (80 cm)")
		return
	if not _chop_log.is_empty():
		var lp: Array = _chop_log.p
		var done: bool = _arvores.buck_hit(lp, float(_chop_log.h))
		_chips(_chop_log.point)
		if done:
			_show_toast("Tora cortada!")
			_cancel_chop()
		return
	var t = _chop_tree
	if t == null:
		return
	var from := Vector3(_player.position.x - float(t[0]), 0, _player.position.z - float(t[1]))
	var hits: int = _arvores.add_cut(t, from)
	var need: int = _arvores.hits_to_fell(t)
	_chips(_arvores.cut_point(t))
	if hits >= need:
		_finish_chop()


## Terra voando da cavadeira.
func _dirt(at: Vector3) -> void:
	var c := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.03, 0.04)
	c.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.33, 0.24, 0.15)
	c.material_override = mat
	c.amount = 16
	c.one_shot = true
	c.explosiveness = 0.9
	c.lifetime = 0.8
	c.direction = Vector3(0, 1, 0)
	c.spread = 40.0
	c.initial_velocity_min = 1.2
	c.initial_velocity_max = 2.4
	c.gravity = Vector3(0, -9.8, 0)
	add_child(c)
	c.global_position = Vector3(at.x, height_at(at.x, at.z) + 0.05, at.z)
	c.emitting = true
	get_tree().create_timer(1.3).timeout.connect(c.queue_free)


## Lascas de madeira voando do corte.
func _chips(at: Vector3) -> void:
	var c := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.012, 0.03)
	c.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.72, 0.5)
	c.material_override = mat
	c.amount = 14
	c.one_shot = true
	c.explosiveness = 0.95
	c.lifetime = 0.9
	c.direction = Vector3(at.x - _player.position.x, 0.6, at.z - _player.position.z).normalized() * -1.0 + Vector3(0, 1.2, 0)
	c.spread = 50.0
	c.initial_velocity_min = 1.5
	c.initial_velocity_max = 3.2
	c.gravity = Vector3(0, -9.8, 0)
	c.angular_velocity_min = -400.0
	c.angular_velocity_max = 400.0
	add_child(c)
	c.global_position = at
	c.emitting = true
	get_tree().create_timer(1.5).timeout.connect(c.queue_free)


func _cancel_chop() -> void:
	_chopping = false
	_swing_on = false
	_swing_queued = false
	_chop_tree = null
	_chop_log = {}
	_chop_hole = false
	if _chop_pose:
		_chop_pose.digging = false
		_chop_pose.vertical = false
		_chop_pose.swinging = false
		_chop_pose.ready_pose = false
	_act_check = 0.0


func _finish_chop() -> void:
	var t = _chop_tree
	_cancel_chop()
	if t == null:
		return
	var away := Vector3(float(t[0]) - _player.position.x, 0, float(t[1]) - _player.position.z)
	_arvores.fell_by_player(t, away)
	_show_toast("A árvore caiu!")


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
	# garoa escurece pouco o céu; temporal escurece bastante
	var target: float = clampf(0.45 + sim.rain_mmh / 16.0, 0.5, 1.0) if (sim.is_ready and sim.raining) else 0.0
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
	if _digging:
		if amount > 0.12:
			_cancel_dig()
		else:
			amount = 0.0
	if _chopping:
		if amount > 0.12:
			_cancel_chop()
		else:
			amount = 0.0
	if _crouch_job != "":
		amount = 0.0           # abaixado pegando ou largando a tora
	if _chop_pose:
		_chop_pose.moving = amount > 0.12
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
		var running := amount > 0.85 and _carry.is_empty()
		var sp := (RUN_SPEED if running else WALK_SPEED) * water_slow
		if not _carry.is_empty():
			sp *= lerpf(0.9, 0.4, clampf(_carry_kg / 300.0, 0.0, 1.0))   # tora pesada: anda devagar
		p += move * sp * delta
		p.x = clampf(p.x, 1.0, MundoSim.W * CELL - 1.0)
		p.z = clampf(p.z, 1.0, MundoSim.H * CELL - 1.0)
		_face = lerp_angle(_face, atan2(-move.x, -move.z), minf(1.0, delta * 10.0))
		_play("Run" if running else "Walk", water_slow)
	elif not _digging:
		_play("Idle")
	if _chopping and not _chop_log.is_empty():
		# de lado para a tora, de frente para o ponto do corte
		var axp: Vector3 = _chop_log.axis
		var al: Vector3 = _chop_log.along
		var rel := Vector3(p.x - axp.x, 0, p.z - axp.z)
		var side := rel - Vector3(al.x, 0, al.z).normalized() * rel.dot(Vector3(al.x, 0, al.z).normalized())
		if side.length() < 0.05:
			side = Vector3(al.z, 0, -al.x)
		var want_pos := axp + side.normalized() * (float(_chop_log.r) + 0.42)
		var mv := Vector2(want_pos.x - p.x, want_pos.z - p.z)
		if mv.length() > 0.04:
			var stp := minf(mv.length(), delta * 1.5)
			p.x += mv.x / mv.length() * stp
			p.z += mv.y / mv.length() * stp
		var tl := Vector2(axp.x - p.x, axp.z - p.z)
		_face = lerp_angle(_face, atan2(-tl.x, -tl.y), minf(1.0, delta * 10.0))
	elif _chopping and _chop_tree != null:
		# fica de frente para o tronco
		var to := Vector2(float(_chop_tree[0]) - p.x, float(_chop_tree[1]) - p.z)
		_face = lerp_angle(_face, atan2(-to.x, -to.y), minf(1.0, delta * 10.0))
		# chega na distância certa para o machado bater no tronco
		var want: float = _arvores.trunk_radius(_chop_tree) + 0.72
		var dist := to.length()
		if dist > 0.01 and absf(dist - want) > 0.05:
			var step := clampf(dist - want, -delta * 1.5, delta * 1.5)
			p.x += to.x / dist * step
			p.z += to.y / dist * step
	var feet := _player.position.y
	if _arvores:
		p = _arvores.push_out(p, feet)   # não atravessa troncos e toras (pulando passa por cima)
	if _buracos:
		p = _buracos.push_out(p)          # nem as toras fincadas
	# chão: o terreno ou o topo de uma tora (dá para subir pulando e andar em cima)
	var ground := height_at(p.x, p.z) - minf(depth, 0.9) * 0.5
	if _arvores:
		var sup: float = _arvores.support_y(p.x, p.z)
		if sup > ground and feet >= sup - 0.2:
			ground = sup
	if _air:
		_vy -= 13.0 * delta
		p.y = feet + _vy * delta
		if p.y <= ground:
			p.y = ground
			_air = false
			_vy = 0.0
	elif feet > ground + 0.12:
		# saiu de cima da tora: cai
		_air = true
		_vy = 0.0
		p.y = feet
	else:
		p.y = ground
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

func _open_backpack() -> void:
	if _bag_ui != null or _cal != null or _craft_ui != null or not _ready_world:
		return
	_joy_id = -1
	_joy_vec = Vector2.ZERO
	_look_id = -1
	_bag_ui = Mochila.new()
	_hud.add_child(_bag_ui)
	_bag_ui.abrir(self)
	_bag_ui.closed.connect(func(): _bag_ui = null)


func _open_craft() -> void:
	if _craft_ui != null or _bag_ui != null or _cal != null or not _ready_world:
		return
	_joy_id = -1
	_joy_vec = Vector2.ZERO
	_look_id = -1
	_craft_ui = Craft.new()
	_hud.add_child(_craft_ui)
	_craft_ui.abrir(self)
	_craft_ui.closed.connect(func(): _craft_ui = null)


func _open_calendar() -> void:
	if _cal != null or _bag_ui != null or _craft_ui != null or not _ready_world:
		return
	_joy_id = -1
	_joy_vec = Vector2.ZERO
	_look_id = -1
	_cal = Calendario.new()
	_hud.add_child(_cal)
	_cal.abrir(sim, Mundos.dir(_world_id) + "/calendario.json" if _world_id != "" else "")
	_cal.closed.connect(func(): _cal = null)


func _input(e: InputEvent) -> void:
	if _cal != null or _bag_ui != null or _craft_ui != null:
		return   # com o calendário, a mochila ou o craft aberto, o toque não anda nem gira a câmera
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if e is InputEventScreenTouch:
		if e.pressed:
			# toque em botão de ação não gira a câmera (dá para tocar "Cortar" várias vezes)
			for btn in [_dig_btn, _chop_btn, _seed_btn, _pick_btn, _jump_btn, _log_btn, _vine_btn, _plant_btn]:
				if btn and btn.visible and btn.get_global_rect().has_point(e.position):
					return
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
	var deep := PackedByteArray(); deep.resize(W * H)
	var count := 0
	for i in W * H:
		if wat[i] > DEEP:
			lvl[i] = (_ter[i] + wat[i]) * HS
			deep[i] = 1
	# estende a água das lagoas um pouco por baixo da margem, para o terreno cortar a borda
	# (filete não se estende, senão vira uma faixa larga descendo a encosta)
	var ext := lvl.duplicate()
	for y in H:
		for x in W:
			var i := y * W + x
			if lvl[i] > NONE:
				count += 1
				continue
			var best := NONE
			if x > 0 and deep[i - 1] and lvl[i - 1] > best: best = lvl[i - 1]
			if x < W - 1 and deep[i + 1] and lvl[i + 1] > best: best = lvl[i + 1]
			if y > 0 and deep[i - W] and lvl[i - W] > best: best = lvl[i - W]
			if y < H - 1 and deep[i + W] and lvl[i + W] > best: best = lvl[i + W]
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
	var cmurk := PackedFloat32Array(); cmurk.resize(cw * (H + 1))
	var has_murk := wat.size() >= W * H * 2
	for y in H + 1:
		for x in cw:
			var s := 0.0; var n := 0; var mk := 0.0
			var cells := []
			if x > 0 and y > 0: cells.append((y - 1) * W + x - 1)
			if x < W and y > 0: cells.append((y - 1) * W + x)
			if x > 0 and y < H: cells.append(y * W + x - 1)
			if x < W and y < H: cells.append(y * W + x)
			for ci in cells:
				if ext[ci] > NONE:
					s += ext[ci]; n += 1
					if has_murk: mk += wat[W * H + ci]
			if n > 0:
				cmurk[y * cw + x] = mk / n
				var lv := s / n
				# canto na borda (encosta em célula sem água): no plano a água afina até sumir
				var edge := false
				if x > 0 and y > 0 and lvl[(y - 1) * W + x - 1] <= NONE: edge = true
				if x < W and y > 0 and lvl[(y - 1) * W + x] <= NONE: edge = true
				if x > 0 and y < H and lvl[y * W + x - 1] <= NONE: edge = true
				if x < W and y < H and lvl[y * W + x] <= NONE: edge = true
				if edge:
					lv = minf(lv, _corner_h[y * cw + x])
				corner[y * cw + x] = lv
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
			var d00 := Color(cmurk[c00], 1, 1, maxf(0.0, corner[c00] - _corner_h[c00]))
			var d10 := Color(cmurk[c10], 1, 1, maxf(0.0, corner[c10] - _corner_h[c10]))
			var d01 := Color(cmurk[c01], 1, 1, maxf(0.0, corner[c01] - _corner_h[c01]))
			var d11 := Color(cmurk[c11], 1, 1, maxf(0.0, corner[c11] - _corner_h[c11]))
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
