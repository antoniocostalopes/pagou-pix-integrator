# Scoring Engine — algoritmo determinístico

Define como calcular o score 0–100 com **determinismo**: mesmas entradas → mesmo score.

## Entradas

A engine recebe um inventário do que foi gerado/validado:

```yaml
config:
  env_example_updated: bool
  gitignore_has_env: bool
  vars_backend_only: bool      # grep negativo
  base_url_by_env: bool
  docs_present: bool

architecture:
  follows_project_pattern: bool
  naming_aligned: bool
  uses_project_logger: bool
  error_handling_consistent: bool
  layers_separated: bool

pix:
  create_endpoint_exists: bool
  amount_in_cents_verified: bool
  external_ref_always: bool
  response_has_qr_and_code: bool
  upsert_by_external_ref: bool
  initial_status_persisted: bool
  status_mapping_complete: bool

webhooks:
  endpoint_exists: bool
  ack_fast: bool                # < 1s tipicamente
  event_id_unique_constraint: bool
  dedupe_by_top_level_event_id: bool
  async_processing: bool
  all_relevant_events_handled: bool

security:
  api_key_backend_only: bool
  no_secrets_committed: bool
  logs_safe: bool
  payload_validated: bool
  https_enforced: bool

reliability:
  reconcile_function: bool
  admin_reconcile_endpoint: bool
  scheduled_reconcile_documented: bool
  tests_passing: bool
  structured_logs: bool
```

## Tabela de pesos

```yaml
config:
  env_example_updated:  3
  gitignore_has_env:    2
  vars_backend_only:    3
  base_url_by_env:      3
  docs_present:         4
  # total: 15

architecture:
  follows_project_pattern:  4
  naming_aligned:           2
  uses_project_logger:      2
  error_handling_consistent: 3
  layers_separated:         4
  # total: 15

pix:
  create_endpoint_exists:   4
  amount_in_cents_verified: 3
  external_ref_always:      3
  response_has_qr_and_code: 2
  upsert_by_external_ref:   3
  initial_status_persisted: 2
  status_mapping_complete:  3
  # total: 20

webhooks:
  endpoint_exists:               3
  ack_fast:                      3
  event_id_unique_constraint:    4
  dedupe_by_top_level_event_id:  4
  async_processing:              3
  all_relevant_events_handled:   3
  # total: 20

security:
  api_key_backend_only:  4
  no_secrets_committed:  3
  logs_safe:             3
  payload_validated:     2
  https_enforced:        3
  # total: 15

reliability:
  reconcile_function:              4
  admin_reconcile_endpoint:        2
  scheduled_reconcile_documented:  3
  tests_passing:                   4
  structured_logs:                 2
  # total: 15

# Total geral: 100
```

## Algoritmo

```python
def score(inventory: dict) -> dict:
    weights = WEIGHTS  # tabela acima

    result = {}
    total = 0
    max_total = 0

    for category, items in weights.items():
        cat_score = 0
        cat_max = 0
        for key, weight in items.items():
            cat_max += weight
            if inventory[category].get(key, False):
                cat_score += weight
        result[category] = {"score": cat_score, "max": cat_max}
        total += cat_score
        max_total += cat_max

    result["total"] = total
    result["max"] = max_total
    result["classification"] = classify(total)
    return result


def classify(total: int) -> str:
    if total >= 95: return "Enterprise Ready"
    if total >= 90: return "Production Ready"
    if total >= 80: return "Minor Improvements"
    if total >= 70: return "Needs Review"
    return "Not Ready"
```

## Itens parciais

Alguns critérios podem ser **parciais**. Quando aplicável, usar `0`, `0.5×weight` ou `weight`:

| Critério | Parcial possível? | Quando |
|---|---|---|
| `docs_present` | sim | Existe mas incompleto → 50% |
| `error_handling_consistent` | sim | Maior parte segue, alguns lugares destoam |
| `status_mapping_complete` | sim | Mapeia 6/8 status corretamente |
| `all_relevant_events_handled` | sim | Cobre `paid` e `cancelled` mas não `refunded` |
| `tests_passing` | sim | 80% passando → proporcional |
| `scheduled_reconcile_documented` | sim | Documentado mas não implementado em cron real |

Demais critérios são **binários**.

## Regras de cálculo

1. **Honestidade.** Se a Skill não conseguiu verificar um item, marcar como `false` (0 pontos). Não inflar.
2. **Verificação automática.** Sempre que possível, derivar do código gerado (grep, AST). Verificações que dependem de inspeção humana ficam pendentes até confirmação.
3. **Sem bônus.** Não há pontuação extra por funcionalidades fora do escopo PIX (subscriptions, transfers).
4. **Sem penalidade negativa.** Score mínimo é 0.

## Faixas e ações

| Score | Classificação | Ação |
|---|---|---|
| 95–100 | Enterprise Ready | Liberar |
| 90–94 | Production Ready | Liberar com monitoramento extra |
| 80–89 | Minor Improvements | Listar gaps e corrigir antes de prod |
| 70–79 | Needs Review | Revisão humana obrigatória |
| 0–69 | Not Ready | Não deploy. Re-trabalhar. |

## Relatório

Sempre gerar `PAGOU_PIX_INTEGRATION_SCORE.md` com:

- Score total
- Tabela por categoria
- Detalhes por critério (✓/✗ + evidência)
- "Para chegar a 95+" (lista de itens parciais que faltam pontos)
- "Para chegar a 100" (lista de tudo que falta)

## Re-avaliação

Recalcular score quando:

- Código é modificado após a primeira execução da Skill
- Bug é encontrado em produção
- Pagou publicar novos eventos ou status que afetem o mapping
- Mudança de versão da API Pagou (v3, etc.)
