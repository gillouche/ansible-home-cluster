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
