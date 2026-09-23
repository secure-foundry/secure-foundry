# SecureFoundry

A Claude Code skill that bootstraps a new project onto a secure, compliant-from-day-one cloud platform: multi-account isolation, a gated CI/CD pipeline, VPN-only network access, encryption and secrets management, and the audit-mapped monitoring to prove all of it — instead of every team re-deriving the same security architecture from scratch, usually after an incident forces the issue.

This isn't a framework or a SaaS product, and it isn't a generic "best practices" document either. It's a working `SKILL.md` your Claude Code session loads, which asks you a handful of setup questions, then walks you (and Claude) through standing up the real infrastructure — real Terraform, real GitHub Actions workflows, real `gh api` commands — one reviewed decision at a time.

## Who this is for

- **A team standing up a new product on a fresh cloud footprint** who wants the security/compliance architecture right from the first commit, not retrofitted after a customer's security questionnaire or an audit forces the issue.
- **A founding engineer who's done this before at a previous company** and wants a real, working starting point instead of re-deriving the same account structure, CI gates, and network isolation pattern from memory, with the same mistakes re-introduced along the way.
- **A team that needs to be SOC 2 / NIST CSF 2.0-ready** but doesn't have a dedicated security engineer yet — every control here is tagged against the specific framework category it satisfies, so what you stand up is evidence you can hand to an auditor, not just something that felt like a good idea.

## Who this is *not* for

- **A team with an existing, mature cloud platform.** This is a bootstrap tool for a new footprint, not a migration tool for an existing one. Retrofitting these patterns onto years of existing infrastructure is a much bigger, more careful undertaking than this skill's own build order assumes.
- **A team that needs a fourth cloud provider, or a different compute model** (this targets serverless-container compute — ECS Fargate, Cloud Run, Container Apps — not Kubernetes, not VMs-as-the-primary-unit). The patterns generalize, but the actual Terraform doesn't cover those shapes today.

## Status — read this before you start

**AWS is battle-tested and proven.** Every pattern under `skills/secure-platform-factory/terraform/aws/` and every claim in the AWS-specific reference docs was extracted from a real platform that has been running in multiple live AWS accounts, gone through independent adversarial security review, and had real vulnerabilities found and fixed (see `skills/secure-platform-factory/reference/security-history.md` for the specific issues caught — a wildcard OIDC trust-policy match, an under-encrypted RDS master secret, a cross-subdomain cookie vulnerability — each with what was wrong and how it was fixed).

**GCP and Azure are work in progress.** The patterns are the same (same account/project isolation model, same CI/CD gate structure, same encryption and secrets discipline), mapped onto each cloud's native equivalent services, and every module validates cleanly — they're just earlier in the same journey AWS has already been through: real production mileage and adversarial review. Contributions that put either path through real production use — especially anything that surfaces a fix — are the single most valuable kind of issue you can file (see `CONTRIBUTING.md`), and are exactly how the AWS path got to where it is now.

## What this actually sets up

- **Multi-account/project isolation** — separate environments (dev/test/staging/prod) as separate cloud accounts or projects, not just separate namespaces in one account, plus dedicated accounts for security-log aggregation and centralized identity/billing.
- **A gated CI/CD pipeline** — SAST, secret scanning, container + license scanning, dependency-vulnerability scanning, IaC scanning, DAST, and application QA (unit + integration tests, a real coverage gate), each with an open-source default and a documented paid alternative (see `skills/secure-platform-factory/reference/cicd-pipeline.md`), keyless cloud authentication via OIDC federation, and a build-once-promote-forward artifact model.
- **VPN-only network access** — no database or internal service ever gets a public IP; a documented VPN pattern (with an open-source default) replaces bastion hosts entirely.
- **Encryption and secrets discipline** — customer-managed encryption keys per environment, secrets injected at the runtime layer only, never in code or plain environment files.
- **Audit-mapped monitoring** — the detective controls (intrusion/threat detection, config drift, findings aggregation) each tagged against the SOC 2 Trust Services Criteria / NIST CSF 2.0 category they satisfy, so what you stand up is provably audit-ready, not just "good practice."
- **A GitHub setup walkthrough** — the literal ruleset, required-check, and environment-protection configuration, scriptable via `gh api` rather than clicked through by hand (this very repo's own `main` branch is configured exactly this way — see it live via `gh api repos/secure-foundry/secure-foundry/rules/branches/main`).
- **A review culture, not just review tooling** — what a real maker-checker review actually requires, when a second independent round is warranted, and how a documented development process (requirements → architecture → adversarial review → code) itself counts as a change-management control in an audit.

## Installation

There's no package manager or plugin marketplace step — a skill is just a directory Claude Code reads.

1. Clone this repo, or download it as a zip:
   ```
   git clone https://github.com/secure-foundry/secure-foundry.git
   ```
2. Copy the skill directory into your **own project's** `.claude/skills/` folder (create that folder if it doesn't exist yet):
   ```
   cp -r secure-foundry/skills/secure-platform-factory /path/to/your-project/.claude/skills/
   ```
3. That's it. Nothing to build, no dependencies to install for the skill itself — `SKILL.md` is plain instructions Claude Code reads directly. (You will need [Terraform](https://developer.hashicorp.com/terraform/install) and the [GitHub CLI](https://cli.github.com/) installed locally, or ask Claude to check for them, since the skill will actually run `terraform` and `gh` commands as it works.)

## Usage

Open a Claude Code session **inside your own project** (not inside this repo) and describe what you want, in your own words — for example:

> "Set up a secure, compliant AWS platform for this project using the secure-platform-factory skill."

Claude Code discovers the skill automatically from its `.claude/skills/` folder and loads it once your request matches its description. If you'd rather be explicit, name it directly:

> "Use the secure-platform-factory skill to bootstrap our infrastructure."

From there, the skill will:
1. Ask you a handful of setup questions — which cloud, which VPN pattern, whether you're starting from the open-source tool defaults or already hold licenses for paid tooling.
2. Read `skills/secure-platform-factory/reference/build-order.md` and work through the phases in that order (account structure first, then network, then encryption, then CI/CD, and so on) rather than jumping straight to code.
3. Adapt the real Terraform under `terraform/<your-cloud>/` and the GitHub Actions templates under `workflows/` to your project's actual naming, domain, and repository — not hand you generic placeholders to fill in yourself.
4. Walk you through the one-time manual steps neither Terraform nor Claude can do for you (creating the cloud organization/tenant itself, registering a domain's NS delegation at your registrar, creating a Tailscale account) — these are called out explicitly in the reference docs, not glossed over.

You stay in control throughout: this is a Claude Code session doing real, reviewable work in your own repository, not an opaque script running against your cloud account. Read the plan, review the diffs, and treat any step that touches real infrastructure (a `terraform apply`, a cloud console action) the same way you'd treat it if you were doing it yourself.

## Repository layout

```
skills/secure-platform-factory/
  SKILL.md                    # entry point — routes to the reference docs below
  reference/
    accounts-aws.md           # battle-tested
    accounts-gcp.md           # work in progress
    accounts-azure.md         # work in progress
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
    aws/       # battle-tested in a real production deployment
    gcp/       # complete, validated (terraform fmt + validate) -- work in progress toward the same production mileage as AWS
    azure/     # complete, validated (terraform fmt + validate) -- work in progress toward the same production mileage as AWS
  workflows/
    ci.yml                      # cloud-agnostic: application QA + security stages that need no cloud credentials
    deploy-aws.yml.example      # rename to deploy.yml for the AWS path
    deploy-gcp.yml.example      # rename to deploy.yml for the GCP path
    deploy-azure.yml.example    # rename to deploy.yml for the Azure path
    promote.yml.example         # the dev -> staging -> prod chain; cloud-agnostic, calls deploy.yml
.github/workflows/validate.yml  # this repo's OWN CI (terraform validate + yaml lint) -- not a template, actually gates PRs here
CONTRIBUTING.md
```

## Contributing

See `CONTRIBUTING.md`. The short version: this project holds itself to the same review discipline it recommends (`skills/secure-platform-factory/reference/review-culture.md`) — a PR that changes a security-relevant default gets an independent adversarial review, not a single-approver rubber stamp, before merge. `main` is protected accordingly: 1 required review, required status checks, no force-push or deletion.

## Changelog

See `CHANGELOG.md`. This project is pre-1.0 on purpose — see that file's own "Versioning" section for what has to be true before it moves past `0.y.z`.

## License

Apache 2.0 — see `LICENSE`. Chosen deliberately over MIT for its explicit patent grant; see `CONTRIBUTING.md` and the project history for the reasoning if you're deciding this for your own project too.
