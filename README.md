# ansible-home-cluster

[ Bare Metal / Pi OS ]
 ├─ Vault
 ├─ dns (pihole)
 ├─ Nexus (Registry + Helm)
 ├─ Grafana / Loki / Metrics backend
 ├─ S3-like (Garage)
 ├─ Identity (Keycloak)
 ├─ edge proxy (caddy)
 ├─ load balancer (haproxy)
 └─ k3s
     ├─ Ephemeral namespaces
     ├─ Test databases
     ├─ ArgoCD / Flux
     ├─ Prometheus agents
     └─ Short-lived apps
