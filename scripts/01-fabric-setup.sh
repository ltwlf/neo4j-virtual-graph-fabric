#!/usr/bin/env bash
# Creates a Fabric workspace + warehouse and a service principal that Neo4j uses to connect.
# Writes the resulting IDs, endpoint and SP credentials to .env. Safe to re-run.
. "$(dirname "$0")/lib.sh"

: "${FABRIC_CAPACITY_NAME:?set FABRIC_CAPACITY_NAME in .env}"
WORKSPACE=${FABRIC_WORKSPACE_NAME:-neo4j-vg-lab}
WAREHOUSE=${FABRIC_WAREHOUSE_NAME:-contracts_wh}
SP_NAME=${FABRIC_SP_NAME:-neo4j-vg-lab-sp}

az account show -o none 2>/dev/null || die "Not logged in. Run: az login"

log "Looking up capacity $FABRIC_CAPACITY_NAME"
capacity_id=$(fabric GET /capacities | python3 -I -c "
import json, sys
caps = [c for c in json.load(sys.stdin)['value'] if c['displayName'] == '$FABRIC_CAPACITY_NAME']
if not caps: sys.exit('capacity not found')
if caps[0]['state'] != 'Active': sys.exit('capacity is ' + caps[0]['state'] + ', resume it first')
print(caps[0]['id'])")

find_id() {  # find_id PATH NAME
  fabric GET "$1" | python3 -I -c "
import json, sys
print(next((x['id'] for x in json.load(sys.stdin)['value'] if x['displayName'] == '$2'), ''))"
}

workspace_id=$(find_id /workspaces "$WORKSPACE")
if [[ -z "$workspace_id" ]]; then
  log "Creating workspace $WORKSPACE"
  workspace_id=$(fabric POST /workspaces "{\"displayName\":\"$WORKSPACE\",\"capacityId\":\"$capacity_id\"}" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["id"])')
else
  log "Workspace $WORKSPACE already exists"
fi

if [[ -z "$(find_id "/workspaces/$workspace_id/warehouses" "$WAREHOUSE")" ]]; then
  log "Creating warehouse $WAREHOUSE (takes ~30 s)"
  fabric POST "/workspaces/$workspace_id/warehouses" "{\"displayName\":\"$WAREHOUSE\"}" >/dev/null
fi
for _ in $(seq 1 30); do
  endpoint=$(fabric GET "/workspaces/$workspace_id/warehouses" | python3 -I -c "
import json, sys
w = [x for x in json.load(sys.stdin)['value'] if x['displayName'] == '$WAREHOUSE']
print(w[0]['properties'].get('connectionString') or '' if w else '')")
  [[ -n "$endpoint" ]] && break
  sleep 5
done
[[ -n "$endpoint" ]] || die "warehouse did not come up"

if [[ -z "${FABRIC_SP_CLIENT_ID:-}" ]]; then
  log "Creating service principal $SP_NAME (no Azure role assignments)"
  sp_json=$(az ad sp create-for-rbac --display-name "$SP_NAME" --years 1 -o json 2>/dev/null)
  set_env FABRIC_SP_CLIENT_ID "$(python3 -I -c 'import json,sys; print(json.load(sys.stdin)["appId"])' <<<"$sp_json")"
  set_env FABRIC_SP_CLIENT_SECRET "$(python3 -I -c 'import json,sys; print(json.load(sys.stdin)["password"])' <<<"$sp_json")"
else
  log "Reusing service principal $FABRIC_SP_CLIENT_ID from .env"
fi

log "Granting the service principal Contributor on the workspace"
sp_object_id=""
for _ in $(seq 1 12); do
  sp_object_id=$(az ad sp show --id "$FABRIC_SP_CLIENT_ID" --query id -o tsv 2>/dev/null || true)
  [[ -n "$sp_object_id" ]] && break
  sleep 5
done
[[ -n "$sp_object_id" ]] || die "service principal $FABRIC_SP_CLIENT_ID not found in Entra"

# A brand-new service principal takes a while to show up in Fabric, so retry.
status=""
for _ in $(seq 1 18); do
  status=$(fabric_status POST "/workspaces/$workspace_id/roleAssignments" \
    "{\"principal\":{\"id\":\"$sp_object_id\",\"type\":\"ServicePrincipal\"},\"role\":\"Contributor\"}")
  [[ "$status" == 20* || "$status" == 409 ]] && break
  sleep 10
done
[[ "$status" == 20* || "$status" == 409 ]] || die "could not grant workspace access (HTTP $status)"

set_env FABRIC_WORKSPACE_ID "$workspace_id"
set_env FABRIC_WAREHOUSE_NAME "$WAREHOUSE"
set_env FABRIC_SQL_ENDPOINT "$endpoint"

log "Done. Warehouse endpoint: $endpoint"
