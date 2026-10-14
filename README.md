# Assign2 — Voting App on Kubernetes (Helm + ArgoCD + OpenBao)

The Docker [example voting app](https://github.com/dockersamples/example-voting-app) deployed to a local **kind** cluster
in three environments (dev / stage / prod) using a single Helm umbrella chart, delivered by **ArgoCD (GitOps)**,
exposed through **Envoy Gateway**, with database credentials stored in **OpenBao** and synced by **External Secrets Operator**.

> No secret values live in this repository. Git only holds *where* a secret comes from (an OpenBao path).

---

## Architecture

```
                         Browser  (http://<app>.<env>.lab:7070)
                                   │
                    kubectl port-forward 7070 → 80
                                   │
            ┌──────────────────────▼───────────────────────┐
            │  Envoy Gateway  — shared-gateway             │  ns: envoy-gateway-system
            │  routes by hostname (HTTPRoute per env)      │
            └──────┬──────────────────┬────────────────────┘
                   │                  │
   ┌───────────────▼──── one namespace per env: assign2-{dev,stage,prod} ─────────────────┐
   │                                                                                     │
   │   vote ──────► redis ──────► worker ──────► postgres (StatefulSet + PVC)            │
   │  (Python)     (queue)        (.NET)              ▲         ▲                        │
   │                                                  │         │                        │
   │                                      result ─────┘     adminer (dev/stage only)     │
   │                                     (Node.js)                                       │
   │                                                                                     │
   │   Secret assign2-db-secret-<env>  ◄── ExternalSecret (ESO)                          │
   │   HPA (vote) · PDB · ResourceQuota · NetworkPolicies · PriorityClasses              │
   └─────────────────────────────────────────────────▲───────────────────────────────────┘
                                                     │ reads secret/assign2/<env>/db
                                   ┌─────────────────┴──────────────────┐
                                   │ ClusterSecretStore                 │
                                   │ openbao-cluster-store              │
                                   └─────────────────┬──────────────────┘
                                                     │ Kubernetes auth (role assign2-eso-role)
                                   ┌─────────────────▼──────────────────┐
                                   │ OpenBao  (ns: openbao)             │
                                   └────────────────────────────────────┘

   GitHub (main) ──► ArgoCD (ns: argocd) ──► helm/assign2 + values-<env>.yaml ──► assign2-<env>
```

### Delivery flow (GitOps)

1. Change the chart or a `values-<env>.yaml` file.
2. Commit and push to `main`.
3. ArgoCD detects the change (polls about every 3 minutes) and syncs all three environments (auto-sync, prune, self-heal).

Do **not** run `helm install` / `helm upgrade` against these namespaces. ArgoCD owns them and will revert manual changes.

---

## Repository layout

```
helm/assign2/                 Umbrella chart
├── values.yaml               Shared defaults
├── values-dev.yaml           dev overrides   (domain dev.lab)
├── values-stage.yaml         stage overrides (domain stage.lab)
├── values-prod.yaml          prod overrides  (domain prod.lab, adminer disabled)
├── templates/
│   ├── db-secret.yaml        ExternalSecret → OpenBao assign2/<env>/db
│   └── dns-aliases.yaml      "db" / "redis" ExternalName aliases (images hardcode these hosts)
└── charts/
    ├── data/                 postgres, redis
    ├── app/                  vote, result, worker, adminer
    ├── ingress/              HTTPRoutes on shared-gateway
    └── security/             HPA, PDB, ResourceQuota, NetworkPolicies, PriorityClasses
argocd/                       ArgoCD Applications (dev/stage/prod) + ClusterSecretStore
openbao/setup-openbao.sh      OpenBao init / unseal / auth / secrets bootstrap
```

---

## Environments

| Env   | Namespace       | ArgoCD app      | Replicas (vote/result/worker) | Adminer |
|-------|-----------------|-----------------|-------------------------------|---------|
| dev   | `assign2-dev`   | `assign2-dev`   | 2 / 1 / 1                     | yes     |
| stage | `assign2-stage` | `assign2-stage` | 2 / 1 / 1                     | yes     |
| prod  | `assign2-prod`  | `assign2-prod`  | 5 / 2 / 2                     | no      |

### URLs (via Envoy Gateway port-forward on 7070)

| Env   | Vote                          | Result                          | Adminer                          |
|-------|-------------------------------|---------------------------------|----------------------------------|
| dev   | http://vote.dev.lab:7070      | http://result.dev.lab:7070      | http://adminer.dev.lab:7070      |
| stage | http://vote.stage.lab:7070    | http://result.stage.lab:7070    | http://adminer.stage.lab:7070    |
| prod  | http://vote.prod.lab:7070     | http://result.prod.lab:7070     | — (disabled)                     |
| ArgoCD| https://argocd.lab:8080       |                                 |                                  |

Required `/etc/hosts` entries:

```
127.0.0.1  vote.dev.lab result.dev.lab adminer.dev.lab
127.0.0.1  vote.stage.lab result.stage.lab adminer.stage.lab
127.0.0.1  vote.prod.lab result.prod.lab adminer.prod.lab
127.0.0.1  argocd.lab
```

---

## Daily start-up (after a laptop / cluster restart)

```bash
# 1. Unseal OpenBao (it seals itself on every restart; ESO cannot sync secrets until this is done)
bash openbao/setup-openbao.sh --unseal-only

# 2. Envoy Gateway → all app URLs on :7070
kubectl port-forward -n envoy-gateway-system \
  svc/envoy-envoy-gateway-system-shared-gateway-0ee10bef 7070:80

# 3. ArgoCD UI → https://argocd.lab:8080   (separate terminal)
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

If a port is "already in use", an old port-forward is still running: `ss -ltnp | grep 7070`, then kill that PID.

---

## Access and credentials

### ArgoCD

- URL: https://argocd.lab:8080 (self-signed certificate; accept the browser warning)
- Username: `admin`
- Password (initial):

  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d; echo
  ```

  After first login, change it (*User Info → Update Password*) and delete `argocd-initial-admin-secret`.
  If the secret is already deleted, ask the cluster owner for the current password.

### Adminer (dev / stage)

| Field    | Value                         |
|----------|-------------------------------|
| System   | PostgreSQL                    |
| Server   | `db-dev` / `db-stage`         |
| Username | read from OpenBao (see below) |
| Password | read from OpenBao (see below) |
| Database | `postgres`                    |

### Database credentials (OpenBao)

Stored at `secret/assign2/<env>/db` with keys `postgres-user` and `postgres-password`.
To read the value the app is actually using:

```bash
kubectl -n assign2-dev get secret assign2-db-secret-dev \
  -o jsonpath='{.data.postgres-password}' | base64 -d; echo
```

> The upstream `dockersamples` worker and result images hardcode user/password `postgres` and database `postgres`,
> so the value in OpenBao must stay `postgres` until custom images are built.

### OpenBao

- Unseal key and root token are in `~/openbao-init.json` on the cluster owner's machine (mode 600, **never commit it**).
- First-time bootstrap (init, unseal, KV v2, Kubernetes auth, ESO policy/role, per-env secrets):

  ```bash
  DB_PASSWORD='<password>' bash openbao/setup-openbao.sh
  ```

---

## Verification

```bash
# ArgoCD status of all environments
kubectl get applications -n argocd

# Secrets synced from OpenBao
kubectl get clustersecretstore
kubectl get externalsecret -A

# End-to-end: cast a vote and confirm it reached postgres
curl -s -o /dev/null -w "%{http_code}\n" -X POST -d "vote=a" http://vote.dev.lab:7070/
kubectl logs -n assign2-dev deploy/worker-dev -c worker --tail=3
kubectl exec -n assign2-dev postgres-dev-0 -- \
  psql -U postgres -d postgres -c "select vote, count(*) from votes group by vote;"
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Pods in `CreateContainerConfigError` | DB Secret missing | `kubectl get externalsecret -n <ns>`; if not synced, unseal OpenBao |
| `ClusterSecretStore` not Ready | OpenBao sealed | `bash openbao/setup-openbao.sh --unseal-only` |
| URL returns 404 | Wrong hostname / port-forward to wrong service | Check `kubectl get httproute -A` and `/etc/hosts` |
| Pods `FailedCreate ... exceeded quota` | ResourceQuota too small for HPA scale-up | Raise `security.quota` in `values-<env>.yaml` and push |
| Manual change reverted | ArgoCD self-heal | Make the change in git instead |
| Result page shows no numbers | Worker cannot reach db/redis | `kubectl logs deploy/worker-<env> -c worker` |

---

## Known limitations / next steps

- Single `ClusterSecretStore` and ESO role for all envs; the policy allows reading `assign2/*`.
  Hardening: one store + role + policy per environment, restricted to its namespace.
- App images hardcode DB credentials; build custom images to allow real password rotation.
- HTTP only (no TLS listener on the gateway).
