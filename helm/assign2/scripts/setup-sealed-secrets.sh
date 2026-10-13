#!/usr/bin/env bash
set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEALED_DIR="${CHART_DIR}/sealed-secrets"
PUBLIC_CERT_FILE="${PUBLIC_CERT_FILE:-/tmp/assign2-sealed-public.pem}"

declare -A NAMESPACE_MAP=(
  [dev]="assign2-dev"
  [stage]="assign2-stage"
  [prod]="assign2-prod"
)

declare -A DOMAIN_MAP=(
  [dev]="local"
  [stage]="stage.example.com"
  [prod]="example.com"
)

usage() {
  echo "Usage: $0 [all|dev|stage|prod]"
}

require_tools() {
  for tool in kubectl kubeseal openssl python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "Missing required tool: $tool" >&2
      exit 1
    fi
  done
}

fetch_cert() {
  kubeseal \
    --controller-name sealed-secrets-controller \
    --controller-namespace kube-system \
    --fetch-cert > "${PUBLIC_CERT_FILE}"
}

ensure_namespace() {
  local env="$1"
  local ns="${NAMESPACE_MAP[$env]}"
  kubectl get namespace "$ns" >/dev/null 2>&1 || kubectl create namespace "$ns"
}

seal_db_secret() {
  local env="$1"
  local ns="${NAMESPACE_MAP[$env]}"
  local password="assign2-${env}-db-$(date +%s)"

  kubectl create secret generic "assign2-db-secret-${env}" \
    --namespace "$ns" \
    --from-literal=postgres-password="${password}" \
    --dry-run=client -o yaml \
  | kubeseal --cert "${PUBLIC_CERT_FILE}" --format yaml \
  > "${SEALED_DIR}/${env}/db-secret.yaml"

  echo "$password"
}

seal_tls_secret() {
  local env="$1"
  local ns="${NAMESPACE_MAP[$env]}"
  local domain="${DOMAIN_MAP[$env]}"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout "${tmp_dir}/tls.key" \
    -out "${tmp_dir}/tls.crt" \
    -subj "/CN=vote.${domain}" \
    -addext "subjectAltName=DNS:vote.${domain},DNS:result.${domain},DNS:adminer.${domain}" >/dev/null 2>&1

  kubectl create secret tls "assign2-tls-${env}" \
    --namespace "$ns" \
    --cert="${tmp_dir}/tls.crt" \
    --key="${tmp_dir}/tls.key" \
    --dry-run=client -o yaml \
  | kubeseal --cert "${PUBLIC_CERT_FILE}" --format yaml \
  > "${SEALED_DIR}/${env}/tls-secret.yaml"

  rm -rf "$tmp_dir"
}

extract_value() {
  local file_path="$1"
  local key="$2"
  python3 - "$file_path" "$key" <<'PY'
import sys, yaml
path, key = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as fh:
    data = yaml.safe_load(fh) or {}
print(data.get('spec', {}).get('encryptedData', {}).get(key, ''))
PY
}

update_values_file() {
  local env="$1"
  local db_value="$2"
  local tls_crt_value="$3"
  local tls_key_value="$4"
  local values_file="${CHART_DIR}/values-${env}.yaml"

  python3 - "$values_file" "$env" "$db_value" "$tls_crt_value" "$tls_key_value" <<'PY'
import sys, yaml
values_file, env, db_value, tls_crt_value, tls_key_value = sys.argv[1:]
with open(values_file, 'r', encoding='utf-8') as fh:
    data = yaml.safe_load(fh) or {}

data['environment'] = env
data['sealedSecrets'] = {
    'enabled': True,
    'dbPassword': db_value,
    'tlsCrt': tls_crt_value,
    'tlsKey': tls_key_value,
}

with open(values_file, 'w', encoding='utf-8') as fh:
    yaml.safe_dump(data, fh, sort_keys=False, default_flow_style=False)
PY
}

generate_env() {
  local env="$1"
  mkdir -p "${SEALED_DIR}/${env}"
  ensure_namespace "$env"

  local db_password
  db_password="$(seal_db_secret "$env")"

  seal_tls_secret "$env"

  local db_encrypted tls_crt_encrypted tls_key_encrypted
  db_encrypted="$(extract_value "${SEALED_DIR}/${env}/db-secret.yaml" "postgres-password")"
  tls_crt_encrypted="$(extract_value "${SEALED_DIR}/${env}/tls-secret.yaml" "tls.crt")"
  tls_key_encrypted="$(extract_value "${SEALED_DIR}/${env}/tls-secret.yaml" "tls.key")"

  update_values_file "$env" "$db_encrypted" "$tls_crt_encrypted" "$tls_key_encrypted"
  echo "Generated sealed artifacts for ${env}"
}

main() {
  local target="${1:-all}"

  require_tools
  fetch_cert

  case "$target" in
    all)
      for env in dev stage prod; do
        generate_env "$env"
      done
      ;;
    dev|stage|prod)
      generate_env "$target"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
