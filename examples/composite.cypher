// Queries against the composite database `contracts360` on neo4j-router.
// Run with: scripts/cypher.sh router examples/composite.cypher
//   contracts360.aura   -> AuraDB: parties, contracts, clauses
//   contracts360.fabric -> Virtual Graph over Fabric: suppliers, POs, invoices, payments, deliveries
// The two sides share contract_id / supplier_id.

// --- these work -------------------------------------------------------------

// Each side on its own
USE contracts360.aura MATCH (c:Contract) RETURN count(c) AS contracts;
USE contracts360.fabric MATCH (po:PurchaseOrder) RETURN count(po) AS purchase_orders;

// Over-budget contracts that also have high-risk clauses.
// Fabric aggregates invoices per contract first, Aura then checks budget and clauses.
CALL () {
  USE contracts360.fabric
  MATCH (i:Invoice)-[:FOR_PO]->(po:PurchaseOrder)
  RETURN po.contract_id AS cid, sum(i.amount) AS invoiced
}
WITH collect({cid: cid, invoiced: invoiced}) AS spend
CALL (spend) {
  USE contracts360.aura
  UNWIND spend AS s
  MATCH (c:Contract {contract_id: s.cid})-[:HAS_CLAUSE]->(k:Clause {risk: 'HIGH'})
  WHERE s.invoiced > c.value
  RETURN c.contract_id AS contract, c.value AS budget, s.invoiced AS invoiced, collect(k.type) AS high_risk_clauses
}
RETURN contract, round(budget) AS budget, round(invoiced) AS invoiced,
       round(100.0 * invoiced / budget) AS burn_pct, high_risk_clauses
ORDER BY burn_pct DESC LIMIT 10;

// Disputed invoices (Fabric) rolled up to the supplier's parent company (Aura)
CALL () {
  USE contracts360.fabric
  MATCH (s:Supplier)-[:ISSUED]->(i:Invoice) WHERE i.status = 'DISPUTED'
  RETURN s.supplier_id AS sid, count(i) AS disputed, sum(i.amount) AS amount
}
WITH collect({sid: sid, disputed: disputed, amount: amount}) AS rows
CALL (rows) {
  USE contracts360.aura
  UNWIND rows AS r
  MATCH (:Party {party_id: r.sid})-[:SUBSIDIARY_OF]->(g:Party)
  RETURN g.name AS parent_company, sum(r.disputed) AS disputed, sum(r.amount) AS amount
}
RETURN parent_company, disputed, round(amount) AS disputed_eur ORDER BY disputed_eur DESC LIMIT 5;

// --- this fails in the current preview ----------------------------------------

// Aura picks the contracts, Fabric fetches only their invoices. The router sends the Fabric part as
// "WITH $cid AS cid MATCH ...", and Virtual Graph only accepts queries that start with MATCH.
CALL () {
  USE contracts360.aura
  MATCH (c:Contract {contract_id: 'C-0163'})
  RETURN c.contract_id AS cid, c.value AS budget
}
CALL (cid) {
  USE contracts360.fabric
  MATCH (i:Invoice)-[:FOR_PO]->(po:PurchaseOrder {contract_id: cid})
  RETURN sum(i.amount) AS invoiced
}
RETURN cid, budget, invoiced;
