# Encryption and Secrets — AWS — Proven

## Customer-managed KMS key, one per environment

Never rely on AWS's shared default encryption key for anything beyond the most disposable, non-sensitive data. Provision one customer-managed KMS key per environment, with:

- **Key rotation enabled** — AWS handles the underlying cryptographic material rotation automatically; you never manage key material by hand.
- **A scoped IAM policy naming explicit key-administrator and key-user roles**, plus narrow, explicitly-conditioned grants for the specific AWS services that need to use it (CloudTrail, CloudWatch Logs) — never a blanket `"*"` principal grant. A KMS key's own resource policy is the actual access-control boundary for everything it encrypts; treat it with the same care as an IAM policy, not as a formality.

## Encrypt everything with that key — including what a managed feature creates for you

Every environment's database storage, its automatically-generated master-password secret, its CloudWatch log groups, and its Secrets Manager secrets should all reference that environment's own customer-managed key explicitly. **Check the auto-generated resources specifically** — a managed database feature that generates its own master-password secret for you can default that secret to AWS's own shared key even when the storage volume next to it is correctly using your customer-managed key (see `security-history.md` #2 — this is a real issue that was caught, not a hypothetical).

## Secrets never in code, never in a plain environment file

Every credential a running container needs reaches it exclusively through the compute platform's own secrets-injection mechanism (an ECS task definition's `secrets` block, mapping a Secrets Manager ARN directly to an environment variable at container start) — never committed to the repository, never placed in a plain `.env` file that ships with the container image.

## TLS enforced end to end, not just "encrypted in transit" as a checkbox

- The load balancer's TLS listener pinned to a current, strong TLS policy (reject legacy protocol versions).
- The database's own parameter group set to require SSL/TLS on every connection — reject any plaintext connection attempt outright, at the database engine level, not just as an application-layer convention.
- The application connects with full certificate verification against the cloud provider's own published certificate authority bundle — not a "skip verification" mode. A connection that's merely encrypted but doesn't verify the certificate is still vulnerable to an on-path attacker presenting their own certificate; verification is what actually closes that.

## When to introduce a paid credential and a spending cap — a general pattern worth naming explicitly

If your product involves any AI/agentic API usage, or any other pay-per-call external service, **provision that service's dedicated API credential — separate from any shared team/interactive subscription — with a hard spending cap attached, before the first automated (non-interactive) call to it, not after.** An automated workflow calling an external paid API can consume usage far faster than a human ever would, and if it shares a credential with your team's own interactive usage, a bug in the automation can exhaust or overspend a budget the whole team depends on. This is a real, previously-learned lesson in the project this skill's pattern is extracted from — provision the dedicated credential and cap deliberately, as its own explicit step, not as an afterthought once something is already live.
