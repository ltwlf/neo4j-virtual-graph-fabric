# shellcheck shell=bash disable=SC2034
# Shared helpers, sourced by the other scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ -f .env ]] || { echo "No .env found. Run: cp .env.example .env" >&2; exit 1; }
set -a; . ./.env; set +a

FABRIC_API=https://api.fabric.microsoft.com/v1
NEO4J_IMAGE=neo4j:2026.10.1-enterprise
MSSQL_JDBC_VERSION=12.10.0.jre11

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Write or replace KEY=value in .env
set_env() {
  local key=$1 value=$2
  if grep -q "^${key}=" .env; then
    python3 -I - "$key" "$value" <<'EOF'
import re, sys
key, value = sys.argv[1], sys.argv[2]
text = open(".env").read()
open(".env", "w").write(re.sub(rf"^{key}=.*$", lambda _: f"{key}={value}", text, flags=re.M))
EOF
  else
    echo "${key}=${value}" >> .env
  fi
  export "$key=$value"
}

fabric() {  # fabric METHOD PATH [JSON]
  local token
  token=$(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
  curl -sS -f -X "$1" -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    "$FABRIC_API$2" ${3:+-d "$3"}
}

fabric_status() {  # like fabric, but prints the HTTP status instead of failing on errors
  local token
  token=$(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
  curl -sS -o /dev/null -w '%{http_code}' -X "$1" -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" "$FABRIC_API$2" ${3:+-d "$3"}
}

# sqlcmd against the warehouse with your own az login
sql() {
  sqlcmd -S "$FABRIC_SQL_ENDPOINT" -d "$FABRIC_WAREHOUSE_NAME" --authentication-method ActiveDirectoryAzCli -b "$@"
}

wait_for_neo4j() {  # wait_for_neo4j CONTAINER
  log "Waiting for $1 to start"
  for _ in $(seq 1 60); do
    if docker logs "$1" 2>&1 | grep -q 'Started\.'; then return 0; fi
    if [[ "$(docker inspect -f '{{.State.Status}}' "$1")" == exited ]]; then
      docker logs "$1" 2>&1 | tail -30; die "$1 exited during startup"
    fi
    sleep 3
  done
  die "$1 did not start within 3 minutes"
}

cypher() {  # cypher CONTAINER DATABASE [cypher-shell args...]
  local container=$1 db=$2; shift 2
  docker exec -i "$container" cypher-shell -u neo4j -p "$NEO4J_PASSWORD" -d "$db" "$@"
}
