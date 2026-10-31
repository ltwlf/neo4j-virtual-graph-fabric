-- Contract 360: operational/financial side, lives in Fabric Warehouse `contracts_wh`.
-- Keys are declared NOT ENFORCED so Virtual Graph can read PK/FK metadata via JDBC.

DROP TABLE IF EXISTS dbo.payments;
DROP TABLE IF EXISTS dbo.deliveries;
DROP TABLE IF EXISTS dbo.invoices;
DROP TABLE IF EXISTS dbo.purchase_orders;
DROP TABLE IF EXISTS dbo.suppliers;

CREATE TABLE dbo.suppliers (
    supplier_id   VARCHAR(20)  NOT NULL,
    name          VARCHAR(200) NOT NULL,
    country       VARCHAR(2)   NOT NULL,
    risk_rating   VARCHAR(10)  NOT NULL,
    onboarded_on  DATE         NOT NULL
);
ALTER TABLE dbo.suppliers ADD CONSTRAINT pk_suppliers PRIMARY KEY NONCLUSTERED (supplier_id) NOT ENFORCED;

CREATE TABLE dbo.purchase_orders (
    po_id         VARCHAR(20)    NOT NULL,
    contract_id   VARCHAR(20)    NOT NULL,  -- joins to (:Contract {contract_id}) in Aura
    supplier_id   VARCHAR(20)    NOT NULL,
    order_date    DATE           NOT NULL,
    amount        DECIMAL(18,2)  NOT NULL,
    currency      VARCHAR(3)     NOT NULL,
    status        VARCHAR(20)    NOT NULL
);
ALTER TABLE dbo.purchase_orders ADD CONSTRAINT pk_purchase_orders PRIMARY KEY NONCLUSTERED (po_id) NOT ENFORCED;
ALTER TABLE dbo.purchase_orders ADD CONSTRAINT fk_po_supplier FOREIGN KEY (supplier_id) REFERENCES dbo.suppliers (supplier_id) NOT ENFORCED;

CREATE TABLE dbo.invoices (
    invoice_id    VARCHAR(20)    NOT NULL,
    po_id         VARCHAR(20)    NOT NULL,
    supplier_id   VARCHAR(20)    NOT NULL,
    invoice_date  DATE           NOT NULL,
    due_date      DATE           NOT NULL,
    amount        DECIMAL(18,2)  NOT NULL,
    status        VARCHAR(20)    NOT NULL
);
ALTER TABLE dbo.invoices ADD CONSTRAINT pk_invoices PRIMARY KEY NONCLUSTERED (invoice_id) NOT ENFORCED;
ALTER TABLE dbo.invoices ADD CONSTRAINT fk_invoice_po FOREIGN KEY (po_id) REFERENCES dbo.purchase_orders (po_id) NOT ENFORCED;
ALTER TABLE dbo.invoices ADD CONSTRAINT fk_invoice_supplier FOREIGN KEY (supplier_id) REFERENCES dbo.suppliers (supplier_id) NOT ENFORCED;

CREATE TABLE dbo.payments (
    payment_id    VARCHAR(20)    NOT NULL,
    invoice_id    VARCHAR(20)    NOT NULL,
    paid_on       DATE           NOT NULL,
    amount        DECIMAL(18,2)  NOT NULL,
    method        VARCHAR(20)    NOT NULL
);
ALTER TABLE dbo.payments ADD CONSTRAINT pk_payments PRIMARY KEY NONCLUSTERED (payment_id) NOT ENFORCED;
ALTER TABLE dbo.payments ADD CONSTRAINT fk_payment_invoice FOREIGN KEY (invoice_id) REFERENCES dbo.invoices (invoice_id) NOT ENFORCED;

CREATE TABLE dbo.deliveries (
    delivery_id   VARCHAR(20)    NOT NULL,
    po_id         VARCHAR(20)    NOT NULL,
    delivered_on  DATE           NOT NULL,
    on_time       BIT            NOT NULL,
    quantity      INT            NOT NULL
);
ALTER TABLE dbo.deliveries ADD CONSTRAINT pk_deliveries PRIMARY KEY NONCLUSTERED (delivery_id) NOT ENFORCED;
ALTER TABLE dbo.deliveries ADD CONSTRAINT fk_delivery_po FOREIGN KEY (po_id) REFERENCES dbo.purchase_orders (po_id) NOT ENFORCED;
