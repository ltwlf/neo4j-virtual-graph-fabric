// Queries against the Virtual Graph instance (database `neo4j` on neo4j-vg).
// Run with: scripts/cypher.sh vg examples/vg.cypher
// Every query is translated to SQL and runs in the Fabric warehouse. Expect a few seconds each.

// --- these work -------------------------------------------------------------

// How many suppliers are there?
MATCH (s:Supplier) RETURN count(s) AS suppliers;

// Disputed invoices: count and total amount
MATCH (i:Invoice) WHERE i.status = 'DISPUTED'
RETURN count(i) AS disputed, round(sum(i.amount)) AS amount;

// Two hops: payments -> invoices -> purchase orders of one contract
MATCH (p:Payment)-[:SETTLES]->(:Invoice)-[:FOR_PO]->(po:PurchaseOrder {contract_id: 'C-0163'})
RETURN count(p) AS payments, round(sum(p.amount)) AS paid;

// Mixed directions plus grouping
MATCH (s:Supplier {supplier_id: 'S-0001'})-[:RECEIVED]->(po:PurchaseOrder)<-[:FOR_PO]-(i:Invoice)
RETURN po.po_id, count(i) AS invoices;

// Late deliveries. Compare BIT columns with 0/1, not false/true.
MATCH (d:Delivery)-[:DELIVERS]->(po:PurchaseOrder) WHERE d.on_time = 0
RETURN count(d) AS late, count(DISTINCT po) AS affected_pos;

// Top suppliers by invoice count. Sorting and limiting happen in Neo4j after collect/UNWIND,
// because ORDER BY / LIMIT pushed to Fabric fail (see below).
MATCH (s:Supplier)-[:ISSUED]->(i:Invoice)
WITH s.name AS name, count(i) AS invoices
WITH collect({name: name, invoices: invoices}) AS rows
UNWIND rows AS r
RETURN r.name AS supplier, r.invoices AS invoices ORDER BY invoices DESC LIMIT 3;

// --- these fail in the current preview ----------------------------------------

// LIMIT is sent to Fabric as-is: "Incorrect syntax near 'LIMIT'"
MATCH (s:Supplier) RETURN s.name LIMIT 5;

// ORDER BY is sent with NULLS LAST: "Incorrect syntax near 'NULLS'"
MATCH (po:PurchaseOrder) RETURN po.po_id ORDER BY po.order_date DESC SKIP 10 LIMIT 3;

// Boolean literal: "Invalid column name 'false'"
MATCH (d:Delivery) WHERE d.on_time = false RETURN count(d);

// Variable-length paths aren't supported by Virtual Graph
MATCH p = (:Supplier {supplier_id: 'S-0001'})-[*1..2]-() RETURN count(p);
