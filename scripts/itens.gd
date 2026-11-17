extends RefCounted
## Itens do jogo e receitas de craft.
##
## Cada item tem nome, peso (kg por unidade), categoria e uma descrição curta.
## As receitas "de mão" são poucas: o craft de verdade vai ser feito nas bancadas.

const ITENS := {
	"machado": {"nome": "Machado de Pedra", "kg": 1.6, "cat": "Ferramentas",
		"desc": "Corta árvores. Equipe na mochila e chegue perto do tronco.", "ferramenta": true},
	"cavadeira": {"nome": "Cavadeira de Pedra", "kg": 2.2, "cat": "Ferramentas",
		"desc": "Cava buracos em qualquer lugar. Cavando no mesmo lugar o buraco fica mais fundo.", "ferramenta": true},
	"forquilha": {"nome": "Forquilha", "kg": 1.2, "cat": "Construção",
		"desc": "Cavalete em X de galhos amarrados com cipó. COLOCAR põe no chão onde você escolher; duas forquilhas seguram uma tora para trabalhar.", "colocar": true},
	"argila": {"nome": "Argila", "kg": 1.0, "cat": "Recursos", "desc": "Barro da beira das lagoas."},
	"semente": {"nome": "Semente de Cedrinho", "kg": 0.002, "cat": "Recursos", "desc": "Plante em terra boa: brota em uns 100 dias."},
	"pedra": {"nome": "Pedra", "kg": 0.8, "cat": "Recursos", "desc": "Pedra lascada, boa para ferramentas."},
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
	{"id": "machado", "qtd": 1, "ingredientes": [["pedra", 2], ["galho", 1], ["cipo", 2]]},
	{"id": "cavadeira", "qtd": 1, "ingredientes": [["pedra", 1], ["galho", 1], ["cipo", 3]]},
	{"id": "forquilha", "qtd": 1, "ingredientes": [["galho", 2], ["cipo", 2]]},
	{"id": "cipo_trancado", "qtd": 1, "ingredientes": [["cipo", 3]]},
	{"id": "balde", "qtd": 1, "ingredientes": [["ripa", 12], ["rodela", 1], ["cipo", 6], ["cipo_trancado", 1]]},
]


## Dá para pôr no chão escolhendo o lugar (com a prévia transparente)?
static func colocavel(id: String) -> bool:
	return bool(ITENS.get(id, {}).get("colocar", false))


static func nome(id: String) -> String:
	return str(ITENS.get(id, {}).get("nome", id))


static func kg(id: String) -> float:
	return float(ITENS.get(id, {}).get("kg", 0.0))


static func kg_txt(v: float) -> String:
	if v < 0.1 and v > 0.0:
		return ("%.3f" % v).replace(".", ",")
	return ("%.1f" % v).replace(".", ",")
