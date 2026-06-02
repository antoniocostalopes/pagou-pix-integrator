# Security Policy

Esta Skill manipula código que processa **pagamentos PIX** em produção. Reportes de vulnerabilidade são levados a sério.

## Versões suportadas

| Versão | Suportada |
|---|---|
| 1.2.x | ✅ |
| 1.1.x | ⚠️ apenas correções críticas |
| < 1.1 | ❌ |

## Como reportar uma vulnerabilidade

**NÃO abras issue pública** para vulnerabilidades. Em vez disso:

1. Usa GitHub Security Advisories: <https://github.com/antoniocostalopes/pagou-pix-integrator/security/advisories/new>
2. Ou envia email cifrado para `security@dantetesta.com.br` (verificar GPG key no GitHub profile)

Inclui no reporte:

- Versão da Skill afetada
- Descrição do impacto (e.g., "permite forjar webhook como se fosse da Pagou")
- Passos para reproduzir
- POC ou exploit se possível
- Patch sugerido (opcional)

## Janela de resposta esperada

| Etapa | SLA |
|---|---|
| Confirmação de receção | 48h |
| Triagem inicial | 5 dias |
| Patch ou mitigação | 30 dias para criticos, 90 para baixo impacto |
| Disclosure público | Acordado contigo (mínimo 30 dias após patch) |

## Escopo

### Em escopo

- Vulnerabilidades nos **adapters de framework** que esta Skill gera (Next.js, Laravel, WordPress, WooCommerce, Generic)
- Falhas que permitam **forjar webhooks** (bypass HMAC, replay)
- Vazamento de **secrets** (`PAGOU_API_KEY`, `PAGOU_WEBHOOK_SECRET`) em ficheiros gerados, logs, ou frontend
- Falhas no **modelo de aprovação humana** que permitem modificar projetos sem consentimento
- SQL injection / XSS / IDOR / auth bypass no código que esta Skill produz
- Race conditions na deduplicação de webhooks

### Fora de escopo

- Vulnerabilidades na **API da Pagou.ai** propriamente dita (reportar diretamente à Pagou)
- Vulnerabilidades no **Claude Code CLI** (reportar à Anthropic)
- Bugs de software de terceiros (ORM, framework, etc.) que esta Skill apenas usa
- Issues que requerem acesso físico à máquina do utilizador
- DoS por consumo legítimo de recursos
- Engenharia social

## Boas práticas para utilizadores

Ao usar esta Skill em produção:

1. **Mantém a versão atualizada** — `git pull` no folder `~/.claude/skills/pagou-pix-integrator/` ou `/plugin marketplace update`
2. **Rotaciona `PAGOU_API_KEY` periodicamente** — pelo menos a cada 90 dias
3. **Define `PAGOU_WEBHOOK_SECRET`** em produção — sem ele, webhooks podem ser forjados
4. **Audita o código gerado** — não te fies cegamente; corre `/code-review` ou equivalente antes de merge
5. **Subscreve releases** — `Watch → Custom → Releases` no GitHub para receber notificação de patches de segurança
6. **Monitoriza alertas** — importa `docs/observability/prometheus-alerts.yml` para detectar abuso

## Reconhecimento

Reportes confirmados são reconhecidos no `CHANGELOG.md` e (com permissão) num "Hall of Fame" em `SECURITY.md`. Não oferecemos bug bounty monetário no momento.
