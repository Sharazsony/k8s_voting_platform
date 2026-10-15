# Assign2 — Voting App on Kubernetes (Helm + ArgoCD + OpenBao)

The Docker [example voting app](https://github.com/dockersamples/example-voting-app) deployed to a local **kind** cluster
in three environments (dev / stage / prod) using one Helm umbrella chart, delivered by **ArgoCD (GitOps)**,
exposed through **Envoy Gateway**, with database credentials stored in **OpenBao** and synced by **External Secrets Operator (ESO)**.

> No secret values live in this repository. Git only holds *where* a secret comes from (an OpenBao path).
> An optional Terraform setup for Oracle Cloud (OKE) lives in [`terraform/oci/`](terraform/oci/README.md).

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
                                   │ (SA external-secrets/assign2-eso-sa)│
                                   └─────────────────┬──────────────────┘
                                                     │ Kubernetes auth: role assign2-eso-role
                                                     │                  → policy assign2-read
                                   ┌─────────────────▼──────────────────┐
                                   │ OpenBao  (ns: openbao)             │
                                   └────────────────────────────────────┘

   GitHub (main) ──► ArgoCD (ns: argocd) ──► helm/assign2 + values-<env>.yaml ──► assign2-<env>
```

### Request flow

1. **vote** (frontend) writes each vote to **redis**.
2. **worker** takes votes from redis and stores them in **postgres**.
3. **result** (frontend) reads the totals from postgres.
4. **adminer** (dev/stage only) is a web UI for the database.

### Delivery flow (GitOps)

1. Change the chart or a `values-<env>.yaml` file.
2. Commit and push to `main`.
3. ArgoCD detects the change (polls about every 3 minutes) and syncs all three environments
   (auto-sync, prune, self-heal).

Do **not** run `helm install` / `helm upgrade` against the `assign2-*` namespaces. ArgoCD owns them and reverts
manual changes within seconds (self-heal).

---

## Repository layout

```
.
├── README.md
├── helm/assign2/                    Umbrella chart (deployed by ArgoCD, never by hand)
│   ├── Chart.yaml                   Depends on the 4 subcharts below
│   ├── values.yaml                  Shared defaults (only global.adminerEnabled)
│   ├── values-dev.yaml              dev:   domain dev.lab,   HPA 2–4,  adminer on
│   ├── values-stage.yaml            stage: domain stage.lab, HPA 2–6,  adminer on
│   ├── values-prod.yaml             prod:  domain prod.lab,  HPA 5–10, adminer off
│   ├── templates/
│   │   ├── _helpers.tpl             resourceName (<name>-<env>), image, labels
│   │   ├── db-secret.yaml           ExternalSecret → OpenBao secret/assign2/<env>/db
│   │   └── dns-aliases.yaml         "db" / "redis" ExternalName aliases (images hardcode these hosts)
│   └── charts/
│       ├── data/                    postgres (StatefulSet + PVC + ConfigMap), redis (Deployment + ConfigMap)
│       ├── app/                     vote, result, worker (+ ServiceAccount), adminer
│       ├── ingress/                 HTTPRoutes vote/result/adminer on shared-gateway
│       └── security/                HPA (vote), PDB (vote), ResourceQuota, NetworkPolicies, PriorityClasses
├── argocd/                          ArgoCD Applications, one per environment
│   ├── app-assign2-dev.yaml         → namespace assign2-dev,   values-dev.yaml
│   ├── app-assign2-stage.yaml       → namespace assign2-stage, values-stage.yaml
│   └── app-assign2-prod.yaml        → namespace assign2-prod,  values-prod.yaml
├── openbao/                         OpenBao + ESO wiring (applied by hand, not by ArgoCD)
│   ├── setup-openbao.sh             init, unseal, KV v2, Kubernetes auth, policy, role, DB secrets
│   ├── eso-serviceaccount.yaml      ServiceAccount assign2-eso-sa (ns external-secrets)
│   └── clustersecretstore.yaml      ClusterSecretStore openbao-cluster-store
├── platform/kind/gateway.yaml       GatewayClass "eg" + Gateway shared-gateway (applied once by hand)
└── terraform/oci/                   Optional: same system on Oracle Cloud OKE (see its README)
```

---

## Environments

| Env   | Namespace       | ArgoCD app      | Vote (HPA min–max, CPU) | Result / Worker | PDB (vote) | Adminer |
|-------|-----------------|-----------------|-------------------------|-----------------|------------|---------|
| dev   | `assign2-dev`   | `assign2-dev`   | 2–4, 70%                | 1 / 1           | min 1      | yes     |
| stage | `assign2-stage` | `assign2-stage` | 2–6, 65%                | 1 / 1           | min 1      | yes     |
| prod  | `assign2-prod`  | `assign2-prod`  | 5–10, 60%               | 2 / 2           | min 2      | no      |

- **Vote replicas are owned by the HPA**, so there is no `vote.replicaCount`. Change `security.hpa` instead.
- Each env also has a ResourceQuota (`security.quota`: CPU, memory, PVC count, pod count).
- Every environment is isolated in its own namespace. The only cluster-scoped objects are the
  env-suffixed PriorityClasses (`postgres-priority-<env>`, `adminer-priority-<env>`).

### URLs (via Envoy Gateway port-forward on 7070)

| Env    | Vote                       | Result                       | Adminer                       |
|--------|----------------------------|------------------------------|-------------------------------|
| dev    | http://vote.dev.lab:7070   | http://result.dev.lab:7070   | http://adminer.dev.lab:7070   |
| stage  | http://vote.stage.lab:7070 | http://result.stage.lab:7070 | http://adminer.stage.lab:7070 |
| prod   | http://vote.prod.lab:7070  | http://result.prod.lab:7070  | — (disabled)                  |
| ArgoCD | https://argocd.lab:8080    |                              |                               |

Required `/etc/hosts` entries:

```
127.0.0.1  vote.dev.lab result.dev.lab adminer.dev.lab
127.0.0.1  vote.stage.lab result.stage.lab adminer.stage.lab
127.0.0.1  vote.prod.lab result.prod.lab adminer.prod.lab
127.0.0.1  argocd.lab
```

---

## Prerequisites

| Tool | Version used |
|---|---|
| Docker + `kind` | kind node image Kubernetes v1.33.1 |
| `kubectl` | v1.36 |
| `helm` | v3 |
| `python3` | used by `setup-openbao.sh` to read the keys file |
| `argocd` CLI (optional) | v3.5 |

---

## First-time setup (new kind cluster)

Run every command from the repository root. Steps 2–6 install the platform once; after that ArgoCD
deploys the app.

### 1. Cluster

```bash
kind create cluster --name my-cluster
```

### 2. metrics-server (needed by the HPA)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml
# kind kubelets use self-signed certs
kubectl patch deploy metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

### 3. Envoy Gateway + shared gateway

```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.7.1 \
  -n envoy-gateway-system --create-namespace
kubectl wait -n envoy-gateway-system deploy/envoy-gateway --for=condition=Available --timeout=5m

kubectl apply -f platform/kind/gateway.yaml      # GatewayClass "eg" + Gateway "shared-gateway" (listener "http" :80)
```

### 4. External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets --version 2.12.0 \
  -n external-secrets --create-namespace
```

### 5. OpenBao

```bash
helm repo add openbao https://openbao.github.io/openbao-helm
helm install openbao openbao/openbao --version 0.30.3 -n openbao --create-namespace \
  --set server.standalone.enabled=true --set injector.enabled=false
kubectl wait -n openbao pod/openbao-0 --for=jsonpath='{.status.phase}'=Running --timeout=5m
```

The pod stays **0/1 Ready** until it is initialized and unsealed in the next step. This is expected.

### 6. Configure OpenBao (init, unseal, auth, policy, role, secrets)

```bash
DB_PASSWORD='postgres' bash openbao/setup-openbao.sh
```

The password must be `postgres` (see [Known limitations](#known-limitations--next-steps)).
If you leave out `DB_PASSWORD`, the script prompts for it.

What the script does, step by step:

| Step | Command it runs (inside `openbao-0`) | Result |
|---|---|---|
| Init | `bao operator init -key-shares=1 -key-threshold=1` | Unseal key + root token written to `~/openbao-init.json` (mode 600) |
| Unseal | `bao operator unseal <key>` | OpenBao becomes usable |
| KV engine | `bao secrets enable -path=secret kv-v2` | Secrets live under `secret/` |
| K8s auth | `bao auth enable kubernetes` + `auth/kubernetes/config` | Pods can log in with their ServiceAccount token |
| Policy | `bao policy write assign2-read` | **Read-only** on `secret/data/assign2/*` |
| Role | `bao write auth/kubernetes/role/assign2-eso-role` | Only SA `external-secrets/assign2-eso-sa` may log in, and it gets policy `assign2-read` (TTL 1h) |
| Secrets | `bao kv put secret/assign2/<env>/db` | `postgres-user` + `postgres-password` for dev, stage, prod |

The script is safe to run again: each step is skipped if it is already done.

> **Back up `~/openbao-init.json`.** Without it OpenBao cannot be unsealed and all secrets are lost.
> Never commit it (it is in `.gitignore`).

### 7. Connect ESO to OpenBao

```bash
kubectl apply -f openbao/eso-serviceaccount.yaml -f openbao/clustersecretstore.yaml
kubectl get clustersecretstore openbao-cluster-store       # STATUS Valid, READY True
```

No TokenReview ClusterRoleBinding is needed for `assign2-eso-sa`. OpenBao verifies ESO's token with
its own ServiceAccount (`openbao/openbao`), which the OpenBao chart already binds to `system:auth-delegator`.

### 8. ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.5/manifests/install.yaml
kubectl wait -n argocd deploy/argocd-server --for=condition=Available --timeout=5m
```

### 9. Deploy the app (dev, stage, prod)

```bash
kubectl apply -f argocd/
kubectl get applications -n argocd        # all three: Synced / Healthy after ~1 minute
```

ArgoCD creates the namespaces, renders `helm/assign2` with each `values-<env>.yaml`, and creates the
ExternalSecrets. ESO then pulls the DB credentials from OpenBao.

### 10. Open the app

Add the `/etc/hosts` entries above, then start the port-forwards (next section).

---

## Daily start-up (after a laptop / cluster restart)

```bash
# 1. Unseal OpenBao. It seals itself on every restart, and ESO cannot read secrets until this is done.
bash openbao/setup-openbao.sh --unseal-only

# 2. Envoy Gateway → all app URLs on :7070   (keep this terminal open)
kubectl port-forward -n envoy-gateway-system \
  svc/$(kubectl get svc -n envoy-gateway-system \
        -l gateway.envoyproxy.io/owning-gateway-name=shared-gateway -o jsonpath='{.items[0].metadata.name}') 7070:80

# 3. ArgoCD UI → https://argocd.lab:8080       (separate terminal)
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

If a port is "already in use", an old port-forward is still running: `ss -ltnp | grep 7070`, then kill that PID.

---

## Access and credentials

### ArgoCD

- URL: https://argocd.lab:8080 (self-signed certificate; accept the browser warning)
- Username: `admin`
- Initial password:

  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d; echo
  ```

  After the first login, change it (*User Info → Update Password*) and delete `argocd-initial-admin-secret`.

### Adminer (dev / stage)

| Field    | Value                                                  |
|----------|--------------------------------------------------------|
| System   | PostgreSQL                                             |
| Server   | `db` (alias) or `db-dev` / `db-stage`                  |
| Username | `postgres-user` from OpenBao (see below)               |
| Password | `postgres-password` from OpenBao (see below)           |
| Database | `postgres`                                             |

---

## OpenBao reference

### Components in the cluster

| Component | Where | Name |
|---|---|---|
| OpenBao server | ns `openbao` | StatefulSet `openbao` (pod `openbao-0`, 10Gi PVC) |
| KV v2 secrets engine | OpenBao | mount `secret/` |
| DB secrets | OpenBao | `secret/assign2/{dev,stage,prod}/db` (keys `postgres-user`, `postgres-password`) |
| Auth method | OpenBao | `kubernetes/` |
| Policy | OpenBao | `assign2-read` (read-only on `assign2/*`) |
| Role | OpenBao | `assign2-eso-role` → SA `assign2-eso-sa` in ns `external-secrets` |
| ServiceAccount | ns `external-secrets` | `assign2-eso-sa` (`openbao/eso-serviceaccount.yaml`) |
| ClusterSecretStore | cluster-wide | `openbao-cluster-store` (`openbao/clustersecretstore.yaml`) |
| ExternalSecret | ns `assign2-<env>` | `assign2-db-secret-<env>` (refresh every 1h) |
| Kubernetes Secret | ns `assign2-<env>` | `assign2-db-secret-<env>` (created and owned by ESO) |

The unseal key and root token are in `~/openbao-init.json` on the cluster owner's machine.

### Useful commands

```bash
# Load the root token into the shell (run once per terminal)
ROOT_TOKEN=$(python3 -c "import json;print(json.load(open('$HOME/openbao-init.json'))['root_token'])")

# Status: must show "Sealed false"
kubectl exec -n openbao openbao-0 -- bao status

# Unseal by hand (same thing the --unseal-only script does)
UNSEAL_KEY=$(python3 -c "import json;print(json.load(open('$HOME/openbao-init.json'))['unseal_keys_b64'][0])")
kubectl exec -n openbao openbao-0 -- bao operator unseal "$UNSEAL_KEY"

# Read a secret
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" bao kv get secret/assign2/dev/db

# Show the policy and the role
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" bao policy read assign2-read
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" bao read auth/kubernetes/role/assign2-eso-role

# Test the ESO login yourself (should list policy assign2-read)
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" bao write auth/kubernetes/login \
  role=assign2-eso-role jwt="$(kubectl create token assign2-eso-sa -n external-secrets)"

# Shell inside the pod with the root token
kubectl exec -it -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" sh
```

### Change a secret

```bash
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" \
  bao kv patch secret/assign2/dev/db postgres-password='<new>'

# ESO picks it up within 1h. To sync now:
kubectl annotate externalsecret assign2-db-secret-dev -n assign2-dev force-sync=$(date +%s) --overwrite

# Pods read env vars only at start-up, so restart the ones that use the Secret
kubectl rollout restart statefulset/postgres-dev -n assign2-dev
```

> Postgres only applies `POSTGRES_PASSWORD` when the data directory is empty (first start). For an existing
> database, also run `ALTER USER postgres PASSWORD '<new>';` inside postgres. With the current images the
> password must stay `postgres`, see the limitations below.

---

## Verification

```bash
# ArgoCD: all environments Synced / Healthy
kubectl get applications -n argocd

# OpenBao unsealed, ESO store valid, secrets synced
kubectl exec -n openbao openbao-0 -- bao status | grep Sealed
kubectl get clustersecretstore
kubectl get externalsecret -A

# DNS aliases point to the right env (run in any env)
kubectl get svc db redis -n assign2-stage

# End-to-end: cast a vote and confirm it reached postgres
curl -s -o /dev/null -w "%{http_code}\n" -b "voter_id=readme-test" -d "vote=a" http://vote.dev.lab:7070/
kubectl logs -n assign2-dev deploy/worker-dev -c worker --tail=3
kubectl exec -n assign2-dev postgres-dev-0 -- \
  psql -U postgres -d postgres -c "select vote, count(*) from votes group by vote;"

# Live cluster matches git (no manual drift)
helm template assign2-dev helm/assign2 -f helm/assign2/values-dev.yaml -n assign2-dev | kubectl diff -f -
```

The `kubectl diff` output only shows ArgoCD's `tracking-id` annotation and the HPA-owned vote `replicas`.
Anything else is drift.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Pods in `CreateContainerConfigError` | DB Secret missing | `kubectl get externalsecret -n <ns>`; if not synced, unseal OpenBao |
| `ClusterSecretStore` not Ready / ExternalSecret `SecretSyncedError` | OpenBao sealed | `bash openbao/setup-openbao.sh --unseal-only`, then force-sync (see above) |
| `openbao-0` is `0/1 Ready` | OpenBao sealed (normal after a restart) | `bash openbao/setup-openbao.sh --unseal-only` |
| `permission denied` in ESO logs | SA / role / policy mismatch | Compare `openbao/eso-serviceaccount.yaml` with role `assign2-eso-role` (`bound_service_account_*`) |
| URL returns 404 | Wrong hostname, or port-forward to the wrong service | `kubectl get httproute -A` and check `/etc/hosts` |
| Pods `FailedCreate ... exceeded quota` | ResourceQuota too small for an HPA scale-up | Raise `security.quota` in `values-<env>.yaml` and push |
| Manual change reverted | ArgoCD self-heal | Make the change in git instead |
| Result page shows no numbers | Worker cannot reach db/redis | `kubectl logs deploy/worker-<env> -c worker -n assign2-<env>` |
| `helm template` error `set global.environment` | No env values file passed | Add `-f values-<env>.yaml` |

---

## Known limitations / next steps

- **Images hardcode credentials and hosts.** The upstream `dockersamples` images use host `db` / `redis`
  and user/password `postgres` in code. That is why `dns-aliases.yaml` exists and why the OpenBao password
  must stay `postgres`. Only postgres really consumes the Secret. Build custom images that read env vars to
  allow real passwords and rotation.
- **One ClusterSecretStore, role and policy for all envs.** The policy allows reading all of `assign2/*`.
  Hardening: one store + role + policy per environment, restricted to its namespace.
- **OpenBao runs standalone with one unseal key** (lab setup). It must be unsealed by hand after every restart.
  Production would use HA (Raft) and auto-unseal.
- **The ESO ServiceAccount and ClusterSecretStore are applied by hand**, not by ArgoCD.
- **HTTP only.** There is no TLS listener on the gateway.
- **Image tags are `latest`** for the dockersamples images (no versioned tags upstream).
