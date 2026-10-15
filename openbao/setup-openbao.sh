#!/usr/bin/env bash
# One-time OpenBao setup for Assign2 (lab: 1 key share).
#   1. init (only if not initialized) → keys saved to ~/openbao-init.json (chmod 600, outside git)
#   2. unseal (also run this script again after every cluster restart)
#   3. KV v2 at secret/, Kubernetes auth, policy + role for ESO
#   4. write DB credentials for dev/stage/prod (password from $DB_PASSWORD or prompt, never stored in git)
set -euo pipefail

NS=openbao
POD=openbao-0
INIT_FILE="${OPENBAO_INIT_FILE:-$HOME/openbao-init.json}"   # override per cluster, e.g. ~/openbao-init-oke.json
bao()    { kubectl exec    -n "$NS" "$POD" -- env BAO_TOKEN="${ROOT_TOKEN:-}" bao "$@"; }
bao_in() { kubectl exec -i -n "$NS" "$POD" -- env BAO_TOKEN="${ROOT_TOKEN:-}" bao "$@"; }   # reads stdin
json() { python3 -c "import json,sys;print(json.load(open('$INIT_FILE'))$1)"; }

status() { bao status -format=json 2>/dev/null || true; }   # exits 2 while sealed

# 1. init
if status | grep -q '"initialized": false'; then
  echo ">> Initializing OpenBao"
  (umask 077; bao operator init -key-shares=1 -key-threshold=1 -format=json > "$INIT_FILE")
  echo ">> Keys saved to $INIT_FILE — back this file up, it cannot be recovered"
fi

# 2. unseal
if status | grep -q '"sealed": true'; then
  echo ">> Unsealing"
  bao operator unseal "$(json '["unseal_keys_b64"][0]')" >/dev/null
fi
ROOT_TOKEN="$(json '["root_token"]')"
[[ "${1:-}" == "--unseal-only" ]] && { echo ">> Unsealed"; exit 0; }

# 3. KV v2 + Kubernetes auth + policy + role
bao secrets list | grep -q '^secret/' || bao secrets enable -path=secret kv-v2
bao auth list | grep -q '^kubernetes/' || bao auth enable kubernetes
bao write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc:443"

bao_in policy write assign2-read - <<'EOF'
path "secret/data/assign2/*"     { capabilities = ["read"] }
path "secret/metadata/assign2/*" { capabilities = ["read", "list"] }
EOF

bao write auth/kubernetes/role/assign2-eso-role \
  bound_service_account_names=assign2-eso-sa \
  bound_service_account_namespaces=external-secrets \
  policies=assign2-read ttl=1h

# 4. DB credentials per environment (worker/result images hardcode user+password "postgres")
if [[ -z "${DB_PASSWORD:-}" ]]; then
  read -rsp "Postgres password to store (images expect 'postgres'): " DB_PASSWORD; echo
fi
for env in dev stage prod; do
  bao kv put "secret/assign2/$env/db" postgres-user=postgres postgres-password="$DB_PASSWORD" >/dev/null
  echo ">> wrote secret/assign2/$env/db"
done
echo ">> Done"
