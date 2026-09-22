# Monitoring, Detection, and Compliance Mapping — GCP — Designed, Not Yet Battle-Tested

Same structure as `monitoring-compliance-aws.md`: every control tagged against the SOC 2 TSC / NIST CSF 2.0 family it satisfies, and honest about what's a documented short-term gap rather than a built control.

## Built into this skill's GCP design

| Control | What it does | Maps to |
|---|---|---|
| Security Command Center (Premium tier), organization-wide | Threat detection, vulnerability findings, and security posture monitoring across every project in the org from one place — the direct GCP analog of GuardDuty + Security Hub combined. | NIST CSF **Detect (DE)**; SOC 2 **CC7.1/CC7.2** |
| Cloud Audit Logs, org-wide sink to the log-archive project | Every admin activity and data-access log across every project, aggregated centrally and immutably (write-once bucket) — the GCP analog of centralized CloudTrail. | NIST CSF **Detect (DE)**, **Identify (ID)**; SOC 2 **CC7.2** |
| Cloud Armor in front of every load balancer | The GCP analog of AWS WAF — managed rule sets plus rate-based rules blocking common web attack patterns and volumetric abuse. | NIST CSF **Protect (PR.AA)**; SOC 2 **CC6.6** |
| Every third-party GitHub Action pinned to a commit SHA | Same control as the AWS doc — cloud-independent. | NIST CSF **Protect (PR.PS)**; SOC 2 **CC8.1** |

## Honestly deferred, same reasoning as the AWS doc

| Gap | Why it's a reasonable short-term gap | Cost/effort to close |
|---|---|---|
| Organization Policy Service constraints actually enforced (not just available) | GCP ships a broad library of org-policy constraints (no public IPs, restrict service account key creation, etc.) — having the *service* available isn't the same as having deliberately chosen and applied the specific constraints your threat model needs. | Low cost, real effort to go through the constraint library deliberately. |
| VPC Flow Logs | Same reasoning as AWS — valuable for post-incident forensics, not load-bearing for day-to-day detection if Security Command Center's network-based findings are already active. | Low cost. |
| Findings routed to a human (a Cloud Monitoring alerting policy + notification channel, not just collected in SCC's dashboard) | The same gap as AWS's "collected but not routed" problem — treat this with the same urgency the AWS doc does; a detection control nobody sees fire is barely better than none. | Low cost, higher priority than it looks. |
| A verified backup-restore drill for Cloud SQL | Backup configuration being correct isn't the same as having exercised the actual restore process once under real conditions. | Effort, not cost. |

## What's genuinely unverified here, beyond the general "not battle-tested" caveat

Whether Security Command Center's Premium tier findings actually cover the same practical ground GuardDuty's Runtime Monitoring does for a running container's *behavior* (not just its configuration) hasn't been confirmed against a real running workload under this skill's own pattern. If you adopt this path and find a real gap here, that's exactly the kind of finding `security-history.md` exists to collect — file it.
