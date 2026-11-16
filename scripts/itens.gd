extends RefCounted
## Itens do jogo e receitas de craft.
##
## Cada item tem nome, peso (kg por unidade), categoria e uma descrição curta.
## As receitas "de mão" são poucas: o craft de verdade vai ser feito nas bancadas.

const ITENS := {
	"machado": {"nome": "Machado de Pedra", "kg": 1.6, "cat": "Ferramentas",
		"desc": "Corta árvores. Equipe na mochila e chegue perto do tronco.", "ferramenta": true},
	"argila": {"nome": "Argila", "kg": 1.0, "cat": "Recursos", "desc": "Barro da beira das lagoas."},
	"semente": {"nome": "Semente de Cedrinho", "kg": 0.002, "cat": "Recursos", "desc": "Plante em terra boa: brota em uns 100 dias."},
	"pedra": {"nome": "Pedra", "kg": 0.8, "cat": "Recursos", "desc": "Pedra lascada, boa para ferramentas."},
	"galho": {"nome": "Galho", "kg": 0.5, "cat": "Recursos", "desc": "Galho reto e firme."},
	"cipo": {"nome": "Cipó", "kg": 0.1, "cat": "Recursos", "desc": "Serve de corda para amarrar."},
}

const CATEGORIAS := ["Tudo", "Armas", "Munição", "Equipamentos", "Ferramentas", "Construção", "Recursos", "Itens Médicos", "Diversos"]

## Receitas que dá para fazer com as mãos (sem bancada).
const RECEITAS_MAO := [
	{"id": "machado", "qtd": 1, "ingredientes": [["pedra", 2], ["galho", 1], ["cipo", 2]]},
]


static func nome(id: String) -> String:
	return str(ITENS.get(id, {}).get("nome", id))


static func kg(id: String) -> float:
	return float(ITENS.get(id, {}).get("kg", 0.0))


static func kg_txt(v: float) -> String:
	if v < 0.1 and v > 0.0:
		return ("%.3f" % v).replace(".", ",")
	return ("%.1f" % v).replace(".", ",")
