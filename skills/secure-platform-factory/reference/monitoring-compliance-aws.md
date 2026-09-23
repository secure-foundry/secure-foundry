# Monitoring, Detection, and Compliance Mapping — AWS — Proven

Every control below is tagged against the SOC 2 Trust Services Criteria (TSC) and/or NIST CSF 2.0 function it satisfies — not because the label matters for its own sake, but because "we have monitoring" means something specific and auditable when you can point to which control family it evidences, versus a vague claim an auditor has to take on faith.

## Built and enforced

| Control | What it does | Maps to |
|---|---|---|
| GuardDuty, organization-wide, with Runtime Monitoring | Threat detection at both the account/API level and — critically — actual running-workload behavior (unexpected process execution, malware-like file/network activity inside a running container). Enabled once at the org level via the log-archive account's delegated admin, so every new account is covered automatically, no per-account setup. | NIST CSF **Detect (DE)**; SOC 2 **CC7.1/CC7.2** (system monitoring, anomaly detection) |
| Security Hub, organization-wide | Aggregates security findings from GuardDuty and other AWS security services into one place, against standard security-control baselines. | NIST CSF **Detect (DE)**, **Identify (ID.RA)**; SOC 2 **CC7.1** |
| Every third-party GitHub Action pinned to a commit SHA | Prevents a compromised upstream dependency in your own CI tooling from silently changing behavior under an existing version reference. | NIST CSF **Protect (PR.PS)**; SOC 2 **CC8.1** (change management) |
| WAF with a managed core rule set + rate-based blocking, in front of every load balancer | Blocks common web attack patterns and volumetric abuse before they reach the application. | NIST CSF **Protect (PR.AA)**; SOC 2 **CC6.6** |
| AWS Config recorder, every environment, centralized into log-archive (`terraform/aws/modules/config_recorder`, `terraform/aws/example-log-archive/config-storage.tf`) | A real, queryable resource-configuration history and drift record — not just an org-wide aggregator with nothing feeding it. Extracted from a real production fix: the aggregator existed for a long time before any account actually had a recorder running. | NIST CSF **Identify (ID.AM)**, **Detect (DE.CM)**; SOC 2 **CC7.1** |
| VPC Flow Logs, every environment (`terraform/aws/modules/network`) | Network-forensics evidence after an incident, retained independently of GuardDuty's own network-based findings — a different failure mode (GuardDuty being wrong or blind) doesn't also take this out. | NIST CSF **Detect (DE.CM)**; SOC 2 **CC7.2** |
| Security Hub findings (HIGH/CRITICAL) routed to SNS — email day-one, Slack/Teams via native AWS Chatbot once configured (`terraform/aws/modules/security_alerting`) | Closes the "collected, not actually seen" gap directly: Security Hub auto-imports every GuardDuty finding as its own finding type, so a single EventBridge rule covers both without a second alerting pipeline. | NIST CSF **Respond (RS.CO)**; SOC 2 **CC7.3** (incident response/communication) |

*(This table is illustrative of the pattern, not exhaustive — cross-reference every control in `cicd-pipeline.md`, `network-vpn.md`, `encryption-secrets-aws.md`, and `authn-authz.md` against the TSC/CSF families above as you adopt them; most of what's in those docs maps to CC6.x (logical access) or CC6.6/CC6.7 (network/transmission security).)*

## Honestly deferred — a documented gap is not a failed control

Being explicit about what isn't built yet, and why it's an acceptable short-term gap rather than an oversight, is itself part of a real audit posture. An auditor (or a careful adopter of this skill) trusts a system more, not less, for naming its own gaps with a reason attached.

| Gap | Why it's commonly deferred short-term | Cost/effort to close |
|---|---|---|
| A verified backup-restore drill | Backup *configuration* being correct (retention period, multi-AZ) is necessary but not sufficient — it needs to actually be exercised at least once to know the restore process itself works under real conditions. | Effort, not cost — needs a deliberately scheduled drill, not a Terraform change. |

**Resolved** (were listed here, now in "Built and enforced" above): a centralized configuration-drift recorder actually wired up per account, VPC Flow Logs, and automated routing of findings to a human. All three were found the same way this section describes — the underlying service existing didn't mean the specific mechanism that makes it useful was actually wired up — and closed the same way `security-history.md` records other real fixes: extracted from a real production account, not designed in the abstract.

## The general principle

Don't claim a control exists because the underlying service is "enabled" in some generic sense — trace whether the specific mechanism that makes it useful (a recorder actually running, a finding actually reaching a person) is really wired up, the way `security-history.md` traces specific real misconfigurations rather than accepting a plausible-sounding default. The three rows resolved above are exactly that gap in practice: an org-wide GuardDuty/Security Hub rollout that looked complete on paper had, for a real stretch of time, no Config recorder actually running and no path for a finding to reach a person — check for the same kind of gap in every control you adopt from this doc, not just the ones already caught here.
