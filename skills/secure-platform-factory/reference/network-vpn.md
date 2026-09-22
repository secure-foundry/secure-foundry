# Network Isolation and VPN Access

Cloud-agnostic pattern first, then per-cloud wiring notes.

## The pattern

**No database or internal service ever gets a public IP, full stop.** Every data-plane resource (database, internal application service) lives in a private subnet/network with no route to the public internet. The only pieces with public exposure are: a load balancer (fronted by a WAF) for actual end-user traffic, and — for administrative/CI access — nothing public at all, routed instead through the VPN layer below.

**A layered security-group/firewall trust chain, not a flat allow-list.** The database trusts only the application tier's own security group, on only its native port. The application tier trusts only the load balancer's security group. Nothing has a shortcut path around this chain — there is no "just open port 5432 to this one IP" exception, because that exception is exactly what an incident review finds three years later, forgotten and still open.

**VPN replaces the bastion host entirely.** A traditional bastion host (a single SSH-exposed jump box) is a single point of both failure and compromise — anyone who gets that one box's key gets a foothold into your whole private network. The recommended alternative is a mesh VPN with per-device authentication.

## VPN options, ranked

**Recommended default: Tailscale.** WireGuard-based, generous free tier for small teams, minimal operational overhead (no VPN server to patch and run yourself). The pattern: run one lightweight "subnet router" node inside each private network, advertising that network's CIDR range to the tailnet — anyone authorized on the tailnet (via Tailscale's own identity-provider-backed device auth) can then reach the private network directly, with no bastion, no public endpoint, and no shared static credential. The subnet router should run with the *minimum* privilege the underlying platform allows — on a container platform without full kernel access, that means userspace/netstack mode rather than kernel-mode routing, which still works correctly for this purpose.

**Zero-cost, fully self-hosted alternative: Headscale + WireGuard.** An open-source, self-hosted control-plane reimplementation of Tailscale's coordination server. Same subnet-router pattern, but you run and maintain the coordination server yourself instead of using a managed service — the right choice if a third-party control plane (even one that never sees your actual traffic, only coordinates key exchange) is a hard no for your threat model.

**Cloud-native alternative: each cloud's own Client VPN service** (AWS Client VPN, GCP Cloud VPN, Azure VPN Gateway). Keeps remote access inside the cloud provider's own IAM boundary instead of introducing a third-party identity system — worth it specifically if your compliance framework requires every access-control decision to be auditable through one single provider's IAM logs, or if organizational policy simply prohibits third-party network tools regardless of their design.

## What to actually configure, regardless of choice

- Authenticate VPN access through the **same identity provider** your application and cloud console already use — never a separate, standalone credential just for VPN. A second, unfederated login system is a second place credentials can go stale or get shared.
- Scope VPN access **per environment**, not globally. Access to the dev network shouldn't imply access to the prod network's VPN endpoint.
- CI needs the same access pattern as a human operator for one specific case: running database migrations from a pipeline job against a private-subnet database. Join the pipeline runner to the VPN as an ephemeral, tagged, single-purpose identity — never a long-lived credential shared across runs.

## Per-cloud wiring

- **AWS**: private subnets with no route to an internet gateway (only a NAT gateway for outbound-only internet access, e.g. patch downloads); security groups reference each other by ID, not by CIDR, so the trust chain survives IP churn.
- **GCP**: VPC with private Google access enabled for subnets that need to reach managed services (like a managed database) without a public IP; firewall rules use service accounts or network tags as the source, mirroring the security-group-by-reference pattern.
- **Azure**: VNet with private endpoints for managed services; NSGs (Network Security Groups) reference application security groups rather than raw IP ranges for the same reason.
