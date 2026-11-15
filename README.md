# Last Horizon

Jogo de sobrevivência multiplayer online com visão de cima, feito na **Godot 4.7.2**.

## Status

- [x] Tela de carregamento
- [ ] Menu principal (por enquanto é só um aviso de "em construção")
- [ ] Jogo, multiplayer, servidor e APK

## Abrir o projeto

1. Baixe o repositório (botão **Code → Download ZIP** no GitHub) e extraia.
2. Na Godot, toque em **Importar** e escolha o arquivo `project.godot`.
3. Rode o projeto (▶). A tela de carregamento abre primeiro e depois vai para o menu.

## Estrutura

| Pasta / arquivo | O que é |
|---|---|
| `project.godot` | Configuração do projeto (tela deitada, 1280×720, renderizador Compatibility para rodar em mais celulares) |
| `scenes/loading_screen.tscn` | Tela de carregamento |
| `scripts/loading_screen.gd` | Carrega a próxima cena em segundo plano, mostra o progresso e as dicas |
| `scripts/horizon_backdrop.gd` | Fundo animado: pôr do sol, serras com pinheiros e brasas |
| `scenes/main_menu.tscn` | Menu principal (provisório) |
| `prototipo-web/index.html` | Protótipo jogável no navegador do ecossistema (Mata Viva), usado para testar as mecânicas |

## Protótipo do ecossistema (navegador)

A pasta `prototipo-web/` tem um protótipo em HTML que roda direto no navegador do celular, sem instalar nada. Ele serve para testar as mecânicas antes de passá-las para a Godot. O arquivo `.gdignore` faz a Godot ignorar essa pasta.

O que já funciona:

- **Capivaras:** fome, sede, grupo, descanso, acasalamento, gestação, filhotes, envelhecimento e morte
- **Capim:** é consumido e volta a crescer, mais rápido perto da água e em solo fértil
- **Carcaças:** 5 estágios de decomposição (fresca, inchada, ativa, avançada, esqueleto) que no fim adubam o solo
- **Jogador:** anda, caça e tira couro e carne; a carne estraga com o tempo
- Ciclo de dia e noite e aceleração do tempo (1x, 4x, 16x)

Para abrir: baixe o arquivo `prototipo-web/index.html` e abra no navegador.
