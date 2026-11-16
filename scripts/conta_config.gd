extends RefCounted
## Configuração do servidor de contas (Firebase Authentication).
## API_KEY: "Chave de API da Web" do projeto no Firebase
## (console.firebase.google.com → Configurações do projeto → Geral).
## Enquanto as duas estiverem vazias, o jogo não pede conta.
## Essa chave identifica o projeto e pode ficar no código; a segurança é do próprio Firebase.

const API_KEY := ""
## "Código do projeto" (Project ID), na mesma tela. Usado para reservar os nomes de usuário
## no Firestore, para dois jogadores nunca terem o mesmo nome.
const PROJECT_ID := ""
