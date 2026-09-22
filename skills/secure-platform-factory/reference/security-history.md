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

## What this list is for

Not a hall of shame — every real system that's actually been reviewed adversarially has a list like this, and a system with an *empty* list has usually just not been looked at hard enough yet. File a PR to this doc with what you found and fixed in your own deployment of this pattern, generalized the same way these three are — the next person adopting this skill benefits from your review the same way you're benefiting from these.
