# Last Horizon

Jogo de sobrevivência multiplayer online com visão de cima, feito na **Godot 4.7.2**.

## Status

- [x] Tela de carregamento
- [x] Atualização automática na tela de carregamento
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
| `scripts/updater.gd` | Atualizador: baixa e instala as atualizações do jogo ao abrir |
| `updates/manifest.json` | Diz qual é a versão mais nova e qual arquivo baixar |
| `tools/criar_atualizacao.py` | Gera um pacote de atualização novo |
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

## Atualização automática

Ao abrir o jogo, a tela de carregamento procura atualizações antes de tudo:

1. Baixa `updates/manifest.json` deste repositório.
2. Se a versão do manifest for maior que a do celular, baixa o pacote `updates/update_N.zip` mostrando o progresso em **MB / MB**.
3. Confere o tamanho e o SHA-256, instala o pacote e só então carrega o jogo.
4. Sem internet, o jogo abre normalmente com a versão que já está no celular.

A versão do celular aparece no canto da tela como `build N`.

### Publicar uma atualização

```
python3 tools/criar_atualizacao.py "o que mudou"
```

Isso gera o pacote novo em `updates/`, atualiza o manifest e o `config/build` do `project.godot`. Depois é só enviar para o GitHub.

O pacote leva código e cenas (`scripts/` e `scenes/`). Imagens, sons e modelos 3D novos precisam de um **APK novo**, porque a Godot tem que importá-los. Para obrigar quem tem um APK antigo a instalar o novo, aumente `min_build` no manifest.

### Ao exportar o APK

- Em **Permissões**, marque **Internet**.
- Em **Recursos**, desmarque *Converter recursos de texto para binário*, e em **Script**, escolha o modo *Texto*. Assim as atualizações substituem os arquivos sem problemas.

## Baixar o APK

A cada envio para o GitHub, o APK é gerado sozinho e publicado em **Releases**. A versão mais recente fica em:
https://github.com/marcosantoniosoaresvalentin-bit/Last-Horizon/releases/latest

O ícone e a capa para a Play Store ficam em `store/` (`icone_512.png` e `capa_1024x500.png`).
