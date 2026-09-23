# AWS Account Structure — Proven

This is the one fully tested cloud path — built and run in a real multi-account AWS Organization, not just designed.

## The account layout

One AWS account per environment, under a single AWS Organization:

- **Management account** (`terraform/aws/example-management`) — the org's payer/root account. Holds no application workloads. Manages Organizations settings, creates the other 5 member accounts, delegates GuardDuty/Security Hub/Config/CloudTrail administration to log-archive, an SCP making Identity Center the only door for human access, and IAM Identity Center (SSO) account assignments.
- **Log-archive account** (`terraform/aws/example-log-archive`) — dedicated to security-log aggregation: the org-wide GuardDuty detector, Security Hub, the AWS Config organizational aggregator, the org CloudTrail trail, and the centralized buckets both CloudTrail and every environment's `config_recorder` module deliver to. No application workload ever runs here.
- **Build-registry account** (`terraform/aws/example-build-registry`) — holds the container image registry (ECR) that images are built into exactly once and promoted forward from. Structurally independent of any single environment's own stack, so tearing down or rebuilding an environment never touches the actual built artifacts.
- **One account per deployment environment** (`terraform/aws/example-env`, copied once per environment) — dev, test, staging, prod. Each with its own VPC, its own database, its own KMS key, its own Secrets Manager secrets, its own Terraform state bucket. A mistake or compromise in one environment's account has no default path to another's.

**Why separate accounts, not separate VPCs in one account**: an AWS account is the actual security and billing boundary — IAM policies, service quotas, and blast radius all stop at the account edge by default. A VPC-level separation inside one shared account still leaves a single set of IAM credentials, a single CloudTrail log stream, and a single set of service quotas shared across every environment. Full account separation is the difference between "isolated by policy, which can have a bug" and "isolated by AWS's own account boundary, which doesn't."

**This is the full blueprint, not just prose.** All 4 compositions above are real, `terraform validate`-clean Terraform in this repo — copy each into your own `infra/envs/<name>/`, in the order below, and fill in the real values each one's variables ask for.

## Setting it up

1. Create the AWS Organization (requires the AWS web console for the initial organization — no API for standing up a brand-new org from nothing) and enable AWS IAM Identity Center (SSO) in the management account, with individually-scoped users per real person — never a shared login, not even for administrators. The one narrow exception, if you need it at all, is a single billing/contact mailbox address used only for account-level notifications, never as an actual login identity for any service.
2. Provision this (management) account's own Terraform state backend, then apply `example-management`: creates the 5 remaining accounts (log-archive, build-registry, dev, test, staging, prod), delegates GuardDuty/Security Hub/Config/CloudTrail administration to log-archive, applies the human-access SCP, and assigns Identity Center admin access to every account.
3. Provision log-archive's state backend, then apply `example-log-archive` — this is what makes every member account's GuardDuty/Security Hub findings flow there automatically, without needing per-account setup as new accounts are added later.
4. Provision build-registry's state backend, then apply `example-build-registry`.
5. For each of dev/test/staging/prod: provision that account's state backend, then apply `example-env`, pointing its `central_config_bucket_name` variable at log-archive's centralized bucket (its own `config-storage.tf` creates it) and its image-URI variables at build-registry's ECR output.

A single account with no Organization at all can still use `example-env` on its own — `config_recorder` and `security_alerting` both default to a self-contained, same-account mode (leave `central_config_bucket_name` empty) for exactly that case. The full blueprint above is what you grow into, not a prerequisite to getting started.

## Cross-account image promotion

Images are built and scanned exactly once, in the build-registry account's own ECR. Every other environment's ECS/Fargate task definitions reference that same registry cross-account (via a resource policy on the registry granting pull access to every account in the same AWS Organization, matched by `aws:PrincipalOrgID` — not a per-account allowlist that needs updating as accounts are added or changed) — never rebuilding the same source into a new image per environment. See `cicd-pipeline.md`'s "build once, promote forward" section for why this matters for what a passed security gate actually proves.

## Non-production vs. production defaults

Deliberately different Terraform-level defaults by environment, driven by a single `environment name` variable threaded through every module:

- **Deletion protection and final-snapshot-on-destroy: production only.** Non-production databases can be destroyed and recreated freely as part of normal iteration; production cannot be destroyed without an explicit override, and always takes a final snapshot first.
- **Internet-facing load balancer: production only.** Every non-production environment's load balancer is internal-only, reachable only through the VPN layer — reduces the attack surface of every environment except the one that actually needs public reachability.
