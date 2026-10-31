#!/usr/bin/env bash
# Stops the containers and deletes the Fabric workspace and the service principal.
# Does not touch your capacity or your Aura instance.
. "$(dirname "$0")/lib.sh"

read -r -p "Delete Fabric workspace ${FABRIC_WORKSPACE_ID:-?} and SP ${FABRIC_SP_CLIENT_ID:-?}? [y/N] " ok
[[ "$ok" == y ]] || exit 0

log "Stopping containers"
docker compose down -v

if [[ -n "${FABRIC_WORKSPACE_ID:-}" ]]; then
  log "Deleting Fabric workspace"
  fabric DELETE "/workspaces/$FABRIC_WORKSPACE_ID" >/dev/null && set_env FABRIC_WORKSPACE_ID ""
fi
if [[ -n "${FABRIC_SP_CLIENT_ID:-}" ]]; then
  log "Deleting app registration / service principal"
  az ad app delete --id "$FABRIC_SP_CLIENT_ID" && set_env FABRIC_SP_CLIENT_ID "" && set_env FABRIC_SP_CLIENT_SECRET ""
fi

rm -rf router/keystore vg/home/secret.json vg/home/datasource.json
log "Done. Remember to pause your Fabric capacity if you don't need it."
