# Last Horizon

Jogo de sobrevivência top-down que roda no navegador (HTML5 Canvas, sem dependências).

De dia você junta madeira, pedra e frutas. À noite as **Sombras** atacam, e a cada noite elas voltam em maior número e mais fortes. Sobreviva o máximo de dias que conseguir.

## Como jogar

Abra `index.html` no navegador. Funciona no computador e no celular.

| Ação | Teclado / mouse | Celular |
|---|---|---|
| Mover | WASD ou setas | Arraste o dedo na tela |
| Golpear (coletar / atacar) | Clique ou Espaço | Botão **Golpe** (mira automática) |
| Fogueira / alimentar fogo | 1 | Botão |
| Muro | 2 | Botão |
| Espinhos | 3 | Botão |
| Lança | 4 | Botão |
| Comer | F | Botão |
| Pausar | P ou Esc | Botão |

## Mecânicas

- **Ciclo dia/noite:** 75 s de dia, 50 s de noite. As Sombras se desfazem ao amanhecer.
- **Fome:** cai com o tempo. Zerada, drena sua vida. Coma frutas dos arbustos vermelhos.
- **Fogueira:** ilumina, cura e afasta as Sombras. Queima por 100 s; construa outra ao lado para alimentá-la (3 madeira).
- **Muros:** bloqueiam as Sombras até serem destruídos.
- **Espinhos:** ferem as Sombras que passam por cima.
- **Lança:** mais dano, mais alcance e coleta mais rápida.
- A partir do dia 3 aparecem **Brutos**: lentos, resistentes e menos medrosos do fogo.

## Desenvolvimento

O código-fonte fica em `src/game.html`. Depois de editar, rode `./build.sh` para gerar o `index.html` standalone.
