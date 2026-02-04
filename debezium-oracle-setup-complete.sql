-- ================================================================================
-- DEBEZIUM ORACLE CDC SETUP SCRIPT
-- Purpose: Configure Oracle database for Debezium change data capture
-- Database: ORCLCDB (CDB) with ORCLPDB1 (PDB)
-- User: c##dbzusermkr (common user for Debezium)
-- Table: DEBEZIUMMKR.PRODUCTS (test table)
-- ================================================================================

-- ================================================================================
-- STEP 1: Database Configuration (Run as SYSDBA in CDB$ROOT)
-- ================================================================================

SHOW CON_NAME;
-- Expected output: CDB$ROOT

-- 1.1 Set recovery file destination size
ALTER SYSTEM SET db_recovery_file_dest_size = 10G SCOPE=BOTH;

-- 1.2 Enable ARCHIVELOG mode if not already enabled
DECLARE
  v_log_mode VARCHAR2(12);
BEGIN
  SELECT LOG_MODE INTO v_log_mode FROM V$DATABASE;
  IF v_log_mode != 'ARCHIVELOG' THEN
    EXECUTE IMMEDIATE 'SHUTDOWN IMMEDIATE';
    EXECUTE IMMEDIATE 'STARTUP MOUNT';
    EXECUTE IMMEDIATE 'ALTER DATABASE ARCHIVELOG';
    EXECUTE IMMEDIATE 'ALTER DATABASE OPEN';
  END IF;
END;
/

-- 1.3 Verify ARCHIVELOG mode is enabled
SELECT LOG_MODE FROM V$DATABASE;
-- Expected: ARCHIVELOG

-- 1.4 Enable supplemental logging at database level (required for LogMiner)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- 1.5 Enable FORCE LOGGING mode
ALTER DATABASE FORCE LOGGING;

-- 1.6 Verify recovery parameters
SHOW PARAMETER recovery;

-- ================================================================================
-- STEP 2: Create Tablespaces
-- ================================================================================

-- 2.1 Create tablespace in CDB$ROOT
BEGIN
  EXECUTE IMMEDIATE
    'CREATE TABLESPACE LOGMINER_TBS
     DATAFILE ''/opt/oracle/oradata/ORCLCDB/logminer_tbs.dbf''
     SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -959 THEN RAISE; END IF;
    -- -959 = Tablespace does not exist (already exists, no error)
END;
/

-- 2.2 Switch to ORCLPDB1
ALTER SESSION SET CONTAINER = ORCLPDB1;
SHOW CON_NAME;
-- Expected: ORCLPDB1

-- 2.3 Create tablespace in ORCLPDB1
BEGIN
  EXECUTE IMMEDIATE
    'CREATE TABLESPACE LOGMINER_TBS
     DATAFILE ''/opt/oracle/oradata/ORCLCDB/ORCLPDB1/logminer_tbs.dbf''
     SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -959 THEN RAISE; END IF;
END;
/

-- 2.4 Verify tablespaces
SELECT TABLESPACE_NAME, STATUS FROM DBA_TABLESPACES;

-- ================================================================================
-- STEP 3: Create Common User at CDB Level
-- ================================================================================

-- 3.1 Switch to CDB$ROOT
ALTER SESSION SET CONTAINER = CDB$ROOT;
SHOW CON_NAME;

-- 3.2 Create common user (c##dbzusermkr) for Debezium connector
BEGIN
  EXECUTE IMMEDIATE '
    CREATE USER c##dbzusermkr IDENTIFIED BY dbzmkr
    DEFAULT TABLESPACE LOGMINER_TBS
    QUOTA UNLIMITED ON LOGMINER_TBS
    CONTAINER=ALL';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1920 THEN RAISE; END IF;
    -- -1920 = User already exists
END;
/

-- 3.3 Grant basic session and container privileges (CONTAINER=ALL applies to all PDBs)
GRANT CREATE SESSION TO c##dbzusermkr CONTAINER=ALL;
GRANT SET CONTAINER TO c##dbzusermkr CONTAINER=ALL;

-- 3.4 Grant table creation and tablespace privileges
GRANT CREATE TABLE TO c##dbzusermkr CONTAINER=ALL;
GRANT UNLIMITED TABLESPACE TO c##dbzusermkr CONTAINER=ALL;

-- 3.5 Grant LogMiner-specific privileges at CDB level
GRANT SELECT ANY DICTIONARY TO c##dbzusermkr CONTAINER=ALL;
GRANT SELECT ANY TRANSACTION TO c##dbzusermkr CONTAINER=ALL;
GRANT LOGMINING TO c##dbzusermkr CONTAINER=ALL;
GRANT EXECUTE ON DBMS_LOGMNR TO c##dbzusermkr CONTAINER=ALL;
GRANT EXECUTE ON DBMS_LOGMNR_D TO c##dbzusermkr CONTAINER=ALL;

-- 3.6 Grant catalog roles at CDB level
GRANT SELECT_CATALOG_ROLE TO c##dbzusermkr CONTAINER=ALL;
GRANT EXECUTE_CATALOG_ROLE TO c##dbzusermkr CONTAINER=ALL;

-- ================================================================================
-- STEP 4: Create Local User in ORCLPDB1
-- ================================================================================

-- 4.1 Switch to ORCLPDB1
ALTER SESSION SET CONTAINER = ORCLPDB1;
SHOW CON_NAME;
-- Expected: ORCLPDB1

-- 4.2 Create local user (debeziummkr) for table ownership
BEGIN
  EXECUTE IMMEDIATE 'CREATE USER debeziummkr IDENTIFIED BY dbzmkr';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1920 THEN RAISE; END IF;
    -- -1920 = User already exists
END;
/

-- 4.3 Grant basic privileges to local user
GRANT CREATE SESSION TO debeziummkr;
GRANT CREATE TABLE TO debeziummkr;
GRANT CREATE SEQUENCE TO debeziummkr;
ALTER USER debeziummkr QUOTA 100M ON users;

-- ================================================================================
-- STEP 5: Create Test Table and Enable Supplemental Logging
-- ================================================================================

-- 5.1 Create PRODUCTS table owned by debeziummkr
BEGIN
  EXECUTE IMMEDIATE '
    CREATE TABLE debeziummkr.products (
      id NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
      name VARCHAR2(255),
      description VARCHAR2(512),
      weight FLOAT
    )';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -955 THEN RAISE; END IF;
    -- -955 = Table already exists
END;
/

-- 5.2 Enable supplemental logging on the table (required for CDC)
ALTER TABLE debeziummkr.products ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- 5.3 Insert test data
INSERT INTO debeziummkr.products (name, description, weight)
VALUES ('scooter','Small 2-wheel scooter',3.14);

COMMIT;

-- ================================================================================
-- STEP 6: Grant Permissions to Debezium User (c##dbzusermkr)
-- ================================================================================

-- 6.1 Grant table access
GRANT SELECT ON debeziummkr.products TO c##dbzusermkr;
GRANT FLASHBACK ON debeziummkr.products TO c##dbzusermkr;

-- 6.2 Grant LogMiner view access (required for logminer adapter)
GRANT SELECT ON V_$DATABASE TO c##dbzusermkr;
GRANT SELECT ON V_$LOGFILE TO c##dbzusermkr;
GRANT SELECT ON V_$LOG TO c##dbzusermkr;
GRANT SELECT ON V_$ARCHIVED_LOG TO c##dbzusermkr;
GRANT SELECT ON V_$LOGMNR_CONTENTS TO c##dbzusermkr;
GRANT SELECT ON V_$LOGMNR_LOGS TO c##dbzusermkr;
GRANT SELECT ON V_$LOGMNR_PARAMETERS TO c##dbzusermkr;

-- ================================================================================
-- STEP 7: Verification Commands
-- ================================================================================

-- 7.1 Verify current container
SHOW CON_NAME;

-- 7.2 Verify local user exists
SELECT USERNAME FROM ALL_USERS WHERE USERNAME = 'DEBEZIUMMKR';

-- 7.3 Verify table exists
SELECT OWNER, TABLE_NAME FROM ALL_TABLES 
WHERE UPPER(OWNER) = 'DEBEZIUMMKR' 
AND UPPER(TABLE_NAME) = 'PRODUCTS';

-- 7.4 View table data
SELECT * FROM debeziummkr.products;

-- ================================================================================
-- STEP 8: Insert Additional Test Data for CDC Testing
-- ================================================================================

INSERT INTO debeziummkr.products (name, description, weight)
VALUES ('IWatch','Smart Watch',10.45);

INSERT INTO debeziummkr.products (name, description, weight)
VALUES ('Headphones','Wireless Headphones',0.25);

COMMIT;

-- Verify data
SELECT * FROM debeziummkr.products;

-- ================================================================================
-- NEXT STEPS: Register Debezium Connector
-- ================================================================================
-- Once database setup is complete, register the Oracle connector with:
--
-- Endpoint: POST http://kafka-connect-url:8083/connectors
--
-- Config:
-- {
--   "name": "oracle-connector-debezium",
--   "config": {
--     "connector.class": "io.debezium.connector.oracle.OracleConnector",
--     "decimal.handling.mode": "string",
--     "database.hostname": "oracle-host",
--     "database.port": "1521",
--     "database.user": "c##dbzusermkr",
--     "database.password": "dbzmkr",
--     "database.dbname": "ORCLCDB",
--     "database.pdb.name": "ORCLPDB1",
--     "database.connection.adapter": "logminer",
--     "topic.prefix": "oracle-debezium",
--     "tasks.max": "1",
--     "schema.include.list": "DEBEZIUMMKR",
--     "table.include.list": "DEBEZIUMMKR.PRODUCTS",
--     "database.tablename.case.insensitive": "true",
--     "snapshot.mode": "initial",
--     "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
--     "schema.history.internal.kafka.topic": "dbhistory.oracle",
--     "key.converter": "io.confluent.connect.avro.AvroConverter",
--     "value.converter": "io.confluent.connect.avro.AvroConverter",
--     "key.converter.schema.registry.url": "http://schema-registry:8081",
--     "value.converter.schema.registry.url": "http://schema-registry:8081",
--     "transforms": "unwrap",
--     "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
--     "transforms.unwrap.drop.tombstones": "false",
--     "transforms.unwrap.delete.handling.mode": "rewrite"
--   }
-- }
--
-- ================================================================================
