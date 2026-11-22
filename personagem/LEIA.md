# Personagens

- `homem.glbin`: avatar masculino realista feito no [Avatar SDK](https://avatarsdk.com) (exemplo do projeto TalkingHead, github.com/met4citizen/TalkingHead).
- `mulher.glbin`: avatar feminino realista feito no [Avaturn](https://avaturn.me) (mesmo projeto).
- **Licença:** os dois avatares são liberados apenas para uso **não comercial**. Antes de vender o jogo, é preciso trocar os modelos ou conseguir a licença comercial com o Avatar SDK e o Avaturn.
- Os arquivos são .glb comuns com outra extensão, para a Godot não importar. O jogo carrega eles na hora com `GLTFDocument`, por isso chegam pela atualização automática. As texturas foram reduzidas e as expressões do rosto removidas com `tools/deixar_modelo_leve.gd`, e as partes do corpo foram juntadas numa malha só com `tools/juntar_malhas_personagem.gd` (vários pedaços animados separados faziam o jogo fechar em celulares Android).
- `*_parado.tres`, `*_andando.tres`, `*_correndo.tres`: animações do Mixamo (modelo "Soldier" dos exemplos do three.js) convertidas para o esqueleto de cada avatar com `tools/converter_animacoes.gd`.
- `vaca.glbin`: a vaca ("Cow") do **Farm Animal Pack** de Quaternius (opengameart.org/content/lowpoly-animated-farm-animal-pack), licença **CC0** (domínio público: pode usar até em jogo vendido, sem precisar dar crédito). Convertida de FBX para .glb com a própria Godot (FBXDocument). As animações vêm no arquivo (parada, andando, correndo, morrendo); a cor, o pelo e o pescoço baixando para pastar são feitos no jogo (`scripts/world/vaca_modelo.gd`).
