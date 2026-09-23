# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/) —
with one deliberate deviation explained below.

## Versioning

Standard semver: **MAJOR** for a breaking change to a Terraform module's
inputs/outputs or a restructuring of the skill's routing, **MINOR** for
a new module/stage/cloud-path addition that's backward compatible,
**PATCH** for fixes and doc corrections.

**Staying below 1.0.0 is itself a real signal here, not a formality.**
This project's own README distinguishes AWS (battle-tested, run in a
real production platform) from GCP/Azure (designed and validated, not
yet run against a real account) — and, as of this writing, several new
AWS additions (the multi-account blueprint, the centralized Config
recorder, Security Hub/GuardDuty alerting) sit in the same "validated,
not yet proven" category, having been through `terraform validate` and
independent review but never a real `terraform apply`. Semver's own
convention for `0.y.z` — "anything may still change, don't treat this
as a stable, fully proven interface" — matches that honestly. This
project moves to `1.0.0` once the multi-account blueprint has been
through at least one real `terraform apply` against a live AWS
account, not on a fixed calendar date.

## [Unreleased]

Nothing yet.

## [0.1.0] - 2026-09-23

Initial public release.

### Added

- The `secure-platform-factory` Claude Code skill: routes a new or
  existing project through cloud choice, VPN pattern, and CI/CD
  tooling tier, then into cloud-specific setup.
- Full parallel Terraform for AWS, GCP, and Azure — 7 modules each
  (`account_baseline`, `kms`, `cicd_oidc`/equivalent, `network`,
  managed Postgres, the app-service module, `vpn_router`) plus a
  single-account `example-env` composition per cloud.
- AWS: the full multi-account blueprint alongside the single-account
  path — `example-management` (Organizations settings, member-account
  creation, GuardDuty/Security Hub/Config/CloudTrail delegation, an
  SCP making Identity Center the only door for human access, Identity
  Center account assignments), `example-log-archive` (org-wide
  GuardDuty + Security Hub + Config aggregator + CloudTrail trail, a
  centralized Config-delivery bucket, Security Hub/GuardDuty findings
  routed to SNS/email/Slack/Teams), and `example-build-registry` (a
  shared, cross-account, KMS-encrypted ECR registry).
- AWS: VPC Flow Logs and a per-account AWS Config recorder
  (`modules/config_recorder`, `modules/network`'s `flow_logs.tf`),
  usable standalone (self-contained, same-account) or pointed at the
  centralized log-archive bucket.
- Reference docs covering account structure, CI/CD pipeline stages (SAST,
  secrets, container/dependency/IaC scanning, DAST, SBOM generation,
  malicious-package detection, agent/skill security scanning), VPN
  patterns, encryption/secrets, auth, GitHub setup, review culture, and
  monitoring/compliance mapped to real SOC 2 / NIST CSF language.
- `security-history.md` — 5 real issues found via independent
  adversarial review (a wildcard OIDC trust-policy match, an
  under-encrypted RDS master secret, a cross-subdomain cookie
  vulnerability, real SkillSpector findings in this repo's own
  Terraform, and a monitoring/alerting gap in the AWS reference
  environment), each with what was wrong, the fix, and why it matters
  generally.
- GitHub Actions workflow templates for adopters (`ci.yml`,
  `deploy-<cloud>.yml.example`, `promote.yml.example`) and this repo's
  own CI (terraform fmt/validate across all three clouds, YAML lint,
  gitleaks, Checkov, SkillSpector, SBOM generation via Trivy, and
  malicious-package scanning via Guarddog).
- Dependabot for GitHub Actions and Terraform provider versions.
- Apache 2.0 license (explicit patent grant), `CONTRIBUTING.md` (review
  requirements, scope boundaries), and a README covering purpose,
  intended audience, and install/usage instructions.

### Fixed

Found during this release's own build, not carried over from anywhere
else:

- `gitleaks/gitleaks-action` requires a paid license for
  organization-owned repos; switched to running the underlying
  (free, MIT-licensed) `gitleaks` CLI directly via its official image.
- SkillSpector's first real scan against this repo's own Terraform
  found an unpinned floating container tag and a `curl | bash` install
  in the Azure/GCP `vpn_router` modules, and an unpinned `npx`
  migration-tool invocation in all three `deploy-<cloud>.yml.example`
  templates — all real, all fixed (see `security-history.md` entry 4).
- Two service-principal trust policies (VPC Flow Logs, AWS Config) and
  one resource policy (the SNS topic for EventBridge) were missing the
  `aws:SourceAccount`/`aws:SourceArn` conditions AWS itself documents
  as required to prevent the confused-deputy problem — caught by an
  independent Codex review before merge, verified against AWS's own
  documentation before fixing (one of Codex's other findings, a
  suggested Config delegated-admin principal swap, was checked and
  rejected as incorrect for what this project actually builds).
- S3 bucket names for the centralized Config and CloudTrail buckets
  now suffix the account ID — bucket names are globally unique across
  all of AWS, and the un-suffixed names would collide with a second
  adopter's own bucket.
