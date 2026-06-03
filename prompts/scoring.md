# Prompt — Scoring (Fase 6)

**Objetivo:** calcular score 0–100 conforme as 6 categorias do PRD e gerar `PAGOU_PIX_INTEGRATION_SCORE.md`.

## Categorias e pesos

| Categoria | Peso máximo |
|---|---|
| Configuração | 15 |
| Arquitetura | 15 |
| PIX | 20 |
| Webhooks | 20 |
| Segurança | 15 |
| Confiabilidade | 15 |
| **Total** | **100** |

## Algoritmo de pontuação por categoria

Cada categoria tem ~5 critérios. Cada critério vale uma fração do peso. Se atingir o critério → soma. Se atingir parcial → soma proporcional. Se não atingir → 0.

### Configuração (15)

| Critério | Pontos |
|---|---|
| `.env.example` atualizado com todas as variáveis Pagou | 3 |
| `.env` está no `.gitignore` (verificado) | 2 |
| Variáveis lidas só no servidor (zero ocorrências em arquivos client) | 3 |
| Base URL `https://api.pagou.ai` hardcoded no cliente (sem env var configurável; Skill v3+ não suporta sandbox) | 3 |
| Documentação operacional em `README_PAGOU_PIX.md` | 4 |

### Arquitetura (15)

| Critério | Pontos |
|---|---|
| Código segue o padrão arquitetural do projeto (não introduz novo) | 4 |
| Tabelas com nomes alinhados à convenção do projeto | 2 |
| Logger do projeto usado (não `console.log` cru, se houver alternativa) | 2 |
| Error handling segue o estilo do projeto | 3 |
| Separação clara: cliente HTTP, serviço, controller, persistência | 4 |

### PIX (20)

| Critério | Pontos |
|---|---|
| Endpoint `POST /api/pagou/pix` (ou equivalente) implementado | 4 |
| Valores em centavos (verificado com teste) | 3 |
| `external_ref` sempre enviado (verificado em teste) | 3 |
| Resposta retorna `pix_qr_code` e `pix_code` | 2 |
| Upsert por `external_ref` (idempotência da criação) | 3 |
| Status inicial persistido conforme retorno da Pagou | 2 |
| Status mapping com todos os 8 status conhecidos + fallback | 3 |

### Webhooks (20)

| Critério | Pontos |
|---|---|
| Endpoint público funcional | 3 |
| ACK rápido `{ received: true }` antes de processar | 3 |
| Tabela `pagou_webhook_events` com `event_id` UNIQUE | 4 |
| Dedup por `event.id` (top-level), **não** por `data.id` | 4 |
| Processamento assíncrono (job/fila/background) | 3 |
| Todos os eventos relevantes (`paid`, `cancelled`, `refunded`, `chargedback`) tratados | 3 |

### Segurança (15)

| Critério | Pontos |
|---|---|
| `PAGOU_API_KEY` apenas backend (grep negativo no client) | 4 |
| Sem segredos commitados (`.env` ausente do histórico) | 3 |
| Logs não vazam `Authorization` nem API key | 3 |
| Payload de webhook validado antes de processar | 2 |
| HTTPS obrigatório em produção | 3 |

### Confiabilidade (15)

| Critério | Pontos |
|---|---|
| Reconciliação implementada (`GET /v2/transactions/:id`) | 4 |
| Endpoint admin de reconciliação manual | 2 |
| Job noturno ou cron de reconciliação documentado | 3 |
| Testes (unit + integration + webhook + e2e) passando | 4 |
| Logs estruturados (não strings soltas) | 2 |

## Classificação

| Total | Classificação |
|---|---|
| 95–100 | **Enterprise Ready** |
| 90–94 | **Production Ready** |
| 80–89 | Minor Improvements |
| 70–79 | Needs Review |
| 0–69 | Not Ready |

## Política de liberação

- Score < 90: **bloqueado para produção sem revisão humana**
- Score 90–94: pronto para deploy controlado (canary, feature flag, monitoring extra)
- Score 95–100: liberado, monitorar como qualquer outra rota crítica

## Formato do relatório

Gerar `PAGOU_PIX_INTEGRATION_SCORE.md` na raiz do projeto-alvo, a partir de `templates/PAGOU_PIX_INTEGRATION_SCORE.md`. Estrutura:

```markdown
# Score: 92/100 — Production Ready

| Categoria | Pontos | Máximo |
|---|---|---|
| Configuração | 13 | 15 |
| Arquitetura | 14 | 15 |
| PIX | 19 | 20 |
| Webhooks | 18 | 20 |
| Segurança | 14 | 15 |
| Confiabilidade | 14 | 15 |
| **Total** | **92** | **100** |

## Detalhes por categoria
(... cada critério com ✓/✗ e justificativa)

## Para chegar a 95+
- [ ] Implementar job noturno automatizado (+1)
- [ ] Adicionar métrica de duração do webhook (+1)
- [ ] Cobertura de testes acima de 90% (+1)
```

## Regras

- **Honestidade.** Não inflar score para fechar tarefa. Se a Skill não conseguiu validar um critério, marcar como 0 e listar o que falta.
- **Evidência.** Cada ponto atribuído deve ter referência de arquivo/linha ou teste verificado.
- **Determinismo.** Mesmas entradas → mesmo score. Se algo for subjetivo, escolher uma régua clara (ex.: "logger do projeto" significa "está importado pelo menos uma vez no código gerado").
