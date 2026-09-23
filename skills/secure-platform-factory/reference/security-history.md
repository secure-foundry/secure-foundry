# Security History — Real Issues Caught in the AWS Reference Implementation

Honesty about what went wrong, and how it was found and fixed, is worth more than a claim that everything was right the first time. These are real issues found during independent adversarial review of the AWS implementation this skill's AWS path is extracted from — before they ever reached a production incident, which is the entire point of the review discipline described in `review-culture.md`.

## 1. Wildcard match in an OIDC trust policy

**What was wrong**: an early version of the CI-to-cloud OIDC trust policy matched the calling identity's subject claim against a wildcard pattern on the organization/repository name (e.g. `YourOrg*`). This is a real vulnerability, not a theoretical one: a wildcard match like that would also match an attacker-created organization with a similar name (`YourOrg-attacker`), since string prefix matching doesn't distinguish "the real org" from "a different org that happens to start with the same letters."

**The fix**: match on the CI provider's own immutable numeric IDs (organization ID and repository ID, not name strings) via exact equality, not a wildcard or prefix pattern. Names can be squatted; numeric IDs, issued once at creation, cannot.

**Why this matters generally**: any trust relationship based on a string pattern match on a name is suspect. Ask, for any trust policy: "if someone else could create an entity whose name matches this pattern, would this policy trust them too?"

## 2. A database's own auto-generated secret defaulting to the wrong encryption key

**What was wrong**: a managed database's automatically-generated master-password secret was left on the cloud provider's own shared default encryption key, while the database's actual data storage was correctly encrypted with the project's own customer-managed key. The secret itself — the credential that unlocks the data — was, subtly, on a different and less tightly-scoped key than the data it protected.

**The fix**: explicitly set the auto-generated secret's encryption key to the same customer-managed key used everywhere else in that environment, rather than accepting whatever the managed-database feature defaults to.

**Why this matters generally**: a feature that manages a secret *for* you can quietly default to weaker protection than the rest of your explicit configuration — "managed" doesn't mean "reviewed." Check every credential a managed service creates on your behalf, not just the resources you configured directly.

## 3. A cross-subdomain session cookie vulnerability

**What was wrong**: a session cookie was scoped with an explicit `Domain` attribute covering the whole parent domain (e.g. `.example.com`), rather than being scoped to just the specific subdomain serving the application. This means a cookie set correctly by the production subdomain could also be read by, or a malicious cookie planted by, any other subdomain under the same parent — including a lower-security development or staging subdomain.

**The fix**: use a browser-enforced `__Host-`-prefixed cookie name. Browsers refuse to honor a `Domain` attribute at all on a cookie with this prefix, and additionally require `Secure` and root `Path=/` — closing the cross-subdomain path structurally, at the browser level, rather than relying on remembering to omit the `Domain` attribute correctly in every code path that sets a cookie.

**Why this matters generally**: prefer a mechanism the browser (or platform) enforces structurally over a configuration convention that has to be remembered correctly every time. A missing `Domain` attribute is one omission away from being wrong again in the next code path that sets a cookie; a `__Host-` prefix makes the safe behavior the only behavior.

## 4. SkillSpector's first real scan — an unpinned floating tag and a curl-pipe-to-bash install, both in our own example Terraform

**What was wrong**: adding SkillSpector (stage 8) as an observational scanning stage and running it for real against this repo's own skill content immediately surfaced two genuine, unrelated-to-the-tool-itself supply-chain issues in the Azure `vpn_router` module: the Tailscale container image was pinned to the floating `:stable` tag rather than a specific version, and the VM's cloud-init bootstrap installed the Azure CLI via `curl -sL <url> | bash` — piping a downloaded script directly into a shell with no integrity verification. The same floating-tag issue existed, unflagged by this particular scan but found by checking the analogous GCP module by hand, in `terraform/gcp/modules/vpn_router/main.tf`. A related, distinct finding: the example `deploy-<cloud>.yml` workflow templates invoked `npx node-pg-migrate` with no version pin, meaning a compromised future release of that package would be pulled automatically at deploy time with no warning.

**The fix**: pinned the Tailscale image to a specific release tag in both the Azure and GCP modules; replaced the `curl | bash` install with Microsoft's own documented apt-repository method (import the real signing key, add the package repo, `apt-get install`) — verifiable and pinned to whatever the repo's index currently serves, rather than trusting an arbitrary script fetch; pinned the `node-pg-migrate` invocation in all three deploy templates to an exact version.

**Why this matters generally**: this is the exact thing stage 8 says a skill-security scanner is for, and it caught real issues in the *reference implementation this project ships*, not a hypothetical adopter's code — proof the pattern works, not just a design that sounds good on paper. It's also a good illustration of the "review it before making it required" caution stage 8 itself recommends: alongside these two real, fixable findings, the same scan also flagged two passages in `cicd-pipeline.md` and `encryption-secrets-aws.md` that talk *about* credential access and autonomous agent behavior defensively — exactly the false-positive class predicted before the tool was ever run for real.

## 5. An org-wide GuardDuty/Security Hub rollout with no recorder running and no way for a finding to reach a person

**What was wrong**: the AWS reference implementation this skill's AWS path is extracted from had GuardDuty and Security Hub enabled organization-wide for a real stretch of time — genuinely generating findings — with three gaps that made that rollout much less useful than it looked on paper: no account had an actual AWS Config recorder/delivery channel running (the org-wide aggregator existed, but was aggregating nothing), no VPC Flow Logs anywhere (so a GuardDuty network finding had no independent forensic trail to cross-check against), and no path for a GuardDuty or Security Hub finding to actually reach a human — they were being collected, not seen.

**The fix**: a per-account AWS Config recorder + delivery channel (`terraform/aws/modules/config_recorder`), VPC Flow Logs on every VPC (`terraform/aws/modules/network`), and an SNS topic + EventBridge rule routing Security Hub's HIGH/CRITICAL imported findings (which include every auto-imported GuardDuty finding) to email immediately and to Slack/Teams via native AWS Chatbot once configured (`terraform/aws/modules/security_alerting`). See `monitoring-compliance-aws.md`'s "Built and enforced" table for the compliance-mapping detail.

**Why this matters generally**: "the service is enabled" and "the control is actually doing its job" are different claims, and the gap between them is exactly where this kind of finding lives — a detection service that's on but unmonitored is barely better than one that's off, and it's easy to mistake the first for the second when reading a list of enabled AWS services rather than checking whether each one's output actually reaches somewhere useful.

## What this list is for

Not a hall of shame — every real system that's actually been reviewed adversarially has a list like this, and a system with an *empty* list has usually just not been looked at hard enough yet. File a PR to this doc with what you found and fixed in your own deployment of this pattern, generalized the same way these five are — the next person adopting this skill benefits from your review the same way you're benefiting from these.
