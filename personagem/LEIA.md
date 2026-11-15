# Personagens

- `homem.glbin`: avatar masculino realista feito no [Avatar SDK](https://avatarsdk.com) (exemplo do projeto TalkingHead, github.com/met4citizen/TalkingHead).
- `mulher.glbin`: avatar feminino realista feito no [Avaturn](https://avaturn.me) (mesmo projeto).
- **Licença:** os dois avatares são liberados apenas para uso **não comercial**. Antes de vender o jogo, é preciso trocar os modelos ou conseguir a licença comercial com o Avatar SDK e o Avaturn.
- Os arquivos são .glb comuns com outra extensão, para a Godot não importar. O jogo carrega eles na hora com `GLTFDocument`, por isso chegam pela atualização automática. As texturas foram reduzidas e as expressões do rosto removidas com `tools/deixar_modelo_leve.gd`.
- `*_parado.tres`, `*_andando.tres`, `*_correndo.tres`: animações do Mixamo (modelo "Soldier" dos exemplos do three.js) convertidas para o esqueleto de cada avatar com `tools/converter_animacoes.gd`.
