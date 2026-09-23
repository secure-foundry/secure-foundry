# AWS Account Structure — Proven

This is the one fully tested cloud path — built and run in a real multi-account AWS Organization, not just designed.

## The account layout

One AWS account per environment, under a single AWS Organization:

- **Management account** — the org's payer/root account. Holds no application workloads. Used for AWS Identity Center (SSO), Organizations policies, and consolidated billing/Cost Explorer only.
- **Log-archive account** — dedicated to security-log aggregation: the org-wide GuardDuty delegated-admin, Security Hub aggregation, and (once wired up — see `monitoring-compliance-aws.md`) the AWS Config organizational aggregator. No application workload ever runs here. Each environment's own AWS Config recorder (`terraform/aws/modules/config_recorder`) and security-alerting pipeline (`terraform/aws/modules/security_alerting`) are demonstrated as self-contained, same-account modules — centralizing either into this account instead is a documented next step, not something this repo's Terraform does for you yet.
- **Build-registry account** (or a dedicated section of one shared account) — holds the container image registry (ECR) that images are built into exactly once and promoted forward from. Structurally independent of any single environment's own stack, so tearing down or rebuilding an environment never touches the actual built artifacts.
- **One account per deployment environment** — dev, test, staging, prod. Each with its own VPC, its own database, its own KMS key, its own Secrets Manager secrets, its own Terraform state bucket. A mistake or compromise in one environment's account has no default path to another's.

**Why separate accounts, not separate VPCs in one account**: an AWS account is the actual security and billing boundary — IAM policies, service quotas, and blast radius all stop at the account edge by default. A VPC-level separation inside one shared account still leaves a single set of IAM credentials, a single CloudTrail log stream, and a single set of service quotas shared across every environment. Full account separation is the difference between "isolated by policy, which can have a bug" and "isolated by AWS's own account boundary, which doesn't."

## Setting it up

1. Create the AWS Organization from the management account (requires the AWS web console for the initial organization — no API for standing up a brand-new org from nothing).
2. Enable AWS IAM Identity Center (SSO) in the management account, with individually-scoped users per real person — never a shared login, not even for administrators. The one narrow exception, if you need it at all, is a single billing/contact mailbox address used only for account-level notifications, never as an actual login identity for any service.
3. Create the remaining accounts (log-archive, build-registry, dev, test, staging, prod) under the Organization.
4. Delegate GuardDuty and Security Hub administration to the log-archive account, and enable both org-wide — every member account's findings flow there automatically, without needing per-account setup as new accounts are added later.
5. Provision each environment account's own Terraform state backend (an S3 bucket + a locking mechanism) before applying any other infrastructure into that account — state has to live somewhere before Terraform can track anything else.

## Cross-account image promotion

Images are built and scanned exactly once, in the build-registry account's own ECR. Every other environment's ECS/Fargate task definitions reference that same registry cross-account (via a resource policy on the registry granting pull access to each environment account's specific role) — never rebuilding the same source into a new image per environment. See `cicd-pipeline.md`'s "build once, promote forward" section for why this matters for what a passed security gate actually proves.

## Non-production vs. production defaults

Deliberately different Terraform-level defaults by environment, driven by a single `environment name` variable threaded through every module:

- **Deletion protection and final-snapshot-on-destroy: production only.** Non-production databases can be destroyed and recreated freely as part of normal iteration; production cannot be destroyed without an explicit override, and always takes a final snapshot first.
- **Internet-facing load balancer: production only.** Every non-production environment's load balancer is internal-only, reachable only through the VPN layer — reduces the attack surface of every environment except the one that actually needs public reachability.
