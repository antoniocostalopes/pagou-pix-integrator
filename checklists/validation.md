# Checklist — Validação Funcional e de Testes

## Críticos

- [ ] **Status mapping cobre os 8 status conhecidos.**
  - `pending`, `paid`, `expired`, `canceled`, `refused`, `refunded`, `partially_refunded`, `chargedback`
  - Função `mapStatus` retorna valor não-vazio para cada um
  - Fallback para `desconhecido` em entrada não prevista

- [ ] **Valores em centavos verificado por teste.** R$ 15,00 → payload `amount: 1500`. Teste explícito.

- [ ] **`external_ref` enviado em toda criação.** Teste verifica payload outbound.

- [ ] **Teste de dedup de webhook passa.** POST duplicado com mesmo `event.id` → 1 linha persistida.

- [ ] **Teste e2e do fluxo feliz passa.** Create → webhook paid → order pago.

- [ ] **Cliente HTTP loga `requestId` quando devolvido pela Pagou.** (v3.0.1+)
  - Headers verificados: `x-request-id` e `x-pagou-request-id`
  - Loga `{ event: "pagou.api.call", path, status, requestId }` em chamadas bem e mal sucedidas
  - Em erro, propaga no `PagouError.requestId` / `PagouException::$requestId` para facilitar troubleshooting com suporte oficial
  - **Não** loga payload nem chave de API junto

## Importantes

- [ ] **Cobertura de testes ≥ 80%** nas linhas/branches do código novo. Comando padrão do framework:
  - JS/TS: `npm test -- --coverage` ou `vitest --coverage`
  - PHP: `phpunit --coverage-text`
  - Python: `pytest --cov`
  - Ruby: `simplecov`
  - Go: `go test -cover ./...`

- [ ] **Suítes nomeadas pelo escopo.** `unit/`, `integration/`, `webhook/`, `e2e/` (ou prefixos correspondentes na convenção do projeto).

- [ ] **Testes determinísticos.** Não dependem de ordem, sleep, datas reais, conexão externa (mockar Pagou em CI). Sandbox real só em testes locais quando explicitamente flagado.

- [ ] **CI roda os testes.** Pipeline atualizada para incluir `tests/pagou/*`. Verificar passada verde antes do merge.

## Recomendados

- [ ] **Testes de carga leves** no endpoint de webhook (100 RPS por 1 min) — não deve travar.

- [ ] **Testes de erro da Pagou** — simular 401, 500, timeout, e validar comportamento do cliente.

- [ ] **Snapshots de payload** — guardar exemplos gerados pelo `tools/pagou-mock/` para regressão.

- [ ] **Fuzz no webhook** — payloads malformados não derrubam o handler.

## Validações funcionais (contra `tools/pagou-mock/`)

A Skill v3+ só fala com produção (`https://api.pagou.ai`). Para validar sem cobranças reais, apontar o cliente HTTP local para `tools/pagou-mock/` (ver README do mock) e executar manualmente:

- [ ] Criar cobrança de R$ 0,01 → recebe QR válido e copia-e-cola
- [ ] QR code renderiza como imagem PNG no frontend
- [ ] Copia-e-cola tem comprimento > 100 chars (BR Code real)
- [ ] Mock dispara webhook simulado (HMAC válido) → handler recebe
- [ ] Status do pedido vira `pago` em menos de 5s após o webhook simulado
- [ ] Reconciliação manual retorna status correto
- [ ] Cobrança expirada vira `expirado` após webhook correspondente (cenário `expire-` do mock)
- [ ] Antes do go-live, smoke test em produção com R$ 1,00 e pagamento real, conforme `checklists/production.md`

## Validações de regressão

- [ ] Outros fluxos do projeto continuam funcionando (smoke tests existentes passam)
- [ ] Outras rotas de pagamento (se houver) não foram afetadas
- [ ] Migrações são reversíveis (ou documentado quando não são)

## Evidência

Para cada ✓:

```markdown
- [x] {{item}}
      Evidência: `{{nome do teste}}` em `{{arquivo:linha}}` — ✓ em {{Xms}}
```

## Quando re-rodar

- Antes de cada release que toca código Pagou
- Em CI a cada push
- Manualmente após qualquer mudança no esquema de eventos da Pagou
