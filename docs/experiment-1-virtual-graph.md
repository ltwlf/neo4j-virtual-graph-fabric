# Experiment 1: Virtual Graph over a Fabric warehouse

Tested with `neo4j:2026.10.1-enterprise`, `mssql-jdbc 12.10.0.jre11` and a Fabric Data Warehouse on an F2 capacity. Virtual Graph is in public preview, so expect this to change.

## Setup

- **Data source.** Virtual Graph has no Fabric or SQL Server data source type, so this uses `generic`. The driver is picked from the JDBC URL subprotocol (`jdbc:sqlserver:`), so it just has to be on the classpath.
- **Auth.** The `generic` type only takes `anonymous` or `basic` secrets. Fabric only does Entra auth. It still fits: put `authentication=ActiveDirectoryServicePrincipal` in the URL and the SP client id and secret in the `basic` secret. The SQL Server driver does the rest.
- **JARs.** Only `mssql-jdbc` was needed. Neo4j 2026.10 already ships `msal4j`, which the driver uses for Entra auth.
- **Startup.** Neo4j opened the first Fabric connection in about 5 s and logged `Default graph-engine database 'neo4j' is created`. The virtual graph shows up as the `neo4j` database.

## Query results

| Query | Result |
|---|---|
| `MATCH (s:Supplier) RETURN count(s)` | works, 8.7 s cold |
| Filter + `count`/`sum` on invoices | works, ~7.7 s |
| 2 hops `(Payment)-[:SETTLES]->(Invoice)-[:FOR_PO]->(PurchaseOrder {contract_id: ...})` + sum | works, same numbers as plain SQL, ~5.3 s |
| Mixed directions `(Supplier)-[:RECEIVED]->(PO)<-[:FOR_PO]-(Invoice)` + grouping | works, ~4.9 s |
| `... RETURN ... LIMIT 5` | fails in Fabric: `Incorrect syntax near 'LIMIT'` |
| `ORDER BY ... LIMIT` / `SKIP` | fails in Fabric: `Incorrect syntax near 'NULLS'` |
| `WHERE d.on_time = false` on a `BIT` column | fails in Fabric: `Invalid column name 'false'` |
| `WHERE d.on_time = 0` | works |
| `WHERE x IN $list` | fails in Neo4j: `Default dialect does not support ...Expression$In` |
| Variable-length `-[*1..2]-` | fails in Neo4j: `Unsupported var-length relationship` |
| `CREATE ...` | fails, Virtual Graph is read-only |
| `collect` → `UNWIND` → `ORDER BY ... LIMIT` | works, sorting happens in Neo4j |

## What we learned

**The basics work end to end.** Auth, metadata, pattern matching, joins and aggregation pushdown all work, and the numbers match plain SQL.

**The dialect is the problem.** The `generic` type always uses the `Default` dialect, which writes ANSI/Postgres-style SQL. T-SQL rejects three things in it:
- `LIMIT` / `OFFSET`. T-SQL wants `TOP n` or `OFFSET ... ROWS FETCH NEXT ... ROWS ONLY`.
- `NULLS LAST` / `NULLS FIRST`, which T-SQL doesn't have.
- `TRUE` / `FALSE` literals. T-SQL uses `1` / `0` on `BIT` columns.

`IN` isn't supported by the `Default` dialect at all. All of this would apply to any SQL Server-family source: SQL Server, Azure SQL, Synapse, Fabric.

**Workarounds for now:**
- Sort and limit in Neo4j after `collect`/`UNWIND`.
- Compare `BIT` columns to `0`/`1`.
- Avoid `IN`.

That's fine for hand-written queries. It's a real problem for agents and LLM-generated Cypher, which add `LIMIT` to almost everything.

**Latency.** 4–9 s per query on F2. Most of it is Fabric: trivial queries sent directly with `sqlcmd` take about 4 s on the warehouse side too. That's fine for batch jobs, analytics and GraphRAG-style enrichment, not for interactive traversals. This matches how Neo4j positions Virtual Graph.

## Feedback for the Virtual Graph team

1. A SQL Server / T-SQL dialect, or a way to pick the dialect for `generic`.
2. `IN` support in the `Default` dialect. It's plain ANSI SQL.
3. Variable-length relationships.

## Not done yet

- Capture the exact SQL that Virtual Graph sends. Fabric logs it in `queryinsights.exec_requests_history` with a delay of roughly 15 min. This would be useful for a bug report.
- Try the `duckdb` data source type over the same data as Delta tables in a Fabric Lakehouse (OneLake). That would give a proper dialect while the data stays in Fabric.
