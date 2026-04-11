# Network Policies (myapp)

Baseline policies applied in namespace `myapp`:

1. `00-default-deny.yaml`  
   Deny all ingress/egress by default.

2. `10-allow-dns-egress.yaml`  
   Allow DNS egress to CoreDNS (`kube-system`, `k8s-app=kube-dns`, TCP/UDP 53).

3. `20-allow-traefik-ingress.yaml`  
   Allow ingress from Traefik (`kube-system`, `app.kubernetes.io/name=traefik`) to:
   - `api-gateway` on TCP 8888
   - `frontend` on TCP 3000

4. `25-allow-traefik-acme-http01-solver.yaml`  
   Allow ingress from Traefik to cert-manager HTTP-01 solver pods
   (`acme.cert-manager.io/http01-solver=true`) on TCP 8089 for Let's Encrypt challenges.

5. `30-allow-internal-service-ports.yaml`  
   Allow internal `myapp` namespace service traffic only on required ports
   (`3000, 5432, 5672, 6379, 8080-8084, 8500, 8888`).

6. `40-allow-external-egress.yaml`  
   Allow internet egress (`80/443/465/587`) for selected pods that need external APIs/mail:
   `user-management`, `payment-service`, `chatbot`, `metamodel-*`, `execution-engine`.

## Apply

```bash
kubectl apply -k deploy/k8s/network-policies
```

## Validate quickly

```bash
kubectl -n myapp get networkpolicy
kubectl -n myapp get pods
```
