# Neo4j Virtual Graph + Microsoft Fabric

Two experiments:

1. **Virtual Graph over Fabric.** Query tables in a Fabric Data Warehouse with Cypher, without copying them into Neo4j. Neo4j Virtual Graph translates the Cypher to SQL and runs it in Fabric over JDBC.
2. **Composite database across AuraDB and Fabric.** A local Neo4j Enterprise instance hosts a composite database with two remote aliases: one to an AuraDB instance (native graph), one to the Virtual Graph instance (Fabric). A single Cypher query can then join both.

> **Heads-up:** Neo4j Virtual Graph is in **public preview**. The config keys used here (`internal.virtual_graph.*`) are internal and will change. Neo4j advises against using sensitive or production data with it. Aura's built-in Virtual Graph doesn't support Fabric, so this uses **self-managed Neo4j Enterprise** with the `generic` JDBC data source.

```
cypher-shell / Browser / agent
        │
        ▼
  neo4j-router  ── composite db `contracts360`
   ├── contracts360.aura   ──► AuraDB            (contracts, parties, clauses)
   └── contracts360.fabric ──► neo4j-vg          (Virtual Graph)
                                  │  generic JDBC (mssql-jdbc, Entra service principal)
                                  ▼
                              Fabric Warehouse   (suppliers, POs, invoices, payments, deliveries)
```

## TL;DR results

| | Works | Doesn't work (yet) |
|---|---|---|
| **Virtual Graph → Fabric** | Auth with a service principal, filters, aggregations, 1–2-hop patterns. Results match plain SQL. | `LIMIT`, `ORDER BY` (sent as ANSI SQL that T-SQL rejects), `IN`, `true`/`false` literals, variable-length paths, writes |
| **Composite DB** | Fabric subquery first, `collect`, then `UNWIND` it into the Aura subquery. Sort and limit in the outer query. | Passing variables *into* the Fabric subquery (correlated `CALL (x) { USE contracts360.fabric ... }`) |

Queries take about 4–9 s each on an F2 capacity, mostly Fabric's own overhead. Details are in [docs/experiment-1-virtual-graph.md](docs/experiment-1-virtual-graph.md) and [docs/experiment-2-composite.md](docs/experiment-2-composite.md).

## What you need

- **Fabric capacity:** a running capacity (F2 is plenty) in a tenant where you can create a workspace and an app registration.
- **Fabric tenant setting:** service principals must be allowed to use Fabric APIs (Admin portal → Tenant settings → Developer settings).
- **Azure CLI:** `az`, logged in with `az login`.
- **sqlcmd:** [go-sqlcmd](https://github.com/microsoft/go-sqlcmd) (`brew install sqlcmd` on macOS).
- **Docker** and **Python 3.10+**. No local Java needed, everything Java runs in containers.
- **AuraDB:** an instance for experiment 2. Any tier should do, but I haven't tried Free specifically. Keep the credentials file Aura shows you on creation.
- **Neo4j Enterprise license:** the containers run `neo4j:2026.10.1-enterprise`. You have to accept the [Neo4j license](https://neo4j.com/terms/licensing/) yourself by setting `NEO4J_ACCEPT_LICENSE_AGREEMENT` to `yes` (commercial license) or `eval` (evaluation) in `.env`.

## Try it

```bash
cp .env.example .env
```

Fill in the first block of `.env`: capacity name, two random passwords, the license setting and your Aura credentials.

```bash
scripts/01-fabric-setup.sh     # workspace, warehouse, service principal (writes IDs + secret to .env)
scripts/02-load-data.sh        # create tables and load ~8k rows of test data
scripts/03-start-vg.sh         # Neo4j Enterprise with Virtual Graph on Fabric
```

Run the experiment 1 queries. Some fail on purpose to show the preview limits:

```bash
scripts/cypher.sh vg examples/vg.cypher
```

Or open Neo4j Browser at http://localhost:17474 (user `neo4j`, password from `.env`, connect to `bolt://localhost:17687`).

Experiment 2:

```bash
scripts/04-load-aura.sh        # load the contract graph into Aura (wipes :Party/:Contract/:Clause there)
scripts/05-start-router.sh     # composite db contracts360 with aliases to Aura and neo4j-vg
scripts/cypher.sh router examples/composite.cypher
```

To get an interactive shell, run `scripts/cypher.sh vg` or `scripts/cypher.sh router`.

## Clean up

```bash
scripts/teardown.sh            # stops containers, deletes the Fabric workspace and the service principal
```

This leaves your capacity and Aura instance alone. Pause the capacity when you're done, it bills while it runs.

## How it's wired

**Test data.** `data/generate.py` builds a small "contract 360" data set from a fixed seed:
- Contracts, parties and clauses go to Aura.
- Purchase orders, invoices, payments and deliveries go to Fabric.
- `contract_id` and `supplier_id` link the two.
- About 12 % of contracts are over budget on purpose, so the cross-database queries find something.

**Fabric side.** `fabric/ddl.sql` creates the tables. Primary and foreign keys are declared `NOT ENFORCED`, which is all Fabric supports. Virtual Graph reads them through JDBC metadata to validate the mapping.

**Virtual Graph config.** It lives in `vg/home/` and is only read when Neo4j starts:

| File | What it does |
|---|---|
| `datasource.json` | `type: generic` with a `jdbc:sqlserver://…;authentication=ActiveDirectoryServicePrincipal` URL |
| `secret.json` | a `basic` secret holding the service principal's client id and secret. The generic type only accepts `anonymous` or `basic`, and with that URL the SQL Server driver uses them for Entra auth. |
| `schema.json` | maps tables to labels and FK columns to relationships. Generated by `vg/make_schema.py`. |

The only extra JAR is `mssql-jdbc`. Neo4j 2026.10 already ships `msal4j`, which the driver needs for Entra auth.

Graph model on the Fabric side:
```
(:Supplier)-[:RECEIVED]->(:PurchaseOrder)
(:Supplier)-[:ISSUED]->(:Invoice)-[:FOR_PO]->(:PurchaseOrder)
(:Payment)-[:SETTLES]->(:Invoice)
(:Delivery)-[:DELIVERS]->(:PurchaseOrder)
```

**Router.** A second, empty Enterprise instance. Its only job is to host the composite database. Remote alias credentials are encrypted with an AES key from a local keystore (`router/keystore/`, created on first run). The alias to `neo4j-vg` uses plain bolt inside the Docker network (`ssl_enforced: false`).

## Gotchas I hit

- **Mount the JDBC JAR on its own.** Mount it file by file into `/var/lib/neo4j/lib`, not over the whole folder, and not read-only, because the entrypoint `chown`s `lib/`.
- **Restart after config changes.** Virtual Graph reads its config only at boot, and Neo4j refuses to start if it can't connect to Fabric. So the capacity has to be running, and any `schema.json` change needs a restart (`scripts/03-start-vg.sh` recreates the container).
- **Case-sensitive strings.** The warehouse's default collation is `Latin1_General_100_BIN2_UTF8`, so `{status: 'paid'}` won't match `'PAID'`.
- **Aura database name.** Newer Aura instances use the instance id as user and database name, not `neo4j`. Use what's in the credentials file.

## Repo layout

```
scripts/      setup, start, query and teardown scripts (numbered in run order)
fabric/       warehouse DDL
data/         test data generator
vg/           Virtual Graph schema generator; vg/home and vg/lib get filled at runtime
aura/         Aura loader
router/       composite database + alias setup
examples/     Cypher to try
docs/         detailed findings per experiment
```

## License

MIT for the code in this repo. Neo4j Enterprise, Virtual Graph and Microsoft Fabric are covered by their own licenses and terms.
