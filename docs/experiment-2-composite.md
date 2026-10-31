# Experiment 2: Composite database across AuraDB and Fabric

Both local instances run `neo4j:2026.10.1-enterprise`. The Aura side is a regular AuraDB instance.

## Setup

```
neo4j-router  (bolt://localhost:27687)
  composite db contracts360
  ├── contracts360.aura   → neo4j+s://<instance>.databases.neo4j.io
  └── contracts360.fabric → neo4j://neo4j-vg:7687 (ssl_enforced: false)
                               └── Virtual Graph → JDBC → Fabric warehouse
```

- Neo4j recommends running Virtual Graph in its own installation, so there are two containers. `neo4j-vg` serves the virtual graph. `neo4j-router` hosts the composite database.
- **Remote aliases** need a keystore with an AES key on the router. Aura itself needs no configuration.
- **Aura's data** is loaded by `aura/load.py`: 133 parties, 300 contracts, 1057 clauses, plus `AMENDS` and `SUBSIDIARY_OF` relationships.
- **No ODBC anywhere.** The router talks Bolt to both sides. Only `neo4j-vg` talks JDBC to Fabric.

## Query results

| Query | Result |
|---|---|
| `USE contracts360.aura` count | works, ~6.7 s |
| `USE contracts360.fabric` count | works, ~7.5 s |
| Aura → Fabric, correlated: `CALL (cid) { USE contracts360.fabric MATCH ... {contract_id: cid} ... }` | fails: `The query must start with at least one MATCH clause` |
| Same with `WHERE po.contract_id = cid` | same error |
| Fabric subquery with a scalar query parameter `$cid` | works, matches SQL |
| Fabric subquery with `WHERE ... IN $cids` | fails: `Default dialect does not support ...Expression$In` |
| Fabric → Aura: aggregate in Fabric, `collect`, `UNWIND` in Aura (over-budget contracts with high-risk clauses) | works, matches SQL, ~6.8 s |
| Fabric → Aura: disputed invoices per supplier, rolled up to parent company via `SUBSIDIARY_OF` | works, ~6.8 s |
| `ORDER BY ... LIMIT` in the outer query | works, runs on the router, so the T-SQL issue doesn't apply |

## What we learned

**It works.** A single Cypher query on the composite database combines a native graph in Aura with warehouse tables in Fabric, and the results match plain SQL.

**But only in one direction.** When a subquery imports a variable, the router sends it to the constituent with a leading `WITH $x AS x`. Virtual Graph only accepts queries that start with `MATCH`, so the Fabric subquery can't import anything. The pattern that works:

1. Run the Fabric subquery without imported variables, and aggregate there to keep rows small.
2. `collect` the result.
3. Pass the list into the Aura subquery and `UNWIND` it there.

The other direction doesn't work inside the composite: Aura picks a few contracts and Fabric fetches only their invoices. Fabric always has to compute for everything, and Aura filters afterwards. That's fine for this data set, but expensive with large tables.

**Workaround from the app side:**
1. Query Aura for the IDs.
2. Query Fabric once per ID with a scalar parameter (`WHERE po.contract_id = $cid`). `IN $list` doesn't work (see experiment 1).

**Latency** is about 6–7 s per federated query. Most of it is Fabric, plus about a second for the Aura round trip. The router adds next to nothing.

## If you put an agent on top

Tell it to:
- start every federated query with the Fabric subquery, without imported variables,
- keep `LIMIT`, `ORDER BY`, `IN`, variable-length paths and `true`/`false` out of any `USE contracts360.fabric` block,
- sort and limit in the outer query.

## Feedback for the Virtual Graph team

On top of the dialect items from experiment 1: accept the leading `WITH $x AS x` that composite databases send, so correlated subqueries into a virtual graph work.
