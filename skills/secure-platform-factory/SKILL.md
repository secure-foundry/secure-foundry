---
name: secure-platform-factory
description: Use when starting a new project (or hardening an existing one) that needs a compliant-from-day-one cloud platform - multi-account isolation, a gated CI/CD pipeline, VPN-only network access, encryption/secrets discipline, and audit-mapped monitoring. Walks through cloud choice, VPN pattern, and CI/CD tool selection, then routes to the specific setup steps.
---

# Secure Platform Factory

Bootstraps the security/compliance foundation a project stands everything else on: cloud account structure, CI/CD gates, network isolation, encryption, and monitoring — mapped to real audit-framework language, not just "best practices."

**Status**: the AWS path is proven (built and run in a real production platform, independently reviewed, real vulnerabilities caught and fixed — see `reference/security-history.md`). The GCP and Azure paths are designed but not yet battle-tested. Say so plainly to whoever you're helping before they commit to either.

## Before you start

This is architectural work — it changes how a team authenticates, how code ships, and where data lives. Do not silently make these decisions on someone's behalf. Ask them, one at a time, using whatever question mechanism your harness provides:

1. **Which cloud** — AWS, GCP, or Azure? If they don't know or don't care, recommend AWS specifically because it's the proven path, and say why.
2. **Tooling budget** — start from the open-source defaults (recommended for anyone not already paying for security tooling), or do they already hold licenses for a commercial SAST/DAST/container-scanning suite that should replace a specific stage?
3. **VPN pattern** — the default is a WireGuard-based mesh (Tailscale is the recommended managed option; self-hosted Headscale is the zero-cost, fully open-source path). If they have a strong preference for a cloud-native VPN or already run one, honor it — see `reference/network-vpn.md` for the tradeoffs to present.
4. **Starting fresh or hardening an existing project?** A brand-new project can adopt every recommendation immediately. An existing one needs a gap assessment first — read what's already there before proposing changes, the same way you would honor an existing design system rather than overriding it.

Record their answers before reading further — every reference doc below assumes you already know the cloud, the tooling tier, and the VPN choice.

## Routing

| Task | Reference |
|---|---|
| Setting up the cloud account/project structure | `reference/accounts-<cloud>.md` |
| Building the CI/CD pipeline (which scanner for which stage) | `reference/cicd-pipeline.md` |
| Network isolation and VPN access | `reference/network-vpn.md` |
| Encryption and secrets management | `reference/encryption-secrets-<cloud>.md` |
| Identity provider integration and authorization model | `reference/authn-authz.md` |
| Monitoring, detection, and compliance-framework mapping | `reference/monitoring-compliance-<cloud>.md` |
| Configuring the GitHub repository itself (rulesets, environments) | `reference/github-setup.md` |
| Establishing review norms, not just review tooling | `reference/review-culture.md` |
| What order to actually do all of this in | `reference/build-order.md` |
| Real vulnerabilities this project has caught, and the fix | `reference/security-history.md` |

Read `reference/build-order.md` first, always — the other docs are organized by topic, not by sequence, and several steps have real dependencies on earlier ones (the CI/CD pipeline's OIDC federation step needs the account structure to exist first; the VPN step needs the network layout from the account-setup doc).

## Working principles

- **Every recommendation names its tradeoff.** Where a doc gives an open-source default and a paid alternative, it says why you might outgrow the free option, not just that one exists.
- **Cite the real mechanism, not the marketing name.** "OIDC federation" means a specific trust-policy shape with a specific vulnerability class it closes (see `security-history.md`) — explain the mechanism, not just the acronym.
- **The gap disclosure is part of the deliverable.** If a control is deferred (not every project needs VPC Flow Logs on day one), say so explicitly and say why, the same way `reference/monitoring-compliance-aws.md` does — a false "everything is done" is worse than an honest, prioritized gap.
- **This skill scaffolds real files, not descriptions.** When a reference doc includes Terraform or workflow YAML, write it into the target project adapted to their actual naming/domain — don't just tell them what a file like this would contain.
