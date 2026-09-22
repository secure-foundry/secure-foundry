# Monitoring, Detection, and Compliance Mapping — AWS — Proven

Every control below is tagged against the SOC 2 Trust Services Criteria (TSC) and/or NIST CSF 2.0 function it satisfies — not because the label matters for its own sake, but because "we have monitoring" means something specific and auditable when you can point to which control family it evidences, versus a vague claim an auditor has to take on faith.

## Built and enforced

| Control | What it does | Maps to |
|---|---|---|
| GuardDuty, organization-wide, with Runtime Monitoring | Threat detection at both the account/API level and — critically — actual running-workload behavior (unexpected process execution, malware-like file/network activity inside a running container). Enabled once at the org level via the log-archive account's delegated admin, so every new account is covered automatically, no per-account setup. | NIST CSF **Detect (DE)**; SOC 2 **CC7.1/CC7.2** (system monitoring, anomaly detection) |
| Security Hub, organization-wide | Aggregates security findings from GuardDuty and other AWS security services into one place, against standard security-control baselines. | NIST CSF **Detect (DE)**, **Identify (ID.RA)**; SOC 2 **CC7.1** |
| Every third-party GitHub Action pinned to a commit SHA | Prevents a compromised upstream dependency in your own CI tooling from silently changing behavior under an existing version reference. | NIST CSF **Protect (PR.PS)**; SOC 2 **CC8.1** (change management) |
| WAF with a managed core rule set + rate-based blocking, in front of every load balancer | Blocks common web attack patterns and volumetric abuse before they reach the application. | NIST CSF **Protect (PR.AA)**; SOC 2 **CC6.6** |

*(This table is illustrative of the pattern, not exhaustive — cross-reference every control in `cicd-pipeline.md`, `network-vpn.md`, `encryption-secrets-aws.md`, and `authn-authz.md` against the TSC/CSF families above as you adopt them; most of what's in those docs maps to CC6.x (logical access) or CC6.6/CC6.7 (network/transmission security).)*

## Honestly deferred — a documented gap is not a failed control

Being explicit about what isn't built yet, and why it's an acceptable short-term gap rather than an oversight, is itself part of a real audit posture. An auditor (or a careful adopter of this skill) trusts a system more, not less, for naming its own gaps with a reason attached.

| Gap | Why it's commonly deferred short-term | Cost/effort to close |
|---|---|---|
| A centralized configuration-drift recorder (e.g. AWS Config) actually wired up per account | The organizational aggregator can exist before any account has an active recorder feeding it — meaning it aggregates nothing until this is done. Reasonable to defer until you have enough accounts/resources that manual drift-checking is actually a bottleneck. | Low — near-zero incremental cost per account once configured. |
| VPC Flow Logs | Valuable for network-forensics after an incident, but not load-bearing for day-to-day detection if GuardDuty's own network-based findings are already active. | Low cost, mostly a "haven't gotten to it yet" gap, not a hard one. |
| Automated routing of findings to a human (alarm + notification, not just collection) | Findings existing in a dashboard nobody watches is a real, common gap — GuardDuty/Security Hub findings are genuinely being generated, but "collected" isn't the same as "someone gets paged." | Low cost (a notification topic + a subscription), but treat this as higher-priority than it looks — a detection control nobody sees fire is barely better than no detection control. |
| A verified backup-restore drill | Backup *configuration* being correct (retention period, multi-AZ) is necessary but not sufficient — it needs to actually be exercised at least once to know the restore process itself works under real conditions. | Effort, not cost — needs a deliberately scheduled drill, not a Terraform change. |

## The general principle

Don't claim a control exists because the underlying service is "enabled" in some generic sense — trace whether the specific mechanism that makes it useful (a recorder actually running, a finding actually reaching a person) is really wired up, the way `security-history.md` traces specific real misconfigurations rather than accepting a plausible-sounding default. The gap between "the feature exists in this account" and "the feature is actually doing its job" is exactly where the AWS Config aggregator example above lives — worth checking for the same gap in every control you adopt from this doc.
