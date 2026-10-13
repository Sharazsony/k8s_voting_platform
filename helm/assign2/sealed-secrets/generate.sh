#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_FILE="${SEALED_SECRET_CERT:-/home/sharaz-sony/sealed-backup/pub-cert.pem}"
TARGET_ENV="${1:-all}"

if ! command -v kubeseal >/dev/null 2>&1; then
  echo "kubeseal is required but not installed." >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not installed." >&2
  exit 1
fi

if [[ ! -f "$CERT_FILE" ]]; then
  echo "Sealed secret public cert not found: $CERT_FILE" >&2
  exit 1
fi

declare -A NAMESPACE_MAP=(
  [dev]=assign2-dev
  [stage]=assign2-stage
  [prod]=assign2-prod
)

extract_value() {
  local file="$1"
  local key="$2"
  python3 - "$file" "$key" <<'PY'
import re, sys
path, key = sys.argv[1], sys.argv[2]
text = open(path, 'r', encoding='utf-8').read()
pattern = rf"(?ms)^\s*{re.escape(key)}:\s*(.*)$"
match = re.search(pattern, text)
if not match:
    raise SystemExit(f"field '{key}' not found in {path}")
print(match.group(1).strip())
PY
}

update_values_file() {
  local env="$1"
  local db_value="$2"
  local tls_crt_value="$3"
  local tls_key_value="$4"
  local values_file="$ROOT_DIR/values-${env}.yaml"

  python3 - "$values_file" "$db_value" "$tls_crt_value" "$tls_key_value" <<'PY'
import json, sys
from pathlib import Path
values_file = Path(sys.argv[1])
db_value = sys.argv[2]
tls_crt_value = sys.argv[3]
tls_key_value = sys.argv[4]

text = values_file.read_text(encoding='utf-8')
start = text.index('# BEGIN SEALED SECRETS')
end = text.index('# END SEALED SECRETS')
block = (
    '# BEGIN SEALED SECRETS\n'
    'security:\n'
    '  sealed:\n'
    f'    dbPassword: {json.dumps(db_value)}\n'
    'ingress:\n'
    '  sealed:\n'
    f'    tlsCrt: {json.dumps(tls_crt_value)}\n'
    f'    tlsKey: {json.dumps(tls_key_value)}\n'
    '# END SEALED SECRETS'
)
values_file.write_text(text[:start] + block + text[end + len('# END SEALED SECRETS'):], encoding='utf-8')
PY
}

generate_env() {
  local env="$1"
  local namespace="${NAMESPACE_MAP[$env]}"
  local env_dir="$ROOT_DIR/sealed-secrets/$env"
  mkdir -p "$env_dir"

  local db_password
  db_password="$(openssl rand -base64 32 | tr -d '\n' | tr '+/' '-_')"

  kubectl create secret generic "assign2-db-secret-${env}" \
    --namespace "$namespace" \
    --from-literal="postgres-password=${db_password}" \
    --dry-run=client -o yaml \
    | kubeseal --cert "$CERT_FILE" --format yaml > "$env_dir/db-secret.yaml"

  local cert_file key_file
  cert_file="$(mktemp)"
  key_file="$(mktemp)"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$key_file" \
    -out "$cert_file" \
    -subj "/CN=${env}.example.com" \
    -days 365 >/dev/null 2>&1

  kubectl create secret tls "assign2-tls-${env}" \
    --namespace "$namespace" \
    --cert "$cert_file" \
    --key "$key_file" \
    --dry-run=client -o yaml \
    | kubeseal --cert "$CERT_FILE" --format yaml > "$env_dir/tls-secret.yaml"

  rm -f "$cert_file" "$key_file"

  local db_encrypted tls_crt_encrypted tls_key_encrypted
  db_encrypted="$(extract_value "$env_dir/db-secret.yaml" 'postgres-password')"
  tls_crt_encrypted="$(extract_value "$env_dir/tls-secret.yaml" 'tls.crt')"
  tls_key_encrypted="$(extract_value "$env_dir/tls-secret.yaml" 'tls.key')"

  update_values_file "$env" "$db_encrypted" "$tls_crt_encrypted" "$tls_key_encrypted"

  echo "Generated sealed secrets for ${env} in ${env_dir}"
}

case "$TARGET_ENV" in
  all)
    for env in dev stage prod; do
      generate_env "$env"
    done
    ;;
  dev|stage|prod)
    generate_env "$TARGET_ENV"
    ;;
  *)
    echo "Usage: $0 [all|dev|stage|prod]" >&2
    exit 1
    ;;
 esac
