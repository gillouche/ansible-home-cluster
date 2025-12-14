# ansible-home-cluster

## Testing Vault ACME with acme.sh (Docker)

This project configures Caddy to obtain certificates from Vault’s ACME endpoint. For manual testing with a real ACME client, you can use the helper script installed on Vault nodes:

```
sudo /usr/local/bin/vault-acme-test.sh <domain> \
  --server https://<vault-ip>:8200/v1/pki/acme/directory \
  --email noreply@<your-domain> [--alpn | --http-01]
```

Defaults and behavior:
- ACME client in Docker per acme.sh docs: https://github.com/acmesh-official/acme.sh/wiki/Run-acme.sh-in-docker
- State is mounted at `/acme.sh` inside the container from `~/.acme-test` on host
- Host CA bundle is mounted into the container and `SSL_CERT_FILE` is set so the client trusts Vault’s TLS
- Challenge defaults to TLS-ALPN-01 (requires port 443 to be free). Use `--http-01` to force HTTP-01 (requires port 80 per ACME spec)

Examples:

1) TLS-ALPN-01 (recommended when 443 is free)
```
sudo /usr/local/bin/vault-acme-test.sh primary.pihole.gillouche.homelab \
  --server https://192.168.0.13:8200/v1/pki/acme/directory \
  --email noreply@gillouche.homelab --alpn
```

2) HTTP-01 (requires port 80; stop any service on :80 first)
```
sudo /usr/local/bin/vault-acme-test.sh primary.pihole.gillouche.homelab \
  --server https://192.168.0.13:8200/v1/pki/acme/directory \
  --email noreply@gillouche.homelab --http-01
```

3) Optional: deploy certs into another container using acme.sh’s docker deploy hook
```
sudo /usr/local/bin/vault-acme-test.sh primary.pihole.gillouche.homelab \
  --server https://192.168.0.13:8200/v1/pki/acme/directory \
  --email noreply@gillouche.homelab --alpn \
  --deploy-to some-container-name
```

Advanced:
- You can choose the client via `--client acme.sh|lego` (default `acme.sh`). `lego` uses `goacme/lego` and supports `--http` or `--tls` (`--alpn` in the script). See https://github.com/Neilpang/letsproxy for related proxy patterns and the acme.sh wiki for deploy options: https://github.com/acmesh-official/acme.sh/wiki/deploy-to-docker-containers

Troubleshooting:
- HTTP-01 must bind to port 80; TLS-ALPN-01 must bind to port 443. If those ports are in use (e.g., by Caddy), stop the service or choose the alternate challenge.
- Ensure the test domain resolves to the host running the test.
- Ensure the Vault ACME directory URL is reachable from the node.

---

## Install required collections
This project pins exact collection versions for reproducibility in `requirements.yml`.

```
ansible-galaxy collection install -r requirements.yml
```

Pinned currently:
- community.general==12.1.0
- community.docker==5.0.4
- ansible.posix==2.1.0
- ansible.utils==6.0.0

## Inventory and variables layout
- Inventory topology: `inventories/inventory.yml`
- Variables for this inventory: `inventories/group_vars/` and `inventories/host_vars/`
  - `inventories/group_vars/all.yml` (global settings like `base_domain`)
  - `inventories/group_vars/pihole_cluster.yml`
  - `inventories/group_vars/reverse_proxy_cluster.yml`
  - `inventories/group_vars/vault_cluster.yml`

### Secrets (vaulted)
Keep secrets only in vaulted files alongside the inventory, e.g.:
- `inventories/group_vars/pihole_cluster.vault.yml`
- `inventories/group_vars/reverse_proxy_cluster.vault.yml`

Encrypt with:

```
ansible-vault encrypt inventories/group_vars/pihole_cluster.vault.yml
ansible-vault encrypt inventories/group_vars/reverse_proxy_cluster.vault.yml
```

## SSH posture and known_hosts
Host key checking is enabled in `ansible.cfg`. Populate the controller’s `known_hosts` once:

```
ansible-playbook -i inventories/inventory.yml playbooks/bootstrap_controller_host.yml
```

## VRRP authentication (keepalived)
Provide strong vaulted passwords:
- `pihole_vrrp_auth_pass` in `inventories/group_vars/pihole_cluster.vault.yml`
- `reverse_proxy_vrrp_auth_pass` in `inventories/group_vars/reverse_proxy_cluster.vault.yml`

## Resolver policy
Reverse proxy prefers systemd‑resolved integration (manages `/etc/systemd/resolved.conf` and ensures `/etc/resolv.conf` points to the stub). To manage `/etc/resolv.conf` directly instead:

```
reverse_proxy_manage_resolved: false
reverse_proxy_manage_resolv_conf: true
```

Pi‑hole minimally updates `pihole.toml` (keeps defaults) and uses dnsmasq.d for wildcard/custom DNS.

## Image pinning policy
Role defaults pin images; override per environment cautiously.
- Pi‑hole: `pihole/pihole:2025.11.1`
- Caddy: `caddy:2.10.2`
- Vault: `hashicorp/vault:1.21.1`

## Running the plays
Main playbook:

```
ansible-playbook -i inventories/inventory.yml playbooks/setup.yml
```

Role-level tags (only):

```
ansible-playbook -i inventories/inventory.yml playbooks/setup.yml --tags pihole
ansible-playbook -i inventories/inventory.yml playbooks/setup.yml --tags vault
ansible-playbook -i inventories/inventory.yml playbooks/setup.yml --tags proxy
```

Use `--check` for dry-runs; tasks that must mutate declare `check_mode: no` explicitly.

## Recommended bring-up order
1. Pi‑hole cluster (VIP for DNS)
2. Vault cluster (PKI + ACME)
3. Reverse proxy (Caddy + VIP)

## Container hardening summary
- `read_only: true` where possible
- `cap_drop: [ALL]` and minimal `capabilities` only when needed (e.g., `NET_BIND_SERVICE`)
- Non‑root user where supported (Caddy, Vault; Pi‑hole best‑effort via variable)
- Healthchecks defined (Pi‑hole DNS, Caddy HTTP, Vault API)
- Mounts minimized and RO where feasible (data/config RW where required)

## Linting & CI
- `.ansible-lint` and `.yamllint.yml` configured
- GitHub Actions workflow `.github/workflows/lint.yml`

Run locally:

```
ansible-lint
yamllint .
```

## Notes
- Least privilege: plays use `become: false` by default; tasks escalate only as needed.
- Idempotency: re‑running converges state; handlers manage restarts.

---

## Operational Runbook (common day‑2 tasks)

All commands assume you run from the project root with the inventory at `inventories/inventory.yml`.

1) Rotate VRRP authentication secrets (keepalived)
- Edit vaulted files with new strong secrets (12+ chars):
  - `inventories/group_vars/pihole_cluster.vault.yml` → set `pihole_vrrp_auth_pass`
  - `inventories/group_vars/reverse_proxy_cluster.vault.yml` → set `reverse_proxy_vrrp_auth_pass`
- Apply roles (dry‑run first):
  - Pi‑hole: `ansible-playbook -i inventories/inventory.yml playbooks/setup.yml --tags pihole --check` then run without `--check`.
  - Reverse proxy: same with `--tags proxy`.

2) Rotate Vault automation/admin tokens
- Force automation token recreate: remove `~/.local/share/ansible-home-cluster/vault-ansible-token.json*` on the controller, then run `--tags vault` (dry‑run first).
- For one‑off admin actions, pass `-e vault_admin_token=...` or set in inventory for that run.

3) Distribute or rotate Vault Root/Cluster CAs
- With trust flags enabled (`vault_install_root_ca_on_hosts`, `vault_trust_ca_on_controller`), rerun `--tags vault` (dry‑run first). The role ensures CA presence and trusts on macOS as configured.

4) Scale Pi‑hole cluster (add/remove replica)
- Edit `inventories/inventory.yml` group `pihole_replicas` to add/remove hosts.
- Apply Pi‑hole: run `--tags pihole` (dry‑run first). Gravity Sync is configured on replicas if enabled.

5) Replace a node
- Update `inventories/inventory.yml` with the new IP/host.
- Refresh controller known_hosts if needed: run `playbooks/bootstrap_controller_host.yml`.
- Apply the relevant role tag.

6) Upgrade a container image safely
- Override image in the relevant group vars (e.g., `reverse_proxy_image: caddy:<tested-version>`) and apply the tag for that role (dry‑run first). Repeat for `pihole_image` and `vault_image` as needed.

7) Switch resolver policy on reverse proxy hosts
- In `inventories/group_vars/reverse_proxy_cluster.yml`: set `reverse_proxy_manage_resolved: false` and `reverse_proxy_manage_resolv_conf: true`. Apply `--tags proxy` (dry‑run first).

8) Refresh controller known_hosts after inventory changes
- Run `playbooks/bootstrap_controller_host.yml` to populate `~/.ssh/known_hosts` for all inventory hosts.

9) Troubleshooting quick tips
- Lint: `ansible-lint`, `yamllint .`
- Dry‑run a role: add `--tags <role>` and `--check`, optionally `-vv` for verbosity
- Inspect containers: `docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'` then `docker logs <container> | tail -n 200`

---

## What is an Ansible Execution Environment (EE)?

An Execution Environment is a container image that bundles Ansible, Python, and required collections so your playbooks run with a predictable toolchain across machines.

Benefits:
- Reproducibility: consistent Ansible and collection versions everywhere
- Portability: developers and automation use the same image
- Simplicity: avoid managing Python packages on the controller

Typical workflow:
- Define dependencies (collections and Python packages) in an `execution-environment.yml` file.
- Build the EE image with `ansible-builder` (e.g., `ansible-builder build -t ahc-ee:latest`).
- Run playbooks using that image (e.g., `ansible-navigator run -m stdout -eei ahc-ee:latest playbooks/setup.yml -i inventories/inventory.yml`).

Note: This project already runs fine natively on your controller; adopting an EE is an optional next step when you want fully pinned, containerized tooling for repeatability.
