# SecureFoundry

A Claude Code skill that bootstraps a new project onto a secure, compliant-from-day-one platform: multi-account cloud structure, a gated CI/CD pipeline, VPN-only network access, encryption and secrets management, and the audit-mapped monitoring to prove all of it — instead of every team re-deriving the same security architecture from scratch, usually after an incident forces the issue.

This isn't a framework or a SaaS product. It's a `SKILL.md` your Claude Code session loads, which then asks you a handful of setup questions and walks you (and Claude) through standing up the real infrastructure, one reviewed decision at a time.

## Status — read this before you start

**AWS is the only fully tested, production-proven implementation.** Every pattern under `skills/secure-platform-factory/terraform/aws/` and every claim in the AWS-specific reference docs was extracted from a real platform that has been running in multiple live AWS accounts, gone through independent adversarial security review, and had real vulnerabilities found and fixed (see `reference/security-history.md` for the specific issues caught — a wildcard OIDC trust-policy match, an under-encrypted RDS master secret, a cross-subdomain cookie vulnerability — each with what was wrong and how it was fixed).

**GCP and Azure are designed, not yet battle-tested.** The patterns are the same (same account/project isolation model, same CI/CD gate structure, same encryption and secrets discipline), mapped onto each cloud's native equivalent services. They have not run in a real production environment yet. Treat them as a well-reasoned starting point that needs your own review, not a proven default. Contributions that report real production experience with the GCP or Azure paths — especially anything that breaks — are the single most valuable kind of issue you can file.

## What this actually sets up

- **Multi-account/project isolation** — separate environments (dev/test/staging/prod) as separate cloud accounts or projects, not just separate namespaces in one account, plus dedicated accounts for security-log aggregation and centralized identity/billing.
- **A gated CI/CD pipeline** — SAST, secret scanning, container + license scanning, dependency-vulnerability scanning, IaC scanning, and DAST, each with an open-source default and a documented paid alternative (see `reference/cicd-pipeline.md`), keyless cloud authentication via OIDC federation, and a build-once-promote-forward artifact model.
- **VPN-only network access** — no database or internal service ever gets a public IP; a documented VPN pattern (with an open-source default) replaces bastion hosts entirely.
- **Encryption and secrets discipline** — customer-managed encryption keys per environment, secrets injected at the runtime layer only, never in code or plain environment files.
- **Audit-mapped monitoring** — the detective controls (intrusion/threat detection, config drift, findings aggregation) each tagged against the SOC 2 Trust Services Criteria / NIST CSF 2.0 category they satisfy, so what you stand up is provably audit-ready, not just "good practice."
- **A GitHub setup walkthrough** — the literal ruleset, required-check, and environment-protection configuration, scriptable via `gh api`/`gh ruleset` rather than clicked through by hand.
- **A review culture, not just review tooling** — what a real maker-checker review actually requires, when a second independent round is warranted, and how a documented development process (requirements → architecture → adversarial review → code) itself counts as a change-management control in an audit.

## Getting started

```
/plugin install secure-foundry
```

or copy `skills/secure-platform-factory/` into your own project's `.claude/skills/` directory. Then, in a Claude Code session in your target repository:

```
/secure-platform-factory
```

The skill will ask which cloud you're targeting, which VPN pattern you want, and whether you're starting from the open-source tool defaults or already have paid tooling in place — then walk through the setup in the order laid out in `reference/build-order.md`.

## Repository layout

```
skills/secure-platform-factory/
  SKILL.md                    # entry point — routes to the reference docs below
  reference/
    accounts-aws.md           # proven
    accounts-gcp.md           # designed, untested
    accounts-azure.md         # designed, untested
    cicd-pipeline.md          # cloud-agnostic tool matrix
    network-vpn.md            # cloud-agnostic VPN pattern + per-cloud wiring
    encryption-secrets-aws.md
    encryption-secrets-gcp.md
    encryption-secrets-azure.md
    authn-authz.md            # cloud-agnostic identity/RBAC pattern
    monitoring-compliance-aws.md
    monitoring-compliance-gcp.md
    monitoring-compliance-azure.md
    github-setup.md
    review-culture.md
    security-history.md       # real vulnerabilities caught in the AWS implementation, and the fix
    build-order.md
  terraform/
    aws/       # complete, tested
    gcp/       # in progress
    azure/     # in progress
  workflows/   # GitHub Actions templates, parameterized per cloud
```

## Contributing

See `CONTRIBUTING.md`. The short version: this project holds itself to the same review discipline it recommends (`reference/review-culture.md`) — a PR that changes a security-relevant default gets an independent adversarial review, not a single-approver rubber stamp, before merge.

## License

Apache 2.0 — see `LICENSE`. Chosen deliberately over MIT for its explicit patent grant; see the project history for the reasoning if you're deciding this for your own project too.
