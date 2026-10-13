# Loosa

App de barra de menus para macOS que deixa você desenhar em cima da tela: setas, formas, texto, traço livre, marca-texto e desfoque. Bom para gravações, aulas, apresentações e para explicar algo em um print.

Grátis e de código aberto.

## O que faz

- **Desenho livre** com suavização, para o traço não ficar tremido
- **Marca-texto** verde semitransparente
- **Seta, quadrado e círculo**, com opção de preencher as formas
- **Texto** direto na tela
- **Desfoque de área**: arraste um retângulo e o que está embaixo fica desfocado
- **Traço fantasma**: o que você desenha some sozinho depois de alguns segundos
- **Borrachas**: apagar um item inteiro ou apagar só o pedaço que você passa por cima
- Desfazer e refazer, cores trocáveis, espessura ajustável
- A barra de ferramentas não aparece em prints nem em gravações de tela
- Vários monitores: cobre todas as telas
- Tudo configurável: ferramentas visíveis, atalhos, cores, posição e tamanho da barra

## Instalar

Requer macOS 14 ou mais recente. Roda em Apple Silicon e em Intel.

### Pelo Terminal (recomendado)

Cole no Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/jhoff66/Loosa/main/install.sh | bash
```

O script baixa a versão mais recente, copia para Applications e abre o app. O ícone aparece na barra de menus.

### Pelo DMG

1. Baixe o `Loosa.dmg` na página de [releases](../../releases).
2. Abra o DMG e arraste o Loosa para Applications.
3. O app não é notarizado pela Apple, então o macOS barra a primeira abertura de um DMG baixado pelo navegador, às vezes dizendo que o app "está danificado". Ele não está. Para liberar, cole no Terminal:

```sh
xattr -cr /Applications/Loosa.app
```

4. Abra o Loosa normalmente.

## Primeiros passos

1. Aperte **⌘1** ou clique no ícone do Loosa na barra de menus. A tela fica pronta para desenhar e aparece a barra de ferramentas.
2. Escolha uma ferramenta, uma cor e a espessura, e desenhe.
3. Aperte **Esc** (ou o X da barra) para sair. Os desenhos somem ao sair.

Clique com o botão direito no ícone para abrir o menu e as Configurações.

## Permissão para o desfoque

O desfoque de área precisa ler o que está na tela, e para isso o macOS exige a permissão de **Gravação de Tela**. Sem ela, o Loosa usa um vidro fosco acinzentado no lugar.

1. Abra **Configurações** (engrenagem na barra de ferramentas) e, na seção **Desfoque**, clique em **Liberar…**
2. Em **Ajustes do Sistema → Privacidade e Segurança → Gravação de Tela e Áudio do Sistema**, ligue o **Loosa**.
3. Feche e abra o Loosa de novo.

O Loosa só usa essa permissão para o desfoque. Nada é gravado nem enviado para lugar nenhum.

## Atalhos

Com o desenho aberto:

| Tecla | Função |
|---|---|
| `P` | Desenho livre |
| `H` | Marca-texto |
| `A` | Seta |
| `R` | Quadrado |
| `O` | Círculo |
| `T` | Texto |
| `D` | Desfoque de área |
| `E` | Apagar item |
| `B` | Borracha livre |
| `G` | Traço fantasma |
| `S` | Suavizar desenho |
| `F` | Preencher formas |
| `1` a `6` | Escolhe a cor da posição correspondente |
| `⌘Z` ou `⌃Z` | Desfazer |
| `⇧⌘Z` ou `⇧⌃Z` | Refazer |
| `⌘⌫` | Limpar tudo |
| `Esc` | Sair |

Dicas:

- Segure **Shift** ao desenhar uma seta para travar em ângulos de 45°, e ao desenhar quadrado ou círculo para fazer formas perfeitas.
- No texto, **Enter** confirma e **Shift+Enter** quebra a linha.
- Arraste a barra de ferramentas por qualquer área vazia dela para movê-la.

O atalho global para ligar e desligar o desenho é **⌘1** por padrão e pode ser trocado.

## Configurações

Abra pela engrenagem da barra ou pelo menu do ícone (botão direito → **Configurações…**).

- **Ferramentas e atalhos:** ligue ou desligue cada ferramenta e troque a letra do atalho. Clique na tecla ao lado do nome e aperte a nova letra; Delete remove o atalho.
- **Cores:** troque cada uma das 6 cores da paleta.
- **Modos:** traço fantasma (com tempo ajustável de 1 a 10 s), suavizar desenho e preencher formas.
- **Barra de ferramentas:** posição (embaixo, em cima, esquerda ou direita) e tamanho de 80% a 160%.
- **Desfoque:** mostra se a permissão de Gravação de Tela está liberada.
- **Geral:** atalho global livre (clique e aperte a combinação), abrir ao iniciar o Mac e restaurar os padrões.

## Compilar

Precisa só das Command Line Tools da Apple (`xcode-select --install`).

```sh
./build.sh           # gera o Loosa.app
./build.sh install   # também copia para /Applications e reabre
./build.sh dmg       # também gera o Loosa.dmg
```

## Licença

MIT. Veja [LICENSE](LICENSE).
