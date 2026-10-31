"""Generate the Contract 360 test data set with a fixed seed.

Writes to data/out/:
  fabric_load.sql  - INSERT batches for the Fabric Warehouse tables
  aura.json        - parties, contracts and clauses for the AuraDB graph (Phase 3)

Both halves share contract_id / supplier_id so the composite query can join them.
"""
import json
import random
from datetime import date, timedelta
from decimal import Decimal
from pathlib import Path

SEED = 42
N_SUPPLIERS = 120
N_CONTRACTS = 300
OUT = Path(__file__).parent / "out"

rnd = random.Random(SEED)

COUNTRIES = ["DE", "AT", "CH", "NL", "FR", "PL", "CZ", "IT", "US", "GB"]
NAME_A = ["Nord", "Alpen", "Rhein", "Elbe", "Donau", "Kraft", "Stahl", "Licht", "Blau", "Funk"]
NAME_B = ["Logistik", "Technik", "Systeme", "Werke", "Bau", "Energie", "Daten", "Chemie", "Metall", "Service"]
NAME_C = ["GmbH", "AG", "KG", "SE", "B.V.", "s.r.o.", "S.A.", "Ltd", "Inc"]
CLAUSE_TYPES = ["LIABILITY_CAP", "TERMINATION", "PRICE_ESCALATION", "SLA", "CONFIDENTIALITY",
                "GOVERNING_LAW", "FORCE_MAJEURE", "AUDIT_RIGHTS", "EXCLUSIVITY"]
CATEGORIES = ["IT Services", "Raw Materials", "Logistics", "Facility", "Consulting", "Energy"]


def d(start: date, max_days: int) -> date:
    return start + timedelta(days=rnd.randint(0, max_days))


def money(lo: int, hi: int) -> Decimal:
    return Decimal(rnd.randint(lo * 100, hi * 100)) / 100


# --- suppliers / parties ------------------------------------------------------
suppliers = []
for i in range(1, N_SUPPLIERS + 1):
    suppliers.append({
        "supplier_id": f"S-{i:04d}",
        "name": f"{rnd.choice(NAME_A)}{rnd.choice(NAME_B)} {rnd.choice(NAME_C)}",
        "country": rnd.choice(COUNTRIES),
        "risk_rating": rnd.choices(["LOW", "MEDIUM", "HIGH"], [6, 3, 1])[0],
        "onboarded_on": d(date(2015, 1, 1), 3000),
    })

# a few corporate groups: parent parties that own several suppliers (graph-only)
groups = [{"party_id": f"G-{i:03d}", "name": f"{rnd.choice(NAME_A)} Holding {rnd.choice(NAME_C)}"} for i in range(1, 11)]
subsidiary_of = [{"child": s["supplier_id"], "parent": rnd.choice(groups)["party_id"]}
                 for s in suppliers if rnd.random() < 0.4]

buyers = [{"party_id": f"B-{i:02d}", "name": n} for i, n in enumerate(
    ["Contoso Buyer DE", "Contoso Buyer AT", "Contoso Buyer CH"], start=1)]

# --- contracts (graph-only master data, value is the budget) -------------------
contracts, clauses, amends = [], [], []
for i in range(1, N_CONTRACTS + 1):
    start = d(date(2022, 1, 1), 1200)
    c = {
        "contract_id": f"C-{i:04d}",
        "title": f"{rnd.choice(CATEGORIES)} agreement {i}",
        "category": rnd.choice(CATEGORIES),
        "value": float(money(20_000, 2_000_000)),
        "currency": "EUR",
        "start_date": start.isoformat(),
        "end_date": (start + timedelta(days=rnd.choice([365, 730, 1095]))).isoformat(),
        "supplier_id": rnd.choice(suppliers)["supplier_id"],
        "buyer_id": rnd.choice(buyers)["party_id"],
    }
    contracts.append(c)
    for j, ct in enumerate(rnd.sample(CLAUSE_TYPES, rnd.randint(2, 5)), start=1):
        clauses.append({"clause_id": f"{c['contract_id']}-K{j}", "contract_id": c["contract_id"], "type": ct,
                        "risk": rnd.choices(["LOW", "MEDIUM", "HIGH"], [5, 3, 2])[0]})
    if i > 20 and rnd.random() < 0.08:
        amends.append({"contract_id": c["contract_id"], "amends": f"C-{rnd.randint(1, i - 1):04d}"})

# --- Fabric operational tables ---------------------------------------------------
pos, invoices, payments, deliveries = [], [], [], []
po_n = inv_n = pay_n = del_n = 0
for c in contracts:
    # a slice of contracts gets "overspent" on purpose so burn-rate queries find something
    target_burn = rnd.uniform(1.05, 1.4) if rnd.random() < 0.12 else rnd.uniform(0.1, 0.95)
    budget = Decimal(str(c["value"])) * Decimal(str(round(target_burn, 3)))
    n_pos = rnd.randint(1, 8)
    start = date.fromisoformat(c["start_date"])
    for _ in range(n_pos):
        po_n += 1
        po_id = f"PO-{po_n:06d}"
        amount = (budget / n_pos).quantize(Decimal("0.01"))
        order_date = d(start, 300)
        pos.append({"po_id": po_id, "contract_id": c["contract_id"], "supplier_id": c["supplier_id"],
                    "order_date": order_date, "amount": amount, "currency": "EUR",
                    "status": rnd.choices(["OPEN", "CLOSED", "CANCELLED"], [3, 6, 1])[0]})
        n_inv = rnd.randint(1, 4)
        for _ in range(n_inv):
            inv_n += 1
            inv_id = f"INV-{inv_n:07d}"
            inv_date = d(order_date, 90)
            inv_amount = (amount / n_inv).quantize(Decimal("0.01"))
            status = rnd.choices(["PAID", "OPEN", "DISPUTED"], [7, 2, 1])[0]
            invoices.append({"invoice_id": inv_id, "po_id": po_id, "supplier_id": c["supplier_id"],
                             "invoice_date": inv_date, "due_date": inv_date + timedelta(days=30),
                             "amount": inv_amount, "status": status})
            if status == "PAID":
                pay_n += 1
                payments.append({"payment_id": f"PAY-{pay_n:07d}", "invoice_id": inv_id,
                                 "paid_on": d(inv_date, 45), "amount": inv_amount,
                                 "method": rnd.choice(["SEPA", "WIRE", "CARD"])})
        for _ in range(rnd.randint(0, 2)):
            del_n += 1
            deliveries.append({"delivery_id": f"DEL-{del_n:06d}", "po_id": po_id,
                               "delivered_on": d(order_date, 60), "on_time": int(rnd.random() < 0.8),
                               "quantity": rnd.randint(1, 500)})


def sql_val(v):
    if isinstance(v, str):
        return "'" + v.replace("'", "''") + "'"
    if isinstance(v, date):
        return f"'{v.isoformat()}'"
    return str(v)


def inserts(table, rows, batch=500):
    cols = list(rows[0])
    for i in range(0, len(rows), batch):
        values = ",\n".join("(" + ", ".join(sql_val(r[c]) for c in cols) + ")" for r in rows[i:i + batch])
        yield f"INSERT INTO dbo.{table} ({', '.join(cols)}) VALUES\n{values};\n"


OUT.mkdir(exist_ok=True)
with open(OUT / "fabric_load.sql", "w") as f:
    for table, rows in [("suppliers", suppliers), ("purchase_orders", pos), ("invoices", invoices),
                        ("payments", payments), ("deliveries", deliveries)]:
        for stmt in inserts(table, rows):
            f.write(stmt + "GO\n")

aura = {
    "parties": [{"party_id": s["supplier_id"], "name": s["name"], "kind": "SUPPLIER", "country": s["country"]}
                for s in suppliers]
               + [{**g, "kind": "GROUP"} for g in groups] + [{**b, "kind": "BUYER"} for b in buyers],
    "subsidiary_of": subsidiary_of,
    "contracts": contracts,
    "clauses": clauses,
    "amends": amends,
}
(OUT / "aura.json").write_text(json.dumps(aura, indent=1))

print(f"suppliers={len(suppliers)} purchase_orders={len(pos)} invoices={len(invoices)} "
      f"payments={len(payments)} deliveries={len(deliveries)} | contracts={len(contracts)} "
      f"clauses={len(clauses)} amends={len(amends)} subsidiary_of={len(subsidiary_of)}")
