# Encryption and Secrets — GCP — Work in Progress

Same pattern as `encryption-secrets-aws.md`; GCP-native mechanisms below.

## Customer-managed Cloud KMS key ring, one per environment

Never rely on Google-managed default encryption for anything sensitive. Provision one Cloud KMS key ring (with a key inside it) per environment, with:
- **Automatic key rotation enabled** on the CryptoKey resource — Google handles the underlying key material rotation.
- **IAM bindings scoped narrowly**: `roles/cloudkms.admin` for a small, explicit set of admin identities, `roles/cloudkms.cryptoKeyEncrypterDecrypter` granted only to the specific service accounts that need to use it — never a project-wide or organization-wide binding.

## Encrypt everything with that key — including what a managed feature creates for you

Cloud SQL storage, its automatically-managed backups, Secret Manager secrets, and Cloud Logging buckets should all reference the environment's own CMEK (customer-managed encryption key) explicitly. **The same class of gap caught in the AWS implementation (security-history.md #2) is worth checking for here just as carefully**: a managed database feature that generates credentials or backups on your behalf can default to Google-managed encryption unless you explicitly configure CMEK on that specific resource, not just on the instance's primary storage.

## Secrets never in code, never in a plain environment file

Every credential a running Cloud Run revision needs reaches it exclusively through Secret Manager's native Cloud Run integration (a secret mounted as an environment variable or a volume at container start, referencing a specific secret version) — never committed to the repository, never placed in a plain `.env` file baked into the image.

## TLS enforced end to end

- Google-managed SSL certificates on the load balancer, or your own certificates if you need a specific CA — either way, reject legacy TLS versions via the load balancer's SSL policy.
- Cloud SQL's `require_ssl` (or the newer `ssl_mode` requiring an encrypted connection) enabled — reject a plaintext connection attempt at the database engine level, the same requirement as AWS's `rds.force_ssl`.
- The application connects with full server certificate verification against Cloud SQL's own CA, not a skip-verification mode.

## The dedicated-credential-plus-spending-cap pattern still applies

If your product calls any pay-per-use external API (including GCP's own Vertex AI or any other AI/agentic service), provision a dedicated credential for automated/non-interactive use — separate from any shared human-interactive access — with a budget alert attached (see `account_baseline` module's GCP equivalent, a Cloud Billing budget), before the first automated call, not after. Same reasoning as the AWS doc: an automated workflow can exhaust a shared budget far faster than a human would notice.
