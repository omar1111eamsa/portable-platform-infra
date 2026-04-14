# Network Policies

Default-deny network policies applied in namespace `myapp`. All inter-service communication is blocked by default and must be explicitly allowed.

## Applied Policies

| File | Effect |
|---|---|
| `00-default-deny.yaml` | Deny all ingress and egress for all pods in the namespace |
| `10-allow-dns-egress.yaml` | Allow egress to CoreDNS (kube-system, port 53 TCP/UDP) |
| `20-allow-traefik-ingress.yaml` | Allow ingress from Traefik ingress controller |
| `25-allow-traefik-acme-http01-solver.yaml` | Allow Traefik ACME HTTP-01 challenge traffic |
| `30-allow-internal-service-ports.yaml` | Allow inter-pod communication on defined service ports |
| `40-allow-external-egress.yaml` | Allow egress to the internet for external API calls |

## Notes

- Network policies are enforced by the CNI (k3s default: Flannel with NetworkPolicy support).
- Policies are additive: a packet is allowed if any policy permits it.
- Review `30-allow-internal-service-ports.yaml` when adding new services that require internal communication.
