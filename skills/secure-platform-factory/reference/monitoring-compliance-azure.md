# Monitoring, Detection, and Compliance Mapping — Azure — Work in Progress

Same structure as the AWS and GCP docs: every control tagged against the SOC 2 TSC / NIST CSF 2.0 family it satisfies, honest about documented gaps.

## Built into this skill's Azure design

| Control | What it does | Maps to |
|---|---|---|
| Microsoft Defender for Cloud, tenant/management-group-wide | Threat detection, security posture recommendations, and (with the Defender for Containers plan specifically enabled) runtime threat detection for running containers — the Azure analog of GuardDuty Runtime Monitoring + Security Hub combined. | NIST CSF **Detect (DE)**; SOC 2 **CC7.1/CC7.2** |
| Centralized Log Analytics workspace, every subscription's diagnostic settings forwarding to it | Every resource's logs land in one place in the log-archive subscription, the Azure analog of centralized CloudTrail/Cloud Audit Logs. | NIST CSF **Detect (DE)**, **Identify (ID)**; SOC 2 **CC7.2** |
| Azure Front Door WAF policy (Microsoft-managed rule set + rate limiting) | The Azure analog of AWS WAF / GCP Cloud Armor. | NIST CSF **Protect (PR.AA)**; SOC 2 **CC6.6** |
| Every third-party GitHub Action pinned to a commit SHA | Same cloud-independent control as the AWS and GCP docs. | NIST CSF **Protect (PR.PS)**; SOC 2 **CC8.1** |

## Honestly deferred, same reasoning as the AWS and GCP docs

| Gap | Why it's a reasonable short-term gap | Cost/effort to close |
|---|---|---|
| Azure Policy definitions actually assigned (not just available) | Azure ships a large built-in policy library (deny public IPs, require encryption, etc.) at the initiative/definition level — assigning the specific ones your threat model needs to the management group is a deliberate step, not automatic. | Low cost, real effort to go through deliberately. |
| NSG Flow Logs / VNet Flow Logs | Same reasoning as AWS VPC Flow Logs and GCP's equivalent — valuable for forensics, not load-bearing if Defender for Cloud's own network-based detections are active. | Low cost. |
| Findings routed to a human (an Azure Monitor alert rule + action group, not just visible in the Defender for Cloud dashboard) | The same "collected but not routed" gap called out in both other cloud docs — treat with the same priority. | Low cost, higher priority than it looks. |
| A verified backup-restore drill for the PostgreSQL Flexible Server | Correct backup configuration isn't the same as a proven restore process. | Effort, not cost. |

## What's genuinely unverified here

Whether Defender for Cloud's container-runtime detection (the Defender for Containers plan) actually needs a sidecar/agent deployed per Container App the way GuardDuty Runtime Monitoring's agent does, and what that means for an already-running app (the AWS doc's own honestly-flagged limitation — a redeploy was needed to actually get coverage) hasn't been confirmed on this path. If you adopt this and find a real answer, that belongs in `security-history.md`.
