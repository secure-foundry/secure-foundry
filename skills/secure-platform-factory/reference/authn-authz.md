# Authentication and Authorization

Cloud-agnostic — this is about how your *application* identifies and authorizes users, distinct from the cloud/CI identity setup in the account and CI/CD docs.

## Authentication: federate, don't build your own

Integrate a real OAuth 2.0 / OIDC identity provider (Microsoft Entra ID, Google Workspace, Okta, Auth0 — whichever your users already have accounts with) rather than building password storage and reset flows yourself. Every password-handling code path you don't write is a class of vulnerability you don't have.

Non-negotiables regardless of provider:
- **Full ID-token verification** — fetch the provider's real signing keys (JWKS), verify the signature, and check audience, issuer, and (if you generated one) nonce. Don't trust a token's claims without verifying its signature against the provider's own keys — an unverified JWT is just a JSON object anyone could have written.
- **A durable identity key that isn't email.** Use the provider's own immutable subject/object identifier as your permanent join key. Email addresses change, get recycled, and can be reused by a different real person later — binding identity to email risks a new person inheriting a previous person's access.
- **Session cookies**: cryptographically random session IDs, `httpOnly` + `secure` + a same-site policy, and prefer a `__Host-`-prefixed cookie name specifically (see `security-history.md` #3 for why this closes a real vulnerability class structurally rather than by convention).
- **Invite-then-activate, not auto-create-on-login.** A pending invitation record exists before anyone can log in as that person; a login that doesn't match a pending invitation is rejected outright, with no account silently created. This is the actual mechanism behind "you can't just show up and get access" — access is granted by an explicit prior action (an invite), not implied by successfully authenticating.

## Authorization: a real Role↔Permission model, not scattered checks

**Don't hardcode roles as an enum or a boolean flag.** A `Role` and a `Permission` are both real, separate database rows, connected by an explicit many-to-many join. This means adding a new role later, or changing what an existing role can do, is a data change — not a code change and redeploy.

**One authored source of truth for the permission catalog**, consumed directly by both the application code and whatever seeds your database — never a human-maintained list in a wiki page that quietly drifts out of sync with what the code actually enforces. If your permission documentation and your permission enforcement can ever disagree, they will, eventually, and an audit (or an incident) is how you'll find out.

**Scope access to the narrowest resource it actually needs**, not just to "this user is an admin." A hierarchical resource model (an organization, its sub-units, and the specific resources within them) should let a permission check walk that hierarchy — someone with access to a department should see that department's own resources and its sub-units', not the whole company's, and definitely not by virtue of holding some separate, unrelated platform-level admin role.

**A platform-level administrative role is a genuinely different scope, not a bigger version of a regular role.** Someone who can provision new tenant organizations and someone who manages one organization's own team are different kinds of access entirely — model the platform-admin scope as its own thing (with no organization/tenant tied to it at all), not as "the regular admin role, but with an extra flag turned on."

**Impersonation/act-as, if you need it, must be live-revalidated and time-boxed.** If a support or admin flow lets one person act as another, don't cache "this access was granted" as a permanent fact — check on every request whether the underlying grant is still active and unexpired. Log every act-as session's start, its real actor, who they're acting as, and its end — for an audit, and so the impersonated person's own trust in the system doesn't depend on hoping nobody misused it unnoticed.

## Handling the login that doesn't match anything

A login attempt from someone with no matching invitation should be rejected outright, with no user or access record created — but the attempt itself is worth logging (who, when, from where) and, where practical, worth notifying an existing administrator about, as a self-service signal that someone tried to get in without an invitation. This is different from a failed-password scenario (which shouldn't exist at all under an identity-provider-only model) — it's specifically "an authenticated real person, from a real identity provider, who nobody invited."
