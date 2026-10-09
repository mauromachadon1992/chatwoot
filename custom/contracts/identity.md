# Identidade Flow v1: um nome, uma marca, uma cor para as duas interfaces

Fonte única, copiada byte a byte nos dois repositórios e coberta pelo `CONTRACT.sha256`, junto com os SVGs de `identity/`. Quem muda a
identidade muda aqui, nos dois repositórios, na mesma sessão (`protocol.md`). Os dois produtos recebem a identidade por caminhos diferentes, porque a edição
Free do agents não aceita marca por API (isso é o branding da edição Pro): o Chatwoot por **configuração** (a tela de login do Super Admin),
o agents pela **marca padrão que o repositório embarca**.

## Nomes

- **Flow** é o projeto e a família. Sozinho, só nesse sentido.
- **Flow Chat** é o Chatwoot do projeto (atendimento, Kanban de vendas). **Flow Agents** são os agentes de IA do projeto. O padrão é "Flow" + um substantivo.
- Uma regra, dos dois lados: **slug para máquina, nome próprio para gente.** Na interface, no título, no README e na mensagem: **Flow Chat** e **Flow Agents** (maiúsculas, com espaço). Em repositório, imagem, pacote, URL e código: `flow-chat` e `flow-agents`. Nunca "FlowChat", "flow chat" ou "Flow-Chat".
- Nos logos, "Flow" vai em peso 600 e o substantivo em 400: é o peso, mais que a grafia, que liga os dois produtos.
- O nome do produto nunca leva "fazer.ai" nem "Chatwoot" junto. A origem aparece como atribuição (README, licença), não na marca.

## A marca

Um azulejo arredondado com três colunas que sobem em degraus: um card passando de etapa em etapa e ganhando terreno. É o Kanban do Flow Chat e o fluxo
de trabalho dos agentes na mesma imagem. Desenhada para este projeto, sem aproveitar nenhuma marca anterior.

| Arquivo | Uso |
| --- | --- |
| `identity/flow-mark.svg` | a marca sozinha: ícone, favicon, barra lateral recolhida. O azulejo lê bem em fundo claro e escuro, então é um só arquivo para os dois temas |
| `identity/flow-chat-light.svg`, `flow-chat-dark.svg` | marca e o nome **Flow Chat**, para fundo claro e escuro |
| `identity/flow-agents-light.svg`, `flow-agents-dark.svg` | marca com uma faísca sobre a última coluna (o detalhe do Flow Agents) e o nome **Flow Agents**, para fundo claro e escuro |

O nome nos lockups é desenho (Inter 600 em "Flow" e 400 no substantivo, convertida em curvas, `-0,01em` de espaçamento), não texto: um SVG usado como imagem não carrega
fonte. Foram gerados por `custom/script/build-identity.mjs` (repositório `flow-agents-ee`); mudou o desenho, rode o script, não edite os SVGs.

Regras de uso: tamanho mínimo da marca **16 px**; respiro livre de um quarto da altura; nunca esticar, girar, recolorir nem pôr sombra;
sobre foto ou cor, use o lockup claro com um fundo liso por baixo.

## A cor

**Flow Indigo `#3E63DD`** é a semente do acento. As interfaces não usam o hex solto: cada uma gera a sua rampa de 12 passos a partir dele
e garante o contraste (branco sobre o passo 9 a 4,5:1; ver `DESIGN.md`, "Accent-Ramp Rule"). Os neutros são os slate já existentes
(tinta `#1C2024`, papel `#EDEEF0`, superfície escura `#111113`). Não há segunda cor de marca: o verde, o âmbar e o vermelho continuam
sendo só semânticos (sucesso, aviso, erro).

## A voz

Operação, não campanha: calma, direta, em português do Brasil primeiro. Frases curtas, o verbo da ação no botão, nada de exclamação
nem de promessa. O mesmo registro nas duas interfaces.

## Onde se aplica (por configuração)

| Interface | Como | O que recebe |
| --- | --- | --- |
| Flow Chat | `rake "flow:identity:apply"` (Super Admin → Login page) | nome `Flow Chat`, logos clara e escura, ícone, acento `#3E63DD`, textos da tela de entrada em pt-BR, en e es |
| Flow Agents | a marca **padrão** do repositório: os PNG de `public/` e `public/assets/` (logo, marca e favicon nos dois temas, gerados a partir dos SVGs por `custom/script/build-identity.mjs`) e o nome padrão `DEFAULT_BRAND_NAME`, o título de `public/index.html` e o acento padrão de `public/index.css` (a rampa do Flow Indigo, no lugar do violeta do upstream); o rodapé do menu sem os links do upstream | nome `Flow Agents`, a marca com a faísca e o favicon; a API de branding da edição Pro não é usada nem contornada |

A aplicação no Flow Chat é **idempotente** e só mexe na identidade; cada ambiente (dev, staging, produção) recebe a sua, e aplicar em
produção é decisão do dono. Desfazer: no Flow Chat, `rake "flow:identity:reset"`; no agents, reverter o commit da marca padrão.

## O que não muda

Pacotes, nomes de imagem, caminhos de código (`i18n/fazer-ai/locale`), URLs e remotes do upstream, a licença e o NOTICE. Os nomes de imagem
e de pacote são decisão à parte (B-14 do `custom/BACKLOG.md` do Chatwoot): as tags já publicadas são imutáveis.

## Compatibilidade

Mudar a cor-semente, o nome ou a marca é mudar a v1; a mudança é anunciada pelo hash e pelo `protocol.md`. Acrescentar um lockup ou uma
variante é aditivo.
