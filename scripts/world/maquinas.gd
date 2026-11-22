extends Node3D
## Máquinas e sistemas construídos por PROJETO (planta): o jogador escolhe o projeto,
## põe a planta no chão (só o desenho, em azul) e vai trazendo cada madeira — ela vai
## para o lugar dela na planta (a sobra fica para fora: tem que cortar a ponta, com a
## serra se a peça é deitada, com o machado se é em pé) — e a lâmina; depois prende
## cada junta com um pino de madeira batido com a marreta. Pronta, a máquina funciona.
##
## Serra de pedal (só em dupla): um pisa no pedal, do lado da máquina, fora do caminho
## da tora. O pedal é uma tábua com dobradiça; uma biela de madeira liga ele à lâmina e
## outra haste de madeira liga a lâmina à vara de mola lá em cima: pisando, a lâmina
## desce; soltando, a vara puxa ela de volta (tudo de madeira, sem corda). O outro
## empurra a tora pela mesa de entrada contra os dentes; a tora passa inteira pela
## lâmina (um corte por passada: tira uma fatia) e as duas peças param na mesa de saída,
## do outro lado: é lá que se pega. Para tirar outra fatia, põe de novo na entrada.
##
## Medidas no espaço da máquina: x = caminho da tora (ela entra pelo +x e sai pelo -x,
## a lâmina fica em x = 0), z = de lado (o pedal fica no -z), y = para cima.

const Sons := preload("res://scripts/sons.gd")

const Arvores := preload("res://scripts/world/arvores.gd")
const Furo := preload("res://scripts/world/furo.gd")

const TIPOS := {
	"serra_pedal": {
		"nome": "Serra de Pedal",
		"desc": "Serraria de madeira movida a pé, toda de madeira. Um jogador pisa no pedal (do lado) e a lâmina sobe e desce; o outro empurra a tora pela mesa contra a serra. Cada passada tira uma fatia; as peças saem na mesa do outro lado. Só funciona em dupla.",
		"versao": 2,
		"lamina": Vector3(0.0, 1.32, 0.0),
		# [tipo da madeira, comprimento (m), centro, deitada ao longo de "x"/"z" ou "y" (em pé), raio]
		"pecas": [
			["meia", 1.8, Vector3(0.0, 0.1, 0.45), "x", 0.13],      # 0 base esquerda
			["meia", 1.8, Vector3(0.0, 0.1, -0.45), "x", 0.13],     # 1 base direita
			["tora", 2.3, Vector3(0.0, 1.32, 0.45), "y", 0.09],     # 2 coluna esquerda
			["tora", 2.3, Vector3(0.0, 1.32, -0.45), "y", 0.09],    # 3 coluna direita
			["meia", 1.25, Vector3(-0.14, 2.52, 0.0), "z", 0.12],   # 4 travessa de cima (atrás da lâmina)
			["tora", 2.0, Vector3(-1.0, 2.66, 0.0), "x", 0.05],     # 5 vara de mola (a ponta em cima da lâmina)
			["tora", 0.95, Vector3(2.75, 0.475, 0.0), "y", 0.08],   # 6 pé da mesa de entrada
			["meia", 0.9, Vector3(2.75, 0.97, 0.0), "z", 0.1],      # 7 travessa da ponta (entrada)
			["meia", 0.9, Vector3(0.36, 0.97, 0.0), "z", 0.1],      # 8 travessa perto da serra (entrada)
			["tabua", 2.6, Vector3(1.55, 1.06, 0.14), "x", 0.08],   # 9 tábua da mesa de entrada
			["tabua", 2.6, Vector3(1.55, 1.06, -0.14), "x", 0.08],  # 10 tábua da mesa de entrada
			["tora", 0.95, Vector3(-2.75, 0.475, 0.0), "y", 0.08],  # 11 pé da mesa de saída
			["meia", 0.9, Vector3(-2.75, 0.97, 0.0), "z", 0.1],     # 12 travessa da ponta (saída)
			["meia", 0.9, Vector3(-0.36, 0.97, 0.0), "z", 0.1],     # 13 travessa perto da serra (saída)
			["tabua", 2.6, Vector3(-1.55, 1.06, 0.14), "x", 0.08],  # 14 tábua da mesa de saída
			["tabua", 2.6, Vector3(-1.55, 1.06, -0.14), "x", 0.08], # 15 tábua da mesa de saída
			["tabua", 1.9, Vector3(0.0, 0.19, -0.35), "z", 0.1],    # 16 pedal (dobradiça no +z, o pé no -z)
		],
		# juntas (cada uma leva um pino): [peças que ela prende, ponto]
		"pinos": [
			[[0, 2], Vector3(0.0, 0.26, 0.45)], [[1, 3], Vector3(0.0, 0.26, -0.45)],
			[[2, 4], Vector3(-0.14, 2.5, 0.45)], [[3, 4], Vector3(-0.14, 2.5, -0.45)],
			[[4, 5], Vector3(-0.14, 2.62, 0.0)],
			[[6, 7], Vector3(2.75, 0.95, 0.0)],
			[[7, 9], Vector3(2.75, 1.03, 0.14)], [[7, 10], Vector3(2.75, 1.03, -0.14)],
			[[8, 9], Vector3(0.36, 1.03, 0.14)], [[8, 10], Vector3(0.36, 1.03, -0.14)],
			[[11, 12], Vector3(-2.75, 0.95, 0.0)],
			[[12, 14], Vector3(-2.75, 1.03, 0.14)], [[12, 15], Vector3(-2.75, 1.03, -0.14)],
			[[13, 14], Vector3(-0.36, 1.03, 0.14)], [[13, 15], Vector3(-0.36, 1.03, -0.14)],
			[[0, 16], Vector3(0.0, 0.22, 0.45)],
		],
		"area": Rect2(-3.0, -1.35, 6.0, 1.95),   # no chão (x, z)
		"lamina_item": "lamina_serra",
		"lamina_pecas": [2, 3, 4],               # a lâmina vai entre as colunas e a travessa
	},
	# Desfibradeira de talo: duas toras em pé cortadas na mesma altura com uma tábua
	# comprida em cima (a bancada), e na frente uma tora mais baixa com uma tábua (o
	# banco). Em cima da bancada, as lâminas de faca em pé, com o fio para cima e ao
	# comprido (na direção de quem puxa). Sentado no banco, o jogador bate o talo de
	# buriti nas lâminas e puxa: o talo se abre em fibras.
	# Medidas: x = da bancada (0) para o banco (-x), z = de lado, y = para cima.
	"desfibradeira": {
		"nome": "Desfibradeira de Talo",
		"desc": "Bancada para tirar a fibra do talo de buriti. Sentado no banco, bata o talo em cima das lâminas de faca e puxe: o talo vai se abrindo em fibras.",
		"pecas": [
			["tora", 0.85, Vector3(0.0, 0.425, 0.32), "y", 0.08],     # 0 pé da bancada
			["tora", 0.85, Vector3(0.0, 0.425, -0.32), "y", 0.08],    # 1 pé da bancada
			["tabua", 1.0, Vector3(0.0, 0.885, 0.0), "z", 0.17],      # 2 tábua da bancada
			["tora", 0.45, Vector3(-0.72, 0.225, 0.0), "y", 0.09],    # 3 pé do banco (mais baixo)
			["tabua", 0.5, Vector3(-0.72, 0.485, 0.0), "z", 0.15],    # 4 tábua do banco
		],
		"pinos": [
			[[0, 2], Vector3(0.0, 0.86, 0.32)], [[1, 2], Vector3(0.0, 0.86, -0.32)],
			[[3, 4], Vector3(-0.72, 0.46, 0.0)],
		],
		"area": Rect2(-0.95, -0.55, 1.15, 1.1),
		"lamina_item": "lamina_faca",
		"lamina_pecas": [0, 1, 2],
		# as lâminas de faca em pé em cima da bancada (fio para cima, ao comprido em x)
		"laminas": [Vector3(0.0, 0.94, -0.013), Vector3(0.0, 0.94, 0.0), Vector3(0.0, 0.94, 0.013)],
	},
	# Mesa de argila: dois pés (toras em pé na mesma altura); em cima de cada pé uma tábua
	# deitada atravessada (a travessa, mais comprida que o tampo é largo), pregada no pé;
	# e o tampo: duas tábuas lado a lado (uma de cada lado do meio, emendadas em cima dos
	# pés) pregadas nas duas travessas. Na frente, um
	# banquinho (toco baixo com uma tábua). Despeja o balde de argila no tampo e, sentado,
	# tira a sujeira com a mão: sai argila limpa.
	"mesa_argila": {
		"nome": "Mesa de Argila",
		"desc": "Mesa com banquinho para trabalhar a argila. Despeje um balde de argila em cima e, sentado, tire a sujeira com a mão (pedrinhas, raízes, folhas): sai argila limpa, pronta para fabricar.",
		"versao": 3,
		"pecas": [
			["tora", 0.7, Vector3(0.0, 0.35, 0.34), "y", 0.08],      # 0 pé da mesa
			["tora", 0.7, Vector3(0.0, 0.35, -0.34), "y", 0.08],     # 1 pé da mesa
			["tabua", 0.52, Vector3(0.0, 0.735, 0.34), "x", 0.15],   # 2 travessa: tábua em cima do pé 0 (a largura do tampo)
			["tabua", 0.52, Vector3(0.0, 0.735, -0.34), "x", 0.15],  # 3 travessa: tábua em cima do pé 1
			["tabua", 1.0, Vector3(-0.13, 0.805, 0.0), "z", 0.15],   # 4 tampo (do lado do banco)
			["tabua", 1.0, Vector3(0.13, 0.805, 0.0), "z", 0.15],    # 5 tampo (do outro lado)
			["tora", 0.42, Vector3(-0.72, 0.21, 0.0), "y", 0.09],    # 6 pé do banquinho
			["tabua", 0.45, Vector3(-0.72, 0.455, 0.0), "z", 0.14],  # 7 tábua do banquinho
		],
		# travessa no pé (pino em pé no meio); cada tábua nas duas travessas
		"pinos": [
			[[0, 2], Vector3(0.0, 0.71, 0.34)], [[1, 3], Vector3(0.0, 0.71, -0.34)],
			[[2, 4], Vector3(-0.13, 0.78, 0.34)], [[2, 5], Vector3(0.13, 0.78, 0.34)],
			[[3, 4], Vector3(-0.13, 0.78, -0.34)], [[3, 5], Vector3(0.13, 0.78, -0.34)],
			[[6, 7], Vector3(-0.72, 0.43, 0.0)],
		],
		"area": Rect2(-0.95, -0.6, 1.25, 1.2),
		"mesa": true,
		# a ponta que sobra da travessa só se corta com o tampo já em cima (corta rente)
		"cortar_depois": {2: [4, 5], 3: [4, 5]},
	},
	# Torno de oleiro (de pedal): armação quadrada (4 pés com 2 tábuas em cima e uma tábua
	# atravessada no meio, o mancal, com o furo do eixo). O eixo (tora fina em pé) passa
	# pelo mancal: em cima dele a mesa giratória (rodela grossa de tora), embaixo o
	# volante (rodela grande e pesada). O pedal (tábua embaixo) puxa o volante por uma
	# biela de madeira. Sentado no banquinho, pisa no pedal e a mesa gira: a argila limpa
	# no meio da mesa vira vasilha, bacia, cabaça (moringa), garrafa, filtro de barro...
	"torno_ceramica": {
		"nome": "Torno de Oleiro",
		"desc": "Torno de pedal para modelar argila limpa: pisando no pedal, o volante e a mesa redonda de cima giram, e a argila no meio vira vasilha, bacia, cabaça (moringa), garrafa ou filtro de barro. A mesa e o volante são rodelas: pedaços curtos de tora grossa (ponha o pedaço e corte a sobra com o machado).",
		"pecas": [
			["tora", 0.55, Vector3(0.3, 0.275, 0.3), "y", 0.06],     # 0 pé da armação
			["tora", 0.55, Vector3(0.3, 0.275, -0.3), "y", 0.06],    # 1 pé
			["tora", 0.55, Vector3(-0.3, 0.275, 0.3), "y", 0.06],    # 2 pé
			["tora", 0.55, Vector3(-0.3, 0.275, -0.3), "y", 0.06],   # 3 pé
			["tabua", 0.72, Vector3(0.0, 0.585, 0.3), "x", 0.14],    # 4 tábua em cima dos pés 0 e 2
			["tabua", 0.72, Vector3(0.0, 0.585, -0.3), "x", 0.14],   # 5 tábua em cima dos pés 1 e 3
			["tabua", 0.72, Vector3(0.0, 0.655, 0.0), "z", 0.14],    # 6 mancal (atravessada no meio, com o furo do eixo)
			["tora", 0.7, Vector3(0.0, 0.36, 0.0), "y", 0.035],      # 7 eixo
			["tora", 0.08, Vector3(0.0, 0.15, 0.0), "y", 0.26, 0.17],  # 8 volante (rodela grossa embaixo)
			["tora", 0.06, Vector3(0.0, 0.73, 0.0), "y", 0.2, 0.13],   # 9 mesa giratória (rodela em cima)
			["tabua", 0.6, Vector3(-0.45, 0.04, 0.0), "x", 0.15],    # 10 pedal
			["tora", 0.45, Vector3(-1.0, 0.225, 0.0), "y", 0.09],    # 11 pé do banquinho
			["tabua", 0.45, Vector3(-1.0, 0.485, 0.0), "z", 0.14],   # 12 tábua do banquinho
		],
		"pinos": [
			[[0, 4], Vector3(0.3, 0.57, 0.3)], [[2, 4], Vector3(-0.3, 0.57, 0.3)],
			[[1, 5], Vector3(0.3, 0.57, -0.3)], [[3, 5], Vector3(-0.3, 0.57, -0.3)],
			[[4, 6], Vector3(0.0, 0.64, 0.3)], [[5, 6], Vector3(0.0, 0.64, -0.3)],
			[[7, 9], Vector3(0.0, 0.76, 0.0), Vector3(0, 1, 0)],    # a mesa no topo do eixo (de cima)
			[[7, 8], Vector3(0.0, 0.11, 0.0), Vector3(0, -1, 0)],   # o volante no eixo (de baixo)
			[[11, 12], Vector3(-1.0, 0.46, 0.0)],
		],
		"area": Rect2(-1.25, -0.45, 1.7, 0.9),
		"torno": true,
	},
	# Peneira de água (filtro artesanal): quatro pés com duas tábuas em cima, e nelas a
	# caixa: fundo de duas tábuas (com a fresta no meio, por onde a água pinga) e quatro
	# tábuas em pé de lado. Dentro, de baixo para cima: pedrinhas, carvão, areia e a tela
	# de fibra. A água do balde jogada em cima passa devagar e pinga limpa na vasilha de
	# barro embaixo.
	"filtro_agua": {
		"nome": "Peneira de Água",
		"desc": "Filtro artesanal: caixa de tábuas em quatro pés. Dentro vão pedrinhas, carvão e areia do mar, com a tela de fibra por cima; embaixo, uma vasilha ou bacia de barro. A água do balde jogada em cima sai limpa e segura para beber.",
		"pecas": [
			["tora", 0.6, Vector3(0.22, 0.3, 0.22), "y", 0.05],        # 0 pé
			["tora", 0.6, Vector3(0.22, 0.3, -0.22), "y", 0.05],       # 1 pé
			["tora", 0.6, Vector3(-0.22, 0.3, 0.22), "y", 0.05],       # 2 pé
			["tora", 0.6, Vector3(-0.22, 0.3, -0.22), "y", 0.05],      # 3 pé
			["tabua", 0.56, Vector3(0.0, 0.635, 0.22), "x", 0.14],     # 4 tábua em cima dos pés 0 e 2
			["tabua", 0.56, Vector3(0.0, 0.635, -0.22), "x", 0.14],    # 5 tábua em cima dos pés 1 e 3
			["tabua", 0.56, Vector3(-0.11, 0.705, 0.0), "z", 0.13],    # 6 fundo da caixa
			["tabua", 0.56, Vector3(0.11, 0.705, 0.0), "z", 0.13],     # 7 fundo da caixa
			["tabua", 0.5, Vector3(0.0, 0.86, 0.2), "x_lado", 0.14],   # 8 lado da frente
			["tabua", 0.5, Vector3(0.0, 0.86, -0.2), "x_lado", 0.14],  # 9 lado de trás
			["tabua", 0.36, Vector3(0.23, 0.86, 0.0), "z_lado", 0.14], # 10 lado direito
			["tabua", 0.36, Vector3(-0.23, 0.86, 0.0), "z_lado", 0.14],# 11 lado esquerdo
		],
		"pinos": [
			[[0, 4], Vector3(0.22, 0.62, 0.22)], [[2, 4], Vector3(-0.22, 0.62, 0.22)],
			[[1, 5], Vector3(0.22, 0.62, -0.22)], [[3, 5], Vector3(-0.22, 0.62, -0.22)],
			[[4, 6], Vector3(-0.11, 0.69, 0.22)], [[4, 7], Vector3(0.11, 0.69, 0.22)],
			[[5, 6], Vector3(-0.11, 0.69, -0.22)], [[5, 7], Vector3(0.11, 0.69, -0.22)],
			[[8, 10], Vector3(0.23, 0.86, 0.225), Vector3(0, 0, 1)], [[8, 11], Vector3(-0.23, 0.86, 0.225), Vector3(0, 0, 1)],
			[[9, 10], Vector3(0.23, 0.86, -0.225), Vector3(0, 0, -1)], [[9, 11], Vector3(-0.23, 0.86, -0.225), Vector3(0, 0, -1)],
		],
		"area": Rect2(-0.45, -0.45, 0.9, 0.9),
		"filtro": true,
	},
	# Forno de carvão: um domo de pedras do chão rebocado de barro por cima, com uma boca
	# na frente (a porta: duas tábuas em pé de lado, que abrem e fecham) e o suspiro em
	# cima, atrás. Enche de lenha, acende, fecha a porta: a lenha vira carvão.
	"forno": {
		"nome": "Forno de Carvão",
		"desc": "Domo de pedras do chão coberto de barro, com uma porta de tábuas e o suspiro em cima. Encha de lenha, acenda com o arco de fogo e feche a porta: a lenha queima devagar, sem ar, e vira carvão.",
		"pecas": [
			["tabua", 0.52, Vector3(0.6, 0.15, 0.0), "z_lado", 0.14],    # 0 porta: tábua de baixo
			["tabua", 0.52, Vector3(0.6, 0.41, 0.0), "z_lado", 0.14],    # 1 porta: tábua de cima
		],
		"pinos": [],
		"area": Rect2(-0.95, -0.9, 1.75, 1.8),
		"forno": {"pedras": 16, "barro": 4},
	},
}

const FILTRO_FUNDO := 0.74       # em cima das tábuas do fundo da caixa
const FILTRO_PEDRAS := 6
const FILTRO_CARVAO := 3
const FILTRO_CIMA_MAX := 24.0    # litros de água que cabem em cima da areia
const FILTRO_VAZAO := 0.06       # litros que passam pelas camadas a cada passo do relógio (6 por segundo)
const POTE_L := {"vasilha_barro": 3.0, "bacia_barro": 8.0}

const FORNO_CAP := 12            # lenhas que cabem dentro
const FORNO_S := 360.0           # segundos de verdade com a porta fechada até virar carvão
const FORNO_R := 0.82            # raio do domo
const FORNO_H := 0.95            # altura do domo
const FORNO_FRENTE := 0.55       # a parede da frente (reta, com a boca)

const TORNO_MESA := 0.76         # em cima da mesa giratória do torno (m)
const MESA_TOPO := 0.84          # em cima do tampo (m)
const MESA_SUJEIRA := 10         # coisas para tirar num balde cheio de argila
const MESA_BOLAS := 8            # bolas de argila limpa num balde cheio

const NOMES := {"tora": "tora redonda", "meia": "meia tora (tora rachada ao meio)", "tabua": "tábua", "lenha": "lenha (lenha é só para o fogo)"}
const BOARD_T := 0.05            # grossura das tábuas que a serra tira (m)

var plantas: Array = []          # {tipo, x, y, z, yaw, pecas: [bool], pinos: [bool], sobra: [m], lamina, tora, prog}
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


## Quanto de cada coisa o projeto pede: {tora: n, meia: n, tabua: n, pino: n, lamina: n}
static func needs(tipo: String) -> Dictionary:
	var t: Dictionary = TIPOS[tipo]
	var out := {"tora": 0, "meia": 0, "tabua": 0}
	for pc in t.pecas:
		out[pc[0]] = int(out[pc[0]]) + 1
	out["pino"] = (t.pinos as Array).size()
	out["lamina"] = lamina_need(tipo)
	out["lamina_item"] = str(t.get("lamina_item", "lamina_serra"))
	var fz: Dictionary = t.get("forno", {})
	out["pedra"] = int(fz.get("pedras", 0))
	out["barro"] = int(fz.get("barro", 0))
	return out


## Quantas lâminas o projeto leva.
static func lamina_need(tipo: String) -> int:
	if TIPOS[tipo].has("laminas"):
		return (TIPOS[tipo].laminas as Array).size()
	return 1 if TIPOS[tipo].has("lamina") else 0          # (a mesa não tem lâmina)


## Quantas lâminas já estão postas (antes era só sim/não).
func lamina_count(mi: int) -> int:
	var v = plantas[mi].get("lamina", false)
	if v is bool:
		return lamina_need(str(plantas[mi].tipo)) if v else 0
	return int(v)


static func lamina_count_of(p: Dictionary) -> int:
	var v = p.get("lamina", false)
	if v is bool:
		return 1 if v else 0
	return int(v)


## Já dá para pôr lâmina (as peças em que ela vai estão no lugar) e ainda falta alguma?
func lamina_open(mi: int) -> bool:
	var p: Dictionary = plantas[mi]
	if lamina_count(mi) >= lamina_need(str(p.tipo)):
		return false
	for si in TIPOS[p.tipo].get("lamina_pecas", []):
		if not bool(p.pecas[int(si)]):
			return false
	return true


func add_lamina(mi: int) -> void:
	plantas[mi].lamina = lamina_count(mi) + 1
	_rebuild()


## Modo de teste: a planta já sai montada (madeiras, furos, pinos, lâminas, pontas).
func complete(mi: int) -> void:
	var p: Dictionary = plantas[mi]
	for i in (p.pecas as Array).size():
		p.pecas[i] = true
		p.sobra[i] = 0.0
	for j in (p.pinos as Array).size():
		p.pinos[j] = 2
	p.lamina = lamina_need(str(p.tipo))
	var fz: Dictionary = TIPOS[p.tipo].get("forno", {})
	if not fz.is_empty():
		p["ped"] = int(fz.pedras)
		p["bar"] = int(fz.barro)
	_rebuild()


func add_planta(tipo: String, x: float, z: float, yaw: float) -> void:
	var t: Dictionary = TIPOS[tipo]
	var pcs := []
	for _p in t.pecas:
		pcs.append(false)
	var am := []
	for _a in t.pinos:
		am.append(0)              # 0 sem nada, 1 furado, 2 com o pino batido
	var sob := []
	for _p in t.pecas:
		sob.append(0.0)
	plantas.append({"tipo": tipo, "x": x, "y": _jogo.surface_at(x, z), "z": z, "yaw": yaw, "pecas": pcs, "pinos": am,
		"sobra": sob, "lamina": false, "tora": {}, "prog": 0.0, "saida": [], "versao": int(t.get("versao", 1))})
	_rebuild()


func xform(mi: int) -> Transform3D:
	var p: Dictionary = plantas[mi]
	return Transform3D(Basis(Vector3.UP, float(p.yaw)), Vector3(float(p.x), float(p.y), float(p.z)))


static func slot_basis(dir: String) -> Basis:
	match dir:
		"z": return Basis(Vector3.UP, PI * 0.5)
		"y": return Basis(Vector3.BACK, PI * 0.5)
		"x_lado": return Basis(Vector3.RIGHT, PI * 0.5)                       # tábua em pé de lado
		"z_lado": return Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5)
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
	if fl.has("lenha"):
		return "lenha"                    # toquinho e acha: só para o fogo
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
	var fz: Dictionary = TIPOS[p.tipo].get("forno", {})
	if not fz.is_empty() and (int(p.get("ped", 0)) < int(fz.pedras) or int(p.get("bar", 0)) < int(fz.barro)):
		return false
	if lamina_count(mi) < lamina_need(str(p.tipo)):
		return false
	for b in p.pecas:
		if not bool(b):
			return false
	for b in p.pinos:
		if int(b) < 2:
			return false
	for v in p.get("sobra", []):
		if float(v) > 0.0:
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
	var thin := 0.0
	var xf := xform(mi)
	for i in (t.pecas as Array).size():
		if bool(p.pecas[i]):
			continue
		var pc: Array = t.pecas[i]
		if str(pc[0]) != kind:
			continue
		any_kind = true
		if L < float(pc[1]) - 0.02:
			short = maxf(short, float(pc[1]))
			continue
		if kind == "tora" and r > float(pc[4]) * 2.6:
			continue                   # tora grossa demais para essa peça
		if pc.size() > 5 and r < float(pc[5]):
			thin = float(pc[5]) if thin <= 0.0 else minf(thin, float(pc[5]))
			continue                   # fina demais (a rodela da mesa e o volante são de tora grossa)
		var w := xf * (pc[2] as Vector3)
		var d := Vector2(w.x - pos.x, w.z - pos.z).length()
		if d < bd:
			bd = d
			best = i
	if best >= 0:
		return {"i": best, "sobra": maxf(0.0, L - float(t.pecas[best][1]))}
	if not any_kind:
		return {"i": -1, "why": "A planta não precisa de mais %s." % NOMES.get(kind, kind)}
	if thin > 0.0:
		return {"i": -1, "why": "Essa tora é fina para a rodela que falta (a mesa e o volante são de tora grossa: raio de pelo menos %d cm)." % roundi(thin * 100.0) + (" Para as outras peças, é curta: precisa de %.2f m." % short if short > 0.0 else "")}
	if short > 0.0:
		return {"i": -1, "why": "Essa madeira é curta: essa peça precisa de pelo menos %.2f m." % short}
	return {"i": -1, "why": "Essa tora é grossa demais para as peças que faltam (precisa ser fina)."}


func fill_slot(mi: int, si: int, sobra := 0.0, fl := {}) -> void:
	plantas[mi].pecas[si] = true
	if not fl.is_empty():
		# a madeira de verdade que o jogador trouxe (a mesma cor, casca e formato)
		if not plantas[mi].has("madeiras"):
			plantas[mi]["madeiras"] = {}
		var c: Dictionary = fl.duplicate(true)
		for k in ["pos", "yaw", "em_pe", "corte_m", "entalhe", "racha"]:
			c.erase(k)
		plantas[mi].madeiras[str(si)] = c
	if not plantas[mi].has("sobra"):
		plantas[mi]["sobra"] = []
		for _p in plantas[mi].pecas:
			plantas[mi].sobra.append(0.0)
	plantas[mi].sobra[si] = snappedf(sobra, 0.005) if sobra > 0.015 else 0.0
	_rebuild()


## A madeira da peça (a de verdade, se tiver), no comprimento Lw.
func piece_log(mi: int, si: int, Lw: float) -> Dictionary:
	var md: Dictionary = plantas[mi].get("madeiras", {})
	var pc: Array = TIPOS[plantas[mi].tipo].pecas[si]
	if not md.has(str(si)):
		var p2: Array = pc.duplicate()
		p2[1] = Lw
		return slot_log(p2)
	var fl: Dictionary = (md[str(si)] as Dictionary).duplicate(true)
	if fl.has("cil"):
		fl.cil.L = Lw
	else:
		var L0: float = _arv.free_log_length(fl)
		if L0 > 0.01:
			fl.h1 = float(fl.h0) + (float(fl.h1) - float(fl.h0)) * Lw / L0
	return fl


## A ponta que passou do tamanho: no espaço da máquina, onde cortar e para que lado
## está a sobra. {pos (corte), mid (meio da sobra), dir, deitada}
func sobra_info(mi: int, si: int) -> Dictionary:
	var t: Dictionary = TIPOS[plantas[mi].tipo]
	var pc: Array = t.pecas[si]
	var b := slot_basis(str(pc[3]))
	var L := float(pc[1])
	var e := float(plantas[mi].sobra[si])
	var c: Vector3 = pc[2]
	var xf := xform(mi)
	var cut := c + b.x * (L * 0.5)
	return {"pos": xf * cut, "mid": xf * (cut + b.x * e * 0.5), "deitada": str(pc[3]) != "y", "len": e}


## Já dá para cortar a ponta dessa peça? (algumas só depois das peças de cima no lugar)
func sobra_pode(mi: int, si: int) -> bool:
	var dep: Dictionary = TIPOS[plantas[mi].tipo].get("cortar_depois", {})
	for d in dep.get(si, []):
		if not bool(plantas[mi].pecas[int(d)]):
			return false
	return true


## Peça com sobra perto (para cortar a ponta): [planta, peça] ou [].
func sobra_near(pos: Vector3, reach := 1.8) -> Array:
	var best := []
	var bd := reach
	for mi in plantas.size():
		var sob: Array = plantas[mi].get("sobra", [])
		for si in sob.size():
			if float(sob[si]) <= 0.0 or not sobra_pode(mi, si):
				continue
			var w: Vector3 = sobra_info(mi, si).pos
			var d := Vector2(w.x - pos.x, w.z - pos.z).length()
			if d < bd:
				bd = d
				best = [mi, si]
	return best


## Corta a ponta: a peça fica do tamanho certo; devolve o pedaço (para cair no chão).
func trim(mi: int, si: int) -> Dictionary:
	var t: Dictionary = TIPOS[plantas[mi].tipo]
	var pc: Array = t.pecas[si].duplicate()
	var e := float(plantas[mi].sobra[si])
	var bit := piece_log(mi, si, e)
	plantas[mi].sobra[si] = 0.0
	_rebuild()
	return bit


## Juntas que já dá para pôr o pino (as peças delas estão no lugar) e ainda não têm.
func joint_near(pos: Vector3, reach := 1.7) -> Array:
	var best := []
	var bd := reach
	for mi in plantas.size():
		var p: Dictionary = plantas[mi]
		var t: Dictionary = TIPOS[p.tipo]
		var xf := xform(mi)
		for ji in (t.pinos as Array).size():
			if int(p.pinos[ji]) >= 2 or not _joint_open(mi, ji):
				continue
			var w := joint_point(mi, ji)
			var d := Vector2(w.x - pos.x, w.z - pos.z).length()
			if d < bd:
				bd = d
				best = [mi, ji]
	return best


func joint_point(mi: int, ji: int) -> Vector3:
	# onde bate: em cima do furo
	return xform(mi) * (_joint_seg(str(plantas[mi].tipo), ji)[1] as Vector3)


func _joint_open(mi: int, ji: int) -> bool:
	var p: Dictionary = plantas[mi]
	var t: Dictionary = TIPOS[p.tipo]
	for si in t.pinos[ji][0]:
		if not bool(p.pecas[int(si)]):
			return false
	return true


## Os pinos que dá para pôr perto (as peças da junta estão no lugar): [{mi, ji, pos}]
func pin_targets(pos: Vector3, reach := 2.6) -> Array:
	var out := []
	for mi in plantas.size():
		var p: Dictionary = plantas[mi]
		var t: Dictionary = TIPOS[p.tipo]
		for ji in (t.pinos as Array).size():
			if int(p.pinos[ji]) >= 2 or not _joint_open(mi, ji):
				continue
			var w := joint_point(mi, ji)
			if Vector2(w.x - pos.x, w.z - pos.z).length() < reach:
				var sg := _joint_seg(str(p.tipo), ji)
				var dw: Vector3 = (xform(mi).basis * ((sg[1] as Vector3) - (sg[0] as Vector3))).normalized()
				out.append({"mi": mi, "ji": ji, "pos": w, "stage": int(p.pinos[ji]), "dir": dw})
	return out


## O que falta na planta antes de pôr outra madeira: {furos, pinos, pontas}
func pending_work(mi: int) -> Dictionary:
	var p: Dictionary = plantas[mi]
	var t: Dictionary = TIPOS[p.tipo]
	var out := {"furos": 0, "pinos": 0, "pontas": 0}
	for ji in (t.pinos as Array).size():
		if not _joint_open(mi, ji):
			continue
		if int(p.pinos[ji]) == 0:
			out.furos += 1
		elif int(p.pinos[ji]) == 1:
			out.pinos += 1
	var sob: Array = p.get("sobra", [])
	for i in sob.size():
		if float(sob[i]) > 0.0 and sobra_pode(mi, i):
			out.pontas += 1           # (a que só se corta depois, com o de cima no lugar, não trava)
	return out


func set_stage(mi: int, ji: int, st: int) -> void:
	plantas[mi].pinos[ji] = st
	_rebuild()


## Meia medida da peça da planta (comprido, grosso, largo) no espaço dela.
func _slot_half(pc: Array, extra := 0.0) -> Vector3:
	var fl := slot_log(pc)
	var e: Vector2 = _arv._sec_ext(fl)
	var r := float(pc[4])
	if str(pc[3]).ends_with("_lado"):
		return Vector3((float(pc[1]) + extra) * 0.5, e.y * r, e.x * r)       # em pé de lado: a largura vira altura
	return Vector3((float(pc[1]) + extra) * 0.5, e.x * r, e.y * r)


## O furo da junta (no espaço da máquina): em pé, atravessando as peças deitadas e
## entrando um pouco na coluna. [baixo, cima]
func _joint_seg(tipo: String, ji: int) -> Array:
	var t: Dictionary = TIPOS[tipo]
	var jp: Vector3 = t.pinos[ji][1]
	if (t.pinos[ji] as Array).size() > 2:
		# pino deitado: entra de fora (jp) para dentro, atravessando a tábua e entrando
		# na ponta da outra
		var d: Vector3 = (t.pinos[ji][2] as Vector3).normalized()
		return [jp - d * 0.2, jp + d * 0.002]
	var top := -1e9
	var bot := 1e9
	var verts := []
	for si in t.pinos[ji][0]:
		var pc: Array = t.pecas[int(si)]
		var c: Vector3 = pc[2]
		if str(pc[3]) == "y":
			verts.append(pc)
			continue
		var hh := _slot_half(pc)
		top = maxf(top, c.y + hh.y)
		bot = minf(bot, c.y - hh.y)
	for pc in verts:
		var c: Vector3 = pc[2]
		var L := float(pc[1])
		if c.y - L * 0.5 >= top - 0.05:
			top += 0.12            # a coluna em cima: o furo entra no pé dela
		else:
			bot -= 0.12            # a travessa em cima da coluna: entra na ponta dela
	return [Vector3(jp.x, bot - 0.01, jp.z), Vector3(jp.x, top + 0.01, jp.z)]


func tie(mi: int, ji: int) -> void:
	set_stage(mi, ji, 2)


func pending_joints(mi: int) -> int:
	var n := 0
	for b in plantas[mi].pinos:
		if int(b) < 2:
			n += 1
	return n


# ================== A SERRA FUNCIONANDO ==================

## Lugar de cada um na serra: "pedal" (atrás, do lado do pedal), "mesa" (na ponta da
## mesa, empurrando) ou "".
func role_at(mi: int, pos: Vector3) -> String:
	if str(plantas[mi].tipo) != "serra_pedal":
		return ""
	var l := xform(mi).affine_inverse() * pos
	if l.z < -1.2 and l.z > -2.6 and absf(l.x) < 1.2:
		return "pedal"                 # do lado, fora do caminho da tora
	if l.x > 2.6 and l.x < 5.2 and absf(l.z) < 1.7:
		return "mesa"                  # na ponta da mesa de entrada (empurra daqui)
	if l.x < -2.6 and l.x > -5.2 and absf(l.z) < 1.7:
		return "saida"                 # na ponta da mesa de saída (pega as peças)
	return ""


## Como a tora vai ser cortada: a lâmina tira uma fatia de BOARD_T de um lado.
## {a (onde corta, na seção), mn, mx, r, ok}
func cut_plan(fl: Dictionary, giro := 0.0, desl := 0.0) -> Dictionary:
	var sec: Dictionary = fl.sec if fl.has("sec") else Arvores.circle_sec()
	var mn := 1e9
	var mx := -1e9
	var ymn := 1e9
	for q in _rot_pts(sec.pts, giro):
		mn = minf(mn, float(q[0]))
		mx = maxf(mx, float(q[0]))
		ymn = minf(ymn, float(q[1]))
	var r: float = _arv.free_log_max_radius(fl)
	# desl: quanto quem empurra moveu a tora de lado (a fatia fica mais grossa ou fina)
	var t := (BOARD_T + desl) / maxf(r, 0.01)
	var tmin := 0.02 / maxf(r, 0.01)
	t = clampf(t, tmin, maxf(tmin, mx - mn - tmin))
	return {"a": mx - t, "mn": mn, "mx": mx, "ymn": ymn, "r": r, "ok": mx - mn > (BOARD_T / maxf(r, 0.01)) * 1.6, "esp": t * r}


## A seção girada (quem empurra gira a tora na mesa para escolher onde a lâmina corta).
static func _rot_pts(pts: Array, g: float) -> Array:
	if absf(g) < 0.0001:
		return pts
	var out := []
	var c := cos(g)
	var sn := sin(g)
	for q in pts:
		out.append([float(q[0]) * c - float(q[1]) * sn, float(q[0]) * sn + float(q[1]) * c, int(q[2])])
	return out


## Põe a tora na mesa de entrada (a ponta encostando nos dentes).
func load_log(mi: int, fl: Dictionary) -> void:
	plantas[mi].tora = fl
	plantas[mi].prog = 0.0
	plantas[mi].giro = 0.0
	plantas[mi].desl = 0.0
	_rebuild()


## Move a tora de lado na mesa (só antes da lâmina pegar): a lâmina tira a tábua mais
## para dentro ou mais na beirada.
func slide(mi: int, d: float) -> bool:
	var p: Dictionary = plantas[mi]
	if (p.tora as Dictionary).is_empty() or cutting(mi) or float(p.prog) > 0.0:
		return false
	var cp := cut_plan(p.tora, float(p.get("giro", 0.0)), 0.0)
	var span: float = (float(cp.mx) - float(cp.mn)) * float(cp.r)
	p.desl = clampf(float(p.get("desl", 0.0)) + d, -BOARD_T + 0.02, span - BOARD_T - 0.02)
	_place_tora(mi)
	return true


func _place_tora(mi: int) -> void:
	var p: Dictionary = plantas[mi]
	var nd: Dictionary = _nodes.get(mi, {})
	if nd.has("tora") and is_instance_valid(nd.tora):
		(nd.tora as Node3D).basis = Basis(Vector3.RIGHT, -float(p.get("giro", 0.0)))
		(nd.tora as Node3D).position = _log_pos(mi)


## Espessura da tábua que vai sair com a tora como está agora (m).
func slice_thickness(mi: int) -> float:
	var p: Dictionary = plantas[mi]
	if (p.tora as Dictionary).is_empty():
		return 0.0
	return float(cut_plan(p.tora, float(p.get("giro", 0.0)), float(p.get("desl", 0.0))).esp)


## Gira a tora na mesa (só antes da lâmina pegar nela).
func spin(mi: int, d: float) -> bool:
	var p: Dictionary = plantas[mi]
	if (p.tora as Dictionary).is_empty() or cutting(mi) or float(p.prog) > 0.0:
		return false
	p.giro = wrapf(float(p.get("giro", 0.0)) + d, -PI, PI)
	_place_tora(mi)
	return true


func take_saida(mi: int) -> Dictionary:
	var sa: Array = plantas[mi].get("saida", [])
	if sa.is_empty():
		return {}
	var fl: Dictionary = sa.pop_front()
	_rebuild()
	return fl


## A tora está passando pela lâmina agora?
func cutting(mi: int) -> bool:
	var p: Dictionary = plantas[mi]
	if (p.tora as Dictionary).is_empty():
		return false
	var L: float = _arv.free_log_length(p.tora)
	var d := float(p.prog) * (L + 0.1)
	return d >= 0.05 and d <= L + 0.05


## Quem manda no corte (o dono do mundo, ou quem joga sozinho): soma o pedal e o
## empurrão de todo mundo. Antes de encostar nos dentes a tora escorrega pela mesa; na
## lâmina, só anda com o pedal subindo e descendo E a tora sendo empurrada.
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
		if str(p.tipo) != "serra_pedal":
			continue
		var xf := xform(mi)
		var ph0 := float(p.get("_ph", 0.0))
		var ph := ph0 + delta * clampf(pedal, 0.0, 3.0) * 7.0
		p["_ph"] = ph
		if pronta(mi):
			_animate(mi, sin(ph) * 0.12)
		var nd: Dictionary = _nodes.get(mi, {})
		if nd.has("tora") and is_instance_valid(nd.tora) and not (p.tora as Dictionary).is_empty():
			(nd.tora as Node3D).position = _log_pos(mi)
		# sons: o pedal range a cada pisada; a lâmina só faz o barulho de serrar com
		# madeira encostada nela e andando
		var corta := cutting(mi) and pedal > 0.05 and emp > 0.02
		if pedal > 0.05 and floori(ph0 / TAU) != floori(ph / TAU):
			Sons.play_at(_jogo, "pedal_range", xf * Vector3(0.0, 0.25, -1.1), 0.0, randf_range(0.92, 1.08))
		if corta and floori(ph0 / PI) != floori(ph / PI):
			Sons.play_at(_jogo, "serra_corte", xf * Vector3(0.0, 1.2, 0.0), 0.0, randf_range(0.94, 1.06))
		if not authority or (p.tora as Dictionary).is_empty() or not pronta(mi):
			continue
		var L: float = _arv.free_log_length(p.tora)
		var r: float = _arv.free_log_max_radius(p.tora)
		var v := 0.0
		if cutting(mi):
			# madeira grossa demora mais (uns 8 cm por segundo numa tora de 20 cm)
			v = minf(pedal, emp) * 0.08 / maxf(r / 0.1, 0.6)
		else:
			v = emp * 0.35               # escorregando na mesa (antes e depois da lâmina)
		if v <= 0.0:
			continue
		p.prog = minf(1.0, float(p.prog) + v * delta / (L + 0.1))
		if float(p.prog) >= 1.0:
			_finish_cut(mi)


## Onde a tora está na mesa (centro dela, no espaço da máquina): começa com a ponta
## encostando nos dentes e vai passando para o -x até sair inteira do outro lado.
func _log_pos(mi: int) -> Vector3:
	var p: Dictionary = plantas[mi]
	var L: float = _arv.free_log_length(p.tora)
	var cp := cut_plan(p.tora, float(p.get("giro", 0.0)), float(p.get("desl", 0.0)))
	var x := L * 0.5 + 0.05 - float(p.prog) * (L + 0.1)
	return Vector3(x, 1.09 - float(cp.ymn) * float(cp.r), -float(cp.a) * float(cp.r))


## Passou inteira: um corte só. A fatia e o resto ficam na mesa de saída.
func _finish_cut(mi: int) -> void:
	var p: Dictionary = plantas[mi]
	var fl: Dictionary = p.tora
	p.tora = {}
	p.prog = 0.0
	var g := float(p.get("giro", 0.0))
	var cp := cut_plan(fl, g, float(p.get("desl", 0.0)))
	var sec: Dictionary = fl.sec if fl.has("sec") else Arvores.circle_sec()
	var rpts := _rot_pts(sec.pts, g)
	var cil: Dictionary
	if fl.has("cil"):
		cil = (fl.cil as Dictionary).duplicate()
	else:
		cil = {"L": _arv.free_log_length(fl), "ra": _arv.free_log_radius_at(fl, 0.02), "rb": _arv.free_log_radius_at(fl, 0.98)}
	var out := []
	for band in [[float(cp.a), float(cp.mx)], [float(cp.mn), float(cp.a)]]:
		var poly := _band(rpts, band[0], band[1], 2)       # face da serra: lisa (tipo 2)
		if poly.size() < 3:
			continue
		var pc := {"cil": cil.duplicate(), "sec": Arvores._lay_flat(poly, sec.ax), "v": int(fl.get("v", 0)), "s": 1.0,
			"h0": 0.0, "h1": 1.0, "bot": {}, "top": {}, "pos": [0, 0, 0], "yaw": 0.0, "dia": int(fl.get("dia", 0))}
		if fl.has("casca"):
			pc["casca"] = fl.casca
		out.append(pc)
	p["saida"] = out
	_rebuild()
	if _jogo.has_method("_show_toast"):
		_jogo._show_toast("A serra tirou uma fatia! As peças estão na mesa do outro lado.")


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
		var poly := _band(sec.pts, a, b, 2)
		if poly.size() >= 3:
			out.append({"cil": cil.duplicate(), "sec": Arvores._lay_flat(poly, sec.ax), "v": int(fl.get("v", 0)), "s": 1.0,
				"h0": 0.0, "h1": 1.0, "bot": {}, "top": {}, "pos": [0, 0, 0], "yaw": 0.0, "dia": int(fl.get("dia", 0))})
		a = b
	return out


## Pedaço da seção entre z = a e z = b (cortes da serra: arestas novas são face serrada).
static func _band(pts_in: Array, a: float, b: float, ctype := 1) -> Array:
	var poly := []
	for q in pts_in:
		poly.append([float(q[0]), float(q[1]), int(q[2])])
	poly = _clip(poly, a, 1.0, ctype)
	poly = _clip(poly, b, -1.0, ctype)
	return poly


## Corta o polígono [z, y, tipo da aresta que sai] pela reta z = v, ficando do lado
## s*(z - v) >= 0. A aresta nova (o corte) é do tipo 1 (madeira).
static func _clip(poly: Array, v: float, s: float, ctype := 1) -> Array:
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
				out.append([I[0], I[1], ctype])
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
				var sob: Array = p.get("sobra", [])
				var e: float = float(sob[si]) if si < sob.size() else 0.0
				var wfl := piece_log(mi, si, float(pc[1]) + e)
				var n: Node3D = _arv.free_log_node(wfl)
				root.add_child(n)
				# a sobra fica para fora numa ponta
				var bb := b
				if str(pc[0]) == "tabua":
					bb = b * Basis(Vector3.RIGHT, PI)      # a tábua virada: a face rachada (reta) para cima
				n.transform = Transform3D(bb, (pc[2] as Vector3) + b.x * e * 0.5)
				nd["p_%d" % si] = n
				nd["t_%d" % si] = n.transform
				# os furos das juntas dessa peça
				var holes := []
				var inv := n.transform.affine_inverse()
				for ji in (t.pinos as Array).size():
					if int(p.pinos[ji]) < 1 or not (t.pinos[ji][0] as Array).has(si):
						continue
					var sg := _joint_seg(str(p.tipo), ji)
					holes.append([inv * (sg[0] as Vector3), inv * (sg[1] as Vector3), 0.022])
				var ex: Vector2 = _arv._sec_ext(wfl)
				var rr: float = _arv.free_log_max_radius(wfl)
				Furo.apply(n, holes, Vector3((float(pc[1]) + e) * 0.5, ex.x * rr, ex.y * rr))
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
		# juntas: com o pino batido, ou esperando o pino (bolinha amarela)
		for ji in (t.pinos as Array).size():
			var at: Vector3 = t.pinos[ji][1]
			var sg2 := _joint_seg(str(p.tipo), ji)
			if int(p.pinos[ji]) >= 2:
				# o pino batido passando pelo furo (as pontas aparecem dos dois lados)
				# o pino batido até o fim: a cabeça fica rente à madeira (só aparece a cor dele)
				var pdir := ((sg2[1] as Vector3) - (sg2[0] as Vector3)).normalized()
				root.add_child(Furo.pin_node((sg2[0] as Vector3) - pdir * 0.012, (sg2[1] as Vector3) - pdir * 0.008))
			elif _joint_open(mi, ji) and int(p.pinos[ji]) == 0:
				# onde tem que furar: um pontinho amarelo em cima
				var mk := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.02
				sm.height = 0.04
				mk.mesh = sm
				mk.material_override = _mark_mat
				mk.position = sg2[1]
				root.add_child(mk)
		if bool(t.get("filtro", false)):
			_draw_filtro(mi, root, nd)
			_nodes[mi] = nd
			continue
		if t.has("forno"):
			_draw_forno(mi, root, nd)
			_nodes[mi] = nd
			continue
		if bool(t.get("torno", false)):
			if pronta(mi):
				nd["biela"] = _stick(Vector3(-0.2, 0.06, 0.0), Vector3(0.2, 0.06, 0.0), 0.018)
				root.add_child(nd.biela)
			_nodes[mi] = nd
			torno_girar(mi, float(p.get("_ang", 0.0)), 0.0)
			continue
		if bool(t.get("mesa", false)):
			if p.has("argila"):
				_draw_argila(p, root)
			_nodes[mi] = nd
			continue
		if t.has("laminas"):
			# lâminas de faca em pé na bancada (as que já estão; as outras em azul)
			var nl := lamina_count(mi)
			for li in (t.laminas as Array).size():
				var lm := MeshInstance3D.new()
				if li < nl:
					lm.mesh = _faca_blade_mesh()
					lm.material_override = _lascar_mat()
				else:
					var gb2 := BoxMesh.new()
					gb2.size = Vector3(0.16, 0.06, 0.01)
					lm.mesh = gb2
					lm.material_override = _ghost_mat
				lm.position = t.laminas[li]
				root.add_child(lm)
			_nodes[mi] = nd
			continue
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
		# pronta: o mecanismo de madeira (biela do pedal até a lâmina, haste da lâmina até
		# a ponta da vara de mola) — o pedal e a vara se mexem com a lâmina
		if pronta(mi) and str(p.tipo) == "serra_pedal":
			var biela := _stick(Vector3(0.0, 0.23, 0.0), Vector3(0.0, 0.77, 0.0), 0.025)
			root.add_child(biela)
			nd["biela"] = biela
			var haste := _stick(Vector3(0.0, 1.87, 0.0), Vector3(0.0, 2.61, 0.0), 0.022)
			root.add_child(haste)
			nd["haste"] = haste
			# a lâmina presa num caixilho de ripas (as duas pontas)
			if nd.has("lamina"):
				for yy in [-0.57, 0.57]:
					(nd.lamina as Node3D).add_child(_stick(Vector3(-0.08, yy, 0.0), Vector3(0.1, yy, 0.0), 0.02))
		# as peças cortadas paradas na mesa de saída
		var sa: Array = p.get("saida", [])
		for k in sa.size():
			var sn: Node3D = _arv.free_log_node(sa[k])
			root.add_child(sn)
			var Ls: float = _arv.free_log_length(sa[k])
			var cps := cut_plan(sa[k])
			sn.position = Vector3(-(Ls * 0.5 + 0.12), 1.09 - float(cps.ymn) * float(cps.r), 0.13 if k == 0 else -0.08)
		# a tora na mesa
		if not (p.tora as Dictionary).is_empty():
			var tn: Node3D = _arv.free_log_node(p.tora)
			root.add_child(tn)
			tn.basis = Basis(Vector3.RIGHT, -float(p.get("giro", 0.0)))
			tn.position = _log_pos(mi)
			nd["tora"] = tn
		_nodes[mi] = nd


## Uma vareta/haste de madeira (galho fino com casca) de a até b.
func _stick(a: Vector3, b: Vector3, r: float) -> Node3D:
	var n: Node3D = _arv.free_log_node(slot_log(["tora", a.distance_to(b), Vector3.ZERO, "x", r]))
	var x := (b - a).normalized()
	var up := Vector3.UP if absf(x.y) < 0.9 else Vector3.RIGHT
	var z := x.cross(up).normalized()
	var y := z.cross(x)
	n.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	return n


## O mecanismo da serra no lugar da lâmina (dy: quanto ela está abaixo/acima do meio):
## o pedal gira na dobradiça, a biela e a haste sobem e descem junto, a vara de mola
## dobra na ponta.
func _animate(mi: int, dy: float) -> void:
	var nd: Dictionary = _nodes.get(mi, {})
	if nd.is_empty():
		return
	var t: Dictionary = TIPOS[plantas[mi].tipo]
	if nd.has("lamina") and is_instance_valid(nd.lamina):
		(nd.lamina as Node3D).position = (t.lamina as Vector3) + Vector3(0, dy, 0)
	for k in ["biela", "haste"]:
		if nd.has(k) and is_instance_valid(nd[k]):
			if not nd.has(k + "0"):
				nd[k + "0"] = (nd[k] as Node3D).position
			(nd[k] as Node3D).position = (nd[k + "0"] as Vector3) + Vector3(0, dy, 0)
	if nd.has("p_16") and is_instance_valid(nd.p_16):
		var hinge := Vector3(0.0, 0.19, 0.6)
		var th := asin(clampf(dy / 0.6, -0.9, 0.9))
		(nd.p_16 as Node3D).transform = Transform3D(Basis(Vector3.RIGHT, th), hinge) * Transform3D(Basis(), -hinge) * (nd.t_16 as Transform3D)
	if nd.has("p_5") and is_instance_valid(nd.p_5):
		var butt := Vector3(-2.0, 2.66, 0.0)
		var ph := asin(clampf(dy / 2.0, -0.9, 0.9))
		(nd.p_5 as Node3D).transform = Transform3D(Basis(Vector3.BACK, ph), butt) * Transform3D(Basis(), -butt) * (nd.t_5 as Transform3D)


# ---------- peneira de água ----------

func filtro_of(mi: int) -> Dictionary:
	var p: Dictionary = plantas[mi]
	if not p.has("filtro"):
		p["filtro"] = {"pedra": 0, "carvao": 0, "areia": 0.0, "tela": false, "pote": "", "cima": 0.0, "pote_l": 0.0, "t0": 0}
	return p.filtro


## O que falta pôr (na ordem): pedra, carvao, areia, tela; "" se está tudo.
func filtro_falta(mi: int) -> String:
	var f := filtro_of(mi)
	if int(f.pedra) < FILTRO_PEDRAS:
		return "pedra"
	if int(f.carvao) < FILTRO_CARVAO:
		return "carvao"
	if float(f.areia) < 0.6:
		return "areia"
	if not bool(f.tela):
		return "tela"
	return ""


func filtro_por(mi: int, what: String, n := 1.0) -> void:
	var f := filtro_of(mi)
	match what:
		"pedra": f.pedra = mini(FILTRO_PEDRAS, int(f.pedra) + int(n))
		"carvao": f.carvao = mini(FILTRO_CARVAO, int(f.carvao) + int(n))
		"areia": f.areia = minf(1.2, float(f.areia) + n)
		"tela": f.tela = true
	_rebuild()


## A água agora: [em cima, na vasilha]. Conta pelo relógio do jogo (o mesmo em todos
## os jogadores) desde a última mudança, sem precisar mandar nada enquanto pinga.
func filtro_agora(mi: int) -> Array:
	var f := filtro_of(mi)
	var cap: float = POTE_L.get(str(f.pote), 0.0)
	var dt := maxf(0.0, (_jogo.sim.real_s(float(_jogo.sim.steps)) - _jogo.sim.real_s(float(f.get("t0", 0)))) * 6.0)   # em sextos de segundo de verdade
	var mv := 0.0
	if str(f.pote) != "":
		mv = clampf(minf(float(f.cima), FILTRO_VAZAO * dt), 0.0, maxf(0.0, cap - float(f.pote_l)))
	return [float(f.cima) - mv, float(f.pote_l) + mv]


## Fixa a água de agora (antes de jogar mais água ou tirar da vasilha).
func _filtro_fixa(mi: int) -> void:
	var f := filtro_of(mi)
	var ag := filtro_agora(mi)
	f.cima = snappedf(float(ag[0]), 0.001)
	f.pote_l = snappedf(float(ag[1]), 0.001)
	f.t0 = int(_jogo.sim.steps)


## Joga água (litros) em cima da areia (o que não cabe escorre pela beira).
func filtro_agua(mi: int, litros: float) -> float:
	_filtro_fixa(mi)
	var f := filtro_of(mi)
	var cabe := minf(litros, FILTRO_CIMA_MAX - float(f.cima))
	f.cima = float(f.cima) + cabe
	filtro_visual(mi)
	return cabe


## Tira água limpa da vasilha (até litros); devolve quanto tirou.
func filtro_tirar(mi: int, litros: float) -> float:
	_filtro_fixa(mi)
	var f := filtro_of(mi)
	var tira := minf(litros, float(f.pote_l))
	f.pote_l = float(f.pote_l) - tira
	filtro_visual(mi)
	return tira


func filtro_pote(mi: int, id: String) -> void:
	_filtro_fixa(mi)
	filtro_of(mi).pote = id
	_rebuild()


## Só a água (a de cima, o fio pingando e a da vasilha), sem refazer a peneira.
func filtro_visual(mi: int) -> void:
	if not _nodes.has(mi):
		return
	var nd: Dictionary = _nodes[mi]
	var f := filtro_of(mi)
	var ag := filtro_agora(mi)
	var cima := float(ag[0])
	var pl := float(ag[1])
	var topo := _filtro_topo(f)
	if nd.has("agua_cima") and is_instance_valid(nd.agua_cima):
		var h := clampf(cima / FILTRO_CIMA_MAX, 0.0, 1.0) * 0.06
		(nd.agua_cima as Node3D).visible = cima > 0.05
		(nd.agua_cima as Node3D).position.y = topo + 0.004 + h
	var cap: float = POTE_L.get(str(f.pote), 0.0)
	if nd.has("fio") and is_instance_valid(nd.fio):
		(nd.fio as Node3D).visible = cima > 0.05 and str(f.pote) != "" and pl < cap - 0.001
	if nd.has("agua_pote") and is_instance_valid(nd.agua_pote):
		var fr := clampf(pl / maxf(cap, 0.1), 0.0, 1.0)
		(nd.agua_pote as Node3D).visible = fr > 0.01
		var hp: float = nd.get("pote_h", 0.08)
		(nd.agua_pote as Node3D).position.y = 0.012 + hp * 0.85 * fr
		var rp: float = nd.get("pote_r", 0.1)
		(nd.agua_pote as Node3D).scale = Vector3.ONE * lerpf(0.6, 0.95, fr) * rp / 0.1


func _filtro_topo(f: Dictionary) -> float:
	var y := FILTRO_FUNDO + 0.06 * float(f.pedra) / FILTRO_PEDRAS + 0.05 * float(f.carvao) / FILTRO_CARVAO + 0.07 * minf(1.0, float(f.areia))
	return y


static var _filtro_mats := {}

static func _fmat(k: String, col: Color, rough := 0.9, alpha := 1.0) -> StandardMaterial3D:
	if not _filtro_mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(col.r, col.g, col.b, alpha)
		m.roughness = rough
		if alpha < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic_specular = 0.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_filtro_mats[k] = m
	return _filtro_mats[k]


## As camadas dentro da caixa (pedrinhas, pedaços de carvão, areia, a tela trançada),
## a água empoçada em cima, o fio pingando e a vasilha de barro embaixo.
func _draw_filtro(mi: int, root: Node3D, nd: Dictionary) -> void:
	var f := filtro_of(mi)
	var rng := RandomNumberGenerator.new()
	rng.seed = mi * 97 + 5
	var hx := 0.205
	var hz := 0.18
	var y := FILTRO_FUNDO
	# pedrinhas: cada pedra posta enche um pedaço do fundo
	var np := int(f.pedra) * 9
	for k in np:
		var sm := SphereMesh.new()
		var r := rng.randf_range(0.018, 0.03)
		sm.radius = r
		sm.height = r * 1.5
		sm.radial_segments = 7
		sm.rings = 4
		var n := MeshInstance3D.new()
		n.mesh = sm
		n.material_override = _fmat("pedra", Color(0.47, 0.45, 0.41))
		n.position = Vector3(rng.randf_range(-hx + r, hx - r), y + r * 0.6 + rng.randf() * 0.02, rng.randf_range(-hz + r, hz - r))
		n.rotation = Vector3(rng.randf() * 3.0, rng.randf() * 3.0, 0)
		root.add_child(n)
	y += 0.06 * float(f.pedra) / FILTRO_PEDRAS
	# carvão: pedaços pretos e quebrados
	for k in int(f.carvao) * 14:
		var bm := BoxMesh.new()
		var a := rng.randf_range(0.015, 0.03)
		bm.size = Vector3(a, a * 0.7, a * rng.randf_range(0.7, 1.4))
		var n2 := MeshInstance3D.new()
		n2.mesh = bm
		n2.material_override = _fmat("carvao", Color(0.06, 0.06, 0.065), 0.7)
		n2.position = Vector3(rng.randf_range(-hx + a, hx - a), y + rng.randf() * 0.04, rng.randf_range(-hz + a, hz - a))
		n2.rotation = Vector3(rng.randf() * 3.0, rng.randf() * 3.0, rng.randf() * 3.0)
		root.add_child(n2)
	y += 0.05 * float(f.carvao) / FILTRO_CARVAO
	# areia: uma camada lisa (molhada fica mais escura)
	if float(f.areia) > 0.0:
		var bx := BoxMesh.new()
		var ah := 0.07 * minf(1.0, float(f.areia))
		bx.size = Vector3(hx * 2.0, ah, hz * 2.0)
		var n3 := MeshInstance3D.new()
		n3.mesh = bx
		n3.material_override = _fmat("areia", Color(0.5, 0.42, 0.3), 1.0)
		n3.position = Vector3(0, y + ah * 0.5, 0)
		root.add_child(n3)
		y += ah
	# a tela de fibra: fios cruzados por cima de tudo
	if bool(f.tela):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var ty := y + 0.006
		for k in 15:
			var o := -hx + (2.0 * hx) * k / 14.0
			for q in [[Vector3(o - 0.0045, ty, -hz), Vector3(o + 0.0045, ty, -hz), Vector3(o + 0.0045, ty, hz), Vector3(o - 0.0045, ty, hz)]]:
				for idx in [0, 1, 2, 0, 2, 3]:
					st.add_vertex(q[idx])
		for k in 13:
			var o2 := -hz + (2.0 * hz) * k / 12.0
			var q2 := [Vector3(-hx, ty + 0.002, o2 - 0.0045), Vector3(hx, ty + 0.002, o2 - 0.0045), Vector3(hx, ty + 0.002, o2 + 0.0045), Vector3(-hx, ty + 0.002, o2 + 0.0045)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q2[idx])
		st.generate_normals()
		var tn := MeshInstance3D.new()
		tn.mesh = st.commit()
		tn.material_override = _fmat("tela", Color(0.9, 0.8, 0.55), 0.8)
		root.add_child(tn)
	# a água empoçada em cima (some aos poucos, passando)
	var pm := PlaneMesh.new()
	pm.size = Vector2(hx * 2.0, hz * 2.0)
	var wa := MeshInstance3D.new()
	wa.mesh = pm
	wa.material_override = _fmat("agua_cima", Color(0.3, 0.32, 0.24), 0.12, 0.8)
	root.add_child(wa)
	nd["agua_cima"] = wa
	# o fio de água limpa pingando pela fresta do fundo até a vasilha
	var cm := CylinderMesh.new()
	cm.top_radius = 0.004
	cm.bottom_radius = 0.003
	cm.height = FILTRO_FUNDO - 0.06
	var fio := MeshInstance3D.new()
	fio.mesh = cm
	fio.material_override = _fmat("fio", Color(0.75, 0.88, 1.0), 0.05, 0.6)
	fio.position = Vector3(0, (FILTRO_FUNDO - 0.06) * 0.5 + 0.06, 0)
	root.add_child(fio)
	nd["fio"] = fio
	# a vasilha de barro embaixo (no chão) e a água limpa dentro dela
	if str(f.pote) != "":
		var Olaria = load("res://scripts/world/olaria.gd")
		var pot := MeshInstance3D.new()
		pot.mesh = Olaria.malha(str(f.pote), [1.0, 1.0, 1.0, 1.0])
		pot.material_override = _fmat("pote", Color(0.55, 0.3, 0.18), 0.85)
		root.add_child(pot)
		var pf: Array = Olaria.perfil_final(str(f.pote))
		nd["pote_h"] = (pf[-1] as Vector2).y
		nd["pote_r"] = (pf[-1] as Vector2).x
		var dm := CylinderMesh.new()
		dm.top_radius = 0.1
		dm.bottom_radius = 0.1
		dm.height = 0.004
		var ap := MeshInstance3D.new()
		ap.mesh = dm
		ap.material_override = _fmat("agua_pote", Color(0.55, 0.72, 0.85), 0.05, 0.75)
		root.add_child(ap)
		nd["agua_pote"] = ap
	_nodes[mi] = nd
	filtro_visual(mi)


# ---------- forno de carvão ----------
# Estado de uso (p.fz): {lenha: [achas], aceso: bool, porta: "aberta"/"fechada",
# t0 (relógio de verdade ao fechar), carvao: n}

func forno_st(mi: int) -> Dictionary:
	var p: Dictionary = plantas[mi]
	if not p.has("fz"):
		p["fz"] = {"lenha": [], "aceso": false, "porta": "aberta", "t0": -1.0, "carvao": 0}
	return p.fz


func _agora_real() -> float:
	return float(_jogo.sim.real_s(float(_jogo.sim.steps)))


## Fração do tempo de carvão que ainda falta (1 = acabou de fechar, 0 = pronto); -1 se
## não está cozinhando.
func forno_falta(mi: int) -> float:
	var f := forno_st(mi)
	if str(f.porta) != "fechada" or not bool(f.aceso) or float(f.t0) < 0.0:
		return -1.0
	return clampf(1.0 - (_agora_real() - float(f.t0)) / FORNO_S, 0.0, 1.0)


## Cozinhando agora (o suspiro solta fumaça)?
func forno_fumando(mi: int) -> bool:
	var fl := forno_falta(mi)
	if fl > 0.0:
		return true
	var f := forno_st(mi)
	return bool(f.aceso) and str(f.porta) == "aberta" and float(f.t0) < 0.0


## Construindo: pedra ou barro postos.
func forno_por(mi: int, what: String) -> void:
	var p: Dictionary = plantas[mi]
	var k := "ped" if what == "pedra" else "bar"
	var fz: Dictionary = TIPOS[p.tipo].forno
	p[k] = mini(int(p.get(k, 0)) + 1, int(fz.pedras if what == "pedra" else fz.barro))
	if what == "barro":
		p["bar_dia"] = int(_jogo.sim.elapsed_days())
	_rebuild()


func forno_lenha(mi: int, acha: Dictionary) -> void:
	(forno_st(mi).lenha as Array).append(acha)
	_rebuild()


func forno_acender(mi: int) -> void:
	forno_st(mi).aceso = true
	_rebuild()


func forno_porta(mi: int, fechar: bool) -> void:
	var f := forno_st(mi)
	if fechar:
		f.porta = "fechada"
		if bool(f.aceso) and float(f.t0) < 0.0:
			f.t0 = _agora_real()
	else:
		f.porta = "aberta"
		if bool(f.aceso) and float(f.t0) >= 0.0 and forno_falta(mi) <= 0.0:
			# pronto: a lenha virou carvão (uma lenha, um carvão)
			f.carvao = int(f.carvao) + (f.lenha as Array).size()
			f.lenha = []
			f.aceso = false
			f.t0 = -1.0
	_rebuild()


func forno_tirar(mi: int) -> int:
	var f := forno_st(mi)
	var n := int(f.carvao)
	f.carvao = 0
	_rebuild()
	return n


## Onde fica a boca (no mundo), para o arco de fogo.
func forno_boca(mi: int) -> Vector3:
	return xform(mi) * Vector3(FORNO_FRENTE + 0.25, 0.0, 0.0)


static var _fz_mats := {}

static func _fzm(k: String) -> StandardMaterial3D:
	if _fz_mats.has(k):
		return _fz_mats[k]
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match k:
		"pedra":
			m.albedo_color = Color(0.3, 0.29, 0.26)
			m.roughness = 1.0
			m.metallic_specular = 0.05
		"escuro":
			m.albedo_color = Color(0.04, 0.03, 0.025)
			m.roughness = 1.0
		"carvao":
			m.albedo_color = Color(0.06, 0.06, 0.065)
			m.roughness = 0.7
		"brasa":
			m.albedo_color = Color(0.25, 0.05, 0.02)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.35, 0.05)
			m.emission_energy_multiplier = 2.5
		"fogo":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.vertex_color_use_as_albedo = true
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			m.albedo_texture = load("res://scripts/world/fogueiras.gd").soft_tex()
		"fumaca":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			m.vertex_color_use_as_albedo = true
			m.albedo_texture = load("res://scripts/world/fogueiras.gd").soft_tex()
			m.emission_enabled = true
			m.emission = Color(0.25, 0.25, 0.24)
			m.disable_fog = true
	_fz_mats[k] = m
	return m


## Ponto na casca do domo (th: em volta, ph: de 0 no chão a PI/2 no topo); a frente
## (x > FORNO_FRENTE) é cortada reta.
static func _domo(th: float, ph: float, inset := 0.0) -> Vector3:
	var R := FORNO_R - inset
	var p := Vector3(cos(ph) * cos(th) * R - 0.1, sin(ph) * (FORNO_H - inset), cos(ph) * sin(th) * R)
	if p.x > FORNO_FRENTE:
		p.x = FORNO_FRENTE
	return p


static func _na_boca(p: Vector3) -> bool:
	return p.x >= FORNO_FRENTE - 0.001 and absf(p.z) < 0.27 and p.y < 0.56


## O forno: as pedras assentadas (até onde já foram postas), o barro cobrindo por cima
## (até onde já foi rebocado), a boca escura, o suspiro, a lenha dentro, o fogo, o
## carvão e a fumaça saindo do suspiro.
func _draw_forno(mi: int, root: Node3D, nd: Dictionary) -> void:
	var p: Dictionary = plantas[mi]
	var fz: Dictionary = TIPOS[p.tipo].forno
	var fped := float(p.get("ped", 0)) / float(fz.pedras)
	var fbar := float(p.get("bar", 0)) / float(fz.barro)
	var rng := RandomNumberGenerator.new()
	rng.seed = mi * 71 + 3
	# as pedras: em fileiras de baixo para cima (até a altura do que já foi posto)
	if fbar < 1.0:
		var fileiras := 7
		for fi in fileiras:
			var ph := (float(fi) + 0.5) / fileiras * PI * 0.47
			if float(fi) / fileiras >= fped:
				break
			var n := int(18.0 * cos(ph)) + 3
			for k in n:
				var th := TAU * (float(k) + 0.5 * (fi % 2)) / n
				var pt := _domo(th, ph)
				if _na_boca(pt) or (pt.x >= FORNO_FRENTE - 0.001 and fi > 4):
					continue
				var sm := SphereMesh.new()
				var r := rng.randf_range(0.07, 0.1)
				sm.radius = r
				sm.height = r * 1.3
				sm.radial_segments = 7
				sm.rings = 4
				var sn := MeshInstance3D.new()
				sn.mesh = sm
				sn.material_override = _fzm("pedra")
				sn.position = pt
				sn.rotation = Vector3(rng.randf(), rng.randf() * 3.0, 0)
				root.add_child(sn)
	# o barro: a casca do domo até a altura rebocada
	if fbar > 0.0:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var NT := 36
		var NP := 12
		var lim := fbar * PI * 0.5 + 0.001
		var nz := FastNoiseLite.new()
		nz.seed = mi + 5
		nz.frequency = 3.0
		for i in NP:
			var ph0 := float(i) / NP * PI * 0.5
			var ph1 := float(i + 1) / NP * PI * 0.5
			if ph0 > lim:
				break
			for k in NT:
				var th0 := TAU * k / NT
				var th1 := TAU * (k + 1) / NT
				var q := [_domo(th0, ph0), _domo(th1, ph0), _domo(th1, minf(ph1, lim)), _domo(th0, minf(ph1, lim))]
				if _na_boca(q[0]) and _na_boca(q[1]) and _na_boca(q[2]) and _na_boca(q[3]):
					continue
				var tq := [th0, th1, th1, th0]
				var pq := [ph0, ph0, minf(ph1, lim), minf(ph1, lim)]
				for idx in [0, 2, 1, 0, 3, 2]:
					var v: Vector3 = q[idx]
					var bump := 0.02 + nz.get_noise_3d(v.x * 3.0, v.y * 3.0, v.z * 3.0) * 0.015
					var nrm := Vector3(v.x + 0.1, v.y * 0.6, v.z).normalized()
					if v.x >= FORNO_FRENTE - 0.001:
						nrm = Vector3.RIGHT
					st.set_normal(nrm)                    # liso (sem os quadradinhos)
					st.set_uv(Vector2(float(tq[idx]) * 0.9, float(pq[idx]) * 1.8))
					st.add_vertex(v + nrm * bump)
		st.generate_tangents()
		var mi2 := MeshInstance3D.new()
		mi2.mesh = st.commit()
		var age := int(_jogo.sim.elapsed_days()) - int(p.get("bar_dia", -99))
		var stage := 1 if age < 3 else (2 if age < 6 else 3)       # (grosso: já começa meio seco)
		mi2.material_override = load("res://scripts/world/construcao.gd")._mud_material(stage)
		root.add_child(mi2)
	if fped <= 0.0:
		return
	# por dentro, escuro (a boca)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.5, 0.5)
	var boca := MeshInstance3D.new()
	boca.mesh = bm
	boca.material_override = _fzm("escuro")
	boca.position = Vector3(FORNO_FRENTE - 0.35, 0.27, 0.0)
	root.add_child(boca)
	var chao := BoxMesh.new()
	chao.size = Vector3(1.2, 0.01, 1.2)
	var cn := MeshInstance3D.new()
	cn.mesh = chao
	cn.material_override = _fzm("escuro")
	cn.position = Vector3(-0.1, 0.005, 0.0)
	root.add_child(cn)
	# o suspiro: um cano curto de barro em cima, atrás
	if fbar >= 1.0:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.08
		cm.height = 0.2
		var sus := MeshInstance3D.new()
		sus.mesh = cm
		sus.material_override = load("res://scripts/world/construcao.gd")._mud_material(2)
		var sp := _domo(PI, PI * 0.36)
		sus.position = sp + Vector3(0, 0.08, 0)
		root.add_child(sus)
		var furo := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.04
		fm.bottom_radius = 0.04
		fm.height = 0.005
		furo.mesh = fm
		furo.material_override = _fzm("escuro")
		furo.position = sp + Vector3(0, 0.181, 0)
		root.add_child(furo)
		nd["suspiro"] = sp + Vector3(0, 0.2, 0)
	if not pronta(mi):
		return
	var f := forno_st(mi)
	# a lenha dentro (as mesmas achas), deitadas em fileiras
	var ach: Array = f.lenha
	for k in ach.size():
		var ln: Node3D = _arv.free_log_node(ach[k])
		var fila := k % 4
		var cam := k / 4
		ln.transform = Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, float(k) * 1.1),
			Vector3(0.15 - cam * 0.27, 0.07 + cam * 0.02 + (fila % 2) * 0.03, -0.24 + fila * 0.16))
		root.add_child(ln)
	# o carvão pronto
	for k in mini(int(f.carvao), 24):
		var cb := BoxMesh.new()
		var a := rng.randf_range(0.04, 0.07)
		cb.size = Vector3(a * 1.5, a * 0.8, a)
		var cv := MeshInstance3D.new()
		cv.mesh = cb
		cv.material_override = _fzm("carvao")
		cv.position = Vector3(rng.randf_range(-0.55, 0.35), 0.03 + rng.randf() * 0.05, rng.randf_range(-0.35, 0.35))
		cv.rotation = Vector3(rng.randf(), rng.randf() * 3.0, rng.randf())
		root.add_child(cv)
	# o fogo lá dentro (aceso com a porta aberta) e o brilho das brasas
	var chama := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.2, 0.28)
	chama.mesh = qm
	chama.material_override = _fzm("fogo")
	chama.amount = 34
	chama.lifetime = 0.7
	chama.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	chama.emission_box_extents = Vector3(0.35, 0.05, 0.3)
	chama.direction = Vector3.UP
	chama.spread = 15.0
	chama.gravity = Vector3(0, 1.0, 0)
	chama.initial_velocity_min = 0.2
	chama.initial_velocity_max = 0.5
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.85, 0.35, 0.95), Color(1.0, 0.45, 0.08, 0.8), Color(0.6, 0.1, 0.02, 0.0)])
	chama.color_ramp = grad
	chama.position = Vector3(-0.05, 0.12, 0)
	chama.emitting = false
	root.add_child(chama)
	nd["chama"] = chama
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.55, 0.2)
	luz.light_energy = 1.6
	luz.omni_range = 4.0
	luz.position = Vector3(FORNO_FRENTE + 0.3, 0.35, 0)
	luz.visible = false
	root.add_child(luz)
	nd["luz"] = luz
	# a fumaça do suspiro: grossa, subindo alto (dá para ver de longe)
	var fum := CPUParticles3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.6, 0.6)
	fum.mesh = q2
	fum.material_override = _fzm("fumaca")
	fum.amount = 60
	fum.lifetime = 12.0
	fum.direction = Vector3.UP
	fum.spread = 12.0
	fum.gravity = Vector3(0.25, 0.35, 0.05)
	fum.initial_velocity_min = 0.7
	fum.initial_velocity_max = 1.1
	fum.scale_amount_min = 1.5
	fum.scale_amount_max = 6.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(1, 1.0))
	fum.scale_amount_curve = sc
	var g2 := Gradient.new()
	g2.offsets = PackedFloat32Array([0.0, 0.1, 0.6, 1.0])
	g2.colors = PackedColorArray([Color(0.7, 0.69, 0.67, 0.0), Color(0.66, 0.65, 0.63, 0.75), Color(0.78, 0.78, 0.77, 0.45), Color(0.85, 0.85, 0.85, 0.0)])
	fum.color_ramp = g2
	fum.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 40, 16))
	fum.position = nd.get("suspiro", Vector3(-0.8, 0.9, 0))
	fum.emitting = false
	root.add_child(fum)
	nd["fumaca"] = fum
	# a porta: as duas tábuas giram na dobradiça (z = -0.27)
	forno_visual(mi, nd)


## O que muda com o tempo (a porta, o fogo, a fumaça).
func forno_visual(mi: int, nd := {}) -> void:
	if nd.is_empty():
		if not _nodes.has(mi):
			return
		nd = _nodes[mi]
	if not pronta(mi):
		return
	var f := forno_st(mi)
	var aberta := str(f.porta) == "aberta"
	var hinge := Vector3(0.6, 0.0, -0.27)
	var ang := 1.75 if aberta else 0.0
	for si in [0, 1]:
		if nd.has("p_%d" % si) and is_instance_valid(nd["p_%d" % si]):
			(nd["p_%d" % si] as Node3D).transform = Transform3D(Basis(Vector3.UP, -ang), hinge) * Transform3D(Basis(), -hinge) * (nd["t_%d" % si] as Transform3D)
	var fum := forno_fumando(mi)
	if nd.has("fumaca") and is_instance_valid(nd.fumaca):
		(nd.fumaca as CPUParticles3D).emitting = fum
	var fogo_aberto := bool(f.aceso) and aberta and float(f.t0) < 0.0
	if nd.has("chama") and is_instance_valid(nd.chama):
		(nd.chama as CPUParticles3D).emitting = fogo_aberto
	if nd.has("luz") and is_instance_valid(nd.luz):
		(nd.luz as OmniLight3D).visible = fogo_aberto


# ---------- torno de oleiro ----------

## Gira o eixo, a mesa de cima e o volante (ang, em radianos); o pedal desce (0 a 1) e
## a biela vai do pedal até o pino do volante.
func torno_girar(mi: int, ang: float, pedal: float) -> void:
	plantas[mi]["_ang"] = ang
	if not _nodes.has(mi):
		return
	var nd: Dictionary = _nodes[mi]
	for si in [7, 8, 9]:
		if nd.has("p_%d" % si) and is_instance_valid(nd["p_%d" % si]):
			(nd["p_%d" % si] as Node3D).transform = Transform3D(Basis(Vector3.UP, ang), Vector3.ZERO) * (nd["t_%d" % si] as Transform3D)
	var hinge := Vector3(-0.75, 0.04, 0.0)
	var th := -0.12 * pedal
	if nd.has("p_10") and is_instance_valid(nd.p_10):
		(nd.p_10 as Node3D).transform = Transform3D(Basis(Vector3.BACK, th), hinge) * Transform3D(Basis(), -hinge) * (nd.t_10 as Transform3D)
	if nd.has("biela") and is_instance_valid(nd.biela):
		var tip := hinge + Basis(Vector3.BACK, th) * Vector3(0.58, 0.03, 0.0)
		var crank := Vector3(cos(ang) * 0.17, 0.2, sin(ang) * 0.17)
		# a mesma vareta (feita com 0,4 m), esticada até o pino do volante
		var x := crank - tip
		var dl := x.length()
		x = x / maxf(dl, 0.001)
		var z := x.cross(Vector3.UP).normalized()
		var y := z.cross(x)
		(nd.biela as Node3D).transform = Transform3D(Basis(x * (dl / 0.4), y, z), (tip + crank) * 0.5)


# ---------- mesa de argila ----------

## Despeja a argila do balde (f = quanto de balde) no tampo, com a sujeira no meio.
func mesa_despejar(mi: int, f: float) -> void:
	var p: Dictionary = plantas[mi]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var a: Dictionary = p.get("argila", {"f": 0.0, "suj": [], "seed": rng.randi() % 100000})
	a.f = minf(1.2, float(a.f) + f)
	var n := maxi(2, int(round(MESA_SUJEIRA * f)))
	var r := _mesa_r(float(a.f))
	var usados := []
	for k in n:
		# espalhadas (uma longe da outra, para dar para tocar em cada uma)
		var ang := 0.0
		var d := 0.0
		for _t in 30:
			ang = rng.randf() * TAU
			d = sqrt(rng.randf()) * r * 0.85
			var q := Vector2(cos(ang), sin(ang)) * d
			var ok := true
			for u in usados:
				if (u as Vector2).distance_to(q) < 0.055:
					ok = false
					break
			if ok:
				break
		usados.append(Vector2(cos(ang), sin(ang)) * d)
		var kind: String = ["pedra", "pedra", "raiz", "folha", "graveto"][rng.randi() % 5]
		(a.suj as Array).append([snappedf(0.06 + cos(ang) * d, 0.001), snappedf(sin(ang) * d, 0.001), kind, rng.randi() % 10000, snappedf(rng.randf() * TAU, 0.01)])
	p["argila"] = a
	_rebuild()


func _mesa_r(f: float) -> float:
	return 0.12 + 0.12 * sqrt(clampf(f, 0.0, 1.2))


## Altura do monte de argila no ponto (x, z) do tampo (espaço da máquina).
func mesa_h(p: Dictionary, x: float, z: float) -> float:
	var a: Dictionary = p.get("argila", {})
	if a.is_empty():
		return 0.0
	var f := float(a.f)
	var r := _mesa_r(f)
	var u := Vector2(x - 0.06, z).length() / r
	if u >= 1.0:
		return 0.0
	var nz := sin(x * 41.0 + float(a.seed)) * cos(z * 37.0 - float(a.seed) * 0.3) * 0.006
	return (0.035 + 0.05 * f) * (1.0 - u * u) * (1.0 - 0.25 * u) + nz * (1.0 - u)


## Onde fica cada sujeira (no mundo), para os losangos.
func mesa_sujeira(mi: int) -> Array:
	var p: Dictionary = plantas[mi]
	var out := []
	var xf := xform(mi)
	for e in (p.get("argila", {}) as Dictionary).get("suj", []):
		out.append(xf * Vector3(float(e[0]), MESA_TOPO + mesa_h(p, float(e[0]), float(e[1])) + 0.012, float(e[1])))
	return out


## Tira a sujeira k. Devolve o tipo dela ("" se não tinha).
func mesa_tirar(mi: int, k: int) -> String:
	var a: Dictionary = plantas[mi].get("argila", {})
	var suj: Array = a.get("suj", [])
	if k < 0 or k >= suj.size():
		return ""
	var kind := str(suj[k][2])
	suj.remove_at(k)
	_rebuild()
	return kind


## Tudo limpo: tira a argila da mesa. Devolve quantas bolas de argila limpa.
func mesa_recolher(mi: int) -> int:
	var a: Dictionary = plantas[mi].get("argila", {})
	if a.is_empty() or not (a.get("suj", []) as Array).is_empty():
		return 0
	plantas[mi].erase("argila")
	_rebuild()
	return maxi(1, int(round(MESA_BOLAS * float(a.f))))


static var _clay_mat: StandardMaterial3D
static var _suj_mats := {}


## A argila no tampo: um monte achatado e irregular (vermelho-alaranjado, molhado) com a
## sujeira aparecendo: pedrinhas, raízes, gravetos e pedaços de folha seca.
func _draw_argila(p: Dictionary, root: Node3D) -> void:
	var a: Dictionary = p.argila
	var r := _mesa_r(float(a.f))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 10
	var segs := 32
	var pts := []
	var nz := FastNoiseLite.new()
	nz.seed = int(a.seed)
	nz.frequency = 9.0
	for ri in rings + 1:
		var row := []
		for k in segs:
			var ang := TAU * k / segs
			var rr := r * float(ri) / rings * (1.0 + 0.12 * nz.get_noise_2d(cos(ang), sin(ang)))
			var x := 0.06 + cos(ang) * rr
			var z := sin(ang) * rr
			row.append(Vector3(x, MESA_TOPO + mesa_h(p, x, z) + 0.002, z))
		pts.append(row)
	for ri in rings:
		for k in segs:
			var k2 := (k + 1) % segs
			var q := [pts[ri][k], pts[ri][k2], pts[ri + 1][k2], pts[ri + 1][k]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = q[idx]
				var tone := nz.get_noise_2d(v.x * 6.0, v.z * 6.0)
				st.set_color(Color(1, 1, 1).darkened(maxf(-tone, 0.0) * 0.25).lightened(maxf(tone, 0.0) * 0.1))
				st.set_uv(Vector2(v.x, v.z) * 4.0)
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	if _clay_mat == null:
		_clay_mat = StandardMaterial3D.new()
		_clay_mat.vertex_color_use_as_albedo = true
		_clay_mat.vertex_color_is_srgb = true
		_clay_mat.albedo_color = Color(0.3, 0.17, 0.11)          # argila molhada da lagoa (barrenta)
		_clay_mat.roughness = 0.62
		_clay_mat.metallic_specular = 0.14
		var nt := NoiseTexture2D.new()
		var tn := FastNoiseLite.new()
		tn.frequency = 0.04
		nt.noise = tn
		nt.width = 128
		nt.height = 128
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 2.0
		_clay_mat.normal_enabled = true
		_clay_mat.normal_texture = nt
		_clay_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = _clay_mat
	root.add_child(mi)
	for e in a.get("suj", []):
		root.add_child(_sujeira_node(p, e))


static func _suj_mat(kind: String) -> StandardMaterial3D:
	if not _suj_mats.has(kind):
		var m := StandardMaterial3D.new()
		m.roughness = 0.9
		match kind:
			"pedra": m.albedo_color = Color(0.3, 0.29, 0.26)
			"raiz": m.albedo_color = Color(0.36, 0.24, 0.13)
			"graveto": m.albedo_color = Color(0.3, 0.22, 0.14)
			_: m.albedo_color = Color(0.3, 0.2, 0.09)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_suj_mats[kind] = m
	return _suj_mats[kind]


## Uma sujeira na argila (meio enterrada): [x, z, tipo, semente, giro].
func _sujeira_node(p: Dictionary, e: Array) -> Node3D:
	var x := float(e[0])
	var z := float(e[1])
	var kind := str(e[2])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e[3])
	var y := MESA_TOPO + mesa_h(p, x, z)
	var n := MeshInstance3D.new()
	n.material_override = _suj_mat(kind)
	match kind:
		"pedra":
			var sm := SphereMesh.new()
			var s := rng.randf_range(0.011, 0.02)
			sm.radius = s
			sm.height = s * 1.4
			sm.radial_segments = 7
			sm.rings = 4
			n.mesh = sm
			n.position = Vector3(x, y + s * 0.15, z)
			n.scale = Vector3(1.0, 0.8, rng.randf_range(0.8, 1.3))
		"raiz", "graveto":
			# um fio torto meio enterrado
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var L := rng.randf_range(0.06, 0.12) if kind == "raiz" else rng.randf_range(0.07, 0.11)
			var w := 0.0025 if kind == "raiz" else 0.004
			var ang := float(e[4])
			var prev := Vector3.INF
			for i in 7:
				var t := float(i) / 6.0
				ang += rng.randf_range(-0.4, 0.4) if kind == "raiz" else 0.0
				var px := x + cos(ang) * L * (t - 0.5)
				var pz := z + sin(ang) * L * (t - 0.5)
				var pt := Vector3(px, MESA_TOPO + mesa_h(p, px, pz) + w * 0.6, pz)
				if prev != Vector3.INF:
					var d := (pt - prev).normalized()
					var sd := d.cross(Vector3.UP).normalized() * w
					var up := Vector3.UP * w
					for v in [prev - sd, pt - sd, pt + sd, prev - sd, pt + sd, prev + sd, prev + up, pt + up, pt - sd, prev + up, pt - sd, prev - sd]:
						st.add_vertex(v)
				prev = pt
			st.generate_normals()
			n.mesh = st.commit()
		_:
			# pedaço de folha seca, torto
			var st2 := SurfaceTool.new()
			st2.begin(Mesh.PRIMITIVE_TRIANGLES)
			var s2 := rng.randf_range(0.018, 0.03)
			var c := Vector3(x, y + 0.002, z)
			var rot := Basis(Vector3.UP, float(e[4]))
			var vs := []
			for i in 6:
				var aa := TAU * i / 6.0
				vs.append(c + rot * Vector3(cos(aa) * s2 * 1.5, rng.randf_range(0.0, 0.006), sin(aa) * s2 * rng.randf_range(0.6, 1.0)))
			for i in 6:
				for v in [c + Vector3.UP * 0.004, vs[i], vs[(i + 1) % 6]]:
					st2.add_vertex(v)
			st2.generate_normals()
			n.mesh = st2.commit()
	return n


static var _fbm: ArrayMesh


## A lâmina de faca lascada deitada de lado (comprido em x, fio para cima), com a
## espiga enfiada na tábua.
static func _faca_blade_mesh() -> ArrayMesh:
	if _fbm == null:
		var Lascar = load("res://scripts/world/lascar.gd")
		var bl: ArrayMesh = Lascar.mesh(Lascar.target("lamina_faca"), Lascar.rock(31), 31)
		var bs := SurfaceTool.new()
		bs.create_from(bl, 0)
		bs.deindex()
		var m := bs.commit()
		var out := SurfaceTool.new()
		out.begin(Mesh.PRIMITIVE_TRIANGLES)
		var k := 0.24
		# pedra: X (comprimento) -> x, Y (grossura) -> z, Z (largura) -> y (o fio para cima)
		out.append_from(m, 0, Transform3D(Basis(Vector3(k, 0, 0), Vector3(0, 0, k * 1.1), Vector3(0, k * 1.15, 0)), Vector3.ZERO))
		out.generate_normals()
		_fbm = out.commit()
	return _fbm


static var _lmat: Material


static func _lascar_mat() -> Material:
	if _lmat == null:
		_lmat = load("res://scripts/world/lascar.gd").material()
	return _lmat


static var _pmat: StandardMaterial3D


static func _pin_mat() -> StandardMaterial3D:
	if _pmat == null:
		_pmat = StandardMaterial3D.new()
		_pmat.albedo_color = Color(0.62, 0.47, 0.3)
		_pmat.roughness = 0.9
	return _pmat


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
	# a caixa de barro saiu do jogo (o barro agora é feito no monte de terra no chão)
	plantas = plantas.filter(func(q): return str(q.get("tipo", "")) != "caixa_barro")
	# mesa de argila das versões antigas (tábuas em cima do pé redondo; travessas de
	# tora): vira a nova (travessas de tábua), montada se estava montada
	for q in plantas:
		if str(q.get("tipo", "")) == "mesa_argila" and int(q.get("versao", 1)) < 3:
			var feita := true
			for bb in q.get("pecas", []):
				if not bool(bb):
					feita = false
			var tm: Dictionary = TIPOS.mesa_argila
			q.pecas = []
			q.sobra = []
			q.pinos = []
			for _i in (tm.pecas as Array).size():
				q.pecas.append(feita)
				q.sobra.append(0.0)
			for _j in (tm.pinos as Array).size():
				q.pinos.append(2 if feita else 0)
			q.erase("madeiras")
			q["versao"] = 3
	for p in plantas:
		if p.has("amarras") and not p.has("pinos"):
			p["pinos"] = p.amarras          # planta de versão antiga: as amarras viram pinos
			p.erase("amarras")
		var tt: Dictionary = TIPOS.get(str(p.tipo), {})
		var st := []
		for v in p.pinos:
			st.append(2 if (v is bool and v) else (0 if v is bool else int(v)))
		while not tt.is_empty() and st.size() < (tt.pinos as Array).size():
			st.append(0)                    # juntas novas (versão nova do projeto)
		p.pinos = st
		if not p.has("sobra"):
			var sb := []
			for _q in p.pecas:
				sb.append(0.0)
			p["sobra"] = sb
	# serra da versão antiga (pedal atrás, cordas): vira a serra nova no mesmo lugar;
	# se já estava pronta, fica pronta
	for p in plantas:
		if str(p.tipo) == "serra_pedal" and int(p.get("versao", 1)) < 2:
			var tt: Dictionary = TIPOS.serra_pedal
			var feita := true
			for b in p.pecas:
				if not bool(b):
					feita = false
			var np := (tt.pecas as Array).size()
			var nj := (tt.pinos as Array).size()
			p.pecas = []
			p.sobra = []
			p.pinos = []
			for _i in np:
				p.pecas.append(feita)
				p.sobra.append(0.0)
			for _j in nj:
				p.pinos.append(2 if feita else 0)
			p.lamina = feita and lamina_count_of(p) > 0
			p.erase("madeiras")
			p["saida"] = []
			p["tora"] = {}
			p["prog"] = 0.0
			p["versao"] = 2
	# o ritmo da lâmina continua (é só desenho)
	for i in mini(old.size(), plantas.size()):
		if (old[i] as Dictionary).has("_ph"):
			plantas[i]["_ph"] = old[i]._ph
	return true
