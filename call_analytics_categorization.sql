-- =====================================================================
-- CALL ANALYTICS - CATEGORIZATION TABLES + SAMPLE DATA
-- Proposal for demo database, built on Wendy's draft model
--
-- EXISTING (not created here, assumed present):
--   INTERACTION, INTERACTION_CASE, CASE,
--   INTERACTION_TRANSCRIPT, TRANSCRIPT, TRANSCRIPT_SUMMARY,
--   TRANSCRIPT_GRIEVANCE
--
-- NEW - configuration (what taxonomies exist):
--   ANALYTIC_CATEGORY_SET
--   ANALYTIC_CATEGORY_SET_VERSION
--   ANALYTIC_CATEGORY
--   ANALYTIC_ATTRIBUTE_TYPE
--
-- NEW - routing (which taxonomy applies to which call):
--   ANALYTIC_CATEGORY_RULE
--
-- NEW - results (what got assigned):
--   TRANSCRIPT_ANALYTIC_RUN
--   TRANSCRIPT_ANALYTIC_REASON
--   TRANSCRIPT_ANALYTIC_CTG
--   TRANSCRIPT_ANALYTIC_ATTRIBUTE
--
-- Names follow Wendy's conventions (category_value, active_ind,
-- last_modified_timestamp, user_name, appl) so this reads as an
-- evolution of her diagram rather than a replacement.
-- =====================================================================


-- =====================================================================
-- SECTION 1 - CONFIGURATION
-- =====================================================================

-- ---------------------------------------------------------------------
-- ANALYTIC_CATEGORY_SET
-- A named taxonomy. This is the thing missing from the draft: it is what
-- tells us the 24 CareSource rows belong to the PCDR report and not the
-- PCIR report. Without it, categories are a flat undifferentiated pile.
-- ---------------------------------------------------------------------
CREATE TABLE analytic_category_set (
  analytic_category_set_id   NUMBER            NOT NULL,
  set_code                   VARCHAR2(50)      NOT NULL,
  set_name                   VARCHAR2(200)     NOT NULL,
  set_desc                   VARCHAR2(4000),
  -- CLIENT_SUPPLIED = client handed us the list (CareSource)
  -- CLUSTERING      = we derived it from transcript clustering
  -- MANUAL          = we wrote it by hand / anecdotal first round
  derivation_type_cd         VARCHAR2(30)      NOT NULL,
  -- 1 = flat list, 2 = category + subcategory. Lets one schema hold both
  -- the flat CareSource lists and the deeper call analysis taxonomy.
  hierarchy_depth            NUMBER(1)         DEFAULT 1 NOT NULL,
  owner_name                 VARCHAR2(100),
  active_ind                 CHAR(1)           DEFAULT 'Y' NOT NULL,
  last_modified_timestamp    TIMESTAMP         DEFAULT SYSTIMESTAMP NOT NULL,
  user_name                  VARCHAR2(100),
  appl                       VARCHAR2(50),
  CONSTRAINT pk_anlyt_ctg_set PRIMARY KEY (analytic_category_set_id),
  CONSTRAINT uk_anlyt_ctg_set_code UNIQUE (set_code),
  CONSTRAINT ck_anlyt_ctg_set_deriv
    CHECK (derivation_type_cd IN ('CLIENT_SUPPLIED','CLUSTERING','MANUAL')),
  CONSTRAINT ck_anlyt_ctg_set_active CHECK (active_ind IN ('Y','N'))
);

-- ---------------------------------------------------------------------
-- ANALYTIC_CATEGORY_SET_VERSION
-- A dated edition of a set. Quarterly clustering produces a new version;
-- CareSource adding a category next year produces a new version.
-- Assignments point at a version, so historical calls keep the exact
-- category list they were scored against. Nothing is ever backfilled.
-- ---------------------------------------------------------------------
CREATE TABLE analytic_category_set_version (
  anlyt_ctg_set_version_id   NUMBER            NOT NULL,
  analytic_category_set_id   NUMBER            NOT NULL,
  version_num                NUMBER(4)         NOT NULL,
  effective_start_date       DATE              NOT NULL,
  effective_end_date         DATE,             -- NULL = currently in force
  -- e.g. 'Q3 2026 clustering run over Apr-Jun 2026 transcripts'
  derivation_desc            VARCHAR2(4000),
  active_ind                 CHAR(1)           DEFAULT 'Y' NOT NULL,
  last_modified_timestamp    TIMESTAMP         DEFAULT SYSTIMESTAMP NOT NULL,
  user_name                  VARCHAR2(100),
  appl                       VARCHAR2(50),
  CONSTRAINT pk_anlyt_ctg_set_ver PRIMARY KEY (anlyt_ctg_set_version_id),
  CONSTRAINT fk_anlyt_ctg_set_ver_set FOREIGN KEY (analytic_category_set_id)
    REFERENCES analytic_category_set (analytic_category_set_id),
  CONSTRAINT uk_anlyt_ctg_set_ver UNIQUE (analytic_category_set_id, version_num),
  CONSTRAINT ck_anlyt_ctg_set_ver_dates
    CHECK (effective_end_date IS NULL OR effective_end_date >= effective_start_date)
);

-- ---------------------------------------------------------------------
-- ANALYTIC_CATEGORY
-- The categories themselves. Self-referencing parent handles the
-- category/subcategory case; a flat set simply has every row at level 1
-- with a null parent.
--
-- category_value is the stable code that survives across versions
-- (so 'CLAIM_STATUS' in v1 and v2 can be compared in reporting even
-- though they are different rows).
-- ---------------------------------------------------------------------
CREATE TABLE analytic_category (
  analytic_category_id       NUMBER            NOT NULL,
  anlyt_ctg_set_version_id   NUMBER            NOT NULL,
  parent_analytic_category_id NUMBER,
  category_value             VARCHAR2(100)     NOT NULL,
  category_name              VARCHAR2(200)     NOT NULL,
  category_desc              VARCHAR2(4000),   -- client-supplied definition
  category_level             NUMBER(1)         DEFAULT 1 NOT NULL,
  display_seq                NUMBER(4),
  active_ind                 CHAR(1)           DEFAULT 'Y' NOT NULL,
  last_modified_timestamp    TIMESTAMP         DEFAULT SYSTIMESTAMP NOT NULL,
  user_name                  VARCHAR2(100),
  appl                       VARCHAR2(50),
  CONSTRAINT pk_anlyt_ctg PRIMARY KEY (analytic_category_id),
  CONSTRAINT fk_anlyt_ctg_ver FOREIGN KEY (anlyt_ctg_set_version_id)
    REFERENCES analytic_category_set_version (anlyt_ctg_set_version_id),
  CONSTRAINT fk_anlyt_ctg_parent FOREIGN KEY (parent_analytic_category_id)
    REFERENCES analytic_category (analytic_category_id),
  CONSTRAINT uk_anlyt_ctg_value UNIQUE (anlyt_ctg_set_version_id, category_value)
);

-- ---------------------------------------------------------------------
-- ANALYTIC_ATTRIBUTE_TYPE
-- Answers "what extra aspect do we extract, and for which calls".
-- Procedure code matters for member coverage questions; it may be
-- meaningless for a provider claim-status call. Configuring this rather
-- than hardcoding columns means adding a new aspect is a row, not a DDL
-- change.
--
-- Scope: attach to a whole set, or narrow to a single category.
-- ---------------------------------------------------------------------
CREATE TABLE analytic_attribute_type (
  analytic_attribute_type_id NUMBER            NOT NULL,
  attribute_type_cd          VARCHAR2(50)      NOT NULL,
  attribute_name             VARCHAR2(200)     NOT NULL,
  attribute_desc             VARCHAR2(4000),
  data_type_cd               VARCHAR2(20)      DEFAULT 'STRING' NOT NULL,
  analytic_category_set_id   NUMBER,           -- applies across the set
  analytic_category_id       NUMBER,           -- or only to this category
  multi_value_ind            CHAR(1)           DEFAULT 'N' NOT NULL,
  active_ind                 CHAR(1)           DEFAULT 'Y' NOT NULL,
  last_modified_timestamp    TIMESTAMP         DEFAULT SYSTIMESTAMP NOT NULL,
  user_name                  VARCHAR2(100),
  appl                       VARCHAR2(50),
  CONSTRAINT pk_anlyt_attr_type PRIMARY KEY (analytic_attribute_type_id),
  CONSTRAINT fk_anlyt_attr_type_set FOREIGN KEY (analytic_category_set_id)
    REFERENCES analytic_category_set (analytic_category_set_id),
  CONSTRAINT fk_anlyt_attr_type_ctg FOREIGN KEY (analytic_category_id)
    REFERENCES analytic_category (analytic_category_id),
  CONSTRAINT ck_anlyt_attr_type_scope
    CHECK (analytic_category_set_id IS NOT NULL OR analytic_category_id IS NOT NULL)
);


-- =====================================================================
-- SECTION 2 - ROUTING
-- =====================================================================

-- ---------------------------------------------------------------------
-- ANALYTIC_CATEGORY_RULE
-- The piece the draft model has no home for. Given a call, this table
-- answers: which category sets do I have to run against it?
--
-- The draft put plan_acronym / client_specified_identifier on the
-- category row itself, which repeats the client on all 24 CareSource
-- rows and still cannot express "provider calls only, from these queues".
-- Pulling scope out to its own table fixes both.
--
-- NULL in a matching column means "any" (wildcard). So:
--   CareSource PCDR  -> client CARESOURCE_OH, caller PROVIDER, queue list
--   Call analysis    -> everything NULL, applies to all calls
--
-- OPEN: queue_identifier has no obvious source column in the existing
-- model. Confirm where queue lives on INTERACTION before building.
-- ---------------------------------------------------------------------
CREATE TABLE analytic_category_rule (
  analytic_category_rule_id  NUMBER            NOT NULL,
  analytic_category_set_id   NUMBER            NOT NULL,
  rule_name                  VARCHAR2(200),
  plan_acronym               VARCHAR2(30),
  client_specified_identifier    VARCHAR2(50),
  subclient_specified_identifier VARCHAR2(50),
  queue_identifier           VARCHAR2(100),
  caller_type_cd             VARCHAR2(30),     -- MEMBER / PROVIDER / AGENCY
  interaction_type_id        NUMBER,
  effective_start_date       DATE              NOT NULL,
  effective_end_date         DATE,
  active_ind                 CHAR(1)           DEFAULT 'Y' NOT NULL,
  last_modified_timestamp    TIMESTAMP         DEFAULT SYSTIMESTAMP NOT NULL,
  user_name                  VARCHAR2(100),
  appl                       VARCHAR2(50),
  CONSTRAINT pk_anlyt_ctg_rule PRIMARY KEY (analytic_category_rule_id),
  CONSTRAINT fk_anlyt_ctg_rule_set FOREIGN KEY (analytic_category_set_id)
    REFERENCES analytic_category_set (analytic_category_set_id)
);


-- =====================================================================
-- SECTION 3 - RESULTS
-- =====================================================================

-- ---------------------------------------------------------------------
-- TRANSCRIPT_ANALYTIC_RUN
-- One row per (transcript, category set version) evaluated. A CareSource
-- provider call produces TWO runs: the CareSource set and the general
-- call analysis set. This is what keeps them tellable apart.
--
-- Also records the no-match case explicitly, so "we looked and nothing
-- applied" is distinguishable from "we never processed this call".
--
-- NOTE: the draft hung CATEGORY_ASSIGNMENT off CASE. Attaching to
-- TRANSCRIPT instead, since the transcript is what is analyzed and not
-- every interaction necessarily has a case. interaction_id is carried
-- denormalized so reporting does not need the full join chain back
-- through INTERACTION_TRANSCRIPT every time. Worth confirming with Wendy.
-- ---------------------------------------------------------------------
CREATE TABLE transcript_analytic_run (
  transcript_analytic_run_id NUMBER            NOT NULL,
  transcript_id              NUMBER            NOT NULL,
  interaction_id             NUMBER,           -- denormalized for reporting
  anlyt_ctg_set_version_id   NUMBER,           -- NULL when NO_RULE_MATCH
  analytic_category_rule_id  NUMBER,           -- which rule fired
  caller_type_cd             VARCHAR2(30),     -- as resolved at run time
  -- COMPLETED / NO_RULE_MATCH / FAILED / SKIPPED
  run_status_cd              VARCHAR2(30)      NOT NULL,
  model_name                 VARCHAR2(100),
  prompt_version             VARCHAR2(50),
  ctg_detection_raw_data     CLOB,             -- raw model response
  run_timestamp              TIMESTAMP         DEFAULT SYSTIMESTAMP NOT NULL,
  last_modified_timestamp    TIMESTAMP         DEFAULT SYSTIMESTAMP NOT NULL,
  user_name                  VARCHAR2(100),
  appl                       VARCHAR2(50),
  CONSTRAINT pk_trnscr_anlyt_run PRIMARY KEY (transcript_analytic_run_id),
  CONSTRAINT fk_trnscr_anlyt_run_ver FOREIGN KEY (anlyt_ctg_set_version_id)
    REFERENCES analytic_category_set_version (anlyt_ctg_set_version_id),
  CONSTRAINT fk_trnscr_anlyt_run_rule FOREIGN KEY (analytic_category_rule_id)
    REFERENCES analytic_category_rule (analytic_category_rule_id),
  CONSTRAINT ck_trnscr_anlyt_run_status
    CHECK (run_status_cd IN ('COMPLETED','NO_RULE_MATCH','FAILED','SKIPPED'))
);

-- ---------------------------------------------------------------------
-- TRANSCRIPT_ANALYTIC_REASON
-- One row per distinct reason the caller called. The "find a dentist AND
-- is a crown covered" case produces two rows.
--
-- This is the open item (#5) held in a shape that costs nothing if the
-- requirement is dropped: a single-reason call is simply one row with
-- primary_ind = 'Y'. intent_text and friction_text sit here rather than
-- becoming a later ALTER TABLE.
-- ---------------------------------------------------------------------
CREATE TABLE transcript_analytic_reason (
  trnscr_anlyt_reason_id     NUMBER            NOT NULL,
  transcript_analytic_run_id NUMBER            NOT NULL,
  reason_seq                 NUMBER(3)         DEFAULT 1 NOT NULL,
  primary_ind                CHAR(1)           DEFAULT 'N' NOT NULL,
  -- short human-readable statement of what they wanted
  intent_text                VARCHAR2(500),
  -- what they did not know / why they had to call
  friction_text              VARCHAR2(1000),
  last_modified_timestamp    TIMESTAMP         DEFAULT SYSTIMESTAMP NOT NULL,
  user_name                  VARCHAR2(100),
  appl                       VARCHAR2(50),
  CONSTRAINT pk_trnscr_anlyt_reason PRIMARY KEY (trnscr_anlyt_reason_id),
  CONSTRAINT fk_trnscr_anlyt_reason_run FOREIGN KEY (transcript_analytic_run_id)
    REFERENCES transcript_analytic_run (transcript_analytic_run_id),
  CONSTRAINT uk_trnscr_anlyt_reason_seq
    UNIQUE (transcript_analytic_run_id, reason_seq),
  CONSTRAINT ck_trnscr_anlyt_reason_prim CHECK (primary_ind IN ('Y','N'))
);

-- ---------------------------------------------------------------------
-- TRANSCRIPT_ANALYTIC_CTG
-- The actual category assignment. Keeps Wendy's table name. Points at
-- the leaf category; the parent chain gives category/subcategory rollup
-- for free, so a flat set and a two-level set store identically.
-- ---------------------------------------------------------------------
CREATE TABLE transcript_analytic_ctg (
  transcript_analytic_ctg_id NUMBER            NOT NULL,
  trnscr_anlyt_reason_id     NUMBER            NOT NULL,
  analytic_category_id       NUMBER            NOT NULL,
  confidence_num             NUMBER(5,4),
  last_modified_timestamp    TIMESTAMP         DEFAULT SYSTIMESTAMP NOT NULL,
  user_name                  VARCHAR2(100),
  appl                       VARCHAR2(50),
  CONSTRAINT pk_trnscr_anlyt_ctg PRIMARY KEY (transcript_analytic_ctg_id),
  CONSTRAINT fk_trnscr_anlyt_ctg_reason FOREIGN KEY (trnscr_anlyt_reason_id)
    REFERENCES transcript_analytic_reason (trnscr_anlyt_reason_id),
  CONSTRAINT fk_trnscr_anlyt_ctg_ctg FOREIGN KEY (analytic_category_id)
    REFERENCES analytic_category (analytic_category_id),
  CONSTRAINT uk_trnscr_anlyt_ctg
    UNIQUE (trnscr_anlyt_reason_id, analytic_category_id)
);

-- ---------------------------------------------------------------------
-- TRANSCRIPT_ANALYTIC_ATTRIBUTE
-- The extracted detail below the category. Procedure code today; claim
-- number, provider NPI, benefit year, whatever else next. Adding one is
-- a row in ANALYTIC_ATTRIBUTE_TYPE, not a schema change.
-- ---------------------------------------------------------------------
CREATE TABLE transcript_analytic_attribute (
  trnscr_anlyt_attribute_id  NUMBER            NOT NULL,
  trnscr_anlyt_reason_id     NUMBER            NOT NULL,
  analytic_attribute_type_id NUMBER            NOT NULL,
  attribute_value            VARCHAR2(500)     NOT NULL,
  confidence_num             NUMBER(5,4),
  last_modified_timestamp    TIMESTAMP         DEFAULT SYSTIMESTAMP NOT NULL,
  user_name                  VARCHAR2(100),
  appl                       VARCHAR2(50),
  CONSTRAINT pk_trnscr_anlyt_attr PRIMARY KEY (trnscr_anlyt_attribute_id),
  CONSTRAINT fk_trnscr_anlyt_attr_reason FOREIGN KEY (trnscr_anlyt_reason_id)
    REFERENCES transcript_analytic_reason (trnscr_anlyt_reason_id),
  CONSTRAINT fk_trnscr_anlyt_attr_type FOREIGN KEY (analytic_attribute_type_id)
    REFERENCES analytic_attribute_type (analytic_attribute_type_id)
);


-- Indexes for the access paths that actually get used
CREATE INDEX ix_trnscr_anlyt_run_trnscr ON transcript_analytic_run (transcript_id);
CREATE INDEX ix_trnscr_anlyt_run_intr   ON transcript_analytic_run (interaction_id);
CREATE INDEX ix_trnscr_anlyt_run_ver    ON transcript_analytic_run (anlyt_ctg_set_version_id);
CREATE INDEX ix_anlyt_ctg_ver           ON analytic_category (anlyt_ctg_set_version_id);
CREATE INDEX ix_anlyt_ctg_parent        ON analytic_category (parent_analytic_category_id);
CREATE INDEX ix_anlyt_ctg_rule_lookup   ON analytic_category_rule
  (client_specified_identifier, caller_type_cd, active_ind);


-- =====================================================================
-- SECTION 4 - SAMPLE DATA
--
-- All values below are fabricated. No real member, provider, or call
-- content. IDs are hardcoded for readability in discussion.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4a. Category sets
-- ---------------------------------------------------------------------
INSERT INTO analytic_category_set
  (analytic_category_set_id, set_code, set_name, set_desc,
   derivation_type_cd, hierarchy_depth, owner_name, user_name, appl)
VALUES (1, 'CARESOURCE_OH_PCDR', 'CareSource Ohio - Provider Dispute Report',
  'Client-supplied categories for provider disputes. Flat list with client definitions.',
  'CLIENT_SUPPLIED', 1, 'CareSource Ohio', 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category_set
  (analytic_category_set_id, set_code, set_name, set_desc,
   derivation_type_cd, hierarchy_depth, owner_name, user_name, appl)
VALUES (2, 'CARESOURCE_OH_PCIR', 'CareSource Ohio - Provider Inquiry Report',
  'Client-supplied categories for provider inquiries. Similar to PCDR but a separate list.',
  'CLIENT_SUPPLIED', 1, 'CareSource Ohio', 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category_set
  (analytic_category_set_id, set_code, set_name, set_desc,
   derivation_type_cd, hierarchy_depth, owner_name, user_name, appl)
VALUES (3, 'CALL_ANALYSIS', 'General Call Analysis',
  'Internal taxonomy derived from quarterly clustering. Category + subcategory. Applies to all calls.',
  'CLUSTERING', 2, 'Analytics Team', 'HAROLD', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- 4b. Set versions
-- CareSource sets are on v1. Call analysis has two versions to
-- demonstrate the quarter boundary.
-- ---------------------------------------------------------------------
INSERT INTO analytic_category_set_version
  (anlyt_ctg_set_version_id, analytic_category_set_id, version_num,
   effective_start_date, effective_end_date, derivation_desc, user_name, appl)
VALUES (101, 1, 1, DATE '2026-01-01', NULL,
  'Initial list supplied by CareSource Ohio.', 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category_set_version
  (anlyt_ctg_set_version_id, analytic_category_set_id, version_num,
   effective_start_date, effective_end_date, derivation_desc, user_name, appl)
VALUES (102, 2, 1, DATE '2026-01-01', NULL,
  'Initial list supplied by CareSource Ohio.', 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category_set_version
  (anlyt_ctg_set_version_id, analytic_category_set_id, version_num,
   effective_start_date, effective_end_date, derivation_desc, user_name, appl)
VALUES (103, 3, 1, DATE '2026-04-01', DATE '2026-06-30',
  'Q2 2026 - anecdotal first round, hand-authored.', 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category_set_version
  (anlyt_ctg_set_version_id, analytic_category_set_id, version_num,
   effective_start_date, effective_end_date, derivation_desc, user_name, appl)
VALUES (104, 3, 2, DATE '2026-07-01', NULL,
  'Q3 2026 clustering run over Apr-Jun 2026 transcripts.', 'HAROLD', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- 4c. Categories - CareSource PCDR (flat, level 1, no parents)
-- Showing 4 of the ~12; real load would carry the full list.
-- ---------------------------------------------------------------------
INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1001, 101, NULL, 'CLAIM_STATUS', 'Claim Status',
  'Provider disputing the adjudicated status or outcome of a submitted claim.',
  1, 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1002, 101, NULL, 'ELIGIBILITY', 'Eligibility',
  'Dispute regarding member eligibility on the date of service.',
  1, 2, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1003, 101, NULL, 'OTHER_INSURANCE', 'Other Insurance',
  'Dispute involving coordination of benefits or other coverage on file.',
  1, 3, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1004, 101, NULL, 'PAYMENT_AMOUNT', 'Payment Amount',
  'Provider disputing the reimbursement amount applied to the claim.',
  1, 4, 'HAROLD', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- 4d. Categories - CareSource PCIR (flat, separate rows even where the
-- name matches PCDR - they are a different list under a different set)
-- ---------------------------------------------------------------------
INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1101, 102, NULL, 'CLAIM_STATUS', 'Claim Status',
  'Provider inquiring about the current status of a submitted claim.',
  1, 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1102, 102, NULL, 'BENEFIT_INQUIRY', 'Benefit Inquiry',
  'Provider inquiring about member benefit coverage prior to service.',
  1, 2, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1103, 102, NULL, 'CREDENTIALING', 'Credentialing',
  'Provider inquiring about network participation or credentialing status.',
  1, 3, 'HAROLD', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- 4e. Categories - Call Analysis v1 (Q2) - two levels
-- ---------------------------------------------------------------------
INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1201, 103, NULL, 'BENEFITS', 'Benefits',
  'Questions about what the plan covers.', 1, 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1202, 103, 1201, 'BENEFITS_COVERAGE', 'Procedure Coverage',
  'Whether a specific procedure is covered.', 2, 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1203, 103, NULL, 'PROVIDER_NETWORK', 'Provider Network',
  'Finding or verifying a participating provider.', 1, 2, 'HAROLD', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- 4f. Categories - Call Analysis v2 (Q3, post-clustering)
-- Note BENEFITS carries the same category_value across versions, so
-- reporting can roll up across the quarter boundary. WAITING_PERIOD is
-- new in v2 and has no v1 equivalent - which is exactly the trend-line
-- break Tim should be aware of.
-- ---------------------------------------------------------------------
INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1301, 104, NULL, 'BENEFITS', 'Benefits',
  'Questions about what the plan covers.', 1, 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1302, 104, 1301, 'BENEFITS_COVERAGE', 'Procedure Coverage',
  'Whether a specific procedure is covered.', 2, 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1303, 104, 1301, 'BENEFITS_WAITING_PERIOD', 'Waiting Period',
  'New in Q3 clustering: confusion about major services waiting periods.',
  2, 2, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1304, 104, NULL, 'PROVIDER_NETWORK', 'Provider Network',
  'Finding or verifying a participating provider.', 1, 2, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1305, 104, 1304, 'FIND_A_DENTIST', 'Find a Dentist',
  'Locating an in-network general or specialty dentist.', 2, 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1306, 104, NULL, 'CLAIM', 'Claim',
  'Claim status, payment, and processing questions.', 1, 3, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, display_seq, user_name, appl)
VALUES (1307, 104, 1306, 'CLAIM_STATUS', 'Claim Status',
  'Where is my claim / has it been processed.', 2, 1, 'HAROLD', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- 4g. Attribute types
-- Procedure code only matters for coverage questions in the call
-- analysis set, so it is scoped to that category. Claim number applies
-- across the whole CareSource dispute set.
-- ---------------------------------------------------------------------
INSERT INTO analytic_attribute_type (analytic_attribute_type_id,
  attribute_type_cd, attribute_name, attribute_desc, data_type_cd,
  analytic_category_set_id, analytic_category_id, multi_value_ind, user_name, appl)
VALUES (201, 'PROCEDURE_CODE', 'Procedure Code',
  'CDT code the caller asked about.', 'STRING',
  NULL, 1302, 'Y', 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_attribute_type (analytic_attribute_type_id,
  attribute_type_cd, attribute_name, attribute_desc, data_type_cd,
  analytic_category_set_id, analytic_category_id, multi_value_ind, user_name, appl)
VALUES (202, 'CLAIM_NUMBER', 'Claim Number',
  'Claim identifier referenced in a provider dispute.', 'STRING',
  1, NULL, 'N', 'HAROLD', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- 4h. Routing rules
--
-- Read these as: "run this category set against calls matching this
-- scope". NULL = any.
-- ---------------------------------------------------------------------
INSERT INTO analytic_category_rule (analytic_category_rule_id,
  analytic_category_set_id, rule_name, plan_acronym,
  client_specified_identifier, subclient_specified_identifier,
  queue_identifier, caller_type_cd, effective_start_date, user_name, appl)
VALUES (301, 1, 'CareSource OH provider dispute queue', 'CSOH',
  'CARESOURCE_OH', NULL, 'CS_OH_PROV_DISPUTE', 'PROVIDER',
  DATE '2026-01-01', 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category_rule (analytic_category_rule_id,
  analytic_category_set_id, rule_name, plan_acronym,
  client_specified_identifier, subclient_specified_identifier,
  queue_identifier, caller_type_cd, effective_start_date, user_name, appl)
VALUES (302, 2, 'CareSource OH provider inquiry queue', 'CSOH',
  'CARESOURCE_OH', NULL, 'CS_OH_PROV_INQUIRY', 'PROVIDER',
  DATE '2026-01-01', 'HAROLD', 'CALLANALYTICS');

-- Applies to every member and provider call regardless of client.
INSERT INTO analytic_category_rule (analytic_category_rule_id,
  analytic_category_set_id, rule_name, plan_acronym,
  client_specified_identifier, subclient_specified_identifier,
  queue_identifier, caller_type_cd, effective_start_date, user_name, appl)
VALUES (303, 3, 'General call analysis - member calls', NULL,
  NULL, NULL, NULL, 'MEMBER', DATE '2026-04-01', 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category_rule (analytic_category_rule_id,
  analytic_category_set_id, rule_name, plan_acronym,
  client_specified_identifier, subclient_specified_identifier,
  queue_identifier, caller_type_cd, effective_start_date, user_name, appl)
VALUES (304, 3, 'General call analysis - provider calls', NULL,
  NULL, NULL, NULL, 'PROVIDER', DATE '2026-04-01', 'HAROLD', 'CALLANALYTICS');

-- Note: no rule with caller_type_cd = 'AGENCY'. Scenario 4 relies on that.


-- =====================================================================
-- SECTION 5 - SAMPLE CALLS
--
-- Six fabricated calls. transcript_id / interaction_id values assume
-- corresponding rows exist in TRANSCRIPT and INTERACTION; adjust to real
-- demo IDs before loading, or drop the FKs for the demo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- SCENARIO 1: CareSource Ohio provider DISPUTE.
-- Gets TWO runs - the CareSource PCDR set and general call analysis.
-- This is the core case the schema has to support.
-- ---------------------------------------------------------------------
INSERT INTO transcript_analytic_run (transcript_analytic_run_id, transcript_id,
  interaction_id, anlyt_ctg_set_version_id, analytic_category_rule_id,
  caller_type_cd, run_status_cd, model_name, prompt_version,
  run_timestamp, user_name, appl)
VALUES (5001, 55101, 88101, 101, 301, 'PROVIDER', 'COMPLETED',
  'gpt-4o', 'caresource-pcdr-v3', TIMESTAMP '2026-09-02 09:14:00', 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text, friction_text,
  user_name, appl)
VALUES (6001, 5001, 1, 'Y',
  'Disputing the reimbursement amount paid on a submitted claim',
  'Did not understand how the fee schedule allowance was applied',
  'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7001, 6001, 1004, 0.9100, 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_attribute (trnscr_anlyt_attribute_id,
  trnscr_anlyt_reason_id, analytic_attribute_type_id, attribute_value,
  confidence_num, user_name, appl)
VALUES (8001, 6001, 202, 'CLM-2026-0043117', 0.9800, 'BATCH', 'CALLANALYTICS');

-- Second run on the SAME transcript: general call analysis
INSERT INTO transcript_analytic_run (transcript_analytic_run_id, transcript_id,
  interaction_id, anlyt_ctg_set_version_id, analytic_category_rule_id,
  caller_type_cd, run_status_cd, model_name, prompt_version,
  run_timestamp, user_name, appl)
VALUES (5002, 55101, 88101, 104, 304, 'PROVIDER', 'COMPLETED',
  'gpt-4o', 'call-analysis-v7', TIMESTAMP '2026-09-02 09:14:05', 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text, friction_text,
  user_name, appl)
VALUES (6002, 5002, 1, 'Y',
  'Wants to know why the claim paid less than expected',
  'Fee schedule allowance not visible in the provider portal',
  'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7002, 6002, 1307, 0.8800, 'BATCH', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- SCENARIO 2: CareSource Ohio provider INQUIRY.
-- Same shape as scenario 1 but routed to the PCIR set purely by queue.
-- No inquiry-vs-dispute classification step is needed.
-- ---------------------------------------------------------------------
INSERT INTO transcript_analytic_run (transcript_analytic_run_id, transcript_id,
  interaction_id, anlyt_ctg_set_version_id, analytic_category_rule_id,
  caller_type_cd, run_status_cd, model_name, prompt_version,
  run_timestamp, user_name, appl)
VALUES (5003, 55102, 88102, 102, 302, 'PROVIDER', 'COMPLETED',
  'gpt-4o', 'caresource-pcir-v3', TIMESTAMP '2026-09-02 10:02:00', 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text, friction_text,
  user_name, appl)
VALUES (6003, 5003, 1, 'Y',
  'Checking whether a submitted claim has been processed',
  'Portal showed no status update after two weeks',
  'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7003, 6003, 1101, 0.9400, 'BATCH', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- SCENARIO 3: Non-CareSource MEMBER call with TWO distinct reasons.
-- Find a dentist, and is a crown covered. Procedure code attaches to the
-- second reason only. This is the case that breaks any design putting
-- category columns directly on the call.
-- ---------------------------------------------------------------------
INSERT INTO transcript_analytic_run (transcript_analytic_run_id, transcript_id,
  interaction_id, anlyt_ctg_set_version_id, analytic_category_rule_id,
  caller_type_cd, run_status_cd, model_name, prompt_version,
  run_timestamp, user_name, appl)
VALUES (5004, 55103, 88103, 104, 303, 'MEMBER', 'COMPLETED',
  'gpt-4o', 'call-analysis-v7', TIMESTAMP '2026-09-02 11:20:00', 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text, friction_text,
  user_name, appl)
VALUES (6004, 5004, 1, 'N',
  'Looking for an in-network general dentist near home',
  'Did not know the provider directory existed',
  'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7004, 6004, 1305, 0.9600, 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text, friction_text,
  user_name, appl)
VALUES (6005, 5004, 2, 'Y',
  'Asking whether a crown is covered under the plan',
  'Unclear whether the major services waiting period had been met',
  'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7005, 6005, 1302, 0.9300, 'BATCH', 'CALLANALYTICS');

-- Same reason also carries the new v2 waiting-period subcategory
INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7006, 6005, 1303, 0.7700, 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_attribute (trnscr_anlyt_attribute_id,
  trnscr_anlyt_reason_id, analytic_attribute_type_id, attribute_value,
  confidence_num, user_name, appl)
VALUES (8002, 6005, 201, 'D2740', 0.9100, 'BATCH', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- SCENARIO 4: AGENCY call. No rule matches.
-- Recorded explicitly so "nothing applied" is distinguishable from
-- "never processed". Reporting can then prove coverage.
-- ---------------------------------------------------------------------
INSERT INTO transcript_analytic_run (transcript_analytic_run_id, transcript_id,
  interaction_id, anlyt_ctg_set_version_id, analytic_category_rule_id,
  caller_type_cd, run_status_cd, model_name, prompt_version,
  run_timestamp, user_name, appl)
VALUES (5005, 55104, 88104, NULL, NULL, 'AGENCY', 'NO_RULE_MATCH',
  NULL, NULL, TIMESTAMP '2026-09-02 13:45:00', 'BATCH', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- SCENARIO 5: Quarter boundary.
-- A Q2 call scored under CALL_ANALYSIS v1, and a Q3 call scored under
-- v2. Both assignments stand; nothing was reclassified. A report
-- spanning both quarters must roll up on category_value, not
-- analytic_category_id.
-- ---------------------------------------------------------------------
INSERT INTO transcript_analytic_run (transcript_analytic_run_id, transcript_id,
  interaction_id, anlyt_ctg_set_version_id, analytic_category_rule_id,
  caller_type_cd, run_status_cd, model_name, prompt_version,
  run_timestamp, user_name, appl)
VALUES (5006, 55105, 88105, 103, 303, 'MEMBER', 'COMPLETED',
  'gpt-4o', 'call-analysis-v5', TIMESTAMP '2026-05-14 08:30:00', 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text, friction_text,
  user_name, appl)
VALUES (6006, 5006, 1, 'Y',
  'Asking whether a root canal is covered',
  'Benefit summary language was ambiguous',
  'BATCH', 'CALLANALYTICS');

-- v1 category id, NOT the v2 one
INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7007, 6006, 1202, 0.8900, 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_run (transcript_analytic_run_id, transcript_id,
  interaction_id, anlyt_ctg_set_version_id, analytic_category_rule_id,
  caller_type_cd, run_status_cd, model_name, prompt_version,
  run_timestamp, user_name, appl)
VALUES (5007, 55106, 88106, 104, 303, 'MEMBER', 'COMPLETED',
  'gpt-4o', 'call-analysis-v7', TIMESTAMP '2026-08-19 15:05:00', 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text, friction_text,
  user_name, appl)
VALUES (6007, 5007, 1, 'Y',
  'Asking whether a root canal is covered',
  'Benefit summary language was ambiguous',
  'BATCH', 'CALLANALYTICS');

-- same category_value, different version, different id
INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7008, 6007, 1302, 0.9000, 'BATCH', 'CALLANALYTICS');

COMMIT;


-- =====================================================================
-- SECTION 6 - THE TESTS
--
-- Harold's proposed test: given a call, what query returns the set of
-- categorizations I have to run? If this needs hardcoded CareSource
-- logic, the model is wrong.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TEST 1: Routing. Which category sets apply to a given call?
-- Substitute the call's client / queue / caller type. Note there is no
-- client-specific logic anywhere in this query.
-- ---------------------------------------------------------------------
SELECT s.set_code,
       s.set_name,
       v.anlyt_ctg_set_version_id,
       v.version_num,
       r.rule_name
FROM   analytic_category_rule r
JOIN   analytic_category_set s
       ON s.analytic_category_set_id = r.analytic_category_set_id
JOIN   analytic_category_set_version v
       ON v.analytic_category_set_id = s.analytic_category_set_id
WHERE  r.active_ind = 'Y'
AND    s.active_ind = 'Y'
       -- call attributes
AND    (r.client_specified_identifier IS NULL
        OR r.client_specified_identifier = 'CARESOURCE_OH')
AND    (r.queue_identifier IS NULL
        OR r.queue_identifier = 'CS_OH_PROV_DISPUTE')
AND    (r.caller_type_cd IS NULL
        OR r.caller_type_cd = 'PROVIDER')
AND    (r.plan_acronym IS NULL OR r.plan_acronym = 'CSOH')
       -- date effectivity, using the call's receipt date
AND    SYSDATE BETWEEN r.effective_start_date
                   AND NVL(r.effective_end_date, DATE '9999-12-31')
AND    SYSDATE BETWEEN v.effective_start_date
                   AND NVL(v.effective_end_date, DATE '9999-12-31');
-- Expected: two rows - CARESOURCE_OH_PCDR v1 and CALL_ANALYSIS v2.


-- ---------------------------------------------------------------------
-- TEST 2: Everything assigned to one call, across all sets.
-- ---------------------------------------------------------------------
SELECT run.interaction_id,
       s.set_code,
       rsn.reason_seq,
       rsn.primary_ind,
       parent.category_name  AS category,
       c.category_name       AS subcategory,
       rsn.intent_text,
       rsn.friction_text,
       ctg.confidence_num
FROM   transcript_analytic_run run
JOIN   analytic_category_set_version v
       ON v.anlyt_ctg_set_version_id = run.anlyt_ctg_set_version_id
JOIN   analytic_category_set s
       ON s.analytic_category_set_id = v.analytic_category_set_id
JOIN   transcript_analytic_reason rsn
       ON rsn.transcript_analytic_run_id = run.transcript_analytic_run_id
JOIN   transcript_analytic_ctg ctg
       ON ctg.trnscr_anlyt_reason_id = rsn.trnscr_anlyt_reason_id
JOIN   analytic_category c
       ON c.analytic_category_id = ctg.analytic_category_id
LEFT   JOIN analytic_category parent
       ON parent.analytic_category_id = c.parent_analytic_category_id
WHERE  run.transcript_id = 55101
ORDER  BY s.set_code, rsn.reason_seq;
-- Expected: the CareSource dispute category AND the call analysis
-- category, clearly attributable to different sets.


-- ---------------------------------------------------------------------
-- TEST 3: Cross-quarter rollup. Same benefits question, two versions.
-- Grouping on category_value survives the version change; grouping on
-- analytic_category_id would split it in two.
-- ---------------------------------------------------------------------
SELECT c.category_value,
       MIN(c.category_name) AS category_name,
       COUNT(*)             AS call_cnt
FROM   transcript_analytic_run run
JOIN   transcript_analytic_reason rsn
       ON rsn.transcript_analytic_run_id = run.transcript_analytic_run_id
JOIN   transcript_analytic_ctg ctg
       ON ctg.trnscr_anlyt_reason_id = rsn.trnscr_anlyt_reason_id
JOIN   analytic_category c
       ON c.analytic_category_id = ctg.analytic_category_id
JOIN   analytic_category_set_version v
       ON v.anlyt_ctg_set_version_id = run.anlyt_ctg_set_version_id
WHERE  v.analytic_category_set_id = 3
GROUP  BY c.category_value
ORDER  BY call_cnt DESC;


-- ---------------------------------------------------------------------
-- TEST 4: Michael's question - which procedures are members asking
-- about most, for a given group?
-- ---------------------------------------------------------------------
SELECT attr.attribute_value AS procedure_code,
       COUNT(*)             AS mention_cnt
FROM   transcript_analytic_attribute attr
JOIN   analytic_attribute_type t
       ON t.analytic_attribute_type_id = attr.analytic_attribute_type_id
JOIN   transcript_analytic_reason rsn
       ON rsn.trnscr_anlyt_reason_id = attr.trnscr_anlyt_reason_id
JOIN   transcript_analytic_run run
       ON run.transcript_analytic_run_id = rsn.transcript_analytic_run_id
WHERE  t.attribute_type_cd = 'PROCEDURE_CODE'
AND    run.caller_type_cd = 'MEMBER'
GROUP  BY attr.attribute_value
ORDER  BY mention_cnt DESC;


-- ---------------------------------------------------------------------
-- TEST 5: Coverage check. Calls where nothing applied.
-- ---------------------------------------------------------------------
SELECT run_status_cd, caller_type_cd, COUNT(*)
FROM   transcript_analytic_run
GROUP  BY run_status_cd, caller_type_cd;


-- =====================================================================
-- SECTION 7 - OPEN ITEMS TO RESOLVE BEFORE THIS GOES BEYOND THE DEMO
--
-- 1. CLIENT IDENTITY. Is CareSource a payer, plan, group, or client?
--    ANALYTIC_CATEGORY_RULE currently carries plan_acronym,
--    client_specified_identifier, and subclient_specified_identifier,
--    copied from the draft's TRANSCRIPT_ANALYTIC_CTG. Probably one of
--    these is the real key and the rest should go.
--
-- 2. QUEUE. Routing depends on queue, but no queue column is visible on
--    INTERACTION. Is it source_system_identifier? interaction_type_id?
--    Somewhere else entirely? This blocks the CareSource rules.
--
-- 3. CALLER TYPE. Lives in the transcript_summary JSON as 'caller'.
--    Recommend extracting to a real column (or an indexed virtual
--    column) at ingest rather than JSON_VALUE on every routing lookup.
--    Also: is it LLM-derived or carried from telephony? And what are
--    the actual permitted values?
--
-- 4. ATTACHMENT POINT. Runs attach to TRANSCRIPT here; the draft
--    attached assignments to CASE. Needs a decision with Wendy. If a
--    case can span multiple interactions, case-level assignment loses
--    which call produced which category.
--
-- 5. MULTI-REASON / INTENT / FRICTION. Modelled but not confirmed.
--    If dropped, every run just has one reason row. If kept, this is
--    the shape. Confirm with Michael and Tim.
--
-- 6. PCDR vs PCIR LISTS. Modelled as two independent sets. If the two
--    CareSource lists turn out to be identical, collapse to one set
--    with two routing rules.
--
-- 7. PRIMARY CATEGORY. primary_ind on the reason gives Tim his single
--    top category. Confirm that is what he means, rather than a
--    separate call-level category independent of the reasons.
-- =====================================================================
