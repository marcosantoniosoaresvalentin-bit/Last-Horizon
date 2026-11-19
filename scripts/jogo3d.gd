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
const Rede := preload("res://scripts/rede.gd")
const JogadorRemoto := preload("res://scripts/world/jogador_remoto.gd")
const Itens := preload("res://scripts/itens.gd")
const Corte := preload("res://scripts/world/corte.gd")
const Craft := preload("res://scripts/ui/craft.gd")
const Icones := preload("res://scripts/ui/icones.gd")
const Cipos := preload("res://scripts/world/cipos.gd")
const Buracos := preload("res://scripts/world/buracos.gd")
const Sons := preload("res://scripts/sons.gd")
const Galhos := preload("res://scripts/world/galhos.gd")
const Apoios := preload("res://scripts/world/apoios.gd")
const Balde := preload("res://scripts/world/balde.gd")
const GalhoGeo := preload("res://scripts/world/galho_geo.gd")
const Pedras := preload("res://scripts/world/pedras.gd")
const Lascar := preload("res://scripts/world/lascar.gd")
const Macacos := preload("res://scripts/world/macacos.gd")
const Bacabas := preload("res://scripts/world/bacabas.gd")
const Araras := preload("res://scripts/world/araras.gd")
const Minerios := preload("res://scripts/world/minerios.gd")
const Cupins := preload("res://scripts/world/cupins.gd")
const Tamanduas := preload("res://scripts/world/tamanduas.gd")
const Construcao := preload("res://scripts/world/construcao.gd")
const Buritis := preload("res://scripts/world/buritis.gd")
const Maquinas := preload("res://scripts/world/maquinas.gd")
const Projetos := preload("res://scripts/ui/projetos.gd")
const MINERAIS_ITENS := ["hematita", "magnetita", "goetita", "silex", "malaquita", "calcopirita", "lasca_silex"]
const Escavacao := preload("res://scripts/world/escavacao.gd")
const Desenhos := preload("res://scripts/ui/desenhos.gd")
const SerraCtrl := preload("res://scripts/ui/serra_ctrl.gd")
const SAW_SPEED := 2.6            # quão rápido a serra acompanha o dedo (curso inteiro ≈ 0,8 s)
const Maos := preload("res://scripts/world/maos.gd")
const Corte2 := preload("res://scripts/world/corte.gd")
## Onda na água: um anel que abre e some (passos dentro d'água).
const RIPPLE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float age = 0.0;
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment(){
	vec2 p = UV * 2.0 - 1.0;
	float a = atan(p.y, p.x);
	// borda levemente ondulada, não um círculo perfeito
	float r = length(p) * (1.0 + 0.04 * sin(a * 5.0 + age * 6.0) + 0.03 * sin(a * 9.0));
	float w = mix(0.05, 0.1, age);
	float ring = smoothstep(0.82 - w, 0.82, r) * (1.0 - smoothstep(0.82, 0.82 + w * 0.6, r));
	float ring2 = (smoothstep(0.5 - w, 0.5, r) * (1.0 - smoothstep(0.5, 0.5 + w * 0.6, r))) * 0.5;
	ALBEDO = vec3(0.78, 0.84, 0.86);
	ALPHA = (ring + ring2) * pow(1.0 - age, 1.5) * 0.28;
}
"""
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
uniform sampler2D dig_mask : filter_linear, repeat_disable;    // terra mexida pela pá (o chão normal some ali)
uniform bool dig_on = false;
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
	// borda arredondada e irregular (nada de quadradinho)
	if (dig_on && texture(dig_mask, uv).r > 0.5 + (noise(wpos.xz * 5.0) - 0.5) * 0.36) { discard; }
	vec4 a = texture(soil_a, uv);
	vec4 b = texture(soil_b, uv);
	float rock = COLOR.a;
	float clay = a.r; float sand = a.g; float moist = a.b; float grass = a.a;
	float bed = smoothstep(0.3, 0.7, b.r);    // leito de lagoa (com ou sem água)
	float surf = b.g;                          // umidade da superfície
	vec3 loam = vec3(0.34, 0.25, 0.17);
	vec3 sandc = vec3(0.80, 0.74, 0.60);
	vec3 clayc = vec3(0.56, 0.30, 0.19);       // terra avermelhada da jazida de argila
	vec3 mud = vec3(0.31, 0.27, 0.21);         // lama do fundo
	vec3 soil = mix(loam, sandc, sand * 0.8);
	float patch = smoothstep(0.15, 0.55, clay + (noise(wpos.xz * 0.45) - 0.5) * 0.35);
	soil = mix(soil, clayc, patch * (1.0 - bed));
	soil = mix(soil, mud, bed * (1.0 - sand * 0.85));   // fundo de mar e praia é areia, não lama
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
uniform vec4 flat_spot = vec4(0.0);
uniform sampler2D dig_mask : filter_linear, repeat_disable;
uniform bool dig_on = false;
uniform vec2 dig_world = vec2(640.0, 480.0);   // xyz = lugar, w = raio: capim amassado (modelando pedra)
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
	if (dig_on && textureLod(dig_mask, root.xz / dig_world, 0.0).r > 0.5) { VERTEX *= 0.0; }
	if (flat_spot.w > 0.0) {
		VERTEX.y *= mix(0.08, 1.0, smoothstep(flat_spot.w * 0.6, flat_spot.w, distance(root.xz, flat_spot.xz)));
	}
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
uniform float sea_level = -1000.0;
uniform vec3 sea_deep = vec3(0.015, 0.075, 0.10);
uniform vec3 sea_shallow = vec3(0.10, 0.28, 0.27);
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
	// fundura com sinal: A = 0..8 m de água, G = quanto o chão passa acima da água (beirada)
	depth = COLOR.a * 8.0 - COLOR.g * 0.5;
	murk = COLOR.r;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment(){
	float t = TIME;
	float e = 0.08;
	float h0 = waves(wpos.xz, t);
	vec3 nw = normalize(vec3(h0 - waves(wpos.xz + vec2(e, 0.0), t), e * 1.6, h0 - waves(wpos.xz + vec2(0.0, e), t)));
	// longe a onda some no brilho geral (senão vira chuvisco de pixels)
	float far = smoothstep(25.0, 260.0, length(wpos - CAMERA_POSITION_WORLD));
	// água rasa e pequena (poça, buraco) quase não faz onda
	float calm = max(far * 0.85, (1.0 - smoothstep(0.2, 3.0, depth)) * 0.65);
	nw = normalize(mix(nw, vec3(0.0, 1.0, 0.0), calm));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float d = clamp(depth / 1.6, 0.0, 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	// barro: enxurrada marrom; lagoa e rio ficam só um pouco sujos depois da chuva
	float m = clamp(murk, 0.0, 1.0) * (0.85 + noise(wpos.xz * 0.15 + vec2(t * 0.02, 0.0)) * 0.3);
	m *= 1.0 - smoothstep(0.03, 0.12, abs(wpos.y - sea_level)) * 0.85;   // o mar não fica barrento
	vec3 clean = mix(shallow, deep, sqrt(d));
	// água do mar (no nível do mar): verde-azulada, bem mais funda
	float salt = 1.0 - smoothstep(0.03, 0.12, abs(wpos.y - sea_level));
	clean = mix(clean, mix(sea_shallow, sea_deep, sqrt(clamp(depth / 6.0, 0.0, 1.0))), salt);
	vec3 muddy = mud * mix(1.0, 0.55, sqrt(d));
	ALBEDO = mix(clean, muddy, clamp(m, 0.0, 1.0) * 0.9) + vec3(0.05, 0.07, 0.08) * fres;
	ALPHA = clamp(mix(0.45, 0.93, sqrt(d)) + m * 0.3 + fres * 0.15, 0.0, 1.0) * smoothstep(0.0, 0.06, depth);
	// água barrenta brilha menos (o barro tira o espelho)
	ROUGHNESS = mix(0.12, 0.4, clamp(m, 0.0, 1.0));
	SPECULAR = mix(0.45, 0.2, clamp(m, 0.0, 1.0));
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
var _skel: Skeleton3D = null
var _head_bone := -1
var _eye_smooth := Vector3.ZERO
var _head_axes := []
var _body_mats: Array = []        # materiais do corpo (some perto da câmera)
var _busy_f := 0.0                # 0 andando livre, 1 abaixado fazendo algo
var _bob_t := 0.0
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
var _galhos: Node3D = null
var _apoios: Node3D = null
var _ctx_btn: Button
var _ctx_action := ""
var _work_btn: Button             # "Trabalhar" na tora apoiada nas forquilhas (ou "Modelar pedra")
var _pedras: Node3D = null
var _macacos: Node3D = null
var _bacabas: Node3D = null
var _buritis: Node3D = null
var _araras: Node3D = null
var _minerios: Node = null
var _cupins: Node3D = null
var _tamanduas: Node3D = null
var teste := false                 # modo de teste (Configurações): tudo de graça e rápido
var _constr: Node3D = null
var _maq: Node3D = null
var _proj := {}                    # pondo a planta no chão: {tipo, yaw, ghost, ok, c}
var _proj_ui: Control = null
var _proj_btns: Array = []
var _buck_sel := {}               # escolhendo onde cortar a tora caída: {info, ponta, d, L, ring}
var _buck_go_cut := {}             # o corte escolhido, para o machado começar
var _buck_btns: Array = []
var _olho := {}                   # o olho no tronco do buriti perto: {p, open}
var _bur := {}                    # o que escolheu no menu do olho: {p, acao}
var _chop_bur := {}               # derrubando um buriti
var _drag := false                # arrastando a tora pesada (sozinho)
var _drag_b := Vector3.ZERO       # a ponta que vai no chão
var _desf := {}                   # sentado na desfibradeira: {mi, fase, n, anim, node, ...}
var _desf_btns: Array = []
var _sub_btns: Array = []
var _sub_ui: Control
var _trim := {}                    # cortando a ponta que sobrou: {mi, si, t, s, tool}
var _pin := {}                     # pondo pinos: {alvos, sel, depth, t, speed, gw, gc, anim, ok}
var _pin_ui: Control = null
var _maq_op := {}                  # na serra: {mi, papel, ctrl, last, speed}
var _maq_stop: Button
var _bld := {}                     # modo construção: {yaw, tilt, roll, ghost, ok, c, b}
var _bld_btn: Button
var _post_cut := {}               # cortando a ponta da estaca: {i, t, y}
var _post_mark := {}              # escolhendo a altura do corte na estaca: {i, y, node}
var _mark_btns: Array = []
var _bld_why: Label
var _medida := {}                 # altura medida com o machado na estaca de referência: {i, y}
var _bld_t := 0.0
var _bld_btns: Array = []
var _bld_cross: Label
const Arrasto := preload("res://scripts/ui/arrasto.gd")
var _bld_pad: Control
const BLD_MODES := ["girar", "inclinar", "virar", "mover", "altura"]
var _escav: Node3D = null
var _escav_steps := 0
var _escav_timer := 0.0
var _pa_vol := 0.0                # quanta terra está na pá (m³)
var _knap := {}                   # modelando pedra no chão: ver _knap_start
var _knap_ui: Control = null
var _knap_mi: MeshInstance3D = null
var _knap_hand: Node3D = null
var _vine := {}                   # puxando cipó: {pl, spots, sel, anim, drag (y do toque), tid}
var _vine_ui: Control = null
var _vine_hand: Node3D = null
var _knap_rng := RandomNumberGenerator.new()
var _work_menu: Control = null
var _work := {}                   # trabalho escolhido: {i (tora apoiada), modo, e (ponta), stage, fix}
var _pa_full := false            # a pá está cheia de terra (precisa jogar fora)
var _pa_dirt: Node3D = null       # a terra em cima da pá
var _pa_tipo := "terra"           # o que está na pá: "terra" ou "argila"
var _balde_carga := {}            # o que tem no balde da mochila/mão: {tipo, vol (m³)}
var _balde_fill: MeshInstance3D = null
var _pour_t := -1.0               # despejando o balde (segundos)
var _split := {}                  # rachando a tora com cunhas (ver _split_begin)
const TAB_L := 0.4                # comprimento da tábua pequena (m)
const RIPAS_POR_TABUA := 4
const BOARD_HITS := 4
var _rede: Node = null            # multiplayer (ver rede.gd)
var _remotos := {}                # peer id -> JogadorRemoto
var _mp_t := 0.0
var _mp_tempo_t := 0.0
var _mp_perto := false
var _split_ui: Control = null
var _split_rng := RandomNumberGenerator.new()
const BALDE_VOL := 0.024          # cabe uns 24 litros
const BALDE_KG := 25.0            # mais que isso não dá para carregar pela alça
const PAZADA := 0.006             # uma pazada: uns 6 litros
const DENS := {"terra": 1500.0, "argila": 1800.0}
var _climb := {}                  # saindo da cova funda: {t, dur, from, to}
var _sawing := false              # serrando a rodela (vai e vem sozinho até terminar ou parar)
var _saw_t := 0.0
var _saw_half := 0
var _saw_ctrl: Control = null     # trilho para subir e descer o dedo (vai e vem da serra)
var _saw_p := 0.0                 # onde a serra está: 0 puxada, 1 empurrada
var _saw_side := 0                # último fim de curso alcançado: 1 frente, -1 trás
const SAW_CYCLE := 1.5            # segundos por ida e volta da serra (devagar)
var _rodelas: Array = []          # formato de cada rodela da mochila (raios em volta)
var _dur := {}                    # durabilidade: id da ferramenta -> [usos que faltam de cada uma]
var _walking := false             # o personagem indo sozinho até um lugar
var _walk_target := Vector3.ZERO
var _walk_t := 0.0
var _walk_next := ""
# colocar item no chão escolhendo o lugar (prévia branca transparente)
const PLACE_DIST := 1.7           # a prévia fica a essa distância na frente do personagem (m)
var _placing := ""                # item sendo colocado ("" = fora do modo)
var _ghost: MeshInstance3D = null
var _place_rot := 0.0             # giro escolhido no botão "Girar"
var _place_pos := Vector3.ZERO
var _place_yaw := 0.0
var _place_ok := true
var _place_btn: Button
var _rot_btn: Button
var _store_btn: Button
var _chop_branch := {}           # cortando um galho (da árvore caída ou do chão)
var _branch_hits := 0
var _plant_btn: Button
var _chop_hole := false           # cavando com a cavadeira
var _holes_t := 0.0
var _step_dist := 0.0
var _step_player: AudioStreamPlayer3D = null
var _ripple_mat: Shader
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
	if _rede and _rede.ativo():
		_rede.parar()
	Diag.marcar("menu")
	if _water_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_water_task)


func _ready() -> void:
	Diag.marcar("gerando mundo")
	_build_hud()
	_build_environment()
	sim = MundoSim.new()
	teste = Perfil.teste()
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

	_ctx_btn = Icones.IconButton.new()
	_ctx_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ctx_btn.offset_left = -290
	_ctx_btn.offset_top = -426
	_ctx_btn.offset_right = -160
	_ctx_btn.offset_bottom = -296
	_ctx_btn.visible = false
	_ctx_btn.pressed.connect(_ctx_press)
	_hud.add_child(_ctx_btn)

	# "Trabalhar": no meio da tela, perto da tora apoiada nas forquilhas
	_work_btn = Icones.IconButton.new()
	_work_btn.text = "Trabalhar"
	_work_btn.add_theme_font_size_override("font_size", 22)
	_work_btn.set_anchors_preset(Control.PRESET_CENTER)
	_work_btn.offset_left = -70
	_work_btn.offset_right = 70
	_work_btn.offset_top = 70
	_work_btn.offset_bottom = 210
	_work_btn.visible = false
	_work_btn.pressed.connect(func():
		if _work_btn.text == "Modelar pedra":
			_open_knap_menu()
		else:
			_open_work_menu())
	_hud.add_child(_work_btn)

	# modo de colocar: Colocar, Girar e Guardar
	var mk := func(txt: String, l: int, t: int, cb: Callable) -> Button:
		var b := Icones.IconButton.new()
		b.text = txt
		b.add_theme_font_size_override("font_size", 22)
		b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		b.offset_left = l
		b.offset_top = t
		b.offset_right = l + 130
		b.offset_bottom = t + 130
		b.visible = false
		b.pressed.connect(cb)
		_hud.add_child(b)
		return b
	_place_btn = mk.call("Colocar", -290, -146, _place_press)
	_rot_btn = mk.call("Girar", -150, -286, func(): _place_rot += PI * 0.25)
	_store_btn = mk.call("Guardar", -290, -286, stop_placing)

	# construção
	_bld_btn = mk.call("Construir", -430, -286, _bld_start)
	_bld_btns = [mk.call("Colocar", -290, -146, _bld_place), mk.call("Girar", -150, -286, func(): _bld_mode("girar")),
		mk.call("Inclinar", -290, -286, func(): _bld_mode("inclinar")), mk.call("Virar", -430, -286, func(): _bld_mode("virar")),
		mk.call("Mover", -150, -426, func(): _bld_mode("mover")), mk.call("Altura", -290, -426, func(): _bld_mode("altura")),
		mk.call("Sair", -430, -426, _bld_stop), mk.call("Mirar", -430, -146, _bld_follow)]
	_bld_pad = Arrasto.new()
	_bld_pad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_bld_pad.offset_left = 30
	_bld_pad.offset_right = 470
	_bld_pad.offset_top = -140
	_bld_pad.offset_bottom = -30
	_bld_pad.visible = false
	_bld_pad.arrastou.connect(_bld_drag)
	_hud.add_child(_bld_pad)
	_proj_btns = [mk.call("Pôr a planta", -290, -146, _proj_place), mk.call("Sair", -430, -426, _proj_stop)]
	_buck_btns = [mk.call("Cortar aqui", -290, -146, _buck_go), mk.call("Sair", -430, -426, _buck_stop)]
	_sub_btns = [mk.call("Sair", -430, -146, _bur_sair)]
	_desf_btns = [mk.call("Puxar", -290, -146, _desf_puxar), mk.call("Levantar", -430, -146, _desf_end)]
	_sub_ui = Control.new()
	_sub_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sub_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_ui.draw.connect(_draw_bur_ui)
	_hud.add_child(_sub_ui)
	_maq_stop = mk.call("Parar", -290, -146, _maq_op_stop)
	_mark_btns = [mk.call("Cortar aqui", -290, -146, _mark_cut), mk.call("Subir", -150, -286, func(): _mark_move(0.05)),
		mk.call("Descer", -290, -286, func(): _mark_move(-0.05)), mk.call("Medir", -150, -426, _mark_measure),
		mk.call("Sair", -290, -426, _mark_close)]
	_bld_why = Label.new()
	_bld_why.add_theme_font_size_override("font_size", 22)
	_bld_why.add_theme_color_override("font_color", Color(1, 0.75, 0.7))
	_bld_why.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_bld_why.add_theme_constant_override("outline_size", 6)
	_bld_why.set_anchors_preset(Control.PRESET_CENTER)
	_bld_why.offset_left = -420
	_bld_why.offset_right = 420
	_bld_why.offset_top = 30
	_bld_why.offset_bottom = 110
	_bld_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bld_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bld_why.visible = false
	_hud.add_child(_bld_why)
	_bld_cross = Label.new()
	_bld_cross.text = "+"
	_bld_cross.add_theme_font_size_override("font_size", 40)
	_bld_cross.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_bld_cross.set_anchors_preset(Control.PRESET_CENTER)
	_bld_cross.offset_left = -12
	_bld_cross.offset_top = -30
	_bld_cross.visible = false
	_hud.add_child(_bld_cross)

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
	var proj_btn := Icones.IconButton.new()
	proj_btn.show_caption = false
	proj_btn.text = "Projetos"
	proj_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	proj_btn.offset_left = -460
	proj_btn.offset_top = 6
	proj_btn.offset_right = -380
	proj_btn.offset_bottom = 72
	proj_btn.pressed.connect(_open_projetos)
	_hud.add_child(proj_btn)
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
	_cam.near = 0.04
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
	_water_mat.set_shader_parameter("sea_level", MundoSim.SEA * HS)


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
	_build_ocean()
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
	_bacabas = Bacabas.new()
	add_child(_bacabas)
	_bacabas.build(self, _arvores, int(sim.world_seed), Mundos.dir(_world_id) + "/bacabas.json" if _world_id != "" else "")
	print("bacabas: %d (%d adultas)" % [_bacabas.palms.size(), _bacabas.adult_palms().size()])
	_buritis = Buritis.new()
	add_child(_buritis)
	_buritis.build(self, _arvores, int(sim.world_seed), Mundos.dir(_world_id) + "/buritis.json" if _world_id != "" else "")
	_buritis.drop_hook = _seca_cai
	print("buritis: %d" % _buritis.count())
	_macacos = Macacos.new()
	add_child(_macacos)
	_macacos.build(self, _arvores, _cipos, _bacabas, int(sim.world_seed), Mundos.dir(_world_id) + "/macacos.json" if _world_id != "" else "")
	print("macacos: %d em %d bandos" % [_macacos.count(), _macacos.troops.size()])
	_araras = Araras.new()
	_araras._bur = _buritis
	add_child(_araras)
	_araras.build(self, _arvores, _bacabas, _cipos, int(sim.world_seed), Mundos.dir(_world_id) + "/araras.json" if _world_id != "" else "")
	print("araras: %d, %d ninhos" % [_araras.count(), _araras.nests.size()])
	_arvores.fell_hook = _cipos.attach_falling
	_arvores.fall_done_hook = _cipos._rebuild
	_buracos = Buracos.new()
	add_child(_buracos)
	_galhos = Galhos.new()
	add_child(_galhos)
	_galhos.build(self, _arvores, int(sim.world_seed), Mundos.dir(_world_id) + "/galhos.json" if _world_id != "" else "")
	_apoios = Apoios.new()
	add_child(_apoios)
	_apoios.build(self, _arvores, Mundos.dir(_world_id) + "/apoios.json" if _world_id != "" else "")
	_pedras = Pedras.new()
	add_child(_pedras)
	_pedras.build(self, int(sim.world_seed), Mundos.dir(_world_id) + "/pedras.json" if _world_id != "" else "")
	_buracos.changed_hook = _update_holes
	_buracos.build(self, _arvores, Mundos.dir(_world_id) + "/buracos.json" if _world_id != "" else "")
	_escav = Escavacao.new()
	add_child(_escav)
	_escav.build(self, _buracos._soil_mat, Mundos.dir(_world_id) + "/escavacao.json" if _world_id != "" else "")
	_minerios = Minerios.new()
	add_child(_minerios)
	_minerios.build(self, int(sim.world_seed), Mundos.dir(_world_id) + "/minerios.json" if _world_id != "" else "")
	_escav.tint_fn = _minerios.tint_at
	_convert_bandas()
	_convert_tabuas()
	_constr = Construcao.new()
	add_child(_constr)
	_constr.build(self, _arvores, _buracos, Mundos.dir(_world_id) + "/construcao.json" if _world_id != "" else "")
	_maq = Maquinas.new()
	add_child(_maq)
	_maq.build(self, _arvores, Mundos.dir(_world_id) + "/maquinas.json" if _world_id != "" else "")
	_cupins = Cupins.new()
	add_child(_cupins)
	_cupins.build(self, _arvores, int(sim.world_seed), Mundos.dir(_world_id) + "/cupins.json" if _world_id != "" else "")
	_tamanduas = Tamanduas.new()
	add_child(_tamanduas)
	_tamanduas.build(self, _arvores, _cupins, int(sim.world_seed), Mundos.dir(_world_id) + "/tamanduas.json" if _world_id != "" else "")
	print("tamanduás: %d" % _tamanduas.count())
	_escav.water_mat = _water_mat
	_escav.sea_m = MundoSim.SEA * HS
	_escav_steps = sim.steps
	for m in [_terrain_mat, _grass_mat]:
		m.set_shader_parameter("dig_mask", _escav.mask_tex)
		m.set_shader_parameter("dig_on", true)
	_grass_mat.set_shader_parameter("dig_world", Vector2(MundoSim.W * CELL, MundoSim.H * CELL))
	if not _pending_carry.is_empty():
		_hold_log(_pending_carry)
		_pending_carry = {}
	_loading.visible = false
	_loading_bg.visible = false
	# hora e dia não aparecem na tela (o calendário vai mostrar a data)
	_ready_world = true
	Diag.marcar("entrando no mundo")
	_mp_start()


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


## Altura exata do chão do jeito que ele está desenhado (triângulos a cada 2,5 m),
## para objetos no chão (buracos, toras fincadas) ficarem encostados, sem flutuar.
func surface_at(x: float, z: float) -> float:
	var step := CELL / SUB
	var gx := floori(x / step)
	var gz := floori(z / step)
	var fx := x / step - gx
	var fz := z / step - gz
	var h00 := height_at(gx * step, gz * step)
	var h10 := height_at((gx + 1) * step, gz * step)
	var h01 := height_at(gx * step, (gz + 1) * step)
	var h11 := height_at((gx + 1) * step, (gz + 1) * step)
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


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
		# primeira pessoa: o que do próprio corpo chega muito perto da câmera (a cabeça, o
		# pescoço, o ombro) some só para a câmera; as mãos (mais longe) e a sombra ficam
		var m3: MeshInstance3D = mi
		if m3.mesh:
			for si in m3.mesh.get_surface_count():
				var mat := m3.get_active_material(si)
				if mat is BaseMaterial3D:
					var nm: BaseMaterial3D = mat.duplicate()
					nm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
					nm.distance_fade_min_distance = 0.27
					nm.distance_fade_max_distance = 0.34
					m3.set_surface_override_material(si, nm)
					_body_mats.append(nm)
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
		pose.ground_fn = surface_at
		sks[0].add_child(pose)
		_chop_pose = pose
		pose.fp = true
		_skel = sks[0]
		_head_bone = _skel.find_bone("Head")


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
	if _drag:
		_drag_update()
	_update_grass()
	if _arvores and _mp_client():
		# convidado: a natureza (crescer, cupins, frutos, bichos comendo) roda no dono e
		# chega pela rede; aqui só os bichos andando
		if _araras:
			_araras.update(delta)
		if _macacos:
			_macacos.update(delta)
		if _tamanduas:
			_tamanduas.update(delta)
	elif _arvores:
		_arvores.tick()   # quando vira o dia: sementes, brotos, crescimento
		if _cipos:
			_cipos.tick()
		if _bacabas:
			_bacabas.tick()
		if _buritis:
			_buritis.tick()
		if _minerios:
			_minerios.tick()
		if _cupins:
			_cupins.tick()
		if _tamanduas:
			_tamanduas.tick()
			_tamanduas.update(delta)
		if _araras:
			_araras.tick()
			_araras.update(delta)
		if _macacos:
			_macacos.tick()
			_macacos.update(delta)
		if _galhos:
			_galhos.tick()
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
	_update_pour(delta)
	_mp_tick(delta)
	_sync_tick(delta)
	_coop_tick(delta)
	if _maq and _ready_world:
		var auth: bool = _rede == null or not _rede.ativo() or _rede.modo == "dono"
		var alone: bool = _rede == null or not _rede.ativo() or _rede.jogadores.size() < 2
		_maq.update(delta, auth, teste and alone)
	_update_split(delta)
	_tick_hole_water(delta)
	_seed_check -= delta
	if _seed_check <= 0.0 and _arvores:
		_seed_check = 0.25
		_seed_btn.visible = _arvores.nearest_seed(_player.position, 1.6) >= 0
	_update_chop(delta)
	_update_crouch(delta)
	_update_placing()
	_update_knap(delta)
	_update_vine(delta)
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
	if _macacos:
		_macacos.save(Mundos.dir(_world_id) + "/macacos.json")
	if _bacabas:
		_bacabas.save(Mundos.dir(_world_id) + "/bacabas.json")
	if _buritis:
		_buritis.save(Mundos.dir(_world_id) + "/buritis.json")
	if _araras:
		_araras.save(Mundos.dir(_world_id) + "/araras.json")
	if _minerios:
		_minerios.save(Mundos.dir(_world_id) + "/minerios.json")
	if _cupins:
		_cupins.save(Mundos.dir(_world_id) + "/cupins.json")
	if _tamanduas:
		_tamanduas.save(Mundos.dir(_world_id) + "/tamanduas.json")
	if _constr:
		_constr.save(Mundos.dir(_world_id) + "/construcao.json")
	if _maq:
		_maq.save(Mundos.dir(_world_id) + "/maquinas.json")
	if _buracos:
		_buracos.save(Mundos.dir(_world_id) + "/buracos.json")
	if _galhos:
		_galhos.save(Mundos.dir(_world_id) + "/galhos.json")
	if _apoios:
		_apoios.save(Mundos.dir(_world_id) + "/apoios.json")
	if _escav:
		_escav.save(Mundos.dir(_world_id) + "/escavacao.json")
	if _pedras:
		_pedras.save(Mundos.dir(_world_id) + "/pedras.json")
	Mundos.touch(_world_id, _game_date())


func _save_player() -> void:
	if _world_id == "" or not _ready_world or _player == null:
		return
	var p := _player.position
	var chao := []
	for g in _chao:
		chao.append({"id": g.id, "qtd": g.qtd, "x": g.x, "z": g.z, "r": g.get("r", 0.0), "dur": g.get("dur", [])})
	var data := {"x": p.x, "z": p.z, "face": _face, "yaw": _yaw, "pitch": _pitch, "argila": _bag, "sementes": _seeds,
		"itens": _itens, "mao": _mao, "chao": chao, "tora": _carry, "ganhou_cavadeira": true, "ganhou_serra": true, "ganhou_pa": true, "ganhou_balde": true, "ganhou_cunhas": true, "ganhou_cunhas2": true, "pa_cheia": _pa_full, "pa_tipo": _pa_tipo, "dur": _dur, "rodelas": _rodelas, "balde_carga": _balde_carga}
	var f := FileAccess.open(Mundos.dir(_world_id) + "/jogador.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func _load_player() -> void:
	# todo mapa novo começa com um machado de pedra na mochila
	_itens = {"machado": 1, "cavadeira": 1, "serra": 1, "pa": 1, "balde": 1}
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
		# a serra de pedra também chegou numa atualização: uma para testar
		if not bool(d.get("ganhou_pa", false)) and not _itens.has("pa"):
			_itens["pa"] = 1        # a pá chegou numa atualização: uma para testar
		if not bool(d.get("ganhou_serra", false)) and not _itens.has("serra"):
			_itens["serra"] = 1
		if not bool(d.get("ganhou_cunhas2", false)):
			_itens["cunha"] = int(_itens.get("cunha", 0)) + 3     # mais 3 cunhas para testar
		if not bool(d.get("ganhou_cunhas", false)):
			_itens["cunha"] = int(_itens.get("cunha", 0)) + 3     # para testar o rachar a tora
			_itens["marreta"] = maxi(1, int(_itens.get("marreta", 0)))
		if not bool(d.get("ganhou_balde", false)) and not _itens.has("balde"):
			_itens["balde"] = 1     # um balde para testar (encher de terra ou argila com a pá)
	if d.get("rodelas") is Array:
		_rodelas = d.rodelas
	if d.has("dur") and d.dur is Dictionary:
		for k in d.dur:
			if d.dur[k] is Array:
				_dur[k] = (d.dur[k] as Array).map(func(v): return int(v))
	if d.has("chao") and d.chao is Array:
		for g in d.chao:
			if g is Dictionary and Itens.ITENS.has(str(g.get("id", ""))):
				_add_ground(str(g.id), int(g.get("qtd", 1)), float(g.get("x", 0.0)), float(g.get("z", 0.0)), float(g.get("r", 0.0)), g.get("dur", []))
	_pa_full = bool(d.get("pa_cheia", false))
	_pa_tipo = str(d.get("pa_tipo", "terra"))
	var bc = d.get("balde_carga", {})
	_balde_carga = bc if bc is Dictionary and bc.has("vol") else {}
	equip(str(d.get("mao", "")))
	var tora = d.get("tora", {})
	if tora is Dictionary and tora.has("v"):
		_pending_carry = tora      # volta com a tora no ombro (depois que as árvores carregam)
	var x := clampf(float(d.get("x", _player.position.x)), 1.0, MundoSim.W * CELL - 1.0)
	var z := clampf(float(d.get("z", _player.position.z)), 1.0, MundoSim.H * CELL - 1.0)
	var ci := clampi(int(z / CELL), 0, MundoSim.H - 1) * MundoSim.W + clampi(int(x / CELL), 0, MundoSim.W - 1)
	if sim.ter[ci] < MundoSim.SEA + 0.3:
		# o mundo virou ilha e aqui agora é mar: volta para a terra firme
		x = (float(sim.spawn.x) + 0.5) * CELL
		z = (float(sim.spawn.y) + 0.5) * CELL
	_player.position = _ground_pos(Vector2(x, z))
	_face = float(d.get("face", 0.0))
	_yaw = float(d.get("yaw", 0.0))
	_pitch = clampf(float(d.get("pitch", _pitch)), -0.4, 0.6)
	_bag = 0.0      # a argila agora vai no balde (com a pá): a da mochila foi tirada
	_seeds = maxi(0, int(d.get("sementes", 0)))
	_update_inventory()


# ================== COLETA DE ARGILA ==================

static func _kg(v: float) -> String:
	return ("%.1f" % v).replace(".", ",")


func _bag_total() -> float:
	var t := _bag + _seeds * Arvores.SEED_KG
	for id in _itens:
		if id == "rodela":
			continue
		t += Itens.kg(id) * int(_itens[id])
	for pf in _rodelas_fix():
		t += Balde.rodela_kg(pf, Apoios.SLICE)
	return t       # (o que vai dentro do balde é levado na mão, pela alça)


## Largura da rodela (o maior diâmetro, m).
static func _rodela_diam(pf: Array) -> float:
	var d := 0.0
	var n := pf.size()
	for i in n / 2:
		d = maxf(d, float(pf[i]) + float(pf[i + n / 2]))
	return d


## Formatos das rodelas da mochila (uma por rodela; as que vieram sem formato ganham uma redonda).
func _rodelas_fix() -> Array:
	var q := int(_itens.get("rodela", 0))
	while _rodelas.size() < q:
		_rodelas.append(_round_profile(0.16))
	while _rodelas.size() > q:
		_rodelas.pop_back()
	return _rodelas


static func _round_profile(r: float) -> Array:
	var out := []
	for k in 24:
		out.append(r)
	return out


## Põe uma rodela (com o formato dela) na mochila; se não couber, cai no chão.
func add_rodela(pf: Array) -> bool:
	_rodelas_fix()
	if _bag_total() + Balde.rodela_kg(pf, Apoios.SLICE) > BAG_MAX + 0.0001:
		var fwd := Vector3(-sin(_face), 0, -cos(_face))
		var pos := _player.position + fwd * 0.7
		_add_ground("rodela", 1, pos.x, pos.z, 0.0, pf)
		return false
	_itens["rodela"] = int(_itens.get("rodela", 0)) + 1
	_rodelas.append(pf)
	return true


## Solta no chão uma rodela desse formato.
func drop_rodela(pf: Array) -> void:
	_rodelas_fix()
	var key := str(pf)
	for i in _rodelas.size():
		if str(_rodelas[i]) == key:
			_rodelas.remove_at(i)
			remove_item("rodela", 1, false)
			var fwd := Vector3(-sin(_face), 0, -cos(_face))
			var pos := _player.position + fwd * 0.8
			_add_ground("rodela", 1, pos.x, pos.z, 0.0, pf)
			return


func item_qtd(id: String) -> int:
	if id == "semente":
		return _seeds
	return int(_itens.get(id, 0))


func remove_item(id: String, qtd: int, fix_rodelas := true) -> void:
	if id == "semente":
		_seeds = maxi(0, _seeds - qtd)
		return
	if id == "rodela" and fix_rodelas:
		_rodelas_fix()
		for k in mini(qtd, _rodelas.size()):
			_rodelas.pop_back()
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
	if id == "rodela":
		var lost := 0
		for k in qtd:
			if not add_rodela(_round_profile(0.16)):
				lost += 1
		return lost
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
	var dv := []
	if id == "rodela" and from_bag:
		for k in mini(qtd, item_qtd("rodela")):
			drop_rodela(_rodelas_fix()[_rodelas.size() - 1])
		return
	if from_bag:
		qtd = mini(qtd, item_qtd(id))
		if qtd <= 0:
			return
		var l := _dur_fix(id)
		if not l.is_empty():
			dv = l.slice(l.size() - qtd)       # a ferramenta largada leva o desgaste junto
		remove_item(id, qtd)
	var fwd := Vector3(-sin(_face), 0, -cos(_face))
	var side := Vector3(cos(_face), 0, -sin(_face)) * randf_range(-0.3, 0.3)
	var pos := _player.position + fwd * 0.7 + side
	if id == "pedra" and _pedras:
		# pedra largada vira pedra do chão (dá para modelar ela depois)
		for k in qtd:
			var q := pos + Vector3(randf_range(-0.25, 0.25), 0, randf_range(-0.25, 0.25))
			_pedras.add(q.x, q.z, randf() * TAU, 0.15, randi())
		_pedras._rebuild_all()
		return
	_add_ground(id, qtd, pos.x, pos.z, 0.0, dv)


func _add_ground(id: String, qtd: int, x: float, z: float, r := 0.0, dur := []) -> void:
	var node := Node3D.new()
	add_child(node)
	if id == "rodela":
		if r <= 0.0:
			r = 0.16
		if dur.size() != 24:
			dur = _round_profile(r)        # rodela: o "dur" leva o formato dela
		var mi := MeshInstance3D.new()
		mi.mesh = Balde.rodela_profile_mesh(dur, Apoios.SLICE)
		mi.material_override = Balde.material()
		mi.position.y = Apoios.SLICE * 0.5
		node.add_child(mi)
	elif id in Lascar.KINDS:
		var mi := MeshInstance3D.new()
		var sz := r if r > 0.0 else 0.17
		if dur.size() == 2:
			# a pedra que acabou de ser modelada: do jeitinho que ficou (mesmo formato e cor)
			var o := Lascar.rock(int(dur[0]))
			mi.mesh = Lascar.mesh(Lascar.fit_target(o, id), o, int(dur[0]))
			mi.material_override = Lascar.material()
		else:
			mi.mesh = Corte2.worked_stone_mesh(id)       # a mesma pedra que vai na ferramenta
			mi.material_override = Lascar.material() if id == "lamina_serra" else Corte2.axe_material()
			sz *= 1.2
		mi.scale = Vector3(sz, sz, sz)
		mi.rotation.y = float(dur[1]) if dur.size() == 2 else randf() * TAU
		mi.position.y = -mi.mesh.get_aabb().position.y * sz
		node.add_child(mi)
	elif id in MINERAIS_ITENS:
		var mi := MeshInstance3D.new()
		mi.mesh = Lascar.cobble_mesh(absi(hash(Vector2(x, z))) % 1000, 0.07 if id != "lasca_silex" else 0.035)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Minerios.COR.get(id, Minerios.COR.silex) if id != "lasca_silex" else Color(0.4, 0.41, 0.44)
		mat.roughness = 0.35 if id in ["calcopirita", "magnetita", "silex", "lasca_silex"] else 0.8
		mat.metallic = 0.6 if id in ["calcopirita", "magnetita"] else 0.0
		mi.material_override = mat
		mi.position.y = 0.03
		node.add_child(mi)
	elif id == "cipo":
		var mi := MeshInstance3D.new()
		if r > 0.3:
			mi.mesh = Cipos.strand_mesh(r, absi(hash(Vector2(x, z))) % 100)     # o fio inteiro, comprido
			mi.rotation.y = float(dur[0]) if dur.size() > 0 else randf() * TAU
		else:
			mi.mesh = Cipos.coil_mesh()
			mi.rotation.y = randf() * TAU
		mi.material_override = Balde.material()
		node.add_child(mi)
	elif id == "balde":
		var mi := MeshInstance3D.new()
		mi.mesh = Balde.mesh()
		mi.material_override = Balde.material()
		node.add_child(mi)
		if dur.size() == 2:
			var fm := MeshInstance3D.new()
			fm.name = "carga"
			node.add_child(fm)
			_update_balde_fill(fm, {"tipo": str(dur[0]), "vol": float(dur[1])})
	elif id == "tabua" or id == "ripa":
		var mi := MeshInstance3D.new()
		mi.mesh = _board_mesh(id == "ripa", int(dur[0]) if dur.size() > 0 and id == "tabua" else 0)
		mi.rotation.y = randf() * TAU
		node.add_child(mi)
	elif id == "talo_buriti" and _buritis and dur.size() >= 6:
		# o talo deitado (o desenho sai do pé dele, guardado em relação ao item)
		var mi := MeshInstance3D.new()
		var v := int(dur[0]) % Buritis.CROWN_VARIANTS
		var li := int(dur[1])
		mi.mesh = _buritis.leaf_mesh(v, li, 1)
		mi.material_override = _buritis._leaf_mat
		var sc := float(dur[3])
		mi.transform = Transform3D(_buritis.leaf_lying_basis(v, li, float(dur[2])).scaled(Vector3(sc, sc, sc)), Vector3(float(dur[4]), 0.05, float(dur[5])))
		node.add_child(mi)
	elif id == "folha_buriti" and _buritis and dur.size() >= 3:
		# a folha cortada deitada no chão
		var mi := MeshInstance3D.new()
		var v := int(dur[0]) % Buritis.CROWN_VARIANTS
		var li := int(dur[1])
		mi.mesh = _buritis.leaf_mesh(v, li)
		mi.material_override = _buritis._leaf_mat
		var sc := float(dur[3]) if dur.size() >= 4 else 1.0
		mi.transform = Transform3D(_buritis.leaf_lying_basis(v, li, float(dur[2])).scaled(Vector3(sc, sc, sc)), Vector3(0, 0.05, 0))
		node.add_child(mi)
	elif id == "banda":
		var mi := MeshInstance3D.new()
		var L := float(dur[0]) if dur.size() >= 3 else 1.5
		mi.mesh = _banda_mesh(L, float(dur[1]) if dur.size() >= 3 else 0.12, float(dur[2]) if dur.size() >= 3 else 0.1)
		mi.rotation.y = float(dur[3]) if dur.size() >= 4 else 0.0
		node.add_child(mi)
	elif id in ["machado", "cavadeira", "serra", "marreta"]:
		var mi := MeshInstance3D.new()
		mi.mesh = Corte.axe_mesh() if id == "machado" else (Corte.digger_mesh() if id == "cavadeira" else (Corte.saw_mesh() if id == "serra" else Corte.marreta_mesh()))
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
	_chao.append({"id": id, "qtd": qtd, "x": x, "z": z, "node": node, "r": r, "dur": dur})
	if id == "rodela":
		_chao[_chao.size() - 1]["perfil"] = dur


func _nearest_ground(r: float) -> int:
	var best := -1
	var bd := r
	for i in _chao.size():
		var g: Dictionary = _chao[i]
		if str(g.id) == "banda":
			continue          # metade de tora: pesada demais para a mochila
		var d := Vector2(float(g.x) - _player.position.x, float(g.z) - _player.position.z).length()
		if d < bd:
			bd = d
			best = i
	return best


## Pegar o item do chão: o personagem se abaixa e pega.
func _pick_ground() -> void:
	if _crouch_job != "" or _chopping or not _carry.is_empty():
		return
	var i := _nearest_ground(1.8)
	if i < 0:
		return
	var g: Dictionary = _chao[i]
	_face_to(Vector3(float(g.x), 0, float(g.z)))
	_crouch_target = {"chao": i}
	_crouch_job = "chao"
	_crouch_t = 0.0
	_pick_btn.visible = false


func _pick_ground_now(i: int) -> void:
	if i < 0 or i >= _chao.size():
		return
	var g: Dictionary = _chao[i]
	if str(g.id) == "rodela":
		var pf: Array = g.get("perfil", _round_profile(float(g.get("r", 0.16))))
		if _bag_total() + Balde.rodela_kg(pf, Apoios.SLICE) > BAG_MAX + 0.0001:
			_show_toast("A mochila está cheia (%d kg)." % int(BAG_MAX))
			return
		add_rodela(pf)
		g.node.queue_free()
		_chao.remove_at(i)
		_show_toast("+1 rodela (Ø %d cm)" % int(round(_rodela_diam(pf) * 100.0)))
		_act_check = 0.0
		return
	if str(g.id) == "balde":
		var c := _carga_of(g)
		var ckg := float(c.get("vol", 0.0)) * float(DENS.get(c.get("tipo", "terra"), 1500.0))
		if not c.is_empty() and not _balde_carga.is_empty() and item_qtd("balde") > 0:
			_show_toast("Você já está com um balde cheio. Esvazie ou largue ele antes.")
			return
		# o balde vai direto para a mão (levado pela alça, não na mochila)
		_balde_carga = c
		_itens["balde"] = int(_itens.get("balde", 0)) + 1
		g.qtd = int(g.qtd) - 1
		if int(g.qtd) <= 0:
			g.node.queue_free()
			_chao.remove_at(i)
		equip("balde")
		_update_inventory()
		_show_toast("Balde na mão" + ("" if c.is_empty() else " com %s kg de %s" % [_kg(ckg), c.tipo]))
		_act_check = 0.0
		return
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
		var mx := Itens.dur_max(str(g.id))
		if mx > 0:
			var l := _dur_fix(str(g.id)).duplicate()
			var dl: Array = g.get("dur", [])
			for k in fit:
				l.append(int(dl[k]) if k < dl.size() else mx)
			_dur[str(g.id)] = l
			g.dur = dl.slice(mini(fit, dl.size()))
		_itens[g.id] = int(_itens.get(g.id, 0)) + fit
	g.qtd = int(g.qtd) - fit
	if int(g.qtd) <= 0:
		g.node.queue_free()
		_chao.remove_at(i)
	_show_toast("+%d %s" % [fit, Itens.nome(str(g.id))])
	_act_check = 0.0


# ================== DURABILIDADE DAS FERRAMENTAS ==================

## Lista de usos que faltam de cada unidade da ferramenta (a primeira é a da mão).
func _dur_fix(id: String) -> Array:
	var mx := Itens.dur_max(id)
	if mx <= 0:
		return []
	var l: Array = _dur.get(id, [])
	var q := item_qtd(id)
	while l.size() < q:
		l.append(mx)
	while l.size() > q:
		l.pop_back()
	_dur[id] = l
	return l


## Quanto ainda aguenta (0 a 1) a ferramenta da mão.
func tool_dur(id: String) -> float:
	var l := _dur_fix(id)
	if l.is_empty():
		return 1.0
	return clampf(float(l[0]) / Itens.dur_max(id), 0.0, 1.0)


## Gasta a ferramenta (n usos). Quando chega a zero ela quebra (some da mochila).
func wear(id: String, n := 1) -> bool:
	if teste:
		return false             # modo de teste: ferramenta não gasta
	var l := _dur_fix(id)
	if l.is_empty():
		return false
	var mx := Itens.dur_max(id)
	var before := int(l[0])
	l[0] = before - n
	if before > int(mx * 0.15) and int(l[0]) <= int(mx * 0.15) and int(l[0]) > 0:
		_show_toast("%s está gasto: logo vai quebrar." % Itens.nome(id))
	if int(l[0]) > 0:
		return false
	l.pop_front()
	_dur[id] = l
	var left := item_qtd(id) - 1
	if left > 0:
		_itens[id] = left
	else:
		_itens.erase(id)
	Sons.play_at(self, "estalo", _player.position + Vector3(0, 1, 0), -10.0, 1.6)
	_show_toast("%s quebrou!" % Itens.nome(id))
	if _mao == id and left <= 0:
		equip("")
	return true


## Equipa uma ferramenta da mochila na mão ("" guarda).
## Só uma ferramenta na mão de cada vez (equipar outra guarda a anterior).
func equip(id: String) -> void:
	_mao = id if id != "" and item_qtd(id) > 0 else ""
	if _chopping:
		_cancel_chop()
	if _sawing:
		_stop_saw()
	if _chop_pose:
		_chop_pose.holding = _mao in ["machado", "cavadeira", "serra", "pedra", "pa", "balde", "marreta", "faca"]
		_chop_pose.tool = _mao if _mao != "" else "machado"
		if _mao == "cavadeira" or _mao == "pa":
			_chop_pose.grip_low = 0.04
			_chop_pose.grip_high = 0.4
			_chop_pose.carry_grip = 0.22
		elif _mao == "serra":
			_chop_pose.carry_grip = Corte.SAW_LEN * 0.5
		elif _mao == "pedra":
			_chop_pose.carry_grip = 0.0          # a pedra fica dentro da mão fechada
		elif _mao == "marreta":
			_chop_pose.carry_grip = 0.08     # segura perto da ponta do cabo: a cabeça fica longe dos olhos
		elif _mao == "faca":
			_chop_pose.grip_low = 0.03
			_chop_pose.grip_high = 0.09
			_chop_pose.carry_grip = 0.06
		else:
			_chop_pose.grip_low = Corte.ChopPose.GRIP_LOW
			_chop_pose.grip_high = Corte.ChopPose.GRIP_HIGH
			_chop_pose.carry_grip = Corte.ChopPose.GRIP_HIGH
	if _axe_node is MeshInstance3D:
		var mi := _axe_node as MeshInstance3D
		if _mao == "cavadeira":
			mi.mesh = Corte.digger_mesh()
		elif _mao == "pa":
			mi.mesh = Corte.pa_mesh()
		elif _mao == "serra":
			mi.mesh = Corte.saw_mesh()
		elif _mao == "pedra":
			mi.mesh = Lascar.cobble_mesh(77, 0.085)    # pedra de bater, na palma da mão
		elif _mao == "balde":
			mi.mesh = Balde.mesh()                     # pendurado pela alça
		elif _mao == "marreta":
			mi.mesh = Corte.marreta_mesh()
		elif _mao == "faca":
			mi.mesh = Corte.faca_mesh()
		else:
			mi.mesh = Corte.axe_mesh()
		if _mao == "balde":
			mi.material_override = Balde.material()
		elif _mao == "pedra":
			mi.material_override = _hand_stone_mat()
		else:
			mi.material_override = Corte.axe_material()
		if _balde_fill == null:
			_balde_fill = MeshInstance3D.new()
			mi.add_child(_balde_fill)
		_balde_fill.visible = _mao == "balde"
		_update_balde_fill(_balde_fill, _balde_carga)
		if _pa_dirt == null:
			var dm := MeshInstance3D.new()
			dm.mesh = Corte.pa_dirt_mesh()
			dm.material_override = Corte.axe_material()
			mi.add_child(dm)
			_pa_dirt = dm
		_pa_dirt.visible = _mao == "pa" and _pa_full
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
	var hd := hole_water_depth(p.x, p.z)
	if _water_level.size() != MundoSim.W * MundoSim.H or cell.x < 0 or cell.y < 0 or cell.x >= MundoSim.W or cell.y >= MundoSim.H:
		return hd
	return maxf(hd, _water_level[cell.y * MundoSim.W + cell.x] - height_at(p.x, p.z))


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
	# argila agora só com a pá (ver _pa_hit): com a mão não sai mais
	var ok := false
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
	if _sawing:
		_saw_update(delta)
		return
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
	if not _split.is_empty():
		return          # rachando a tora: os botões normais somem
	_post_cut_tick(delta)
	if not _proj.is_empty():
		_proj_tick()
		return
	if not _buck_sel.is_empty():
		_buck_tick()
		return
	if not _maq_op.is_empty():
		_maq_op_tick(delta)
		return
	if not _desf.is_empty():
		_desf_tick(delta)
		return
	_bur_tick()
	if not _pin.is_empty():
		_pin_tick(delta)
		return
	if not _trim.is_empty():
		_trim_tick(delta)
		return
	if not _post_mark.is_empty():
		_mark_tick()
		return
	if not _bld.is_empty():
		_bld_t -= delta
		if _bld_t <= 0.0:
			_bld_t = 0.08          # procura o lugar umas 12 vezes por segundo
			_bld_update()
		return
	_act_check -= delta
	if _act_check > 0.0:
		return
	_act_check = 0.25
	var gi := _nearest_ground(1.8)
	_pick_btn.visible = gi >= 0
	if gi >= 0:
		_pick_btn.text = "Pegar %s" % Itens.nome(str(_chao[gi].id)).to_lower().split(" de ")[0]
	_chop_btn.visible = false
	_update_log_btn()
	if _mao == "cavadeira" and not _digging and not _air and _carry.is_empty() and _crouch_job == "" and _player_depth() < 0.3:
		_chop_btn.visible = true
		_chop_btn.text = "Cavar"
	if _mao == "pa" and not _air and _carry.is_empty() and _crouch_job == "" and _climb.is_empty() and _player_depth() < 0.3:
		_chop_btn.visible = true
		if not _pa_full:
			_chop_btn.text = "Cavar"
		elif _bucket_ahead() >= 0:
			_chop_btn.text = "Pôr no balde"
		else:
			_chop_btn.text = "Jogar " + ("argila" if _pa_tipo == "argila" else "terra")
	if _mao == "balde" and not _air and _carry.is_empty() and _crouch_job == "":
		_chop_btn.visible = true
		_chop_btn.text = "Pôr no chão"
	if not _work.is_empty() and str(_work.get("stage", "")) == "pronto":
		var sp: Vector3 = _apoios.slice_point(int(_work.i), int(_work.e)) if int(_work.i) < _apoios.rested.size() else Vector3(1e9, 0, 1e9)
		if Vector2(sp.x - _player.position.x, sp.z - _player.position.z).length() > 3.0:
			_work = {}      # foi embora: sai do modo de cortar rodela
		elif _mao == "serra" and _crouch_job == "" and not _air:
			_chop_btn.visible = true
			_chop_btn.text = "Serrar rodela"
			return
	if _mao == "machado" and not _digging and not _air and _carry.is_empty() and _crouch_job == "" and _board_ahead() >= 0:
		_chop_btn.visible = true
		_chop_btn.text = "Rachar tábua"
	elif _mao == "machado" and _arvores != null and not _digging and not _air and _carry.is_empty() and _crouch_job == "":
		if _bur_fell_ready():
			_chop_btn.visible = true
			_chop_btn.text = "Derrubar"
		elif _arvores.nearest_standing(_player.position, 1.3) != null:
			_chop_btn.visible = true
			_chop_btn.text = "Cortar"
		elif not _branch_target().is_empty():
			_chop_btn.visible = true
			_chop_btn.text = "Cortar galho"
		elif not _arvores.log_piece_near(_player.position, 1.6).is_empty() or _arvores.free_log_near(_player.position, 1.4) >= 0:
			_chop_btn.visible = true
			_chop_btn.text = "Cortar tora"


# ================== PEGAR, CARREGAR E LARGAR TORA ==================

## Botão de ação do lugar: pegar galho, apoiar a tora nas forquilhas, pegar a tora
## de cima delas ou recolher uma forquilha.
func _update_ctx_btn() -> void:
	_ctx_action = ""
	if _mao == "balde" and not _balde_carga.is_empty() and _crouch_job == "" and not _air and _pour_t < 0.0:
		_ctx_action = "despejar"
		_ctx_btn.text = "Despejar no balde" if _bucket_ahead() >= 0 else "Despejar"
	elif _cupins and _crouch_job == "" and not _chopping and not _air and _carry.is_empty() and _cupins.nearest_timbo(_player.position, 1.4) >= 0:
		_ctx_action = "timbo"
		_ctx_btn.text = "Colher timbó"
	elif _cupins and _crouch_job == "" and not _chopping and not _air and _carry.is_empty() and _cupins.nearest_andiroba(_player.position, 1.3) >= 0:
		_ctx_action = "andiroba"
		_ctx_btn.text = "Pegar sementes de andiroba"
	elif _cupins and _crouch_job == "" and not _chopping and not _air and _carry.is_empty() and item_qtd("oleo_andiroba") > 0 and _oil_target().size() > 0:
		_ctx_action = "oleo"
		_ctx_btn.text = "Passar óleo de andiroba"
	elif _cupins and _crouch_job == "" and not _chopping and not _air and _carry.is_empty() and item_qtd("veneno_timbo") > 0 and _poison_target().size() > 0:
		_ctx_action = "veneno"
		var pt := _poison_target()
		_ctx_btn.text = "Envenenar madeira" + (" (com cupim)" if _cupins.dmg_of(pt) > 0.02 else "")
	elif _mao == "machado" and _buracos and _carry.is_empty() and _crouch_job == "" and not _chopping and not _air and not _walking and _post_cut.is_empty() and _post_mark.is_empty() and _buracos.post_near(_player.position, 1.3) >= 0:
		var pi2: int = _buracos.post_near(_player.position, 1.3)
		var top2: float = _buracos.post_top(_buracos.posts[pi2])
		if not _medida.is_empty() and pi2 != int(_medida.i) and top2 > float(_medida.y) + 0.02:
			_ctx_btn.text = "Cortar estaca (-%d cm)" % roundi((top2 - float(_medida.y)) * 100.0)
		else:
			_ctx_btn.text = "Cortar estaca"
		_ctx_action = "estaca"
	elif _buritis and _carry.is_empty() and _crouch_job == "" and not _chopping and not _air and _buritis.seca_near(_player.position, 1.5) >= 0:
		_ctx_action = "folha_seca"
		_ctx_btn.text = "Pegar folha seca"
	elif _carry.is_empty() and _crouch_job == "" and not _chopping and not _air and _trim.is_empty() and item_qtd("marreta") > 0 and not _pin_targets().is_empty():
		_ctx_action = "pinos"
		_ctx_btn.text = "Furar e pinos (%d)" % _pin_targets().size()
	elif _maq and _crouch_job == "" and not _chopping and not _air and _trim.is_empty() and _maq_ctx():
		pass
	elif _constr and _carry.is_empty() and _crouch_job == "" and not _chopping and not _air and not _aimed_piece().is_empty():
		_ctx_action = "peca"
		_ctx_btn.text = "Pegar peça"
	elif _crouch_job == "" and not _chopping and not _air and _galhos != null and _apoios != null:
		if not _carry.is_empty():
			if not _apoios.pair_for(_player.position, _arvores.free_log_length(_carry)).is_empty():
				_ctx_action = "apoiar"
				_ctx_btn.text = "Apoiar tora"
		elif _galhos.nearest(_player.position, 1.3, false) >= 0:
			_ctx_action = "galho"
			_ctx_btn.text = "Pegar galho"
		elif _pedras and _pedras.nearest(_player.position, 1.1, true) >= 0:
			_ctx_action = "pedra"
			_ctx_btn.text = "Pegar pedra"
		elif _apoios.nearest_rested(_player.position, 1.6) >= 0:
			_ctx_action = "tora_apoiada"
			_ctx_btn.text = "Pegar tora"
		elif _apoios.nearest_fork(_player.position, 1.2) >= 0:
			_ctx_action = "forquilha"
			_ctx_btn.text = "Pegar forquilha"
	_ctx_btn.visible = _ctx_action != ""


func _ctx_press() -> void:
	if _ctx_action == "" or _crouch_job != "":
		return
	match _ctx_action:
		"timbo":
			var ti: int = _cupins.nearest_timbo(_player.position, 1.4)
			if ti >= 0:
				_cupins.harvest_timbo(ti)
				var n := randi_range(2, 3)
				var left := add_item("raiz_timbo", n)
				_show_toast("+%d raiz de timbó%s. 3 raízes fazem o veneno (craft)." % [n - left, "" if left == 0 else " (mochila cheia)"])
				_update_inventory()
				_act_check = 0.0
			return
		"estaca":
			var ci: int = _buracos.post_near(_player.position, 1.3)
			if ci >= 0:
				_mark_open(ci)
			return
		"pinos":
			_pin_start()
			return
		"folha_seca":
			var si: int = _buritis.seca_near(_player.position, 1.5)
			if si >= 0:
				if _bag_total() + Itens.kg("folha_buriti_seca") > BAG_MAX:
					_show_toast("A mochila está cheia.")
				else:
					_buritis.take_seca(si)
					add_item("folha_buriti_seca", 1)
					_update_inventory()
					_show_toast("+1 folha seca de buriti")
				_act_check = 0.0
			return
		"planta_peca", "planta_lamina", "sobra", "pedalar", "empurrar", "tora_serra", "saida_pegar":
			_maq_ctx_press(_ctx_action)
			return
		"peca":
			var pc := _aimed_piece()
			if not pc.is_empty():
				if _constr.carrying_others(pc):
					_show_toast("Tem outra peça apoiada em cima dessa. Tire ela antes.")
				elif not _can_solo(pc.log) and _arvores.free_log_kg(pc.log) > DRAG_KG:
					_show_toast("Pesada demais: %d kg (nem arrastando: até %d kg)." % [roundi(_arvores.free_log_kg(pc.log)), int(DRAG_KG)])
				else:
					var npin := 0
					for pn in pc.get("pinos", []):
						if bool(pn[1]):
							npin += 1
					_hold_log(_constr.remove_piece(pc))
					if npin > 0:
						_show_toast("Arrancou a peça: %d pino%s quebrou (não dá para usar de novo)." % [npin, "" if npin == 1 else "s"])
				_act_check = 0.0
			return
		"andiroba":
			var ai: int = _cupins.nearest_andiroba(_player.position, 1.3)
			if ai >= 0:
				var n: int = _cupins.take_seeds(ai)
				var left := add_item("semente_andiroba", n)
				if left > 0:
					_cupins.andirobas[ai].sem = left
					_cupins._rebuild()
				_show_toast("+%d semente de andiroba%s. 6 sementes fazem o óleo (craft)." % [n - left, "" if left == 0 else " (mochila cheia)"])
				_update_inventory()
				_act_check = 0.0
			return
		"oleo":
			var ot := _oil_target()
			if not ot.is_empty():
				var had2: float = _cupins.dmg_of(ot)
				_cupins.treat(ot, "oleo")
				remove_item("oleo_andiroba", 1)
				_update_inventory()
				_show_toast(("O cheiro amargo espantou os cupins. " if had2 > 0.02 else "") + "A madeira está protegida contra cupins por uns 2 anos.")
				_act_check = 0.0
			return
		"veneno":
			var pt := _poison_target()
			if not pt.is_empty():
				var had: float = _cupins.dmg_of(pt)
				_cupins.treat(pt)
				remove_item("veneno_timbo", 1)
				_update_inventory()
				_show_toast(("Os cupins dessa madeira morreram. " if had > 0.02 else "") + "O veneno de timbó se desfaz em uns 45 dias. Para proteger por anos, passe óleo de andiroba.")
				_act_check = 0.0
			return
		"despejar":
			_start_pour()
			return
		"pedra":
			var i: int = _pedras.nearest(_player.position, 1.1, true)
			if i < 0:
				return
			_face_to(_pedras.point_of(i))
			_crouch_target = {"pedra": i}
			_crouch_job = "pedra"
		"galho":
			var i: int = _galhos.nearest(_player.position, 1.3, false)
			if i < 0:
				return
			_face_to(_galhos.point_of(i))
			_crouch_target = {"galho": i}
			_crouch_job = "galho"
		"forquilha":
			var i: int = _apoios.nearest_fork(_player.position, 1.2)
			if i < 0:
				return
			_crouch_target = {"forquilha": i}
			_crouch_job = "forquilha_pegar"
		"apoiar":
			var pr: Array = _apoios.pair_for(_player.position, _arvores.free_log_length(_carry))
			if pr.is_empty():
				return
			_crouch_target = {"par": pr}
			_crouch_job = "apoiar"
		"tora_apoiada":
			var i: int = _apoios.nearest_rested(_player.position, 1.6)
			if i < 0:
				return
			var kg3: float = _arvores.free_log_kg(_apoios.rested[i].log)
			var rl: Dictionary = _apoios.rested[i].log
			if not _can_solo(rl) and _can_coop(rl) and _coop_possible():
				_coop_click({"a": "pegar", "k": "r:" + _log_key(_apoios.rested[i].log)}, _apoios.rested[i].log)
				return
			if not _can_solo(rl) and kg3 > DRAG_KG:
				_show_toast("Pesada demais: %d kg (nem arrastando: até %d kg)." % [roundi(kg3), int(DRAG_KG)])
				return
			_crouch_target = {"apoiada": i}
			_crouch_job = "tora_apoiada"
	_crouch_t = 0.0
	_act_check = 0.0


func _face_to(at: Vector3) -> void:
	_face = atan2(-(at.x - _player.position.x), -(at.z - _player.position.z))


## Mochila: usar a forquilha (o personagem põe ela no chão, na frente).
func use_fork() -> bool:
	if item_qtd("forquilha") <= 0 or not _carry.is_empty() or _crouch_job != "":
		return false
	_crouch_target = {}
	_crouch_job = "forquilha_por"
	_crouch_t = 0.0
	return true


func _update_log_btn() -> void:
	if _arvores == null:
		return
	_update_ctx_btn()
	_work_btn.visible = false
	if _carry.is_empty() and _crouch_job == "" and not _chopping and not _walking and _work.is_empty() and _work_menu == null and _knap.is_empty():
		if _mao == "pedra" and _pedras and _pedras.nearest(_player.position, 1.3, true) >= 0:
			_work_btn.visible = true
			_work_btn.text = "Modelar pedra"
		elif _apoios != null and _apoios.nearest_rested(_player.position, 1.6) >= 0:
			_work_btn.visible = true
			_work_btn.text = "Trabalhar"
	_vine_btn.visible = _cipos != null and _carry.is_empty() and _crouch_job == "" and not _chopping and _vine.is_empty() and _knap.is_empty() and not _cipos.harvest_target(_player.position, 1.6).is_empty()
	if _crouch_job != "" or _chopping or _air:
		_log_btn.visible = false
		_bld_btn.visible = false
		return
	(_log_btn as Icones.IconButton).kind = ""
	if not _coop.is_empty():
		# carregando junto: o botão Cooperativo com o ícone de onde vai pôr
		_bld_btn.visible = false
		_plant_btn.visible = false
		var pl: Dictionary = _coop_place()
		_log_btn.visible = true
		_log_btn.text = "Cooperativo"
		(_log_btn as Icones.IconButton).kind = str(pl.icone)
		_log_btn.queue_redraw()
		return
	_bld_btn.visible = not _carry.is_empty()
	if not _carry.is_empty():
		_log_btn.visible = true
		_log_btn.text = "Largar tora"
		_plant_btn.visible = _buracos != null and _buracos.hole_near(_front(0.6), 0.9) >= 0
		return
	_plant_btn.visible = false
	var t: Dictionary = _arvores.pick_target(_player.position, 1.3)
	_log_btn.visible = not t.is_empty()
	if not t.is_empty():
		var kg2: float = _arvores.free_log_kg(t.log)
		if not _can_solo(t.log) and _can_coop(t.log) and _coop_possible():
			_log_btn.text = "Cooperativo"
			(_log_btn as Icones.IconButton).kind = "pegar_tora"
		else:
			_log_btn.text = ("Pegar tora (%d kg)" if _can_solo(t.log) else ("Arrastar tora (%d kg)" if kg2 <= DRAG_KG else "Pesada: %d kg")) % roundi(kg2)
		_log_btn.queue_redraw()


func _log_action() -> void:
	if _crouch_job != "" or _chopping or _air or _arvores == null:
		return
	if not _coop.is_empty():
		var pl: Dictionary = _coop_place()
		_coop_click({"a": str(pl.a), "k": "carga"}, {})
		return
	if not _carry.is_empty():
		_crouch_job = "largar"
		_crouch_t = 0.0
		return
	var t: Dictionary = _arvores.pick_target(_player.position, 1.3)
	if t.is_empty():
		return
	var kg: float = _arvores.free_log_kg(t.log)
	if not _can_solo(t.log):
		if _can_coop(t.log) and _coop_possible() and t.kind == "solta":
			_coop_click({"a": "pegar", "k": _log_key(t.log)}, t.log)
			return
		if kg > DRAG_KG:
			_show_toast("Pesada demais: %d kg (nem arrastando: até %d kg). Corte em pedaços menores com o machado." % [roundi(kg), int(DRAG_KG)])
			return
		# sozinho: arrasta (segue para pegar)
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
	if _cipos == null or _crouch_job != "" or not _carry.is_empty() or not _vine.is_empty():
		return
	var pl: Dictionary = _cipos.harvest_target(_player.position, 1.6)
	if pl.is_empty():
		return
	_vine_start(pl)


# ================== PUXAR CIPÓ (com as mãos) ==================

func _vine_start(pl: Dictionary) -> void:
	_face_to(Vector3(float(pl.x), 0, float(pl.z)))
	var away := Vector3(_player.position.x - float(pl.x), 0, _player.position.z - float(pl.z))
	_vine = {"pl": pl, "spots": _cipos.pull_spots(pl), "sel": -1, "anim": -1.0, "drag": -1.0, "tid": -2,
		"orbit": atan2(away.z, away.x), "orbit_to": atan2(away.z, away.x), "dx": -1.0}
	# a mão é a do próprio personagem: câmera nos olhos dele (a cabeça some)
	if _chop_pose:
		_chop_pose.hide_head = true
		_chop_pose.reach_on = true
		_chop_pose.reach_grip = false
	_play("Idle", 0.5)
	_vine_camera()
	_vine_ui = Control.new()
	_vine_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vine_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_vine_ui)
	var info := PanelContainer.new()
	info.offset_left = 16
	info.offset_top = 16
	info.offset_right = 400
	info.offset_bottom = 110
	info.add_theme_stylebox_override("panel", Mochila._box(Color(0.05, 0.05, 0.04, 0.82), Color(1, 1, 1, 0.18), 2, 8))
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var il := Label.new()
	il.text = "COLETAR CIPÓ\nToque no cipó e arraste o dedo para BAIXO. Arraste para o lado para dar a volta na árvore."
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	il.add_theme_font_size_override("font_size", 15)
	info.add_child(il)
	_vine_ui.add_child(info)
	var mk := Control.new()
	mk.name = "mk"
	mk.set_anchors_preset(Control.PRESET_FULL_RECT)
	mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mk.draw.connect(func(): _draw_vine_marks(mk))
	_vine_ui.add_child(mk)
	var out := Icones.IconButton.new()
	out.text = "Sair"
	out.add_theme_font_size_override("font_size", 20)
	out.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	out.offset_left = 30
	out.offset_top = -160
	out.offset_right = 160
	out.offset_bottom = -30
	out.pressed.connect(_vine_end)
	_vine_ui.add_child(out)


func _vine_end() -> void:
	if _vine_ui:
		_vine_ui.queue_free()
	_vine_ui = null
	if _vine_hand:
		_vine_hand.queue_free()
	_vine_hand = null
	_vine = {}
	if _chop_pose:
		_chop_pose.hide_head = false
		_chop_pose.reach_on = false
	_act_check = 0.0


## O personagem fica de frente para o tronco (dá a volta nele) e a câmera fica nos
## olhos dele, olhando para os cipós.
func _vine_camera() -> void:
	var pl: Dictionary = _vine.pl
	var c := Vector3(float(pl.x), 0, float(pl.z))
	var o := float(_vine.orbit)
	var away := Vector3(cos(o), 0, sin(o))
	var gy := height_at(c.x, c.z)
	# distância do tronco: um pouco mais que onde ficam os cipós (para o braço alcançar)
	var rr := 0.25
	for sp in _vine.spots:
		var w: Vector3 = sp.pos
		rr = maxf(rr, Vector2(w.x - c.x, w.z - c.z).length())
	var pp := c + away * (rr + 0.36)
	_player.position = Vector3(pp.x, height_at(pp.x, pp.z), pp.z)
	_face = atan2(away.x, away.z)
	_player.rotation.y = _face
	var eye := _player.position + Vector3(0, 1.64, 0) - away * 0.1
	_cam.global_position = eye
	_cam.look_at(Vector3(c.x, gy + 1.0, c.z))


## O cipó está do lado da árvore que a câmera vê?
func _vine_visible(i: int) -> bool:
	var pl: Dictionary = _vine.pl
	var w: Vector3 = _vine.spots[i].pos
	var d := Vector2(w.x - float(pl.x), w.z - float(pl.z))
	var o := float(_vine.orbit)
	if d.length() < 0.05:
		return true
	return d.normalized().dot(Vector2(cos(o), sin(o))) > -0.15


func _vine_spot_screen(i: int) -> Vector2:
	var w: Vector3 = _vine.spots[i].pos
	if _cam.is_position_behind(w) or not _vine_visible(i):
		return Vector2(-9999, -9999)
	return _cam.unproject_position(w)


func _draw_vine_marks(mk: Control) -> void:
	if _vine.is_empty() or float(_vine.anim) >= 0.0:
		return
	var font := ThemeDB.fallback_font
	for i in _vine.spots.size():
		var p := _vine_spot_screen(i)
		var sel: bool = int(_vine.sel) == i
		var r := 15.0 + (3.0 * sin(Time.get_ticks_msec() / 160.0) if sel else 0.0)
		var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
		if sel:
			mk.draw_circle(p, r * 1.6, Color(1.0, 0.75, 0.2, 0.25))
			mk.draw_colored_polygon(pts, Color(1.0, 0.78, 0.2, 0.9))
		mk.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.95) if not sel else Color(0.3, 0.18, 0.02), 3.0, true)
	if int(_vine.sel) >= 0:
		var p := _vine_spot_screen(int(_vine.sel))
		var txt := "Arraste para baixo"
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var lb := Rect2(p + Vector2(-tw * 0.5 - 8, -60), Vector2(tw + 16, 28))
		mk.draw_rect(lb, Color(0.05, 0.05, 0.04, 0.85))
		mk.draw_rect(lb, Color(1.0, 0.78, 0.2, 0.9), false, 2.0)
		mk.draw_string(font, lb.position + Vector2(8, 20), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.95, 0.8))
		# setinha para baixo
		var ax := p.x + tw * 0.5 + 30
		mk.draw_line(Vector2(ax, p.y - 40), Vector2(ax, p.y + 30), Color(1, 0.85, 0.3, 0.9), 4.0, true)
		mk.draw_colored_polygon(PackedVector2Array([Vector2(ax - 10, p.y + 22), Vector2(ax + 10, p.y + 22), Vector2(ax, p.y + 38)]), Color(1, 0.85, 0.3, 0.9))


func _vine_input(e: InputEvent) -> void:
	if float(_vine.anim) >= 0.0:
		return
	var pos := Vector2.INF
	var pressed := false
	var released := false
	var tid := -2
	if e is InputEventScreenTouch:
		pos = e.position
		tid = e.index
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
		tid = -1
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventScreenDrag:
		pos = e.position
		tid = e.index
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		pos = e.position
		tid = -1
	if pos == Vector2.INF:
		return
	if pressed:
		_vine.dx = pos.x
		# tocou num cipó? seleciona e já começa a contar o arrasto dali
		var best := -1
		var bd := 75.0
		for i in _vine.spots.size():
			var d := pos.distance_to(_vine_spot_screen(i))
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			_vine.sel = best
		_vine.drag = pos.y if int(_vine.sel) >= 0 else -1.0
		_vine.tid = tid
		return
	if released:
		_vine.drag = -1.0
		_vine.dx = -1.0
		return
	# arrastando para o lado (sem estar puxando um cipó): dá a volta na árvore
	if float(_vine.dx) >= 0.0 and float(_vine.drag) < 0.0:
		var o := float(_vine.orbit) + (pos.x - float(_vine.dx)) * 0.006
		_vine.orbit = o
		_vine.orbit_to = o
		_vine.dx = pos.x
		return
	if float(_vine.dx) >= 0.0 and absf(pos.x - float(_vine.dx)) > 60.0 and float(_vine.drag) >= 0.0 and absf(pos.y - float(_vine.drag)) < 40.0:
		_vine.drag = -1.0        # foi para o lado: vira giro
		return
	# arrastando para baixo com um cipó escolhido: puxa
	if int(_vine.sel) >= 0 and float(_vine.drag) >= 0.0 and tid == int(_vine.tid):
		if pos.y - float(_vine.drag) > 110.0:
			_vine.drag = -1.0
			_vine.anim = 0.0
			Sons.play_at(self, "passo", _vine.spots[int(_vine.sel)].pos, -4.0, 0.7)


## O braço do personagem: parado, a mão fica na frente da barriga; puxando, ela vai
## até o cipó, fecha e puxa para baixo.
func _place_vine_hand(a: float) -> void:
	if _chop_pose == null:
		return
	var fwd := Vector3(-sin(_face), 0, -cos(_face))
	var right := Vector3(cos(_face), 0, -sin(_face))
	var idle := _player.position + Vector3.UP * 1.22 + fwd * 0.36 + right * 0.2
	var p := idle
	var grip := false
	if a >= 0.0 and int(_vine.sel) >= 0 and int(_vine.sel) < _vine.spots.size():
		var sp: Vector3 = _vine.spots[int(_vine.sel)].pos
		var reach := sp - fwd * 0.04
		if a < 0.35:
			p = idle.lerp(reach, smoothstep(0.0, 1.0, a / 0.35))
		elif a < 0.75:
			grip = true
			p = reach + Vector3.DOWN * 0.45 * smoothstep(0.0, 1.0, (a - 0.35) / 0.4) - fwd * 0.1 * smoothstep(0.0, 1.0, (a - 0.35) / 0.4)
		else:
			p = (reach + Vector3.DOWN * 0.45 - fwd * 0.1).lerp(idle, smoothstep(0.0, 1.0, (a - 0.75) / 0.25))
	_chop_pose.reach_target = p
	_chop_pose.reach_grip = grip


func _update_vine(delta: float) -> void:
	if _vine.is_empty():
		return
	for b in [_dig_btn, _chop_btn, _seed_btn, _pick_btn, _log_btn, _vine_btn, _plant_btn, _ctx_btn, _work_btn, _jump_btn]:
		if b:
			b.visible = false
	var a := float(_vine.anim)
	if a >= 0.0:
		var before := a
		a += delta / 1.1
		if before < 0.72 and a >= 0.72:
			_vine_pull_now()
			if _vine.is_empty():
				return
		_vine.anim = -1.0 if a >= 1.0 else a
	else:
		# nenhum cipó à vista: a câmera dá a volta sozinha até o mais perto
		var any := false
		for i in _vine.spots.size():
			if _vine_visible(i):
				any = true
				break
		if not any and not _vine.spots.is_empty():
			var w: Vector3 = _vine.spots[0].pos
			var pl: Dictionary = _vine.pl
			_vine.orbit_to = atan2(w.z - float(pl.z), w.x - float(pl.x))
		_vine.orbit = lerp_angle(float(_vine.orbit), float(_vine.orbit_to), minf(1.0, delta * 3.0))
	_place_vine_hand(a if a < 1.0 else -1.0)
	var mk := _vine_ui.find_child("mk", true, false) as Control
	if mk:
		mk.queue_redraw()


## O fio inteiro de cipó solta lá de cima e tomba no chão (puxado de baixo pela mão),
## ficando comprido deitado no chão, do lado do jogador.
func _drop_vine_coil(at: Vector3, top: Vector3, k: int) -> void:
	var L := clampf(top.y - height_at(at.x, at.z), 0.8, 9.0)
	var toward := Vector3(_player.position.x - at.x, 0, _player.position.z - at.z)
	if toward.length() < 0.05:
		toward = Vector3(1, 0, 0)
	toward = toward.normalized().rotated(Vector3.UP, (k - 0.5) * 0.35 if k > 0 else 0.0)
	var foot := Vector3(at.x, height_at(at.x, at.z), at.z)
	var yaw := atan2(-toward.z, toward.x)          # o fio deitado vai do pé da árvore para fora
	var seed_ := absi(hash(Vector2(foot.x + k, foot.z))) % 100
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.global_position = foot
	var mi := MeshInstance3D.new()
	mi.mesh = Cipos.strand_mesh(L, seed_)
	mi.material_override = Balde.material()
	mi.position = Vector3(L * 0.5, 0, 0)            # a ponta de baixo fica no pivô
	pivot.add_child(mi)
	# começa em pé (pendurado até onde estava preso) e tomba para o chão
	var up_b := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, -PI * 0.5 + 0.05)
	var down_b := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, -atan2(height_at(foot.x + toward.x * L, foot.z + toward.z * L) - foot.y, L))
	pivot.basis = up_b
	var fall := clampf(0.5 + L * 0.08, 0.6, 1.3)
	var tw := pivot.create_tween()
	tw.tween_method(func(t: float) -> void:
		pivot.basis = Basis(Quaternion(up_b).slerp(Quaternion(down_b), t * t)), 0.0, 1.0, fall)
	var mid := foot + toward * L * 0.5
	tw.tween_callback(func():
		pivot.queue_free()
		_add_ground("cipo", 1, mid.x, mid.z, L, [yaw])
		Sons.play_at(self, "baque", mid, -18.0, 1.6)
		Sons.play_at(self, "passo", mid, -10.0, 0.6))


## O cipó solta: cai no chão (dá para ver ele caindo) e fica lá para pegar.
func _vine_pull_now() -> void:
	var sp: Dictionary = _vine.spots[int(_vine.sel)]
	var pl: Dictionary = _vine.pl
	var at: Vector3 = sp.pos
	if str(sp.kind) == "raiz":
		_cipos.pull_root(pl, int(sp.i))
	else:
		_cipos.pull_stem(pl)
	Sons.play_at(self, "estalo", at, -16.0, 1.9)
	var tops := [sp.top]
	if str(sp.kind) != "raiz":
		# arrancou o pé: as raízes que ainda estavam nele vêm junto
		for q in _vine.spots:
			if str(q.kind) == "raiz":
				tops.append(q.top)
	for k in tops.size():
		_drop_vine_coil(at, tops[k], k)
	_vine.sel = -1
	_vine.spots = _cipos.pull_spots(pl) if _cipos.plants.has(pl) else []
	if _vine.spots.is_empty():
		var tm := get_tree().create_timer(1.0)
		tm.timeout.connect(func():
			if not _vine.is_empty():
				_vine_end())


## Agacha, pega (ou larga) a tora embaixo e levanta: 1,1 s no total.
func _update_crouch(delta: float) -> void:
	if _crouch_job == "" or _chop_pose == null:
		return
	var before := _crouch_t
	_crouch_t += delta
	var T := 1.1
	var mid := 0.5
	var amp := 0.35 if _crouch_job in ["apoiar", "tora_apoiada"] else 1.0   # na altura da cintura: abaixa pouco
	_chop_pose.crouch = amp * (smoothstep(0.0, mid, _crouch_t) if _crouch_t < mid else 1.0 - smoothstep(mid, T, _crouch_t))
	if before < mid and _crouch_t >= mid:
		if _crouch_job == "puxar":
			pass
		elif _crouch_job == "galho":
			_galhos.take(int(_crouch_target.galho))
			var dropped := add_item("galho", 1)
			_show_toast("+1 galho" + (" (mochila cheia: caiu no chão)" if dropped > 0 else ""))
		elif _crouch_job == "forquilha_pegar":
			_apoios.take_fork(int(_crouch_target.forquilha))
			add_item("forquilha", 1)
			_show_toast("Forquilha de volta na mochila")
		elif _crouch_job == "pedra":
			var pi := int(_crouch_target.pedra)
			if pi < _pedras.items.size():
				_pedras.take(pi)
				var dropped := add_item("pedra", 1)
				_show_toast("+1 pedra" + (" (mochila cheia: caiu no chão)" if dropped > 0 else ""))
		elif _crouch_job == "colocar":
			_place_now(_crouch_target)
		elif _crouch_job == "forquilha_por":
			remove_item("forquilha", 1)
			_apoios.place(_front(0.9), _face + PI * 0.5)
			Sons.play_at(self, "baque", _front(0.9), -6.0)
		elif _crouch_job == "apoiar":
			var pr: Array = _crouch_target.par
			_apoios.rest(_carry, int(pr[0]), int(pr[1]))
			Sons.play_at(self, "baque", _player.position)
			_carry = {}
			if _carry_node:
				_carry_node.queue_free()
			_carry_node = null
			_chop_pose.log_node = null
			_show_toast("Tora apoiada nas forquilhas")
		elif _crouch_job == "tora_apoiada":
			_work = {}
			_hold_log(_apoios.take_rested(int(_crouch_target.apoiada)))
		elif _crouch_job == "mover_forquilha":
			if not _work.is_empty() and _work.has("fix") and int(_work.i) < _apoios.rested.size():
				var fx: Dictionary = _work.fix
				_apoios.move_fork(int(_work.i), int(fx.fork), fx.to)
				Sons.play_at(self, "baque", fx.to + Vector3(0, height_at(fx.to.x, fx.to.z), 0), -8.0)
		elif _crouch_job == "chao":
			_pick_ground_now(int(_crouch_target.chao))
		elif _crouch_job == "fincar":
			_buracos.plant(int(_crouch_target.buraco), _carry, _face)
			Sons.play_at(self, "baque", _player.position)
			_carry = {}
			if _carry_node:
				_carry_node.queue_free()
			_carry_node = null
			_chop_pose.log_node = null
			_show_toast("Tora fincada!")
		elif _crouch_job == "pegar":
			var fl: Dictionary = _arvores.take_log(_crouch_target)
			_hold_log(fl)
		elif _drag and _carry_node:
			# arrastando: larga onde ela está (deita no chão no mesmo rumo)
			var x2: Vector3 = _carry_node.global_transform.basis.x
			var c2: Vector3 = _carry_node.global_position
			_arvores.drop_log(_carry, c2, atan2(-x2.z, x2.x))
			Sons.play_at(self, "baque", c2)
			_carry = {}
			_carry_node.queue_free()
			_carry_node = null
			_drag = false
		else:
			var fwd := Vector3(-sin(_face), 0, -cos(_face))
			var r: float = _arvores.free_log_radius(_carry)
			var c := _player.position + fwd * (r + 0.55)
			_arvores.drop_log(_carry, c, _face)
			Sons.play_at(self, "baque", c)
			_carry = {}
			if _carry_node:
				_carry_node.queue_free()
			_carry_node = null
			_chop_pose.log_node = null
	if _crouch_t >= T:
		var job := _crouch_job
		_crouch_job = ""
		_chop_pose.crouch = 0.0
		_act_check = 0.0
		if job == "colocar" and _placing != "" and item_qtd(_placing) <= 0:
			stop_placing()       # acabou: sai do modo de colocar
		if job == "mover_forquilha" and not _work.is_empty():
			# forquilha no lugar: agora vai para a ponta da tora cortar a rodela
			var e: int = _apoios.slice_side(int(_work.i), _player.position)
			if e == 0:
				_work = {}
			else:
				_rodela_go(e)


## Um passo: som no chão ou na água; na água abre uma onda em volta do pé.
func _footstep(p: Vector3, depth: float, hard := false, running := false) -> void:
	if depth > 0.04:
		Sons.play_at(self, "agua", p, 0.0 if not hard else 4.0)
		var level := p.y + depth * 2.0
		var cell := Vector2i(int(p.x / CELL), int(p.z / CELL))
		if _water_level.size() == MundoSim.W * MundoSim.H and cell.x >= 0 and cell.y >= 0 and cell.x < MundoSim.W and cell.y < MundoSim.H:
			level = _water_level[cell.y * MundoSim.W + cell.x]
		var fwd := Vector3(-sin(_face), 0, -cos(_face))
		_ripple(Vector3(p.x, level + 0.015, p.z) + fwd * 0.12, 0.9 + depth * 0.8)
	else:
		# um tocador só para os passos: o passo novo corta o anterior (não embola na corrida)
		if _step_player == null:
			_step_player = AudioStreamPlayer3D.new()
			_step_player.unit_size = 6.0
			_step_player.max_distance = 60.0
			_player.add_child(_step_player)
		var kind := "corrida" if running and not hard else "passo"
		_step_player.stream = Sons.pick(kind)
		_step_player.volume_db = float(Sons.VOLUME.get(kind, 0.0)) + (4.0 if hard else 0.0)
		_step_player.pitch_scale = randf_range(0.95, 1.05)
		_step_player.play()


func _ripple(pos: Vector3, size: float) -> void:
	if _ripple_mat == null:
		_ripple_mat = Shader.new()
		_ripple_mat.code = RIPPLE_SHADER
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = _ripple_mat
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(0.25, 1, 0.25)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(size, 1, size), 1.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(func(a: float): mat.set_shader_parameter("age", a), 0.0, 1.0, 1.6)
	tw.chain().tween_callback(mi.queue_free)


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
	_drag = not _can_solo(fl)
	if _drag:
		# pesada demais para o ombro: segura uma ponta e a outra vai arrastando no chão
		var fwd := Vector3(-sin(_face), 0, -cos(_face))
		_drag_b = _player.global_position - fwd * _arvores.free_log_length(fl)
		if _chop_pose:
			_chop_pose.log_node = null
		_drag_update()
		_show_toast("Tora pesada (%d kg): você vai arrastando, uma ponta no chão." % roundi(_carry_kg))
		return
	if _chop_pose:
		_chop_pose.log_node = _carry_node
		_chop_pose.log_r = _arvores.free_log_radius(fl)


## Arrastando: a ponta da mão atrás do corpo, na altura do quadril; a outra ponta vem
## escorregando no chão atrás (segue o caminho, como uma corda).
func _drag_update() -> void:
	if _carry.is_empty() or _carry_node == null or not is_instance_valid(_carry_node):
		_drag = false
		return
	var L: float = _arvores.free_log_length(_carry)
	var r: float = _arvores.free_log_radius(_carry)
	var fwd := Vector3(-sin(_face), 0, -cos(_face))
	var A := _player.global_position + Vector3.UP * 0.72 - fwd * 0.32
	var B := _drag_b
	for it in 3:
		var d := Vector3(B.x - A.x, 0, B.z - A.z)
		if d.length() < 0.05:
			d = -fwd
		d = d.normalized()
		var dy := clampf(A.y - B.y, -L * 0.9, L * 0.9)
		var horiz := sqrt(maxf(L * L - dy * dy, 0.01))
		B = Vector3(A.x + d.x * horiz, 0, A.z + d.z * horiz)
		B.y = height_at(B.x, B.z) + r
	_drag_b = B
	var x := (A - B).normalized()
	var y := (Vector3.UP - x * x.dot(Vector3.UP)).normalized()
	_carry_node.global_transform = Transform3D(Basis(x, y, x.cross(y)), (A + B) * 0.5)


## Galho para cortar: da copa da árvore derrubada ou galho grande caído no chão.
func _branch_target() -> Dictionary:
	if _arvores == null or _galhos == null:
		return {}
	var fb: Dictionary = _arvores.felled_branch_target(_player.position, 1.6)
	if not fb.is_empty():
		return {"kind": "arvore", "p": fb.p, "i": fb.i, "t": fb.t, "to": fb.to, "point": fb.point}
	var gi: int = _galhos.nearest(_player.position, 1.5, true)
	if gi >= 0:
		return {"kind": "chao", "i": gi, "point": _galhos.point_of(gi)}
	return {}


# ================== TRABALHAR NA TORA APOIADA ==================

func _open_work_menu() -> void:
	if _apoios == null or _apoios.nearest_rested(_player.position, 1.8) < 0:
		return
	var ri: int = _apoios.nearest_rested(_player.position, 1.8)
	if _apoios.rested[ri].log.has("sec"):
		var opts := [["Rachar ao meio", "Racha de novo no comprido com\n3 cunhas e a marreta:\nvai virando tábuas.", func(): _split_begin()]]
		if _is_board(_apoios.rested[ri].log):
			opts.append(["Serrar tábua pequena", "Serra um pedaço de 40 cm da ponta\n(cai no chão). Dá para repetir\naté acabar a tábua.", func(): _work_choose("tabua")])
		_choice_menu("TRABALHAR NA MADEIRA", "Escolha o que fazer", opts)
		return
	_choice_menu("TRABALHAR NA TORA", "Escolha o que fazer",
		[["Cortar rodela", "Uma fatia fina da ponta da tora.\nÉ o fundo do balde.", func(): _work_choose("rodela")],
		["Rachar ao meio", "Abre a tora no comprido com\n3 cunhas e a marreta: 2 bandas.", func(): _split_begin()]])


## Menu no meio da tela com opções em botões grandes (com ícone) e FECHAR.
func _choice_menu(title_txt: String, sub_txt: String, opts: Array) -> void:
	if _work_menu != null:
		return
	_joy_id = -1
	_joy_vec = Vector2.ZERO
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud.add_child(dim)
	_work_menu = dim
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", Mochila._box(Color(0.06, 0.06, 0.05, 0.94), Color(0.85, 0.7, 0.45, 0.6), 2, 10))
	dim.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var title := Label.new()
	title.text = title_txt
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.96, 0.9, 0.78))
	v.add_child(title)
	var sub := Label.new()
	sub.text = sub_txt
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	v.add_child(sub)
	var row := GridContainer.new()
	row.columns = 3 if opts.size() > 4 else opts.size()
	row.add_theme_constant_override("h_separation", 18)
	row.add_theme_constant_override("v_separation", 10)
	var cc := CenterContainer.new()
	cc.add_child(row)
	v.add_child(cc)
	for opt in opts:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.custom_minimum_size = Vector2(190, 0)
		row.add_child(col)
		var b := Icones.IconButton.new()
		b.text = opt[0]
		b.custom_minimum_size = Vector2(190, 170 if opts.size() <= 4 else 120)
		b.add_theme_font_size_override("font_size", 20)
		var cb: Callable = opt[2]
		b.pressed.connect(func():
			_close_work_menu()
			cb.call())
		col.add_child(b)
		var d := Label.new()
		d.text = opt[1]
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_font_size_override("font_size", 15)
		d.add_theme_color_override("font_color", Color(0.8, 0.77, 0.7))
		col.add_child(d)
	var close := Button.new()
	close.text = "FECHAR"
	close.custom_minimum_size = Vector2(0, 56)
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(_close_work_menu)
	v.add_child(close)


func _close_work_menu() -> void:
	if _work_menu != null:
		_work_menu.queue_free()
	_work_menu = null
	_act_check = 0.0


## Escolheu o trabalho: pega o machado na mão e vai para a ponta da tora.
## Se nenhuma ponta passa o bastante da forquilha, primeiro muda a forquilha de lugar.
func _work_choose(modo: String) -> void:
	_close_work_menu()
	var i: int = _apoios.nearest_rested(_player.position, 1.8)
	if i < 0:
		return
	var is_tab := modo == "tabua"
	if _apoios.rested[i].log.has("sec") and not is_tab:
		_show_toast("Rodela só sai de tora inteira (redonda).")
		return
	_apoios.rested[i]["cut"] = TAB_L if is_tab else Apoios.SLICE
	# a rodela é fina: só a serra de pedra corta (o machado racha a madeira)
	if item_qtd("serra") <= 0:
		_show_toast("Precisa de uma serra de pedra para serrar.")
		return
	if _mao != "serra":
		equip("serra")
	_work = {"i": i, "modo": modo, "stage": "indo"}
	var e: int = _apoios.slice_side(i, _player.position)
	if e != 0:
		_rodela_go(e)
		return
	var fx: Dictionary = _apoios.fix_plan(i, _player.position)
	if fx.is_empty():
		_work = {}
		_show_toast("Essa madeira ficou curta demais para serrar de novo." if is_tab else "Essa tora ficou curta demais para tirar rodela.")
		return
	_work.fix = fx
	var f: Dictionary = _apoios.forks[int(fx.fork)]
	var fpos := Vector3(float(f.x), 0, float(f.z))
	var to: Vector3 = fx.to
	var mid := (fpos + to) * 0.5
	_work.look = mid
	_walk_to(_side_spot(i, mid, 0.8), "forquilha")


func _rodela_go(e: int) -> void:
	var i := int(_work.i)
	_work.e = e
	_work.erase("fix")
	var sp: Vector3 = _apoios.slice_point(i, e)
	_work.look = sp
	_walk_to(_side_spot(i, sp, 0.95), "rodela")       # a serra é comprida: fica mais afastado


## Lugar do lado da tora (do lado em que o jogador está), na altura do ponto "at".
func _side_spot(i: int, at: Vector3, dist: float) -> Vector3:
	var dir: Vector3 = _apoios.info(i).dir
	var n := Vector3(-dir.z, 0, dir.x).normalized()
	if Vector3(_player.position.x - at.x, 0, _player.position.z - at.z).dot(n) < 0.0:
		n = -n
	return Vector3(at.x, 0, at.z) + n * dist


func _walk_to(target: Vector3, next: String) -> void:
	_walk_target = target
	_walk_next = next
	_walk_t = 0.0
	_walking = true


func _walk_arrived() -> void:
	if _walk_next == "pino":
		_walk_next = ""
		_pin_ready()
		return
	if _walk_next == "rachar":
		_walk_next = ""
		_split_arrived()
		return
	if _walk_next == "modelar":
		_walk_next = ""
		var pend: Dictionary = _crouch_target
		_knap_start(int(pend.get("i", -1)), str(pend.get("kind", "")))
		return
	if _walk_next == "colocar":
		_walk_next = ""
		_face_to(_place_pos)
		_crouch_target = {"id": _placing, "pos": _place_pos, "yaw": _place_yaw}
		_crouch_job = "colocar"
		_crouch_t = 0.0
		return
	if _work.is_empty():
		return
	var look: Vector3 = _work.get("look", _player.position)
	_face_to(look)
	match _walk_next:
		"forquilha":
			_crouch_target = {}
			_crouch_job = "mover_forquilha"
			_crouch_t = 0.0
		"rodela":
			_work.stage = "pronto"
			_act_check = 0.0
	_walk_next = ""


## A rodela solta da ponta e cai no chão (gira de em pé para deitada).
func _drop_rodela(at: Vector3, out: Vector3, r: float, pf := []) -> void:
	var land := at + Vector3(out.x, 0, out.z).normalized() * (0.3 + r)
	_add_ground("rodela", 1, land.x, land.z, r, pf)
	var g: Dictionary = _chao[_chao.size() - 1]
	var node: Node3D = g.node
	var end_pos := node.position
	var q0 := Quaternion(Vector3.UP, out.normalized())
	var q1 := Quaternion(Vector3.UP, randf() * TAU)
	var tw := node.create_tween()
	tw.tween_method(func(t: float) -> void:
		var arc := Vector3(0, sin(t * PI) * 0.12, 0)
		node.position = at.lerp(end_pos, t) + arc
		node.basis = Basis(q0.slerp(q1, smoothstep(0.0, 1.0, t))), 0.0, 1.0, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): Sons.play_at(self, "baque", end_pos, -10.0, 1.4))
	node.position = at
	node.basis = Basis(q0)


## O que soltou do galho cortado cai no chão e fica lá: as folhas (amassadas num
## monte) e os pedaços de galho (viram galhos do chão: os grandes cortam em 2).
func _fall_branch_bits(tp: Array, res: Dictionary) -> void:
	var xf: Transform3D = res.xf
	var sc := xf.basis.x.length()
	var v := int(tp[4])
	var tint: Color = _arvores.fallen_leaf_tint(tp)
	for piece in res.wood:
		var pts: Array = piece[0]
		var radii: Array = piece[1]
		var c := Vector3.ZERO
		for q in pts:
			c += q as Vector3
		c /= pts.size()
		var d3: Vector3 = ((pts[pts.size() - 1] as Vector3) - (pts[0] as Vector3))
		var length := 0.0
		for k in pts.size() - 1:
			length += ((pts[k + 1] as Vector3) - (pts[k] as Vector3)).length()
		var dh := Vector3(d3.x, 0, d3.z)
		if dh.length() < 0.05:
			dh = Vector3(cos(randf() * TAU), 0, sin(randf() * TAU))
		dh = dh.normalized()
		var rel := []
		for q in pts:
			rel.append((q as Vector3) - c)
		var bd := GalhoGeo.Builder.new()
		bd.tube(rel, radii, [true, false], {}, 7)
		var mi := MeshInstance3D.new()
		mi.mesh = bd.commit()
		mi.set_surface_override_material(0, _arvores.bark_material())
		if mi.mesh.get_surface_count() > 1:
			mi.set_surface_override_material(1, GalhoGeo.wood_material())
		add_child(mi)
		mi.position = c
		var r0 := float(radii[0])
		var ground := Vector3(c.x, surface_at(c.x, c.z) + r0 * 0.8, c.z)
		var q0 := Quaternion.IDENTITY
		var q1 := Quaternion(d3.normalized(), dh)
		var dur := clampf(sqrt(maxf(c.y - ground.y, 0.1) / 4.9), 0.25, 0.8)
		var tw := mi.create_tween()
		tw.tween_method(func(t: float) -> void:
			mi.position = c.lerp(ground, t * t)
			mi.basis = Basis(q0.slerp(q1, t)), 0.0, 1.0, dur)
		var gx := c.x
		var gz := c.z
		var yaw := atan2(dh.z, dh.x)
		var big := length > 1.4
		tw.tween_callback(func():
			mi.queue_free()
			_galhos.add(gx, gz, yaw, length, r0, false, big)
			_galhos._rebuild()
			# galho caindo de pouca altura: barulho baixo, abafado
			Sons.play_at(self, "baque", Vector3(gx, surface_at(gx, gz), gz), -17.0, 1.45))
	for ci in res.leaves:
		var lm: MeshInstance3D = _galhos.leaves_node(v, int(ci))
		lm.set_instance_shader_parameter("tint", tint)
		add_child(lm)
		var cxf: Transform3D = res.get("lxf", {}).get(ci, xf)
		lm.transform = cxf
		var aabb: AABB = lm.mesh.get_aabb()
		var wc: Vector3 = cxf * aabb.get_center()
		var gy := surface_at(wc.x, wc.z)
		var yaw := randf() * TAU
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc * 0.62, sc * 0.4, sc * 0.62))
		var end_xf := Transform3D(b, Vector3(wc.x, gy + aabb.size.y * sc * 0.12, wc.z) - b * aabb.get_center())
		var dur := clampf(sqrt(maxf(wc.y - gy, 0.1) / 4.9) * 1.6, 0.4, 1.2)   # folha cai mais devagar
		var tw := lm.create_tween()
		tw.tween_method(func(t: float) -> void:
			lm.transform = cxf.interpolate_with(end_xf, smoothstep(0.0, 1.0, t)), 0.0, 1.0, dur)
		var cii := int(ci)
		tw.tween_callback(func():
			lm.queue_free()
			_galhos.add_leaves(wc.x, wc.z, gy, yaw, v, cii, sc, tint)
			_galhos._rebuild()
			Sons.play_at(self, "passo", Vector3(wc.x, gy, wc.z), -8.0, 0.7))
	if not res.wood.is_empty():
		_show_toast("O galho caiu." if res.leaves.is_empty() else "Caíram as folhas e o galho.")
	elif not res.leaves.is_empty():
		_show_toast("Caíram as folhas do galho.")


# ================== COLOCAR ITEM NO CHÃO ==================

## Mochila: COLOCAR. Aparece a prévia do item, branca e transparente, onde a câmera
## aponta (perto do personagem). Dá para andar, girar a câmera e o botão "Girar".
func start_placing(id: String) -> bool:
	if item_qtd(id) <= 0 or not _carry.is_empty() or _crouch_job != "":
		return false
	if _chopping:
		_cancel_chop()
	stop_placing()
	_placing = id
	_place_rot = 0.0
	_ghost = MeshInstance3D.new()
	if id == "forquilha":
		_ghost.mesh = _apoios.preview_mesh()
	elif id == "balde":
		_ghost.mesh = Balde.mesh()
	elif id == "tabua":
		_ghost.mesh = _board_mesh(false, 0)
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.12, 0.18)
		_ghost.mesh = bm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(1, 1, 1, 0.55)
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.render_priority = 10
	_ghost.material_override = gm
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	_act_check = 0.0
	_update_placing()
	return true


func stop_placing() -> void:
	_placing = ""
	if _ghost:
		_ghost.queue_free()
	_ghost = null
	if _walk_next == "colocar":
		_walking = false
		_walk_next = ""
	for b in [_place_btn, _rot_btn, _store_btn]:
		if b:
			b.visible = false
	_act_check = 0.0


func _update_placing() -> void:
	if _placing == "" or _ghost == null:
		return
	# os outros botões de ação somem enquanto escolhe o lugar
	for b in [_dig_btn, _chop_btn, _seed_btn, _pick_btn, _log_btn, _vine_btn, _plant_btn, _ctx_btn, _work_btn]:
		if b:
			b.visible = false
	var busy := _crouch_job != "" or _walk_next == "colocar"
	_place_btn.visible = not busy
	_rot_btn.visible = not busy
	_store_btn.visible = not busy
	if busy:
		return
	# na frente do personagem, para onde a câmera está virada
	var pp := _player.position
	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var pos := pp + fwd * PLACE_DIST
	pos.y = surface_at(pos.x, pos.z)
	_place_pos = pos
	_place_yaw = atan2(fwd.z, fwd.x) + _place_rot      # o X fica de frente para a câmera
	# a segunda forquilha já fica alinhada com a que está no chão (a tora deita reta nas duas)
	if _placing == "forquilha" and _apoios:
		var best := 3.2
		for f in _apoios.forks:
			var d := Vector2(pos.x - float(f.x), pos.z - float(f.z))
			if d.length() > 0.4 and d.length() < best:
				best = d.length()
				_place_yaw = atan2(d.y, d.x) + _place_rot
	# não dá para colocar dentro da água funda
	var depth := 0.0
	var cell := Vector2i(int(pos.x / CELL), int(pos.z / CELL))
	if _water_level.size() == MundoSim.W * MundoSim.H and cell.x >= 0 and cell.y >= 0 and cell.x < MundoSim.W and cell.y < MundoSim.H:
		depth = maxf(0.0, _water_level[cell.y * MundoSim.W + cell.x] - height_at(pos.x, pos.z))
	depth = maxf(depth, hole_water_depth(pos.x, pos.z))
	_place_ok = depth < 0.25
	(_ghost.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, 0.55) if _place_ok else Color(1, 0.35, 0.3, 0.55)
	_ghost.global_position = pos
	_ghost.rotation = Vector3(0, -_place_yaw, 0)
	_place_btn.disabled = not _place_ok


## Botão "Colocar": o personagem vai até perto do lugar, se abaixa e põe o item lá.
func _place_press() -> void:
	if _placing == "" or not _place_ok or _crouch_job != "" or item_qtd(_placing) <= 0:
		return
	var to := Vector3(_place_pos.x - _player.position.x, 0, _place_pos.z - _player.position.z)
	if to.length() > 1.1:
		_walk_to(_place_pos - to.normalized() * 0.85, "colocar")
		return
	_walk_next = "colocar"
	_walk_arrived()


func _place_now(t: Dictionary) -> void:
	var id := str(t.get("id", ""))
	if id == "" or item_qtd(id) <= 0:
		return
	var pos: Vector3 = t.pos
	remove_item(id, 1)
	if id == "forquilha":
		_apoios.place(pos, float(t.yaw))
	else:
		_add_ground(id, 1, pos.x, pos.z)
		var g: Dictionary = _chao[_chao.size() - 1]
		(g.node as Node3D).rotation.y = -float(t.yaw)
	Sons.play_at(self, "baque", pos, -12.0, 1.3)
	_update_inventory()


# ================== SERRAR A RODELA ==================

func _begin_saw() -> void:
	var wi := int(_work.get("i", -1))
	var we := int(_work.get("e", 0))
	if wi < 0 or wi >= _apoios.rested.size() or we == 0:
		return
	var inf: Dictionary = _apoios.info(wi)
	var sp: Vector3 = _apoios.slice_point(wi, we)
	var rend: float = _arvores.free_log_end_radius(_apoios.rested[wi].log, we)
	_chop_log = {"rodela": true, "axis": sp, "along": inf.dir, "r": rend, "dist": 0.95, "point": sp + Vector3.UP * rend}
	_sawing = true
	_saw_t = 0.0
	_saw_half = 0
	_play("Idle", 0.5)
	if _chop_pose:
		_chop_pose.sawing = true
		_chop_pose.saw_point = sp + Vector3.UP * rend
		_chop_pose.saw_axis = inf.dir
		_chop_pose.saw_depth = _saw_depth(wi, rend)
	_chop_btn.visible = true
	_chop_btn.text = "Parar"
	# o jogador faz o vai e vem: sobe o dedo empurra, desce puxa
	_saw_p = 0.0
	_saw_side = -1
	if _saw_ctrl == null:
		_saw_ctrl = SerraCtrl.new()
		_saw_ctrl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_saw_ctrl.offset_left = -150
		_saw_ctrl.offset_right = -30
		_saw_ctrl.offset_top = -470
		_saw_ctrl.offset_bottom = -20
		_hud.add_child(_saw_ctrl)
	_saw_ctrl.value = 0.0
	_saw_ctrl.visible = true
	_saw_ctrl.queue_redraw()
	_jump_btn.visible = false
	for b in [_log_btn, _ctx_btn, _work_btn, _pick_btn, _vine_btn, _plant_btn]:
		if b:
			b.visible = false
	_show_toast("Arraste o pegador: para cima empurra a serra, para baixo puxa.")


func _stop_saw() -> void:
	_sawing = false
	if _saw_ctrl:
		_saw_ctrl.visible = false
	_jump_btn.visible = true
	_chop_log = {}
	if _chop_pose:
		_chop_pose.sawing = false
	_act_check = 0.0


## Quanto o corte já desceu na tora (m), para a serra ir afundando.
func _saw_depth(wi: int, rend: float) -> float:
	var en: Dictionary = _apoios.rested[wi].log.get("entalhe", {})
	if en.is_empty():
		return 0.0
	return clampf(float(en.hits) / maxf(float(en.need), 1.0), 0.0, 1.0) * rend * 1.7


func _saw_update(delta: float) -> void:
	var wi := int(_work.get("i", -1))
	var we := int(_work.get("e", 0))
	if wi < 0 or wi >= _apoios.rested.size() or we == 0 or _mao != "serra":
		_stop_saw()
		return
	# a serra segue o dedo (com um limite de velocidade: braço de verdade)
	var want: float = float(_saw_ctrl.value) if _saw_ctrl else _saw_p
	_saw_p = move_toward(_saw_p, want, SAW_SPEED * delta)
	_saw_t += delta
	if _chop_pose:
		_chop_pose.saw_pos = _saw_p * 2.0 - 1.0
	var at: Vector3 = _chop_log.point
	# chegou num fim de curso vindo do outro: uma passada (empurrando ou puxando)
	var reached := 1 if _saw_p > 0.85 else (-1 if _saw_p < 0.15 else 0)
	if reached != 0 and reached != _saw_side:
		_saw_side = reached
		Sons.play_at(self, "serra", at, 0.0, 0.92 if reached > 0 else 1.0)
		_sawdust(at)
		if reached < 0:
			# uma ida e volta inteira: o corte desce um pouco e a serra gasta
			var end_before: Vector3 = _apoios.end_point(wi, we)
			var dir: Vector3 = _apoios.info(wi).dir
			var pf: Array = _arvores.free_log_end_profile(_apoios.rested[wi].log, we)
			var rad: float = _apoios.slice_stroke(wi, we)
			var broke := wear("serra")
			if rad > 0.0:
				if str(_work.get("modo", "")) == "tabua":
					_tabua_cortada(wi, end_before, dir * float(we))
					_stop_saw()
					_work = {}
					return
				_drop_rodela(end_before - dir * float(we) * Apoios.SLICE * 0.5, dir * float(we), rad, pf)
				_stop_saw()
				_work = {}
				_show_toast("A rodela soltou. Pegue ela!")
				return
			if broke and item_qtd("serra") <= 0:
				_stop_saw()
				return
			if _chop_pose:
				_chop_pose.saw_depth = _saw_depth(wi, float(_chop_log.r))


## Pó de serra caindo do corte.
func _sawdust(at: Vector3) -> void:
	var c := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.006, 0.012)
	c.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.64, 0.42)
	c.material_override = mat
	c.amount = 18
	c.one_shot = true
	c.explosiveness = 0.6
	c.lifetime = 0.9
	c.direction = Vector3(0, -1, 0)
	c.spread = 35.0
	c.initial_velocity_min = 0.2
	c.initial_velocity_max = 0.6
	c.gravity = Vector3(0, -6.0, 0)
	add_child(c)
	c.global_position = at
	c.emitting = true
	get_tree().create_timer(1.2).timeout.connect(c.queue_free)


# ================== MODELAR PEDRA (no chão) ==================

func _open_knap_menu() -> void:
	var i: int = _pedras.nearest(_player.position, 1.3, true)
	if i < 0:
		return
	var p: Dictionary = _pedras.items[i]
	if str(p.get("kind", "")) != "":
		_knap_go(i, str(p.kind))      # já tinha começado: continua de onde parou
		return
	var descs := {"pedra_machado": "Pedra com fio, do formato da cabeça do machado.",
		"pedra_cavadeira": "Pedra larga e chata, como uma pá.",
		"lamina_serra": "Pedra comprida e fina, com dentes num lado.",
		"pedra_pa": "Pedra larga e fina, arredondada na frente, para a pá.",
		"cunha": "Grossa atrás e com fio reto: abre a tora.",
		"pedra_marreta": "Bloco grosso e comprido: cabeça da marreta.",
		"ponta_pedra": "Grossa atrás e bem aguda na frente: ponta do furador.",
		"lamina_faca": "Comprida e fina, com fio e ponta: lâmina da faca."}
	var opts := []
	for k in ["pedra_machado", "pedra_cavadeira", "lamina_serra", "pedra_pa", "cunha", "pedra_marreta", "ponta_pedra", "lamina_faca"]:
		var kk: String = k
		opts.append([Lascar.KINDS[k].nome, descs[k], func(): _knap_go(_pedras.nearest(_player.position, 1.5, true), kk)])
	_choice_menu("MODELAR PEDRA", "Que ferramenta essa pedra vai virar?", opts)


## Vai até do lado da pedra do chão e começa a modelar.
func _knap_go(i: int, kind: String) -> void:
	if i < 0 or _mao != "pedra":
		return
	var c: Vector3 = _pedras.point_of(i)
	var away := Vector3(_player.position.x - c.x, 0, _player.position.z - c.z)
	if away.length() < 0.05:
		away = Vector3(0, 0, 1)
	_crouch_target = {"i": i, "kind": kind}
	_walk_to(c + away.normalized() * 0.72, "modelar")


func _knap_start(i: int, kind: String) -> void:
	if i < 0 or i >= _pedras.items.size() or kind == "":
		return
	var p: Dictionary = _pedras.items[i]
	var orig := Lascar.rock(int(p.seed))
	var tgt := Lascar.fit_target(orig, kind)
	var cur: PackedFloat32Array = _pedras.radii(i)
	p.kind = kind
	_knap_rng.seed = int(p.seed) + int(p.get("spots", 0)) * 131
	_knap = {"i": i, "kind": kind, "cur": cur, "tgt": tgt, "orig": orig, "sel": false, "hits": 0,
		"done": int(p.get("spots", 0)), "K": int(Lascar.KINDS[kind].spots),
		"ex0": maxf(Lascar.excess(orig, tgt), 0.0001), "anim": -1.0, "t": 0.0, "ending": -1.0}
	_knap.spot = Lascar.next_spot(cur, tgt)
	_knap_new_spot()
	_face_to(_pedras.point_of(i))
	_pedras.hide_stone(i)
	_knap_mi = MeshInstance3D.new()
	_knap_mi.material_override = Lascar.material()
	add_child(_knap_mi)
	_knap_refresh_mesh()
	# o próprio personagem se abaixa e bate com as duas mãos (a câmera fica nos olhos dele)
	if _chop_pose:
		_chop_pose.knapping = true
		_chop_pose.hide_head = true
		_chop_pose.crouch = 1.0
		_chop_pose.crouch_spine = 0.55
	_knap_camera(1.0)
	_place_knap_hand(0.0)
	_play("Idle", 0.5)
	_build_knap_ui()
	_grass_mat.set_shader_parameter("flat_spot", Vector4(_knap_mi.global_position.x, 0, _knap_mi.global_position.z, 2.2))
	if teste:
		_knap_finish()           # modo de teste: fica pronta na hora


func _knap_refresh_mesh() -> void:
	var i := int(_knap.i)
	_knap_mi.mesh = Lascar.mesh(_knap.cur, _knap.orig, int(_pedras.items[i].seed))
	_knap_mi.transform = _pedras.xform(i)


func _knap_spot_world() -> Vector3:
	var sp := int(_knap.get("spot", -1))
	if sp < 0:
		return _knap_mi.global_position
	return _knap_mi.transform * Lascar.spot_point(_knap.cur, sp)


func _knap_progress() -> float:
	return clampf(1.0 - Lascar.excess(_knap.cur, _knap.tgt) / float(_knap.ex0), 0.0, 1.0)


## Ponto novo: quantas batidas pede e a dificuldade da barrinha (cada lugar é diferente:
## o marcador anda mais rápido ou mais devagar, o verde é maior ou menor).
func _knap_new_spot() -> void:
	var pr := _knap_progress()
	_knap.sel = false
	_knap.hits = 0
	_knap.need = _knap_rng.randi_range(1, 2)
	_knap.speed = _knap_rng.randf_range(0.22, 0.5) * (1.0 + 0.3 * pr)       # idas e voltas por segundo
	_knap.gw = _knap_rng.randf_range(0.22, 0.36) * (1.0 - 0.2 * pr)         # largura do verde (0 a 1)
	_knap.gc = _knap_rng.randf_range(0.25, 0.75)                            # onde fica o verde
	_knap.t = _knap_rng.randf() * 4.0


## Onde está o marcador amarelo na barrinha (0 a 1, vai e volta).
func _knap_marker() -> float:
	var x := fmod(float(_knap.t) * float(_knap.speed), 2.0)
	return x if x <= 1.0 else 2.0 - x


const KNAP_EDGE := 0.08            # faixa laranja do lado do verde: "quase" (não quebra)


func _knap_in_green(m: float) -> bool:
	return absf(m - float(_knap.gc)) <= float(_knap.gw) * 0.5 + 0.01


func _knap_near(m: float) -> bool:
	return absf(m - float(_knap.gc)) <= float(_knap.gw) * 0.5 + KNAP_EDGE


## A mão com a pedra de bater: parada do lado (fora da pedra), e na batida vai até o
## ponto, levanta, desce e volta. a = 0 a 1 (momento da batida), < 0 parada.
func _place_knap_hand(a: float) -> void:
	if _chop_pose == null or _knap_mi == null:
		return
	# levanta a pedra de bater, desce rápido no ponto e volta
	var lift := 0.55
	if a >= 0.0:
		if a < 0.4:
			lift = lerpf(0.55, 1.0, smoothstep(0.0, 1.0, a / 0.4))
		elif a < 0.55:
			lift = lerpf(1.0, 0.0, pow((a - 0.4) / 0.15, 2.0))
		else:
			lift = lerpf(0.0, 0.55, smoothstep(0.0, 1.0, (a - 0.55) / 0.45))
	_chop_pose.knap_point = _knap_spot_world()
	_chop_pose.knap_lift = lift


func _build_knap_ui() -> void:
	_knap_ui = Control.new()
	_knap_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_knap_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_knap_ui)
	var box := func(l: float, t: float, r: float, b: float, anchor: int) -> PanelContainer:
		var pc := PanelContainer.new()
		pc.set_anchors_preset(anchor)
		pc.offset_left = l
		pc.offset_top = t
		pc.offset_right = r
		pc.offset_bottom = b
		pc.add_theme_stylebox_override("panel", Mochila._box(Color(0.05, 0.05, 0.04, 0.82), Color(1, 1, 1, 0.18), 2, 8))
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_knap_ui.add_child(pc)
		return pc
	var info: PanelContainer = box.call(16, 16, 380, 120, Control.PRESET_TOP_LEFT)
	var il := Label.new()
	il.text = "MODELAGEM DE PEDRA\nToque no ponto da pedra e em BATER com o marcador no VERDE. Laranja: quase (não quebra). Vermelho: a pedra quebra!"
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	il.add_theme_font_size_override("font_size", 15)
	info.add_child(il)
	var prog: PanelContainer = box.call(-200, 16, 200, 84, Control.PRESET_CENTER_TOP)
	var pv := VBoxContainer.new()
	prog.add_child(pv)
	var pl := Label.new()
	pl.name = "pl"
	pl.add_theme_font_size_override("font_size", 16)
	pv.add_child(pl)
	var bar := ProgressBar.new()
	bar.name = "bar"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(360, 14)
	bar.max_value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.75, 0.25)
	bar.add_theme_stylebox_override("fill", fill)
	pv.add_child(bar)
	var tool: PanelContainer = box.call(-200, 96, -16, 276, Control.PRESET_TOP_RIGHT)
	var tv := VBoxContainer.new()
	tool.add_child(tv)
	var tl := Label.new()
	tl.text = "Fazendo:"
	tl.add_theme_font_size_override("font_size", 15)
	tv.add_child(tl)
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(160, 110)
	var kind := str(_knap.kind)
	ic.draw.connect(func(): Desenhos.item(ic, kind, ic.size * 0.5, 100.0))
	tv.add_child(ic)
	var tn := Label.new()
	tn.text = str(Lascar.KINDS[kind].nome)
	tn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tn.add_theme_font_size_override("font_size", 16)
	tv.add_child(tn)
	# o ponto onde bater (desenhado em cima da pedra)
	var mk := Control.new()
	mk.name = "mk"
	mk.set_anchors_preset(Control.PRESET_FULL_RECT)
	mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mk.draw.connect(func(): _draw_knap_marker(mk))
	_knap_ui.add_child(mk)
	# barrinha do tempo da batida: embaixo, no meio
	var tb := Control.new()
	tb.name = "tb"
	tb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tb.offset_left = -270
	tb.offset_right = 270
	tb.offset_top = -110
	tb.offset_bottom = -30
	tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.draw.connect(func(): _draw_knap_bar(tb))
	_knap_ui.add_child(tb)
	var hit := Icones.IconButton.new()
	hit.text = "Bater"
	hit.add_theme_font_size_override("font_size", 22)
	hit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hit.offset_left = -190
	hit.offset_top = -190
	hit.offset_right = -30
	hit.offset_bottom = -30
	hit.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS     # conta na hora que o dedo encosta
	hit.pressed.connect(_knap_hit)
	_knap_ui.add_child(hit)
	var out := Icones.IconButton.new()
	out.text = "Sair"
	out.add_theme_font_size_override("font_size", 20)
	out.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	out.offset_left = 30
	out.offset_top = -160
	out.offset_right = 160
	out.offset_bottom = -30
	out.pressed.connect(func():
		_show_toast("A pedra fica do jeito que está. Dá para continuar depois.")
		_knap_end())
	_knap_ui.add_child(out)


func _draw_knap_bar(tb: Control) -> void:
	if _knap.is_empty():
		return
	var w := tb.size.x
	var r := Rect2(Vector2(0, 34), Vector2(w, 34))
	var font := ThemeDB.fallback_font
	var txt := "Bata quando o marcador estiver no verde" if bool(_knap.sel) else "Toque no ponto da pedra"
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	tb.draw_rect(Rect2(Vector2(w * 0.5 - tw * 0.5 - 10, 0), Vector2(tw + 20, 28)), Color(0.05, 0.05, 0.04, 0.85))
	tb.draw_string(font, Vector2(w * 0.5 - tw * 0.5, 21), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.95, 0.8))
	tb.draw_rect(r.grow(4), Color(0.05, 0.05, 0.04, 0.9))
	# vermelho com o verde no meio (as beiradas do verde vão clareando)
	var n := 60
	for k in n:
		var u := (k + 0.5) / n
		var d := absf(u - float(_knap.gc)) - float(_knap.gw) * 0.5
		var col := Color(0.2, 0.75, 0.2) if d <= 0.0 else (Color(0.92, 0.55, 0.1) if d <= KNAP_EDGE else Color(0.8, 0.12, 0.1))
		tb.draw_rect(Rect2(r.position + Vector2(w * k / n, 0), Vector2(w / n + 0.5, r.size.y)), col)
	tb.draw_rect(r, Color(0, 0, 0, 0.8), false, 2.0)
	# o marcador amarelo (para no lugar do toque durante a batida)
	var m: float = float(_knap.get("frozen", 0.5)) if float(_knap.anim) >= 0.0 else _knap_marker()
	var x := r.position.x + m * w
	tb.draw_rect(Rect2(Vector2(x - 4, r.position.y - 7), Vector2(8, r.size.y + 14)), Color(1.0, 0.85, 0.15))
	tb.draw_rect(Rect2(Vector2(x - 4, r.position.y - 7), Vector2(8, r.size.y + 14)), Color(0.2, 0.12, 0.0), false, 2.0)


func _draw_knap_marker(mk: Control) -> void:
	if _knap.is_empty() or int(_knap.get("spot", -1)) < 0 or float(_knap.anim) >= 0.0:
		return
	var w := _knap_spot_world()
	if _cam.is_position_behind(w):
		return
	var p := _cam.unproject_position(w)
	var sel := bool(_knap.sel)
	var t := Time.get_ticks_msec() / 1000.0
	var r := 16.0 + (3.0 * sin(t * 6.0) if sel else 0.0)
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	if sel:
		mk.draw_circle(p, r * 1.6, Color(1.0, 0.75, 0.2, 0.25))
		mk.draw_colored_polygon(pts, Color(1.0, 0.78, 0.2, 0.9))
	mk.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.95) if not sel else Color(0.3, 0.18, 0.02), 3.0, true)
	var font := ThemeDB.fallback_font
	var txt := "Toque aqui" if not sel else "Agora: BATER"
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var lb := Rect2(p + Vector2(-tw * 0.5 - 8, -r - 44), Vector2(tw + 16, 28))
	mk.draw_rect(lb, Color(0.05, 0.05, 0.04, 0.85))
	mk.draw_rect(lb, Color(1.0, 0.78, 0.2, 0.9), false, 2.0)
	mk.draw_string(font, lb.position + Vector2(8, 20), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.95, 0.8))


func _knap_input(e: InputEvent) -> void:
	var pos := Vector2.INF
	if e is InputEventScreenTouch and e.pressed:
		pos = e.position
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
	if pos == Vector2.INF or int(_knap.get("spot", -1)) < 0:
		return
	var w := _knap_spot_world()
	if _cam.is_position_behind(w):
		return
	if pos.distance_to(_cam.unproject_position(w)) < 70.0:
		_knap.sel = true


func _knap_hit() -> void:
	if _knap.is_empty() or float(_knap.anim) >= 0.0 or float(_knap.ending) >= 0.0:
		return
	if not bool(_knap.sel):
		_show_toast("Toque primeiro no ponto marcado na pedra.")
		return
	# acertou o verde? (conta onde o marcador estava um instante antes do toque:
	# o celular demora um pouquinho para avisar o toque)
	_knap.t = float(_knap.t) - 0.06
	var m := _knap_marker()
	_knap.frozen = m
	if _knap_in_green(m):
		_knap.ok = true
	elif _knap_near(m):
		# laranja: quase! não quebra, mas a batida não conta
		_show_toast("Quase! Bata no verde.")
		Sons.play_at(self, "pedra_bate", _knap_spot_world(), -8.0, 1.2)
		return
	else:
		_knap.ok = false
	_knap.anim = 0.0


func _knap_camera(_delta: float) -> void:
	var c := _knap_mi.global_position
	# nos olhos do personagem abaixado, olhando a pedra
	var eye := _player.global_position + Vector3.UP * 1.0
	if _skel and _head_bone >= 0:
		var hg: Transform3D = _skel.global_transform * _skel.get_bone_global_pose(_head_bone)
		var to := Vector3(c.x - hg.origin.x, 0, c.z - hg.origin.z).normalized()
		eye = hg.origin + Vector3.UP * 0.06 + to * 0.3
	_cam.global_position = eye
	_cam.look_at(c + Vector3.UP * 0.02)


func _update_knap(delta: float) -> void:
	if _knap.is_empty():
		return
	for b in [_dig_btn, _chop_btn, _seed_btn, _pick_btn, _log_btn, _vine_btn, _plant_btn, _ctx_btn, _work_btn, _jump_btn]:
		if b:
			b.visible = false
	if float(_knap.ending) >= 0.0:
		_knap.ending = float(_knap.ending) - delta
		if float(_knap.ending) < 0.0:
			var i := int(_knap.i)
			_knap_end()
			if i < _pedras.items.size():
				_pedras.take(i)          # a pedra quebrou: perdeu
		return
	var a := float(_knap.anim)
	if a >= 0.0:
		var before := a
		a += delta / 0.55
		if before < 0.55 and a >= 0.55:
			_knap_impact()
			if _knap.is_empty():
				return
		_knap.anim = -1.0 if a >= 1.0 else a
		_place_knap_hand(minf(a, 1.0) if a < 1.0 else -1.0)
	else:
		_knap.t = float(_knap.t) + delta
		_place_knap_hand(-1.0)
	var pr := _knap_progress()
	var pl := _knap_ui.find_child("pl", true, false) as Label
	var bar := _knap_ui.find_child("bar", true, false) as ProgressBar
	if pl:
		pl.text = "Progresso da modelagem   %d%%" % int(pr * 100.0)
	if bar:
		bar.value = pr * 100.0
	for n in ["mk", "tb"]:
		var c := _knap_ui.find_child(n, true, false) as Control
		if c:
			c.queue_redraw()


## A pedra de bater chegou na pedra do chão.
func _knap_impact() -> void:
	var w := _knap_spot_world()
	var i := int(_knap.i)
	if not bool(_knap.ok):
		# bateu no vermelho: a pedra quebra e não serve mais para nada
		_pedras.items[i].rachada = true
		_pedras.items[i].kind = ""
		Sons.play_at(self, "pedra_racha", w, 2.0)
		_stone_chips(w, 24)
		_knap_mi.mesh = Lascar.mesh(_knap.cur, _knap.orig, int(_pedras.items[i].seed), true)
		_show_toast("Bateu fora do verde: a pedra quebrou! Perdeu a pedra.")
		_knap.ending = 1.6
		return
	Sons.play_at(self, "pedra_bate", w, 0.0, randf_range(0.95, 1.1))
	_stone_chips(w, 6)
	_knap.hits = int(_knap.hits) + 1
	if int(_knap.hits) < int(_knap.need):
		return
	# soltou uma lasca: a pedra vai tomando forma (aos poucos)
	var cur: PackedFloat32Array = _knap.cur
	Lascar.flake(cur, _knap.tgt, int(_knap.spot), _knap_rng)
	# a pedra inteira vai chegando no formato: na última lasca ela fica pronta, sem pular
	var tg: PackedFloat32Array = _knap.tgt
	var left := maxi(int(_knap.K) - int(_knap.done), 1)
	var g := 1.0 / float(left)
	for q in cur.size():
		cur[q] = lerpf(cur[q], tg[q], g)
	_knap.cur = cur
	_knap.done = int(_knap.done) + 1
	_pedras.items[i].spots = int(_knap.done)
	Sons.play_at(self, "pedra_lasca", w, 0.0, randf_range(0.95, 1.08))
	_stone_chips(w, 14)
	if int(_knap.done) >= int(_knap.K):
		_knap_finish()
		return
	_pedras.set_radii(i, cur)
	_knap_refresh_mesh()
	_knap.spot = Lascar.next_spot(cur, _knap.tgt)
	_knap_new_spot()


func _knap_finish() -> void:
	var i := int(_knap.i)
	var kind := str(_knap.kind)
	var p: Dictionary = _pedras.items[i]
	var c: Vector3 = _pedras.point_of(i)
	var size := float(p.s)
	_knap_end()
	_pedras.take(i)
	_add_ground(kind, 1, c.x, c.z, size, [int(p.seed), float(p.yaw)])
	_show_toast("%s pronta! Pegue ela do chão." % Lascar.KINDS[kind].nome)


func _knap_end() -> void:
	if _knap_ui:
		_knap_ui.queue_free()
	_knap_ui = null
	if _knap_mi:
		_knap_mi.queue_free()
	_knap_mi = null
	_knap = {}
	if _knap_hand:
		_knap_hand.queue_free()
	_knap_hand = null
	_player.visible = true
	_jump_btn.visible = true
	if _chop_pose:
		_chop_pose.crouch_spine = 1.0
		_chop_pose.hide_head = false
	_grass_mat.set_shader_parameter("flat_spot", Vector4.ZERO)
	if _pedras:
		_pedras.hide_stone(-1)
	if _chop_pose:
		_chop_pose.knapping = false
		_chop_pose.crouch = 0.0
	_act_check = 0.0


## Lascas de pedra voando da batida.
func _stone_chips(at: Vector3, n: int) -> void:
	var c := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.006, 0.01)
	c.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.58, 0.52)
	c.material_override = mat
	c.amount = n
	c.one_shot = true
	c.explosiveness = 0.95
	c.lifetime = 0.6
	c.direction = Vector3(0, 1, 0)
	c.spread = 70.0
	c.initial_velocity_min = 0.6
	c.initial_velocity_max = 1.6
	c.gravity = Vector3(0, -9.8, 0)
	add_child(c)
	c.global_position = at
	c.emitting = true
	get_tree().create_timer(1.0).timeout.connect(c.queue_free)


# ================== PÁ ==================

## A pá chegou no chão: se está vazia, tira uma pá de terra do chão na frente (o chão
## desce ali); se está cheia, joga a terra na frente (o chão sobe ali).
func _pa_hit() -> void:
	var at := _front(0.75)
	if not _pa_full:
		var y_old: float = _escav.ground_at(at.x, at.z)
		var was_clay: bool = _escav.is_clay(at.x, at.z)       # monte de argila despejada
		var v: float = _escav.dig(at)
		if v <= 0.0001:
			_show_toast("Não dá para cavar mais fundo aqui.")
			return
		# chão de argila (a jazida da beira das lagoas): a pá sai cheia de argila
		var cell := Vector2i(int(at.x / CELL), int(at.z / CELL))
		var sd: Dictionary = sim.soil_data(cell)
		var depth_now := surface_at(at.x, at.z) - y_old
		var mound_clay: bool = was_clay
		_pa_tipo = "argila" if (mound_clay or (not sd.is_empty() and float(sd.clay) >= 0.35 and depth_now < 1.2)) else "terra"
		if _pa_tipo == "argila":
			sim.dig(cell, PAZADA * DENS.argila * 0.004)     # gasta um pouquinho da argila da beira
		if _pa_dirt:
			_pa_dirt.material_override = _clay_mat() if _pa_tipo == "argila" else Corte.axe_material()
		if _minerios:
			# o que veio junto com a terra (só debaixo da terra, onde a geologia deixou)
			var got: Dictionary = _minerios.extract(at, y_old, _escav.ground_at(at.x, at.z))
			var msg := []
			for m in got:
				var left := add_item(m, int(got[m]))
				if left > 0:
					_add_ground(m, left, at.x + randf_range(-0.4, 0.4), at.z + randf_range(-0.4, 0.4))
				msg.append("%d %s" % [int(got[m]), Itens.ITENS[m].nome])
			if not msg.is_empty():
				_show_toast("Junto com a terra veio: " + ", ".join(msg))
		_dirt(at)
		Sons.play_at(self, "cavar", at, 0.0, 0.9)
		_pa_full = true
		_pa_vol = v
	else:
		var bi := _bucket_ahead()
		if bi >= 0:
			_fill_bucket(bi)
			return
		var to := _front(1.05)
		_escav.dump(to, _pa_vol, _pa_tipo)
		_dirt(to)
		Sons.play_at(self, "cavar", to, -4.0, 1.15)
		_pa_full = false
		_pa_vol = 0.0
	if _pa_dirt:
		_pa_dirt.visible = _pa_full


# ================== BALDE ==================

## Balde no chão bem na frente (onde a pá vai despejar), ou -1.
func _bucket_ahead() -> int:
	var to := _front(1.0)
	var best := -1
	var bd := 0.75
	for i in _chao.size():
		var g: Dictionary = _chao[i]
		if str(g.id) != "balde":
			continue
		var d := Vector2(float(g.x) - to.x, float(g.z) - to.z).length()
		if d < bd:
			bd = d
			best = i
	return best


static func _carga_of(g: Dictionary) -> Dictionary:
	var dl: Array = g.get("dur", [])
	if dl.size() == 2 and float(dl[1]) > 0.0:
		return {"tipo": str(dl[0]), "vol": float(dl[1])}
	return {}


## Despeja a pá no balde do chão (terra com terra, argila com argila).
func _fill_bucket(i: int) -> void:
	var g: Dictionary = _chao[i]
	var c := _carga_of(g)
	if not c.is_empty() and str(c.tipo) != _pa_tipo:
		_show_toast("O balde está com %s. Não misture: esvazie ou use outro balde." % c.tipo)
		return
	var vol := float(c.get("vol", 0.0))
	var cap := minf(BALDE_VOL, BALDE_KG / float(DENS[_pa_tipo]))
	if vol >= cap - 0.0005:
		_show_toast("O balde já está cheio (uns %d kg). Mais que isso não dá para carregar." % int(BALDE_KG))
		return
	var add := minf(PAZADA, cap - vol)
	vol += add
	g.dur = [_pa_tipo, vol]
	var n: Node3D = g.node
	var fm: MeshInstance3D = n.get_node_or_null("carga")
	if fm == null:
		fm = MeshInstance3D.new()
		fm.name = "carga"
		n.add_child(fm)
	_update_balde_fill(fm, {"tipo": _pa_tipo, "vol": vol})
	Sons.play_at(self, "cavar", n.global_position + Vector3.UP * 0.3, -6.0, 1.3)
	_pa_full = false
	_pa_vol = 0.0
	if _pa_dirt:
		_pa_dirt.visible = false
	var kg := vol * float(DENS[_pa_tipo])
	_show_toast("Balde com %s: %d%% (%s kg)" % [_pa_tipo, int(vol / BALDE_VOL * 100.0), _kg(kg)])
	_act_check = 0.0


## A terra ou a argila dentro do balde: superfície de verdade no nível do que tem dentro.
## Terra: solta, granulada, com torrões e pedrinhas, sem brilho. Argila: bolos
## arredondados grudados uns nos outros, lisa, avermelhada e úmida (brilha um pouco).
## Cheio, faz um montinho acima da boca.
static var _fill_mats := {}

func _update_balde_fill(mi: MeshInstance3D, c: Dictionary) -> void:
	if mi == null:
		return
	if c.is_empty() or float(c.get("vol", 0.0)) <= 0.0:
		mi.mesh = null
		return
	var clay := str(c.tipo) == "argila"
	var f := clampf(float(c.vol) / BALDE_VOL, 0.0, 1.2)
	var level := 0.05 + minf(f, 1.0) * (Balde.H - 0.06)
	var dome := 0.015 + maxf(0.0, f - 0.7) * 0.12          # cheio: montinho no meio
	var nz := FastNoiseLite.new()
	nz.seed = 77 if clay else 33
	nz.frequency = 9.0 if not clay else 5.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 9
	var secs := 28
	var pts := []
	for ri in rings + 1:
		var row := []
		var rr := float(ri) / rings
		for k in secs:
			var a := TAU * k / secs
			var y := level + dome * (1.0 - rr * rr)
			var r_wall := Balde._r_at(y) - 0.012
			var x := cos(a) * r_wall * rr
			var z := sin(a) * r_wall * rr
			var n := nz.get_noise_2d(x * 40.0, z * 40.0)
			if clay:
				# bolos de argila: ondulado largo e liso, sobe um pouco na parede (grudada)
				y += n * 0.018 + maxf(0.0, rr - 0.85) * 0.06
			else:
				var n2 := nz.get_noise_2d(x * 140.0 + 9.0, z * 140.0)
				y += n * 0.012 + n2 * 0.006 + maxf(0.0, rr - 0.9) * 0.02
			row.append(Vector3(x, y, z))
		pts.append(row)
	var base := Color(0.62, 0.3, 0.16) if clay else Color(0.36, 0.25, 0.16)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 if clay else 5
	for ri in rings:
		for k in secs:
			var k2 := (k + 1) % secs
			var q := [pts[ri][k], pts[ri][k2], pts[ri + 1][k2], pts[ri + 1][k]]
			for idx in [0, 2, 1, 0, 3, 2]:
				var p: Vector3 = q[idx]
				var tone := nz.get_noise_2d(p.x * 90.0 + 3.0, p.z * 90.0) * (0.12 if clay else 0.22)
				st.set_color(base.lightened(maxf(tone, 0.0)).darkened(maxf(-tone, 0.0)))
				st.set_uv(Vector2(p.x, p.z) * 6.0)
				st.add_vertex(p)
	# torrões (terra) ou bolos (argila) em cima
	var lumps := 12 if not clay else 6
	for l in lumps:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.8) * (Balde._r_at(level) - 0.03)
		var cpos := Vector3(cos(a) * r, level + dome * (1.0 - pow(r / Balde.R_TOP, 2.0)) + 0.004, sin(a) * r)
		var size := rng.randf_range(0.01, 0.022) if not clay else rng.randf_range(0.022, 0.038)
		var lc := base.darkened(rng.randf_range(-0.1, 0.2))
		if not clay and rng.randf() < 0.3:
			lc = Color(0.3, 0.29, 0.27)           # pedrinha
			size *= 0.6
		_lump(st, cpos, size, lc, rng, clay)
	st.generate_normals()
	mi.mesh = st.commit()
	var key := "argila" if clay else "terra"
	if not _fill_mats.has(key):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		# argila vermelho-alaranjada (terracota úmida); terra marrom-escura
		m.albedo_color = Color(0.42, 0.3, 0.24) if clay else Color(0.55, 0.5, 0.45)
		var nt := NoiseTexture2D.new()
		var tn := FastNoiseLite.new()
		tn.frequency = 0.08 if not clay else 0.03
		nt.noise = tn
		nt.width = 128
		nt.height = 128
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 3.0 if not clay else 1.2
		m.normal_enabled = true
		m.normal_texture = nt
		m.roughness = 0.85 if clay else 1.0
		m.metallic_specular = 0.06 if clay else 0.02
		_fill_mats[key] = m
	mi.material_override = _fill_mats[key]


## Um torrão (pontudo, de terra) ou um bolo (redondo, de argila).
static func _lump(st: SurfaceTool, c: Vector3, s: float, col: Color, rng: RandomNumberGenerator, round: bool) -> void:
	var lat := 4
	var lon := 6
	var jit := []
	for i in (lat + 1) * lon:
		jit.append(rng.randf_range(0.75, 1.15) if not round else rng.randf_range(0.92, 1.05))
	for i in lat:
		for j in lon:
			var v := []
			for e in [[i, j], [i, j + 1], [i + 1, j + 1], [i + 1, j]]:
				var t: float = float(e[0]) / lat * PI
				var p: float = float(e[1] % lon) / lon * TAU
				var k: float = jit[int(e[0]) * lon + int(e[1]) % lon]
				v.append(c + Vector3(sin(t) * cos(p), cos(t) * 0.7, sin(t) * sin(p)) * s * k)
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.set_uv(Vector2(v[idx].x, v[idx].z) * 6.0)
				st.add_vertex(v[idx])


var _hstone: StandardMaterial3D

func _hand_stone_mat() -> Material:
	if _hstone == null:
		_hstone = StandardMaterial3D.new()
		_hstone.albedo_color = Color(0.24, 0.23, 0.21)
		_hstone.roughness = 0.9
	return _hstone


func _clay_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.9, 1.15, 1.0)        # a terra da pá fica avermelhada (argila)
	m.roughness = 0.6 
	return m


## Despejar: o balde vira para a frente e o que tem dentro cai (no chão, num monte,
## ou dentro de outro balde que esteja no chão bem na frente).
func _start_pour() -> void:
	if _balde_carga.is_empty() or _pour_t >= 0.0:
		return
	_pour_t = 0.0
	_ctx_btn.visible = false


func _update_pour(delta: float) -> void:
	if _pour_t < 0.0:
		return
	_pour_t += delta
	var tilt := smoothstep(0.0, 0.45, _pour_t) * (1.0 - smoothstep(1.1, 1.5, _pour_t))
	if _chop_pose:
		_chop_pose.pour = tilt
	if _pour_t >= 0.55 and not _balde_carga.is_empty():
		var c := _balde_carga
		var bi := _bucket_ahead()
		var to := _front(0.95)
		if bi >= 0:
			var g: Dictionary = _chao[bi]
			var gc := _carga_of(g)
			if not gc.is_empty() and str(gc.tipo) != str(c.tipo):
				_show_toast("O outro balde está com %s. Não misture." % gc.tipo)
				_pour_t = 1.1
				return
			var cap := minf(BALDE_VOL, BALDE_KG / float(DENS[c.tipo]))
			var room := cap - float(gc.get("vol", 0.0))
			var mv := minf(room, float(c.vol))
			if mv <= 0.0005:
				_show_toast("O outro balde está cheio.")
				_pour_t = 1.1
				return
			g.dur = [str(c.tipo), float(gc.get("vol", 0.0)) + mv]
			var fm: MeshInstance3D = (g.node as Node3D).get_node_or_null("carga")
			if fm == null:
				fm = MeshInstance3D.new()
				fm.name = "carga"
				(g.node as Node3D).add_child(fm)
			_update_balde_fill(fm, _carga_of(g))
			var left := float(c.vol) - mv
			_balde_carga = {} if left <= 0.0005 else {"tipo": c.tipo, "vol": left}
		else:
			_escav.dump(to, float(c.vol), str(c.tipo))
			_dirt(to)
			_balde_carga = {}
		_falling_lumps(_balde_fill.global_position + Vector3.UP * 0.05 if _balde_fill else to + Vector3.UP, to, str(c.tipo))
		Sons.play_at(self, "cavar", to, -2.0, 0.8)
		_update_balde_fill(_balde_fill, _balde_carga)
		_update_inventory()
	if _pour_t >= 1.5:
		_pour_t = -1.0
		if _chop_pose:
			_chop_pose.pour = 0.0
		_act_check = 0.0


## Torrões caindo da boca do balde até o chão (ou até o outro balde).
func _falling_lumps(from: Vector3, to: Vector3, tipo: String) -> void:
	var col := Color(0.55, 0.22, 0.1) if tipo == "argila" else Color(0.3, 0.2, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.8
	for k in 9:
		var mi := MeshInstance3D.new()
		mi.mesh = Lascar.cobble_mesh(300 + k, randf_range(0.02, 0.045))
		mi.material_override = mat
		add_child(mi)
		var start := from + Vector3(randf_range(-0.08, 0.08), randf_range(-0.05, 0.05), randf_range(-0.08, 0.08))
		var end := to + Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2))
		end.y = ground_at(end.x, end.z) + 0.02
		mi.global_position = start
		var tw := create_tween()
		tw.tween_interval(k * 0.035)
		tw.tween_property(mi, "global_position", end, 0.28 + randf() * 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_interval(0.15)
		tw.tween_callback(mi.queue_free)


## Põe o balde da mão no chão, na frente (com o que tiver dentro).
func _put_bucket_down() -> void:
	if item_qtd("balde") <= 0:
		equip("")
		return
	var to := _front(0.8)
	var dur := []
	if not _balde_carga.is_empty():
		dur = [str(_balde_carga.tipo), float(_balde_carga.vol)]
	remove_item("balde", 1)
	_add_ground("balde", 1, to.x, to.z, 0.0, dur)
	var g: Dictionary = _chao[_chao.size() - 1]
	(g.node as Node3D).rotation.y = _face
	_balde_carga = {}
	equip("")
	Sons.play_at(self, "baque", to, -14.0, 1.4)
	_update_inventory()


## Chão de verdade (com o que a pá cavou ou aterrou).
func ground_at(x: float, z: float) -> float:
	return _escav.ground_at(x, z) if _escav else surface_at(x, z)


## Barranco na frente (mais alto que o pulo): o personagem se agarra e sobe.
func _start_climb_out() -> bool:
	if _escav == null:
		return false
	var feet := _player.position.y
	var to := _front(0.55)
	var gh := ground_at(to.x, to.z)
	if gh - feet < 0.5 or gh - feet > 1.9:
		return false
	to = _front(0.75)
	to.y = ground_at(to.x, to.z)
	_climb = {"t": 0.0, "dur": 0.5 + (gh - feet) * 0.6, "from": _player.position, "to": to}
	return true


## Pulo: sobe uns 60 cm (dá para passar por cima de uma tora ou subir nela).
func _jump() -> void:
	if _air or _chopping or _digging or not _carry.is_empty() or _crouch_job != "" or not _climb.is_empty():
		return
	if _start_climb_out():
		return
	_air = true
	_vy = 4.2


## Toque no botão "Cortar": uma machadada (se já está no meio de uma, guarda a próxima).
func _start_chop() -> void:
	if _mao == "balde":
		_put_bucket_down()
		return
	if _mao == "serra":
		# serra: um toque começa a serrar (vai e vem sozinho), outro toque para
		if _sawing:
			_stop_saw()
		elif not _work.is_empty() and str(_work.get("stage", "")) == "pronto":
			_begin_saw()
		return
	if (_mao != "machado" and _mao != "cavadeira" and _mao != "pa") or _arvores == null:
		return
	if _chopping:
		if _swing_on:
			_swing_queued = true
		else:
			_begin_swing()
		return
	if _mao == "cavadeira" or _mao == "pa":
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
	if _mao == "machado" and _board_ahead() >= 0:
		_start_board_chop(_board_ahead())
		return
	if _bur_fell_ready():
		if _digging:
			_cancel_dig()
		_chop_bur = _bur.p
		_chop_tree = null
		_chop_log = {}
		_chop_branch = {}
		_chopping = true
		_swing_queued = false
		_play("Idle", 0.5)
		if _chop_pose:
			_chop_pose.vertical = false
			_chop_pose.ready_pose = true
		_begin_swing()
		return
	var t = _arvores.nearest_standing(_player.position, 1.3)
	_chop_log = {}
	_chop_branch = {}
	if t == null:
		var br := _branch_target()
		if not br.is_empty():
			_chop_branch = br
			_branch_hits = 0
		else:
			if _buck_go_cut.is_empty():
				# primeiro escolhe onde cortar (o anel na tora)
				_buck_open()
				return
			_chop_log = _buck_go_cut
			_buck_go_cut = {}
	if _digging:
		_cancel_dig()
	_chop_tree = t
	_chopping = true
	if _chop_pose:
		_chop_pose.vertical = not _chop_log.is_empty() or not _chop_branch.is_empty()
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
	var tool := _mao
	_chop_hit_now()
	wear(tool)               # cada machadada ou cavada gasta a ferramenta


func _chop_hit_now() -> void:
	if not _chop_bur.is_empty():
		_bur_chop_hit()
		return
	if not _chop_branch.is_empty():
		var at: Vector3 = _chop_branch.point
		_chips(at)
		Sons.play_at(self, "machado", at, -2.0, 1.12)
		if _chop_branch.kind == "arvore":
			# 3 cortes em cada galho: nas folhas, no meio e no toco
			var tp: Array = _chop_branch.p
			var res: Dictionary = _arvores.branch_hit(tp, int(_chop_branch.i), float(_chop_branch.t), int(_chop_branch.to))
			if not res.is_empty():
				_fall_branch_bits(tp, res)
				_cancel_chop()
		else:
			if _galhos.chop(int(_chop_branch.i)):
				_show_toast("Galho cortado em 2. Agora dá para pegar.")
				_cancel_chop()
		return
	if _chop_hole and _mao == "pa":
		_pa_hit()
		_cancel_chop()
		return
	if _chop_hole:
		var at := _front(0.62)
		var d: float = _buracos.dig_at(at)
		_dirt(at)
		Sons.play_at(self, "cavar", at)
		_show_toast("Buraco com %d cm de fundura" % int(round(d * 100.0)) if d < Buracos.MAX_DEPTH else "O buraco já está bem fundo (80 cm)")
		return
	if bool(_chop_log.get("tabua", false)):
		_board_hit()
		return
	if _chop_log.has("solta"):
		var fl: Dictionary = _chop_log.solta
		if not _arvores.free_logs.has(fl):
			_cancel_chop()
			return
		var at: Vector3 = _chop_log.point
		_chips(at)
		Sons.play_at(self, "machado", at, 0.0, 0.95)
		var cm: Array = fl.get("corte_m", [])
		if cm.is_empty() or absf(float(cm[0]) - float(_chop_log.u)) > 0.01:
			cm = [float(_chop_log.u), 0]
		cm[1] = int(cm[1]) + 1
		fl["corte_m"] = cm
		var need := 1 if teste else clampi(int(round(2.0 + float(_chop_log.r) * 14.0)), 2, 9)
		if int(cm[1]) >= need:
			fl.erase("corte_m")
			_arvores.split_free_log(fl, float(_chop_log.u))
			Sons.play_at(self, "estalo", at, -2.0, 0.9)
			_show_toast("Tora cortada em dois pedaços!")
			_cancel_chop()
		else:
			_show_toast("Cortando: %d de %d machadadas" % [int(cm[1]), need])
		return
	if not _chop_log.is_empty():
		var lp: Array = _chop_log.p
		var done: bool = _arvores.buck_hit(lp, float(_chop_log.h))
		_chips(_chop_log.point)
		Sons.play_at(self, "machado", _chop_log.point, 0.0, 0.92)
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
	Sons.play_at(self, "machado", _arvores.cut_point(t))
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
	_chop_bur = {}
	_chopping = false
	_swing_on = false
	_swing_queued = false
	_chop_tree = null
	_chop_log = {}
	_chop_branch = {}
	_chop_hole = false
	if _chop_pose:
		_chop_pose.digging = false
		_chop_pose.vertical = false
		_chop_pose.down_hit = -42.0
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
	if _sawing:
		if amount > 0.12:
			_stop_saw()
		else:
			amount = 0.0
	if not _knap.is_empty() or not _vine.is_empty() or not _climb.is_empty() or not _split.is_empty():
		amount = 0.0
	if _crouch_job != "":
		amount = 0.0           # abaixado pegando ou largando a tora
	if not _coop.is_empty() and (not bool(_coop.lider) or float(_coop.anim) > 0.0):
		amount = 0.0           # carregando junto: quem vai atrás segue quem vai na frente
	if _walking and amount > 0.12:
		_walking = false       # o jogador mexeu no controle: para de ir sozinho
		_work = {}
		if _walk_next == "colocar":
			_walk_next = ""
	if _chop_pose:
		_chop_pose.moving = amount > 0.12 or _walking
		_chop_pose.in_air = _air
	var p := _player.position
	if not _desf.is_empty():
		_desf_move(delta)
		return
	if not _coop.is_empty() and not bool(_coop.lider) and float(_coop.anim) <= 0.0:
		var e = _rede.estados.get(int(_coop.pid)) if _rede else null
		if e != null:
			var lp: Array = e.p
			var ly := float(e.y)
			var fwd2 := Vector3(-sin(ly), 0, -cos(ly))
			var tgt := Vector3(float(lp[0]), 0, float(lp[2])) - fwd2 * float(_coop.sep)
			var mv2 := Vector2(tgt.x - p.x, tgt.z - p.z)
			var stp2 := minf(mv2.length(), 4.0 * delta)
			if mv2.length() > 0.01:
				p.x += mv2.x / mv2.length() * stp2
				p.z += mv2.y / mv2.length() * stp2
			_face = lerp_angle(_face, ly, minf(1.0, delta * 8.0))
			_yaw = _face
			_play("Walk" if mv2.length() > 0.05 else "Idle", 0.8)
	var cell := Vector2i(int(p.x / CELL), int(p.z / CELL))
	var depth := 0.0
	if _water_level.size() == MundoSim.W * MundoSim.H and cell.x >= 0 and cell.y >= 0 and cell.x < MundoSim.W and cell.y < MundoSim.H:
		depth = maxf(0.0, _water_level[cell.y * MundoSim.W + cell.x] - height_at(p.x, p.z))
	depth = maxf(depth, hole_water_depth(p.x, p.z))
	var water_slow := lerpf(1.0, 0.4, clampf(depth / 0.8, 0.0, 1.0))
	if amount > 0.12:
		# anda na direção para onde a câmera está olhando
		var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
		var right := Vector3(cos(_yaw), 0, -sin(_yaw))
		var move := (right * dir.x - fwd * dir.y).normalized()
		var running := amount > 0.85 and _carry.is_empty()
		if _mao == "balde" and not _balde_carga.is_empty() and float(_balde_carga.vol) * float(DENS.get(_balde_carga.tipo, 1500.0)) >= 8.0:
			running = false      # com balde pesado não dá para correr
		var sp := (RUN_SPEED if running else WALK_SPEED) * water_slow
		if not _carry.is_empty():
			sp *= lerpf(0.9, 0.4, clampf(_carry_kg / 300.0, 0.0, 1.0))   # tora pesada: anda devagar
			if _drag:
				sp *= 0.8                                              # arrastando: mais devagar ainda
		if not _coop.is_empty():
			sp *= lerpf(0.75, 0.45, clampf(float(_coop.kg) / COOP_KG, 0.0, 1.0))   # devagar, junto com o outro
		if _mao == "balde" and not _balde_carga.is_empty():
			var bkg := float(_balde_carga.vol) * float(DENS.get(_balde_carga.tipo, 1500.0))
			sp *= lerpf(1.0, 0.72, clampf(bkg / BALDE_KG, 0.0, 1.0))   # balde pesado: mais devagar
		p += move * sp * delta
		p.x = clampf(p.x, 1.0, MundoSim.W * CELL - 1.0)
		p.z = clampf(p.z, 1.0, MundoSim.H * CELL - 1.0)
		_face = _yaw          # primeira pessoa: o corpo olha para onde a câmera olha
		_play("Run" if running else "Walk", water_slow)
	elif _walking and not _chopping and _crouch_job == "":
		# indo sozinho até o lugar do trabalho (a forquilha ou a ponta da tora)
		var to := Vector2(_walk_target.x - p.x, _walk_target.z - p.z)
		_walk_t += delta
		if to.length() < 0.08 or _walk_t > 6.0:
			_walking = false
			_play("Idle")
			_walk_arrived()
		else:
			var stp := minf(to.length(), WALK_SPEED * 0.8 * delta)
			p.x += to.x / to.length() * stp
			p.z += to.y / to.length() * stp
			_face = lerp_angle(_face, atan2(-to.x, -to.y), minf(1.0, delta * 10.0))
			_play("Walk", 0.8)
	elif not _digging:
		_play("Idle")
	if _chopping and not _chop_branch.is_empty():
		var bp: Vector3 = _chop_branch.point
		var tl := Vector2(bp.x - p.x, bp.z - p.z)
		_face = lerp_angle(_face, atan2(-tl.x, -tl.y), minf(1.0, delta * 10.0))
		if tl.length() > 0.7:
			var stp := minf(tl.length() - 0.65, delta * 1.5)
			p.x += tl.x / tl.length() * stp
			p.z += tl.y / tl.length() * stp
	elif (_chopping or _sawing) and not _chop_log.is_empty():
		# de lado para a tora, de frente para o ponto do corte
		var axp: Vector3 = _chop_log.axis
		var al: Vector3 = _chop_log.along
		var rel := Vector3(p.x - axp.x, 0, p.z - axp.z)
		var side := rel - Vector3(al.x, 0, al.z).normalized() * rel.dot(Vector3(al.x, 0, al.z).normalized())
		if side.length() < 0.05:
			side = Vector3(al.z, 0, -al.x)
		var want_pos := axp + side.normalized() * float(_chop_log.get("dist", float(_chop_log.r) + 0.42))
		var mv := Vector2(want_pos.x - p.x, want_pos.z - p.z)
		if mv.length() > 0.04:
			var stp := minf(mv.length(), delta * 1.5)
			p.x += mv.x / mv.length() * stp
			p.z += mv.y / mv.length() * stp
		var tl := Vector2(axp.x - p.x, axp.z - p.z)
		_face = lerp_angle(_face, atan2(-tl.x, -tl.y), minf(1.0, delta * 10.0))
	elif _chopping and not _chop_bur.is_empty():
		var tob := Vector2(float(_chop_bur.x) - p.x, float(_chop_bur.z) - p.z)
		_face = lerp_angle(_face, atan2(-tob.x, -tob.y), minf(1.0, delta * 10.0))
		var wantb: float = _buritis.trunk_r(_chop_bur) + 0.72
		var distb := tob.length()
		if distb > 0.01 and absf(distb - wantb) > 0.05:
			var stepb := clampf(distb - wantb, -delta * 1.5, delta * 1.5)
			p.x += tob.x / distb * stepb
			p.z += tob.y / distb * stepb
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
	if _bacabas:
		p = _bacabas.push_out(p)          # nem o tronco das palmeiras
	if _buritis:
		p = _buritis.push_out(p)
	if _apoios:
		p = _apoios.push_out(p)           # nem as forquilhas e a tora em cima delas
	if _constr or _cupins or _maq:
		# nem as paredes e vigas da construção, nem os cupinzeiros; em passinhos, para
		# não pular a tábua fina num quadro lento
		var prev := _player.position
		var mv := Vector2(p.x - prev.x, p.z - prev.z).length()
		var nsub := clampi(int(ceil(mv / 0.06)), 1, 12)
		var q := prev
		for k in nsub:
			q.x += (p.x - prev.x) / nsub
			q.z += (p.z - prev.z) / nsub
			if _constr:
				q = _constr.push_out(q, feet)
			if _cupins:
				q = _cupins.push_out(q, feet)
			if _maq:
				q = _maq.push_out(q)
		p.x = q.x
		p.z = q.z
	if _escav and not _air:
		# barranco cavado: parede alta não dá para subir andando
		var gnew: float = ground_at(p.x, p.z)
		var run := Vector2(p.x - _player.position.x, p.z - _player.position.z).length()
		var rise := gnew - feet
		if rise > 0.45 or (rise > 0.1 and rise / maxf(run, 0.001) > 1.2):
			p.x = _player.position.x
			p.z = _player.position.z
	# chão: o terreno ou o topo de uma tora (dá para subir pulando e andar em cima)
	var ground := height_at(p.x, p.z) - minf(depth, 0.9) * 0.5
	if _escav:
		var dv: float = _escav.delta_at(p.x, p.z)
		if absf(dv) > 0.001:
			ground = surface_at(p.x, p.z) + dv - minf(depth, 0.9) * 0.5    # chão cavado ou aterrado
	if _arvores:
		var sup: float = _arvores.support_y(p.x, p.z)
		if sup > ground and feet >= sup - 0.2:
			ground = sup
	if _constr:
		var sup2: float = _constr.support_y(p.x, p.z, feet)
		if sup2 > ground and feet >= sup2 - 0.32:
			ground = sup2                 # andando no assoalho
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
	if not _climb.is_empty():
		# escalando a parede da cova: sobe, e no fim passa por cima da borda
		_climb.t = float(_climb.t) + delta
		var u := clampf(float(_climb.t) / float(_climb.dur), 0.0, 1.0)
		var a: Vector3 = _climb.from
		var b: Vector3 = _climb.to
		var up := smoothstep(0.0, 0.8, u)
		var out := smoothstep(0.7, 1.0, u)
		p = Vector3(lerpf(a.x, b.x, out), lerpf(a.y, b.y + 0.05, up), lerpf(a.z, b.z, out))
		_air = false
		_vy = 0.0
		if u >= 1.0:
			p.y = b.y
			_climb = {}
	# passos: um som a cada passada (na água, respingo e onda)
	var moved := Vector2(p.x - _player.position.x, p.z - _player.position.z).length()
	var landed := _air == false and _player.position.y > p.y + 0.15
	if not _air:
		_step_dist += moved
		# andando ~1,9 passos por segundo; correndo ~3 (passada mais longa)
		var running := moved / maxf(delta, 0.001) > 3.0
		var stride := 0.66 if not running else 1.7
		if _step_dist >= stride or landed:
			_step_dist = 0.0
			_footstep(p, depth, landed, running)
	_player.position = p
	# primeira pessoa: livre, o corpo vira para onde a câmera olha; trabalhando (cortar,
	# serrar, ir até o lugar...) é o corpo que manda e a câmera vai junto
	if _chopping or _sawing or _walking or _digging or _crouch_job != "" or not _climb.is_empty():
		_yaw = lerp_angle(_yaw, _face, minf(1.0, delta * 8.0))
	else:
		_face = _yaw
	_player.rotation.y = _face

	if not _knap.is_empty():
		_knap_camera(delta)
		return
	if not _vine.is_empty():
		_vine_camera()
		return
	_fp_camera(delta, moved)


## Eixo do osso (±X, ±Y, ±Z) que mais aponta para "want".
static func _best_axis(b: Basis, want: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var bd := -2.0
	for ax in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
		var d: float = (b * ax).normalized().dot(want)
		if d > bd:
			bd = d
			best = ax
	return best


## Primeira pessoa: a câmera fica nos olhos do personagem (segue a cabeça dele, que
## abaixa, anda e balança junto) e as mãos dele aparecem na frente.
func _fp_camera(delta: float, moved: float) -> void:
	if _sub_ui:
		_sub_ui.queue_redraw()        # o olho e os losangos do buriti acompanham a câmera
	var body := _player.global_transform.basis
	var bfwd := -body.z
	var eye := _player.global_position + Vector3(0, 1.62, 0) + bfwd * 0.1
	if _skel and _head_bone >= 0:
		# os olhos ficam presos na cabeça (seguem ela inclinando no passo, sem atraso):
		# assim a câmera nunca fica atrás ou em cima da própria cabeça
		var hg: Transform3D = _skel.global_transform * _skel.get_bone_global_pose(_head_bone)
		var hb := hg.basis.orthonormalized()
		if _head_axes.is_empty():
			_head_axes = [_best_axis(hb, bfwd), _best_axis(hb, Vector3.UP)]
		var hf: Vector3 = (hb * _head_axes[0]).normalized()
		var hu: Vector3 = (hb * _head_axes[1]).normalized()
		eye = hg.origin + hu * 0.1 - hf * 0.03        # dentro da cabeça (que some para a câmera): as mãos alcançam a frente da vista
		# abaixado fazendo algo: os olhos ficam na frente do rosto (no plano), assim o
		# peito e a barriga ficam para trás da câmera
		if _busy_f > 0.01:
			var flat := Vector3(-sin(_yaw), 0, -cos(_yaw))
			eye = eye.lerp(hg.origin + Vector3.UP * 0.1 + flat * 0.24, _busy_f)
	# olhando para baixo: os olhos vão para a frente do peito (como quem inclina a
	# cabeça), senão a câmera enxerga o corpo por dentro
	var down := 0.0 if (_sawing or _digging or _chopping or not _split.is_empty()) else clampf((_pitch - 0.3) / 0.8, 0.0, 1.0)
	if down > 0.0:
		var flat2 := Vector3(-sin(_yaw), 0, -cos(_yaw))
		eye += flat2 * down * 0.24 * (1.0 - _busy_f) - Vector3.UP * down * 0.06
	_eye_smooth = eye
	# o que está acontecendo: abaixado pegando/pondo, cavando, modelando...
	var busy: bool = _crouch_job != "" or _digging or (_chop_pose != null and _chop_pose.crouch > 0.05)
	_busy_f = move_toward(_busy_f, 1.0 if busy else 0.0, delta * 4.0)
	if _chop_pose:
		_chop_pose.hide_head = true          # primeira pessoa: a própria cabeça nunca aparece
		# com ferramenta na mão os braços não aparecem (só a ferramenta, segura por baixo da tela)
		_chop_pose.hide_arms = not _desf.is_empty() or _mao in ["machado", "cavadeira", "serra", "pedra", "pa", "balde", "marreta", "faca"] and _vine.is_empty()
	for m in _body_mats:
		(m as BaseMaterial3D).distance_fade_min_distance = lerpf(0.27, 0.5, maxf(_busy_f, down))
		(m as BaseMaterial3D).distance_fade_max_distance = lerpf(0.34, 0.6, maxf(_busy_f, down))
	if _crouch_job != "":
		_pitch = lerpf(_pitch, 0.95, minf(1.0, delta * 4.0))     # olha para onde as mãos vão
	# trabalhando, o olhar desce para onde as mãos estão (o golpe, a serra, a pá)
	var work := -1.0
	if _sawing:
		work = 0.95
	elif _digging:
		work = 0.9
	elif _chopping:
		work = 0.85 if (not _chop_log.is_empty() or not _chop_branch.is_empty()) else 0.6
	if work > -1.0:
		_pitch = lerpf(_pitch, work, minf(1.0, delta * 3.0))
	var cam_basis := Basis.from_euler(Vector3(-_pitch, _yaw, 0.0))
	_cam.global_transform = Transform3D(cam_basis, _eye_smooth)
	if _chop_pose:
		var speed := moved / maxf(delta, 0.001)
		_bob_t += delta * (6.0 + speed * 1.6) if speed > 0.3 else 0.0
		var amp := clampf(speed / 4.0, 0.0, 1.0) * 0.018
		_chop_pose.fp_eye = _eye_smooth
		_chop_pose.fp_basis = cam_basis
		_chop_pose.fp_bob = Vector2(sin(_bob_t) * amp, absf(cos(_bob_t)) * amp * 0.8)


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
	if not _desf.is_empty() and _desf_input(e):
		return
	if not _split.is_empty() and _split_input(e):
		return
	if not _knap.is_empty():
		_knap_input(e)
		return
	if not _vine.is_empty():
		_vine_input(e)
		return   # modelando pedra: o personagem não anda nem gira a câmera
	if _proj_ui != null:
		return   # escolhendo o projeto
	if not _pin.is_empty() and _pin_input(e):
		return
	if _bag_ui == null and _craft_ui == null and _cal == null and _work_menu == null and _bur_input(e):
		return
	if _cal != null or _bag_ui != null or _craft_ui != null or _work_menu != null:
		return   # com o calendário, a mochila ou o craft aberto, o toque não anda nem gira a câmera
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if e is InputEventScreenTouch:
		if e.pressed:
			# toque em botão de ação não gira a câmera (dá para tocar "Cortar" várias vezes)
			for btn in [_dig_btn, _chop_btn, _seed_btn, _pick_btn, _jump_btn, _log_btn, _vine_btn, _plant_btn, _ctx_btn, _work_btn, _place_btn, _rot_btn, _store_btn, _saw_ctrl, _bld_pad, _bld_btn, _maq_stop] + _bld_btns + _mark_btns + ([_trim.ctrl] if _trim.has("ctrl") else []) + ([_maq_op.ctrl] if _maq_op.has("ctrl") else []) + _sub_btns:
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
			_pitch = clampf(_pitch + d.y * 0.004, -1.3, 1.35)


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


## Água nos buracos cavados: a chuva enche, o sol seca, o mar entra nos que passam do nível dele.
func _tick_hole_water(delta: float) -> void:
	if _escav == null:
		return
	_escav_timer -= delta
	if _escav_timer > 0.0:
		return
	_escav_timer = 1.0
	var hrs: float = float(sim.steps - _escav_steps) * MundoSim.STEP_HOURS
	_escav_steps = sim.steps
	if hrs < 0.0:
		hrs = 0.0
	var rain: float = sim.rain_mmh if sim.raining else 0.0
	var evap: float = 0.02 if sim.raining else lerpf(0.6, 0.25, sim.wetness()) * (0.3 + 1.4 * sim.sun())
	evap += lerpf(1.6, 0.15, sim.wetness())   # a terra seca chupa a água do fundo; na chuva ela já está encharcada
	_escav.water_tick(minf(hrs, 24.0 * 30.0), rain, evap)


## Profundidade da água dos buracos cavados no ponto.
func hole_water_depth(x: float, z: float) -> float:
	if _escav == null:
		return 0.0
	var L: float = _escav.water_level_at(x, z)
	if L < -1e8:
		return 0.0
	return maxf(0.0, L - _escav.ground_at(x, z))


## Cor de vértice da água: R barro, G chão acima da água (beirada), A fundura.
static func _wcol(murk: float, depth: float) -> Color:
	return Color(murk, clampf(-depth / 0.5, 0.0, 1.0), 1.0, clampf(depth / 8.0, 0.0, 1.0))


## O mar em volta da ilha: vai do fim do mapa até o horizonte, com o fundo de areia embaixo.
func _build_ocean() -> void:
	var sea := MundoSim.SEA * HS
	var bed := MundoSim.SEA_FLOOR * HS
	var MW := MundoSim.W * CELL
	var MH := MundoSim.H * CELL
	var F := 6000.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bst := SurfaceTool.new()
	bst.begin(Mesh.PRIMITIVE_TRIANGLES)
	# quatro faixas em volta do mapa (sem cobrir o mapa, que tem a sua própria água)
	var rects := [[-F, -F, MW + F, 0.0], [-F, MH, MW + F, MH + F], [-F, 0.0, 0.0, MH], [MW, 0.0, MW + F, MH]]
	for r in rects:
		var x0: float = r[0]; var z0: float = r[1]; var x1: float = r[2]; var z1: float = r[3]
		var q := [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]
		for t in [0, 2, 1, 0, 3, 2]:
			st.set_color(_wcol(0.0, sea - bed))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(q[t].x, sea, q[t].y))
			bst.set_normal(Vector3.UP)
			bst.add_vertex(Vector3(q[t].x, bed - 0.05, q[t].y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.75, 0.65, 0.45)
	bmat.roughness = 1.0
	var bmi := MeshInstance3D.new()
	bmi.mesh = bst.commit()
	bmi.material_override = bmat
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bmi)


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
				if edge and absf(lv - MundoSim.SEA * HS) > 0.06:
					lv = minf(lv, _corner_h[y * cw + x])   # (o mar não: a areia corta a beirada dele)
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
			var d00 := _wcol(cmurk[c00], corner[c00] - _corner_h[c00])
			var d10 := _wcol(cmurk[c10], corner[c10] - _corner_h[c10])
			var d01 := _wcol(cmurk[c01], corner[c01] - _corner_h[c01])
			var d11 := _wcol(cmurk[c11], corner[c11] - _corner_h[c11])
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


## Bandas de versões antigas (eram enfeite no chão): viram pedaços de tora de verdade,
## que dá para pegar, apoiar, rachar de novo e fincar.
func _convert_bandas() -> void:
	var keep := []
	var any := false
	for g in _chao:
		if str(g.id) != "banda":
			keep.append(g)
			continue
		var dl: Array = g.get("dur", [])
		var L := float(dl[0]) if dl.size() >= 4 else 1.5
		var ra := float(dl[1]) if dl.size() >= 4 else 0.12
		var rb := float(dl[2]) if dl.size() >= 4 else 0.1
		var yaw := float(dl[3]) if dl.size() >= 4 else 0.0
		var halves: Array = Arvores.split_sec(Arvores.circle_sec(), false)
		var fl := {"cil": {"L": L, "ra": ra, "rb": rb}, "sec": halves[0], "v": 0, "s": 1.0, "h0": 0.0, "h1": 1.0,
			"bot": {}, "top": {}, "pos": [float(g.x), 0.0, float(g.z)], "yaw": yaw, "dia": _arvores.last_day}
		fl.pos[1] = height_at(float(g.x), float(g.z)) + ra * 0.5
		_arvores.free_logs.append(fl)
		if g.node:
			(g.node as Node3D).queue_free()
		any = true
	if any:
		_chao = keep
		_arvores._rebuild_logs()


# ================== RACHAR A TORA COM CUNHAS ==================
# Na tora apoiada nas forquilhas: o jogador põe 3 cunhas (uma perto de cada ponta e uma
# no meio), com o fio virado para a madeira; depois bate nelas com a marreta, um pouco
# em cada (nenhuma pode entrar muito mais que as outras), com a barrinha de acerto.
# Vermelho: a marreta pega torto e a cunha quebra (tem que pôr outra). Quando as três
# entram até o fim, a tora abre no comprido em duas bandas.

const SPLIT_U := [0.15, 0.5, 0.85]
const SPLIT_LEAD := 0.34          # o quanto uma cunha pode estar à frente das outras


const SPLIT_MIN_T := 0.05        # a cunha não tira tábua mais fina que isso (m)


## Grossura da metade mais fina, se rachar essa madeira ao meio com as cunhas.
func _split_thickness(fl: Dictionary) -> float:
	if not fl.has("sec"):
		return _arvores.free_log_radius(fl)        # tora redonda: cada metade tem o raio
	var r: float = _arvores._cil_r(fl, 0.5)
	var th := 1e9
	for h in Arvores.split_sec(fl.sec, bool(fl.get("em_pe", false))):
		var mn := 1e9
		var mx := -1e9
		for q in h.pts:
			mn = minf(mn, float(q[1]))
			mx = maxf(mx, float(q[1]))
		th = minf(th, (mx - mn) * r)
	return th


func _split_begin() -> void:
	var i: int = _apoios.nearest_rested(_player.position, 1.8)
	if i < 0:
		return
	if item_qtd("cunha") < 3 and not teste:
		_show_toast("Precisa de 3 cunhas de pedra (tem %d). Faça modelando pedra." % item_qtd("cunha"))
		return
	if item_qtd("marreta") < 1 and not teste:
		_show_toast("Precisa de uma marreta (pedra de marreta + galho + 2 cipós).")
		return
	var fl0: Dictionary = _apoios.rested[i].log
	var th := _split_thickness(fl0)
	if th < SPLIT_MIN_T:
		_show_toast("Fina demais para rachar com cunha: cada metade ficaria com %d cm. A cunha só tira tábua de %d cm ou mais (para tábua fina, serre um pedaço e rache com o machado)." % [roundi(th * 100.0), roundi(SPLIT_MIN_T * 100.0)])
		return
	equip("")                      # as mãos livres para pôr as cunhas
	var spots := []
	for u in SPLIT_U:
		spots.append({"u": u, "placed": false, "depth": 0.0, "node": null})
	_split = {"i": i, "stage": "cunhas", "spots": spots, "sel": -1, "go": -1, "anim": -1.0, "kind": "", "ok": false,
		"crack": null, "t": 0.0, "speed": 0.4, "gw": 0.3, "gc": 0.5, "fired": false}
	_split_rng.randomize()
	_split_new_timing()
	_build_split_ui()
	if teste:
		_split_finish()          # modo de teste: racha na hora
		return
	_show_toast("Toque nos 3 lugares marcados na tora para pôr as cunhas.")


func _split_geo(u: float) -> Dictionary:
	var i := int(_split.i)
	var inf: Dictionary = _apoios.info(i)
	var fl: Dictionary = _apoios.rested[i].log
	var rad: float = _arvores.free_log_radius_at(fl, clampf(u, 0.02, 0.98))
	var axis: Vector3 = inf.center + inf.dir * (u - 0.5) * float(inf.L)
	return {"top": axis + Vector3.UP * rad, "axis": axis, "rad": rad, "dir": inf.dir}


func _split_new_timing() -> void:
	_split.speed = _split_rng.randf_range(0.3, 0.55)
	_split.gw = _split_rng.randf_range(0.2, 0.32)
	_split.gc = _split_rng.randf_range(0.25, 0.75)
	_split.t = _split_rng.randf() * 4.0


func _split_marker() -> float:
	var x := fmod(float(_split.t) * float(_split.speed), 2.0)
	return x if x <= 1.0 else 2.0 - x


func _split_busy() -> bool:
	if _split.is_empty():
		return false
	return _walking or float(_split.anim) >= 0.0


## Toque na tela: escolhe um dos lugares das cunhas. Devolve true se usou o toque.
func _split_input(e: InputEvent) -> bool:
	var pos := Vector2.INF
	if e is InputEventScreenTouch and e.pressed:
		pos = e.position
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
	if pos == Vector2.INF:
		return false
	var spots: Array = _split.spots
	for k in spots.size():
		var w: Vector3 = _split_geo(float(spots[k].u)).top
		if _cam.is_position_behind(w):
			continue
		if pos.distance_to(_cam.unproject_position(w)) < 80.0:
			_split_pick(k)
			return true
	return false


func _split_pick(k: int) -> void:
	if _split_busy():
		return
	var sp: Dictionary = _split.spots[k]
	if not bool(sp.placed):
		if item_qtd("cunha") <= 0:
			_show_toast("Acabaram as cunhas. Faça outra modelando pedra.")
			return
	elif str(_split.stage) == "cunhas":
		_show_toast("Já tem cunha aqui.")
		return
	_split.go = k
	var g := _split_geo(float(sp.u))
	var spot := _side_spot(int(_split.i), g.top, 0.72)
	if Vector2(spot.x - _player.position.x, spot.z - _player.position.z).length() < 0.15:
		_split_arrived()
	else:
		_walk_to(spot, "rachar")


## Olha para o ponto (vira o corpo e a câmera).
func _split_aim(at: Vector3) -> void:
	_face_to(at)
	_yaw = _face
	var eye := _player.global_position + Vector3.UP * 1.6
	var hd := Vector2(at.x - eye.x, at.z - eye.z).length()
	_pitch = clampf(atan2(eye.y - at.y, maxf(hd, 0.1)) - 0.08, -0.4, 1.2)


func _split_arrived() -> void:
	var k := int(_split.go)
	if k < 0:
		return
	var sp: Dictionary = _split.spots[k]
	var g := _split_geo(float(sp.u))
	_split_aim(g.top)
	if not bool(sp.placed):
		# põe a cunha com a mão: estica o braço até o lugar, encaixa o fio na madeira
		equip("")
		_split.anim = 0.0
		_split.kind = "pôr"
		if _chop_pose:
			_chop_pose.reach_on = true
			_chop_pose.reach_grip = true
			_chop_pose.reach_target = g.top + Vector3.UP * 0.08
		return
	_split.sel = k
	_split_ready_hammer(g)


func _split_ready_hammer(g: Dictionary) -> void:
	if item_qtd("marreta") <= 0:
		_show_toast("A marreta quebrou. Faça outra para continuar.")
		return
	if _mao != "marreta":
		equip("marreta")
	if _chop_pose:
		var top_h: float = g.top.y - _player.global_position.y
		_chop_pose.vertical = true
		_chop_pose.down_hit = lerpf(-42.0, -14.0, clampf(top_h / 0.95, 0.0, 1.0))
		_chop_pose.ready_pose = true
		_chop_pose.swinging = false


func _split_hit() -> void:
	if _split.is_empty() or str(_split.stage) != "bater" or _split_busy():
		return
	var k := int(_split.sel)
	if k < 0 or not bool(_split.spots[k].placed):
		_show_toast("Toque primeiro numa cunha da tora.")
		return
	if _mao != "marreta":
		_split_ready_hammer(_split_geo(float(_split.spots[k].u)))
		if _mao != "marreta":
			return
	_split.t = float(_split.t) - 0.06       # o toque chega um pouquinho atrasado
	var m := _split_marker()
	_split.frozen = m
	var d := absf(m - float(_split.gc)) - float(_split.gw) * 0.5
	if d > 0.01 and d <= KNAP_EDGE:
		_show_toast("Quase! Bata no verde.")
		return
	_split.ok = d <= 0.01
	_split.anim = 0.0
	_split.kind = "bater"
	_split.fired = false
	if _chop_pose:
		_chop_pose.swinging = true
		_chop_pose.phase = 0.0


func _update_split(delta: float) -> void:
	if _split.is_empty():
		return
	for b in [_dig_btn, _chop_btn, _seed_btn, _pick_btn, _log_btn, _vine_btn, _plant_btn, _ctx_btn, _work_btn, _jump_btn]:
		if b:
			b.visible = false
	if int(_split.i) >= _apoios.rested.size():
		_split_end()
		return
	var a := float(_split.anim)
	if a >= 0.0:
		a += delta
		_split.anim = a
		if str(_split.kind) == "pôr":
			if a >= 0.9:
				_split_place_done()
		else:
			var ph := a / 0.85
			if _chop_pose:
				_chop_pose.phase = minf(ph, 1.0)
			if ph >= Corte.ChopPose.HIT_AT and not bool(_split.fired):
				_split.fired = true
				_split_impact()
			if ph >= 1.0:
				_split.anim = -1.0
				if _chop_pose:
					_chop_pose.swinging = false
				if not _split.is_empty():
					_split_new_timing()
	elif str(_split.stage) == "bater":
		_split.t = float(_split.t) + delta
	if _split.is_empty():
		return
	_split_update_visuals()
	if _split_ui:
		for n in ["mk", "tb"]:
			var c := _split_ui.find_child(n, true, false) as Control
			if c:
				c.queue_redraw()
		var hit := _split_ui.find_child("hit", true, false) as Control
		if hit:
			hit.visible = str(_split.stage) == "bater"
		var il := _split_ui.find_child("il", true, false) as Label
		if il:
			if str(_split.stage) == "cunhas":
				il.text = "RACHAR A TORA\nToque nos 3 lugares marcados para pôr as cunhas (o fio vai virado para a madeira)."
			else:
				il.text = "RACHAR A TORA\nToque numa cunha e em BATER com o marcador no VERDE. Bata um pouco em cada. Vermelho: a cunha quebra!"
		var pl := _split_ui.find_child("pl", true, false) as Label
		var bar := _split_ui.find_child("bar", true, false) as ProgressBar
		var pr := _split_progress()
		if pl:
			pl.text = "Rachadura   %d%%" % int(pr * 100.0)
		if bar:
			bar.value = pr * 100.0


func _split_progress() -> float:
	var t := 0.0
	for sp in _split.spots:
		t += float(sp.depth)
	return t / 3.0


func _split_place_done() -> void:
	var k := int(_split.go)
	var sp: Dictionary = _split.spots[k]
	_split.anim = -1.0
	if _chop_pose:
		_chop_pose.reach_on = false
		_chop_pose.reach_grip = false
	if item_qtd("cunha") <= 0:
		return
	remove_item("cunha", 1)
	sp.placed = true
	var mi := MeshInstance3D.new()
	mi.mesh = Corte2.worked_stone_mesh("cunha")
	mi.material_override = Lascar.material()
	add_child(mi)
	sp.node = mi
	Sons.play_at(self, "pedra_bate", _split_geo(float(sp.u)).top, -8.0, 1.2)
	_update_inventory()
	var all := true
	for s2 in _split.spots:
		all = all and bool(s2.placed)
	if str(_split.stage) == "cunhas":
		if all:
			_split.stage = "bater"
			_show_toast("As 3 cunhas estão no lugar. Pegue a marreta: toque numa cunha e bata.")
			_split.go = -1
	else:
		_split.sel = k
		_split_ready_hammer(_split_geo(float(sp.u)))


## A marreta chegou na cunha.
func _split_impact() -> void:
	var k := int(_split.sel)
	var sp: Dictionary = _split.spots[k]
	var g := _split_geo(float(sp.u))
	var at: Vector3 = g.top + Vector3.UP * 0.07
	wear("marreta")
	if not bool(_split.ok):
		# pegou torto: a cunha estoura
		sp.placed = false
		if sp.node:
			(sp.node as Node3D).queue_free()
		sp.node = null
		_split.sel = -1
		Sons.play_at(self, "pedra_racha", at, 2.0)
		_stone_chips(at, 22)
		_show_toast("A marreta pegou torto: a cunha quebrou! Ponha outra cunha no lugar.")
		if _chop_pose:
			_chop_pose.ready_pose = false
		return
	Sons.play_at(self, "pedra_bate", at, 2.0, randf_range(0.8, 0.95))
	_stone_chips(at, 5)
	var low := 1e9
	for j in _split.spots.size():
		if j != k:
			low = minf(low, float(_split.spots[j].depth))
	if float(sp.depth) - low >= SPLIT_LEAD:
		_show_toast("Essa cunha já entrou mais que as outras: bata um pouco nas outras.")
		return
	sp.depth = minf(1.0, float(sp.depth) + _split_rng.randf_range(0.15, 0.24))
	if _split_rng.randf() < 0.5:
		Sons.play_at(self, "estalo", g.axis, -6.0, randf_range(0.7, 0.9))     # a madeira estala abrindo
	var done := true
	for s2 in _split.spots:
		done = done and float(s2.depth) >= 1.0
	if done:
		_split_finish()


## Posição das cunhas (entrando na madeira) e a rachadura em cima da tora.
func _split_update_visuals() -> void:
	for sp in _split.spots:
		var mi: Node3D = sp.node
		if mi == null:
			continue
		var g := _split_geo(float(sp.u))
		var dir: Vector3 = g.dir
		var x := Vector3.DOWN
		var z := Vector3(dir.x, 0, dir.z).normalized()
		var y := z.cross(x)
		var s := 0.28
		mi.global_transform = Transform3D(Basis(x * s, y * s, z * s), g.top + Vector3.UP * (0.1 - float(sp.depth) * 0.075))
	_split_crack_mesh()


## Rachadura ao longo da tora: sai de cada cunha para os dois lados, tortinha, mais
## aberta perto da cunha e mais funda quanto mais a cunha entrou; quando chega na
## ponta, desce pela cara da tora. Mostra até onde a tora vai abrir.
func _split_crack_mesh() -> void:
	var pr := _split_progress()
	if pr <= 0.0:
		return
	var crack: MeshInstance3D = _split.crack
	if crack == null:
		crack = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.06, 0.035, 0.02)
		m.roughness = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		crack.material_override = m
		add_child(crack)
		_split.crack = crack
	# quanto a rachadura está aberta em cada ponto u da tora (0 a 1)
	var open_at := func(u: float) -> float:
		var o := 0.0
		for sp in _split.spots:
			var dpt := float(sp.depth)
			var reach := dpt * 0.45                       # até onde a rachadura desta cunha já correu
			var dd := absf(u - float(sp.u))
			if dd < reach + 0.001:
				o = maxf(o, dpt * (1.0 - 0.6 * dd / maxf(reach, 0.001)))
		return o
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 90
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var has_prev := false
	var nz := FastNoiseLite.new()
	nz.seed = int(_split.i) * 7 + 3
	nz.frequency = 9.0
	for q in steps + 1:
		var u := float(q) / steps
		var o: float = open_at.call(u)
		if o <= 0.0:
			has_prev = false
			continue
		var g := _split_geo(u)
		var dir: Vector3 = g.dir
		var n := dir.cross(Vector3.UP).normalized()
		var wob := nz.get_noise_1d(u) * 0.018 + nz.get_noise_1d(u * 5.0 + 9.0) * 0.006
		var c: Vector3 = g.top + n * wob + Vector3.UP * 0.014
		var w := 0.005 + o * 0.028
		var l := c - n * w
		var r := c + n * w
		if has_prev:
			for v in [prev_l, l, r, prev_l, r, prev_r]:
				st.add_vertex(v)
			# rachadurinhas de lado (farpas abrindo) de vez em quando
			if q % 7 == 0 and o > 0.3:
				var side := 1.0 if (q / 7) % 2 == 0 else -1.0
				var tip := c + n * side * (0.02 + o * 0.03) + dir * 0.03 - Vector3.UP * 0.004
				for v in [c - dir * 0.006, c + dir * 0.006, tip]:
					st.add_vertex(v)
		prev_l = l
		prev_r = r
		has_prev = true
	# chegou na ponta: a rachadura desce pela cara da tora
	for end in [0.0, 1.0]:
		var o: float = open_at.call(end)
		if o <= 0.0:
			continue
		var g := _split_geo(end)
		var dir: Vector3 = g.dir
		var n := dir.cross(Vector3.UP).normalized()
		var out := -dir if end == 0.0 else dir
		var rad: float = g.rad
		var down := rad * clampf(o * 1.6, 0.0, 1.9)
		var segs := 8
		var pl := Vector3.ZERO
		var prr := Vector3.ZERO
		for k in segs + 1:
			var t := float(k) / segs
			var c: Vector3 = g.top + out * 0.004 - Vector3.UP * down * t + n * nz.get_noise_1d(t * 3.0 + end * 10.0) * 0.015
			var w := (0.002 + o * 0.01) * (1.0 - t * 0.7)
			var l := c - n * w
			var r := c + n * w
			if k > 0:
				for v in [pl, l, r, pl, r, prr]:
					st.add_vertex(v)
			pl = l
			prr = r
	st.generate_normals()
	crack.mesh = st.commit()
	crack.global_transform = Transform3D.IDENTITY


func _split_finish() -> void:
	var i := int(_split.i)
	var inf: Dictionary = _apoios.info(i)
	var fl: Dictionary = _apoios.rested[i].log
	var L := float(inf.L)
	var c: Vector3 = inf.center
	var dir: Vector3 = inf.dir
	# os dois pedaços: mesma casca, raio e comprimento da tora; a seção rachada ao meio
	var cil: Dictionary
	var sec: Dictionary
	if fl.has("cil"):
		cil = fl.cil.duplicate()
		sec = fl.sec
	else:
		cil = {"L": L, "ra": _arvores.free_log_radius_at(fl, 0.02), "rb": _arvores.free_log_radius_at(fl, 0.98)}
		sec = Arvores.circle_sec()
	var halves: Array = Arvores.split_sec(sec, bool(fl.get("em_pe", false)))
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var n := Vector3(-flat.z, 0, flat.x)
	# as cunhas que sobraram voltam para a mochila
	var back := 0
	for sp in _split.spots:
		if bool(sp.placed):
			back += 1
	_split_end(false)
	if back > 0:
		_itens["cunha"] = int(_itens.get("cunha", 0)) + back
	_apoios.take_rested(i)
	var yaw := atan2(-flat.z, flat.x)
	var rmax := maxf(float(cil.ra), float(cil.rb))
	var side := -1.0
	for hs in halves:
		var piece := {"cil": cil.duplicate(), "sec": hs, "v": int(fl.get("v", 0)), "s": float(fl.get("s", 1.0)),
			"h0": float(fl.get("h0", 0.0)), "h1": float(fl.get("h1", 1.0)), "bot": {}, "top": {},
			"pos": [0, 0, 0], "yaw": yaw, "dia": int(fl.get("dia", _arvores.last_day))}
		var p: Vector3 = c + n * side * (rmax + 0.3)
		_arvores.drop_log(piece, p, yaw)
		side = 1.0
	Sons.play_at(self, "queda", c, -4.0, 1.3)
	Sons.play_at(self, "estalo", c, 0.0, 0.8)
	_update_inventory()
	_show_toast("Rachou ao meio! Os dois pedaços estão no chão: dá para pegar, apoiar nas forquilhas e rachar de novo (tábuas) ou fincar. As cunhas voltaram para a mochila.")


func _split_end(give_back := true) -> void:
	if _split.is_empty():
		return
	for sp in _split.spots:
		if sp.node:
			(sp.node as Node3D).queue_free()
		if give_back and bool(sp.placed):
			_itens["cunha"] = int(_itens.get("cunha", 0)) + 1
	if _split.crack:
		(_split.crack as Node3D).queue_free()
	_split = {}
	_jump_btn.visible = true
	if _split_ui:
		_split_ui.queue_free()
	_split_ui = null
	_walking = false
	if _chop_pose:
		_chop_pose.reach_on = false
		_chop_pose.reach_grip = false
		_chop_pose.swinging = false
		_chop_pose.ready_pose = false
		_chop_pose.vertical = false
		_chop_pose.down_hit = -42.0
	_update_inventory()
	_act_check = 0.0


func _build_split_ui() -> void:
	_split_ui = Control.new()
	_split_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_split_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_split_ui)
	var info := PanelContainer.new()
	info.offset_left = 16
	info.offset_top = 16
	info.offset_right = 400
	info.offset_bottom = 130
	info.add_theme_stylebox_override("panel", Mochila._box(Color(0.05, 0.05, 0.04, 0.82), Color(1, 1, 1, 0.18), 2, 8))
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var il := Label.new()
	il.name = "il"
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	il.add_theme_font_size_override("font_size", 15)
	info.add_child(il)
	_split_ui.add_child(info)
	var prog := PanelContainer.new()
	prog.set_anchors_preset(Control.PRESET_CENTER_TOP)
	prog.offset_left = -200
	prog.offset_right = 200
	prog.offset_top = 16
	prog.offset_bottom = 84
	prog.add_theme_stylebox_override("panel", Mochila._box(Color(0.05, 0.05, 0.04, 0.82), Color(1, 1, 1, 0.18), 2, 8))
	prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pv := VBoxContainer.new()
	prog.add_child(pv)
	var pl := Label.new()
	pl.name = "pl"
	pl.add_theme_font_size_override("font_size", 16)
	pv.add_child(pl)
	var bar := ProgressBar.new()
	bar.name = "bar"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(360, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.55, 0.25)
	bar.add_theme_stylebox_override("fill", fill)
	pv.add_child(bar)
	_split_ui.add_child(prog)
	var mk := Control.new()
	mk.name = "mk"
	mk.set_anchors_preset(Control.PRESET_FULL_RECT)
	mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mk.draw.connect(func(): _draw_split_marks(mk))
	_split_ui.add_child(mk)
	var tb := Control.new()
	tb.name = "tb"
	tb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tb.offset_left = -270
	tb.offset_right = 270
	tb.offset_top = -110
	tb.offset_bottom = -30
	tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.draw.connect(func(): _draw_split_bar(tb))
	_split_ui.add_child(tb)
	var hit := Icones.IconButton.new()
	hit.name = "hit"
	hit.text = "Bater"
	hit.add_theme_font_size_override("font_size", 22)
	hit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hit.offset_left = -190
	hit.offset_top = -190
	hit.offset_right = -30
	hit.offset_bottom = -30
	hit.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	hit.pressed.connect(_split_hit)
	hit.visible = false
	_split_ui.add_child(hit)
	var out := Icones.IconButton.new()
	out.text = "Sair"
	out.add_theme_font_size_override("font_size", 20)
	out.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	out.offset_left = 30
	out.offset_top = -160
	out.offset_right = 160
	out.offset_bottom = -30
	out.pressed.connect(func():
		_show_toast("Você tirou as cunhas da tora.")
		_split_end())
	_split_ui.add_child(out)


func _draw_split_marks(mk: Control) -> void:
	if _split.is_empty():
		return
	var font := ThemeDB.fallback_font
	var tsec := Time.get_ticks_msec() / 1000.0
	var spots: Array = _split.spots
	for k in spots.size():
		var sp: Dictionary = spots[k]
		var w: Vector3 = _split_geo(float(sp.u)).top + Vector3.UP * 0.1
		if _cam.is_position_behind(w):
			continue
		var p := _cam.unproject_position(w)
		var sel := k == int(_split.sel)
		var txt: String
		var col := Color(1, 1, 1, 0.95)
		if not bool(sp.placed):
			txt = "Pôr cunha"
		else:
			txt = "%d%%" % int(float(sp.depth) * 100.0)
			col = Color(0.3, 0.85, 0.3) if sel else Color(1.0, 0.8, 0.3)
		var r := 16.0 + (3.0 * sin(tsec * 6.0) if sel else 0.0)
		var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
		if sel:
			mk.draw_circle(p, r * 1.6, Color(0.3, 0.9, 0.3, 0.25))
		mk.draw_polyline(pts + PackedVector2Array([pts[0]]), col, 3.0, true)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var lb := Rect2(p + Vector2(-tw * 0.5 - 8, -r - 44), Vector2(tw + 16, 28))
		mk.draw_rect(lb, Color(0.05, 0.05, 0.04, 0.85))
		mk.draw_rect(lb, col, false, 2.0)
		mk.draw_string(font, lb.position + Vector2(8, 20), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.95, 0.8))


func _draw_split_bar(tb: Control) -> void:
	if _split.is_empty() or str(_split.stage) != "bater":
		return
	var w := tb.size.x
	var r := Rect2(Vector2(0, 34), Vector2(w, 34))
	var font := ThemeDB.fallback_font
	var txt := "Bata quando o marcador estiver no verde" if int(_split.sel) >= 0 else "Toque numa cunha da tora"
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	tb.draw_rect(Rect2(Vector2(w * 0.5 - tw * 0.5 - 10, 0), Vector2(tw + 20, 28)), Color(0.05, 0.05, 0.04, 0.85))
	tb.draw_string(font, Vector2(w * 0.5 - tw * 0.5, 21), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.95, 0.8))
	tb.draw_rect(r.grow(4), Color(0.05, 0.05, 0.04, 0.9))
	var n := 60
	for k in n:
		var u := (k + 0.5) / n
		var d := absf(u - float(_split.gc)) - float(_split.gw) * 0.5
		var col := Color(0.2, 0.75, 0.2) if d <= 0.0 else (Color(0.92, 0.55, 0.1) if d <= KNAP_EDGE else Color(0.8, 0.12, 0.1))
		tb.draw_rect(Rect2(r.position + Vector2(w * k / n, 0), Vector2(w / n + 0.5, r.size.y)), col)
	tb.draw_rect(r, Color(0, 0, 0, 0.8), false, 2.0)
	var m: float = float(_split.get("frozen", 0.5)) if float(_split.anim) >= 0.0 else _split_marker()
	var x := r.position.x + m * w
	tb.draw_rect(Rect2(Vector2(x - 4, r.position.y - 7), Vector2(8, r.size.y + 14)), Color(1.0, 0.85, 0.15))
	tb.draw_rect(Rect2(Vector2(x - 4, r.position.y - 7), Vector2(8, r.size.y + 14)), Color(0.2, 0.12, 0.0), false, 2.0)


## Banda (metade da tora): deitada com a casca embaixo e a madeira aberta para cima.
## Comprida no eixo X local, afinando de ra (x = -L/2) até rb (x = +L/2).
func _banda_mesh(L: float, ra: float, rb: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var segs := 12
	var arcs := 14
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rmax := maxf(ra, rb)
	for i in segs:
		for j in arcs:
			var q := []
			var uvs := []
			for e in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var t := float(e[0]) / segs
				var a := PI * float(e[1]) / arcs
				var r := lerpf(ra, rb, t)
				var x := (t - 0.5) * L
				q.append(Vector3(x, rmax - sin(a) * r, cos(a) * r))
				uvs.append(Vector2(a * r / 0.5, x / 1.0))
			for idx in [0, 2, 1, 0, 3, 2]:
				var pv: Vector3 = q[idx]
				var nrm := Vector3(0, pv.y - rmax, pv.z).normalized()
				bark.set_normal(nrm)
				bark.set_uv(uvs[idx])
				bark.add_vertex(pv)
	bark.commit(mesh)
	mesh.surface_set_material(0, _arvores.bark_material())
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(L * 1000.0)
	# face aberta (em cima): rachada com cunha não sai lisa: ondulada no sentido das
	# fibras, com degraus onde a madeira rasgou, rachaduras compridas, o miolo escuro e
	# farpas levantadas
	var nz := FastNoiseLite.new()
	nz.seed = rng.randi()
	nz.frequency = 1.0
	var cracks := []
	for c in 4:
		cracks.append([rng.randf_range(-0.75, 0.75), rng.randf_range(0.0, 6.0), rng.randf_range(0.2, 0.9), rng.randf_range(-0.4, 0.4)])
	var fx := 60
	var fv := 34
	var face_h := func(t: float, v: float) -> float:
		var x := (t - 0.5) * L
		var h := nz.get_noise_2d(x * 1.2, v * 6.0) * 0.022 + nz.get_noise_2d(x * 5.0, v * 22.0) * 0.007
		h += nz.get_noise_2d(x * 0.3 + 40.0, 0.0) * 0.02 * v           # a face torce de leve
		var step_ := nz.get_noise_2d(x * 0.8 + 100.0, v * 2.0)
		h += 0.008 if step_ > 0.25 else 0.0                              # degrau onde a fibra rasgou
		for c in cracks:
			var cv: float = float(c[0]) + sin(x * 2.0 + float(c[1])) * 0.08
			if t > float(c[2]) - 0.35 and t < float(c[2]) + 0.35 and absf(v - cv) < 0.035:
				h -= 0.012
		return h
	var face_c := func(t: float, v: float) -> Color:
		var x := (t - 0.5) * L
		var core := 1.0 - smoothstep(0.0, 0.1, absf(v + nz.get_noise_1d(x * 2.0) * 0.05))
		var grain := 0.07 * nz.get_noise_2d(x * 2.0, v * 40.0)
		var col := Color(0.4, 0.28, 0.17).darkened(core * 0.35 + grain)
		for c in cracks:
			var cv: float = float(c[0]) + sin(x * 2.0 + float(c[1])) * 0.08
			if t > float(c[2]) - 0.35 and t < float(c[2]) + 0.35 and absf(v - cv) < 0.03:
				col = Color(0.1, 0.07, 0.04)                               # rachadura
		return col
	for i in fx:
		for j in fv:
			var q := []
			var cs := []
			for e in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var t := float(e[0]) / fx
				var v := float(e[1]) / fv * 2.0 - 1.0
				var r := lerpf(ra, rb, t)
				var edge := 1.0 - smoothstep(0.85, 1.0, absf(v))         # na beira a casca segura a altura
				q.append(Vector3((t - 0.5) * L, rmax + float(face_h.call(t, v)) * edge, v * r))
				cs.append(face_c.call(t, v))
			for idx in [0, 1, 2, 0, 2, 3]:
				wood.set_color(cs[idx])
				wood.add_vertex(q[idx])
	# farpas: lascas finas e compridas levantadas da face, no sentido das fibras
	for k in 26:
		var t := rng.randf_range(0.03, 0.97)
		var v := rng.randf_range(-0.9, 0.9)
		var r := lerpf(ra, rb, t)
		var base := Vector3((t - 0.5) * L, rmax + float(face_h.call(t, v)), v * r)
		var dirx := 1.0 if rng.randf() < 0.5 else -1.0
		var ln := rng.randf_range(0.04, 0.14)
		var tip := base + Vector3(dirx * ln, rng.randf_range(0.01, 0.04), rng.randf_range(-0.01, 0.01))
		var wd := rng.randf_range(0.004, 0.01)
		var col := Color(0.58, 0.43, 0.28).darkened(rng.randf() * 0.15)
		for vtx in [base + Vector3(0, 0, -wd), base + Vector3(0, 0, wd), tip, base + Vector3(0, 0.003, 0), base + Vector3(0, -0.002, wd), tip]:
			wood.set_color(col)
			wood.add_vertex(vtx)
	# farpas na beira da madeira, junto da casca (onde a fibra arrebentou)
	for k in 18:
		var t := rng.randf_range(0.02, 0.98)
		var sgn := 1.0 if rng.randf() < 0.5 else -1.0
		var r := lerpf(ra, rb, t)
		var base := Vector3((t - 0.5) * L, rmax, sgn * r * 0.97)
		var tip := base + Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(0.01, 0.03), sgn * rng.randf_range(0.01, 0.03))
		var col := Color(0.55, 0.4, 0.26)
		for vtx in [base + Vector3(-0.01, 0, 0), base + Vector3(0.01, 0, 0), tip]:
			wood.set_color(col)
			wood.add_vertex(vtx)
	# pontas (meia-lua de madeira com anéis)
	wood.generate_normals()
	var wood_mesh := wood.commit()
	wood = SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	wood.append_from(wood_mesh, 0, Transform3D.IDENTITY)
	for end in [0, 1]:
		var r := ra if end == 0 else rb
		var x := (float(end) - 0.5) * L
		var nx := -1.0 if end == 0 else 1.0
		for j in arcs:
			var a0 := PI * float(j) / arcs
			var a1 := PI * float(j + 1) / arcs
			var c0 := Vector3(x, rmax, 0)
			var p0 := Vector3(x, rmax - sin(a0) * r, cos(a0) * r)
			var p1 := Vector3(x, rmax - sin(a1) * r, cos(a1) * r)
			for v in ([c0, p0, p1] if end == 1 else [c0, p1, p0]):
				var dd := Vector2(v.y - rmax, v.z).length() / maxf(r, 0.01)
				wood.set_normal(Vector3(nx, 0, 0))
				wood.set_color(Color(0.47, 0.34, 0.22).darkened(0.1 * absf(sin(dd * 14.0))))
				wood.add_vertex(v)
	wood.commit(mesh)
	var wm := StandardMaterial3D.new()
	wm.vertex_color_use_as_albedo = true
	wm.vertex_color_is_srgb = true
	wm.roughness = 1.0
	wm.metallic_specular = 0.1
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(1, wm)
	return mesh



# ================== MULTIPLAYER ==================

func _mp_start() -> void:
	var r := get_tree().root.get_node_or_null("Rede")
	if r == null or not r.ativo():
		return
	_rede = r
	_rede.parte_mundo.connect(_sync_receive)
	_sync_baseline()
	if _rede.modo == "dono":
		# quem entra pede o mundo de agora: manda todas as partes de novo
		_rede.pediram_mundo.connect(func():
			_sync_hash = {}
			for nome in SYNC_EVERY:
				_sync_t[nome] = 0.0)
	else:
		_rede.pedir_mundo_atual()
	if _rede.modo == "dono":
		_rede.hook_salvar = _save_world
		_rede.hook_tempo = func() -> int: return int(sim.steps)
		_show_toast("Mundo aberto no multiplayer: quem estiver na mesma Wi-Fi pode entrar.")
	else:
		if int(_rede.tempo_recebido) >= 0:
			sim.steps = int(_rede.tempo_recebido)
		_show_toast("Você entrou no mundo de %s." % _dono_nome())
	_rede.falhou.connect(func(msg: String):
		_show_toast(msg + " Voltando para o menu…")
		get_tree().create_timer(2.5).timeout.connect(func():
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))


func _dono_nome() -> String:
	if _rede and _rede.jogadores.has(1):
		return str(_rede.jogadores[1].nome)
	return "outro jogador"


func _mp_tick(delta: float) -> void:
	if _rede == null or not _rede.ativo():
		return
	_mp_t -= delta
	if _mp_t <= 0.0:
		_mp_t = 0.1          # 10 vezes por segundo
		var p := _player.global_position
		var crouch := 0.0
		if _crouch_job != "" or not _knap.is_empty() or _digging:
			crouch = 1.0
		var est := {"p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)], "y": snappedf(_face, 0.01),
			"a": _anim_now, "s": _anim.speed_scale if _anim else 1.0, "c": crouch, "m": _mao}
		if not _coop_int.is_empty():
			est["coop"] = {"a": _coop_int.a, "k": _coop_int.k, "ts": _coop_int.ts}
		if not _coop.is_empty():
			est["coopl"] = [snappedf(float(_coop.L), 0.01), snappedf(float(_coop.r), 0.01), int(_coop.pid), bool(_coop.lider)]
		if not _maq_op.is_empty():
			est["maq"] = [int(_maq_op.mi), snappedf(float(_maq_op.pedal), 0.01), snappedf(float(_maq_op.emp), 0.01)]
		if not _carry.is_empty():
			est["tora"] = [snappedf(_arvores.free_log_length(_carry), 0.01), snappedf(_arvores.free_log_radius(_carry), 0.01)]
		_rede.mandar_estado(est)
	if _rede.modo == "dono":
		_mp_tempo_t -= delta
		if _mp_tempo_t <= 0.0:
			_mp_tempo_t = 5.0
			_rede.mandar_tempo(int(sim.steps))
	elif int(_rede.tempo_recebido) >= 0:
		if absi(int(sim.steps) - int(_rede.tempo_recebido)) > 40:
			sim.steps = int(_rede.tempo_recebido)
		_rede.tempo_recebido = -1
	# os outros jogadores
	var me := multiplayer.get_unique_id()
	for id in _rede.jogadores:
		var pid := int(id)
		if pid == me:
			continue
		if not _remotos.has(pid):
			var j := JogadorRemoto.new()
			add_child(j)
			j.setup(str(_rede.jogadores[id].nome), str(_rede.jogadores[id].get("skin", "homem")))
			j.visible = false
			_remotos[pid] = j
		var e = _rede.estados.get(pid)
		if e != null and _maq and (e as Dictionary).has("maq"):
			var mq: Array = e.maq
			_maq.inputs[pid] = {"mi": int(mq[0]), "pedal": float(mq[1]), "emp": float(mq[2]), "t": Time.get_ticks_msec()}
		if e != null:
			var j: Node3D = _remotos[pid]
			j.visible = true
			j.aplicar(e)
			# quem acabou de entrar aparece do lado do dono
			if pid == 1 and _rede.modo == "convidado" and not _mp_perto:
				_mp_perto = true
				var hp: Array = e.p
				var spot := Vector3(float(hp[0]) + 1.5, 0, float(hp[2]) + 1.0)
				_player.position = _ground_pos(Vector2(spot.x, spot.z))
	for pid in _remotos.keys():
		if not _rede.jogadores.has(pid):
			(_remotos[pid] as Node).queue_free()
			_remotos.erase(pid)



# ================== TÁBUAS PEQUENAS E RIPAS ==================

## Pedaço rachado fino o bastante para ser tábua (até uns 12 cm de grossura).
func _is_board(fl: Dictionary) -> bool:
	if not fl.has("sec"):
		return false
	var e: Vector2 = _arvores._sec_ext(fl)
	var r: float = _arvores._cil_r(fl, 0.5)
	return minf(e.x, e.y) * r * 2.0 <= 0.12


## Serrou um pedaço da ponta: ele cai no chão do jeito que saiu da serra (o mesmo
## formato da tábua, só que curto). Se o que sobrou nas forquilhas é curto, cai também.
func _tabua_cortada(wi: int, end_before: Vector3, out_dir: Vector3) -> void:
	var fl: Dictionary = _apoios.rested[wi].log
	var flat := Vector3(out_dir.x, 0, out_dir.z).normalized()
	var yaw := atan2(-flat.z, flat.x)
	var r_end: float = float(fl.cil.rb) if out_dir.dot(_apoios.info(wi).dir) > 0.0 else float(fl.cil.ra)
	var piece := _board_piece(fl, TAB_L, r_end, r_end)
	_arvores.drop_log(piece, end_before - out_dir * TAB_L * 0.5 + flat * 0.1, yaw)
	var n := 1
	if _arvores.free_log_length(fl) < TAB_L + 0.12:
		var c: Vector3 = _apoios.info(wi).center
		var rest: Dictionary = _apoios.take_rested(wi)
		_arvores.drop_log(rest, c, yaw)
		n += 1
	_arvores._rebuild_logs()
	Sons.play_at(self, "baque", end_before, -14.0, 1.4)
	_show_toast("A tábua pequena caiu no chão. Rache ela com o machado para tirar as ripas, ou pegue e carregue." if n == 1 else "As duas tábuas pequenas caíram no chão.")


## Um pedaço novo com a mesma seção (o mesmo formato) da madeira de origem.
func _board_piece(fl: Dictionary, L: float, ra: float, rb: float) -> Dictionary:
	return {"cil": {"L": L, "ra": ra, "rb": rb}, "sec": fl.sec.duplicate(true), "v": int(fl.get("v", 0)),
		"s": float(fl.get("s", 1.0)), "h0": 0.0, "h1": 1.0, "bot": {}, "top": {}, "pos": [0, 0, 0], "yaw": 0.0,
		"dia": int(fl.get("dia", _arvores.last_day))}


## Tábua curta (pedaço rachado fino, até uns 60 cm) deitada no chão, para rachar em ripas.
func _is_short_board(fl: Dictionary) -> bool:
	return _is_board(fl) and _arvores.free_log_length(fl) <= 0.62


## Largura da tábua (a face deitada), em metros.
func _board_width(fl: Dictionary) -> float:
	var e: Vector2 = _arvores._sec_ext(fl)
	return maxf(e.x, e.y) * _arvores._cil_r(fl, 0.5) * 2.0


## Quantas ripas saem de uma tábua curta: uma a cada uns 3,5 cm de largura.
func _ripas_of(fl: Dictionary) -> int:
	return clampi(int(_board_width(fl) / 0.035), 2, 6)


## Tábua curta deitada no chão bem na frente (índice em free_logs), ou -1.
func _board_ahead() -> int:
	var to := _front(0.7)
	var best := -1
	var bd := 0.8
	for i in _arvores.free_logs.size():
		var fl: Dictionary = _arvores.free_logs[i]
		if not _is_short_board(fl):
			continue
		var d := Vector2(float(fl.pos[0]) - to.x, float(fl.pos[2]) - to.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func _start_board_chop(i: int) -> void:
	var fl: Dictionary = _arvores.free_logs[i]
	var c := Vector3(float(fl.pos[0]), float(fl.pos[1]), float(fl.pos[2]))
	var yaw := float(fl.yaw)
	var along := Vector3(cos(yaw), 0, -sin(yaw))
	var top: float = c.y + _arvores.free_log_radius(fl)
	_chop_log = {"tabua": true, "fl": fl, "axis": c, "along": along, "r": 0.02, "dist": 0.62, "point": Vector3(c.x, top, c.z)}
	_chop_branch = {}
	_chop_tree = null
	_chopping = true
	if _chop_pose:
		_chop_pose.vertical = true
		_chop_pose.down_hit = -42.0
		_chop_pose.ready_pose = true
	_swing_queued = false
	_play("Idle", 0.5)
	_begin_swing()


var _board_crack_node: MeshInstance3D


## O machado bateu na tábua: cada batida abre uma rachadura; na última ela solta as ripas.
func _board_hit() -> void:
	var fl: Dictionary = _chop_log.get("fl", {})
	if fl.is_empty() or not _arvores.free_logs.has(fl):
		_cancel_chop()
		return
	var at: Vector3 = _chop_log.point
	_chips(at)
	Sons.play_at(self, "machado", at, -2.0, 1.15)
	var n_rip := _ripas_of(fl)
	var hits := int(fl.get("racha", 0)) + 1
	fl["racha"] = hits
	var need := 1 if teste else n_rip
	if hits < need:
		_show_board_cracks(fl, hits, n_rip)
		Sons.play_at(self, "estalo", at, -10.0, 1.3)
		_show_toast("Rachando a tábua: %d de %d" % [hits, need])
		return
	# soltou: as ripas caem lado a lado
	if _board_crack_node:
		_board_crack_node.queue_free()
		_board_crack_node = null
	var c := Vector3(float(fl.pos[0]), 0, float(fl.pos[2]))
	var yaw := float(fl.yaw)
	_arvores.free_logs.erase(fl)
	_arvores._rebuild_logs()
	var across := Vector3(sin(yaw), 0, cos(yaw))
	for k in n_rip:
		var p := c + across * (float(k) - (n_rip - 1) * 0.5) * 0.05
		_add_ground("ripa", 1, p.x, p.z)
		(_chao[_chao.size() - 1].node as Node3D).get_child(0).rotation.y = yaw
	Sons.play_at(self, "estalo", at, 0.0, 1.1)
	_show_toast("A tábua rachou em %d ripas (mata-juntas). Pegue elas!" % n_rip)
	_cancel_chop()


## As rachaduras do machado em cima da tábua (linhas escuras no comprido).
func _show_board_cracks(fl: Dictionary, hits: int, n_rip: int) -> void:
	if _board_crack_node == null or not is_instance_valid(_board_crack_node):
		_board_crack_node = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.05, 0.03)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_board_crack_node.material_override = m
		add_child(_board_crack_node)
	var L: float = _arvores.free_log_length(fl)
	var W := _board_width(fl)
	var top: float = float(fl.pos[1]) + _arvores.free_log_radius(fl) + 0.004
	var yaw := float(fl.yaw)
	var along := Vector3(cos(yaw), 0, -sin(yaw))
	var across := Vector3(sin(yaw), 0, cos(yaw))
	var c := Vector3(float(fl.pos[0]), top, float(fl.pos[2]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in hits:
		var off := ((float(k) + 1.0) / n_rip - 0.5) * W
		var segs := 8
		var prev := c + across * off - along * L * 0.48
		for sg in segs:
			var u := float(sg + 1) / segs
			var nxt := c + across * (off + rng.randf_range(-0.004, 0.004)) + along * (u - 0.5) * L * 0.96
			var w := across * 0.003
			for v in [prev - w, nxt - w, nxt + w, prev - w, nxt + w, prev + w]:
				st.add_vertex(v)
			prev = nxt
	_board_crack_node.mesh = st.commit()


## Tábuas pequenas de versões antigas (eram item da mochila ou enfeite no chão):
## viram pedaços de madeira de verdade, deitados no chão.
func _convert_tabuas() -> void:
	var keep := []
	var spots := []
	for g in _chao:
		if str(g.id) != "tabua":
			keep.append(g)
			continue
		for q in maxi(1, int(g.get("qtd", 1))):
			spots.append(Vector3(float(g.x) + q * 0.2, 0, float(g.z)))
		if g.node:
			(g.node as Node3D).queue_free()
	var inv := int(_itens.get("tabua", 0))
	if inv > 0 and _player:
		for q in inv:
			var f := _player.position + Vector3(0.6 + q * 0.22, 0, 0.4)
			spots.append(Vector3(f.x, 0, f.z))
		_itens.erase("tabua")
	if spots.is_empty():
		return
	_chao = keep
	# seção de tábua: 15 cm de largura, 5 cm de grossura, casca numa beirada
	var sec := {"pts": [[-1.0, -0.33, 1], [1.0, -0.33, 0], [1.0, 0.33, 1], [-1.0, 0.33, 1]], "ax": [0.0, -2.0]}
	for p in spots:
		var fl := {"cil": {"L": TAB_L, "ra": 0.075, "rb": 0.075}, "sec": sec.duplicate(true), "v": 0, "s": 1.0,
			"h0": 0.0, "h1": 1.0, "bot": {}, "top": {}, "pos": [p.x, 0.0, p.z], "yaw": randf() * TAU, "dia": _arvores.last_day}
		fl.pos[1] = height_at(p.x, p.z) + 0.025
		_arvores.free_logs.append(fl)
	_arvores._rebuild_logs()


## Tábua pequena (40 x 14 x 3 cm) ou ripa (40 x 3,5 x 1,5 cm): madeira com veios, a
## face rachada ondulada; na tábua, as rachaduras do machado aparecendo.
func _board_mesh(ripa: bool, cracks: int) -> ArrayMesh:
	var L := TAB_L
	var W := 0.035 if ripa else 0.14
	var T := 0.015 if ripa else 0.03
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nz := FastNoiseLite.new()
	nz.seed = 7 if ripa else 11
	var nx := 10
	var nzs := 4 if ripa else 16
	var wood := Color(0.36, 0.26, 0.16)
	var top := func(i: int, j: int) -> Vector3:
		var x := (float(i) / nx - 0.5) * L
		var z := (float(j) / nzs - 0.5) * W
		return Vector3(x, T + nz.get_noise_2d(x * 12.0, z * 40.0) * 0.003, z)
	for i in nx:
		for j in nzs:
			var q := [top.call(i, j), top.call(i + 1, j), top.call(i + 1, j + 1), top.call(i, j + 1)]
			var zc := (float(j) + 0.5) / nzs
			var col := wood.darkened(0.08 * nz.get_noise_2d(float(i) * 3.0, zc * 30.0) + 0.04)
			# rachaduras do machado ao longo da tábua
			for k in cracks:
				if absf(zc - (float(k) + 1.0) / float(RIPAS_POR_TABUA)) < 0.035:
					col = Color(0.12, 0.08, 0.05)
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_color(col)
				st.add_vertex(q[idx])
	# lados e embaixo (caixa)
	var hx := L * 0.5
	var hz := W * 0.5
	var box := [[Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, T, -hz), Vector3(-hx, T, -hz)],
		[Vector3(hx, 0, hz), Vector3(-hx, 0, hz), Vector3(-hx, T, hz), Vector3(hx, T, hz)],
		[Vector3(-hx, 0, hz), Vector3(-hx, 0, -hz), Vector3(-hx, T, -hz), Vector3(-hx, T, hz)],
		[Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(hx, T, hz), Vector3(hx, T, -hz)],
		[Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(hx, 0, -hz)]]
	var k2 := 0
	for f in box:
		var col := wood.darkened(0.15) if k2 < 2 else Color(0.46, 0.34, 0.22)     # pontas serradas mais claras
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.add_vertex(f[idx])
		k2 += 1
	st.generate_normals()
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, m)
	return mesh



## Madeira perto para passar o óleo de andiroba (a que ainda não tem óleo).
func _oil_target() -> Dictionary:
	if _cupins == null:
		return {}
	var t: Dictionary = _cupins.nearest_wood(_player.position, 1.6)
	if t.is_empty() or _cupins.oiled(t):
		return {}
	return t


## Madeira perto para passar o veneno (a que não está tratada ainda).
func _poison_target() -> Dictionary:
	if _cupins == null:
		return {}
	var t: Dictionary = _cupins.nearest_wood(_player.position, 1.6)
	if t.is_empty() or _cupins._treated(t, _cupins.last_day):
		return {}
	return t


# ================== CONSTRUÇÃO ==================
# Com uma madeira no ombro (tora, meia tora, tábua): "Construir" mostra a peça
# fantasma onde o olho mira (verde: dá para pôr; vermelho: não dá). Girar, Inclinar
# (deitada, 30, 45, 60 graus, em pé) e Virar (tábua deitada ou de lado).

## Cortando a ponta da estaca com o machado (uns 3 segundos de batidas); andar cancela.
func _post_cut_tick(delta: float) -> void:
	if _post_cut.is_empty():
		return
	var i := int(_post_cut.i)
	if i >= _buracos.posts.size() or _mao != "machado" or _buracos.post_near(_player.position, 1.6) != i:
		_post_cut = {}
		return
	var po: Dictionary = _buracos.posts[i]
	var top := Vector3(float(po.x), _buracos.post_top(po), float(po.z))
	_post_cut.t = float(_post_cut.t) + delta
	_post_cut.s = float(_post_cut.s) - delta
	var to := Vector2(top.x - _player.position.x, top.z - _player.position.z)
	_face = lerp_angle(_face, atan2(-to.x, -to.y), minf(1.0, delta * 8.0))
	if float(_post_cut.s) <= 0.0:
		_post_cut.s = 0.6
		var cutp := Vector3(top.x, float(_post_cut.y) + 0.02, top.z)
		Sons.play_at(self, "machado", cutp, -2.0, 1.0 + randf() * 0.1)
		_chips(cutp)
	if float(_post_cut.t) >= (0.3 if teste else 3.0):
		var cut: float = _buracos.cut_post(i, float(_post_cut.y))
		_post_cut = {}
		if cut > 0.0:
			Sons.play_at(self, "estalo", top, -4.0, 1.1)
			if cut >= 0.12:
				# a ponta cortada cai do lado
				var r: float = _arvores.free_log_radius(po.log)
				var bit := {"cil": {"L": cut, "ra": r, "rb": r}, "sec": Arvores.circle_sec(), "v": 0, "s": 1.0, "h0": 0.0, "h1": 1.0,
					"bot": {}, "top": {}, "pos": [0, 0, 0], "yaw": 0.0, "dia": _arvores.last_day}
				_arvores.drop_log(bit, top + Vector3(0.3, 0, 0), randf() * TAU)
			var fell: int = _constr.settle() if _constr else 0
			_show_toast("Ponta cortada: tirou %d cm." % roundi(cut * 100.0) + (" O que estava em cima dela caiu." if fell > 0 else ""))
		_act_check = 0.0


# ================== CORTAR A ESTACA NA ALTURA QUE QUISER ==================
# Com o machado perto da estaca: uma marca vermelha em volta dela mostra onde vai
# cortar; Subir/Descer de 5 em 5 cm, "Cortar aqui". "Medir" guarda a altura do topo
# dessa estaca (para cortar outra igual) e vai até a mais alta perto.

func _mark_open(i: int) -> void:
	var po: Dictionary = _buracos.posts[i]
	var top: float = _buracos.post_top(po)
	var y := top - 0.1
	if not _medida.is_empty() and int(_medida.i) != i and float(_medida.y) < top - 0.02:
		y = float(_medida.y)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var r: float = _arvores.free_log_radius(po.log)
	cm.top_radius = r + 0.03
	cm.bottom_radius = r + 0.03
	cm.height = 0.02
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.15, 0.1, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	add_child(mi)
	_post_mark = {"i": i, "y": y, "node": mi}
	_mark_clamp()
	for b in [_log_btn, _ctx_btn, _chop_btn, _pick_btn, _plant_btn, _work_btn, _vine_btn, _seed_btn, _bld_btn]:
		(b as Control).visible = false
	for b in _mark_btns:
		(b as Control).visible = true
	_bld_why.visible = true
	_mark_tick()


func _mark_clamp() -> void:
	var i := int(_post_mark.i)
	var po: Dictionary = _buracos.posts[i]
	var top: float = _buracos.post_top(po)
	var gy: float = surface_at(float(po.x), float(po.z))
	_post_mark.y = clampf(float(_post_mark.y), gy + 0.15, top - 0.02)


func _mark_move(dy: float) -> void:
	if _post_mark.is_empty():
		return
	_post_mark.y = float(_post_mark.y) + dy
	_mark_clamp()
	_mark_tick()


func _mark_tick() -> void:
	var i := int(_post_mark.i)
	if i >= _buracos.posts.size() or _mao != "machado" or _buracos.post_near(_player.position, 2.0) != i:
		_mark_close()
		return
	var po: Dictionary = _buracos.posts[i]
	var top: float = _buracos.post_top(po)
	var gy: float = surface_at(float(po.x), float(po.z))
	var y := float(_post_mark.y)
	(_post_mark.node as Node3D).position = Vector3(float(po.x), y, float(po.z))
	var txt := "Cortar a %d cm do chão (tira %d cm)" % [roundi((y - gy) * 100.0), roundi((top - y) * 100.0)]
	if not _medida.is_empty() and absf(float(_medida.y) - y) < 0.006:
		txt += " · na altura medida"
	_bld_why.text = txt
	for b in [_log_btn, _ctx_btn, _chop_btn, _pick_btn, _plant_btn, _work_btn, _vine_btn, _seed_btn, _bld_btn]:
		(b as Control).visible = false


func _mark_close() -> void:
	if _post_mark.is_empty():
		return
	(_post_mark.node as Node3D).queue_free()
	_post_mark = {}
	for b in _mark_btns:
		(b as Control).visible = false
	_bld_why.visible = false
	_act_check = 0.0


func _mark_cut() -> void:
	if _post_mark.is_empty():
		return
	var i := int(_post_mark.i)
	var y := float(_post_mark.y)
	_mark_close()
	_post_cut = {"i": i, "t": 0.0, "y": y, "s": 0.0}


func _mark_measure() -> void:
	if _post_mark.is_empty():
		return
	var mi := int(_post_mark.i)
	_mark_close()
	var my: float = _buracos.post_top(_buracos.posts[mi])
	_medida = {"i": mi, "y": my}
	# vai sozinho até a estaca mais alta mais perto
	var best := -1
	var bd := 6.0
	for j in _buracos.posts.size():
		var po: Dictionary = _buracos.posts[j]
		if j == mi or _buracos.post_top(po) <= my + 0.02:
			continue
		var d := Vector2(float(po.x) - _player.position.x, float(po.z) - _player.position.z).length()
		if d < bd:
			bd = d
			best = j
	if best < 0:
		_show_toast("Altura do topo medida. Vá até a estaca que quer cortar e toque em \"Cortar estaca\".")
		return
	var po2: Dictionary = _buracos.posts[best]
	var pc := Vector3(float(po2.x), 0, float(po2.z))
	var away := Vector3(_player.position.x - pc.x, 0, _player.position.z - pc.z)
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	_walk_to(pc + away * 0.75, "")
	_show_toast("Altura medida. Indo até a estaca mais alta: lá toque em \"Cortar estaca\" e a marca já vem na altura medida.")


func _aimed_piece() -> Dictionary:
	if _constr == null or _cam == null:
		return {}
	var o: Vector3 = _cam.global_position
	var d: Vector3 = -_cam.global_transform.basis.z
	return _constr.aimed_piece(o, d, 2.6)


func _bld_start() -> void:
	if _carry.is_empty() or _constr == null:
		return
	var ghost: Node3D = _arvores.free_log_node(_carry)
	add_child(ghost)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 1.0, 0.3, 0.45)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in ghost.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var yaw := snappedf(_face, PI / 12.0)
	_bld = {"yaw": yaw, "tilt": 0.0, "roll": 0.0, "ghost": ghost, "mat": mat, "ok": false, "c": Vector3.ZERO, "b": Basis(),
		"modo": "girar", "fixo": false}
	if _carry_node:
		_carry_node.visible = false
	_bld_btn.visible = false
	for b in [_log_btn, _ctx_btn, _chop_btn, _pick_btn, _plant_btn, _work_btn, _vine_btn, _seed_btn]:
		(b as Control).visible = false
	for b in _bld_btns:
		(b as Control).visible = true
	_bld_pad.visible = true
	_bld_cross.visible = true
	_bld_mode("girar")
	_show_toast("Mire onde quer pôr a peça. Arraste a faixa de baixo para girar, inclinar, virar ou mover devagar.")


func _bld_stop() -> void:
	if _bld.is_empty():
		return
	(_bld.ghost as Node3D).queue_free()
	_bld = {}
	if _carry_node:
		_carry_node.visible = true
	for b in _bld_btns:
		(b as Control).visible = false
	_bld_pad.visible = false
	_bld_cross.visible = false
	_bld_why.visible = false
	_act_check = 0.0


## O que a faixa de arrastar mexe agora.
func _bld_mode(m: String) -> void:
	if _bld.is_empty():
		return
	_bld.modo = m
	var idx := {"girar": 1, "inclinar": 2, "virar": 3, "mover": 4, "altura": 5}
	for k in [1, 2, 3, 4, 5]:
		(_bld_btns[k] as Control).modulate = Color(1, 0.85, 0.3) if idx[m] == k else Color(1, 1, 1)
	if m in ["mover", "altura"] and not bool(_bld.fixo) and (_bld.ghost as Node3D).visible:
		_bld.fixo = true            # para de seguir a mira: fica onde está, e o dedo ajusta
		_bld.anchor = _bld.c
	_bld_pad_text()
	_bld_t = 0.0


## Volta a peça para onde o olho mira.
func _bld_follow() -> void:
	if _bld.is_empty():
		return
	_bld.fixo = false
	if str(_bld.modo) in ["mover", "altura"]:
		_bld_mode("girar")
	_bld_t = 0.0


func _bld_pad_text() -> void:
	var t := ""
	match str(_bld.modo):
		"girar": t = "Girar  %d°" % roundi(fposmod(rad_to_deg(float(_bld.yaw)), 360.0))
		"inclinar": t = "Inclinar  %d°" % roundi(rad_to_deg(float(_bld.tilt)))
		"virar": t = "Virar  %d°" % roundi(rad_to_deg(float(_bld.roll)))
		"mover": t = "Mover (lados / frente)"
		"altura": t = "Altura (cima / baixo)"
	(_bld_pad as Arrasto).set_text(t)


## O dedo andou na faixa: gira/inclina/vira (graus por pixel) ou move (cm por pixel).
func _bld_drag(d: Vector2) -> void:
	if not _buck_sel.is_empty():
		_buck_drag(d)
		return
	if not _proj.is_empty():
		_proj.yaw = float(_proj.yaw) - d.x * deg_to_rad(0.25)      # girando a planta
		return
	if _bld.is_empty():
		return
	var rot := deg_to_rad(0.25)
	match str(_bld.modo):
		"girar":
			_bld.yaw = float(_bld.yaw) - d.x * rot
		"inclinar":
			_bld.tilt = clampf(float(_bld.tilt) - d.x * rot, -PI * 0.5, PI * 0.5)
		"virar":
			_bld.roll = wrapf(float(_bld.roll) + d.x * rot, -PI, PI)
		"mover", "altura":
			if not bool(_bld.fixo):
				_bld.fixo = true
				_bld.anchor = _bld.c
			var cb: Basis = _cam.global_transform.basis
			var right := Vector3(cb.x.x, 0, cb.x.z).normalized()
			var fwd := Vector3(-cb.z.x, 0, -cb.z.z).normalized()
			var a: Vector3 = _bld.anchor
			if str(_bld.modo) == "mover":
				a += right * d.x * 0.002 - fwd * d.y * 0.002
			else:
				a.y -= d.y * 0.002
			_bld.anchor = a
	_bld_pad_text()
	_bld_t = 0.0                    # mostra na hora


func _bld_basis() -> Basis:
	return Basis(Vector3.UP, float(_bld.yaw)) * Basis(Vector3.BACK, float(_bld.tilt)) * Basis(Vector3.RIGHT, float(_bld.roll))


func _bld_update() -> void:
	if _carry.is_empty():
		_bld_stop()
		return
	for b in [_log_btn, _ctx_btn, _chop_btn, _pick_btn, _plant_btn, _work_btn, _vine_btn, _seed_btn, _bld_btn]:
		(b as Control).visible = false
	var b := _bld_basis()
	var ghost: Node3D = _bld.ghost
	var hb: Dictionary = {}
	var r: Dictionary
	if bool(_bld.get("fixo", false)):
		# parada onde o jogador deixou: só confere se dá para pôr ali
		var c0: Vector3 = _bld.anchor
		r = _constr.check(_carry, b, c0)
		r.c = c0
		r.b = b
		if not bool(r.ok):
			r.juntas = []
	else:
		var o: Vector3 = _cam.global_position
		var d: Vector3 = -_cam.global_transform.basis.z
		var hit: Dictionary = _constr.raycast(o, d, 6.0)
		if hit.is_empty():
			ghost.visible = false
			_bld.ok = false
			_bld.juntas = []
			(_bld_btns[0] as Button).text = "Colocar"
			_bld_why.visible = true
			_bld_why.text = "Mire mais perto (até uns 6 m)."
			return
		hb = hit.box
		r = _constr.find_place(_carry, b, hit)
		b = r.b
	# longe demais do jogador não
	if (r.c as Vector3).distance_to(_player.position + Vector3.UP * 0.9) > 4.5:
		r.ok = false
		r.why = "Longe demais."
	if not bool(r.ok) and not hb.is_empty() and hb.has("post"):
		# dica: estacas em alturas diferentes
		var po: Dictionary = hb.post
		var my: float = _buracos.post_top(po)
		var L: float = _arvores.free_log_length(_carry)
		for op in _buracos.posts:
			if op == po:
				continue
			if Vector2(float(op.x) - float(po.x), float(op.z) - float(po.z)).length() < L:
				var dh: float = absf(_buracos.post_top(op) - my)
				if dh > 0.04:
					r.why = "As estacas estão em alturas diferentes (%d cm). Com o machado: \"Cortar estaca\" na mais alta (ou \"Medir\" na mais baixa primeiro)." % roundi(dh * 100.0)
					break
	(_bld_btns[0] as Button).text = "Colocar"
	_bld_why.visible = not bool(r.ok) and str(r.get("why", "")) != ""
	_bld_why.text = str(r.get("why", ""))
	_bld.juntas = r.get("juntas", [])
	ghost.visible = true
	ghost.transform = Transform3D(b, r.c)
	_bld.ok = bool(r.ok)
	_bld.c = r.c
	_bld.b = b
	_bld.why = str(r.why)
	(_bld_btns[7] as Control).visible = bool(_bld.get("fixo", false))
	(_bld.mat as StandardMaterial3D).albedo_color = Color(0.2, 1.0, 0.3, 0.45) if bool(r.ok) else Color(1.0, 0.2, 0.15, 0.45)
	(_bld_btns[0] as Control).modulate = Color(1, 1, 1, 1.0 if bool(r.ok) else 0.45)


func _bld_place() -> void:
	if _bld.is_empty():
		return
	if not bool(_bld.ok):
		var why := str(_bld.get("why", ""))
		_show_toast(why if why != "" else "Não dá para pôr aqui.")
		return
	var fl := _carry
	var c: Vector3 = _bld.c
	var b: Basis = _bld.b
	_carry = {}
	if _carry_node:
		_carry_node.queue_free()
	_carry_node = null
	if _chop_pose:
		_chop_pose.log_node = null
	var juntas: Array = _bld.get("juntas", [])
	_constr.add(fl, b, c, juntas)
	Sons.play_at(self, "baque", c, -4.0)
	if juntas.size() > 0:
		_show_toast("Peça no lugar. Agora prenda com %d pino%s de madeira: pegue a marreta e toque em \"Fixar pinos\"." % [juntas.size(), "s" if juntas.size() > 1 else ""])
	_bld_stop()



# ================== MUNDO IGUAL PARA TODOS (MULTIPLAYER) ==================
# Cada parte do mundo que muda (construção, buracos e estacas, forquilhas, toras e
# árvores cortadas, galhos, pedras, coisas no chão, terra cavada, cupins, cipós...) é
# conferida algumas vezes por segundo; mudou aqui, vai para os outros. A natureza
# (crescer, cupins comendo, frutos) só roda no dono: os convidados recebem dele.

var _sync_hash := {}               # parte -> hash do que todos já têm
var _sync_t := {}                  # parte -> tempo até conferir de novo
const SYNC_EVERY := {"construcao": 0.4, "buracos": 0.4, "apoios": 0.4, "galhos": 0.6, "pedras": 0.6, "chao": 0.4,
	"escavacao": 0.5, "maquinas": 0.3, "arvores": 0.8, "cupins": 1.5, "cipos": 1.5, "bacabas": 3.0, "buritis": 0.6, "minerios": 3.0}
const SYNC_ONLY_HOST := ["bacabas"]        # só o dono manda (os bichos comem os frutos); buritis: degraus e folhas cortadas vêm de todos


func _mp_client() -> bool:
	return _rede != null and _rede.ativo() and _rede.modo == "convidado"


func _sync_tmp(nome: String) -> String:
	return "user://sync_%d_%s.json" % [OS.get_process_id(), nome]


func _file_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


## O estado da parte, em texto (o mesmo formato do arquivo salvo do mundo).
func _sync_get(nome: String) -> String:
	var tmp := _sync_tmp(nome)
	match nome:
		"chao":
			var chao := []
			for g in _chao:
				chao.append({"id": g.id, "qtd": g.qtd, "x": snappedf(float(g.x), 0.001), "z": snappedf(float(g.z), 0.001), "r": g.get("r", 0.0), "dur": g.get("dur", [])})
			return JSON.stringify(chao)
		"escavacao":
			# só a terra mexida (a água nos buracos sobe e desce sozinha em cada celular)
			var pts := []
			var ks: Array = _escav.d.keys()
			ks.sort()
			for k in ks:
				pts.append([k.x, k.y, snappedf(float(_escav.d[k]), 0.001)])
			var cl := []
			var cks: Array = _escav.clay.keys()
			cks.sort()
			for k in cks:
				cl.append([k.x, k.y])
			return JSON.stringify({"pontos": pts, "argila": cl})
	var mod = _sync_mod(nome)
	if mod == null:
		return ""
	mod.save(tmp)
	return _file_text(tmp)


func _sync_mod(nome: String):
	match nome:
		"construcao": return _constr
		"buracos": return _buracos
		"apoios": return _apoios
		"galhos": return _galhos
		"pedras": return _pedras
		"arvores": return _arvores
		"cupins": return _cupins
		"cipos": return _cipos
		"bacabas": return _bacabas
		"buritis": return _buritis
		"minerios": return _minerios
		"maquinas": return _maq
	return null


## Aplica o que chegou de outro jogador.
func _sync_set(nome: String, txt: String) -> void:
	match nome:
		"chao":
			var lst = JSON.parse_string(txt)
			if not lst is Array:
				return
			for g in _chao:
				if g.node:
					(g.node as Node3D).queue_free()
			_chao = []
			for e in lst:
				_add_ground(str(e.id), int(e.qtd), float(e.x), float(e.z), float(e.get("r", 0.0)), e.get("dur", []))
			_act_check = 0.0
			return
		"escavacao":
			var j = JSON.parse_string(txt)
			if not j is Dictionary:
				return
			var nd := {}
			for e in j.get("pontos", []):
				nd[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
			var ncl := {}
			for e in j.get("argila", []):
				ncl[Vector2i(int(e[0]), int(e[1]))] = true
			var touched := {}
			for k in _escav.d:
				touched[k] = true
			for k in nd:
				touched[k] = true
			_escav.d = nd
			_escav.clay = ncl
			_escav._changed(touched)
			_update_holes()
			return
	var mod = _sync_mod(nome)
	if mod == null:
		return
	var tmp := _sync_tmp(nome)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(txt)
	f.close()
	# o dia de cada parte: o convidado fica com o do dono; o dono nunca volta no tempo
	var has_day: bool = "last_day" in mod
	var keep_day: int = int(mod.last_day) if has_day else 0
	if has_day:
		mod.last_day = 1 << 30
	mod._load(tmp)
	if has_day and not _mp_client():
		mod.last_day = maxi(keep_day, int(mod.last_day))
	match nome:
		"pedras":
			mod._rebuild_all()
		"arvores":
			mod._rebuild()
			mod._rebuild_logs()
		"minerios":
			pass
		"buritis":
			mod._rebuild()
			_buriti_relink()
		_:
			mod._rebuild()
	_act_check = 0.0


## Os buritis chegaram de outro jogador (dicionários novos): quem está na escada ou
## furando/cortando continua no mesmo buriti (achado pelo lugar).
func _buriti_relink() -> void:
	var find := func(old: Dictionary) -> Dictionary:
		for q in _buritis.palms + _buritis.caidos:
			if absf(float(q.x) - float(old.x)) < 0.01 and absf(float(q.z) - float(old.z)) < 0.01:
				return q
		return {}
	for st in [_bur, _olho]:
		if not st.is_empty():
			var nb: Dictionary = find.call(st.p)
			if nb.is_empty():
				st.clear()
			else:
				st.p = nb
	if not _chop_bur.is_empty():
		var nc: Dictionary = find.call(_chop_bur)
		if nc.is_empty():
			_cancel_chop()
		else:
			_chop_bur = nc
	if not _pin.is_empty() and _pin.has("alvos"):
		for al in _pin.alvos:
			if (al as Dictionary).has("bp"):
				var nb: Dictionary = find.call(al.bp)
				if not nb.is_empty():
					al.bp = nb


## Depois de entrar (ou de receber): o que tem aqui é o que todos têm.
func _sync_baseline() -> void:
	for nome in SYNC_EVERY:
		_sync_hash[nome] = _sync_get(nome).hash()
		_sync_t[nome] = randf() * float(SYNC_EVERY[nome])


func _sync_receive(nome: String, txt: String) -> void:
	if not _ready_world or not SYNC_EVERY.has(nome):
		return
	_sync_set(nome, txt)
	_sync_hash[nome] = _sync_get(nome).hash()       # o que ficou aqui agora (não manda de volta)


func _sync_tick(delta: float) -> void:
	if _rede == null or not _rede.ativo() or not _ready_world:
		return
	for nome in SYNC_EVERY:
		_sync_t[nome] = float(_sync_t.get(nome, 0.0)) - delta
		if float(_sync_t[nome]) > 0.0:
			continue
		_sync_t[nome] = float(SYNC_EVERY[nome])
		if _mp_client() and nome in SYNC_ONLY_HOST:
			continue
		var txt := _sync_get(nome)
		var h := txt.hash()
		if h != int(_sync_hash.get(nome, 0)):
			_sync_hash[nome] = h
			_rede.mandar_parte(nome, txt)



# ================== PROJETOS (MÁQUINAS POR PLANTA) ==================

func _open_projetos() -> void:
	if _proj_ui != null or _craft_ui != null or _bag_ui != null or _cal != null or not _ready_world:
		return
	_joy_id = -1
	_joy_vec = Vector2.ZERO
	_look_id = -1
	_proj_ui = Projetos.new()
	_hud.add_child(_proj_ui)
	_proj_ui.abrir(self)
	_proj_ui.escolheu.connect(_proj_start)
	_proj_ui.closed.connect(func(): _proj_ui = null)


## Começa a pôr a planta no chão: o desenho dela (azul) na frente do jogador.
func _proj_start(tipo: String) -> void:
	if not _bld.is_empty():
		_bld_stop()
	var ghost := Node3D.new()
	add_child(ghost)
	var t: Dictionary = Maquinas.TIPOS[tipo]
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.35, 0.65, 1.0, 0.4)
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for pc in t.pecas:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var r := float(pc[4])
		bm.size = Vector3(float(pc[1]), r * 2.0, r * 2.0)
		mi.mesh = bm
		mi.material_override = gm
		mi.transform = Transform3D(Maquinas.slot_basis(str(pc[3])), pc[2])
		ghost.add_child(mi)
	_proj = {"tipo": tipo, "yaw": _face + PI * 0.5, "ghost": ghost, "mat": gm, "ok": false, "c": Vector3.ZERO}
	for b in _proj_btns:
		(b as Control).visible = true
	_bld_pad.visible = true
	(_bld_pad as Arrasto).set_text("Girar a planta")
	_show_toast("Arraste a faixa para girar a planta. Verde: dá para pôr aqui.")


func _proj_stop() -> void:
	if _proj.is_empty():
		return
	(_proj.ghost as Node3D).queue_free()
	_proj = {}
	for b in _proj_btns:
		(b as Control).visible = false
	_bld_pad.visible = false
	_bld_why.visible = false
	_act_check = 0.0


func _proj_tick() -> void:
	for b in [_log_btn, _ctx_btn, _chop_btn, _pick_btn, _plant_btn, _work_btn, _vine_btn, _seed_btn, _bld_btn]:
		(b as Control).visible = false
	var fwd := Vector3(-sin(_face), 0, -cos(_face))
	var c := _player.position + fwd * 3.2
	c.y = surface_at(c.x, c.z)
	var t: Dictionary = Maquinas.TIPOS[_proj.tipo]
	var ar: Rect2 = t.area
	var b := Basis(Vector3.UP, float(_proj.yaw))
	# o chão embaixo da planta precisa ser quase reto e seco, e longe de outra planta
	var why := ""
	var hs := []
	for fx in [0.0, 1.0]:
		for fz in [0.0, 1.0]:
			var l := Vector3(ar.position.x + ar.size.x * fx, 0, ar.position.y + ar.size.y * fz)
			var w := c + b * l
			hs.append(surface_at(w.x, w.z))
			var cell := Vector2i(int(w.x / CELL), int(w.z / CELL))
			if _water_level.size() == MundoSim.W * MundoSim.H and cell.x >= 0 and cell.y >= 0 and cell.x < MundoSim.W and cell.y < MundoSim.H:
				if _water_level[cell.y * MundoSim.W + cell.x] > height_at(w.x, w.z) + 0.02:
					why = "Tem água embaixo."
	if hs.max() - hs.min() > 0.45:
		why = "O chão é torto demais aqui (procure um lugar mais plano)."
	if _maq.planta_near(c, 4.0) >= 0:
		why = "Muito perto de outra planta."
	_proj.ok = why == ""
	_proj.c = c
	(_proj.ghost as Node3D).transform = Transform3D(b, c)
	(_proj.mat as StandardMaterial3D).albedo_color = Color(0.35, 0.65, 1.0, 0.4) if why == "" else Color(1.0, 0.25, 0.2, 0.4)
	_bld_why.visible = why != ""
	_bld_why.text = why


func _proj_place() -> void:
	if _proj.is_empty():
		return
	if not bool(_proj.ok):
		_show_toast(str(_bld_why.text))
		return
	var c: Vector3 = _proj.c
	_maq.add_planta(str(_proj.tipo), c.x, c.z, float(_proj.yaw))
	_proj_stop()
	if teste:
		_maq.complete(_maq.plantas.size() - 1)        # modo de teste: já sai montada
		_show_toast("Modo de teste: a %s já ficou pronta." % str(Maquinas.TIPOS[_maq.plantas[-1].tipo].nome).to_lower())
		return
	_show_toast("Planta no chão! Traga as madeiras e toque em \"Pôr na planta\" perto dela. Depois fure e bata os pinos nas juntas (bolinhas amarelas).")


## Decide o botão de contexto perto de uma planta/máquina. true se pôs algum.
func _maq_ctx() -> bool:
	var mi: int = _maq.planta_near(_player.position, 5.0)     # a serra tem 6 m: as pontas ficam longe do meio
	if mi < 0:
		return false
	var p: Dictionary = _maq.plantas[mi]
	if _maq.pronta(mi):
		var role: String = _maq.role_at(mi, _player.position)
		if role == "pedal" and _carry.is_empty():
			_ctx_action = "pedalar"
			_ctx_btn.text = "Pedalar"
			return true
		if role == "mesa":
			if (p.tora as Dictionary).is_empty() and not _carry.is_empty():
				_ctx_action = "tora_serra"
				_ctx_btn.text = "Pôr tora na serra"
				return true
			if not (p.tora as Dictionary).is_empty() and _carry.is_empty():
				_ctx_action = "empurrar"
				_ctx_btn.text = "Empurrar a tora"
				return true
		if role == "saida" and _carry.is_empty() and not (p.get("saida", []) as Array).is_empty():
			var sa: Array = p.saida
			_ctx_action = "saida_pegar"
			_ctx_btn.text = "Pegar %s (%d)" % ["tábua" if _maq.kind_of(sa[0]) == "tabua" else "peça", sa.size()]
			return true
		return false
	if not _carry.is_empty():
		_ctx_action = "planta_peca"
		_ctx_btn.text = "Pôr na planta"
		return true
	var lit := str(Maquinas.TIPOS[p.tipo].get("lamina_item", "lamina_serra"))
	if _maq.lamina_open(mi) and (item_qtd(lit) > 0 or teste) and _carry.is_empty():
		_ctx_action = "planta_lamina"
		var nl: int = Maquinas.lamina_need(str(p.tipo))
		_ctx_btn.text = "Pôr a lâmina" if nl == 1 else "Pôr lâmina de faca (%d/%d)" % [_maq.lamina_count(mi) + 1, nl]
		return true
	var sb: Array = _maq.sobra_near(_player.position, 1.8)
	if not sb.is_empty() and _carry.is_empty():
		var inf: Dictionary = _maq.sobra_info(int(sb[0]), int(sb[1]))
		_ctx_action = "sobra"
		_ctx_btn.text = ("Serrar a ponta (%d cm)" if bool(inf.deitada) else "Cortar a ponta (%d cm)") % roundi(float(inf.len) * 100.0)
		return true
	return false


func _maq_ctx_press(act: String) -> void:
	var mi: int = _maq.planta_near(_player.position, 5.0)     # a serra tem 6 m: as pontas ficam longe do meio
	if mi < 0:
		return
	match act:
		"planta_peca":
			var pw: Dictionary = _maq.pending_work(mi)
			if int(pw.furos) + int(pw.pinos) + int(pw.pontas) > 0:
				var falta := []
				if int(pw.furos) > 0:
					falta.append("%d furo%s" % [pw.furos, "" if int(pw.furos) == 1 else "s"])
				if int(pw.pinos) > 0:
					falta.append("%d pino%s" % [pw.pinos, "" if int(pw.pinos) == 1 else "s"])
				if int(pw.pontas) > 0:
					falta.append("%d ponta%s para cortar" % [pw.pontas, "" if int(pw.pontas) == 1 else "s"])
				_show_toast("Termine a madeira que já está na planta antes de pôr outra: falta%s %s." % ["m" if falta.size() > 1 or int(pw.furos) + int(pw.pinos) + int(pw.pontas) > 1 else "", ", ".join(falta)])
				return
			var r: Dictionary = _maq.slot_for(mi, _carry, _player.position)
			if int(r.i) < 0:
				_show_toast(str(r.why))
				return
			var placed: Dictionary = _carry
			_carry = {}
			if _carry_node:
				_carry_node.queue_free()
			_carry_node = null
			if _chop_pose:
				_chop_pose.log_node = null
			_maq.fill_slot(mi, int(r.i), float(r.get("sobra", 0.0)), placed)
			var falta: int = (_maq.plantas[mi].pecas as Array).size() - _maq.done_count(mi)
			Sons.play_at(self, "baque", _player.position, -6.0)
			var sob := float(r.get("sobra", 0.0))
			var pw2: Dictionary = _maq.pending_work(mi)
			_show_toast("Peça no lugar! " + ("Sobrou %d cm para fora: corte a ponta. " % roundi(sob * 100.0) if sob > 0.015 else "") + ("Agora fure e ponha %d pino%s nas juntas dela. " % [pw2.furos, "" if int(pw2.furos) == 1 else "s"] if int(pw2.furos) > 0 else "") + ("Faltam %d peças." % falta if falta > 0 else "Todas as madeiras estão no lugar."))
		"planta_lamina":
			var lit2 := str(Maquinas.TIPOS[_maq.plantas[mi].tipo].get("lamina_item", "lamina_serra"))
			if not teste:
				remove_item(lit2, 1)
				_update_inventory()
			_maq.add_lamina(mi)
			Sons.play_at(self, "pedra_bate", _maq.xform(mi).origin + Vector3.UP, -8.0, 1.3)
			if lit2 == "lamina_faca":
				var nl2: int = Maquinas.lamina_need(str(_maq.plantas[mi].tipo))
				var tem: int = _maq.lamina_count(mi)
				_show_toast(("Lâmina de faca encaixada em pé na bancada (%d de %d)." % [tem, nl2]) + (" A desfibradeira está pronta!" if _maq.pronta(mi) else ""))
			else:
				_show_toast("Lâmina presa entre as colunas, com os dentes virados para a mesa.")
		"sobra":
			var sb: Array = _maq.sobra_near(_player.position, 1.8)
			if sb.is_empty():
				return
			var inf: Dictionary = _maq.sobra_info(int(sb[0]), int(sb[1]))
			var tool := "serra" if bool(inf.deitada) else "machado"
			if item_qtd(tool) <= 0 and not teste:
				_show_toast("Precisa de %s para cortar essa ponta." % ("uma serra (a peça está deitada)" if tool == "serra" else "um machado (a peça está em pé)"))
				return
			_trim_start(int(sb[0]), int(sb[1]), tool)
		"saida_pegar":
			var pfl: Dictionary = _maq.take_saida(mi)
			if not pfl.is_empty():
				_hold_log(pfl)
				Sons.play_at(self, "baque", _player.position + Vector3.UP, -10.0)
				var rest: int = (_maq.plantas[mi].get("saida", []) as Array).size()
				_show_toast("Pegou da mesa de saída." + (" Ainda tem %d peça lá." % rest if rest > 0 else " Para tirar outra fatia, ponha a tora de novo na mesa de entrada."))
		"tora_serra":
			var Lc: float = _arvores.free_log_length(_carry)
			if Lc < 0.6 or Lc > 2.6:
				_show_toast("Na serra vai madeira de 60 cm a 2,6 m (o tamanho da mesa).")
				return
			if _arvores.free_log_max_radius(_carry) > 0.3:
				_show_toast("Tora grossa demais para essa serra (até uns 60 cm de largura).")
				return
			if not (_maq.plantas[mi].get("saida", []) as Array).is_empty():
				_show_toast("Tire antes as peças que estão na mesa do outro lado da serra.")
				return
			if not bool(_maq.cut_plan(_carry).ok):
				_show_toast("Essa madeira já está fina demais para tirar outra fatia.")
				return
			var fl := _carry
			_carry = {}
			if _carry_node:
				_carry_node.queue_free()
			_carry_node = null
			if _chop_pose:
				_chop_pose.log_node = null
			_maq.load_log(mi, fl)
			_show_toast("Tora na mesa. Um pedala e o outro empurra a tora contra a serra.")
		"pedalar", "empurrar":
			_maq_op_start(mi, "pedal" if act == "pedalar" else "mesa")


## Na serra: o controle de pedalar (trilho de subir e descer o pé) ou de empurrar
## (faixa de arrastar para o lado da lâmina).
func _maq_op_start(mi: int, role: String) -> void:
	var ctrl: Control
	if role == "pedal":
		ctrl = SerraCtrl.new()
		ctrl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		ctrl.offset_left = -150
		ctrl.offset_right = -30
		ctrl.offset_top = -470
		ctrl.offset_bottom = -20
	else:
		ctrl = Arrasto.new()
		ctrl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		ctrl.offset_left = 30
		ctrl.offset_right = 520
		ctrl.offset_top = -150
		ctrl.offset_bottom = -30
		(ctrl as Arrasto).set_text("◀  Empurre a tora para a serra")
	_hud.add_child(ctrl)
	_maq_op = {"mi": mi, "papel": role, "ctrl": ctrl, "last": 0.5, "pedal": 0.0, "emp": 0.0, "acc": 0.0}
	if role == "mesa":
		(ctrl as Arrasto).arrastou.connect(func(d: Vector2):
			if not _maq_op.is_empty():
				_maq_op.acc = float(_maq_op.acc) + maxf(0.0, -d.x))
	_maq_stop.visible = true
	_jump_btn.visible = false
	for b in [_log_btn, _ctx_btn, _work_btn, _pick_btn, _vine_btn, _plant_btn, _chop_btn, _bld_btn]:
		(b as Control).visible = false
	_show_toast("Suba e desça o pedal com o dedo." if role == "pedal" else "Arraste para a esquerda (para a lâmina) para empurrar a tora.")


func _maq_op_stop() -> void:
	if not _trim.is_empty():
		_trim_end()                 # o mesmo botão Parar serve para o corte da ponta
		return
	if _maq_op.is_empty():
		return
	(_maq_op.ctrl as Node).queue_free()
	_maq.inputs.erase(_my_id())
	_maq_op = {}
	_maq_stop.visible = false
	_bld_why.visible = false
	_jump_btn.visible = true
	_act_check = 0.0


func _my_id() -> int:
	return multiplayer.get_unique_id() if _rede and _rede.ativo() else 1


func _maq_op_tick(delta: float) -> void:
	var mi := int(_maq_op.mi)
	if mi >= _maq.plantas.size() or _maq.role_at(mi, _player.position) != str(_maq_op.papel):
		_maq_op_stop()
		return
	# o pé no pedal: a velocidade do pegador subindo e descendo
	if str(_maq_op.papel) == "pedal":
		var v := float(_maq_op.ctrl.value)
		var spd := absf(v - float(_maq_op.last)) / maxf(delta, 0.001)
		_maq_op.last = v
		_maq_op.pedal = lerpf(float(_maq_op.pedal), clampf(spd / 2.0, 0.0, 2.0), minf(1.0, delta * 4.0))
	else:
		var push := float(_maq_op.acc) / maxf(delta, 0.001) / 300.0
		_maq_op.acc = 0.0
		_maq_op.emp = lerpf(float(_maq_op.emp), clampf(push, 0.0, 2.0), minf(1.0, delta * 5.0))
		var p: Dictionary = _maq.plantas[mi]
		if (p.tora as Dictionary).is_empty():
			_maq_op_stop()
			return
		var ped := float(p.get("_pedal", 0.0))
		_bld_why.visible = float(_maq_op.emp) > 0.1 and ped < 0.05
		_bld_why.text = "Precisa de alguém pisando no pedal (a serra só funciona em dupla)."
	_maq.inputs[_my_id()] = {"mi": mi, "pedal": float(_maq_op.pedal), "emp": float(_maq_op.emp), "t": Time.get_ticks_msec()}



# ================== PINOS DE MADEIRA ==================
# Toda madeira posta (construção ou planta) fica com lugares de pino. Com a marreta:
# "Fixar pinos" mostra um losango em cada lugar; toca num, o personagem chega perto,
# põe o pino no furo e bate com a marreta na barrinha de acerto (a mesma da cunha):
# verde afunda, laranja quase, vermelho quebra o pino (perde ele). 3 batidas boas
# e o pino fica rente à madeira.

const PIN_HITS := 3


func _pin_targets() -> Array:
	var out := []
	if _constr:
		for t in _constr.pin_targets(_player.position):
			out.append({"kind": "c", "pc": t.pc, "k": t.k, "pos": t.pos, "stage": t.stage})
	if _maq:
		for t in _maq.pin_targets(_player.position):
			out.append({"kind": "m", "mi": t.mi, "ji": t.ji, "pos": t.pos, "stage": t.stage})
	return out


func _pin_start() -> void:
	_pin = {"alvos": _pin_targets(), "sel": -1, "depth": 0.0, "t": 0.0, "speed": 0.4, "gw": 0.3, "gc": 0.5,
		"anim": -1.0, "ok": false, "node": null, "refresh": 0.5}
	_pin_new_timing()
	_build_pin_ui()
	for b in [_log_btn, _ctx_btn, _chop_btn, _pick_btn, _plant_btn, _work_btn, _vine_btn, _seed_btn, _bld_btn]:
		(b as Control).visible = false
	_show_toast("Toque num losango: \"Furar\" põe a ponteira de pedra, \"Pino\" põe o pino no furo. Bata com a marreta quando o marcador estiver no verde.")


func _pin_end() -> void:
	if _pin.is_empty():
		return
	if _pin.node and is_instance_valid(_pin.node):
		(_pin.node as Node).queue_free()
	if _pin.get("knife") != null and is_instance_valid(_pin.knife):
		(_pin.knife as Node).queue_free()
		if _chop_pose:
			_chop_pose.holding = _mao in ["machado", "cavadeira", "serra", "pedra", "pa", "balde", "marreta", "faca"]
	_pin = {}
	if _pin_ui:
		_pin_ui.queue_free()
		_pin_ui = null
	if _chop_pose:
		_chop_pose.ready_pose = false
		_chop_pose.swinging = false
		_chop_pose.vertical = false
	_act_check = 0.0


func _pin_new_timing() -> void:
	_pin.speed = randf_range(0.3, 0.55)
	_pin.gw = randf_range(0.2, 0.32)
	_pin.gc = randf_range(0.25, 0.75)
	_pin.t = randf() * 4.0


func _pin_marker() -> float:
	var x := fmod(float(_pin.t) * float(_pin.speed), 2.0)
	return x if x <= 1.0 else 2.0 - x


## Toque: escolhe o losango (true = usou o toque; senão anda/gira a câmera normal).
func _pin_input(e: InputEvent) -> bool:
	var pos := Vector2.INF
	if e is InputEventScreenTouch and e.pressed:
		pos = e.position
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
	if pos == Vector2.INF or float(_pin.anim) >= 0.0:
		return false
	if _pin_ui:
		for c in _pin_ui.get_children():
			if c is Button and (c as Button).visible and (c as Button).get_global_rect().has_point(pos):
				return true          # é botão (Bater/Sair): deixa o botão tratar
	var alvos: Array = _pin.alvos
	for k in alvos.size():
		var w: Vector3 = alvos[k].pos
		if _cam.is_position_behind(w):
			continue
		if pos.distance_to(_cam.unproject_position(w)) < 80.0:
			_pin_pick(k)
			return true
	return false


func _pin_pick(k: int) -> void:
	if int(_pin.sel) >= 0:
		_show_toast("Termine esse pino primeiro (ou ele quebra se você sair).")
		return
	var stg := int(_pin.alvos[k].get("stage", 0))
	if str(_pin.alvos[k].kind) in ["folha", "talo"]:
		stg = 9
		if item_qtd("faca") <= 0:
			_show_toast("Precisa de uma faca de pedra (lâmina de faca + galho + cipó, no craft).")
			return
	if stg == 0 and item_qtd("furador") <= 0 and not teste:
		_show_toast("Precisa de um furador para abrir o furo (ponta de pedra + galho + cipó, no craft).")
		return
	if stg == 1 and item_qtd("pino") <= 0 and not teste:
		_show_toast("Acabaram os pinos. Faça mais no craft com mata-juntas.")
		return
	_pin.go = k
	var w: Vector3 = _pin.alvos[k].pos
	var d := Vector2(w.x - _player.position.x, w.z - _player.position.z)
	if str(_pin.alvos[k].kind) in ["folha", "talo"]:
		# o talo: chega perto (uns 70 cm, de frente para ele) e aí começa a cortar
		var dl := Vector2(w.x - _player.position.x, w.z - _player.position.z)
		if dl.length() > 0.95:
			var spot2 := Vector3(w.x, 0, w.z) - Vector3(dl.x, 0, dl.y).normalized() * 0.7
			_walk_to(_ground_pos(Vector2(spot2.x, spot2.z)), "pino")
		else:
			_pin_ready()
	elif d.length() > 1.1:
		var spot := Vector3(w.x, 0, w.z) - Vector3(d.x, 0, d.y).normalized() * 0.8
		_walk_to(_ground_pos(Vector2(spot.x, spot.z)), "pino")
	else:
		_pin_ready()


## Chegou: põe o pino no furo (em pé, metade para fora) e prepara a marreta.
func _pin_ready() -> void:
	if _pin.is_empty():
		return
	var k := int(_pin.get("go", -1))
	if k < 0 or k >= (_pin.alvos as Array).size():
		return
	var w: Vector3 = _pin.alvos[k].pos
	_pin.sel = k
	_pin.depth = 0.0
	_pin.stage = int(_pin.alvos[k].get("stage", 0))
	if str(_pin.alvos[k].kind) in ["folha", "talo"]:
		_pin.stage = 9
	var mi: Node3D
	if int(_pin.stage) == 9:
		mi = _talho_node(_pin.alvos[k])          # o corte no talo (vai abrindo a cada golpe)
	elif int(_pin.stage) == 0:
		mi = _ponteira_node()
	else:
		var pm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.012
		cm.height = 0.16
		pm.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.62, 0.47, 0.3)
		pm.material_override = m
		mi = pm
	add_child(mi)
	_pin.node = mi
	_pin_place_node()
	_face_to(w)
	_yaw = _face
	var eye := _player.global_position + Vector3.UP * 1.6
	var hd := Vector2(w.x - eye.x, w.z - eye.z).length()
	_pitch = clampf(atan2(eye.y - w.y, maxf(hd, 0.1)) - 0.05, -0.4, 1.2)
	var tool := "faca" if int(_pin.stage) == 9 else "marreta"
	if _mao != tool:
		equip(tool)
	if int(_pin.stage) == 9:
		# a faca na mão (só ela aparece, como as outras ferramentas): golpe próprio, que
		# vai exatamente no talo
		if _chop_pose:
			_chop_pose.holding = false
			_chop_pose.ready_pose = false
			_chop_pose.vertical = false
		if _pin.get("knife") == null or not is_instance_valid(_pin.knife):
			var kn := MeshInstance3D.new()
			kn.mesh = Corte.faca_mesh()
			var km: StandardMaterial3D = Corte.axe_material().duplicate()
			km.no_depth_test = true          # primeira pessoa: a faca na mão nunca some atrás do talo
			km.render_priority = 10
			kn.material_override = km
			kn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(kn)
			_pin.knife = kn
		_pin_new_timing()
		_knife_pose(-1.0)
		return
	if _chop_pose:
		var top_h: float = w.y - _player.global_position.y
		_chop_pose.vertical = true
		# o golpe termina na altura do talo: do chão até acima da cabeça
		_chop_pose.down_hit = clampf(-42.0 + 28.0 * top_h / 0.95, -42.0, 25.0)
		_chop_pose.ready_pose = true
		_chop_pose.swinging = false
	_pin_new_timing()


func _pin_place_node() -> void:
	var k := int(_pin.sel)
	if k < 0 or _pin.node == null:
		return
	var w: Vector3 = _pin.alvos[k].pos
	if int(_pin.stage) == 9:
		# o corte no talo vai abrindo (mais largo e mais claro a cada golpe bom)
		var al: Dictionary = _pin.alvos[k]
		var dpt := float(_pin.depth)
		var band := (_pin.node as Node3D).get_child(0) as MeshInstance3D
		var cm := band.mesh as CylinderMesh
		cm.height = 0.006 + 0.03 * dpt
		var rr := float(al.get("r", 0.04))
		cm.top_radius = rr * (0.8 - 0.25 * dpt)
		cm.bottom_radius = rr * (0.8 - 0.25 * dpt)
		band.visible = dpt > 0.01
		(_pin.node as Node3D).position = w
	elif int(_pin.stage) == 0:
		# a ponteira em pé com a ponta na madeira; vai entrando a cada batida boa
		(_pin.node as Node3D).position = w - Vector3.UP * 0.07 * float(_pin.depth)
	else:
		# a parte de fora do pino vai sumindo a cada batida boa
		(_pin.node as Node3D).position = w + Vector3.UP * (0.08 - 0.075 * float(_pin.depth))


## A ponteira (furador): cabo de galho com a ponta de pedra amarrada, ponta para baixo.
func _ponteira_node() -> Node3D:
	var root := Node3D.new()
	var cabo := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.022
	cm.bottom_radius = 0.02
	cm.height = 0.24
	cabo.mesh = cm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.45, 0.3, 0.17)
	cabo.material_override = wm
	cabo.position = Vector3(0, 0.17, 0)
	root.add_child(cabo)
	var tip := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.024
	tc.bottom_radius = 0.002
	tc.height = 0.07
	tc.radial_segments = 6
	tip.mesh = tc
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.4, 0.4, 0.38)
	sm.roughness = 0.8
	tip.material_override = sm
	tip.position = Vector3(0, 0.035, 0)
	root.add_child(tip)
	var amarra := MeshInstance3D.new()
	var am := CylinderMesh.new()
	am.top_radius = 0.027
	am.bottom_radius = 0.027
	am.height = 0.045
	amarra.mesh = am
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.5, 0.42, 0.22)
	amarra.material_override = cmat
	amarra.position = Vector3(0, 0.075, 0)
	root.add_child(amarra)
	return root


func _pin_hit() -> void:
	if _pin.is_empty() or int(_pin.sel) < 0 or float(_pin.anim) >= 0.0 or _walking:
		return
	if int(_pin.get("stage", 0)) != 9 and item_qtd("marreta") <= 0 and not teste:
		_show_toast("Precisa da marreta.")
		return
	_pin.t = float(_pin.t) - 0.06
	var m := _pin_marker()
	_pin.frozen = m
	var d := absf(m - float(_pin.gc)) - float(_pin.gw) * 0.5
	if d > 0.01 and d <= KNAP_EDGE:
		_show_toast("Quase! Bata no verde.")
		return
	_pin.ok = d <= 0.01
	_pin.anim = 0.0
	_pin.fired = false
	if _chop_pose and int(_pin.get("stage", 0)) != 9:
		_chop_pose.swinging = true
		_chop_pose.phase = 0.0


func _pin_tick(delta: float) -> void:
	for b in [_log_btn, _ctx_btn, _chop_btn, _pick_btn, _plant_btn, _work_btn, _vine_btn, _seed_btn, _bld_btn]:
		(b as Control).visible = false
	_pin.t = float(_pin.t) + delta
	_pin.refresh = float(_pin.refresh) - delta
	if float(_pin.refresh) <= 0.0 and int(_pin.sel) < 0 and not bool(_pin.get("folhas", false)):
		_pin.refresh = 0.5
		_pin.alvos = _pin_targets()
	if _pin.get("knife") != null and is_instance_valid(_pin.knife):
		_knife_pose(clampf(float(_pin.anim) / 0.6, 0.0, 1.0) if float(_pin.anim) >= 0.0 else -1.0)
	if float(_pin.anim) >= 0.0:
		_pin.anim = float(_pin.anim) + delta
		var ph := clampf(float(_pin.anim) / (0.6 if int(_pin.get("stage", 0)) == 9 else 0.45), 0.0, 1.0)
		if _chop_pose and int(_pin.get("stage", 0)) != 9:
			_chop_pose.phase = ph
		if ph >= 0.55 and not bool(_pin.fired):
			_pin.fired = true
			_pin_strike()
		if ph >= 1.0:
			_pin.anim = -1.0
			if _chop_pose:
				_chop_pose.swinging = false
			_pin_new_timing()
	if _pin_ui:
		var hit: Control = _pin_ui.get_node("hit")
		hit.visible = int(_pin.sel) >= 0 and not _walking
		var il: Label = _pin_ui.get_node("info/il")
		var nf := 0
		for a in _pin.alvos:
			if int(a.get("stage", 0)) == 0:
				nf += 1
		if bool(_pin.get("folhas", false)):
			il.text = "Facas na mochila: %d\nFaca: %d%% · talo cortado %d%%" % [item_qtd("faca"), int(round(tool_dur("faca") * 100.0)), int(float(_pin.depth) * 100.0)]
		else:
			il.text = "Pinos na mochila: %s\nFaltam %d furos e %d pinos aqui perto" % ["∞ (teste)" if teste else str(item_qtd("pino")), nf, (_pin.alvos as Array).size() - nf]
		(_pin_ui.get_node("mk") as Control).queue_redraw()
		(_pin_ui.get_node("tb") as Control).queue_redraw()


## A marreta bateu no pino.
func _pin_strike() -> void:
	var k := int(_pin.sel)
	if k < 0:
		return
	var al: Dictionary = _pin.alvos[k]
	var w: Vector3 = al.pos
	if int(_pin.stage) == 9:
		_leaf_strike(al, w)
		return
	if int(_pin.stage) == 0:
		# furando: a ponteira entra; 4 batidas boas atravessam a madeira
		wear("furador")
		if bool(_pin.ok):
			_pin.depth = float(_pin.depth) + 0.25
			Sons.play_at(self, "machado", w, -6.0, 1.5)
			_chips(w)
			wear("marreta")
			if float(_pin.depth) >= 0.99:
				if str(al.kind) == "c":
					_constr.set_stage(al.pc, int(al.k), 1)
				else:
					_maq.set_stage(int(al.mi), int(al.ji), 1)
				(_pin.node as Node).queue_free()
				_pin.node = null
				_pin.sel = -1
				_pin.alvos = _pin_targets()
				_show_toast("Furou! Agora o losango vira \"Pino\": ponha o pino no furo e bata.")
			else:
				_pin_place_node()
		else:
			Sons.play_at(self, "estalo", w, -8.0, 1.6)
			_show_toast("A ponteira escorregou. Bata no verde.")
		return
	if bool(_pin.ok):
		_pin.depth = float(_pin.depth) + 1.0 / PIN_HITS
		Sons.play_at(self, "machado", w, -4.0, 1.35)
		_chips(w)
		wear("marreta")
		if float(_pin.depth) >= 0.99:
			if not teste:
				remove_item("pino", 1)
				_update_inventory()
			if str(al.kind) == "c":
				_constr.pin_done(al.pc, int(al.k))
			else:
				_maq.tie(int(al.mi), int(al.ji))
			(_pin.node as Node).queue_free()
			_pin.node = null
			_pin.sel = -1
			_pin.alvos = _pin_targets()
			var pronta: bool = str(al.kind) == "m" and _maq.pronta(int(al.mi))
			_show_toast("Pino batido! " + ("A serra está pronta!" if pronta else ("Faltam %d aqui perto." % (_pin.alvos as Array).size() if not (_pin.alvos as Array).is_empty() else "Todos os pinos daqui estão batidos.")))
		else:
			_pin_place_node()
	else:
		# pegou torto: o pino racha e não serve mais
		Sons.play_at(self, "estalo", w, -2.0, 1.2)
		if not teste:
			remove_item("pino", 1)
			_update_inventory()
		(_pin.node as Node).queue_free()
		_pin.node = null
		_pin.sel = -1
		_show_toast("A marreta pegou torto e o pino rachou! Ponha outro.")


func _build_pin_ui() -> void:
	_pin_ui = Control.new()
	_pin_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pin_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_pin_ui)
	var info := PanelContainer.new()
	info.name = "info"
	info.offset_left = 16
	info.offset_top = 90
	info.offset_right = 360
	info.offset_bottom = 170
	info.add_theme_stylebox_override("panel", Mochila._box(Color(0.05, 0.05, 0.04, 0.82), Color(1, 1, 1, 0.18), 2, 8))
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var il := Label.new()
	il.name = "il"
	il.add_theme_font_size_override("font_size", 17)
	info.add_child(il)
	_pin_ui.add_child(info)
	var mk := Control.new()
	mk.name = "mk"
	mk.set_anchors_preset(Control.PRESET_FULL_RECT)
	mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mk.draw.connect(func(): _draw_pin_marks(mk))
	_pin_ui.add_child(mk)
	var tb := Control.new()
	tb.name = "tb"
	tb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tb.offset_left = -270
	tb.offset_right = 270
	tb.offset_top = -110
	tb.offset_bottom = -30
	tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.draw.connect(func(): _draw_pin_bar(tb))
	_pin_ui.add_child(tb)
	var hit := Icones.IconButton.new()
	hit.name = "hit"
	hit.text = "Bater"
	hit.add_theme_font_size_override("font_size", 22)
	hit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hit.offset_left = -190
	hit.offset_top = -190
	hit.offset_right = -30
	hit.offset_bottom = -30
	hit.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	hit.pressed.connect(_pin_hit)
	hit.visible = false
	_pin_ui.add_child(hit)
	var out := Icones.IconButton.new()
	out.text = "Sair"
	out.add_theme_font_size_override("font_size", 20)
	out.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	out.offset_left = -360
	out.offset_top = -160
	out.offset_right = -230
	out.offset_bottom = -30
	out.pressed.connect(_pin_end)
	_pin_ui.add_child(out)


func _draw_pin_marks(mk: Control) -> void:
	if _pin.is_empty():
		return
	var font := ThemeDB.fallback_font
	var tsec := Time.get_ticks_msec() / 1000.0
	var alvos: Array = _pin.alvos
	for k in alvos.size():
		var w: Vector3 = alvos[k].pos
		if _cam.is_position_behind(w):
			continue
		var p := _cam.unproject_position(w)
		var sel := k == int(_pin.sel)
		var col := Color(0.3, 0.85, 0.3) if sel else Color(1, 1, 1, 0.95)
		var r := 16.0 + (3.0 * sin(tsec * 6.0) if sel else 0.0)
		var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
		if sel:
			mk.draw_circle(p, r * 1.6, Color(0.3, 0.9, 0.3, 0.25))
		mk.draw_polyline(pts + PackedVector2Array([pts[0]]), col, 3.0, true)
		var txt := ("%d%%" % int(float(_pin.depth) * 100.0)) if sel else ("Folha" if str(alvos[k].kind) == "folha" else ("Pino" if int(alvos[k].get("stage", 0)) == 1 else "Furar"))
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var lb := Rect2(p + Vector2(-tw * 0.5 - 8, -r - 44), Vector2(tw + 16, 28))
		mk.draw_rect(lb, Color(0.05, 0.05, 0.04, 0.85))
		mk.draw_rect(lb, col, false, 2.0)
		mk.draw_string(font, lb.position + Vector2(8, 20), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.95, 0.8))


func _draw_pin_bar(tb: Control) -> void:
	if _pin.is_empty() or int(_pin.sel) < 0:
		return
	var w := tb.size.x
	if int(_pin.get("stage", 0)) == 9:
		pass
	var r := Rect2(Vector2(0, 34), Vector2(w, 34))
	var font := ThemeDB.fallback_font
	var txt := "Bata quando o marcador estiver no verde"
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	tb.draw_rect(Rect2(Vector2(w * 0.5 - tw * 0.5 - 10, 0), Vector2(tw + 20, 28)), Color(0.05, 0.05, 0.04, 0.85))
	tb.draw_string(font, Vector2(w * 0.5 - tw * 0.5, 21), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.95, 0.8))
	tb.draw_rect(r.grow(4), Color(0.05, 0.05, 0.04, 0.9))
	var n := 60
	for k in n:
		var u := (k + 0.5) / n
		var d := absf(u - float(_pin.gc)) - float(_pin.gw) * 0.5
		var col := Color(0.2, 0.75, 0.2) if d <= 0.0 else (Color(0.92, 0.55, 0.1) if d <= KNAP_EDGE else Color(0.8, 0.12, 0.1))
		tb.draw_rect(Rect2(r.position + Vector2(w * k / n, 0), Vector2(w / n + 0.5, r.size.y)), col)
	tb.draw_rect(r, Color(0, 0, 0, 0.8), false, 2.0)
	var m: float = float(_pin.get("frozen", 0.5)) if float(_pin.anim) >= 0.0 else _pin_marker()
	var x := r.position.x + m * w
	tb.draw_rect(Rect2(Vector2(x - 4, r.position.y - 7), Vector2(8, r.size.y + 14)), Color(1.0, 0.85, 0.15))
	tb.draw_rect(Rect2(Vector2(x - 4, r.position.y - 7), Vector2(8, r.size.y + 14)), Color(0.2, 0.12, 0.0), false, 2.0)


# ================== CORTAR A PONTA QUE SOBROU (PLANTA) ==================

func _trim_tick(delta: float) -> void:
	if _trim.is_empty():
		return
	var mi := int(_trim.mi)
	var si := int(_trim.si)
	if mi >= _maq.plantas.size() or float(_maq.plantas[mi].sobra[si]) <= 0.0:
		_trim_end()
		return
	var inf: Dictionary = _maq.sobra_info(mi, si)
	var at: Vector3 = inf.pos
	if Vector2(at.x - _player.position.x, at.z - _player.position.z).length() > 2.4:
		_trim_end()
		_show_toast("Você saiu de perto: parou de cortar.")
		return
	_face_to(at)
	for b in [_log_btn, _ctx_btn, _chop_btn, _pick_btn, _plant_btn, _work_btn, _vine_btn, _seed_btn, _bld_btn, _jump_btn]:
		(b as Control).visible = false
	_maq_stop.visible = true
	if str(_trim.tool) == "serra":
		# o jogador faz o vai e vem com o dedo no trilho: cada ida e volta afunda o corte
		var v := float(_trim.ctrl.value)
		var end := 1 if v > 0.85 else (-1 if v < 0.15 else 0)
		if _chop_pose:
			_chop_pose.saw_pos = v * 2.0 - 1.0
			_chop_pose.saw_depth = float(_trim.hits) / float(_trim.need) * float(_trim.r) * 1.7
		if end != 0 and end != int(_trim.side):
			_trim.side = end
			Sons.play_at(self, "serra", at, 0.0, 0.92 if end > 0 else 1.0)
			_sawdust(at)
			if end < 0:
				_trim.hits = int(_trim.hits) + 1
				wear("serra")
	_bld_why.visible = true
	_bld_why.text = ("Serrando a ponta: %d%%" if str(_trim.tool) == "serra" else "Cortando a ponta: %d%%") % int(100.0 * float(_trim.hits) / float(_trim.need))
	if int(_trim.hits) >= int(_trim.need):
		var fl: Dictionary = _maq.trim(mi, si)
		var mid: Vector3 = inf.mid
		var ax: Vector3 = (_maq.xform(mi).basis * Maquinas.slot_basis(str(Maquinas.TIPOS[_maq.plantas[mi].tipo].pecas[si][3])).x)
		var yaw := atan2(-ax.z, ax.x) if Vector2(ax.x, ax.z).length() > 0.3 else randf() * TAU
		_arvores.drop_log(fl, mid, yaw)
		Sons.play_at(self, "baque", mid, -8.0, 1.2)
		_trim_end()
		_show_toast("Ponta cortada: o pedaço caiu no chão.")


## Começa a cortar a ponta: serra (trilho de vai e vem) ou machado (botão Bater).
func _trim_start(mi: int, si: int, tool: String) -> void:
	var inf: Dictionary = _maq.sobra_info(mi, si)
	var pc: Array = Maquinas.TIPOS[_maq.plantas[mi].tipo].pecas[si]
	var r := float(pc[4])
	var need := 1 if teste else (clampi(int(round(6.0 + r * 40.0)), 8, 18) if tool == "serra" else clampi(int(round(3.0 + r * 20.0)), 4, 8))
	_trim = {"mi": mi, "si": si, "tool": tool, "hits": 0, "need": need, "side": -1, "r": r}
	equip(tool)
	if tool == "serra":
		var ctrl := SerraCtrl.new()
		ctrl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		ctrl.offset_left = -150
		ctrl.offset_right = -30
		ctrl.offset_top = -470
		ctrl.offset_bottom = -20
		_hud.add_child(ctrl)
		ctrl.value = 0.0
		_trim.ctrl = ctrl
		if _chop_pose:
			var ax: Vector3 = _maq.xform(mi).basis * Maquinas.slot_basis(str(pc[3])).x
			_chop_pose.sawing = true
			_chop_pose.saw_point = inf.pos + Vector3.UP * r
			_chop_pose.saw_axis = ax.normalized()
			_chop_pose.saw_depth = 0.0
		_show_toast("Arraste o pegador: para cima empurra a serra, para baixo puxa. Vai e vem até atravessar.")
	else:
		var hb := Icones.IconButton.new()
		hb.text = "Bater"
		hb.add_theme_font_size_override("font_size", 22)
		hb.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		hb.offset_left = -190
		hb.offset_top = -190
		hb.offset_right = -30
		hb.offset_bottom = -30
		hb.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		hb.pressed.connect(_trim_axe_hit)
		_hud.add_child(hb)
		_trim.ctrl = hb
		_show_toast("Toque em Bater para cada machadada na ponta.")


func _trim_axe_hit() -> void:
	if _trim.is_empty() or str(_trim.tool) != "machado":
		return
	var inf: Dictionary = _maq.sobra_info(int(_trim.mi), int(_trim.si))
	var at: Vector3 = inf.pos
	Sons.play_at(self, "machado", at, -2.0, 1.0 + randf() * 0.1)
	_chips(at)
	wear("machado")
	_trim.hits = int(_trim.hits) + 1
	if _chop_pose:
		_chop_pose.swinging = true
		_chop_pose.phase = 0.6
		get_tree().create_timer(0.25).timeout.connect(func():
			if _chop_pose:
				_chop_pose.swinging = false)


func _trim_end() -> void:
	if _trim.is_empty():
		return
	if _trim.has("ctrl") and is_instance_valid(_trim.ctrl):
		(_trim.ctrl as Node).queue_free()
	if _chop_pose:
		_chop_pose.sawing = false
		_chop_pose.swinging = false
	_trim = {}
	_maq_stop.visible = false
	_bld_why.visible = false
	_jump_btn.visible = true
	_act_check = 0.0


# ================== ESCOLHER ONDE CORTAR A TORA ==================
# Machado na tora caída: aparece um anel em volta dela, começando perto da ponta mais
# perto do jogador. A faixa de arrastar leva o anel pela tora e mostra quanto fica da
# ponta até o corte; "Cortar aqui" começa as machadadas nesse lugar.

func _buck_open() -> void:
	var info: Dictionary = _arvores.log_piece_near(_player.position, 1.6)
	var fi: int = _arvores.free_log_near(_player.position, 1.4)
	if fi >= 0:
		var fl: Dictionary = _arvores.free_logs[fi]
		var ends: Array = _arvores._free_ends(fl)
		var dfree: float = _arvores._seg_dist(_player.position, ends)
		var dtree: float = 1e9 if info.is_empty() else _arvores._seg_dist(_player.position, [info.A, info.B])
		if dfree < dtree:
			info = {"solta": fl, "A": ends[0], "B": ends[1], "h0": 0.0, "h1": 1.0, "s": _arvores.free_log_length(fl)}
	if info.is_empty():
		return
	var s := float(info.s)
	var L := (float(info.h1) - float(info.h0)) * s
	var A: Vector3 = info.A
	var B: Vector3 = info.B
	# a ponta: a mais perto do jogador
	var ponta := -1 if Vector2(A.x - _player.position.x, A.z - _player.position.z).length() < Vector2(B.x - _player.position.x, B.z - _player.position.z).length() else 1
	var d := minf(0.5, L * 0.5)
	# já tinha começado um corte nessa tora: o anel começa nele
	var p: Array = info.get("p", [])
	var buck = p[11] if p.size() > 11 else null
	if info.has("solta") and (info.solta as Dictionary).has("corte_m"):
		var cm: Array = info.solta.corte_m
		d = (float(cm[0]) if ponta < 0 else 1.0 - float(cm[0])) * L
	elif buck is Array and float(buck[0]) > float(info.h0) and float(buck[0]) < float(info.h1):
		var hm := float(buck[0])
		d = ((hm - float(info.h0)) if ponta < 0 else (float(info.h1) - hm)) * s
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1.0, 0.82, 0.2)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_buck_sel = {"info": info, "ponta": ponta, "d": d, "L": L, "ring": ring}
	for b in _buck_btns:
		(b as Control).visible = true
	_bld_pad.visible = true
	_buck_tick()
	_show_toast("Arraste a faixa para levar o anel até onde quer cortar. Depois toque em \"Cortar aqui\".")


func _buck_h() -> float:
	var info: Dictionary = _buck_sel.info
	var dh := float(_buck_sel.d) / float(info.s)
	return float(info.h0) + dh if int(_buck_sel.ponta) < 0 else float(info.h1) - dh


func _buck_drag(d: Vector2) -> void:
	var L := float(_buck_sel.L)
	# arrastar para a direita leva o anel para longe da ponta
	_buck_sel.d = clampf(float(_buck_sel.d) + (d.x - d.y) * 0.004, 0.25, L - 0.25)
	_buck_tick()


func _buck_tick() -> void:
	for b in [_log_btn, _ctx_btn, _chop_btn, _pick_btn, _plant_btn, _work_btn, _vine_btn, _seed_btn, _bld_btn]:
		(b as Control).visible = false
	var info: Dictionary = _buck_sel.info
	if (info.has("solta") and not _arvores.free_logs.has(info.solta)) or (not info.has("solta") and not _arvores.plants.has(info.p)) or Vector2(float((info.A as Vector3).x) - _player.position.x, float((info.A as Vector3).z) - _player.position.z).length() > 12.0:
		_buck_stop()
		return
	var c: Dictionary = _buck_cut()
	var r := float(c.r)
	var tm: TorusMesh = (_buck_sel.ring as MeshInstance3D).mesh
	tm.inner_radius = r + 0.012
	tm.outer_radius = r + 0.04
	var up: Vector3 = (c.along as Vector3).normalized()
	var sd := up.cross(Vector3.UP)
	if sd.length() < 0.1:
		sd = up.cross(Vector3.RIGHT)
	sd = sd.normalized()
	(_buck_sel.ring as Node3D).global_transform = Transform3D(Basis(sd, up, sd.cross(up)), c.axis)
	var dd := float(_buck_sel.d)
	(_bld_pad as Arrasto).set_text(("Tora: %.2f m  (sobra %.2f m)" % [dd, float(_buck_sel.L) - dd]).replace(".", ","))
	_bld_why.visible = bool(c.galho)
	_bld_why.text = "Tem galho preso nessa parte do tronco: corte os galhos primeiro."


func _buck_stop() -> void:
	if _buck_sel.is_empty():
		return
	(_buck_sel.ring as Node).queue_free()
	_buck_sel = {}
	for b in _buck_btns:
		(b as Control).visible = false
	_bld_pad.visible = false
	_bld_why.visible = false
	_act_check = 0.0


## O corte no lugar do anel (tronco caído ou tora solta).
func _buck_cut() -> Dictionary:
	var info: Dictionary = _buck_sel.info
	if not info.has("solta"):
		return _arvores.log_cut_at(info, _buck_h())
	var fl: Dictionary = info.solta
	var u := _buck_h()                    # na tora solta h0=0, h1=1: o h já é a fração
	var A: Vector3 = info.A
	var B: Vector3 = info.B
	# a tora deitada acompanha o chão (uma ponta pode estar mais alta que a outra)
	var ax: Array = _arvores.free_axis(fl)
	var P: Vector3 = (ax[0] as Vector3).lerp(ax[1], u)
	var r: float = _arvores.free_log_radius_at(fl, u)
	return {"solta": fl, "u": u, "point": P + Vector3.UP * r, "axis": P, "along": ((ax[1] as Vector3) - (ax[0] as Vector3)).normalized(), "r": r, "galho": false}


func _buck_go() -> void:
	if _buck_sel.is_empty():
		return
	var c: Dictionary = _buck_cut()
	if bool(c.galho):
		_show_toast("Tem galho preso nessa parte do tronco: corte os galhos primeiro.")
		return
	_buck_stop()
	_buck_go_cut = c
	_start_chop()



# ================== CARREGAR JUNTO (COOPERATIVO) ==================
# Madeira pesada demais para um (mais de 60 kg) e no máximo 120 kg: com outro jogador,
# o botão "Cooperativo" aparece. Um clica e espera; o outro clica na mesma tora: os
# dois se abaixam e levantam juntos. Quem clicou primeiro vai na frente e guia; o
# outro segue atrás na outra ponta, olhando para o mesmo lado. Para pôr (no chão, nas
# forquilhas ou na planta), de novo: um clica "Cooperativo", depois o outro.

const COOP_KG := 120.0
const DRAG_KG := 250.0            # sozinho, maior que o ombro aguenta: arrasta (uma ponta no chão)
const SOLO_L := 1.0               # sozinho pega no ombro tora de até 1 m (qualquer grossura)
const COOP_L := 2.0               # dois juntos: até 2 m


## Um sozinho consegue pôr no ombro? Até 1 m sempre (ou leve, até 60 kg).
func _can_solo(fl: Dictionary) -> bool:
	return _arvores.free_log_length(fl) <= SOLO_L + 0.03 or _arvores.free_log_kg(fl) <= Arvores.CARRY_MAX_KG


## Dois juntos conseguem? Até 2 m sempre (ou até 120 kg).
func _can_coop(fl: Dictionary) -> bool:
	return _arvores.free_log_length(fl) <= COOP_L + 0.03 or _arvores.free_log_kg(fl) <= COOP_KG

var _coop_int := {}                # meu clique esperando o outro: {a, k, ts, ok_ms}
var _coop_int_fl := {}             # a tora do clique (cópia, para quem vai atrás)
var _coop := {}                    # carregando junto: {fl, pid, lider, L, r, kg, sep, node, anim}
var _coop_viz := {}                # tora de outros dois jogadores carregando juntos: pid -> nó


func _coop_possible() -> bool:
	return _rede != null and _rede.ativo() and _rede.jogadores.size() >= 2


func _log_key(fl: Dictionary) -> String:
	return "%.2f,%.2f,%.2f" % [float(fl.pos[0]), float(fl.pos[2]), _arvores.free_log_length(fl)]


func _coop_click(intent: Dictionary, fl: Dictionary) -> void:
	if not _coop_int.is_empty() and str(_coop_int.a) == str(intent.a) and str(_coop_int.k) == str(intent.k):
		_coop_int = {}
		_show_toast("Cooperativo cancelado.")
		return
	_coop_int = {"a": intent.a, "k": intent.k, "ts": Time.get_unix_time_from_system(), "ok_ms": -1}
	_coop_int_fl = fl.duplicate(true) if not fl.is_empty() else {}
	_show_toast("Esperando o outro jogador tocar em \"Cooperativo\" também...")


## Onde a tora vai se os dois tocarem agora: planta, forquilhas ou chão (com o ícone).
func _coop_place() -> Dictionary:
	var mid := _coop_mid()
	var L := float(_coop.L)
	if _maq and _coop_serra(mid) >= 0:
		return {"a": "serra", "icone": "projetos"}
	if _maq:
		var mi: int = _maq.planta_near(mid, 3.5)
		if mi >= 0 and not _maq.pronta(mi):
			var pw: Dictionary = _maq.pending_work(mi)
			if int(pw.furos) + int(pw.pinos) + int(pw.pontas) == 0 and int(_maq.slot_for(mi, _coop.fl, mid).i) >= 0:
				return {"a": "planta", "icone": "projetos"}
	if _apoios and not _apoios.pair_for(mid, L).is_empty():
		return {"a": "forquilha", "icone": "apoiar"}
	return {"a": "chao", "icone": "largar_tora"}


func _coop_partner_node() -> Node3D:
	if _coop.is_empty():
		return null
	return _remotos.get(int(_coop.pid))


func _coop_mid() -> Vector3:
	var o := _coop_partner_node()
	var a := _player.global_position
	if o == null:
		return a
	return (a + o.global_position) * 0.5


func _coop_tick(delta: float) -> void:
	if _rede == null or not _rede.ativo():
		if not _coop.is_empty():
			_coop_end(true)
		_coop_int = {}
		return
	var now := Time.get_ticks_msec()
	# o meu clique: procura o outro jogador com o mesmo clique
	if not _coop_int.is_empty():
		if int(_coop_int.ok_ms) >= 0:
			if now > int(_coop_int.ok_ms) + 1500:
				_coop_int = {}               # já combinou: para de avisar
		else:
			for pid in _rede.estados:
				if int(pid) == multiplayer.get_unique_id():
					continue
				var e: Dictionary = _rede.estados[pid]
				var oc = e.get("coop")
				if oc == null or str(oc.a) != str(_coop_int.a) or str(oc.k) != str(_coop_int.k):
					continue
				var lider: bool = float(_coop_int.ts) < float(oc.ts) or (float(_coop_int.ts) == float(oc.ts) and multiplayer.get_unique_id() < int(pid))
				_coop_int.ok_ms = now
				_coop_match(int(pid), lider)
				break
	# carregando: a tora entre os ombros dos dois
	if not _coop.is_empty():
		if not _rede.jogadores.has(int(_coop.pid)):
			_coop_end(true)
			_show_toast("O outro jogador saiu: a tora caiu.")
			return
		_coop.anim = maxf(0.0, float(_coop.anim) - delta)
		if _chop_pose:
			_chop_pose.crouch = clampf(float(_coop.anim) / 0.6, 0.0, 1.0) if float(_coop.anim) > 0.0 else 0.0
		var o := _coop_partner_node()
		var lift := 1.0 - clampf(float(_coop.anim) / 0.6, 0.0, 1.0)
		var me := _player.global_position + Vector3.UP * lerpf(0.35, 1.45, lift)
		var ot := (o.global_position if o else me) + Vector3.UP * lerpf(0.35, 1.45, lift)
		if o == null:
			ot = me - Vector3(-sin(_face), 0, -cos(_face)) * float(_coop.sep)
		var d := me - ot
		if d.length() < 0.1:
			d = Vector3(-sin(_face), 0, -cos(_face))
		(_coop.node as Node3D).global_transform = Transform3D(Basis(Quaternion(Vector3.RIGHT, d.normalized())), (me + ot) * 0.5)
	# outros dois jogadores carregando juntos (eu não estou nisso): a tora entre eles
	for pid in _coop_viz.keys():
		var e2 = _rede.estados.get(pid)
		if e2 == null or not (e2 as Dictionary).has("coopl") or not _remotos.has(pid):
			(_coop_viz[pid] as Node).queue_free()
			_coop_viz.erase(pid)
	for pid in _rede.estados:
		var e3: Dictionary = _rede.estados[pid]
		if not e3.has("coopl") or not bool(e3.coopl[3]) or not _remotos.has(pid):
			continue
		var other := int(e3.coopl[2])
		if other == multiplayer.get_unique_id() or not _remotos.has(other):
			continue
		if not _coop_viz.has(pid):
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.height = float(e3.coopl[0])
			cm.top_radius = float(e3.coopl[1])
			cm.bottom_radius = float(e3.coopl[1])
			mi.mesh = cm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.36, 0.28, 0.2)
			mi.material_override = m
			add_child(mi)
			_coop_viz[pid] = mi
		var a: Vector3 = (_remotos[pid] as Node3D).global_position + Vector3.UP * 1.45
		var b: Vector3 = (_remotos[other] as Node3D).global_position + Vector3.UP * 1.45
		var dd := (a - b)
		if dd.length() > 0.1:
			(_coop_viz[pid] as Node3D).global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dd.normalized())), (a + b) * 0.5)


## Os dois clicaram a mesma coisa.
func _coop_match(pid: int, lider: bool) -> void:
	var a := str(_coop_int.a)
	if a == "pegar":
		var k := str(_coop_int.k)
		var fl := _coop_int_fl
		# quem vai na frente tira a tora do mundo (o outro recebe pela rede)
		if lider:
			if k.begins_with("r:"):
				for i in _apoios.rested.size():
					if "r:" + _log_key(_apoios.rested[i].log) == k:
						fl = _apoios.take_rested(i)
						break
			else:
				for f2 in _arvores.free_logs:
					if _log_key(f2) == k:
						fl = f2
						break
				_arvores.free_logs.erase(fl)
				_arvores._rebuild_logs()
		if fl.is_empty():
			return
		fl = fl.duplicate(true)
		var node: Node3D = _arvores.free_log_node(fl)
		add_child(node)
		var L: float = _arvores.free_log_length(fl)
		_coop = {"fl": fl, "pid": pid, "lider": lider, "L": L, "r": _arvores.free_log_max_radius(fl),
			"kg": _arvores.free_log_kg(fl), "sep": clampf(L * 0.8, 1.0, 2.6), "node": node, "anim": 0.9}
		equip("")
		Sons.play_at(self, "baque", _player.position, -10.0)
		_show_toast("Pegaram juntos! " + ("Você vai na frente: guie com o controle." if lider else "Você vai atrás: segue quem vai na frente."))
		return
	# pôr a tora: quem vai na frente faz (o mundo vai pela rede); os dois soltam
	if _coop.is_empty():
		return
	if bool(_coop.lider):
		var fl: Dictionary = _coop.fl
		var mid := _coop_mid()
		var o := _coop_partner_node()
		var d := (_player.global_position - (o.global_position if o else _player.global_position - Vector3(-sin(_face), 0, -cos(_face))))
		var yaw := atan2(-d.z, d.x)
		var done := false
		if a == "serra" and _maq:
			var ms := _coop_serra(mid)
			var Lc: float = _arvores.free_log_length(fl)
			if ms >= 0 and Lc >= 0.6 and Lc <= 2.6 and _arvores.free_log_max_radius(fl) <= 0.3 and bool(_maq.cut_plan(fl).ok):
				_maq.load_log(ms, fl)
				done = true
				_show_toast("Tora na mesa da serra! Um pedala (do lado) e o outro empurra.")
			else:
				_show_toast("Essa tora não cabe na serra (60 cm a 2,6 m, até 60 cm de largura).")
		elif a == "planta" and _maq:
			var mi: int = _maq.planta_near(mid, 3.5)
			if mi >= 0:
				var r: Dictionary = _maq.slot_for(mi, fl, mid)
				if int(r.i) >= 0:
					_maq.fill_slot(mi, int(r.i), float(r.get("sobra", 0.0)), fl)
					done = true
					_show_toast("Peça no lugar da planta! Agora fure e ponha os pinos.")
		elif a == "forquilha" and _apoios:
			var pr: Array = _apoios.pair_for(mid, float(_coop.L))
			if not pr.is_empty():
				fl.erase("em_pe")
				_apoios.rest(fl, int(pr[0]), int(pr[1]))
				done = true
				_show_toast("Tora apoiada nas forquilhas!")
		if not done:
			_arvores.drop_log(fl, mid + Vector3.UP * 0.4, yaw)
			_show_toast("Largaram a tora no chão.")
	else:
		_show_toast("Pronto!")
	Sons.play_at(self, "baque", _player.position, -6.0)
	_coop_end(false)


## A serra pronta e vazia com a mesa de entrada perto de onde os dois estão (ou -1).
func _coop_serra(mid: Vector3) -> int:
	var mi: int = _maq.planta_near(mid, 5.5)
	if mi < 0 or str(_maq.plantas[mi].tipo) != "serra_pedal" or not _maq.pronta(mi):
		return -1
	var p: Dictionary = _maq.plantas[mi]
	if not (p.tora as Dictionary).is_empty() or not (p.get("saida", []) as Array).is_empty():
		return -1
	var l: Vector3 = _maq.xform(mi).affine_inverse() * mid
	if l.x < 1.2 or l.x > 5.0 or absf(l.z) > 1.8:
		return -1                  # os dois têm que estar do lado da mesa de entrada
	return mi


## Solta (drop = se cair sem combinar: quem vai na frente larga no chão).
func _coop_end(drop: bool) -> void:
	if _coop.is_empty():
		return
	if drop and bool(_coop.lider):
		_arvores.drop_log(_coop.fl, _player.global_position + Vector3.UP * 0.4, _face)
	if is_instance_valid(_coop.node):
		(_coop.node as Node).queue_free()
	if _chop_pose:
		_chop_pose.crouch = 0.0
	_coop = {}
	_act_check = 0.0


# ================== DESFIBRADEIRA: TIRAR A FIBRA DO TALO DE BURITI ==================
# Pelo olho da desfibradeira pronta, "Trabalhar": o jogador senta no banco (só se tiver
# talo de buriti na mochila) e já pega um talo. Passando o dedo PARA BAIXO na tela, bate
# o talo em cima das lâminas de faca; tocando em "Puxar", puxa o talo por cima delas
# (o talo vai se abrindo em fibras). Umas vezes assim e sai a fibra para a mochila; se
# tiver outro talo, pega sozinho; se não, levanta.
const DESF_PUXADAS := 3          # passadas: em 4 tiras, depois em palitos, depois em fibra
const DESF_TOQUES := 8           # toques em "Puxar" para passar o talo inteiro uma vez
const DESF_R := 0.026            # raio do talo
const DESF_L := 1.1              # comprimento do pedaço de talo na mão

func _desf_start(mi: int) -> void:
	if item_qtd("talo_buriti") <= 0:
		_show_toast("Precisa de talo de buriti na mochila para trabalhar na desfibradeira.")
		return
	if _mao != "":
		equip("")
	_desf = {"mi": mi, "fase": "bater", "anim": -1.0, "acao": "", "node": null, "drag": -9, "dy": 0.0}
	_olho = {}
	_bur = {}
	_jump_btn.visible = false
	for b in [_log_btn, _ctx_btn, _chop_btn, _pick_btn, _plant_btn, _work_btn, _vine_btn, _seed_btn, _bld_btn]:
		(b as Control).visible = false
	(_desf_btns[1] as Control).visible = true
	if _chop_pose:
		_chop_pose.crouch = 1.0          # sentado no banco
	if _skel:
		(_skel.get_parent() as Node3D).visible = false     # primeira pessoa sentado: o próprio corpo não tapa a bancada
	_pitch = 0.62
	_desf_take()
	Sons.play_at(self, "baque", _player.position + Vector3.UP * 0.4, -14.0, 1.4)


## Pega o próximo talo da mochila (na mão, em cima das lâminas).
func _desf_take() -> void:
	remove_item("talo_buriti", 1)
	_update_inventory()
	if _desf.node != null and is_instance_valid(_desf.node):
		(_desf.node as Node).queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)
	_desf.node = mi
	_desf.passe = 0              # passadas completas
	_desf.pull = 0.0             # quanto da passada atual já foi puxado (0 a 1)
	_desf.alvo = 0.0             # até onde os toques mandaram puxar
	_desf.down = 0.0
	_desf.rot = 0.0
	_desf.fase = "bater"
	_desf.anim = -1.0
	_desf_build()
	_desf_place()
	(_desf_btns[0] as Control).visible = false
	_show_toast("Passe o dedo PARA BAIXO na tela para bater o talo nas lâminas.")


## O talo no espaço da máquina: centro em x (vai vindo para o banco ao puxar), descido
## nas lâminas (down) e girado no comprido (rot).
func _desf_place() -> void:
	var xf: Transform3D = _maq.xform(int(_desf.mi))
	# começa com quase todo o talo além das lâminas e vem até a pontinha da mão
	var l := Vector3(0.5 - 1.0 * float(_desf.pull), lerpf(1.1, 0.95 + DESF_R, float(_desf.down)), 0.0)
	(_desf.node as Node3D).global_transform = Transform3D(xf.basis * Basis(Vector3.RIGHT, float(_desf.rot)), xf * l)


## Monta o talo: só a pontinha da mão fica inteira; o resto, por onde as lâminas já
## passaram, fica cortado no comprido: em 4 tiras, depois em palitos (4x4), depois em
## fibras finas (6x6), cada uma inteira de ponta a ponta.
func _desf_build() -> void:
	var im := (_desf.node as MeshInstance3D).mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color(0.34, 0.48, 0.19)
	var R := DESF_R
	var half := DESF_L * 0.5
	var start := -half + 0.06                   # a pontinha da mão (não passa nas lâminas)
	var passe := int(_desf.passe)
	var uc := start - 0.01
	if str(_desf.fase) == "puxar":
		uc = -0.5 + float(_desf.pull)            # onde a lâmina está no talo agora
	_desf_prism(im, -half, start, R, green)
	# a parte já passada nesta passada (um nível a mais) e a que ainda não passou
	var mid := clampf(uc, start, half)
	if mid > start:
		_desf_strands(im, start, mid, passe + 1)
	if mid < half:
		if passe <= 0:
			_desf_prism(im, mid, half, R, green)
		else:
			_desf_strands(im, mid, half, passe)
	im.surface_end()


## Tiras/fibras contínuas de u0 até u1 (cada uma uma peça só, abrindo um pouco para a ponta).
func _desf_strands(im: ImmediateMesh, u0: float, u1: float, lev: int) -> void:
	var R := DESF_R
	var green := Color(0.34, 0.48, 0.19)
	var fiber := Color(0.84, 0.78, 0.55)
	var nz := 4 if lev <= 2 else 6
	var ny := 1 if lev == 1 else (4 if lev == 2 else 6)
	var nsamp := maxi(2, int(ceil((u1 - u0) / 0.08)) + 1)
	var g := 0.0011
	for iz in nz:
		for iy in ny:
			var z0 := -R + 2.0 * R * iz / nz
			var z1 := -R + 2.0 * R * (iz + 1) / nz
			var zc := (z0 + z1) * 0.5
			var y0: float
			var y1: float
			if ny == 1:
				var hh := sqrt(maxf(R * R - zc * zc, 0.0001))
				y0 = -hh
				y1 = hh
			else:
				y0 = -R + 2.0 * R * iy / ny
				y1 = -R + 2.0 * R * (iy + 1) / ny
				if zc * zc + pow((y0 + y1) * 0.5, 2.0) > R * R * 1.05:
					continue
			var yc := (y0 + y1) * 0.5
			var dirc := Vector2(zc, yc).normalized() if Vector2(zc, yc).length() > 0.0005 else Vector2.ZERO
			# a casca verde de fora some a cada passada (a fibra de dentro é clara)
			var outer := Vector2(zc, yc).length() > R * 0.7
			var col := fiber.lerp(green, (0.55 if outer else 0.2) / float(lev))
			col = col.darkened(0.06 * float((iz + iy) % 2))
			var phase := float(iz * 7 + iy * 3)
			var rings := []
			for k in nsamp:
				var u := lerpf(u0, u1, float(k) / (nsamp - 1))
				var t := clampf((u - u0) / maxf(DESF_L * 0.5, 0.01), 0.0, 1.5)
				var off := dirc * (0.0015 * lev + 0.006 * lev * t * t)          # abrindo devagar para a ponta
				var wav := sin(u * 9.0 + phase) * 0.0012 * (lev - 1)            # a fibra ondula um pouco
				var droop := -t * t * 0.01 * lev
				var oz := off.x + wav
				var oy := off.y + droop
				rings.append([Vector3(u, y1 - g + oy, z0 + g + oz), Vector3(u, y1 - g + oy, z1 - g + oz),
					Vector3(u, y0 + g + oy, z1 - g + oz), Vector3(u, y0 + g + oy, z0 + g + oz)])
			for k in nsamp - 1:
				var A: Array = rings[k]
				var B: Array = rings[k + 1]
				for f in 4:
					var f2 := (f + 1) % 4
					_desf_quad(im, A[f], B[f], B[f2], A[f2], col.darkened(0.1 if f == 2 else 0.0))
			# a ponta da tira (fechada)
			var E: Array = rings[nsamp - 1]
			_desf_quad(im, E[0], E[1], E[2], E[3], col.lightened(0.1))


func _desf_quad(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c, a, c, d]:
		im.surface_set_normal(n)
		im.surface_set_color(col)
		im.surface_add_vertex(v)


func _desf_prism(im: ImmediateMesh, u0: float, u1: float, R: float, col: Color) -> void:
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		var p0 := Vector2(cos(a0), sin(a0)) * R
		var p1 := Vector2(cos(a1), sin(a1)) * R
		_desf_quad(im, Vector3(u0, p0.y, p0.x), Vector3(u1, p0.y, p0.x), Vector3(u1, p1.y, p1.x), Vector3(u0, p1.y, p1.x), col.darkened(0.06 * (k % 2)))


## Sentado no banco, de frente para a bancada.
func _desf_move(delta: float) -> void:
	var mi := int(_desf.mi)
	if mi >= _maq.plantas.size():
		_desf_end()
		return
	var xf: Transform3D = _maq.xform(mi)
	var at: Vector3 = xf * Vector3(-0.6, 0.0, 0.0)
	_player.position = at
	_air = false
	_vy = 0.0
	var fx: Vector3 = xf.basis.x
	_face = atan2(-fx.x, -fx.z)
	_yaw = _face
	_player.rotation.y = _face
	if _chop_pose:
		_chop_pose.crouch = 1.0
		_chop_pose.moving = false
	_play("Idle")
	_fp_camera(delta, 0.0)
	# sentado: os olhos na altura de quem está no banco, olhando as lâminas na bancada
	var eye: Vector3 = xf * Vector3(-0.7, 1.24, 0.0)
	_cam.global_transform = Transform3D(Basis.from_euler(Vector3(-_pitch, _yaw, 0.0)), eye)


func _desf_input(e: InputEvent) -> bool:
	if (e is InputEventMouseButton or e is InputEventMouseMotion) and e.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	var pos := Vector2.INF
	var idx := -9
	var pressed := false
	if e is InputEventScreenTouch:
		pos = e.position
		idx = e.index
		pressed = e.pressed
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
		idx = -1
		pressed = e.pressed
	if pos != Vector2.INF:
		for b in _desf_btns:
			if (b as Control).visible and (b as Control).get_global_rect().has_point(pos):
				return false
		if pressed:
			_desf.drag = idx
			_desf.dy = 0.0
		elif int(_desf.drag) == idx:
			_desf.drag = -9
		return true
	var d := Vector2.ZERO
	if e is InputEventScreenDrag and e.index == int(_desf.drag):
		d = e.relative
	elif e is InputEventMouseMotion and int(_desf.drag) == -1:
		d = e.relative
	else:
		return e is InputEventScreenDrag or e is InputEventMouseMotion
	_desf.dy = float(_desf.dy) + d.y
	if float(_desf.dy) > 70.0:
		_desf.dy = -1e9                  # uma batida por passada de dedo
		_desf_bater()
	return true


func _desf_bater() -> void:
	if str(_desf.fase) != "bater" or float(_desf.anim) >= 0.0:
		if str(_desf.fase) == "puxar":
			_show_toast("Agora vá tocando em \"Puxar\" para passar o talo nas lâminas.")
		return
	_desf.acao = "bater"
	_desf.anim = 0.0
	_desf.rot0 = float(_desf.rot)
	_desf.rot_to = PI * 0.5 * int(_desf.passe)       # de uma passada para a outra o talo gira um quarto de volta


## Cada toque puxa um pouco (o talo vem devagar por cima das lâminas).
func _desf_puxar() -> void:
	if _desf.is_empty() or str(_desf.fase) != "puxar" or float(_desf.anim) >= 0.0:
		return
	_desf.alvo = minf(1.0, float(_desf.alvo) + 1.0 / DESF_TOQUES)
	var xf: Transform3D = _maq.xform(int(_desf.mi))
	var at: Vector3 = xf * Vector3(0.0, 0.96, 0.0)
	Sons.play_at(self, "fibra_puxa", at, 0.0, randf_range(0.92, 1.08))      # o talo rasgando no fio das lâminas
	_fiber_chips(at)


func _desf_tick(delta: float) -> void:
	for b in [_log_btn, _ctx_btn, _chop_btn, _pick_btn, _plant_btn, _work_btn, _vine_btn, _seed_btn, _bld_btn, _jump_btn]:
		(b as Control).visible = false
	if _desf.node == null or not is_instance_valid(_desf.node):
		return
	if str(_desf.fase) == "puxar" and float(_desf.anim) < 0.0:
		# o talo vem até onde os toques mandaram (devagar, cortando)
		if float(_desf.pull) < float(_desf.alvo):
			_desf.pull = move_toward(float(_desf.pull), float(_desf.alvo), delta * 0.45)
			_desf_build()
			_desf_place()
			if float(_desf.pull) >= 0.999:
				_desf.passe = int(_desf.passe) + 1
				_desf.acao = "volta"
				_desf.anim = 0.0
				(_desf_btns[0] as Control).visible = false
		return
	if float(_desf.anim) < 0.0:
		return
	_desf.anim = float(_desf.anim) + delta
	var t := float(_desf.anim)
	if str(_desf.acao) == "bater":
		# vira um quarto de volta (a partir da 2ª), levanta e desce batendo nas lâminas
		var T := 0.42
		var k := clampf(t / T, 0.0, 1.0)
		_desf.rot = lerpf(float(_desf.rot0), float(_desf.rot_to), smoothstep(0.0, 0.5, k))
		_desf.down = clampf(-0.6 * sin(k * PI) * (1.0 - k) + k * k, -0.8, 1.0)
		_desf_place()
		if k >= 1.0:
			var at: Vector3 = _maq.xform(int(_desf.mi)) * Vector3(0.0, 0.96, 0.0)
			Sons.play_at(self, "fibra_bate", at, 0.0, randf_range(0.94, 1.06))
			_fiber_chips(at)
			_desf.anim = -1.0
			_desf.fase = "puxar"
			_desf.pull = 0.0
			_desf.alvo = 0.0
			_desf_build()
			(_desf_btns[0] as Control).visible = true
			_show_toast("Vá tocando em \"Puxar\": o talo passa devagar pelas lâminas (passada %d de %d)." % [int(_desf.passe) + 1, DESF_PUXADAS])
	else:
		# a passada terminou: levanta o talo e leva de volta para a frente
		var T2 := 0.4
		var k2 := clampf(t / T2, 0.0, 1.0)
		_desf.pull = 1.0 - k2
		_desf.down = 1.0 - k2
		_desf.fase = "volta"
		_desf_place()
		if k2 >= 1.0:
			_desf.anim = -1.0
			_desf.pull = 0.0
			_desf.alvo = 0.0
			_desf.fase = "bater"
			_desf_build()
			if int(_desf.passe) >= DESF_PUXADAS:
				_desf_done()
			else:
				_show_toast("O talo abriu em %s. Bata de novo (dedo para baixo): ele gira e corta do outro lado." % ("4 tiras" if int(_desf.passe) == 1 else "palitos"))


func _desf_done() -> void:
	var left := add_item("fibra_buriti", 2)
	_update_inventory()
	_show_toast("O talo virou fibra! +%d fibra de buriti%s" % [2 - left, "" if left == 0 else " (mochila cheia)"])
	Sons.play_at(self, "folha_cai", _player.position + Vector3.UP, -10.0, 1.6)
	if _desf.node != null and is_instance_valid(_desf.node):
		(_desf.node as Node).queue_free()
	_desf.node = null
	(_desf_btns[0] as Control).visible = false
	if item_qtd("talo_buriti") > 0:
		get_tree().create_timer(0.7).timeout.connect(func():
			if not _desf.is_empty():
				_desf_take())
	else:
		get_tree().create_timer(0.9).timeout.connect(func():
			if not _desf.is_empty():
				_show_toast("Acabaram os talos. Você se levantou da desfibradeira.")
				_desf_end())


func _desf_end() -> void:
	if _desf.is_empty():
		return
	if _desf.node != null and is_instance_valid(_desf.node):
		# o talo que estava na mão (pela metade) volta para a mochila
		if int(_desf.get("passe", 0)) < DESF_PUXADAS:
			add_item("talo_buriti", 1)
			_update_inventory()
		(_desf.node as Node).queue_free()
	var mi := int(_desf.mi)
	_desf = {}
	for b in _desf_btns:
		(b as Control).visible = false
	if _chop_pose:
		_chop_pose.crouch = 0.0
	if _skel:
		(_skel.get_parent() as Node3D).visible = true
	if mi < _maq.plantas.size():
		var xf: Transform3D = _maq.xform(mi)
		var out: Vector3 = xf * Vector3(-1.25, 0.0, 0.0)
		_player.position = _ground_pos(Vector2(out.x, out.z))
	_jump_btn.visible = true
	_act_check = 0.0


# ================== BURITI: O OLHO, CORTAR FOLHA E DERRUBAR ==================
# Perto do pé do buriti aparece um olho no tronco. Tocando nele abre o menu (embaixo
# do olho, com a setinha do lado para fechar). Buriti pequeno (as folhas ao alcance):
# Cortar e Derrubar. Grande: só Derrubar (as folhas lá de cima só derrubando).
#  - Cortar: losangos nas folhas que o braço alcança; com a faca, golpes no talo na
#    barrinha (errou no vermelho, a lâmina quebra e cai).
#  - Derrubar: com o machado na mão, aparece o botão; machadadas no pé até ele
#    tombar. O tronco fica no chão (dá para cortar em toras) e as folhas espalhadas.
# As folhas secas (a "saia" da copa) caem sozinhas de vez em quando: dá para pegar.

func _olho_free() -> bool:
	return _desf.is_empty() and _pin.is_empty() and _carry.is_empty() and not _chopping and _crouch_job == "" \
		and not _air and _bld.is_empty() and _proj.is_empty() and _buck_sel.is_empty() and _maq_op.is_empty() \
		and _trim.is_empty() and _post_mark.is_empty() and _knap.is_empty() and _vine.is_empty() and not _walking \
		and _coop.is_empty() and _bag_ui == null and _craft_ui == null


## Procura o buriti perto (a cada 1/4 s) e mantém o olho/escolha dele.
func _olho_tick() -> void:
	if _buritis == null:
		return
	if not _bur.is_empty():
		var bp: Dictionary = _bur.p
		var far := Vector2(float(bp.x) - _player.position.x, float(bp.z) - _player.position.z).length() > 3.2
		if far or not _buritis.has_palm(bp) or bp.has("toco") or (str(_bur.acao) == "derrubar" and _mao != "machado" and not _chopping):
			_bur = {}
	if not _olho_free():
		_olho = {}
		return
	var p: Dictionary = _buritis.palm_near(_player.position, 2.2)
	if p.is_empty():
		p = _buritis.caido_near(_player.position, 2.6)      # a copa do buriti derrubado
	if p.is_empty() and _maq:
		var mi: int = _maq.planta_near(_player.position, 2.2)
		if mi >= 0 and str(_maq.plantas[mi].tipo) == "desfibradeira" and _maq.pronta(mi):
			p = {"maq": mi}
	if p.is_empty() or _olho_opts(p).is_empty():
		_olho = {}
		return
	if _olho.is_empty() or not (_olho.p as Dictionary) == p or (not p.has("maq") and not _buritis.has_palm(_olho.p)):
		_olho = {"p": p, "open": false}


## O que dá para fazer nesse buriti: [[ação, nome]]
func _olho_opts(p: Dictionary) -> Array:
	var out := []
	if p.has("maq"):
		return [["trabalhar", "Trabalhar"]]
	if p.has("caido"):
		return [["cortar", "Cortar"]] if not _buritis.leaves_of(p).is_empty() else []
	if _buritis.is_small(p):
		out.append(["cortar", "Cortar"])
	if _buritis.can_fell(p):
		out.append(["derrubar", "Derrubar"])
	return out


## Onde o olho fica: no tronco (na altura do peito), do lado de quem está olhando.
func _olho_world(p: Dictionary) -> Vector3:
	if p.has("maq"):
		return _maq.xform(int(p.maq)) * Vector3(0.05, 1.2, 0.0)
	if p.has("caido"):
		var o: Vector3 = _buritis.crown_xf(p).origin
		return Vector3(o.x, maxf(o.y, height_at(o.x, o.z) + 0.3) + 0.45, o.z)
	var ang := atan2(_player.position.z - float(p.z), _player.position.x - float(p.x))
	var h: float = _buritis.trunk_h(p)
	if h > 1.6:
		return _buritis.trunk_point(p, 1.3, ang, 0.08)
	return _buritis.trunk_point(p, clampf(h + 0.45, 0.6, 1.25), ang, 0.12)


## Posições do menu na tela: {eye, close, rows:[Rect2]}
func _olho_layout() -> Dictionary:
	if _olho.is_empty():
		return {}
	var w := _olho_world(_olho.p)
	if _cam.is_position_behind(w):
		return {}
	var vs := get_viewport().get_visible_rect().size
	var e := _cam.unproject_position(w)
	e.x = clampf(e.x, 70.0, vs.x - 260.0)
	e.y = clampf(e.y, 70.0, vs.y - 260.0)
	var rows := []
	if bool(_olho.open):
		var opts := _olho_opts(_olho.p)
		for i in opts.size():
			rows.append(Rect2(e + Vector2(-125, 62 + i * 74), Vector2(250, 64)))
	return {"eye": e, "close": e + Vector2(72, 0), "rows": rows}


func _draw_bur_ui() -> void:
	var font := ThemeDB.fallback_font
	var L := _olho_layout() if _olho_free() and _bur.is_empty() else {}
	if not L.is_empty():
		var e: Vector2 = L.eye
		Desenhos.eye(_sub_ui, e, 64.0, bool(_olho.open))
		if bool(_olho.open):
			# a setinha para cima (fechar), do lado do olho
			var c: Vector2 = L.close
			_sub_ui.draw_circle(c, 24.0, Color(0.05, 0.05, 0.04, 0.8))
			_sub_ui.draw_arc(c, 24.0, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0, true)
			_sub_ui.draw_polyline(PackedVector2Array([c + Vector2(-11, 6), c + Vector2(0, -7), c + Vector2(11, 6)]), Color(1, 0.95, 0.8), 4.0, true)
			var opts := _olho_opts(_olho.p)
			for i in (L.rows as Array).size():
				var r: Rect2 = L.rows[i]
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(0.05, 0.045, 0.035, 0.86)
				sb.border_color = Color(1, 1, 1, 0.22)
				sb.set_border_width_all(2)
				sb.set_corner_radius_all(12)
				_sub_ui.draw_style_box(sb, r)
				# o quadradinho (losango) para escolher
				var q := r.position + Vector2(30, r.size.y * 0.5)
				var rr := 13.0
				var pts := PackedVector2Array([q + Vector2(0, -rr), q + Vector2(rr, 0), q + Vector2(0, rr), q + Vector2(-rr, 0)])
				_sub_ui.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.95), 3.0, true)
				_sub_ui.draw_string(font, r.position + Vector2(56, r.size.y * 0.5 + 9), str(opts[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.96, 0.86))
				# a ilustração na frente do nome
				Desenhos.item(_sub_ui, "acao_" + str(opts[i][0]), r.position + Vector2(r.size.x - 40, r.size.y * 0.5), 56.0)
	# losangos nos talos das folhas caídas (o 2º corte, perto do leque)
	if _pin.is_empty() and _olho_free():
		var tl := _talo_marks()
		for i in tl.size():
			var tp: Vector2 = tl[i][1]
			var rr := 13.0
			var pts2 := PackedVector2Array([tp + Vector2(0, -rr), tp + Vector2(rr, 0), tp + Vector2(0, rr), tp + Vector2(-rr, 0)])
			_sub_ui.draw_polyline(pts2 + PackedVector2Array([pts2[0]]), Color(1.0, 0.85, 0.35), 3.0, true)
			if i == 0:
				var tw2 := font.get_string_size("Talo", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				var lb2 := Rect2(tp + Vector2(-tw2 * 0.5 - 6, -rr - 34), Vector2(tw2 + 12, 24))
				_sub_ui.draw_rect(lb2, Color(0.05, 0.05, 0.04, 0.85))
				_sub_ui.draw_string(font, lb2.position + Vector2(6, 18), "Talo", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.95, 0.8))
	# losangos das folhas (cortando do chão, ou subindo)
	var lfs := _leaf_list()
	if lfs.is_empty() or not _pin.is_empty():
		return
	var eye := _cam.global_position
	# o nome "Folha" só na que está mais no meio da tela (perto o bastante)
	var mid := get_viewport().get_visible_rect().size * 0.5
	var lab := -1
	var lbd := 1e9
	for i in lfs.size():
		var w0: Vector3 = lfs[i].cut
		if _cam.is_position_behind(w0) or w0.distance_to(eye) >= _leaf_reach():
			continue
		var dd := _cam.unproject_position(w0).distance_to(mid)
		if dd < lbd:
			lbd = dd
			lab = i
	for i in lfs.size():
		var lf: Dictionary = lfs[i]
		var w: Vector3 = lf.cut
		if _cam.is_position_behind(w):
			continue
		var p := _cam.unproject_position(w)
		var perto := w.distance_to(eye) < _leaf_reach()
		var col := Color(0.4, 0.95, 0.4) if perto else Color(1, 1, 1, 0.75)
		var r := 13.0
		var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
		_sub_ui.draw_polyline(pts + PackedVector2Array([pts[0]]), col, 3.0, true)
		if i == lab:
			var tw := font.get_string_size("Folha", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var lb := Rect2(p + Vector2(-tw * 0.5 - 6, -r - 34), Vector2(tw + 12, 24))
			_sub_ui.draw_rect(lb, Color(0.05, 0.05, 0.04, 0.85))
			_sub_ui.draw_string(font, lb.position + Vector2(6, 18), "Folha", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.95, 0.8))


## Talos das folhas caídas perto (na tela): [[índice, ponto na tela]], o mais perto primeiro.
func _talo_marks() -> Array:
	var out := []
	if _buritis == null:
		return out
	for i in _buritis.chao_folhas.size():
		var w: Vector3 = _buritis.talo_point(_buritis.chao_folhas[i])
		var dd := Vector2(w.x - _player.position.x, w.z - _player.position.z).length()
		if dd > 4.0 or _cam.is_position_behind(w):
			continue
		out.append([i, _cam.unproject_position(w), dd])
	out.sort_custom(func(a, b): return float(a[2]) < float(b[2]))
	return out


## Folhas com losango agora: subindo (todas) ou cortando do chão (as que alcança).
func _leaf_list() -> Array:
	if not _bur.is_empty() and str(_bur.acao) == "cortar":
		return _buritis.reach_leaves(_bur.p)
	return []


func _leaf_reach() -> float:
	return 2.4


func _bur_input(e: InputEvent) -> bool:
	var pos := Vector2.INF
	if e is InputEventScreenTouch and e.pressed:
		pos = e.position
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
	if pos == Vector2.INF:
		return false
	for b in _sub_btns + [_ctx_btn, _chop_btn]:
		if (b as Control).visible and (b as Control).get_global_rect().has_point(pos):
			return false
	var L := _olho_layout() if _olho_free() and _bur.is_empty() else {}
	if not L.is_empty():
		if pos.distance_to(L.eye) < 48.0:
			if not bool(_olho.open):
				_olho.open = true
				Sons.play_at(self, "pedra_bate", _player.position + Vector3.UP, -30.0, 2.0)
			return true
		if bool(_olho.open):
			if pos.distance_to(L.close) < 34.0:
				_olho.open = false
				return true
			var opts := _olho_opts(_olho.p)
			for i in (L.rows as Array).size():
				if (L.rows[i] as Rect2).grow(4).has_point(pos):
					_olho_pick(str(opts[i][0]))
					return true
	if _pin.is_empty() and _olho_free():
		for tm in _talo_marks():
			if pos.distance_to(tm[1]) < 50.0:
				_talo_pick(int(tm[0]))
				return true
	if _pin.is_empty():
		for lf in _leaf_list():
			var w: Vector3 = lf.cut
			if _cam.is_position_behind(w):
				continue
			if pos.distance_to(_cam.unproject_position(w)) < 60.0:
				_leaf_pick(_bur.p, int(lf.li), w)
				return true
	return false


func _olho_pick(acao: String) -> void:
	var p: Dictionary = _olho.p
	_olho.open = false
	match acao:
		"trabalhar":
			_desf_start(int(p.maq))
			return
		"cortar":
			_bur = {"p": p, "acao": "cortar"}
			if item_qtd("faca") <= 0:
				_show_toast("Para cortar a folha precisa de uma faca de pedra (lâmina de faca + galho + cipó, no craft).")
			else:
				_show_toast("Toque no losango da folha que quer cortar.")
		"derrubar":
			if _mao != "machado":
				_show_toast("Para derrubar, ponha o machado na mão (Mochila → Equipar) e escolha Derrubar de novo.")
				return
			_bur = {"p": p, "acao": "derrubar"}
			_show_toast("Toque em \"Derrubar\" para dar as machadadas no pé do buriti.")
	_act_check = 0.0


## Cortando folha do chão: botão Sair.
var _olho_t := 0.0

func _bur_tick() -> void:
	_olho_t -= get_process_delta_time()
	if _olho_t <= 0.0:
		_olho_t = 0.2
		_olho_tick()
	(_sub_btns[0] as Control).visible = not _bur.is_empty() and str(_bur.acao) == "cortar" and _pin.is_empty()


func _bur_sair() -> void:
	_bur = {}
	(_sub_btns[0] as Control).visible = false
	_act_check = 0.0


func _leaf_pick(bp: Dictionary, li: int, w: Vector3) -> void:
	if Vector2(w.x - _player.position.x, w.z - _player.position.z).length() > 5.0:
		_show_toast("Longe: chegue mais perto dessa folha.")
		return
	if item_qtd("faca") <= 0:
		_show_toast("Precisa de uma faca de pedra (lâmina de faca + galho + cipó, no craft).")
		return
	_pin_start()
	var v := int(bp.get("var", 0)) % Buritis.CROWN_VARIANTS
	var xf: Transform3D = _buritis.crown_xf(bp)
	var dir: Vector3 = xf * _buritis.pet_point(v, li, 0.2) - xf * _buritis.pet_point(v, li, 0.12)
	_pin.alvos = [{"kind": "folha", "bp": bp, "li": li, "pos": w, "stage": 9, "dir": dir, "r": 0.045 * _buritis.crown_scale(bp)}]
	_pin.folhas = true
	_pin_pick(0)
	_show_toast("1º corte: no pé do talo. Golpeie com a faca quando o marcador estiver no verde. Errou no vermelho, a faca quebra!")


## O 2º corte: na folha caída, o talo perto do leque. O talo vai para a mochila.
func _talo_pick(i: int) -> void:
	if item_qtd("faca") <= 0:
		_show_toast("Precisa de uma faca de pedra (lâmina de faca + galho + cipó, no craft).")
		return
	var e: Array = _buritis.chao_folhas[i]
	var w: Vector3 = _buritis.talo_point(e)
	var dir: Vector3 = _buritis.talo_point(e, 0.98) - w
	_pin_start()
	_pin.alvos = [{"kind": "talo", "e": e, "pos": w, "stage": 9, "dir": dir, "r": 0.03 * float(e[5])}]
	_pin.folhas = true
	_pin_pick(0)
	_show_toast("2º corte: no talo, perto do leque. Assim o talo sai inteiro.")


# ---------- derrubar ----------

func _bur_fell_ready() -> bool:
	return not _bur.is_empty() and str(_bur.acao) == "derrubar" and _mao == "machado" and _carry.is_empty() and not _air


func _bur_chop_hit() -> void:
	var p: Dictionary = _chop_bur
	if not _buritis.palms.has(p) or p.has("toco"):
		_cancel_chop()
		return
	var side := atan2(_player.position.z - float(p.z), _player.position.x - float(p.x))
	var n: int = _buritis.add_hit(p, side)
	var need: int = 1 if teste else _buritis.hits_to_fell(p)
	var at: Vector3 = _buritis.trunk_point(p, 1.0, side, 0.02)
	_chips(at)
	Sons.play_at(self, "machado", at, 0.0, 1.05)
	if n >= need:
		var away := Vector3(float(p.x) - _player.position.x, 0, float(p.z) - _player.position.z)
		_cancel_chop()
		_bur = {}
		_bur_fall(p, away)
	else:
		_show_toast("Derrubando: %d de %d machadadas" % [n, need])


## O buriti tomba para o lado contrário de quem cortou e fica deitado no chão.
func _bur_fall(p: Dictionary, away: Vector3) -> void:
	var info: Dictionary = _buritis.fell(p)
	var h := float(info.h)
	var r := float(info.r)
	var gy := float(info.gy)
	var base := Vector3(float(info.x), gy + Buritis.TOCO_H, float(info.z))
	var dir := Vector3(away.x, 0, away.z)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(1, 0, 0)
	var L := maxf(h - Buritis.TOCO_H, 0.5)
	var root := Node3D.new()
	add_child(root)
	root.global_position = base
	# o tronco (de pé, em volta da base) e a copa em cima
	var tr := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.9
	cm.bottom_radius = r * 1.02
	cm.height = L
	cm.radial_segments = 14
	tr.mesh = cm
	tr.material_override = _buritis._dead_mat if bool(info.morta) else _buritis._trunk_mat
	tr.position = Vector3.UP * L * 0.5
	root.add_child(tr)
	if not bool(info.morta):
		var sk := {}
		for li in info.cortadas:
			sk[int(li)] = true
		var cr := MeshInstance3D.new()
		cr.mesh = _buritis._crown_mesh(_buritis._crown_params[int(info.v)], sk)
		cr.material_override = _buritis._leaf_mat
		var s := float(info.s)
		cr.transform = Transform3D(Basis(Vector3.UP, float(info.rot)).scaled(Vector3(s, s, s)), Vector3.UP * (L - 0.1))
		root.add_child(cr)
	var axis := Vector3.UP.cross(dir).normalized()
	var dur := clampf(sqrt(L) * 0.75, 1.4, 3.6)
	Sons.play_at(self, "estalo", base, 2.0, 0.8)
	var tw := root.create_tween()
	tw.tween_method(func(t: float) -> void:
		# começa devagar (estalando) e acelera; no fim quica um pouquinho
		var a := (t * t) * (PI * 0.5 - 0.04)
		root.global_transform = Transform3D(Basis(axis, a), base), 0.0, 1.0, dur)
	tw.tween_callback(func():
		Sons.play_at(self, "queda", base + dir * L * 0.6, clampf(-6.0 + L * 0.5, -6.0, 6.0), clampf(1.3 - L * 0.025, 0.8, 1.2))
		if not bool(info.morta):
			Sons.play_at(self, "folha_cai", base + dir * L, 2.0, 1.4, 120.0, 10.0))
	tw.tween_interval(0.25)
	tw.tween_callback(func():
		root.queue_free()
		_bur_fallen(info, base, dir, L, axis))


## Depois da queda: a tora do buriti deitada no chão e as folhas verdes espalhadas.
func _bur_fallen(info: Dictionary, base: Vector3, dir: Vector3, L: float, axis: Vector3) -> void:
	var r := float(info.r)
	var c := base + dir * (L * 0.5 + 0.1)
	var cy := height_at(c.x, c.z) + r * 0.95
	var yaw := atan2(-dir.z, dir.x)
	var fl := {"cil": {"L": L, "ra": r * 1.02, "rb": r * 0.9}, "sec": Arvores.circle_sec(), "pos": [c.x, cy, c.z],
		"yaw": yaw, "dia": int(sim.elapsed_days()), "casca": "buriti_seco" if bool(info.morta) else "buriti"}
	_arvores.free_logs.append(fl)
	_arvores._rebuild_logs()
	if not bool(info.morta):
		# a copa fica deitada no fim da tora, com todas as folhas presas
		var sc := float(info.s)
		var fall := Transform3D(Basis(axis, PI * 0.5 - 0.04), base)
		var xf: Transform3D = fall * Transform3D(Basis(Vector3.UP, float(info.rot)).scaled(Vector3(sc, sc, sc)), Vector3.UP * (L - 0.1))
		var ends: Array = _arvores.free_axis(fl)
		xf.origin = (ends[1] as Vector3) + dir * 0.05
		_buritis.add_caido(info, xf)
	_show_toast("O buriti caiu! A tora ficou no chão (dá para cortar com o machado)%s." % ("" if bool(info.morta) else ". As folhas continuam na copa: toque no olho para cortar"))
	_act_check = 0.0


## O talo separado do leque: fica no chão (um pouco afastado) para pegar.
func _talo_drop(e: Array) -> void:
	var xf: Transform3D = _buritis.lying_xf(e)
	var v := int(e[2])
	var li := int(e[3])
	var mid: Vector3 = xf * _buritis.pet_point(v, li, 0.5)
	var side: Vector3 = (xf.basis * Vector3.UP).cross(xf * _buritis.pet_point(v, li, 0.9) - xf.origin).normalized()
	var shift := side * 0.12
	# o item fica no meio do talo; o desenho guarda onde fica o pé dele
	var hub := xf.origin + shift
	_add_ground("talo_buriti", 1, mid.x + shift.x, mid.z + shift.z, 0.0, [v, li, float(e[4]), float(e[5]), hub.x - (mid.x + shift.x), hub.z - (mid.z + shift.z)])


## Fibras verdes e claras voando do talo cortado.
func _fiber_chips(at: Vector3) -> void:
	var c := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.006, 0.012)
	c.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.72, 0.4)
	c.material_override = mat
	c.amount = 12
	c.one_shot = true
	c.explosiveness = 0.95
	c.lifetime = 0.8
	c.direction = Vector3(0, 1, 0)
	c.spread = 70.0
	c.initial_velocity_min = 0.8
	c.initial_velocity_max = 2.0
	c.gravity = Vector3(0, -9.8, 0)
	c.angular_velocity_min = -300.0
	c.angular_velocity_max = 300.0
	add_child(c)
	c.global_position = at
	c.emitting = true
	get_tree().create_timer(1.2).timeout.connect(c.queue_free)


## A faca na frente da câmera: parada embaixo à direita; no golpe (ph 0 a 1) sobe, desce
## cortando e o meio da lâmina bate no talo em ph = 0,55; depois volta.
func _knife_pose(ph: float) -> void:
	var kn: Node3D = _pin.knife
	var cam := _cam.global_transform
	var cr := cam.basis.x.normalized()
	var cu := cam.basis.y.normalized()
	var cf := -cam.basis.z.normalized()
	var eye := cam.origin
	var k := int(_pin.sel)
	var w: Vector3 = _pin.alvos[k].pos if k >= 0 and k < (_pin.alvos as Array).size() else eye + cf * 0.6
	var rest_p := eye + cr * 0.2 - cu * 0.27 + cf * 0.42
	var rest_y := (cu * 0.8 + cf * 0.45 - cr * 0.1).normalized()
	var up_p := eye + cr * 0.3 + cu * 0.02 + cf * 0.32
	var up_y := (cu * 0.75 - cf * 0.25 + cr * 0.35).normalized()
	# na batida: o meio da lâmina no talo (a mão fica antes, do lado direito)
	var hit_y := (cf * 0.55 + cu * 0.35 - cr * 0.45).normalized()
	var hit_p := w - hit_y * 0.22
	var hp: Vector3 = hit_p - eye
	if hp.length() > 0.75:
		hit_p = eye + hp.normalized() * 0.75        # o braço não estica mais que isso
		hit_y = (w - hit_p).normalized()
		hit_p = w - hit_y * 0.22
	var p := rest_p
	var y := rest_y
	if ph >= 0.0:
		if ph < 0.4:
			var t := smoothstep(0.0, 1.0, ph / 0.4)
			p = rest_p.lerp(up_p, t)
			y = rest_y.slerp(up_y, t)
		elif ph < 0.55:
			var t := (ph - 0.4) / 0.15
			t = t * t
			p = up_p.lerp(hit_p, t)
			y = up_y.slerp(hit_y, t)
		else:
			var t := smoothstep(0.0, 1.0, (ph - 0.55) / 0.45)
			p = hit_p.lerp(rest_p, t)
			y = hit_y.slerp(rest_y, t)
	var x := (-cu + cf * 0.2)
	x = (x - y * x.dot(y)).normalized()          # o gume virado para baixo (para o talo)
	kn.global_transform = Transform3D(Basis(x, y, x.cross(y)), p)


## O corte no talo: um anel de fibra clara (o miolo aparecendo) atravessado no talo,
## que vai abrindo e afinando o talo a cada golpe bom.
func _talho_node(al: Dictionary) -> Node3D:
	var root := Node3D.new()
	var band := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.radial_segments = 10
	cm.height = 0.006
	cm.top_radius = 0.04
	cm.bottom_radius = 0.04
	band.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.84, 0.62)       # o miolo fibroso do talo
	m.roughness = 1.0
	band.material_override = m
	band.visible = false
	root.add_child(band)
	var d: Vector3 = al.get("dir", Vector3.UP)
	if d.length() > 0.001:
		var y := d.normalized()
		var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
		band.basis = Basis(x, y, x.cross(y))
	return root


func _faca_node() -> Node3D:
	var root := Node3D.new()
	var cabo := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.016
	cm.bottom_radius = 0.016
	cm.height = 0.14
	cabo.mesh = cm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.45, 0.3, 0.17)
	cabo.material_override = wm
	cabo.position = Vector3(0, 0.12, 0)
	root.add_child(cabo)
	var bl := MeshInstance3D.new()
	var bm := PrismMesh.new()
	bm.size = Vector3(0.05, 0.12, 0.01)
	bl.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.42, 0.42, 0.4)
	bl.material_override = sm
	bl.rotation.z = PI
	bl.position = Vector3(0, 0.0, 0)
	root.add_child(bl)
	return root


## Golpe da faca no talo.
func _leaf_strike(al: Dictionary, w: Vector3) -> void:
	var bp: Dictionary = al.get("bp", {})
	if bool(_pin.ok):
		_pin.depth = float(_pin.depth) + 0.25
		Sons.play_at(self, "talo_corte", w, -2.0)
		_fiber_chips(w)
		var broke := wear("faca")
		if float(_pin.depth) >= 0.99 and str(al.kind) == "talo":
			var ei: int = _buritis.chao_folhas.find(al.e)
			if ei >= 0:
				var e: Array = _buritis.cut_talo(ei)
				_talo_drop(e)
			(_pin.node as Node).queue_free()
			_pin.node = null
			_pin_end()
			_show_toast("O talo saiu! Pegue ele no chão (o leque fica).")
			return
		if float(_pin.depth) >= 0.99:
			var li := int(al.li)
			_buritis.cut_leaf(bp, li)
			_leaf_fall(bp, li)
			(_pin.node as Node).queue_free()
			_pin.node = null
			_pin_end()
			_show_toast("A folha caiu! Agora corte o talo perto do leque (losango na folha no chão).")
			return
		if broke:
			_pin_end()
		else:
			_pin_place_node()
		return
	# pegou torto: a lâmina de pedra estala e cai
	Sons.play_at(self, "estalo", w, 0.0, 1.5)
	remove_item("faca", 1)
	_dur.erase("faca")
	_update_inventory()
	_blade_fall(w)
	if _pin.node:
		(_pin.node as Node).queue_free()
		_pin.node = null
	_pin_end()
	_show_toast("A faca bateu torto e a lâmina quebrou! Ela caiu lá embaixo. Faça outra faca.")


## A lâmina quebrada caindo (girando) até o chão.
func _blade_fall(w: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := PrismMesh.new()
	bm.size = Vector3(0.05, 0.12, 0.012)
	mi.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.42, 0.42, 0.4)
	mi.material_override = sm
	add_child(mi)
	mi.global_position = w
	var gy := height_at(w.x + 0.4, w.z + 0.3) + 0.02
	var end := Vector3(w.x + 0.4, gy, w.z + 0.3)
	var dur := clampf(sqrt(maxf(w.y - gy, 0.1) / 4.9), 0.3, 2.5)
	var tw := mi.create_tween()
	tw.tween_method(func(t: float) -> void:
		mi.global_position = w.lerp(end, t) + Vector3.UP * 0.0
		mi.global_position.y = lerpf(w.y, gy, t * t)
		mi.rotation = Vector3(t * 14.0, t * 9.0, t * 5.0), 0.0, 1.0, dur)
	tw.tween_callback(func(): Sons.play_at(self, "pedra_bate", end, -6.0, 1.4))
	tw.tween_interval(6.0)
	tw.tween_callback(mi.queue_free)


## Folha seca soltando da copa sozinha: perto do jogador ela aparece caindo (com o
## barulho); quando deita no chão vira folha seca para pegar. Longe: só aparece no chão.
func _seca_cai(bp: Dictionary, li: int, land: Vector3, yaw: float) -> bool:
	if _player == null or Vector2(float(bp.x) - _player.position.x, float(bp.z) - _player.position.z).length() > 70.0:
		return false
	_leaf_fall(bp, li, land, yaw, func(): _buritis.add_seca(bp, li, land, yaw), -6.0)
	return true


## A folha cortada caindo: sai da copa, vai tombando e balançando até deitar no chão.
func _leaf_fall(bp: Dictionary, li: int, land_at := Vector3.INF, yaw_at := INF, on_land := Callable(), vol := 2.0) -> void:
	var v := int(bp.get("var", 0)) % Buritis.CROWN_VARIANTS
	var mi := MeshInstance3D.new()
	mi.mesh = _buritis.leaf_mesh(v, li)
	mi.material_override = _buritis._leaf_mat
	add_child(mi)
	var start: Transform3D = _buritis.crown_xf(bp)
	mi.global_transform = start
	var lp: Dictionary = _buritis._crown_params[v][li]
	var az := float(lp.az) + float(bp.get("rot", 0.0))
	# deita no chão uns 2 a 3 m para fora do tronco, para o lado em que ela estava
	var out := Vector3(cos(-az), 0, sin(-az))
	var s: float = _buritis.crown_scale(bp)
	var land := Vector3(float(bp.x), 0, float(bp.z)) - out * randf_range(0.5, 1.2)
	if land_at != Vector3.INF:
		land = land_at
	land.y = height_at(land.x, land.z) + 0.05
	var yaw := randf() * TAU if yaw_at == INF else yaw_at
	var lying: Basis = (_buritis.leaf_lying_basis(v, li, yaw) as Basis).scaled(Vector3(s, s, s))
	var end := Transform3D(lying, land)
	var dur := clampf(sqrt(maxf(start.origin.y - land.y, 1.0) / 4.9) * 1.25, 0.9, 2.4)
	Sons.play_at(self, "folha_cai", start.origin + Vector3.DOWN * 4.0, vol, 1.75 / maxf(dur, 0.5) * 0.9, 120.0, 10.0)
	var tw := mi.create_tween()
	tw.tween_method(func(t: float) -> void:
		var e := t * t * (3.0 - 2.0 * t)
		var tr := start.interpolate_with(end, e)
		# balança e plana um pouco (folha grande segura o ar)
		tr.origin += Vector3(sin(t * 9.0), 0, cos(t * 7.0)) * 0.35 * sin(t * PI)
		mi.global_transform = tr, 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		mi.queue_free()
		if on_land.is_valid():
			on_land.call()
		else:
			_buritis.add_chao_folha(v, li, land, yaw, s))
