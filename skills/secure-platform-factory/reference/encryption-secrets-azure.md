# Encryption and Secrets — Azure — Work in Progress

Same pattern as the AWS and GCP docs. **One consolidation worth naming up front**: Azure Key Vault holds encryption keys AND secrets in the same resource (as distinct object types — "keys" and "secrets" — inside one vault), where AWS and GCP split this into two separate services (KMS + Secrets Manager, Cloud KMS + Secret Manager). This isn't a gap in the Azure design, just a real structural difference: one `key_vault` module in this skill's Azure path does the job of both the AWS `kms` module and the credential-injection half of `encryption-secrets-aws.md`.

## One Key Vault per environment

- **Purge protection enabled** — without this, a deleted vault (or a deleted key/secret inside it) can be permanently purged before its soft-delete retention period elapses, which defeats the entire safety purpose of soft-delete in the first place. Treat this as non-negotiable, not just a production-only setting.
- **Azure RBAC authorization mode**, not the older vault access-policy model — role assignments (`Key Vault Secrets User`, `Key Vault Crypto User`, etc.) scoped per-identity via standard Azure RBAC, auditable the same way every other Azure resource's access is, rather than a vault-specific access-policy list that lives outside the normal RBAC audit trail.

## Encrypt everything with that vault's key — including what a managed feature creates for you

Azure Database for PostgreSQL Flexible Server's data-at-rest encryption should reference this environment's own Key Vault key (customer-managed key, not the Microsoft-managed default) explicitly. **Check this specifically, the same way the AWS and GCP docs do**: a managed database defaulting to Microsoft-managed encryption instead of your own customer-managed key is the same class of gap as `security-history.md` #2, just on a different cloud.

## Secrets never in code, never in a plain environment file

Azure Container Apps' native Key Vault reference syntax (`secretRef` pointing at a Key Vault secret URI, resolved via the Container App's own managed identity) injects every credential at container start — never committed to the repository, never placed in a plain `.env` file baked into the image.

## TLS enforced end to end

- Azure Front Door's WAF policy pinned to a modern minimum TLS version.
- Azure Database for PostgreSQL Flexible Server's `require_secure_transport` parameter set to `ON` — rejects a non-TLS connection at the database engine level, the same requirement as AWS's `rds.force_ssl` and GCP's `ssl_mode`.
- The application connects with full certificate verification against Azure's own published certificate chain — not a skip-verification mode.

## The dedicated-credential-plus-spending-cap pattern still applies

Same reasoning as the AWS and GCP docs: provision a dedicated credential for any automated/non-interactive call to a pay-per-use external API (including Azure OpenAI or any other AI/agentic service), with an Azure Cost Management budget alert attached (see the `account_baseline` module's Azure equivalent), before the first automated call — not after.
