## O quê

<!-- 1-2 frases sobre o que muda -->

## Porquê

<!-- O problema que isto resolve, motivação técnica/de negócio -->

## Como testaste

<!-- Comandos correu, projetos onde aplicaste, screenshots -->

## Tipo de mudança

- [ ] Bug fix (não-breaking, corrige algo errado)
- [ ] Feature nova (não-breaking, adiciona capacidade)
- [ ] Breaking change (consumidores existentes vão precisar adaptar)
- [ ] Documentação only
- [ ] Refactor (sem mudar comportamento)
- [ ] Build / CI / repo hygiene

## Checklist

- [ ] Atualizei `CHANGELOG.md` com a entrada apropriada
- [ ] Atualizei versão em `SKILL.md`, `plugin.json`, `marketplace.json` se aplicável (SemVer)
- [ ] Atualizei badge de versão no README se bumpei a versão
- [ ] Mantive os princípios do `CLAUDE.md`:
  - [ ] Dedup por `event.id` (top-level), nunca por `data.id`
  - [ ] Valores em centavos
  - [ ] `external_ref` em toda escrita
  - [ ] `PAGOU_API_KEY` apenas backend
  - [ ] Webhook ACK rápido `{ received: true }`
- [ ] Se mudei um adapter, mudei TODOS os afectados (ou justifiquei por que só um)
- [ ] Se adicionei novo critério ao score, atualizei `docs/scoring-engine.md`

## Issue relacionada

Closes #
