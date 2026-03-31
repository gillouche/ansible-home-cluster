# ansible-home-cluster

Ansible automation for a 14-node K3s homelab cluster (3 control planes + 11 workers).

## Cluster Architecture

| Component | Details |
|-----------|---------|
| Control Planes | homeserver, homeserver2, homeserver3 (AMD/NVIDIA GPU, NVMe SSD) |
| Workers | 3x RPi5 16GB SSD, 3x RPi5 16GB, 1x RPi5 8GB, 4x RPi4 8GB |
| K3s Version | v1.35.0+k3s1 |
| Datastore | PostgreSQL (Patroni HA, 3-node) |
| Storage | Longhorn (distributed on control planes + SSD workers) |
| GitOps | ArgoCD (app-of-apps pattern, 25 sync waves) |
| VIPs | API: 192.168.0.249, LB: 192.168.0.248, Postgres: 192.168.0.247 |

## Playbooks

| Playbook | Command | Description |
|----------|---------|-------------|
| Bootstrap | `ansible-playbook playbooks/bootstrap.yml` | Initial cluster setup |
| K3s Install | `ansible-playbook playbooks/k3s.yml` | Install/configure k3s + infrastructure |
| Start | `ansible-playbook playbooks/start_k3s.yml` | Start k3s after a stop |
| Stop | `ansible-playbook playbooks/stop_k3s.yml` | Graceful cluster shutdown |
| Restore | `ansible-playbook playbooks/restore.yml --tags restore_k3s` | Full cluster restore |
| Maintenance | `ansible-playbook playbooks/maintenance.yml` | System updates + reboot |
| Health | `ansible-playbook playbooks/health.yml` | Health checks |

## Restore Procedure

### Prerequisites

Before running the restore playbook, verify:

- All servers are powered on and reachable via SSH
- Network connectivity between all nodes (ping test)
- NVMe/SSD storage mounted on control planes (`/mnt/ssd_nvme`)
- No stale k3s processes running (`ps aux | grep k3s` on each node)
- DNS is resolving (Pi-hole VIP 192.168.0.251 responding)

### Execution

Full restore (all phases):
```bash
ansible-playbook playbooks/restore.yml
```

K3s-only restore (skip DNS/infra/apps):
```bash
ansible-playbook playbooks/restore.yml --tags restore_k3s
```

### Restore Phases

| Phase | Duration | Description |
|-------|----------|-------------|
| DNS | ~1 min | Pi-hole cluster start + VIP |
| Infrastructure | ~2 min | HAProxy, Keepalived, Caddy |
| Applications | ~3 min | Postgres HA, Authelia, Nexus, Firefly |
| K3s | ~15-30 min | Control planes, agents, tiered ArgoCD startup |
| Verification | ~1 min | API, proxy, connectivity checks |

### Tiered ArgoCD Startup

After k3s starts, ArgoCD applications are re-enabled in tiers to prevent a pod startup storm:

| Tier | Applications | Wait For |
|------|-------------|----------|
| T0 | cluster-tls, coredns-custom, sealed-secrets, reflector | CoreDNS + sealed-secrets ready |
| T1 | longhorn, longhorn-prereqs | Longhorn nodes ready, webhooks deleted |
| T2 | traefik, authelia, cluster-policies, argocd-ingress | Traefik available |
| T3 | cloudnative-pg, vpa, keda, device plugins, event-exporter | CNPG operator available |
| T4 | gatekeeper, gatekeeper-templates, gatekeeper-constraints | Gatekeeper audit available |
| T5 | postgres-shared | CNPG cluster healthy (stale resources cleaned first) |
| T6 | seaweedfs | Master-0 running |
| T7 | monitoring stack (prometheus, grafana, loki, tempo, etc.) | Prometheus running |
| T8-T12 | CI/CD, runners, data lake, user apps, chaos-mesh | No gates (lower priority) |

### Manual Intervention Procedures

If the automated restore fails at any tier, you can continue manually:

```bash
# Check which tier failed
kubectl get applications -n argocd -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' | grep -v 'Synced.*Healthy'

# Enable auto-sync on a specific app
kubectl -n argocd patch application <app-name> --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'

# Delete blocking webhooks
kubectl delete validatingwebhookconfiguration longhorn-webhook-validator --ignore-not-found
kubectl delete mutatingwebhookconfiguration longhorn-webhook-mutator --ignore-not-found
kubectl delete validatingwebhookconfiguration gatekeeper-validating-webhook-configuration --ignore-not-found

# Check Longhorn health
kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns='NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness' | grep -v 'attached.*healthy'

# Check control plane resource pressure
for h in homeserver homeserver2 homeserver3; do echo "=== $h ===" && ssh $h 'awk "/MemAvailable/ {printf \"%.0fMB\n\", \$2/1024}" /proc/meminfo'; done
```
