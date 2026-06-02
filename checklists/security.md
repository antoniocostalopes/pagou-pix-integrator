# Checklist — Segurança

## Críticos (bloqueiam liberação)

- [ ] **API key apenas backend.** Grep negativo de `PAGOU_API_KEY` em arquivos client/browser:
  - Next.js: `grep -r "PAGOU_API_KEY" src/app src/components src/pages` → 0 ocorrências em código que vai para o browser. Aceito em `app/api/`, `pages/api/`, `src/lib/` que rodam server-side.
  - Laravel: zero ocorrências em `resources/js/`
  - Sempre evitar variáveis prefixadas `NEXT_PUBLIC_`, `VITE_`, `REACT_APP_` para a key.

- [ ] **Sem segredos no repositório.** `git log -S PAGOU_API_KEY -- .` retorna vazio. `.env` está no `.gitignore` (linha verificada).

- [ ] **Sem segredos em logs.**
  - Logger não imprime o header `Authorization`
  - Logger não imprime o objeto de configuração completo do cliente Pagou
  - Mensagens de erro mascaram a key (ex.: `pagou.error.401: api key inválida (***)`)

- [ ] **HTTPS na URL pública.** A URL pública configurada começa com `https://` (exceto `localhost`).

- [ ] **Webhook não aceita payload arbitrário.** Validação básica antes de inserir:
  - `event === "transaction"` (para fluxo PIX)
  - `id` (top-level) não vazio
  - `data` é objeto

## Importantes

- [ ] **Variáveis no painel do provedor de deploy.** Não apenas no `.env` local. Confirmação visual ou via CLI do provedor (Vercel, AWS, etc.).

- [ ] **Permissões dos endpoints.**
  - `POST /api/pagou/pix` exige sessão autenticada do projeto
  - `POST /admin/pagou/reconcile/:id` exige permissão admin
  - `POST /webhooks/pagou` é público, mas só persiste eventos válidos

- [ ] **CSRF.** Em frameworks que validam CSRF por padrão (Laravel, Django, Rails), o endpoint de webhook está na **allowlist** (sem CSRF, porque é chamado por terceiro).

- [ ] **Rate limiting.**
  - `POST /api/pagou/pix` tem rate limit por usuário (sugestão: 10/min)
  - `POST /webhooks/pagou` confia na Pagou (sem rate limit do lado da app — apenas no infra/CDN se houver)

- [ ] **Tratamento de erros sem leak.** Resposta de erro ao client **não** expõe stack trace nem detalhes internos.

## Recomendados

- [ ] **Rotacionar API key periodicamente** (procedimento documentado em `README_PAGOU_PIX.md`).

- [ ] **Auditoria de acesso.** Logs com `user_id` em todas as criações de cobrança.

- [ ] **Allowlist de IPs da Pagou no webhook** (se Pagou publicar range — verificar docs; se não publicar, deixar pendente).

- [ ] **HMAC do webhook.** Se Pagou suportar header de assinatura, validar. Se não documentado, não inventar — deixar como follow-up.

- [ ] **Backup/retention da `pagou_pix_transactions`.** Garantir que está no escopo do backup do projeto.

## Evidência mínima por item

Para cada ✓:

```markdown
- [x] {{item}}
      Evidência: {{arquivo:linha ou comando + resultado}}
```

Para cada ✗ crítico:

```markdown
- [ ] {{item}}
      Status: bloqueado
      Plano: {{como será resolvido antes do go-live}}
```
