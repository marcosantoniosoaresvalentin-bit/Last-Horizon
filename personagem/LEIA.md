# Personagem

- `humano.glbin`: modelo humano "Michelle" dos exemplos do three.js (personagem da Adobe Mixamo). É um .glb comum com outra extensão, para a Godot não importar; o jogo carrega ele na hora com `GLTFDocument`, por isso ele chega pela atualização automática.
- `parado.tres`, `andando.tres`, `correndo.tres`: animações do Mixamo (do modelo "Soldier" do three.js) convertidas para o esqueleto da Michelle com `tools/converter_animacoes.gd`.
