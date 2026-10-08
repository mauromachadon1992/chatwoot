<div align="center">

<h1>flow-chat</h1>

<p>O Chatwoot do projeto Flow: atendimento por WhatsApp com Kanban de vendas e agentes de IA.</p>
<p>Fork privado do Chatwoot fazer.ai, que estende o Chatwoot oficial. Não é a distribuição oficial.</p>

**Português (Brasil)** · [English](README-en.md)

</div>

## O que é

O **flow-chat** é o Chatwoot do projeto Flow. Parte do [fork da fazer.ai](https://github.com/fazer-ai/chatwoot), que por sua vez estende o [Chatwoot oficial](https://github.com/chatwoot/chatwoot), e acrescenta, na pasta [`custom/`](custom/), um Kanban de vendas próprio e a conversa com o **flow-agents**, os agentes de IA do projeto (`mauromachadon1992/flow-agents-ee`).

Três camadas, cada uma com o seu dono: o Chatwoot (Chatwoot Inc.), as adições do fork da fazer.ai (FAZER.AI LTDA) e as do flow-chat. O flow-chat **não** é produto, release, imagem nem suporte oficiais do Chatwoot nem da fazer.ai.

## O que o flow-chat adiciona

### Kanban de vendas (`custom/`)

- Quadros, etapas (abertas, ganha, perdida) e cards: um negócio ligado a um contato, com as conversas de qualquer caixa de entrada. Arrastar e soltar, filtros, tempo real e visibilidade por caixa de entrada, time e agente.
- Valor e produtos: catálogo, linhas do negócio, orçamento montado a partir do card, probabilidade por etapa e relatórios de funil e previsão.
- Tarefas por card, "minhas tarefas", lembretes e notificações.
- Negócios que nascem sozinhos de novas conversas (por conta e por quadro), alerta de negócio parado e motivo de perda.
- Automações por etapa, webhooks de saída assinados (HMAC) e importação e exportação em CSV.
- Resumo do negócio por IA (Captain), desligado por padrão.
- Linha do tempo de cada card, com quem agiu: uma pessoa, um agente de IA, uma regra ou o sistema.
- Painel do card em abas, celular, português, inglês e espanhol, claro e escuro.

O que cada parte faz e o que não faz está em [`custom/README.md`](custom/README.md). O plano, em [`custom/ROADMAP.md`](custom/ROADMAP.md), e o estado de agora, em [`custom/BACKLOG.md`](custom/BACKLOG.md).

### Conversa com o flow-agents

- O flow-chat fala o **dialeto de Kanban** que o cliente do agente já usa (15 operações; o harness do flow-agents passa 16 de 16 contra ele) e oferece **extensões** (catálogo, produtos do negócio, valor), todas por capacidades anunciadas em `GET kanban/settings`.
- O agente age como um **usuário de serviço** (`agent_bot`), que não alcança webhooks, importações nem automações.
- O contrato, em [`custom/contracts/`](custom/contracts/), é o mesmo nos dois repositórios, com um hash só. O [protocolo](custom/contracts/protocol.md) diz quem muda o quê, em que ordem, e como cada lado prova a sua parte.

### O que vem do fork da fazer.ai

O flow-chat herda tudo isso; os detalhes estão no [README do fork](https://github.com/fazer-ai/chatwoot#readme).

- **WhatsApp:** QR code ou API oficial, provedor nativo em beta (conector de código aberto da fazer.ai), grupos, reações, respostas citadas, edição e exclusão, histórico do celular.
- **Chat interno entre agentes**, com os limites da edição aberta.
- **Conversas e mensagens:** mensagens agendadas, edição com histórico, conversas fixadas, assinatura por caixa, filtros personalizados.
- **Automações e integrações:** gatilhos novos, bots observadores, webhook por caixa de entrada.
- **Operação:** white label ([CUSTOM_BRANDING.md](CUSTOM_BRANDING.md); o flow-chat o usa para o nome e a tela de login), envio de e-mail pelo Resend, armazenamento compatível com S3, relatórios ordenáveis.

## Imagem e deploy

- **Imagem:** privada, `ghcr.io/mauromachadon1992/chatwoot`, com as tags `<versão>-<sha>-ee` (imutável, a que se fixa em produção), `<sha>-ee`, `<versão>-ee` e `latest-ee`. Ela traz `enterprise/` e `custom/`. A imagem pública da fazer.ai **não** serve: ela remove `enterprise/` e não tem `custom/`.
- **Construir e publicar:** `custom/docker/build-ee` e `custom/docker/publish-ghcr`. Rodar a imagem na sua máquina: `custom/docker/ee-local up` (http://localhost:3100, com banco e Redis próprios).
- **Coolify:** `custom/docker/coolify.compose.yaml` (produção) e `custom/docker/coolify.staging.compose.yaml` (homologação, com PostgreSQL e Redis próprios). O passo a passo e as tags estão em [`custom/docker/README.md`](custom/docker/README.md).
- **Desenvolvimento:** Docker, com `docker compose`; as regras do projeto estão em [AGENTS.md](AGENTS.md) e as de interface em [DESIGN.md](DESIGN.md).

## Atualizar a partir do upstream

O tronco do flow-chat é `feat/kanban`; a `main` espelha o fork da fazer.ai e não recebe commits nossos. Traga o upstream por merge, de preferência em tag, e confira os arquivos do upstream que tocamos, listados em [`custom/README.md`](custom/README.md) ("Upstream files we touch"). Faça backup do banco antes de trocar a imagem.

## Licença

O Chatwoot original tem copyright (c) 2017-2026 Chatwoot Inc. e usa a licença MIT, exceto o conteúdo de `enterprise/`, que segue os termos de [enterprise/LICENSE](enterprise/LICENSE). Os recursos do `enterprise/` (SSO, Captain, logs de auditoria, funções personalizadas e os demais) exigem licença da Chatwoot Inc. em produção; o resumo do negócio por IA usa o Captain.

As alterações e adições do fork da fazer.ai têm copyright (c) 2025-2026 FAZER.AI LTDA e seguem os mesmos termos do código que estendem. As adições do flow-chat (`custom/` e os ganchos listados em `custom/README.md`) derivam desse código e não mudam os termos do que estendem. Componentes de terceiros mantêm suas respectivas licenças.

Ao redistribuir o software ou partes substanciais dele, mantenha os avisos de copyright e o aviso de permissão. A exigência também se aplica a cópias de arquivos individuais. Consulte [NOTICE](NOTICE) e [LICENSE](LICENSE) para os termos completos.

## Links

- **flow-agents:** `mauromachadon1992/flow-agents-ee`
- **Upstream:** [fork da fazer.ai](https://github.com/fazer-ai/chatwoot) · [Chatwoot oficial](https://www.chatwoot.com) · [código do Chatwoot oficial](https://github.com/chatwoot/chatwoot)
- **Suporte:** este repositório não tem suporte de terceiros; o suporte do produto original é da Chatwoot Inc. e da fazer.ai.
