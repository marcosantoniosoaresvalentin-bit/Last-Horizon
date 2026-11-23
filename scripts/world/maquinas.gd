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
	# Mesa de carne: 4 pés de tora (não precisa fincar), em cima de cada par de pés uma
	# tora deitada atravessada (a travessa) e, de comprido por cima das duas travessas, as
	# tábuas do tampo, largo. É onde a carne vai ser posta e cortada com a faca e o machado.
	"mesa_carne": {
		"nome": "Mesa de Carne",
		"desc": "Mesa de tábuas em cima de duas travessas de tora, nos quatro pés: para pôr a carne e cortar os pedaços com a faca e o machado.",
		"pecas": [
			["tora", 0.8, Vector3(0.8, 0.4, 0.42), "y", 0.07],       # 0 pé
			["tora", 0.8, Vector3(0.8, 0.4, -0.42), "y", 0.07],      # 1 pé
			["tora", 0.8, Vector3(-0.8, 0.4, 0.42), "y", 0.07],      # 2 pé
			["tora", 0.8, Vector3(-0.8, 0.4, -0.42), "y", 0.07],     # 3 pé
			["tora", 1.1, Vector3(0.8, 0.86, 0.0), "z", 0.06],       # 4 travessa em cima dos pés 0 e 1
			["tora", 1.1, Vector3(-0.8, 0.86, 0.0), "z", 0.06],      # 5 travessa em cima dos pés 2 e 3
			["tabua", 1.95, Vector3(0.0, 0.955, -0.375), "x", 0.15], # 6 tábua do tampo
			["tabua", 1.95, Vector3(0.0, 0.955, -0.125), "x", 0.15], # 7 tábua do tampo
			["tabua", 1.95, Vector3(0.0, 0.955, 0.125), "x", 0.15],  # 8 tábua do tampo
			["tabua", 1.95, Vector3(0.0, 0.955, 0.375), "x", 0.15],  # 9 tábua do tampo
		],
		# a travessa em cada pé (pino em pé) e cada tábua nas duas travessas
		"pinos": [
			[[4, 0], Vector3(0.8, 0.86, 0.42)], [[4, 1], Vector3(0.8, 0.86, -0.42)],
			[[5, 2], Vector3(-0.8, 0.86, 0.42)], [[5, 3], Vector3(-0.8, 0.86, -0.42)],
			[[6, 4], Vector3(0.8, 0.94, -0.375)], [[7, 4], Vector3(0.8, 0.94, -0.125)], [[8, 4], Vector3(0.8, 0.94, 0.125)], [[9, 4], Vector3(0.8, 0.94, 0.375)],
			[[6, 5], Vector3(-0.8, 0.94, -0.375)], [[7, 5], Vector3(-0.8, 0.94, -0.125)], [[8, 5], Vector3(-0.8, 0.94, 0.125)], [[9, 5], Vector3(-0.8, 0.94, 0.375)],
		],
		"area": Rect2(-1.05, -0.6, 2.1, 1.2),
		"mesa_carne": true,
	},
	# Fogão de barro (fogão caipira): a base de madeira (4 pés de tora, 2 travessas e o
	# tampo de tábuas) e em cima o fogão: as pedras assentadas no tampo (o chão do fogão e
	# o forro da boca de fogo) e o barro levantando as paredes, a chapa de barro com as duas
	# bocas das panelas e a chaminé atrás. Na frente a boca de fogo: lenha fina, rachada no
	# cepo (a acha grossa não cabe).
	"fogao": {
		"nome": "Fogão de Barro",
		"desc": "Fogão caipira de barro e pedras em cima de uma base de madeira. Primeiro a base (pés, travessas e o tampo de tábuas), depois as pedras do chão do fogão e o barro das paredes, da chapa com as duas bocas de panela e da chaminé. Na boca de fogo vai lenha fina (rachada no cepo em pedaços pequenos); acende com o arco de fogo. Nas bocas vão as vasilhas com carne: cozinhar (com água) ou fritar (mexendo).",
		"pecas": [
			["tora", 0.25, Vector3(0.6, 0.125, 0.33), "y", 0.07],      # 0 pé (baixinho)
			["tora", 0.25, Vector3(0.6, 0.125, -0.33), "y", 0.07],     # 1 pé
			["tora", 0.25, Vector3(-0.6, 0.125, 0.33), "y", 0.07],     # 2 pé
			["tora", 0.25, Vector3(-0.6, 0.125, -0.33), "y", 0.07],    # 3 pé
			["tora", 0.9, Vector3(0.6, 0.3, 0.0), "z", 0.06],          # 4 travessa
			["tora", 0.9, Vector3(-0.6, 0.3, 0.0), "z", 0.06],         # 5 travessa
			["tabua", 1.45, Vector3(0.0, 0.395, -0.3), "x", 0.15],     # 6 tampo
			["tabua", 1.45, Vector3(0.0, 0.395, -0.1), "x", 0.15],     # 7 tampo
			["tabua", 1.45, Vector3(0.0, 0.395, 0.1), "x", 0.15],      # 8 tampo
			["tabua", 1.45, Vector3(0.0, 0.395, 0.3), "x", 0.15],      # 9 tampo
		],
		"pinos": [
			[[4, 0], Vector3(0.6, 0.3, 0.33)], [[4, 1], Vector3(0.6, 0.3, -0.33)],
			[[5, 2], Vector3(-0.6, 0.3, 0.33)], [[5, 3], Vector3(-0.6, 0.3, -0.33)],
			[[6, 4], Vector3(0.6, 0.38, -0.3)], [[9, 4], Vector3(0.6, 0.38, 0.3)],
			[[6, 5], Vector3(-0.6, 0.38, -0.3)], [[9, 5], Vector3(-0.6, 0.38, 0.3)],
		],
		"area": Rect2(-0.8, -0.5, 1.6, 1.0),
		"fogao": {"pedras": 10, "barro": 6},
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
	# Forno de carvão: um domo de barro grosso (batido com a mão) com as pedras do chão
	# encaixadas nele (umas aparecendo por fora), uma boca na frente com a porta de barro
	# (uma placa grossa que tampa a boca) e o suspiro em cima, atrás. Enche de lenha,
	# acende, tampa a boca: a lenha vira carvão.
	# Carrinho de mão: caixa de tábuas serradas (fundo, laterais, frente e trás) em cima de
	# dois braços compridos de tábua que viram as alças atrás; na frente, a roda (uma
	# rodela de tora) num eixo de galho que passa pela ponta dos braços; atrás, dois pés
	# de tábua. Tudo amarrado com cipó.
	"carrinho": {
		"nome": "Carrinho de Mão",
		"desc": "Carrinho de mão de tábuas: carrega terra, barro, argila, areia, carvão, lenha e qualquer coisa da mochila.",
		# tábuas encostadas umas nas outras (sem fresta): o fundo de duas tábuas largas em
		# cima dos braços, as laterais por fora do fundo, a frente e o fundo de trás entre elas
		"pecas": [
			["tabua", 1.72, Vector3(-0.09, 0.22, 0.18), "x", 0.07],         # 0 braço (vira a alça atrás)
			["tabua", 1.72, Vector3(-0.09, 0.22, -0.18), "x", 0.07],        # 1 braço
			["tabua", 0.8, Vector3(0.04, 0.272, 0.12), "x", 0.1386],        # 2 fundo
			["tabua", 0.8, Vector3(0.04, 0.272, -0.12), "x", 0.1386],       # 3 fundo
			["tabua", 0.94, Vector3(0.04, 0.3575, 0.2747), "x_lado", 0.1386],   # 4 lateral
			["tabua", 0.94, Vector3(0.04, 0.3575, -0.2747), "x_lado", 0.1386],  # 5 lateral
			["tabua", 0.48, Vector3(0.4747, 0.3575, 0.0), "z_lado", 0.1386],    # 6 frente
			["tabua", 0.48, Vector3(-0.3947, 0.3575, 0.0), "z_lado", 0.1386],   # 7 trás
			["tabua", 0.22, Vector3(-0.55, 0.11, 0.18), "y", 0.06],         # 8 pé
			["tabua", 0.22, Vector3(-0.55, 0.11, -0.18), "y", 0.06],        # 9 pé
		],
		"pinos": [
			# o fundo pregado em cada braço (pino em pé, atravessando o fundo e entrando no braço)
			[[0, 2], Vector3(0.32, 0.29, 0.18)], [[0, 2], Vector3(-0.24, 0.29, 0.18)],
			[[1, 3], Vector3(0.32, 0.29, -0.18)], [[1, 3], Vector3(-0.24, 0.29, -0.18)],
			# as laterais no fundo (pino deitado, de fora para dentro)
			[[4, 2], Vector3(0.3, 0.272, 0.3094), Vector3(0, 0, 1)], [[4, 2], Vector3(-0.22, 0.272, 0.3094), Vector3(0, 0, 1)],
			[[5, 3], Vector3(0.3, 0.272, -0.3094), Vector3(0, 0, -1)], [[5, 3], Vector3(-0.22, 0.272, -0.3094), Vector3(0, 0, -1)],
			# os cantos: a lateral pregada na ponta da frente e do fundo de trás
			[[4, 6], Vector3(0.4747, 0.38, 0.3094), Vector3(0, 0, 1)], [[4, 7], Vector3(-0.3947, 0.38, 0.3094), Vector3(0, 0, 1)],
			[[5, 6], Vector3(0.4747, 0.38, -0.3094), Vector3(0, 0, -1)], [[5, 7], Vector3(-0.3947, 0.38, -0.3094), Vector3(0, 0, -1)],
			# os pés debaixo dos braços
			[[0, 8], Vector3(-0.55, 0.22, 0.18)], [[1, 9], Vector3(-0.55, 0.22, -0.18)],
		],
		"area": Rect2(-0.95, -0.32, 1.95, 0.64),
		"carrinho": {"eixo": 1, "roda": 1, "cipo": 0},
	},
	# Cavalete de trançar corda: de cada lado duas varas finas cruzadas em X (os pés
	# abertos no chão, as pontas passando um pouco do cruzamento) e, deitada no V de
	# cima, a vara comprida atravessada. Os cruzamentos são amarrados com cipó. No meio
	# da vara de cima prende a ponta dos cipós, que vão sendo trançados para baixo.
	"trancador": {
		"nome": "Cavalete de Trançar",
		"desc": "Cavalete de varas amarradas com cipó para trançar cipó em corda.",
		"pecas": [
			["tora", 1.75, Vector3(0.8, 0.8, 0.2), "y_t-", 0.05],      # 0 perna (pé para fora em +z)
			["tora", 1.75, Vector3(0.8, 0.8, -0.2), "y_t+", 0.05],     # 1 perna
			["tora", 1.75, Vector3(-0.8, 0.8, 0.2), "y_t-", 0.05],     # 2 perna
			["tora", 1.75, Vector3(-0.8, 0.8, -0.2), "y_t+", 0.05],    # 3 perna
			["tora", 1.95, Vector3(0.0, 1.43, 0.0), "x", 0.05],        # 4 a vara de cima
		],
		"pinos": [],
		"area": Rect2(-1.0, -0.55, 2.0, 1.1),
		"amarrar": {"n": 4, "nos": [Vector3(0.8, 1.38, 0.0), Vector3(-0.8, 1.38, 0.0)]},
	},
	# Tripé de içar: três toras compridas em pé, abertas embaixo e cruzadas em cima,
	# amarradas com cipó no cruzamento. Do cruzamento pende a roldana (amarrada com uma
	# cordinha de cipó trançado) e por ela corre a corda: uma ponta vai no pé do bicho, a
	# outra o jogador puxa andando para trás até a estaca fincada no chão, e amarra ali.
	"tripe": {
		"nome": "Tripé de Içar",
		"desc": "Três toras amarradas com cipó no topo, a roldana pendurada e a corda correndo nela, com a estaca no chão para amarrar.",
		"pecas": [
			["tora", 4.7, Vector3.ZERO, "tri0", 0.08],     # 0..2 as pernas (o centro é calculado)
			["tora", 4.7, Vector3.ZERO, "tri1", 0.08],
			["tora", 4.7, Vector3.ZERO, "tri2", 0.08],
			["tora", 0.7, Vector3(4.8, 0.12, 0.0), "y", 0.05],   # 3 a estaca (meio enterrada)
		],
		"pinos": [],
		"area": Rect2(-2.0, -2.0, 4.0, 4.0),
		"sem_colisao": true,
		"amarrar": {"n": 3, "nos": [Vector3(0.0, 4.0, 0.0)]},
		"tripe": {"roldana": 1, "cordinha": 1, "corda": 5, "forro": 8},
		"versao": 2,                    # (a partir da 2 o chão tem que ser forrado)
	},
	"forno": {
		"nome": "Forno de Carvão",
		"desc": "Domo de barro com pedras do chão encaixadas, uma porta de barro e o suspiro em cima. Primeiro levante as paredes de barro, depois encaixe as pedras e por último faça a porta de barro. Encha de lenha, acenda com o arco de fogo e tampe a boca: a lenha queima devagar, sem ar, e vira carvão.",
		"pecas": [],
		"pinos": [],
		"area": Rect2(-0.95, -0.9, 1.75, 1.8),
		"forno": {"barro": 4, "pedras": 16, "porta": 1},
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

static var _forro_mesh: ArrayMesh = null
const Babacus := preload("res://scripts/world/babacus.gd")
const TRI_R := 1.9               # raio dos pés do tripé
const TRI_H := 4.0              # altura do cruzamento das pernas
const TRI_L := 4.7               # comprimento das pernas
const TRI_ANG := [PI, PI / 3.0, -PI / 3.0]       # onde ficam os pés (a estaca em +x, entre dois)
const TRI_ROLDANA := 0.36        # quanto a roldana pende abaixo do cruzamento (o centro dela)
const TRI_RR := 0.11             # raio da roldana
const TRI_ESTACA := Vector3(4.8, 0.47, 0.0)     # a cabeça da estaca (onde amarra)
const TRI_CORDA := 5.0           # o comprimento de corda que trabalha (o resto fica enrolado)

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
var empurrando := -1             # o carrinho que este jogador está empurrando


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
		for q in plantas:
			q.erase("emp")             # ninguém está empurrando quando o mundo abre
			if q.get("ice", {}) is Dictionary:
				(q.get("ice", {}) as Dictionary).erase("puxando")
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
	var ca: Dictionary = t.get("carrinho", {})
	out["galho"] = int(ca.get("eixo", 0))
	out["rodela"] = int(ca.get("roda", 0))
	out["cipo"] = int(ca.get("cipo", 0)) + int((t.get("amarrar", {}) as Dictionary).get("n", 0))
	var tp: Dictionary = t.get("tripe", {})
	out["roldana"] = int(tp.get("roldana", 0))
	out["cipo_trancado"] = int(tp.get("cordinha", 0))
	out["corda"] = int(tp.get("corda", 0))
	out["folha_babacu"] = int(tp.get("forro", 0))
	var fg: Dictionary = t.get("fogao", {})
	out["pedra"] = int(fz.get("pedras", 0)) + int(fg.get("pedras", 0))
	out["barro"] = int(fz.get("barro", 0)) + int(fz.get("porta", 0)) + int(fg.get("barro", 0))
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
	if TIPOS[p.tipo].has("amarrar"):
		p["amarras"] = int(TIPOS[p.tipo].amarrar.n)
	if TIPOS[p.tipo].has("carrinho"):
		p["eixo"] = true
		if (p.get("roda", {}) as Dictionary).is_empty():
			p["roda"] = {"r": 0.2}
		p["amarras"] = int(TIPOS[p.tipo].carrinho.cipo)
	if TIPOS[p.tipo].has("tripe"):
		p["roldana"] = true
		p["corda_m"] = 5
		p["forro"] = int(TIPOS[p.tipo].tripe.forro)
	var fz: Dictionary = TIPOS[p.tipo].get("forno", {})
	if not fz.is_empty():
		p["ped"] = int(fz.pedras)
		p["bar"] = int(fz.barro)
		p["porta"] = int(fz.porta)
	var fg: Dictionary = TIPOS[p.tipo].get("fogao", {})
	if not fg.is_empty():
		p["ped"] = int(fg.pedras)
		p["bar"] = int(fg.barro)
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
	if tipo == "tripe":
		# o chão em cada pé e na estaca (o tripé fica em pé no chão torto)
		var q: Dictionary = plantas[plantas.size() - 1]
		var xf := xform(plantas.size() - 1)
		var dy := []
		for a in TRI_ANG:
			var w := xf * Vector3(cos(float(a)) * TRI_R, 0, sin(float(a)) * TRI_R)
			dy.append(snappedf(float(_jogo.surface_at(w.x, w.z)) - float(q.y), 0.01))
		var we := xf * Vector3(TRI_ESTACA.x, 0, TRI_ESTACA.z)
		dy.append(snappedf(float(_jogo.surface_at(we.x, we.z)) - float(q.y), 0.01))
		q["tri_dy"] = dy
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
		"y_t+": return Basis(Vector3.RIGHT, 0.36) * Basis(Vector3.BACK, PI * 0.5)     # em pé, inclinada
		"y_t-": return Basis(Vector3.RIGHT, -0.36) * Basis(Vector3.BACK, PI * 0.5)
	if dir.begins_with("tri"):
		var u := tri_dir(int(dir.substr(3)))
		var up := Vector3.UP - u * u.y
		var zz := u.cross(up.normalized()).normalized()
		return Basis(u, zz.cross(u), zz)
	return Basis()


## A perna i do tripé: do pé para o cruzamento (normalizado).
static func tri_dir(i: int) -> Vector3:
	var a: float = TRI_ANG[i]
	# (cada perna passa um pouco para o lado dela no cruzamento: as três ficam encostadas)
	return (Vector3(cos(a) * 0.075, TRI_H, sin(a) * 0.075) - Vector3(cos(a) * TRI_R, 0, sin(a) * TRI_R)).normalized()


## O centro da peça (as pernas do tripé têm o centro calculado).
static func slot_pos(pc: Array) -> Vector3:
	var d := str(pc[3])
	if d.begins_with("tri"):
		var i := int(d.substr(3))
		var a: float = TRI_ANG[i]
		return Vector3(cos(a) * TRI_R, -0.05, sin(a) * TRI_R) + tri_dir(i) * float(pc[1]) * 0.5
	return pc[2]


## A peça si da planta mi: o tamanho (L), o meio (pos) e a direção (b). No tripé cada
## perna vai do chão dela (mais baixo: perna mais comprida) até o cruzamento lá em cima.
func peca_geo(mi: int, si: int) -> Dictionary:
	var p: Dictionary = plantas[mi]
	var pc: Array = TIPOS[p.tipo].pecas[si]
	var d := str(pc[3])
	var dy: Array = p.get("tri_dy", [])
	if d.begins_with("tri") and dy.size() >= 4:
		var i := int(d.substr(3))
		var a: float = TRI_ANG[i]
		var F := Vector3(cos(a) * TRI_R, float(dy[i]) - 0.05, sin(a) * TRI_R)
		var C := Vector3(cos(a) * 0.075, TRI_H, sin(a) * 0.075)
		var u := (C - F).normalized()
		var L := snappedf(F.distance_to(C) + 0.3, 0.05)
		var up := Vector3.UP - u * u.y
		var zz := u.cross(up.normalized()).normalized()
		return {"L": L, "pos": F + u * L * 0.5, "b": Basis(u, zz.cross(u), zz)}
	if str(p.tipo) == "tripe" and si == 3 and dy.size() >= 4:
		return {"L": float(pc[1]), "pos": (pc[2] as Vector3) + Vector3(0, float(dy[3]), 0), "b": slot_basis(d)}
	return {"L": float(pc[1]), "pos": slot_pos(pc), "b": slot_basis(d)}


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
	if not fz.is_empty() and (int(p.get("ped", 0)) < int(fz.pedras) or int(p.get("bar", 0)) < int(fz.barro) or int(p.get("porta", 0)) < int(fz.porta)):
		return false
	var fg: Dictionary = TIPOS[p.tipo].get("fogao", {})
	if not fg.is_empty() and (int(p.get("ped", 0)) < int(fg.pedras) or int(p.get("bar", 0)) < int(fg.barro)):
		return false
	if lamina_count(mi) < lamina_need(str(p.tipo)):
		return false
	if TIPOS[p.tipo].has("carrinho") and carrinho_etapa(mi) != "":
		return false
	if TIPOS[p.tipo].has("tripe") and (not bool(p.get("roldana", false)) or int(p.get("corda_m", 0)) <= 0 or forro_falta(mi) > 0):
		return false
	if int(p.get("amarras", 0)) < int((TIPOS[p.tipo].get("amarrar", {}) as Dictionary).get("n", 0)):
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
		var pLs := float(peca_geo(mi, i).L)
		if L < pLs - 0.02:
			short = maxf(short, pLs)
			continue
		if kind == "tora" and r > float(pc[4]) * 2.6:
			continue                   # tora grossa demais para essa peça
		if pc.size() > 5 and r < float(pc[5]):
			thin = float(pc[5]) if thin <= 0.0 else minf(thin, float(pc[5]))
			continue                   # fina demais (a rodela da mesa e o volante são de tora grossa)
		var w: Vector3 = xf * (peca_geo(mi, i).pos as Vector3)
		var d := Vector2(w.x - pos.x, w.z - pos.z).length()
		if d < bd:
			bd = d
			best = i
	if best >= 0:
		return {"i": best, "sobra": maxf(0.0, L - float(peca_geo(mi, best).L))}
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
	if str(TIPOS[plantas[mi].tipo].pecas[si][3]).begins_with("tri"):
		sobra = 0.0                # (a perna do tripé passando do cruzamento é normal)
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
	var geo := peca_geo(mi, si)
	var b: Basis = geo.b
	var L := float(geo.L)
	var e := float(plantas[mi].sobra[si])
	var c: Vector3 = geo.pos
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
		if done_count(mi) < 3 or mi == empurrando:
			continue
		var t: Dictionary = TIPOS[plantas[mi].tipo]
		if bool(t.get("sem_colisao", false)):
			continue
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
			var geo := peca_geo(mi, si)
			var b: Basis = geo.b
			var pL := float(geo.L)
			var ppos: Vector3 = geo.pos
			if bool(p.pecas[si]):
				var sob: Array = p.get("sobra", [])
				var e: float = float(sob[si]) if si < sob.size() else 0.0
				var wfl := piece_log(mi, si, pL + e)
				var n: Node3D = _arv.free_log_node(wfl)
				root.add_child(n)
				# a sobra fica para fora numa ponta
				var bb := b
				if str(pc[0]) == "tabua":
					bb = b * Basis(Vector3.RIGHT, PI)      # a tábua virada: a face rachada (reta) para cima
				n.transform = Transform3D(bb, ppos + b.x * e * 0.5)
				if t.has("carrinho") and str(pc[0]) == "tabua":
					# a tábua aparelhada na largura e na grossura da peça: fica rente à outra
					var ex0: Vector2 = _arv._sec_ext(slot_log(pc))
					var ex1: Vector2 = _arv._sec_ext(wfl)
					var rr1: float = _arv.free_log_max_radius(wfl)
					var r0 := float(pc[4])
					var sc := Vector3(1.0, clampf(ex0.x * r0 / maxf(ex1.x * rr1, 0.005), 0.3, 3.0), clampf(ex0.y * r0 / maxf(ex1.y * rr1, 0.005), 0.3, 3.0))
					n.transform = Transform3D(bb * Basis.from_scale(sc), n.transform.origin)
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
				Furo.apply(n, holes, Vector3((pL + e) * 0.5, ex.x * rr, ex.y * rr))
			else:
				var mi2 := MeshInstance3D.new()
				var bm := BoxMesh.new()
				var r := float(pc[4])
				bm.size = Vector3(pL, r * (2.0 if str(pc[0]) == "tora" else (1.0 if str(pc[0]) == "meia" else 0.5)), r * 2.0)
				mi2.mesh = bm
				mi2.material_override = _ghost_mat
				mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(mi2)
				mi2.transform = Transform3D(b, ppos)
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
		if t.has("fogao"):
			_draw_fogao(mi, root, nd)
			_nodes[mi] = nd
			continue
		if t.has("tripe"):
			_draw_tripe(mi, root, nd)
			_nodes[mi] = nd
			continue
		if t.has("amarrar"):
			_draw_amarras(mi, root, nd)
			_nodes[mi] = nd
			continue
		if t.has("carrinho"):
			_draw_carrinho(mi, root, nd)
			_nodes[mi] = nd
			carrinho_pose(mi, mi == empurrando)
			continue
		if bool(t.get("torno", false)):
			if pronta(mi):
				nd["biela"] = _stick(Vector3(-0.2, 0.06, 0.0), Vector3(0.2, 0.06, 0.0), 0.018)
				root.add_child(nd.biela)
			_nodes[mi] = nd
			torno_girar(mi, float(p.get("_ang", 0.0)), 0.0)
			continue
		if bool(t.get("mesa_carne", false)):
			_nodes[mi] = nd
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


# ---------- cavalete de trançar ----------

## Falta amarrar? (todas as varas no lugar e ainda faltam amarras de cipó)
func amarras_falta(mi: int) -> int:
	var p: Dictionary = plantas[mi]
	var am: Dictionary = TIPOS[p.tipo].get("amarrar", {})
	if am.is_empty():
		return 0
	for b in p.pecas:
		if not bool(b):
			return 0
	return maxi(0, int(am.n) - int(p.get("amarras", 0)))


func amarrar(mi: int) -> void:
	plantas[mi]["amarras"] = int(plantas[mi].get("amarras", 0)) + 1
	_rebuild()


## A corda sendo feita: {alvo (m), feito (m), cipo (cipós já postos)} ou {}.
func corda_of(mi: int) -> Dictionary:
	var c = plantas[mi].get("corda", {})
	return c if c is Dictionary else {}


static var _cipo_mat: StandardMaterial3D

static func cipo_mat() -> StandardMaterial3D:
	if _cipo_mat == null:
		_cipo_mat = StandardMaterial3D.new()
		_cipo_mat.vertex_color_use_as_albedo = true
		_cipo_mat.vertex_color_is_srgb = true
		_cipo_mat.roughness = 0.8
	return _cipo_mat


## Um fio de cipó: tubo fino por uma lista de pontos, com a cor variando pelo comprimento
## (cipó-titica: castanho-esverdeado com nós e partes mais claras).
static func fio_cipo(st: SurfaceTool, pts: Array, r: float, tom := 0.0) -> void:
	var lados := 5
	var rows := []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var q: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var o: Vector3 = pts[maxi(i - 1, 0)]
		var d := (q - o).normalized()
		if d.length() < 0.5:
			d = Vector3.UP
		var a := d.cross(Vector3(0.31, 0.77, 0.55)).normalized()
		var b := d.cross(a).normalized()
		var row := []
		for k in lados:
			var t := TAU * k / lados
			row.append(p + (a * cos(t) + b * sin(t)) * r)
		rows.append(row)
	var base := Color(0.3, 0.23, 0.1).lerp(Color(0.26, 0.26, 0.11), tom)
	for i in rows.size() - 1:
		var c0 := base.darkened(0.12 * sin(float(i) * 1.7) + 0.06 * sin(float(i) * 0.37 + tom * 9.0))
		for k in lados:
			var qq := [rows[i][k], rows[i + 1][k], rows[i + 1][(k + 1) % lados], rows[i][(k + 1) % lados]]
			var sh := 0.85 + 0.15 * float(k % 2)
			for j in [0, 2, 1, 0, 3, 2]:
				st.set_color(Color(c0.r * sh, c0.g * sh, c0.b * sh))
				st.add_vertex(qq[j])


## Corda torcida ao longo de um caminho: três pernas de cipó enroladas bem juntas em
## espiral (encostando uma na outra, sem fresta) e um miolo por dentro.
## r: raio de cada perna; passo: comprimento de uma volta; fase: gira as pernas.
static func corda_tubo(st: SurfaceTool, caminho: Array, r: float, passo: float, fase := 0.0) -> void:
	if caminho.size() < 2:
		return
	# reamostra o caminho em passos curtos (a espiral fica lisa)
	var pts := []
	var dmax := passo / 18.0
	for i in caminho.size() - 1:
		var a: Vector3 = caminho[i]
		var b: Vector3 = caminho[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / dmax)))
		for k in n:
			pts.append(a.lerp(b, float(k) / n))
	pts.append(caminho[caminho.size() - 1])
	var rr := r * 1.12                       # as pernas encostam (sobrepõem um tico)
	var ref := Vector3(0.31, 0.77, 0.55).normalized()
	var esq := []
	var sacum := 0.0
	var fr_a := Vector3.ZERO
	for i in pts.size():
		var p: Vector3 = pts[i]
		if i > 0:
			sacum += p.distance_to(pts[i - 1])
		var d := ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var a2: Vector3
		if fr_a == Vector3.ZERO:
			a2 = d.cross(ref).normalized()
		else:
			a2 = (fr_a - d * d.dot(fr_a)).normalized()          # o quadro gira junto, sem torcer
		fr_a = a2
		var b2 := d.cross(a2).normalized()
		esq.append([p, a2, b2, sacum])
	for k in 3:
		var fio := []
		for e in esq:
			var th := float(e[3]) / passo * TAU + TAU * k / 3.0 + fase
			fio.append((e[0] as Vector3) + ((e[1] as Vector3) * cos(th) + (e[2] as Vector3) * sin(th)) * rr)
		fio_cipo(st, fio, r, 0.15 + k * 0.3)
	var miolo := []
	for e in esq:
		miolo.append(e[0])
	fio_cipo(st, miolo, rr * 0.95, 0.9)


## A amarração de um cruzamento: voltas de cipó apertadas em volta da vara de cima (dos
## dois lados das pernas) e voltas em X passando pelo cruzamento das pernas.
static func amarra_mesh(cheia: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var R := 0.058
	var r := 0.0085
	var voltas := 6 if cheia else 3
	# as voltas em volta da vara de cima, dos dois lados
	for lado in [-1.0, 1.0]:
		var pts := []
		var n := voltas * 14
		for i in n + 1:
			var u := float(i) / n
			var a := u * TAU * voltas
			pts.append(Vector3(lado * (0.045 + u * 0.07), 0.05 + cos(a) * R, sin(a) * R))
		fio_cipo(st, pts, r, 0.2 if lado > 0 else 0.5)
	# as voltas em X pelo cruzamento das pernas (por baixo da vara)
	var nx := 3 if cheia else 1
	for k in nx:
		for sg in [-1.0, 1.0]:
			var pts2 := []
			for i in 25:
				var a2 := float(i) / 24.0 * TAU
				var raio := 0.075 + k * 0.012
				var c := Vector3(0, -0.01, 0)
				var v := Vector3(0, cos(a2) * raio, sin(a2) * raio * 0.9)
				pts2.append(c + Basis(Vector3.RIGHT, sg * 0.75) * v + Vector3(sin(a2) * 0.03 * sg, 0, 0))
			fio_cipo(st, pts2, r * 0.95, 0.7 + k * 0.1)
	# o nó
	var no := []
	for i in 9:
		var a3 := float(i) / 8.0 * TAU
		no.append(Vector3(0.12 + cos(a3) * 0.015, 0.05 + sin(a3) * 0.015, 0.06))
	fio_cipo(st, no, r * 1.1, 0.3)
	st.generate_normals()
	return st.commit()


func _draw_amarras(mi: int, root: Node3D, nd: Dictionary) -> void:
	var p: Dictionary = plantas[mi]
	var am: Dictionary = TIPOS[p.tipo].amarrar
	var nos: Array = am.nos
	var feitas := int(p.get("amarras", 0))
	var por := int(am.n) / maxi(1, nos.size())
	for i in nos.size():
		var k := feitas - i * por
		if k <= 0:
			continue
		var m := MeshInstance3D.new()
		m.mesh = amarra_mesh(k >= por)
		m.material_override = cipo_mat()
		m.position = nos[i]
		root.add_child(m)
	if not pronta(mi):
		return
	# a ponta dos cipós amarrada no meio da vara de cima e a corda já trançada
	var tr := Node3D.new()
	tr.name = "tranca"
	tr.position = Vector3(0, 1.43, 0)
	root.add_child(tr)
	nd["tranca"] = tr
	var cd := corda_of(mi)
	var mt := MeshInstance3D.new()
	mt.name = "corda"
	mt.material_override = cipo_mat()
	tr.add_child(mt)
	mt.mesh = tranca_mesh(float(cd.get("feito", 0.0)) * 4.0, -1, 0.0, not cd.is_empty())
	# o rolo de corda que já ficou pronta (no chão, embaixo)
	if not cd.is_empty() and float(cd.get("feito", 0.0)) > 0.05:
		var rolo := MeshInstance3D.new()
		rolo.name = "rolo"
		rolo.mesh = rolo_mesh(float(cd.feito))
		rolo.material_override = cipo_mat()
		rolo.position = Vector3(0.25, 0.0, 0.32)
		root.add_child(rolo)


## A trança pendurada (de cima para baixo): três fios de cipó em trança (cada fio cruza
## por cima do do meio, um lado de cada vez), embaixo os três soltos. fase: quanto já
## trançou (move o desenho); movendo (0..1): o fio "lado" passando para o meio.
static func tranca_mesh(fase: float, lado: int, movendo: float, com_fios: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var topo := 0.0
	var fim := -0.62                         # onde a trança acaba (o resto solto)
	var passo := 0.055                       # comprimento de um cruzamento
	var a := 0.018
	var b := 0.012
	if com_fios:
		var r := 0.0125
		var ps := 0.1
		var corpo := []
		for j in 2:
			corpo.append(Vector3(0, lerpf(topo, fim, float(j)), 0))
		corda_tubo(st, corpo, r, ps, fase * 0.25 / ps * TAU)
		# embaixo as três pernas soltas, abrindo (a que está passando vem para o meio)
		var giro := fase * 0.25 / ps * TAU + (topo - fim) / ps * TAU
		for i in 3:
			var th := giro + TAU * i / 3.0
			var pf := Vector3(cos(th), fim, sin(th)) * Vector3(r * 1.12, 1, r * 1.12)
			var lado_i: float = [-1.0, 0.0, 1.0][i]
			var ponta := Vector3(lado_i * 0.13, fim - 0.32, 0.06)
			if lado != -1 and ((lado == 0 and i == 0) or (lado == 1 and i == 2)):
				ponta = ponta.lerp(Vector3(0, fim - 0.3, 0.1), movendo)
			var pts := []
			for j in 13:
				var u2 := float(j) / 12.0
				# a perna ainda torcida no começo, depois solta
				var tw := (1.0 - u2) * 0.6
				var pp := pf.lerp(ponta, u2) + Vector3(sin(th + tw) * 0.004, 0, sin(u2 * PI) * 0.03)
				pts.append(pp)
			fio_cipo(st, pts, r, float(i) * 0.35)
	# o nó no alto da vara
	var no := []
	for j in 13:
		var a3 := float(j) / 12.0 * TAU
		no.append(Vector3(cos(a3) * 0.065, sin(a3) * 0.065, 0.0))
	fio_cipo(st, no, 0.012, 0.4)
	st.generate_normals()
	return st.commit()


## O rolo de corda (em voltas, deitado): mais voltas quanto mais comprida.
static func rolo_mesh(metros: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var voltas := clampi(int(round(metros * 0.6)) + 2, 3, 34)
	var R := clampf(0.1 + metros * 0.002, 0.1, 0.2)
	var r := 0.0075
	var esp := r * 2.3 * 1.12                # grossura da corda
	var pts := []
	var n := voltas * 20
	var por_camada := 6
	for i in n + 1:
		var u := float(i) / n
		var a := u * TAU * voltas
		var v := u * voltas
		var camada: float = floor(v / por_camada)
		var dentro := fmod(v, por_camada) / por_camada
		var rr: float = R - esp * 0.5 + esp * dentro * por_camada * 0.18
		pts.append(Vector3(cos(a) * rr, esp * 0.5 + camada * esp * 0.95, sin(a) * rr))
	corda_tubo(st, pts, r, 0.07)
	st.generate_normals()
	return st.commit()


# ---------- tripé de içar ----------

## Falta o quê: "pecas", "amarrar", "roldana", "corda" ou "" (pronto).
func tripe_etapa(mi: int) -> String:
	var p: Dictionary = plantas[mi]
	for b in p.pecas:
		if not bool(b):
			return "pecas"
	if amarras_falta(mi) > 0:
		return "amarrar"
	if forro_falta(mi) > 0:
		return "forro"
	if not bool(p.get("roldana", false)):
		return "roldana"
	if int(p.get("corda_m", 0)) <= 0:
		return "corda"
	return ""


## Quantas folhas de babaçu ainda faltam no forro do chão (tripé novo).
func forro_falta(mi: int) -> int:
	var p: Dictionary = plantas[mi]
	if str(p.tipo) != "tripe" or int(p.get("versao", 1)) < 2:
		return 0
	return maxi(0, int(TIPOS.tripe.tripe.forro) - int(p.get("forro", 0)))


## O ponto está em cima do forro de algum tripé (forrado de todo)?
func no_forro(pos: Vector3) -> bool:
	for mi in plantas.size():
		var p: Dictionary = plantas[mi]
		if str(p.tipo) != "tripe" or int(p.get("forro", 0)) <= 0:
			continue
		var l := xform(mi).affine_inverse() * pos
		var raio := 2.3 * clampf(float(p.forro) / float(TIPOS.tripe.tripe.forro), 0.0, 1.0)
		if Vector2(l.x, l.z).length() < raio:
			return true
	return false


func tripe_por(mi: int, what: String, metros := 0) -> void:
	match what:
		"forro": plantas[mi]["forro"] = int(plantas[mi].get("forro", 0)) + 1
		"roldana": plantas[mi]["roldana"] = true
		"corda": plantas[mi]["corda_m"] = metros
	_rebuild()


## O centro da roldana no mundo.
func tri_roldana(mi: int) -> Vector3:
	return xform(mi) * Vector3(0, TRI_H - TRI_ROLDANA, 0)


## A cabeça da estaca no mundo.
func tri_estaca(mi: int) -> Vector3:
	var dy: Array = plantas[mi].get("tri_dy", [])
	return xform(mi) * (TRI_ESTACA + Vector3(0, float(dy[3]) if dy.size() >= 4 else 0.0, 0))


## O lado da roldana para onde vai a estaca (o lado de puxar), no mundo.
func tri_lado(mi: int) -> Vector3:
	return xform(mi).basis.x.normalized()


## A corda parada (pendurada na roldana) aparece ou não (o jogo desenha a que está em uso).
func tri_corda_parada(mi: int, ver: bool) -> void:
	var nd: Dictionary = _nodes.get(mi, {})
	if nd.has("corda") and is_instance_valid(nd.corda):
		(nd.corda as Node3D).visible = ver


## As voltas de cipó amarrando as três pernas no cruzamento (k: quantas amarras já foram).
static func tripe_amarra_mesh(k: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := 0.0085
	var R := 0.158
	var voltas := 2 + k * 2
	var pts := []
	var n := voltas * 18
	for i in n + 1:
		var u := float(i) / n
		var a := u * TAU * voltas
		pts.append(Vector3(cos(a) * R, -0.13 + u * 0.19, sin(a) * R))
	fio_cipo(st, pts, r, 0.3)
	# as voltas de aperto entre as pernas (passam por fora e por dentro das voltas)
	if k >= 2:
		for j in 3:
			var a0: float = TRI_ANG[j] + PI / 3.0
			var c := Vector3(cos(a0), 0, sin(a0)) * (R + 0.005)
			var pp := []
			for i in 17:
				var t := float(i) / 16.0 * TAU
				pp.append(c + Vector3(cos(a0), 0, sin(a0)) * cos(t) * 0.03 + Vector3(0, sin(t) * 0.11 - 0.035, 0))
			fio_cipo(st, pp, r * 0.9, 0.6 + j * 0.1)
	if k >= 3:
		var no := []
		for i in 9:
			var a3 := float(i) / 8.0 * TAU
			no.append(Vector3(R + 0.012, 0.06 + sin(a3) * 0.016, cos(a3) * 0.016))
		fio_cipo(st, no, r * 1.1, 0.2)
	st.generate_normals()
	return st.commit()


func _draw_tripe(mi: int, root: Node3D, nd: Dictionary) -> void:
	var p: Dictionary = plantas[mi]
	# o forro: as folhas de babaçu deitadas no chão, em roda, cobrindo onde a carne cai
	var nf := int(p.get("forro", 0))
	if nf > 0:
		if _forro_mesh == null:
			var stf := SurfaceTool.new()
			stf.begin(Mesh.PRIMITIVE_TRIANGLES)
			var rng := RandomNumberGenerator.new()
			rng.seed = 4242
			Babacus._folha(stf, Vector3(-2.2, 0, 0), Vector3.RIGHT, 0.0, 4.4, Color(0.13, 0.22, 0.08), rng, false, true)
			stf.generate_normals()
			_forro_mesh = stf.commit()
		var fm := StandardMaterial3D.new()
		fm.vertex_color_use_as_albedo = true
		fm.vertex_color_is_srgb = true
		fm.roughness = 0.85
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		for i in nf:
			var a := TAU * i / 8.0 + 0.2
			var lf := MeshInstance3D.new()
			lf.mesh = _forro_mesh
			lf.material_override = fm
			var c := Vector3(cos(a), 0, sin(a)) * 0.95
			# a folha deita no chão ponto a ponto (no morro ela dobra junto, não fica no ar)
			var tl := Transform3D(Basis(Vector3.UP, -a).scaled(Vector3(0.62, 1.0, 1.15)), c)
			var xw := xform(mi)
			var arr: Array = _forro_mesh.surface_get_arrays(0)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nv := PackedVector3Array()
			nv.resize(vs.size())
			for k2 in vs.size():
				var lp := tl * vs[k2]
				var wp := xw * Vector3(lp.x, 0.0, lp.z)
				lp.y = float(_jogo.surface_at(wp.x, wp.z)) - float(p.y) + vs[k2].y * 0.25 + 0.03 + i * 0.004
				nv[k2] = lp
			arr[Mesh.ARRAY_VERTEX] = nv
			arr[Mesh.ARRAY_NORMAL] = null
			var stg := SurfaceTool.new()
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			stg.create_from(am, 0)
			stg.generate_normals()
			lf.mesh = stg.commit()
			lf.transform = Transform3D.IDENTITY
			lf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(lf)
	var k := int(p.get("amarras", 0))
	if k > 0:
		var m := MeshInstance3D.new()
		m.mesh = tripe_amarra_mesh(k)
		m.material_override = cipo_mat()
		m.position = Vector3(0, TRI_H, 0)
		root.add_child(m)
	if not bool(p.get("roldana", false)):
		return
	var pc := Vector3(0, TRI_H - TRI_ROLDANA, 0)
	# a cordinha de cipó trançado: do cruzamento (em volta das amarras) até a forquilha
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	corda_tubo(st, [Vector3(0, TRI_H - 0.1, 0), pc + Vector3(0, 0.22, 0)], 0.0055, 0.05)
	var laco := []
	for i in 13:
		var a := float(i) / 12.0 * TAU
		laco.append(Vector3(0, TRI_H - 0.1, 0) + Vector3(cos(a) * 0.17, 0.02 * sin(a * 2.0), sin(a) * 0.17))
	corda_tubo(st, laco, 0.0055, 0.05)
	st.generate_normals()
	var cm := MeshInstance3D.new()
	cm.mesh = st.commit()
	cm.material_override = cipo_mat()
	root.add_child(cm)
	# a forquilha segurando a roldana pela vareta (o eixo atravessa de lado, em z)
	root.add_child(_stick(pc + Vector3(0, 0.23, 0), pc + Vector3(0, 0.15, 0), 0.016))
	for sd in [-1.0, 1.0]:
		root.add_child(_stick(pc + Vector3(0, 0.15, 0), pc + Vector3(0, 0.0, sd * 0.045), 0.014))
	root.add_child(_stick(pc + Vector3(0, 0, -0.06), pc + Vector3(0, 0, 0.06), 0.009))
	# a roldana: rodela com o sulco (duas bordas e o miolo mais fino)
	var rod := Node3D.new()
	rod.name = "roldana"
	rod.position = pc
	root.add_child(rod)
	nd["roldana"] = rod
	for e in [[-0.019, TRI_RR, 0.012], [0.019, TRI_RR, 0.012], [0.0, TRI_RR * 0.78, 0.028]]:
		var w: Node3D = _arv.free_log_node(slot_log(["tora", float(e[2]), Vector3.ZERO, "x", float(e[1])]))
		w.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0, float(e[0])))
		rod.add_child(w)
	if int(p.get("corda_m", 0)) <= 0:
		return
	# a corda parada: passando por cima da roldana, uma ponta pendurada de cada lado e o
	# resto enrolado no chão do lado da estaca
	var gy := 0.03
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cam := [Vector3(-TRI_RR * 0.85, 0.45, 0.0), Vector3(-TRI_RR * 0.85, pc.y, 0.0)]
	for i in range(1, 8):
		var a := PI - PI * float(i) / 8.0
		cam.append(pc + Vector3(cos(a), sin(a), 0) * TRI_RR * 0.85)
	cam.append(Vector3(TRI_RR * 0.85, pc.y, 0.0))
	cam.append(Vector3(TRI_RR * 0.85, gy + 0.05, 0.0))
	cam.append(Vector3(0.45, gy, 0.08))
	corda_tubo(st2, cam, 0.0075, 0.07)
	st2.generate_normals()
	var cd := MeshInstance3D.new()
	cd.name = "corda"
	cd.mesh = st2.commit()
	cd.material_override = cipo_mat()
	root.add_child(cd)
	nd["corda"] = cd
	var rolo := MeshInstance3D.new()
	rolo.mesh = rolo_mesh(2.0)
	rolo.material_override = cipo_mat()
	rolo.position = Vector3(0.6, 0.0, 0.1)
	cd.add_child(rolo)


# ---------- carrinho de mão ----------

const CAR_EIXO := Vector3(0.72, 0.2, 0.0)   # o eixo da roda (na ponta dos braços)
const CAR_PE := Vector3(-0.55, 0.0, 0.0)    # onde os pés encostam no chão
const CAR_ALCA := Vector3(-0.95, 0.22, 0.0) # a ponta das alças (na mão de quem empurra)
const CAR_MAO := 0.62            # altura das mãos empurrando (m)
const CAR_VOL := 0.11            # m³ de terra/barro/areia/carvão que cabem na caixa (uns 4,5 baldes)
const CAR_LENHA := 12            # achas de lenha que cabem
const CAR_FUNDO := 0.307         # em cima das tábuas do fundo
const CAR_MATS := ["terra", "argila", "barro", "areia", "carvao"]


## Falta o quê para o carrinho ficar pronto: "tabuas", "eixo", "roda", "cipo" ou "".
func carrinho_etapa(mi: int) -> String:
	var p: Dictionary = plantas[mi]
	var ca: Dictionary = TIPOS[p.tipo].get("carrinho", {})
	if ca.is_empty():
		return ""
	for b in p.pecas:
		if not bool(b):
			return "tabuas"
	if not bool(p.get("eixo", false)):
		return "eixo"
	if (p.get("roda", {}) as Dictionary).is_empty():
		return "roda"
	if int(p.get("amarras", 0)) < int(ca.cipo):
		return "cipo"
	return ""


## Põe o eixo (galho), a roda (rodela, com o raio dela) ou uma amarra de cipó.
func carrinho_por(mi: int, what: String, raio := 0.2) -> void:
	var p: Dictionary = plantas[mi]
	match what:
		"eixo": p["eixo"] = true
		"roda": p["roda"] = {"r": snappedf(clampf(raio, 0.18, 0.32), 0.001)}
		"cipo": p["amarras"] = int(p.get("amarras", 0)) + 1
	_rebuild()


## O que tem dentro: {carga: {tipo, vol}, lenhas: [achas], itens: {id: n}}
func car_of(mi: int) -> Dictionary:
	var p: Dictionary = plantas[mi]
	if not p.has("car") or not p.car is Dictionary:
		p["car"] = {"carga": {}, "lenhas": [], "itens": {}}
	var c: Dictionary = p.car
	if not c.has("carga"): c["carga"] = {}
	if not c.has("lenhas"): c["lenhas"] = []
	if not c.has("itens"): c["itens"] = {}
	return c


func car_vazio(mi: int) -> bool:
	var c := car_of(mi)
	return float((c.carga as Dictionary).get("vol", 0.0)) <= 0.0005 and (c.lenhas as Array).is_empty() and (c.itens as Dictionary).is_empty()


## Cabe quanto mais desse material (m³)? (não mistura: terra com terra, barro com barro)
func car_cabe(mi: int, tipo: String) -> float:
	var c := car_of(mi)
	var cg: Dictionary = c.carga
	if not cg.is_empty() and float(cg.get("vol", 0.0)) > 0.0005 and str(cg.tipo) != tipo:
		return 0.0
	if not (c.lenhas as Array).is_empty():
		return 0.0                      # com lenha dentro não dá para jogar terra em cima
	return maxf(0.0, CAR_VOL - float(cg.get("vol", 0.0)))


func car_por_carga(mi: int, tipo: String, vol: float) -> float:
	var mv := minf(vol, car_cabe(mi, tipo))
	if mv <= 0.0:
		return 0.0
	var c := car_of(mi)
	c.carga = {"tipo": tipo, "vol": float((c.carga as Dictionary).get("vol", 0.0)) + mv}
	_rebuild()
	return mv


## Tira até vol m³ do material (para o balde, ou tudo para despejar). Devolve {tipo, vol}.
func car_tirar_carga(mi: int, vol: float) -> Dictionary:
	var c := car_of(mi)
	var cg: Dictionary = c.carga
	if cg.is_empty() or float(cg.get("vol", 0.0)) <= 0.0005:
		return {}
	var mv := minf(vol, float(cg.vol))
	var left := float(cg.vol) - mv
	c.carga = {} if left <= 0.0005 else {"tipo": cg.tipo, "vol": left}
	_rebuild()
	return {"tipo": cg.tipo, "vol": mv}


func car_por_lenha(mi: int, acha: Dictionary) -> bool:
	var c := car_of(mi)
	if (c.lenhas as Array).size() >= CAR_LENHA or float((c.carga as Dictionary).get("vol", 0.0)) > 0.0005:
		return false
	(c.lenhas as Array).append(acha)
	_rebuild()
	return true


func car_tirar_lenha(mi: int) -> Dictionary:
	var c := car_of(mi)
	if (c.lenhas as Array).is_empty():
		return {}
	var a: Dictionary = (c.lenhas as Array).pop_back()
	_rebuild()
	return a


func car_por_item(mi: int, id: String, n: int) -> void:
	var c := car_of(mi)
	c.itens[id] = int((c.itens as Dictionary).get(id, 0)) + n
	_rebuild()


func car_tirar_itens(mi: int) -> Dictionary:
	var c := car_of(mi)
	var it: Dictionary = c.itens
	c.itens = {}
	_rebuild()
	return it


## Tudo das plantas menos onde os carrinhos estão (para saber se, no multiplayer, só um
## carrinho andou: aí não precisa refazer o desenho de tudo, só mover).
func assinatura() -> String:
	var out := []
	for p in plantas:
		var c: Dictionary = {}
		for k in p:
			if str(k).begins_with("_"):
				continue
			if str(p.get("tipo", "")) == "carrinho" and str(k) in ["x", "y", "z", "yaw"]:
				continue
			if str(k) == "ice":
				continue                   # (o içamento anda todo quadro: desenhado pelo jogo)
			c[k] = p[k]
		out.append(c)
	return JSON.stringify(out)


## Só os carrinhos mudaram de lugar: move os desenhos deles.
func reposicionar() -> void:
	for mi in plantas.size():
		if str(plantas[mi].get("tipo", "")) == "carrinho":
			carrinho_pose(mi, mi == empurrando)


## Onde o carrinho fica: a roda sempre em cima do chão (passa por cima dos montes de
## terra, nunca atravessa) e, atrás, os pés no chão (parado) ou as alças na altura das
## mãos (empurrando). vira: quanto as alças sobem além disso (virando a caçamba).
func carrinho_pose(mi: int, empurrado: bool, vira := 0.0) -> void:
	var nd: Dictionary = _nodes.get(mi, {})
	if nd.is_empty() or not is_instance_valid(nd.root):
		return
	var p: Dictionary = plantas[mi]
	empurrado = empurrado or bool(p.get("emp", false))       # (outro jogador empurrando)
	var R := float((p.get("roda", {}) as Dictionary).get("r", CAR_EIXO.y))
	var yawb := Basis(Vector3.UP, float(p.yaw))
	var dx: Vector3 = yawb * Vector3.RIGHT
	var o := Vector3(float(p.x), 0.0, float(p.z))
	# a roda: o ponto mais alto do chão debaixo dela (encosta no monte e sobe nele)
	var wc := o + dx * CAR_EIXO.x
	var wy := -1e9
	for k in 9:
		var sd := (float(k) / 4.0 - 1.0) * R * 0.95
		var q := wc + dx * sd
		wy = maxf(wy, float(_jogo.ground_at(q.x, q.z)) + sqrt(maxf(R * R - sd * sd, 0.0)))
	# atrás: os pés no chão, ou as alças nas mãos
	var bl: Vector3 = CAR_ALCA if empurrado else CAR_PE
	var bw := o + dx * bl.x
	var by := float(_jogo.ground_at(bw.x, bw.z)) + (CAR_MAO if empurrado else 0.0)
	var v := Vector2(CAR_EIXO.x - bl.x, CAR_EIXO.y - bl.y)
	var th := asin(clampf((wy - by) / v.length(), -0.95, 0.95)) - atan2(v.y, v.x)
	th -= vira                         # alças para cima: a caçamba vira para a frente
	var bs := yawb * Basis(Vector3.BACK, th)
	var aw := Vector3(wc.x, wy, wc.z)
	(nd.root as Node3D).transform = Transform3D(bs, aw - bs * CAR_EIXO)


## Move o carrinho (empurrando): só a posição, sem refazer o desenho; a roda gira.
func carrinho_mover(mi: int, pos: Vector3, yaw: float, andou: float) -> void:
	var p: Dictionary = plantas[mi]
	p.x = snappedf(pos.x, 0.001)
	p.y = snappedf(pos.y, 0.001)
	p.z = snappedf(pos.z, 0.001)
	p.yaw = snappedf(yaw, 0.0001)
	carrinho_pose(mi, mi == empurrando)
	var nd: Dictionary = _nodes.get(mi, {})
	if nd.has("roda") and is_instance_valid(nd.roda):
		var R := float((p.get("roda", {}) as Dictionary).get("r", 0.2))
		p["_giro"] = float(p.get("_giro", 0.0)) - andou / maxf(R, 0.05)
		(nd.roda as Node3D).transform = Transform3D(Basis(Vector3.BACK, float(p._giro)), CAR_EIXO)


## O eixo, a roda, as amarras de cipó e o que está dentro.
func _draw_carrinho(mi: int, root: Node3D, nd: Dictionary) -> void:
	var p: Dictionary = plantas[mi]
	var etapa := carrinho_etapa(mi)
	var R := float((p.get("roda", {}) as Dictionary).get("r", 0.2))
	# o eixo: um galho atravessado na ponta dos braços
	if bool(p.get("eixo", false)):
		root.add_child(_stick(CAR_EIXO + Vector3(0, 0, -0.25), CAR_EIXO + Vector3(0, 0, 0.25), 0.022))
	elif etapa == "eixo":
		var ge := MeshInstance3D.new()
		var gm := CylinderMesh.new()
		gm.top_radius = 0.022
		gm.bottom_radius = 0.022
		gm.height = 0.5
		ge.mesh = gm
		ge.material_override = _ghost_mat
		ge.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), CAR_EIXO)
		root.add_child(ge)
	# a roda: a rodela de tora em pé (casca em volta, os anéis nas caras), girando no eixo
	var roda := Node3D.new()
	roda.transform = Transform3D(Basis(Vector3.BACK, float(p.get("_giro", 0.0))), CAR_EIXO)
	root.add_child(roda)
	if not (p.get("roda", {}) as Dictionary).is_empty():
		var cil := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = R
		cm.bottom_radius = R
		cm.height = 0.09
		cm.radial_segments = 26
		cil.mesh = cm
		cil.material_override = _fmat("roda_casca", Color(0.2, 0.14, 0.09), 0.95)
		cil.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
		roda.add_child(cil)
		for sg in [-1.0, 1.0]:
			var face := MeshInstance3D.new()
			var fm := CylinderMesh.new()
			fm.top_radius = R - 0.025
			fm.bottom_radius = R - 0.025
			fm.height = 0.004
			fm.radial_segments = 26
			face.mesh = fm
			face.material_override = _fmat("roda_cara", Color(0.6, 0.42, 0.26), 0.85)
			face.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, sg * 0.046))
			roda.add_child(face)
			for k in 3:
				var an := MeshInstance3D.new()
				var tm := TorusMesh.new()
				var rr := (R - 0.025) * (0.3 + 0.22 * k)
				tm.inner_radius = rr - 0.004
				tm.outer_radius = rr
				tm.rings = 22
				tm.ring_segments = 4
				an.mesh = tm
				an.material_override = _fmat("roda_anel", Color(0.38, 0.25, 0.14), 0.9)
				an.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, sg * 0.049))
				roda.add_child(an)
		nd["roda"] = roda
	elif etapa == "roda":
		var gr := MeshInstance3D.new()
		var gc := CylinderMesh.new()
		gc.top_radius = 0.2
		gc.bottom_radius = 0.2
		gc.height = 0.07
		gr.mesh = gc
		gr.material_override = _ghost_mat
		gr.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
		roda.add_child(gr)
	# as amarras de cipó: onde o fundo cruza os braços
	var pts := [Vector3(0.4, 0.245, 0.24), Vector3(0.4, 0.245, -0.24), Vector3(-0.3, 0.245, 0.24), Vector3(-0.3, 0.245, -0.24)]
	var na := int(p.get("amarras", 0))
	for k in mini(na, pts.size()):
		var am := MeshInstance3D.new()
		am.mesh = _lash_mesh()
		am.material_override = _lash_mat
		am.scale = Vector3(0.38, 0.38, 0.38)
		am.position = pts[k]
		root.add_child(am)
	if etapa != "":
		return
	# o que está dentro da caixa
	var c := car_of(mi)
	var cg: Dictionary = c.carga
	if not cg.is_empty() and float(cg.get("vol", 0.0)) > 0.0005:
		var f := clampf(float(cg.vol) / CAR_VOL, 0.0, 1.0)
		var cores := {"terra": Color(0.36, 0.25, 0.16), "argila": Color(0.62, 0.3, 0.16), "barro": Color(0.42, 0.27, 0.15),
			"areia": Color(0.85, 0.76, 0.52), "carvao": Color(0.08, 0.08, 0.085)}
		var monte := MeshInstance3D.new()
		monte.mesh = _car_monte_mesh(f, str(cg.tipo))
		monte.material_override = _fmat("car_" + str(cg.tipo), cores.get(str(cg.tipo), Color(0.4, 0.3, 0.2)), 0.95 if str(cg.tipo) != "carvao" else 0.7)
		root.add_child(monte)
	var ln: Array = c.lenhas
	for k in ln.size():
		var an2: Node3D = _arv.free_log_node(ln[k])
		root.add_child(an2)
		var fila := k % 4
		var cam := k / 4
		an2.transform = Transform3D(Basis(Vector3.UP, 0.05 * float((k * 7) % 5 - 2)), Vector3(0.04, CAR_FUNDO + 0.05 + cam * 0.09, -0.18 + fila * 0.12))
	var it: Dictionary = c.itens
	if it.has("quarto_vaca") or it.has("quarto_vaca_sujo"):
		# o quarto de vaca deitado na caixa (carne vermelha com a gordura)
		var qm := MeshInstance3D.new()
		var sq := SphereMesh.new()
		sq.radius = 0.2
		sq.height = 0.3
		qm.mesh = sq
		qm.scale = Vector3(1.7, 1.0, 1.0)
		qm.material_override = _fmat("quarto", Color(0.42, 0.06, 0.05), 0.5)
		qm.position = Vector3(0.04, CAR_FUNDO + 0.14, 0.0)
		root.add_child(qm)
	if not it.is_empty():
		# o que veio da mochila: uma trouxa no canto da caixa
		var tr := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.18
		tr.mesh = sm
		tr.material_override = _fmat("trouxa", Color(0.55, 0.47, 0.32), 0.95)
		tr.position = Vector3(-0.22, CAR_FUNDO + 0.08, 0.1)
		root.add_child(tr)


## O monte de material na caixa: liso em cima, com um morrinho no meio quando enche.
func _car_monte_mesh(f: float, tipo: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 10
	var nz := 7
	var h := 0.02 + f * 0.2
	var nzl := FastNoiseLite.new()
	nzl.seed = hash(tipo)
	nzl.frequency = 6.0 if tipo != "carvao" else 18.0
	var grid := []
	for i in nx + 1:
		var row := []
		for j in nz + 1:
			var u := float(i) / nx
			var v := float(j) / nz
			var x := lerpf(-0.355, 0.435, u)
			var z := lerpf(-0.235, 0.235, v)
			var borda := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
			var y := CAR_FUNDO + h + f * 0.06 * smoothstep(0.0, 0.5, borda) + nzl.get_noise_2d(x * 10.0, z * 10.0) * (0.012 if tipo != "carvao" else 0.025)
			row.append(Vector3(x, y, z))
		grid.append(row)
	for i in nx:
		for j in nz:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i + 1][j]
			var c2: Vector3 = grid[i + 1][j + 1]
			var d: Vector3 = grid[i][j + 1]
			for v in [a, b, c2, a, c2, d]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


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
	var fz: Dictionary = TIPOS[p.tipo].forno
	match what:
		"pedra": p["ped"] = mini(int(p.get("ped", 0)) + 1, int(fz.pedras))
		"barro":
			p["bar"] = mini(int(p.get("bar", 0)) + 1, int(fz.barro))
			p["bar_dia"] = int(_jogo.sim.elapsed_days())
		"porta": p["porta"] = 1
	_rebuild()


## O que falta agora, na ordem: "barro" (as paredes), "pedra" (encaixar), "porta", "".
func forno_etapa(mi: int) -> String:
	var p: Dictionary = plantas[mi]
	var fz: Dictionary = TIPOS[p.tipo].forno
	if int(p.get("bar", 0)) < int(fz.barro):
		return "barro"
	if int(p.get("ped", 0)) < int(fz.pedras):
		return "pedra"
	if int(p.get("porta", 0)) < int(fz.porta):
		return "porta"
	return ""


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


func forno_tirar(mi: int, max_n := 1000) -> int:
	var f := forno_st(mi)
	var n := mini(int(f.carvao), max_n)
	f.carvao = int(f.carvao) - n
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
	var nz := FastNoiseLite.new()
	nz.seed = mi + 5
	nz.frequency = 1.6
	var nz2 := FastNoiseLite.new()
	nz2.seed = mi + 19
	nz2.frequency = 7.0
	# a superfície do barro: grossa embaixo, ondulada (montes de barro batidos com a mão)
	var sup := func(th: float, ph: float) -> Vector3:
		var v := _domo(th, ph)
		var nrm := Vector3(v.x + 0.1, v.y * 0.6, v.z).normalized()
		if v.x >= FORNO_FRENTE - 0.001:
			nrm = Vector3.RIGHT
		var bojo := 0.05 * (1.0 - ph / (PI * 0.5)) + 0.02          # a base mais grossa
		var onda := nz.get_noise_3d(v.x * 2.0, v.y * 2.0, v.z * 2.0) * 0.035 + nz2.get_noise_3d(v.x * 3.0, v.y * 3.0, v.z * 3.0) * 0.012
		var tapa := sin(th * 9.0 + ph * 5.0) * 0.006                # as marcas da mão
		return v + nrm * (bojo + onda + tapa)
	if fbar > 0.0:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var NT := 48
		var NP := 16
		var lim := fbar * PI * 0.5 + 0.001
		for i in NP:
			var ph0 := float(i) / NP * PI * 0.5
			var ph1 := minf(float(i + 1) / NP * PI * 0.5, lim)
			if ph0 > lim:
				break
			for k in NT:
				var th0 := TAU * k / NT
				var th1 := TAU * (k + 1) / NT
				var tq := [th0, th1, th1, th0]
				var pq := [ph0, ph0, ph1, ph1]
				var q := []
				for j in 4:
					q.append(_domo(float(tq[j]), float(pq[j])))
				if _na_boca(q[0]) and _na_boca(q[1]) and _na_boca(q[2]) and _na_boca(q[3]):
					continue
				for idx in [0, 2, 1, 0, 3, 2]:
					var th := float(tq[idx])
					var ph := float(pq[idx])
					var v: Vector3 = sup.call(th, ph)
					var da: Vector3 = sup.call(th + 0.01, ph) - sup.call(th - 0.01, ph)
					var db: Vector3 = sup.call(th, ph + 0.01) - sup.call(th, ph - 0.01)
					var nrm: Vector3 = da.cross(db).normalized()
					if nrm.dot(Vector3(v.x + 0.1, v.y, v.z)) < 0.0:
						nrm = -nrm
					# cor: manchas mais claras (secou mais) e escuras (mais úmido), a base suja
					var tone := nz2.get_noise_3d(v.x * 6.0, v.y * 6.0, v.z * 6.0)
					var col := Color(1, 1, 1).darkened(clampf(-tone * 0.35, 0.0, 0.3)).lightened(clampf(tone * 0.25, 0.0, 0.2))
					col = col.darkened(0.25 * (1.0 - smoothstep(0.0, 0.18, v.y)))
					st.set_color(col)
					st.set_normal(nrm)
					st.set_uv(Vector2(th * 0.9, ph * 1.8))
					st.add_vertex(v)
		st.generate_tangents()
		var mi2 := MeshInstance3D.new()
		mi2.mesh = st.commit()
		var age := int(_jogo.sim.elapsed_days()) - int(p.get("bar_dia", -99))
		var stage := 1 if age < 3 else (2 if age < 6 else 3)       # (grosso: já começa meio seco)
		mi2.material_override = load("res://scripts/world/construcao.gd")._mud_material(stage)
		root.add_child(mi2)
	# as pedras encaixadas no barro (umas aparecendo, meio enterradas na parede)
	var npos := 34
	var mostra := int(round(fped * npos))
	for k in mostra:
		var th := rng.randf() * TAU
		var ph := rng.randf_range(0.05, 1.25)
		var pt := _domo(th, ph)
		if _na_boca(pt) or pt.x >= FORNO_FRENTE - 0.02:
			continue
		var surf: Vector3 = sup.call(th, ph)
		var nrm2 := (surf - Vector3(-0.1, 0, 0)).normalized()
		var sm := SphereMesh.new()
		var r := rng.randf_range(0.055, 0.095)
		sm.radius = r
		sm.height = r * rng.randf_range(1.1, 1.5)
		sm.radial_segments = 7
		sm.rings = 4
		var sn := MeshInstance3D.new()
		sn.mesh = sm
		sn.material_override = _fzm("pedra")
		sn.position = surf - nrm2 * r * 0.45                       # metade dentro do barro
		sn.rotation = Vector3(rng.randf() * 3.0, rng.randf() * 3.0, rng.randf() * 3.0)
		sn.scale = Vector3(1.0, rng.randf_range(0.7, 1.0), rng.randf_range(0.8, 1.2))
		root.add_child(sn)
	# a porta de barro: uma placa grossa e arredondada
	if int(p.get("porta", 0)) >= 1:
		var ps := SurfaceTool.new()
		ps.begin(Mesh.PRIMITIVE_TRIANGLES)
		var W := 0.3
		var Hh := 0.3
		var T := 0.07
		var N := 10
		for face in [1.0, -1.0]:
			for i in N:
				for j in N:
					var qd := []
					for e in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
						var u := lerpf(-1.0, 1.0, float(e[0]) / N)
						var w := lerpf(-1.0, 1.0, float(e[1]) / N)
						var round_ := 1.0 - u * u * 0.15 - w * w * 0.15
						var bump := nz.get_noise_2d(u * 3.0 + face, w * 3.0) * 0.012
						qd.append(Vector3(face * (T * 0.5 * round_ + bump), w * Hh, u * W))
					for idx in ([0, 1, 2, 0, 2, 3] if face > 0.0 else [0, 2, 1, 0, 3, 2]):
						ps.set_uv(Vector2((qd[idx] as Vector3).z, (qd[idx] as Vector3).y) * 2.0)
						ps.add_vertex(qd[idx])
		ps.generate_normals()
		ps.generate_tangents()
		var porta := MeshInstance3D.new()
		porta.mesh = ps.commit()
		porta.material_override = load("res://scripts/world/construcao.gd")._mud_material(2)
		root.add_child(porta)
		nd["porta"] = porta
	if fbar <= 0.0:
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
	var fum: Node3D = load("res://scripts/world/fumaca.gd").new()
	fum.position = nd.get("suspiro", Vector3(-0.8, 0.9, 0))
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
	if nd.has("porta") and is_instance_valid(nd.porta):
		if aberta:
			# a placa encostada na parede, do lado da boca
			(nd.porta as Node3D).transform = Transform3D(Basis(Vector3.UP, 0.35) * Basis(Vector3.BACK, -0.25), Vector3(FORNO_FRENTE + 0.12, 0.29, 0.5))
		else:
			# tampando a boca
			(nd.porta as Node3D).transform = Transform3D(Basis(), Vector3(FORNO_FRENTE + 0.04, 0.29, 0.0))
	var fum := forno_fumando(mi)
	if nd.has("fumaca") and is_instance_valid(nd.fumaca):
		nd.fumaca.set_emitting(fum)
	var fogo_aberto := bool(f.aceso) and aberta and float(f.t0) < 0.0
	if nd.has("chama") and is_instance_valid(nd.chama):
		(nd.chama as CPUParticles3D).emitting = fogo_aberto
		(nd.chama as CPUParticles3D).visible = fogo_aberto
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
	# carrinho da versão do cipó: agora é de pinos (o que já estava amarrado vem pregado)
	for q in plantas:
		if str(q.get("tipo", "")) == "carrinho" and (q.get("pinos", []) as Array).size() != (TIPOS.carrinho.pinos as Array).size():
			var feito := int(q.get("amarras", 0)) >= 4
			var pn := []
			for _j in TIPOS.carrinho.pinos:
				pn.append(2 if feito else 0)
			q.pinos = pn
			q.erase("amarras")
	# forno da versão de antes (porta de tábuas): a porta vira de barro
	for q in plantas:
		if str(q.get("tipo", "")) == "forno" and (q.get("pecas", []) as Array).size() > 0:
			var tinha := true
			for b in q.pecas:
				if not bool(b):
					tinha = false
			q.pecas = []
			q.sobra = []
			q.erase("madeiras")
			q["porta"] = 1 if tinha else 0
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


# ---------- fogão de barro ----------
# Estado de uso (p.fg): {lenha: [achas], aceso: bool, f: lenha queimando (em lenhas),
# bocas: [{tipo, modo ("cozinhar"/"fritar"), p, q (queimando), mexe (hora)} ou {}, ...]}

const FOGAO_Y := 0.425            # o chão do fogão (em cima do tampo e das pedras)
const FOGAO_H := 0.38             # a altura da chapa em cima do chão do fogão (a chapa fica a uns 85 cm do chão)
const FOGAO_W := 0.6              # meia largura (x)
const FOGAO_D := 0.33             # meia fundura (z); a frente é +z
const FOGAO_CAP := 5              # lenhas que cabem na boca
const FOGAO_LARG := 0.22          # a acha mais grossa que passa pela boca (m): a acha comum cabe; o toquinho inteiro não
const FOGAO_BOCAS := [Vector3(0.24, 0.0, 0.02), Vector3(-0.22, 0.0, 0.02)]
const FOGAO_R_BOCA := 0.11
const FOGAO_FOGO := Vector3(0.24, 0.0, 0.0)     # o meio da fornalha (embaixo da boca 0)


func fogao_st(mi: int) -> Dictionary:
	var p: Dictionary = plantas[mi]
	if not p.has("fg"):
		p["fg"] = {"lenha": [], "aceso": false, "f": 0.0, "bocas": [{}, {}]}
	return p.fg


## O que falta para ficar pronto: "base", "pedra", "barro" ou "".
func fogao_etapa(mi: int) -> String:
	var p: Dictionary = plantas[mi]
	var fg: Dictionary = TIPOS[p.tipo].fogao
	for b in p.pecas:
		if not bool(b):
			return "base"
	for b in p.pinos:
		if int(b) < 2:
			return "base"
	if int(p.get("ped", 0)) < int(fg.pedras):
		return "pedra"
	if int(p.get("bar", 0)) < int(fg.barro):
		return "barro"
	return ""


func fogao_por(mi: int, what: String) -> void:
	var p: Dictionary = plantas[mi]
	var fg: Dictionary = TIPOS[p.tipo].fogao
	match what:
		"pedra": p["ped"] = mini(int(p.get("ped", 0)) + 1, int(fg.pedras))
		"barro": p["bar"] = mini(int(p.get("bar", 0)) + 1, int(fg.barro))
	_rebuild()


## A grossura da acha (o lado maior da seção, m): só a fina passa pela boca do fogão.
static func acha_larg(acha: Dictionary) -> float:
	var r := 0.12
	if acha.has("cil"):
		r = maxf(float(acha.cil.get("ra", 0.12)), float(acha.cil.get("rb", 0.12)))
	if not acha.has("sec"):
		return r * 2.0
	var mx := 0.0
	for k in 6:
		var a := PI * k / 6.0
		var fx: Vector2 = Arvores.sec_faixa(acha.sec, Vector2(cos(a), sin(a)))
		mx = maxf(mx, (fx.y - fx.x) * r)
	return mx


static func acha_cabe(acha: Dictionary) -> bool:
	return acha_larg(acha) <= FOGAO_LARG


func fogao_lenha(mi: int, acha: Dictionary) -> void:
	var g := fogao_st(mi)
	(g.lenha as Array).append(acha)
	if bool(g.aceso):
		g.f = float(g.f) + 1.0
	_rebuild()


func fogao_acender(mi: int) -> void:
	var g := fogao_st(mi)
	if (g.lenha as Array).is_empty():
		return
	g.aceso = true
	g.f = float((g.lenha as Array).size())
	_rebuild()


func fogao_boca_mundo(mi: int) -> Vector3:
	return xform(mi) * Vector3(FOGAO_FOGO.x, FOGAO_Y + 0.1, FOGAO_D + 0.15)


func fogao_panela_mundo(mi: int, k: int) -> Vector3:
	var b: Vector3 = FOGAO_BOCAS[k]
	return xform(mi) * Vector3(b.x, FOGAO_Y + FOGAO_H, b.z)


## O fogo: vai queimando a lenha (horas do jogo); acabou, apaga. As bocas: a de cima da
## fornalha esquenta mais que a de trás.
func fogao_tick(mi: int, dh: float) -> void:
	var g := fogao_st(mi)
	if not bool(g.aceso):
		return
	var f := float(g.f) - dh / 0.22                 # uma lenha fina queima em uns 13 min do jogo
	var n := (g.lenha as Array).size()
	while n > 0 and f < float(n) - 1.0:
		(g.lenha as Array).pop_front()
		n -= 1
	if f <= 0.0:
		g.f = 0.0
		g.aceso = false
		g.lenha = []
		_rebuild()
		return
	g.f = f


func fogao_calor(mi: int, k: int) -> float:
	var g := fogao_st(mi)
	if not bool(g.aceso):
		return 0.0
	var forte := clampf(0.6 + float(g.f) * 0.15, 0.6, 1.4)
	return forte * (1.0 if k == 0 else 0.6)


static var _barro_mat: StandardMaterial3D = null

static func _barro_m() -> StandardMaterial3D:
	if _barro_mat == null:
		_barro_mat = StandardMaterial3D.new()
		_barro_mat.albedo_color = Color(0.46, 0.3, 0.2)
		_barro_mat.roughness = 1.0
		_barro_mat.metallic_specular = 0.05
		_barro_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		# o barro alisado à mão: manchas e marcas (textura de ruído)
		var nt := NoiseTexture2D.new()
		var fn := FastNoiseLite.new()
		fn.frequency = 0.05
		nt.noise = fn
		nt.width = 128
		nt.height = 128
		nt.seamless = true
		var gtx := Gradient.new()
		gtx.colors = PackedColorArray([Color(0.86, 0.82, 0.78), Color(1.0, 1.0, 1.0), Color(1.04, 1.0, 0.97)])
		gtx.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		nt.color_ramp = gtx
		_barro_mat.albedo_texture = nt
		_barro_mat.uv1_triplanar = true
		_barro_mat.uv1_scale = Vector3(1.6, 1.6, 1.6)
	return _barro_mat


## Uma caixa (no SurfaceTool), de mn a mx.
static func _cx(st: SurfaceTool, mn: Vector3, mx: Vector3) -> void:
	var c := (mn + mx) * 0.5
	var e := (mx - mn) * 0.5
	for f in [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.BACK, Vector3.UP], [Vector3.UP, Vector3.BACK, Vector3.RIGHT],
			[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK], [Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := c + n * e
		var uu := u * e
		var vv := v * e
		var q := [o - uu - vv, o + uu - vv, o + uu + vv, o - uu + vv]
		for t in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.add_vertex(q[t])


## O fogão: as pedras (até onde foram postas), o barro subindo (paredes, chapa com as
## duas bocas, chaminé), a boca de fogo escura na frente, a lenha, o fogo e a fumaça.
func _draw_fogao(mi: int, root: Node3D, nd: Dictionary) -> void:
	var p: Dictionary = plantas[mi]
	var fg: Dictionary = TIPOS[p.tipo].fogao
	var nped := int(p.get("ped", 0))
	var fbar := float(p.get("bar", 0)) / float(fg.barro)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + mi
	var y0 := FOGAO_Y - 0.03
	# as pedras: o chão do fogão e o forro da fornalha (embaixo da boca 0), em fileira
	for k in nped:
		var a := float(k) / float(fg.pedras)
		var pos := Vector3(lerpf(-0.48, 0.48, fmod(a * 2.0, 1.0)), y0 + 0.02, -0.16 if k % 2 == 0 else 0.16)
		var pm := SphereMesh.new()
		var r := rng.randf_range(0.07, 0.1)
		pm.radius = r
		pm.height = r * 1.2
		pm.radial_segments = 7
		pm.rings = 4
		var pd := MeshInstance3D.new()
		pd.mesh = pm
		pd.material_override = _fzm("pedra")
		pd.position = pos
		pd.rotation = Vector3(rng.randf(), rng.randf() * 3.0, rng.randf())
		root.add_child(pd)
	if fbar <= 0.0:
		return
	# o barro: as paredes subindo; com tudo, a chapa (com as bocas) e a chaminé
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := FOGAO_H * minf(1.0, fbar * 1.25)
	var t := 0.06
	var yb := y0
	var yt := y0 + hw
	_cx(st, Vector3(-FOGAO_W, yb, -FOGAO_D), Vector3(-FOGAO_W + t, yt, FOGAO_D))        # parede esquerda
	_cx(st, Vector3(FOGAO_W - t, yb, -FOGAO_D), Vector3(FOGAO_W, yt, FOGAO_D))          # parede direita
	_cx(st, Vector3(-FOGAO_W, yb, -FOGAO_D), Vector3(FOGAO_W, yt, -FOGAO_D + t))        # fundo
	# a frente, com a boca de fogo (embaixo da boca 0)
	var bx0 := FOGAO_FOGO.x - 0.13
	var bx1 := FOGAO_FOGO.x + 0.13
	var by1 := minf(yt, y0 + 0.2)
	_cx(st, Vector3(-FOGAO_W, yb, FOGAO_D - t), Vector3(bx0, yt, FOGAO_D))
	_cx(st, Vector3(bx1, yb, FOGAO_D - t), Vector3(FOGAO_W, yt, FOGAO_D))
	if yt > by1:
		_cx(st, Vector3(bx0, by1, FOGAO_D - t), Vector3(bx1, yt, FOGAO_D))
	# a parede de dentro que separa a fornalha (o fogo fica só embaixo da boca 0)
	_cx(st, Vector3(-0.02, yb, -FOGAO_D), Vector3(0.03, yt, FOGAO_D))
	if fbar >= 1.0:
		# a chapa de barro, furada nas duas bocas (quadradinhos fora dos furos)
		var cel := 0.04
		var nx := int(FOGAO_W * 2.0 / cel)
		var nz := int(FOGAO_D * 2.0 / cel)
		for i in nx:
			for j in nz:
				var x0 := -FOGAO_W + i * cel
				var z0 := -FOGAO_D + j * cel
				var cc := Vector3(x0 + cel * 0.5, 0, z0 + cel * 0.5)
				var fura := false
				for b in FOGAO_BOCAS:
					if Vector2(cc.x - (b as Vector3).x, cc.z - (b as Vector3).z).length() < FOGAO_R_BOCA:
						fura = true
				if fura:
					continue
				_cx(st, Vector3(x0, yt, z0), Vector3(x0 + cel, yt + 0.05, z0 + cel))
		# a chaminé atrás, à esquerda
		_cx(st, Vector3(-FOGAO_W + 0.02, yt, -FOGAO_D + 0.02), Vector3(-FOGAO_W + 0.18, yt + 0.62, -FOGAO_D + 0.18))
	var bm := MeshInstance3D.new()
	bm.mesh = st.commit()
	bm.material_override = _barro_m()
	root.add_child(bm)
	# a boca de fogo escura e o fundo das bocas de panela (o escuro de dentro)
	var bq := MeshInstance3D.new()
	var bqm := QuadMesh.new()
	bqm.size = Vector2(0.26, by1 - yb)
	bq.mesh = bqm
	bq.material_override = _fzm("escuro")
	bq.position = Vector3(FOGAO_FOGO.x, (yb + by1) * 0.5, -FOGAO_D + t + 0.01)     # o fundo da fornalha (escuro)
	root.add_child(bq)
	# as paredes de dentro da fornalha (escuras de fuligem)
	for sx in [-1.0, 1.0]:
		var pq := MeshInstance3D.new()
		var pqm := QuadMesh.new()
		pqm.size = Vector2(FOGAO_D * 2.0 - t * 2.0, by1 - yb)
		pq.mesh = pqm
		pq.material_override = _fzm("escuro")
		pq.rotation.y = PI * 0.5
		pq.position = Vector3(FOGAO_FOGO.x + sx * 0.13, (yb + by1) * 0.5, 0.0)
		root.add_child(pq)
	if fbar < 1.0:
		return
	for b in FOGAO_BOCAS:
		var fd := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = FOGAO_R_BOCA
		cm.bottom_radius = FOGAO_R_BOCA
		cm.height = 0.01
		cm.radial_segments = 16
		fd.mesh = cm
		fd.material_override = _fzm("escuro")
		fd.position = Vector3((b as Vector3).x, yt + 0.005, (b as Vector3).z)
		root.add_child(fd)
	var g := fogao_st(mi)
	# a lenha na fornalha (as mesmas achas, deitadas apontando para a boca)
	var ach: Array = g.lenha
	for k in ach.size():
		var ln: Node3D = _arv.free_log_node(ach[k])
		ln.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, float(k) * 1.3),
			Vector3(FOGAO_FOGO.x + (k % 3 - 1) * 0.07, y0 + 0.05 + (k / 3) * 0.05, -0.02))
		root.add_child(ln)
	# o fogo (aceso) e a luz
	var chama := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.12, 0.16)
	chama.mesh = qm
	chama.material_override = _fzm("fogo")
	chama.amount = 22
	chama.lifetime = 0.5
	chama.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	chama.emission_box_extents = Vector3(0.1, 0.03, 0.2)
	chama.direction = Vector3.UP
	chama.spread = 15.0
	chama.gravity = Vector3(0, 1.0, 0)
	chama.initial_velocity_min = 0.15
	chama.initial_velocity_max = 0.4
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.85, 0.35, 0.95), Color(1.0, 0.45, 0.08, 0.8), Color(0.6, 0.1, 0.02, 0.0)])
	chama.color_ramp = grad
	chama.position = Vector3(FOGAO_FOGO.x, y0 + 0.08, 0.0)
	root.add_child(chama)
	nd["chama"] = chama
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.55, 0.2)
	luz.light_energy = 1.2
	luz.omni_range = 3.0
	luz.position = Vector3(FOGAO_FOGO.x, y0 + 0.15, FOGAO_D + 0.3)
	root.add_child(luz)
	nd["luz"] = luz
	# a brasa no chão da fornalha (brilha com o fogo)
	var br := MeshInstance3D.new()
	var brm := BoxMesh.new()
	brm.size = Vector3(0.22, 0.02, FOGAO_D * 1.6)
	br.mesh = brm
	br.material_override = _fzm("brasa")
	br.position = Vector3(FOGAO_FOGO.x, y0 + 0.02, 0.0)
	root.add_child(br)
	nd["brasa"] = br
	var fum: Node3D = load("res://scripts/world/fumaca.gd").new()
	fum.position = Vector3(-FOGAO_W + 0.1, yt + 0.66, -FOGAO_D + 0.1)
	root.add_child(fum)
	nd["fumaca"] = fum
	fogao_visual(mi, nd)


func fogao_visual(mi: int, nd := {}) -> void:
	if nd.is_empty():
		if not _nodes.has(mi):
			return
		nd = _nodes[mi]
	if not pronta(mi):
		return
	var aceso := bool(fogao_st(mi).aceso)
	if nd.has("chama") and is_instance_valid(nd.chama):
		(nd.chama as CPUParticles3D).emitting = aceso
		(nd.chama as CPUParticles3D).visible = aceso
	if nd.has("luz") and is_instance_valid(nd.luz):
		(nd.luz as OmniLight3D).visible = aceso
	if nd.has("brasa") and is_instance_valid(nd.brasa):
		(nd.brasa as Node3D).visible = aceso
	if nd.has("fumaca") and is_instance_valid(nd.fumaca):
		nd.fumaca.set_emitting(aceso)

