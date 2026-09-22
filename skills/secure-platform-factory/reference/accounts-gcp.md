# GCP Project Structure — Designed, Not Yet Battle-Tested

This is the GCP mapping of the same pattern proven in `accounts-aws.md`. The account/project isolation model, the reasoning, and the sequencing are the same — only the native service names differ. Read `accounts-aws.md` first if you haven't; this doc assumes that reasoning and just re-maps it.

## The project layout

One GCP project per environment, under a single GCP Organization, mirroring AWS's one-account-per-environment structure:

- **Root organization** — created once, tied to your domain (Google Workspace or Cloud Identity). Holds no workloads.
- **A dedicated "management" folder/project** — Identity and Access Management (IAM) at the org level, org policies, billing account ownership.
- **A dedicated "log-archive" project** — the Security Command Center's org-level findings, aggregated Cloud Audit Logs (via a log sink), and org-wide policy monitoring. No application workload runs here, same reasoning as the AWS log-archive account.
- **A dedicated "build-registry" project (or Artifact Registry repository)** — holds the container images, built once and referenced cross-project by every environment.
- **One project per deployment environment** — dev, test, staging, prod. Each with its own VPC, its own Cloud SQL instance, its own Cloud KMS key ring, its own Secret Manager secrets, its own Terraform state bucket.

**Why separate projects, not separate VPCs in one project**: a GCP project is the actual IAM and billing boundary, the same way an AWS account is — service accounts, IAM policies, and quotas are scoped per-project by default. Folder-level organization policies (GCP's org-policy constraints) let you enforce baseline security posture (e.g. "no public IPs allowed") across every project in a folder at once, the rough equivalent of an AWS Organizations Service Control Policy.

## Setting it up

1. Create the GCP Organization (tied to your Workspace/Cloud Identity domain) and the folder structure (management, log-archive, build-registry, and one per environment) — this needs the Cloud Console for the very first organization-level setup, the same one-time manual step AWS's Organization creation needs.
2. Set up centralized identity via **Workload Identity Federation** for any CI/automation access (see `cicd-pipeline.md`'s OIDC section — GCP's equivalent avoids service account keys entirely, the same way AWS's OIDC role assumption avoids long-lived access keys) and Google Workspace/Cloud Identity SSO for human access, with IAM roles granted per-project via group membership — never a standalone credential per person per project.
3. Enable the **Security Command Center** at the organization level, with findings routed to the log-archive project.
4. Create each environment project's own Terraform state backend (a GCS bucket with object versioning enabled) before applying anything else into that project.

## Cross-project image promotion

Images are built and scanned exactly once, into the build-registry project's own Artifact Registry repository. Every other environment's Cloud Run services reference that same registry cross-project (via an IAM binding granting the environment's own runtime service account `roles/artifactregistry.reader` on that specific repository) — never rebuilding the same source into a new image per environment, mirroring AWS's ECR cross-account pull pattern exactly.

## Non-production vs. production defaults

Same principle as AWS, GCP-native mechanism:
- **Deletion protection: production only** — Cloud SQL's own `deletion_protection` flag, set `true` only for the production project's instance.
- **Internal-only load balancing: non-production only** — use an internal HTTP(S) load balancer (or keep Cloud Run services set to "internal only" ingress) for every environment except the one that needs public reachability.

## What's genuinely untested here

The account/project isolation model itself is a very direct, low-risk mapping of a real, proven AWS pattern — organizations, folders, and projects are conceptually close enough to AWS's Organizations/OUs/accounts that this mapping carries low real risk. What hasn't been run in a real production GCP environment is the full combination with the CI/CD, network, and compute pieces below — treat the account structure as solid and everything downstream of it as needing your own review.
