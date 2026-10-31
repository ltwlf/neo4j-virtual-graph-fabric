// Run by scripts/05-start-router.sh against the `system` database of neo4j-router, with params:
//   :param auraUri, auraDb, auraUser, auraPassword, vgPassword
CREATE COMPOSITE DATABASE contracts360 IF NOT EXISTS WAIT;

// Constituent 1: AuraDB, native contract graph
CREATE OR REPLACE ALIAS contracts360.aura
  FOR DATABASE $auraDb AT $auraUri
  USER $auraUser PASSWORD $auraPassword;

// Constituent 2: neo4j-vg, Virtual Graph over Fabric Warehouse.
// Plain bolt inside the compose network, so TLS enforcement is off for this alias only.
CREATE OR REPLACE ALIAS contracts360.fabric
  FOR DATABASE neo4j AT 'neo4j://neo4j-vg:7687'
  USER neo4j PASSWORD $vgPassword
  DRIVER { ssl_enforced: false };

SHOW ALIASES FOR DATABASE;
