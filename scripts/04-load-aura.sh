#!/usr/bin/env bash
# Loads the contract graph (the AuraDB half of the data set) into your Aura instance.
# Note: deletes existing :Party, :Contract and :Clause nodes in that database first.
. "$(dirname "$0")/lib.sh"

: "${AURA_URI:?set AURA_URI in .env}"
[[ -f data/out/aura.json ]] || python3 -I data/generate.py

log "Loading contract graph into $AURA_URI"
docker run --rm --env-file .env \
  -v "$ROOT/aura:/app/aura:ro" -v "$ROOT/data/out:/app/data/out:ro" -w /app \
  python:3.12-slim sh -c "pip install -q --root-user-action=ignore neo4j==5.28.2 && python -I aura/load.py"
