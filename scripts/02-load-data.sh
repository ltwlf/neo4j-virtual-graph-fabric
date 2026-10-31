#!/usr/bin/env bash
# Generates the test data set and loads the tables into the Fabric warehouse.
. "$(dirname "$0")/lib.sh"

command -v sqlcmd >/dev/null || die "sqlcmd not found. Install go-sqlcmd: brew install sqlcmd"

log "Generating data"
python3 -I data/generate.py

log "Creating tables"
sql -i fabric/ddl.sql >/dev/null

log "Loading rows (~15 s)"
sql -i data/out/fabric_load.sql >/dev/null

log "Checking access as the service principal"
sqlcmd -S "$FABRIC_SQL_ENDPOINT" -d "$FABRIC_WAREHOUSE_NAME" -b -W \
  --authentication-method ActiveDirectoryServicePrincipal -U "$FABRIC_SP_CLIENT_ID" -P "$FABRIC_SP_CLIENT_SECRET" \
  -Q "SET NOCOUNT ON;
      SELECT 'suppliers' AS tbl, COUNT(*) AS n FROM dbo.suppliers
      UNION ALL SELECT 'purchase_orders', COUNT(*) FROM dbo.purchase_orders
      UNION ALL SELECT 'invoices', COUNT(*) FROM dbo.invoices
      UNION ALL SELECT 'payments', COUNT(*) FROM dbo.payments
      UNION ALL SELECT 'deliveries', COUNT(*) FROM dbo.deliveries"
