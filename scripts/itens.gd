extends RefCounted
## Itens do jogo e receitas de craft.
##
## Cada item tem nome, peso (kg por unidade), categoria e uma descrição curta.
## As receitas "de mão" são poucas: o craft de verdade vai ser feito nas bancadas.

const ITENS := {
	"machado": {"nome": "Machado de Pedra", "kg": 1.6, "cat": "Ferramentas",
		"desc": "Corta árvores. Equipe na mochila e chegue perto do tronco.", "ferramenta": true, "dur": 400},
	"cavadeira": {"nome": "Cavadeira de Pedra", "kg": 2.2, "cat": "Ferramentas",
		"desc": "Cava buracos em qualquer lugar. Cavando no mesmo lugar o buraco fica mais fundo.", "ferramenta": true, "dur": 300},
	"serra": {"nome": "Serra de Pedra", "kg": 1.4, "cat": "Ferramentas",
		"desc": "Lâmina de pedra com dentes amarrada num cabo comprido, com pegador nas duas pontas. Corta devagar e gasta rápido, mas tira peças finas da tora (a rodela) que o machado não consegue.",
		"ferramenta": true, "dur": 120},
	"lamina_serra": {"nome": "Lâmina de Serra", "kg": 0.4, "cat": "Recursos",
		"desc": "Pedra trabalhada, comprida e fina, com dentes lascados num lado. Vai ser feita na mesa de trabalhar pedra."},
	"pedra_machado": {"nome": "Pedra de Machado", "kg": 0.9, "cat": "Recursos",
		"desc": "Pedra trabalhada com fio, do formato da cabeça do machado. Vai ser feita na mesa de trabalhar pedra."},
	"pedra_cavadeira": {"nome": "Lâmina de Cavadeira", "kg": 1.0, "cat": "Recursos",
		"desc": "Pedra trabalhada larga e chata, como uma pá. Vai ser feita na mesa de trabalhar pedra."},
	"forquilha": {"nome": "Forquilha", "kg": 1.2, "cat": "Construção",
		"desc": "Cavalete em X de galhos amarrados com cipó. COLOCAR põe no chão onde você escolher; duas forquilhas seguram uma tora para trabalhar.", "colocar": true},
	"argila": {"nome": "Argila", "kg": 1.0, "cat": "Recursos", "desc": "Barro da beira das lagoas."},
	"semente": {"nome": "Semente de Cedrinho", "kg": 0.002, "cat": "Recursos", "desc": "Plante em terra boa: brota em uns 100 dias."},
	"pedra": {"nome": "Pedra", "kg": 0.8, "cat": "Recursos", "desc": "Pedra solta do chão. USAR põe ela na mão: perto de outra pedra no chão dá para bater e modelar as pedras das ferramentas."},
	"galho": {"nome": "Galho", "kg": 0.5, "cat": "Recursos", "desc": "Galho reto e firme."},
	"cipo": {"nome": "Cipó-titica", "kg": 0.15, "cat": "Recursos", "desc": "Raiz aérea da titica: forte e flexível. Serve para amarrar, cestos e cordas."},
	"cipo_trancado": {"nome": "Cipó Trançado", "kg": 0.4, "cat": "Recursos",
		"desc": "Três raízes de titica trançadas: bem mais forte. É a alça do balde e vai servir para muitas outras coisas."},
	"rodela": {"nome": "Rodela", "kg": 2.5, "cat": "Recursos",
		"desc": "Fatia fina cortada da ponta da tora apoiada nas forquilhas. É o fundo do balde."},
	"ripa": {"nome": "Ripa", "kg": 0.4, "cat": "Recursos",
		"desc": "Tábua fina lascada da tora. Vai sair da tora apoiada nas forquilhas, com ferramentas que ainda vão chegar."},
	"balde": {"nome": "Balde de Madeira", "kg": 2.8, "cat": "Equipamentos",
		"desc": "Ripas em volta de um fundo redondo, apertadas com aros de cipó. Alça de cipó trançado.", "colocar": true},
}

const CATEGORIAS := ["Tudo", "Armas", "Munição", "Equipamentos", "Ferramentas", "Construção", "Recursos", "Itens Médicos", "Diversos"]

## Receitas que dá para fazer com as mãos (sem bancada).
const RECEITAS_MAO := [
	{"id": "machado", "qtd": 1, "ingredientes": [["pedra_machado", 1], ["galho", 1], ["cipo", 2]]},
	{"id": "cavadeira", "qtd": 1, "ingredientes": [["pedra_cavadeira", 1], ["galho", 1], ["cipo", 3]]},
	{"id": "serra", "qtd": 1, "ingredientes": [["lamina_serra", 1], ["galho", 1], ["cipo", 1]]},
	{"id": "forquilha", "qtd": 1, "ingredientes": [["galho", 2], ["cipo", 2]]},
	{"id": "cipo_trancado", "qtd": 1, "ingredientes": [["cipo", 3]]},
	{"id": "balde", "qtd": 1, "ingredientes": [["ripa", 12], ["rodela", 1], ["cipo", 6], ["cipo_trancado", 1]]},
]


## Dá para pôr no chão escolhendo o lugar (com a prévia transparente)?
static func colocavel(id: String) -> bool:
	return bool(ITENS.get(id, {}).get("colocar", false))


## Quantos usos a ferramenta aguenta (0 = não gasta).
static func dur_max(id: String) -> int:
	return int(ITENS.get(id, {}).get("dur", 0))


static func nome(id: String) -> String:
	return str(ITENS.get(id, {}).get("nome", id))


static func kg(id: String) -> float:
	return float(ITENS.get(id, {}).get("kg", 0.0))


static func kg_txt(v: float) -> String:
	if v < 0.1 and v > 0.0:
		return ("%.3f" % v).replace(".", ",")
	return ("%.1f" % v).replace(".", ",")
