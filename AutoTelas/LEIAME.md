# AutoTelas: SAIPOS na tela principal e um arquivo na segunda tela

Para Dell OptiPlex 990 com Windows 10 e 2 monitores em modo "Estender":
- **Tela principal (VGA):** SAIPOS maximizado.
- **Segunda tela (DisplayPort → HDMI):** o arquivo definido em `C:\AutoTelas\config.txt`. Se ele estiver vazio, nada abre.

## Instalar
1. Baixe esta pasta `AutoTelas` para o computador (por exemplo, para `Downloads\AutoTelas`).
2. Dê dois cliques em **`1-CONFIGURAR.bat`**. O assistente:
   - mostra os monitores (resolução, posição, VGA/DisplayPort e qual é o principal) e para se só houver 1;
   - procura o atalho do SAIPOS (Área de Trabalho, `C:\Users\Public\Desktop` e Menu Iniciar), mostra o executável e os argumentos, e pergunta qual usar se houver mais de um;
   - avisa se o SAIPOS já abre sozinho ao ligar, para não abrir duas vezes;
   - cria `C:\AutoTelas` e o atalho na pasta Inicializar;
   - oferece o teste e o login automático.

   **Ele pede S/N antes de cada alteração.**

## Configurar a segunda tela
Abra `C:\AutoTelas\config.txt` no Bloco de Notas e preencha a linha:

```
SEGUNDA_TELA=C:\Users\Public\Documents\cardapio.pdf
```

- Use o caminho completo, **sem aspas** (espaços são permitidos).
- Dica: no Explorador, segure **Shift**, clique com o botão direito no arquivo e escolha **"Copiar como caminho"**. Cole e apague as aspas.
- PDF, imagem, `.html` ou endereço `https://...` abrem no Chrome em tela cheia. Para sair da tela cheia, use **Alt+F4**.
- Qualquer outro tipo abre no programa padrão e a janela é movida e maximizada na segunda tela.
- Deixe vazio (`SEGUNDA_TELA=`) para não abrir nada. Se o arquivo não existir, nada abre e o motivo fica registrado no log.
- A mudança vale a partir do próximo login. Para testar na hora, rode `2-TESTAR.bat`.

## Log
`C:\AutoTelas\log.txt` registra o que foi aberto, onde e eventuais erros.

## Desativar
- **Só parar de abrir ao ligar:** apague o atalho `AutoTelas` em `shell:startup` (Win+R → `shell:startup`).
- **Remover tudo:** rode `3-DESINSTALAR.bat` ou apague o atalho acima e a pasta `C:\AutoTelas`.
- **Login automático:** abra `netplwiz` e marque de novo "Os usuários devem digitar um nome de usuário e uma senha...". Se usou o Autologon, abra-o e clique em **Disable**.
