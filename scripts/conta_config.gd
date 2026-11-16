extends RefCounted
## Onde ficam as contas: um arquivo de texto num repositório PRIVADO do GitHub,
## separado do repositório do jogo. Uma conta por linha.
##
## A chave de acesso (token) NÃO fica no código, porque o repositório do jogo é
## público. Ela é guardada nos segredos do GitHub (CONTAS_TOKEN) e o robô que gera
## o APK grava em res://segredos/token.txt. Sem esse arquivo, o jogo não pede conta.
##
## Solução provisória: quem tirar a chave de dentro do APK consegue ler e mexer no
## arquivo de contas. Antes de publicar o jogo, trocar por um servidor próprio.

const OWNER := "marcosantoniosoaresvalentin-bit"
const REPO := "last-horizon-contas"
const FILE := "contas.txt"
const TOKEN_PATH := "res://segredos/token.txt"
