#!/usr/bin/env bash
# Starts Neo4j Enterprise with Virtual Graph pointed at the Fabric warehouse (experiment 1).
. "$(dirname "$0")/lib.sh"

[[ "${NEO4J_ACCEPT_LICENSE_AGREEMENT:-}" == yes || "${NEO4J_ACCEPT_LICENSE_AGREEMENT:-}" == eval ]] ||
  die "Set NEO4J_ACCEPT_LICENSE_AGREEMENT in .env (see README, Neo4j Enterprise license)"
: "${FABRIC_SQL_ENDPOINT:?run scripts/01-fabric-setup.sh first}"

jar="vg/lib/mssql-jdbc-${MSSQL_JDBC_VERSION}.jar"
if [[ ! -f "$jar" ]]; then
  log "Downloading mssql-jdbc $MSSQL_JDBC_VERSION"
  mkdir -p vg/lib
  curl -sSfL -o "$jar" \
    "https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/${MSSQL_JDBC_VERSION}/mssql-jdbc-${MSSQL_JDBC_VERSION}.jar"
fi

log "Rendering Virtual Graph config into vg/home"
cat > vg/home/datasource.json <<EOF
{
  "type": "generic",
  "url": "jdbc:sqlserver://${FABRIC_SQL_ENDPOINT}:1433;database=${FABRIC_WAREHOUSE_NAME};encrypt=true;loginTimeout=30;authentication=ActiveDirectoryServicePrincipal",
  "additionalProperties": {
    "applicationName": "neo4j-virtual-graph",
    "hikari.maximumPoolSize": "4"
  }
}
EOF
# The SP id/secret go into a "basic" secret; the JDBC URL tells the driver to use them for Entra auth.
cat > vg/home/secret.json <<EOF
{
  "type": "basic",
  "username": "${FABRIC_SP_CLIENT_ID}",
  "password": "${FABRIC_SP_CLIENT_SECRET}"
}
EOF
python3 -I vg/make_schema.py

mkdir -p logs/vg
# --force-recreate because Virtual Graph only reads its config at boot
docker compose up -d --force-recreate neo4j-vg
wait_for_neo4j neo4j-vg
log "Virtual Graph is up: http://localhost:${VG_HTTP_PORT:-17474} (bolt://localhost:${VG_BOLT_PORT:-17687})"
