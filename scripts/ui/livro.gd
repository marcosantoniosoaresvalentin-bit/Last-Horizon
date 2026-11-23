extends Control
## O Livro do Sobrevivente: ensina o jogo todo (os controles, o corpo, a água e a comida, o
## fogo, a madeira, as ferramentas, o barro, as plantas das máquinas, a caça e o abate, a
## cozinha e como a natureza funciona). Abre sozinho na primeira vez que o jogo é aberto e
## depois pelas Configurações. Um livro aberto: à esquerda o título e os desenhos, à direita
## o texto; vira a página pelas setas ou arrastando o dedo para o lado.

signal fechou

const Desenhos := preload("res://scripts/ui/desenhos.gd")

const C_PAPEL := Color(0.93, 0.88, 0.76)
const C_PAPEL2 := Color(0.89, 0.83, 0.69)
const C_TINTA := Color(0.17, 0.11, 0.06)
const C_TINTA2 := Color(0.38, 0.27, 0.16)
const C_CAPA := Color(0.28, 0.17, 0.09)
const C_DESTAQUE := Color(0.55, 0.22, 0.1)

## Capítulos: {t: título, ic: ícone do índice, pags: [{t, ic: [desenhos], x: texto]}
const CAPITULOS := [
	{"t": "Bem-vindo à mata", "ic": "machado", "pags": [
		{"t": "Last Horizon", "ic": ["machado", "faca", "arco"], "x": "Você está sozinho numa ilha coberta de mata amazônica. Não tem nada além das mãos: tudo o que vai usar, vai ter que achar, cortar, lascar, trançar e construir.\n\nEste livro ensina como sobreviver e como o mundo funciona. Ele fica sempre com você: abra pelas [b]Configurações[/b] quando quiser.\n\nVá com calma. A mata é grande, o tempo passa (dias, meses, estações) e cada coisa tem o seu jeito certo de fazer."},
		{"t": "Os controles", "ic": [], "x": "[b]Andar:[/b] o dedo no lado esquerdo da tela (o direcional).\n[b]Olhar:[/b] arraste o dedo no lado direito.\n[b]Pular:[/b] o botão Pular.\n\n[b]O botão de ação[/b] aparece sozinho quando tem alguma coisa para fazer ali perto: Pegar galho, Pegar pedra, Beber água, Pegar tora... é só tocar.\n\n[b]O olho:[/b] perto de uma máquina, da fogueira, do fogão, de uma árvore que dá para trabalhar, aparece um olho. Tocando nele abrem as opções do que dá para fazer ali.\n\n[b]Em cima:[/b] as Plantas (projetos de máquinas), o Craft (fazer coisas com as mãos), a Mochila e o Calendário."},
		{"t": "Quando dá errado", "ic": [], "x": "Quando você tenta uma coisa e não dá, aparece uma mensagem dizendo [b]por quê[/b]: falta um material, a lenha é grossa demais, a mochila está cheia, precisa de uma ferramenta...\n\nLeia a mensagem: ela diz o que falta.\n\n[b]A mochila[/b] tem um limite de peso. Coisas grandes (toras, lenha, carne em peças grandes) não vão na mochila: vão no ombro, nas costas, arrastadas ou no carrinho de mão."},
	]},
	{"t": "O seu corpo", "ic": "goiaba", "pags": [
		{"t": "Vida, fome e sede", "ic": ["goiaba", "moringa_limpa"], "x": "No canto de cima estão as três barras: [b]vida[/b] (vermelha), [b]fome[/b] (laranja) e [b]sede[/b] (azul).\n\nA fome e a sede vão caindo com o tempo. Quando zeram, a vida começa a cair. Vida zerada: você morre e acorda de novo no começo da ilha, sem nada (o que tinha fica onde você caiu).\n\nComer: na Mochila, escolha a comida e toque em [b]USAR[/b]."},
		{"t": "Água", "ic": ["moringa_barro", "moringa_agua", "moringa_limpa"], "x": "Na beira de um rio, lagoa ou nascente aparece [b]Beber água[/b] (com a mão). Mata a sede, mas a água sem filtrar pode ter bactérias e dar doença (dor de barriga, enjoo, febre).\n\nDa água do mar: nunca. É salgada.\n\nMelhor: a [b]cabaça de barro[/b] (moringa) cheia de água e a [b]peneira de água[/b] (o filtro, nas Plantas) para tirar a sujeira. Água filtrada é segura."},
		{"t": "Doença e remédios", "ic": ["folha_goiabeira", "cha_goiabeira", "taia", "remedio_cobra"], "x": "[b]Chá de folha de goiabeira:[/b] na fogueira acesa, com 3 folhas de goiabeira, uma vasilha de barro e água na cabaça. Acalma a barriga depois de água ruim.\n\n[b]Picada de cobra:[/b] a jararaca vive no chão da mata. Picou, o veneno vai fazendo efeito. O remédio sai da [b]jararaca-taia[/b], a planta da sombra com o talo pintado igual pele de cobra: arranque a batata e, no craft, 2 batatas viram o remédio. Tome logo (USAR)."},
	]},
	{"t": "Coletar", "ic": "galho", "pags": [
		{"t": "O que tem no chão", "ic": ["galho", "pedra", "capim_seco", "cipo"], "x": "Andando pela mata você acha:\n\n[b]Galhos[/b] caídos (o começo de quase toda ferramenta).\n[b]Pedras[/b] soltas.\n[b]Capim seco[/b]: colha as touceiras de capim alto quando secam (no fim do mês). É a isca do fogo e a liga do barro.\n[b]Cipó-titica:[/b] as raízes aéreas que descem das árvores. Serve para amarrar tudo.\n\nFrutas: goiaba, bacaba e buriti na época de cada uma (veja o Calendário)."},
		{"t": "Palmeiras", "ic": ["folha_buriti", "talo_buriti", "fibra_buriti", "folha_babacu", "coco_babacu"], "x": "[b]Buriti:[/b] a palmeira grande das áreas molhadas. Com a faca, pelo olho, corta a folha em leque (palha) e o talo comprido. O talo vira fibra na desfibradeira, e a fibra vira tela e corda.\n\n[b]Babaçu:[/b] as folhas verdes se cortam com o machado (forram o chão do tripé onde a carne cai). Na época dá os cachos de coco.\n\nDá também para derrubar o buriti com o machado: o tronco vira tora."},
		{"t": "Ervas da mata", "ic": ["raiz_timbo", "veneno_timbo", "semente_andiroba", "oleo_andiroba"], "x": "[b]Timbó:[/b] a raiz amassada vira veneno. Passado na madeira, mata os cupins que estão nela (dura uns 45 dias).\n\n[b]Andiroba:[/b] as sementes caídas viram óleo (6 sementes no craft). Passado na madeira, espanta os cupins por uns 2 anos.\n\nOs [b]cupins[/b] comem a madeira das construções com o tempo: proteja a madeira."},
	]},
	{"t": "Pedra e ferramentas", "ic": "pedra_machado", "pags": [
		{"t": "Modelar pedra", "ic": ["pedra", "pedra_machado", "lamina_faca", "lamina_serra"], "x": "As ferramentas começam pela pedra. Pegue uma pedra e USE ela (fica na mão). Perto de outra pedra no chão aparece [b]Modelar pedra[/b]: escolha o que fazer e bata com cuidado nos pontos marcados, no tempo certo (no verde). Bater errado quebra a pedra.\n\nSaem assim: a pedra do machado, a lâmina da faca, da serra, da pá, da enxada, da cavadeira, a pedra da marreta, as cunhas, a ponta do furador..."},
		{"t": "Montar as ferramentas", "ic": ["machado", "faca", "serra", "pa", "enxada", "marreta"], "x": "No [b]Craft[/b] a pedra trabalhada vira ferramenta, presa num galho com cipó:\n\n[b]Machado:[/b] pedra de machado + galho + 2 cipós.\n[b]Faca:[/b] lâmina de faca + galho + cipó.\n[b]Serra, pá, enxada, cavadeira, marreta:[/b] cada uma com a sua pedra, galho e cipó.\n\nAs ferramentas gastam com o uso e quebram: veja o desgaste na mochila e faça outra antes."},
		{"t": "Outras coisas do craft", "ic": ["forquilha", "cipo_trancado", "vareta", "arco_fogo", "espeto"], "x": "[b]Forquilha:[/b] 2 galhos + 2 cipós (o cavalete para apoiar toras).\n[b]Cipó trançado:[/b] 3 cipós.\n[b]Vareta:[/b] 1 galho. [b]Espeto:[/b] 1 vareta (com a faca na mochila).\n[b]Arco de fogo:[/b] galho + 2 cipós.\n[b]Arco[/b] (de caça): vareta + cipó trançado. [b]Flecha:[/b] vareta + pedra + cipó.\n[b]Pinos:[/b] lascados das ripas. [b]Balde:[/b] 12 ripas + 1 rodela + cipós."},
	]},
	{"t": "Madeira", "ic": "tabua", "pags": [
		{"t": "Derrubar e cortar", "ic": ["machado", "galho"], "x": "Com o [b]machado[/b] na mão (Mochila → Equipar), chegue numa árvore: as machadadas vão cortando o pé até ela cair.\n\nCaída, corte os galhos e depois corte o tronco em [b]toras[/b] do tamanho que quiser. Tora leve vai no ombro; pesada vai arrastada; muito pesada não sai: corte menor.\n\nAs árvores crescem com o tempo, e dá para plantar sementes de cedrinho em terra boa."},
		{"t": "Trabalhar a tora", "ic": ["forquilha", "cunha", "marreta", "serra", "tabua"], "x": "Ponha duas [b]forquilhas[/b] no chão e apoie a tora nelas. Pelo olho ([b]Trabalhar[/b]):\n\n[b]Cortar rodela:[/b] a fatia fina da ponta (fundo do balde, roda do carrinho).\n[b]Cortar toquinho:[/b] um pedaço de 25 cm para rachar lenha.\n[b]Rachar ao meio:[/b] com 3 cunhas e a marreta, abre a tora no comprido. Rachando de novo saem as tábuas.\n\nA tábua pequena, rachada com o machado, dá as [b]ripas[/b]; das ripas saem os pinos."},
		{"t": "O cepo e a lenha", "ic": ["machado", "lenha"], "x": "Finque uma tora grossa e baixa num buraco: é o [b]cepo[/b].\n\nPonha o toquinho em pé em cima dele ([b]Pôr no cepo[/b]) e, com o machado, escolha onde rachar (o risco vermelho) e dê as machadadas. Os dois pedaços caem para os lados. Rache de novo: em 4, em 8...\n\nA lenha vai [b]na mão[/b] (não na mochila): leve até a fogueira, o forno ou o fogão. Para muita lenha, use o carrinho de mão."},
	]},
	{"t": "Fogo", "ic": "arco_fogo", "pags": [
		{"t": "Fazer fogo", "ic": ["arco_fogo", "vareta", "ripa", "capim_seco"], "x": "Precisa: [b]arco de fogo[/b], uma [b]vareta[/b], uma [b]ripa[/b] (a base) e [b]capim seco[/b]. Na chuva o fogo não pega.\n\nUSE o arco de fogo. Passe o dedo para os lados, rápido, indo e voltando: a vareta gira e esquenta. Com a barra cheia cai a brasa no capim: toque em [b]Soprar[/b] umas vezes e o fogo pega.\n\nPonha lenha logo: o capim sozinho queima pouco."},
		{"t": "A fogueira", "ic": ["lenha", "carvao"], "x": "Pelo olho da fogueira: [b]Pôr lenha[/b] (com a lenha na mão), Acender, Pôr capim na brasa.\n\nMais lenha, fogo mais forte e mais tempo queimando (mas fogo forte gasta mais depressa). Parou de pôr lenha, vai baixando e apaga. Fica a brasa por uns minutos: com capim seco, o fogo volta sem o arco. Fria, a cinza tem [b]carvão[/b].\n\nA chuva apaga o fogo e a brasa."},
		{"t": "Forno de carvão", "ic": ["carvao", "balde"], "x": "O forno de barro (nas Plantas) transforma lenha em carvão: encha de lenha (12), acenda com o arco de fogo na boca e [b]feche a porta[/b] de barro. Sem ar, a lenha vira carvão devagar: de perto, o relógio mostra quanto falta.\n\nPronto, abra a porta e pegue o carvão com o balde. O carvão vai na peneira de água."},
	]},
	{"t": "Barro e cerâmica", "ic": "vasilha_barro", "pags": [
		{"t": "Argila", "ic": ["pa", "balde", "argila", "argila_limpa"], "x": "Na beira das lagoas o chão tem [b]argila[/b]. Com a pá e o balde na mão, cave e encha o balde.\n\nDespeje na [b]mesa de argila[/b] (nas Plantas) e escolha Limpar: tire as pedrinhas, raízes e folhas tocando nos losangos. Sai a [b]argila limpa[/b], em bolas, pronta para modelar."},
		{"t": "O torno", "ic": ["vasilha_barro", "bacia_barro", "moringa_barro", "garrafa_barro", "filtro_barro"], "x": "No [b]torno de oleiro[/b] (de pedal), com argila limpa: sente, pise no pedal para a mesa girar e modele a peça.\n\nSaem: a [b]vasilha[/b] (comida, carne picada), a [b]bacia[/b], a [b]cabaça[/b] (moringa, para água), a [b]garrafa[/b] e o [b]filtro de barro[/b]."},
		{"t": "Barro de construir", "ic": ["enxada", "capim_seco", "balde"], "x": "Para paredes, forno e fogão: o [b]barro[/b] (não a argila). No [b]barreiro[/b]: abra a cova na terra, jogue água, ponha capim seco e misture com a enxada.\n\nPronto, encha o balde vazio de barro e leve até a obra: rebocar paredes, levantar o forno, o fogão."},
	]},
	{"t": "Água limpa", "ic": "moringa_limpa", "pags": [
		{"t": "A peneira de água", "ic": ["pedra", "carvao", "tela_fibra", "vasilha_barro"], "x": "A peneira (nas Plantas) limpa a água em camadas, na ordem pelo olho:\n\n1. [b]Pedrinhas[/b] (6 pedras do chão)\n2. [b]Carvão[/b] (3, da fogueira)\n3. [b]Areia[/b] (um balde de areia da praia)\n4. A [b]tela de fibra[/b] (craft, 6 fibras de buriti)\n\nEmbaixo vai a vasilha ou a bacia de barro. Jogue a água do balde em cima: ela passa devagar pelas camadas e pinga limpa embaixo. Depois, [b]Encher a cabaça[/b]."},
	]},
	{"t": "Plantas e máquinas", "ic": "pino", "pags": [
		{"t": "Como construir uma planta", "ic": ["pino", "marreta", "furador"], "x": "Abra as [b]Plantas[/b] (em cima) e escolha a máquina: o desenho dela aparece no chão, azul. Gire e ponha onde quiser.\n\nTraga as madeiras que a planta pede (toras, meias, tábuas): perto da planta aparece [b]Pôr na planta[/b] e cada peça vai para o seu lugar.\n\nDepois [b]fure[/b] (com o furador) e bata os [b]pinos[/b] (com a marreta) onde as madeiras se cruzam. Algumas pedem ainda lâminas, cipó, pedras ou barro."},
		{"t": "As máquinas", "ic": ["serra", "fibra_buriti", "corda_10", "balde"], "x": "[b]Serra de pedal:[/b] serra toras em tábuas, a dois.\n[b]Desfibradeira:[/b] tira a fibra do talo do buriti.\n[b]Cavalete de trançar:[/b] trança a fibra em corda.\n[b]Mesa de argila[/b] e [b]torno:[/b] a cerâmica.\n[b]Peneira de água[/b] e [b]forno de carvão.[/b]\n[b]Carrinho de mão:[/b] leva lenha, baldes, carne e coisas pesadas.\n[b]Tripé de içar[/b] e [b]mesa de carne:[/b] o abate.\n[b]Fogão de barro:[/b] cozinhar e fritar."},
	]},
	{"t": "Caça", "ic": "arco", "pags": [
		{"t": "Os bichos", "ic": ["arco", "flecha", "laco_10"], "x": "Na ilha vivem araras, macacos, tamanduás, cobras e um gado asselvajado (vacas, touros e bezerros) que vive em rebanhos nos pastos.\n\nOs bichos fogem de gente. As vacas comem o capim, têm crias, passam fome na seca e morrem de velhas: a carcaça fica no pasto."},
		{"t": "Arco e flecha", "ic": ["arco", "flecha"], "x": "Equipe o arco (Mochila → Equipar) com flechas na mochila. Segure [b]Atirar[/b] para puxar a corda (a mira fecha) e solte: a flecha vai para onde a mira aponta, mais forte quanto mais puxou.\n\nCada parte do corpo tem o seu dano: na cabeça ou no peito derruba rápido; na perna o bicho foge sangrando e cai mais longe."},
		{"t": "O laço", "ic": ["laco_5", "laco_10"], "x": "Com o laço equipado, chegue perto da vaca e jogue (Laçar). Laçada, ela puxa: segure com [b]Força[/b]. Dá para amarrar a vaca numa estaca ou árvore e levar."},
	]},
	{"t": "O abate", "ic": "faca", "pags": [
		{"t": "O tripé", "ic": ["roldana", "corda_5", "folha_babacu"], "x": "Monte o [b]tripé de içar[/b] (nas Plantas) em cima da vaca: 3 pernas amarradas com cipó, a roldana, a corda e a estaca. O chão embaixo tem que ser [b]forrado com folhas de babaçu[/b] (a carne que cai no forro fica limpa; na terra fica suja).\n\n[b]Pegue a corda[/b], amarre nas patas da frente, volte para a estaca puxando com [b]Força[/b] até a vaca subir, e amarre na estaca."},
		{"t": "Couro e buchada", "ic": ["faca", "couro_vaca"], "x": "[b]O couro:[/b] com a faca, segure a Força e ao mesmo tempo passe a faca na linha onde o couro está soltando. Sai todo e fica estendido no chão: Enrolar e Pegar.\n\n[b]A buchada:[/b] corte a barriga, o Y em volta do úbere e a garganta; puxe com força: as vísceras saem e caem no chão.\n\n[b]As patas e a cabeça[/b] saem a machadadas."},
		{"t": "Bandas e peças", "ic": ["machado", "carrinho"], "x": "Com o machado, parta a vaca ao meio pela espinha: são as duas [b]bandas[/b]. Em cada banda, a faca entre as costelas e o machado na espinha: o pedaço de baixo cai.\n\nPonha o [b]carrinho de mão[/b] embaixo para a carne cair limpa. Pegue a carne (nas costas) e leve para a mesa."},
		{"t": "A mesa de carne", "ic": ["vasilha_carne", "carne_assar", "espeto"], "x": "Ponha a peça na [b]mesa de carne[/b] e toque em Trabalhar a carne. Escolha o corte:\n\n[b]Pedaços pequenos[/b] (cubos, para cozinhar ou fritar) ou [b]pedaços grandes[/b] (para assar).\n\nAparece a grade: toque nos quadradinhos, Cortar, passe a faca em volta (e o machado onde tem osso). Pegar: os pequenos vão na [b]vasilha de barro[/b] (2 kg em cada); os grandes vão na mochila (ou já no espeto)."},
	]},
	{"t": "Pesca", "ic": "vara_pesca", "pags": [
		{"t": "A linha e a vara", "ic": ["coco_babacu", "fibra_coco", "linha_pesca", "vara_pesca"], "x": "[b]Fibra de coco:[/b] no craft, com a faca na mochila, cada coco de babaçu dá 2 fibras.\n\n[b]A linha:[/b] no [b]cavalete de trançar[/b], pelo olho: [b]Fazer linha de pesca[/b]. Trance as fibras igual à corda (o dedo para o lado da seta), só que bem fininha. A linha tem um tamanho só: 10 m, e gasta 10 fibras.\n\n[b]A vara:[/b] no craft, 1 galho + a linha (com a faca)."},
		{"t": "Pescar", "ic": ["vara_pesca", "peixe_tucunare", "peixe_piranha"], "x": "Equipe a vara (Mochila → Equipar) e chegue na beira do [b]rio ou da lagoa[/b] (no mar não tem esses peixes; água rasa também não).\n\n[b]Arremessar:[/b] segure o botão (a vara vai para trás; mais tempo, mais longe) e solte: o anzol bate na água.\n\nEspere. A boia [b]treme[/b]: o peixe está beliscando (não puxe ainda!). A boia [b]afunda[/b]: toque em [b]Força[/b] na hora.\n\nNa briga, toque em Força sem parar: a barra tem que ficar acima do risco branco. Faltando força, o peixe leva a linha e escapa. Chegando na beira, a vara sobe e o peixe sai da água."},
		{"t": "Os peixes", "ic": ["peixe_tucunare", "peixe_pacu", "peixe_traira", "peixe_piranha", "peixe_curimata"], "x": "[b]Piranha:[/b] pequena, morde depressa.\n[b]Curimatã:[/b] anda em cardume, fácil.\n[b]Traíra:[/b] fica parada no fundo perto da beira.\n[b]Pacu:[/b] redondo, puxa bem.\n[b]Tucunaré:[/b] o mais brigador: precisa de muita força.\n\nDe manhãzinha e no fim da tarde o peixe morde mais depressa.\n\n[b]Fritar:[/b] no fogão de barro aceso, com o peixe e uma vasilha de barro vazia na mochila: Pôr a vasilha → Fritar o peixe. Vire de vez em quando."},
	]},
	{"t": "Cozinha", "ic": "carne_assada", "pags": [
		{"t": "Assar no espeto", "ic": ["espeto", "espeto_carne", "carne_assada"], "x": "Com um [b]espeto[/b] na mochila, o pedaço grande sai da mesa já espetado (ou USE a carne para espetar).\n\nNa fogueira acesa: [b]Pôr o espeto no fogo[/b]. Só o lado de baixo assa: [b]vire o espeto[/b] de vez em quando, senão queima. De perto, o relógio mostra quanto falta e cada lado (amarelo dourando, verde pronto, vermelho passando).\n\n[b]Tirar o espeto:[/b] a carne assada e o espeto vão para a mochila."},
		{"t": "O fogão de barro", "ic": ["lenha", "vasilha_carne", "vasilha_carne_cozida", "vasilha_carne_frita"], "x": "Construa o [b]fogão[/b] (Plantas): a base de madeira, 10 pedras e 6 baldes de barro. Ponha a lenha na boca (com ela na mão) e acenda com o arco de fogo.\n\nNas bocas, a vasilha com carne picada: [b]cozinhar[/b] (com 2 goles de água da cabaça) ou [b]fritar[/b] (mexa sempre, senão gruda e queima). A boca em cima do fogo esquenta mais.\n\nPronta, a carne já se come; comendo, a vasilha volta vazia."},
		{"t": "Carne crua e suja", "ic": ["carne_crua", "carne_suja"], "x": "Carne que caiu na terra fica [b]suja[/b]: não serve para comer.\n\nCarne deixada no tempo [b]apodrece[/b]: depois de um dia ela já não presta.\n\nCozinhe ou asse logo o que cortou."},
	]},
	{"t": "A natureza", "ic": "semente", "pags": [
		{"t": "Dias, meses e estações", "ic": [], "x": "O dia passa: de manhã, de tarde, a noite (mais curta). Veja a data no [b]Calendário[/b].\n\nTem a época das chuvas e a seca. Na chuva o fogo apaga, os rios e lagoas enchem, a terra encharca. Na seca o capim seca e as vacas passam fome.\n\nCada fruta tem o seu mês: goiaba de janeiro a abril, bacaba de outubro a dezembro..."},
		{"t": "Água, terra e plantas", "ic": ["cavadeira", "semente"], "x": "A água da chuva corre morro abaixo e enche os buracos e as valetas. Uma valeta cavada até o rio enche com a água dele.\n\nO capim cresce, é comido pelo gado e rebrota; pisado e comido demais, a terra fica pelada.\n\nAs árvores crescem, dão sementes e novas árvores nascem. Você também pode plantar."},
		{"t": "A vida e a morte", "ic": [], "x": "Todo bicho morto [b]apodrece[/b]: incha, estoura, as bicheiras comem a carne, as moscas zumbem, vira couro seco e no fim só os ossos (que ficam meses no pasto).\n\nHoras depois de um bicho morrer, os [b]urubus[/b] chegam e ficam rondando lá no alto. Quando não tem ninguém perto, descem e comem a carniça (e a carne que ficou no chão). Chegou perto, eles levantam voo.\n\nO corpo morto num morro escorrega e assenta no chão."},
	]},
	{"t": "Jogar junto", "ic": "corda_5", "pags": [
		{"t": "Multiplayer", "ic": [], "x": "No menu, [b]Multiplayer[/b]: abra o seu mundo para quem estiver na mesma rede Wi-Fi, ou entre no mundo de outro jogador.\n\nO mundo é o mesmo para todos: o que um constrói, corta ou caça, o outro vê. Algumas coisas são feitas a dois: a serra de pedal (um pedala, o outro empurra a tora) e carregar toras pesadas juntos."},
		{"t": "Boa sorte", "ic": ["machado", "faca", "arco", "balde"], "x": "Cada coisa no jogo funciona do jeito que funciona de verdade. Na dúvida, pense: como se faria isso na mata, sem nada?\n\nObserve a natureza, cuide do corpo, guarde o que for importante e vá construindo aos poucos.\n\nEste livro fica nas [b]Configurações[/b]. Boa sorte, sobrevivente."},
	]},
]

var _pagina := 0                  # índice na lista achatada; -1 = o índice dos capítulos
var _lista := []                  # [cap, pag] de cada página
var _esq: Control
var _ilus: Control
var _titulo: Label
var _cap_lbl: Label
var _texto: RichTextLabel
var _num: Label
var _indice: VBoxContainer
var _scroll_idx: ScrollContainer
var _btn_ant: Button
var _btn_prox: Button
var _arr_x := -1.0
var _arr_id := -99


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for ci in CAPITULOS.size():
		for pi in (CAPITULOS[ci].pags as Array).size():
			_lista.append([ci, pi])
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.01, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	# a capa (a moldura de couro do livro) e as duas páginas
	var capa := Panel.new()
	capa.set_anchors_preset(Control.PRESET_FULL_RECT)
	capa.offset_left = 24
	capa.offset_right = -24
	capa.offset_top = 16
	capa.offset_bottom = -86
	capa.add_theme_stylebox_override("panel", _caixa(C_CAPA, 14, Color(0.15, 0.09, 0.04), 3))
	capa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(capa)
	var pags := HBoxContainer.new()
	pags.set_anchors_preset(Control.PRESET_FULL_RECT)
	pags.offset_left = 40
	pags.offset_right = -40
	pags.offset_top = 30
	pags.offset_bottom = -100
	pags.add_theme_constant_override("separation", 0)
	add_child(pags)
	# a página da esquerda: o capítulo, o título e os desenhos
	var pe := PanelContainer.new()
	pe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pe.size_flags_stretch_ratio = 0.85
	pe.add_theme_stylebox_override("panel", _papel(true))
	pags.add_child(pe)
	_esq = VBoxContainer.new()
	(_esq as VBoxContainer).add_theme_constant_override("separation", 8)
	pe.add_child(_esq)
	_cap_lbl = _lbl("", 18, C_TINTA2)
	_esq.add_child(_cap_lbl)
	_titulo = _lbl("", 32, C_TINTA)
	_titulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_esq.add_child(_titulo)
	var linha := ColorRect.new()
	linha.color = C_DESTAQUE
	linha.custom_minimum_size = Vector2(0, 3)
	_esq.add_child(linha)
	_ilus = Control.new()
	_ilus.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ilus.draw.connect(_desenha_ilus)
	_esq.add_child(_ilus)
	# o índice (no lugar dos desenhos, quando aberto)
	_scroll_idx = ScrollContainer.new()
	_scroll_idx.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_idx.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_esq.add_child(_scroll_idx)
	_indice = VBoxContainer.new()
	_indice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_indice.add_theme_constant_override("separation", 4)
	_scroll_idx.add_child(_indice)
	for ci in CAPITULOS.size():
		var b := Button.new()
		b.text = "%d. %s" % [ci + 1, CAPITULOS[ci].t]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 21)
		b.add_theme_color_override("font_color", C_TINTA)
		b.add_theme_color_override("font_hover_color", C_DESTAQUE)
		b.add_theme_color_override("font_pressed_color", C_DESTAQUE)
		var vazio := StyleBoxEmpty.new()
		b.add_theme_stylebox_override("normal", vazio)
		b.add_theme_stylebox_override("hover", _caixa(Color(0.55, 0.22, 0.1, 0.1), 6))
		b.add_theme_stylebox_override("pressed", _caixa(Color(0.55, 0.22, 0.1, 0.18), 6))
		b.add_theme_stylebox_override("focus", vazio)
		var cap := ci
		b.pressed.connect(func(): _vai_cap(cap))
		_indice.add_child(b)
	# a página da direita: o texto
	var pd := PanelContainer.new()
	pd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pd.add_theme_stylebox_override("panel", _papel(false))
	pags.add_child(pd)
	_texto = RichTextLabel.new()
	_texto.bbcode_enabled = true
	_texto.fit_content = false
	_texto.scroll_active = true
	_texto.add_theme_font_size_override("normal_font_size", 21)
	_texto.add_theme_font_size_override("bold_font_size", 21)
	_texto.add_theme_color_override("default_color", C_TINTA)
	_texto.add_theme_constant_override("line_separation", 4)
	pd.add_child(_texto)
	# embaixo: anterior, índice, a página, próxima, fechar
	var barra := HBoxContainer.new()
	barra.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	barra.offset_top = -78
	barra.offset_bottom = -10
	barra.offset_left = 30
	barra.offset_right = -30
	barra.add_theme_constant_override("separation", 12)
	add_child(barra)
	_btn_ant = _botao("◀  Anterior", func(): _vira(-1))
	barra.add_child(_btn_ant)
	barra.add_child(_botao("Índice", func(): _mostra(-1)))
	_num = _lbl("", 20, Color(0.93, 0.88, 0.76))
	_num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	barra.add_child(_num)
	_btn_prox = _botao("Próxima  ▶", func(): _vira(1))
	barra.add_child(_btn_prox)
	barra.add_child(_botao("Fechar", fechar))
	_mostra(0)


func _lbl(t: String, sz: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", c)
	return l


func _botao(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(150, 60)
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	b.add_theme_stylebox_override("normal", _caixa(Color(0.3, 0.19, 0.1), 10, Color(0.6, 0.45, 0.25), 2))
	b.add_theme_stylebox_override("hover", _caixa(Color(0.38, 0.24, 0.12), 10, Color(0.75, 0.55, 0.3), 2))
	b.add_theme_stylebox_override("pressed", _caixa(Color(0.22, 0.14, 0.07), 10, Color(0.75, 0.55, 0.3), 2))
	b.add_theme_stylebox_override("disabled", _caixa(Color(0.2, 0.14, 0.09, 0.5), 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


static func _caixa(bg: Color, r := 8, borda := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(r)
	s.border_color = borda
	s.set_border_width_all(bw)
	return s


## O papel: claro, a borda de dentro (perto da costura) mais escura.
static func _papel(esq: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = C_PAPEL if esq else C_PAPEL2.lerp(C_PAPEL, 0.5)
	s.corner_radius_top_left = 6 if esq else 0
	s.corner_radius_bottom_left = 6 if esq else 0
	s.corner_radius_top_right = 0 if esq else 6
	s.corner_radius_bottom_right = 0 if esq else 6
	s.border_color = Color(0.6, 0.5, 0.35, 0.7)
	s.border_width_right = 3 if esq else 0
	s.border_width_left = 0 if esq else 3
	s.content_margin_left = 34 if esq else 30
	s.content_margin_right = 26 if esq else 34
	s.content_margin_top = 26
	s.content_margin_bottom = 22
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 4
	return s


func _mostra(i: int) -> void:
	_pagina = i
	var idx := i < 0
	_scroll_idx.visible = idx
	_ilus.visible = not idx
	if idx:
		_cap_lbl.text = "LAST HORIZON"
		_titulo.text = "Livro do Sobrevivente"
		_texto.text = "[b]Índice[/b]\n\nToque num capítulo (na página da esquerda) para ir até ele.\n\nVire as páginas com as setas embaixo ou arrastando o dedo para o lado.\n\nEste livro fica nas [b]Configurações[/b]: abra quando quiser lembrar como se faz alguma coisa."
		_num.text = "Índice"
		_btn_ant.disabled = true
		_btn_prox.disabled = false
		return
	var cp: Array = _lista[i]
	var cap: Dictionary = CAPITULOS[int(cp[0])]
	var pg: Dictionary = (cap.pags as Array)[int(cp[1])]
	_cap_lbl.text = "CAPÍTULO %d · %s" % [int(cp[0]) + 1, str(cap.t).to_upper()]
	_titulo.text = str(pg.t)
	_texto.text = str(pg.x)
	_texto.scroll_to_line(0)
	_num.text = "Página %d de %d" % [i + 1, _lista.size()]
	_btn_ant.disabled = false
	_btn_prox.disabled = i >= _lista.size() - 1
	_ilus.queue_redraw()


func _vira(d: int) -> void:
	var n := _pagina + d
	if _pagina < 0:
		n = 0 if d > 0 else -1
	if n < -1 or n >= _lista.size():
		return
	_mostra(n)


func _vai_cap(ci: int) -> void:
	for i in _lista.size():
		if int(_lista[i][0]) == ci:
			_mostra(i)
			return


## Os desenhos da página (os itens que ela ensina), em fileira, com o nome embaixo.
func _desenha_ilus() -> void:
	if _pagina < 0:
		return
	var cp: Array = _lista[_pagina]
	var pg: Dictionary = (CAPITULOS[int(cp[0])].pags as Array)[int(cp[1])]
	var ics: Array = pg.get("ic", [])
	if ics.is_empty():
		ics = [CAPITULOS[int(cp[0])].ic]
	var w := _ilus.size.x
	var h := _ilus.size.y
	var n := ics.size()
	var por_linha := mini(n, 3)
	var linhas := ceili(float(n) / por_linha)
	var cel := minf(w / por_linha, (h - 10.0) / linhas)
	var s := minf(cel * 0.62, 120.0)
	var font := get_theme_default_font()
	for k in n:
		var col := k % por_linha
		var lin := k / por_linha
		var nesta := mini(por_linha, n - lin * por_linha)
		var x0 := (w - nesta * cel) * 0.5
		var c := Vector2(x0 + (col + 0.5) * cel, (lin + 0.45) * cel + (h - linhas * cel) * 0.4)
		_ilus.draw_circle(c, s * 0.62, Color(0.82, 0.74, 0.58, 0.55))
		Desenhos.item(_ilus, str(ics[k]), c, s)
		var nome := _nome_item(str(ics[k]))
		var tw := font.get_string_size(nome, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_ilus.draw_string(font, c + Vector2(-tw * 0.5, s * 0.62 + 20), nome, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_TINTA2)


func _nome_item(id: String) -> String:
	var Itens = load("res://scripts/itens.gd")
	var it: Dictionary = Itens.ITENS.get(id, {})
	if it.is_empty():
		return "Carrinho de mão" if id == "carrinho" else ""
	return str(it.nome)


## Arrastar o dedo para o lado vira a página.
func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_arr_x = e.position.x
			_arr_id = e.index
		elif e.index == _arr_id and _arr_x >= 0.0:
			var dx: float = e.position.x - _arr_x
			if absf(dx) > 120.0:
				_vira(-1 if dx > 0.0 else 1)
			_arr_x = -1.0
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.device != InputEvent.DEVICE_ID_EMULATION:
		if e.pressed:
			_arr_x = e.position.x
		elif _arr_x >= 0.0:
			var dx2: float = e.position.x - _arr_x
			if absf(dx2) > 120.0:
				_vira(-1 if dx2 > 0.0 else 1)
			_arr_x = -1.0


func fechar() -> void:
	fechou.emit()
	queue_free()
