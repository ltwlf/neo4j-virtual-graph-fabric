#!/usr/bin/env bash
# Starts a second Enterprise instance with the composite database `contracts360`,
# aliasing AuraDB and the Virtual Graph instance (experiment 2).
. "$(dirname "$0")/lib.sh"

: "${AURA_URI:?set AURA_URI in .env}"
docker ps --format '{{.Names}}' | grep -qx neo4j-vg || die "neo4j-vg is not running, run scripts/03-start-vg.sh first"

# Remote aliases store their credentials encrypted with a key from this keystore.
if [[ ! -f router/keystore/aliases.pkcs12 ]]; then
  log "Creating alias keystore"
  mkdir -p router/keystore
  docker run --rm --entrypoint keytool -v "$ROOT/router/keystore:/ks" -e KSP="$KEYSTORE_PASSWORD" "$NEO4J_IMAGE" \
    -genseckey -keyalg aes -keysize 256 -storetype pkcs12 -keystore /ks/aliases.pkcs12 \
    -alias aliases-key -storepass:env KSP
fi

mkdir -p logs/router
docker compose up -d neo4j-router
wait_for_neo4j neo4j-router

log "Creating composite database and aliases"
params=$(python3 -I -c "
import json, os
p = {'auraUri': os.environ['AURA_URI'], 'auraDb': os.environ.get('AURA_DATABASE') or 'neo4j',
     'auraUser': os.environ['AURA_USER'], 'auraPassword': os.environ['AURA_PASSWORD'],
     'vgPassword': os.environ['NEO4J_PASSWORD']}
print('{' + ', '.join(f'{k}: {json.dumps(v)}' for k, v in p.items()) + '}')")
cypher neo4j-router system --format plain -P "$params" < router/init.cypher

log "Router is up: http://localhost:${ROUTER_HTTP_PORT:-27474} (bolt://localhost:${ROUTER_BOLT_PORT:-27687}), database contracts360"
