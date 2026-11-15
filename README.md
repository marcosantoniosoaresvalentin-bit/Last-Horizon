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
