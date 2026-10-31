"""Load the graph half of Contract 360 (data/out/aura.json) into AuraDB.

  (:Party)-[:PARTY_TO {role}]->(:Contract)-[:HAS_CLAUSE]->(:Clause)
  (:Contract)-[:AMENDS]->(:Contract)
  (:Party)-[:SUBSIDIARY_OF]->(:Party)

Idempotent: wipes the Contract 360 labels first, then MERGEs everything.
Reads AURA_URI / AURA_USER / AURA_PASSWORD / AURA_DATABASE from the environment.
"""
import json
import os
import sys

from neo4j import GraphDatabase

data = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "data/out/aura.json"))
db = os.environ.get("AURA_DATABASE") or "neo4j"

STATEMENTS = [
    ("MATCH (n) WHERE n:Party OR n:Contract OR n:Clause CALL (n) { DETACH DELETE n } IN TRANSACTIONS", None),
    ("CREATE CONSTRAINT party_id IF NOT EXISTS FOR (p:Party) REQUIRE p.party_id IS UNIQUE", None),
    ("CREATE CONSTRAINT contract_id IF NOT EXISTS FOR (c:Contract) REQUIRE c.contract_id IS UNIQUE", None),
    ("CREATE CONSTRAINT clause_id IF NOT EXISTS FOR (k:Clause) REQUIRE k.clause_id IS UNIQUE", None),
    ("UNWIND $rows AS r MERGE (p:Party {party_id: r.party_id}) SET p += r", "parties"),
    ("""UNWIND $rows AS r
        MERGE (c:Contract {contract_id: r.contract_id})
        SET c.title = r.title, c.category = r.category, c.value = r.value, c.currency = r.currency,
            c.start_date = date(r.start_date), c.end_date = date(r.end_date)
        WITH c, r
        MATCH (s:Party {party_id: r.supplier_id}), (b:Party {party_id: r.buyer_id})
        MERGE (s)-[:PARTY_TO {role: 'SUPPLIER'}]->(c)
        MERGE (b)-[:PARTY_TO {role: 'BUYER'}]->(c)""", "contracts"),
    ("""UNWIND $rows AS r
        MATCH (c:Contract {contract_id: r.contract_id})
        MERGE (k:Clause {clause_id: r.clause_id}) SET k.type = r.type, k.risk = r.risk
        MERGE (c)-[:HAS_CLAUSE]->(k)""", "clauses"),
    ("""UNWIND $rows AS r
        MATCH (a:Contract {contract_id: r.contract_id}), (b:Contract {contract_id: r.amends})
        MERGE (a)-[:AMENDS]->(b)""", "amends"),
    ("""UNWIND $rows AS r
        MATCH (c:Party {party_id: r.child}), (p:Party {party_id: r.parent})
        MERGE (c)-[:SUBSIDIARY_OF]->(p)""", "subsidiary_of"),
]

with GraphDatabase.driver(os.environ["AURA_URI"], auth=(os.environ["AURA_USER"], os.environ["AURA_PASSWORD"])) as driver:
    driver.verify_connectivity()
    with driver.session(database=db) as session:
        for cypher, key in STATEMENTS:
            if key is None:
                session.run(cypher).consume()
            else:
                session.execute_write(lambda tx: tx.run(cypher, rows=data[key]).consume())
                print(f"loaded {key}: {len(data[key])}")
        counts = session.run("""
            MATCH (n) WHERE n:Party OR n:Contract OR n:Clause
            RETURN labels(n)[0] AS label, count(*) AS n ORDER BY label""").data()
        print(counts)
