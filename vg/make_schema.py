"""Write vg/home/schema.json: the Virtual Graph mapping of the contracts_wh tables.

Graph model:
  (:Supplier)-[:RECEIVED]->(:PurchaseOrder)
  (:Supplier)-[:ISSUED]->(:Invoice)-[:FOR_PO]->(:PurchaseOrder)
  (:Payment)-[:SETTLES]->(:Invoice)
  (:Delivery)-[:DELIVERS]->(:PurchaseOrder)

Relationships are backed by the FK column in the child table, so each relationship
key is (child PK, FK column).
"""
import json
from pathlib import Path


def prop(name, typ, column=None):
    return {"name": name, "column": column or name, "type": typ}


def node(label, table, key, props):
    return {"label": label, "table": table, "properties": props, "key": [{"column": key}]}


def fk_rel(label, table, child_label, child_key, parent_label, fk, child_is_start=True):
    child = {"targetEntity": child_label, "keys": [{"nodeColumn": child_key, "relationshipColumn": child_key}]}
    parent = {"targetEntity": parent_label, "keys": [{"nodeColumn": fk, "relationshipColumn": fk}]}
    start, end = (child, parent) if child_is_start else (parent, child)
    return {"label": label, "table": table, "properties": [],
            "key": [{"column": child_key}, {"column": fk}], "start": start, "end": end}


schema = {
    "catalog": "contracts_wh",
    "schema": "dbo",
    "entities": {
        "nodes": [
            node("Supplier", "suppliers", "supplier_id", [
                prop("supplier_id", "STRING"), prop("name", "STRING"), prop("country", "STRING"),
                prop("risk_rating", "STRING"), prop("onboarded_on", "DATE")]),
            node("PurchaseOrder", "purchase_orders", "po_id", [
                prop("po_id", "STRING"), prop("contract_id", "STRING"), prop("order_date", "DATE"),
                prop("amount", "FLOAT"), prop("currency", "STRING"), prop("status", "STRING")]),
            node("Invoice", "invoices", "invoice_id", [
                prop("invoice_id", "STRING"), prop("invoice_date", "DATE"), prop("due_date", "DATE"),
                prop("amount", "FLOAT"), prop("status", "STRING")]),
            node("Payment", "payments", "payment_id", [
                prop("payment_id", "STRING"), prop("paid_on", "DATE"), prop("amount", "FLOAT"),
                prop("method", "STRING")]),
            node("Delivery", "deliveries", "delivery_id", [
                prop("delivery_id", "STRING"), prop("delivered_on", "DATE"), prop("on_time", "BOOLEAN"),
                prop("quantity", "INTEGER")]),
        ],
        "relationships": [
            fk_rel("RECEIVED", "purchase_orders", "PurchaseOrder", "po_id", "Supplier", "supplier_id",
                   child_is_start=False),
            fk_rel("ISSUED", "invoices", "Invoice", "invoice_id", "Supplier", "supplier_id",
                   child_is_start=False),
            fk_rel("FOR_PO", "invoices", "Invoice", "invoice_id", "PurchaseOrder", "po_id"),
            fk_rel("SETTLES", "payments", "Payment", "payment_id", "Invoice", "invoice_id"),
            fk_rel("DELIVERS", "deliveries", "Delivery", "delivery_id", "PurchaseOrder", "po_id"),
        ],
    },
}

out = Path(__file__).parent / "home" / "schema.json"
out.write_text(json.dumps(schema, indent=2) + "\n")
print(f"wrote {out}")
