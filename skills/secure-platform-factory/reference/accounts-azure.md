# Azure Subscription Structure — Work in Progress

The Azure mapping of the pattern proven in `accounts-aws.md`. Same reasoning, same sequencing — Azure's native names and one structural difference (resource groups) below.

## The subscription layout

One Azure subscription per environment, under a single Azure AD tenant and Management Group hierarchy:

- **Root management group** — created with the tenant. Holds Azure Policy assignments that cascade to every subscription beneath it (Azure's rough equivalent of an AWS Organizations SCP or a GCP Organization Policy).
- **A dedicated "platform" management group**, containing:
  - A **management subscription** — Azure AD (Entra ID) tenant-wide identity configuration, root-level Azure Policy definitions. No workloads.
  - A **log-archive/security subscription** — Microsoft Defender for Cloud's tenant-wide findings, a centralized Log Analytics workspace every other subscription's diagnostic settings forward to.
  - A **build-registry subscription (or a dedicated Azure Container Registry within one)** — holds container images, built once and pulled cross-subscription by every environment.
- **A dedicated "workloads" management group**, containing one subscription per deployment environment (dev/test/staging/prod).

**One structural difference worth naming explicitly**: Azure adds a layer AWS and GCP don't have between "environment" and "individual resource" — the **resource group**. Every resource in Azure belongs to exactly one resource group, and a resource group belongs to exactly one subscription. Put each environment's entire stack (network, database, container apps, Key Vault) in one resource group per environment, named consistently (e.g. `rg-<env_name>`) — this makes "destroy everything for this environment" and "see everything this environment owns" both a single resource-group-scoped operation, rather than something you have to reconstruct from tags.

**Why separate subscriptions, not just separate resource groups in one subscription**: a subscription, like an AWS account or GCP project, is a real billing and access-control boundary — Azure RBAC role assignments, network resources, and many quota limits are scoped at the subscription level. A resource-group-only separation inside one shared subscription still leaves a single set of subscription-level role assignments and a single quota pool shared across every environment.

## Setting it up

1. The Azure AD tenant is typically already created (often bundled with an existing Microsoft 365 subscription) — build the management group hierarchy and create the environment subscriptions under it.
2. Configure centralized identity: Azure AD is already your identity provider by definition (there's no separate "SSO setup" step the way AWS/GCP need one bolted on) — grant access via Azure AD group-based role assignments per subscription, never a standalone credential per person per subscription.
3. Enable **Microsoft Defender for Cloud** at the management-group level so it covers every subscription automatically as new ones are added.
4. Create each environment subscription's own Terraform state backend (an Azure Storage Account with a blob container, versioning/soft-delete enabled) before applying anything else into that subscription.

## Cross-subscription image promotion

Images are built and scanned exactly once into the build-registry subscription's Azure Container Registry. Every other environment's Container Apps reference that same registry cross-subscription (via a role assignment granting the environment's own managed identity `AcrPull` on that specific registry) — never rebuilding per environment, the same "build once, promote forward" principle as AWS/GCP.

## Non-production vs. production defaults

- **Purge protection on Key Vault: production only** (or, more conservatively, everywhere — Azure Key Vault's purge protection prevents a deleted vault or secret from being permanently destroyed before its retention period elapses; the AWS/GCP equivalent split by production is deletion protection on the database, so mirror this at minimum on the database: `Azure Database for PostgreSQL`'s own backup retention set higher for production).
- **Public network access on Container Apps: production only** — every non-production environment's Container Apps environment stays on internal-only ingress, reachable solely through the VPN layer.
