# Build Order

The reference docs are organized by topic; this doc is organized by sequence, because several steps have real dependencies on earlier ones. Skipping ahead usually means redoing the skipped step's output once you circle back.

## Phase 0 — Decisions (see SKILL.md's setup questions)

Cloud, tooling tier (open-source default vs. paid), VPN pattern. Don't proceed past this phase with an unanswered question — every later doc assumes these are already settled.

## Phase 1 — Account/project structure

`reference/accounts-<cloud>.md`. This has to exist first: every later phase (CI/CD's OIDC trust policy, the network layout, environment-scoped secrets) is *per environment*, and an environment here means a separate account/project, not a namespace inside one. Get this wrong and every later phase has to be redone per-account instead of once.

Includes: the management/root account or organization, a dedicated security-log-aggregation account (GuardDuty/Security Hub findings and audit logs land here, isolated from every account that runs actual workloads), and one account per deployment environment (dev/test/staging/prod at minimum).

## Phase 2 — Identity and SSO

Set up centralized identity (your cloud's SSO/Identity Center equivalent) before creating any individual IAM users in a workload account. Every person's access should route through one federated identity, scoped per-account by role assignment — never a separate local IAM user per account per person.

## Phase 3 — Network layout

`reference/network-vpn.md`. Private subnets, security-group trust chain, and the VPN subnet-router pattern, per environment. This needs Phase 1's account structure to exist (each environment gets its own network, inside its own account).

## Phase 4 — Encryption and secrets

`reference/encryption-secrets-<cloud>.md`. A customer-managed encryption key per environment, before anything that needs to reference it (a database, a secrets store) is created — retrofitting encryption onto an already-existing unencrypted resource is possible on most clouds but meaningfully more disruptive than provisioning it encrypted from the start.

## Phase 5 — CI/CD pipeline

`reference/cicd-pipeline.md` and `reference/github-setup.md`. This needs Phases 1–4 done first: the OIDC trust policy needs a real account and IAM role to trust into; the pipeline's deploy step needs a real network and database to deploy against.

## Phase 6 — Identity provider integration and authorization

`reference/authn-authz.md`. Can happen in parallel with Phase 5 rather than strictly after it, since it's mostly application-layer work, but needs Phase 2's identity foundation already in place conceptually (you're integrating your *application's* login with the same kind of identity-provider thinking you just used for infrastructure access).

## Phase 7 — Monitoring and compliance mapping

`reference/monitoring-compliance-<cloud>.md`. Deliberately last, not because it matters least, but because it's the phase that *verifies* everything before it — you can't meaningfully monitor for drift in a security group that doesn't exist yet. Turn on the cloud's native threat-detection service org-wide, and go through the compliance-framework mapping table to decide, explicitly, what's built now versus deliberately deferred — and document the deferred items with a reason, the same way `reference/monitoring-compliance-aws.md` does.

## Phase 8 — Review culture

`reference/review-culture.md` isn't a "phase" you finish — it's the practice that should already be running underneath every phase above, starting with the very first PR. Called out last here only because it's easy to treat process as an afterthought; don't.
