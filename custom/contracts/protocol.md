# Protocolo entre o Chatwoot custom EE e o agents-ee

Fonte única, idêntica nos dois repositórios e coberta pelo `CONTRACT.sha256`: se um lado muda este arquivo sem o outro, o CI de um dos
dois fica vermelho. Aqui está **como os dois conversam**; o **estado** de cada lado mora no `custom/BACKLOG.md` do próprio repositório
(não se espelha um no outro: liga-se, não se copia).

- **CW** = `mauromachadon1992/chatwoot`, branch `feat/kanban` (Rails + Vue; o Kanban está em `custom/`).
- **AG** = `mauromachadon1992/flow-agents-ee`, branch `main` (cópia privada do fazer.ai agents, edição Free; o nosso código fica em `custom/`).

## 1. As camadas da conversa

| Camada | O que é | Documento | Quem implementa | Quem prova |
| --- | --- | --- | --- | --- |
| L1 dialeto Pro | as 15 operações que o cliente do Agents exige | `pro-kanban.md`, `pro-kanban.v1.schema.json` | CW | `spec/custom/kanban/pro_contract_spec.rb` (CW) e `custom/harness/run.ts` com o cliente real (AG) |
| L2 extensões Flow | capacidades e rotas que só o Flow tem | `flow-extensions.md` | CW | `spec/custom/kanban/flow_extensions_contract_spec.rb` (CW) e `custom/script/toolpack-check.ts` (AG) |
| L3 ferramentas | as ferramentas HTTP que levam o agente às extensões | `custom/toolpacks/*.json` (AG) | AG | `toolpack-check.ts` (AG): só URLs e capacidades do L2 |
| L4 identidade | o agente age como o usuário de serviço `agent_bot` | ADR-6 do `custom/BACKLOG.md` (AG) | CW | o histórico mostra `actor_kind: agent_bot` |
| L5 implantação | a imagem de cada lado e o staging | `custom/BACKLOG.md` de cada lado | o dono | o teste ponta a ponta no staging |

Regra de ouro: o Agents **não muda para caber no Flow** (ADR-1, ADR-2, ADR-3). O Flow se adapta ao dialeto (L1) e se oferece por
configuração (L2 e L3). Código novo no `src/` do AG só com decisão explícita do dono (o caso do PR #2 foi decidido: não).

## 2. Quem pode mudar o quê sozinho

| Mudança | CW sozinho | AG sozinho | Os dois, na mesma sessão |
| --- | --- | --- | --- |
| Tela, regra interna, tabela, spec do Kanban | sim | | |
| Campo novo na resposta de uma rota que já existe (aditivo) | sim, e anuncia em `flow-extensions.md` se o agente puder usar | | |
| Rota ou capacidade nova | | | **sim**: contrato, spec do CW, toolpack e verificação do AG |
| Ferramenta HTTP nova ou alterada no toolpack | | sim, desde que só use rotas e capacidades já anunciadas | |
| Remover ou mudar o sentido de algo anunciado | | | v2: capacidade nova, a antiga mantida uma versão |
| Sincronizar o upstream (`fazer-ai/agents`) | | sim, em tag (T-01 do backlog do AG) | se tocar `client.ts`, `kanban.ts` ou `native.ts`: reler o L1 antes |
| Publicar imagem, promover staging ou produção | | | só com o OK explícito do dono naquele turno |

## 3. Como uma mudança entre os dois repositórios acontece (nesta ordem)

1. **Dizer o que é**: no AG, uma issue (regra do AG: um PR fecha uma issue, `Fixes #N`); no CW, um item `B-xx` no `custom/BACKLOG.md`.
   Cada um cita o outro por id (`AG#12`, `B-14`), nunca copia o texto.
2. **Contrato primeiro**: editar `flow-extensions.md` (ou o L1) **nos dois repositórios**, depois `bun custom/script/contract-hash.ts
   --write` no AG; o CW lê o mesmo `CONTRACT.sha256`.
3. **CW implementa e prova**: rota, spec que cobre o contrato (a spec compara as capacidades anunciadas e as rotas do contrato com o
   código), gate completo, commit na `feat/kanban`.
4. **AG consome e prova**: o toolpack só usa rotas e capacidades do contrato; `toolpack-check.ts` e `contract-hash.ts` passam; PR com
   `Fixes #N`.
5. **Implantar**: imagem do CW publicada e staging promovido (o dono); depois `custom/script/apply-toolpack.ts` no agents do staging.
6. **Provar ponta a ponta** no staging com uma conversa nova (receita no `custom/BACKLOG.md` do CW) e só então marcar feito nos dois backlogs.
7. **Avisar o outro lado**: uma linha no backlog do outro repositório (regra R8 do AG), com o id e o SHA.

Ordem de merge: o contrato entra nos dois **antes** de qualquer consumidor. Um consumidor que aparece antes da capacidade anunciada
fica inerte (as ferramentas verificam a capacidade), nunca quebrado.

## 4. Issues, PRs e rótulos

- **AG**: toda PR tem `Fixes #N`; uma issue com três entregas vira três issues. Rótulos: `contract` (mexe nos arquivos de
  `custom/contracts/`), `cross-repo` (depende ou impõe algo ao CW), `decision` (espera o dono), `held` (aberta de propósito, não mesclar).
  O modelo de PR (`.github/pull_request_template.md`) pergunta: mexe no contrato? anuncia ou usa uma capacidade? precisa de imagem
  nova? Quem decide o merge é o dono.
- **CW**: o trabalho vai em ramo a partir de `feat/kanban`; o histórico de decisões fica no `custom/BACKLOG.md` (B-xx), e o que o agente
  precisa saber vai para o contrato, não para o backlog.
- **PR retido não se apaga**: fica aberto com o rótulo `held` e um comentário que diz o que decide. Um PR decidido contra é **fechado**
  (não mesclado) com a decisão no comentário, e o ramo fica como referência até o dono pedir para apagar.

## 5. Versões e estado

- Cada backlog guarda o seu bloco `STATE` (SHAs, imagem no staging) e o atualiza ao fim de toda sessão. Antes de confiar nele, confira
  com os comandos da seção "Session start" do backlog do AG; outra sessão ou o dono pode ter commitado depois.
- Imagens: o CW publica `ghcr.io/mauromachadon1992/chatwoot:<versão>-<sha>-ee` (imutável) e o AG `…/agents-ee:<sha>`. O staging fixa as
  duas por tag. A tag no ar é registrada no `STATE` do backlog de quem a publicou.
- Hash do contrato: o mesmo `CONTRACT.sha256` nos dois lados, sobre os bytes (arquivos em LF, ver `.gitattributes`).

## 6. A escada de provas (do mais barato ao mais caro)

1. `bun custom/script/contract-hash.ts` (AG) e a spec do hash (CW): o contrato não mudou sem o outro lado.
2. `bun custom/script/toolpack-check.ts` (AG): o toolpack só usa o que o contrato anuncia.
3. `spec/custom/kanban/flow_extensions_contract_spec.rb` e `pro_contract_spec.rb` (CW): o servidor cumpre o que o contrato diz.
4. `custom/harness/run.ts` (AG, cliente real contra o CW): as 15 operações do L1.
5. Conversa ponta a ponta no staging: cliente, agente, Kanban, histórico `agent_bot`.
