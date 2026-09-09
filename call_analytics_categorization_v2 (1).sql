-- =====================================================================
-- CALL ANALYTICS - CATEGORIZATION TABLES + SAMPLE DATA
-- Version 2. Built on Wendy's draft model.
--
-- CHANGES FROM V1:
--   * PCDR and PCIR merged into ONE CareSource set with DISPUTE and
--     INQUIRY as level-1 categories. Inquiry vs dispute is determined by
--     AI from the transcript, not by queue, so it cannot be a routing
--     decision - it has to be an outcome of the analysis.
--   * Routing simplified to client + caller type. queue_identifier is
--     retained as a nullable column for future clients but nothing
--     depends on it today.
--   * CLAIM_NUMBER attribute rescoped so it works on any claim call,
--     not only CareSource ones.
--   * Four example calls covering every routing outcome.
--
-- EXISTING (not created here, assumed present):
--   INTERACTION, INTERACTION_CASE, CASE,
--   INTERACTION_TRANSCRIPT, TRANSCRIPT, TRANSCRIPT_SUMMARY,
--   TRANSCRIPT_GRIEVANCE
--
-- NEW - GROUP 1, CONFIGURATION (what taxonomies exist):
--   ANALYTIC_CATEGORY_SET
--   ANALYTIC_CATEGORY_SET_VERSION
--   ANALYTIC_CATEGORY
--   ANALYTIC_ATTRIBUTE_TYPE
--
-- NEW - GROUP 2, ROUTING (which taxonomy applies to which call):
--   ANALYTIC_CATEGORY_RULE
--
-- NEW - GROUP 3, RESULTS (what got assigned):
--   TRANSCRIPT_ANALYTIC_RUN
--   TRANSCRIPT_ANALYTIC_REASON
--   TRANSCRIPT_ANALYTIC_CTG
--   TRANSCRIPT_ANALYTIC_ATTRIBUTE
--
-- Naming follows Wendy's conventions (category_value, active_ind,
-- last_modified_timestamp, user_name, appl).
-- =====================================================================


-- =====================================================================
-- SECTION 0 - DROP (demo only, safe to re-run)
-- =====================================================================
-- Child to parent order.
DROP TABLE transcript_analytic_attribute CASCADE CONSTRAINTS;
DROP TABLE transcript_analytic_ctg CASCADE CONSTRAINTS;
DROP TABLE transcript_analytic_reason CASCADE CONSTRAINTS;
DROP TABLE transcript_analytic_run CASCADE CONSTRAINTS;
DROP TABLE analytic_category_rule CASCADE CONSTRAINTS;
DROP TABLE analytic_attribute_type CASCADE CONSTRAINTS;
DROP TABLE analytic_category CASCADE CONSTRAINTS;
DROP TABLE analytic_category_set_version CASCADE CONSTRAINTS;
DROP TABLE analytic_category_set CASCADE CONSTRAINTS;


-- =====================================================================
-- SECTION 1 - GROUP 1: CONFIGURATION
--
-- Reference data. Loaded by hand or by a clustering run. Slow-changing,
-- small. Nothing here refers to a specific call.
-- =====================================================================

-- ---------------------------------------------------------------------
-- ANALYTIC_CATEGORY_SET
-- A named taxonomy. This is what tells us a group of category rows
-- belongs to CareSource rather than to general call analysis. Without
-- it, categories are an undifferentiated pile.
--
-- Adding a second client who wants their own report is ONE ROW here
-- plus their categories. No DDL, no code change.
-- ---------------------------------------------------------------------
CREATE TABLE analytic_category_set (
  analytic_category_set_id   NUMBER            NOT NULL,
  set_code                   VARCHAR2(50)      NOT NULL,
  set_name                   VARCHAR2(200)     NOT NULL,
  set_desc                   VARCHAR2(4000),
  -- CLIENT_SUPPLIED = client handed us the list (CareSource)
  -- CLUSTERING      = derived from transcript clustering
  -- MANUAL          = hand-authored / anecdotal first round
  derivation_type_cd         VARCHAR2(30)      NOT NULL,
  -- 1 = flat list, 2 = category + subcategory, 3 = three levels.
  -- Lets one schema hold a flat client list and a deeper internal one.
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
-- A dated edition of a set. Quarterly clustering produces a new version.
-- CareSource adding a category next year produces a new version.
--
-- Assignments point at a VERSION, so a call keeps forever the exact
-- category list it was scored against. Confirmed requirement: historical
-- calls are never reclassified - only new calls get the new set.
-- ---------------------------------------------------------------------
CREATE TABLE analytic_category_set_version (
  anlyt_ctg_set_version_id   NUMBER            NOT NULL,
  analytic_category_set_id   NUMBER            NOT NULL,
  version_num                NUMBER(4)         NOT NULL,
  effective_start_date       DATE              NOT NULL,
  effective_end_date         DATE,             -- NULL = currently in force
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
-- The categories themselves. Self-referencing parent handles depth: a
-- flat set has every row at level 1 with a null parent; the CareSource
-- set has DISPUTE and INQUIRY at level 1 with their report lists as
-- children.
--
-- category_value is the STABLE CODE that survives across versions, so
-- 'BENEFITS' in v1 and v2 can be rolled up together even though they are
-- physically different rows. Report on category_value, not on
-- analytic_category_id.
-- ---------------------------------------------------------------------
CREATE TABLE analytic_category (
  analytic_category_id        NUMBER           NOT NULL,
  anlyt_ctg_set_version_id    NUMBER           NOT NULL,
  parent_analytic_category_id NUMBER,
  category_value              VARCHAR2(100)    NOT NULL,
  category_name               VARCHAR2(200)    NOT NULL,
  category_desc               VARCHAR2(4000),  -- client-supplied definition
  category_level              NUMBER(1)        DEFAULT 1 NOT NULL,
  -- Y when a category may be assigned directly. Set to N for a level-1
  -- node that exists only to group children.
  assignable_ind              CHAR(1)          DEFAULT 'Y' NOT NULL,
  display_seq                 NUMBER(4),
  active_ind                  CHAR(1)          DEFAULT 'Y' NOT NULL,
  last_modified_timestamp     TIMESTAMP        DEFAULT SYSTIMESTAMP NOT NULL,
  user_name                   VARCHAR2(100),
  appl                        VARCHAR2(50),
  CONSTRAINT pk_anlyt_ctg PRIMARY KEY (analytic_category_id),
  CONSTRAINT fk_anlyt_ctg_ver FOREIGN KEY (anlyt_ctg_set_version_id)
    REFERENCES analytic_category_set_version (anlyt_ctg_set_version_id),
  CONSTRAINT fk_anlyt_ctg_parent FOREIGN KEY (parent_analytic_category_id)
    REFERENCES analytic_category (analytic_category_id),
  CONSTRAINT uk_anlyt_ctg_value UNIQUE (anlyt_ctg_set_version_id, category_value),
  CONSTRAINT ck_anlyt_ctg_assignable CHECK (assignable_ind IN ('Y','N'))
);

-- ---------------------------------------------------------------------
-- ANALYTIC_ATTRIBUTE_TYPE
-- Answers "what extra detail do we extract, and for which calls".
-- Procedure code matters on a coverage question; claim number matters on
-- a claim question. Configuring this rather than hardcoding columns
-- means adding a new aspect is a row, not a schema change.
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
-- SECTION 2 - GROUP 2: ROUTING
--
-- A handful of rows, edited maybe twice a year. Given a call, this
-- answers: which category sets do I have to run against it?
-- =====================================================================

-- ---------------------------------------------------------------------
-- ANALYTIC_CATEGORY_RULE
-- The piece Wendy's draft has no home for. The draft put plan_acronym
-- and client_specified_identifier on the CATEGORY row, which repeats the
-- client across all 24 CareSource rows and still cannot express "only
-- provider calls".
--
-- NULL in a matching column means ANY (wildcard):
--   CareSource    -> client CARESOURCE_OH, caller PROVIDER
--   Call analysis -> client NULL (all clients), caller MEMBER / PROVIDER
--
-- NOTE ON QUEUE: inquiry vs dispute is determined by AI from the
-- transcript, NOT by queue, so routing does not use queue today.
-- queue_identifier is kept nullable for a future client whose scope
-- genuinely is queue-based. Confirm where queue lives on INTERACTION
-- before relying on it.
-- ---------------------------------------------------------------------
CREATE TABLE analytic_category_rule (
  analytic_category_rule_id  NUMBER            NOT NULL,
  analytic_category_set_id   NUMBER            NOT NULL,
  rule_name                  VARCHAR2(200),
  -- OPEN ITEM: which of these three is the real key for "CareSource"?
  -- Carried from the draft until confirmed.
  plan_acronym                   VARCHAR2(30),
  client_specified_identifier    VARCHAR2(50),
  subclient_specified_identifier VARCHAR2(50),
  queue_identifier           VARCHAR2(100),    -- unused today
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
-- SECTION 3 - GROUP 3: RESULTS
--
-- Written by the batch process, never updated. This is what grows -
-- roughly 1500 calls a day.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TRANSCRIPT_ANALYTIC_RUN
-- One row per (transcript, category set version) evaluated. A CareSource
-- provider call produces TWO runs: the CareSource set and general call
-- analysis. This is what keeps the two categorizations tellable apart.
--
-- NO_RULE_MATCH is recorded explicitly, so "we looked and nothing
-- applied" is distinguishable from "we never processed this call".
--
-- Wendy's draft hung CATEGORY_ASSIGNMENT off CASE. Attaching to
-- TRANSCRIPT instead - the transcript is what gets analyzed, and not
-- every interaction necessarily has a case. If a case spans multiple
-- interactions, case-level assignment loses which call produced which
-- category. interaction_id is carried denormalized so reporting does not
-- need the full join chain every time. NEEDS WENDY'S INPUT.
-- ---------------------------------------------------------------------
CREATE TABLE transcript_analytic_run (
  transcript_analytic_run_id NUMBER            NOT NULL,
  transcript_id              NUMBER            NOT NULL,
  interaction_id             NUMBER,           -- denormalized for reporting
  anlyt_ctg_set_version_id   NUMBER,           -- NULL when NO_RULE_MATCH
  analytic_category_rule_id  NUMBER,           -- which rule fired
  caller_type_cd             VARCHAR2(30),     -- as resolved at run time
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
-- One row per distinct reason the caller called. "Find a dentist AND is
-- a crown covered" produces two rows.
--
-- reason_seq is ordering. primary_ind is a DIFFERENT job: it marks the
-- one category Tim's single-value report should show. A one-reason call
-- still needs primary_ind = 'Y'.
--
-- OPEN ITEM: confirm with Tim that "top category" means the most
-- important of the reasons found, and not a separate call-level category
-- independent of them. The two designs look identical until a
-- multi-topic call arrives.
-- ---------------------------------------------------------------------
CREATE TABLE transcript_analytic_reason (
  trnscr_anlyt_reason_id     NUMBER            NOT NULL,
  transcript_analytic_run_id NUMBER            NOT NULL,
  reason_seq                 NUMBER(3)         DEFAULT 1 NOT NULL,
  primary_ind                CHAR(1)           DEFAULT 'N' NOT NULL,
  -- short readable statement of what they wanted, so nobody has to read
  -- a paragraph to see why the call happened
  intent_text                VARCHAR2(500),
  -- what they did not know / why they had to call at all
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
-- the deepest category that fits; the parent chain gives rollup for
-- free, so a flat set and a two-level set store identically.
--
-- A reason may carry more than one category (a braces question can be
-- both a coverage question and a waiting-period question), which is why
-- this is its own table and not columns on the reason.
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
-- number, provider NPI, benefit year next. Adding one is a row in
-- ANALYTIC_ATTRIBUTE_TYPE, not a schema change.
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
-- SECTION 4 - SAMPLE DATA: GROUP 1, CONFIGURATION
--
-- Everything below is FABRICATED. No real member, provider, or call
-- content. IDs are hardcoded so they are readable in discussion.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4a. Category sets - TWO of them, not three
-- ---------------------------------------------------------------------
INSERT INTO analytic_category_set
  (analytic_category_set_id, set_code, set_name, set_desc,
   derivation_type_cd, hierarchy_depth, owner_name, user_name, appl)
VALUES (1, 'CARESOURCE_OH', 'CareSource Ohio - Provider Reporting',
  'Client-supplied categories. Level 1 is DISPUTE vs INQUIRY, determined by AI from the transcript. Level 2 is the PCDR list under DISPUTE and the PCIR list under INQUIRY. PCDR and PCIR reports are filtered views of this one set.',
  'CLIENT_SUPPLIED', 2, 'CareSource Ohio', 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category_set
  (analytic_category_set_id, set_code, set_name, set_desc,
   derivation_type_cd, hierarchy_depth, owner_name, user_name, appl)
VALUES (3, 'CALL_ANALYSIS', 'General Call Analysis',
  'Internal taxonomy derived from quarterly clustering. Category plus subcategory. Applies to all member and provider calls regardless of client.',
  'CLUSTERING', 2, 'Analytics Team', 'HAROLD', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- 4b. Set versions
-- CareSource on v1. Call analysis has two, to show the quarter boundary.
-- ---------------------------------------------------------------------
INSERT INTO analytic_category_set_version
  (anlyt_ctg_set_version_id, analytic_category_set_id, version_num,
   effective_start_date, effective_end_date, derivation_desc, user_name, appl)
VALUES (101, 1, 1, DATE '2026-01-01', NULL,
  'Initial lists supplied by CareSource Ohio for the PCDR and PCIR reports.',
  'HAROLD', 'CALLANALYTICS');

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
-- 4c. CareSource categories - THE MERGED TREE
--
--   DISPUTE  (level 1, grouping node)
--     Claim Status / Eligibility / Other Insurance / Payment Amount
--   INQUIRY  (level 1, grouping node)
--     Claim Status / Benefit Inquiry / Credentialing / Eligibility
--
-- assignable_ind = 'N' on the level-1 nodes: the model must land on a
-- child, never stop at DISPUTE alone.
--
-- Note CLAIM_STATUS and ELIGIBILITY appear under BOTH branches as
-- separate rows with distinct category_value codes. If the two client
-- lists turn out to be identical, this is where you would see it.
-- SOMEONE STILL NEEDS TO DIFF THE TWO REAL LISTS.
-- ---------------------------------------------------------------------
INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1000, 101, NULL, 'DISPUTE', 'Dispute',
  'Provider is contesting a decision already made. Feeds the PCDR report.',
  1, 'N', 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1001, 101, 1000, 'DISP_CLAIM_STATUS', 'Claim Status',
  'Provider disputing the adjudicated status or outcome of a submitted claim.',
  2, 'Y', 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1002, 101, 1000, 'DISP_ELIGIBILITY', 'Eligibility',
  'Dispute regarding member eligibility on the date of service.',
  2, 'Y', 2, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1003, 101, 1000, 'DISP_OTHER_INSURANCE', 'Other Insurance',
  'Dispute involving coordination of benefits or other coverage on file.',
  2, 'Y', 3, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1004, 101, 1000, 'DISP_PAYMENT_AMOUNT', 'Payment Amount',
  'Provider disputing the reimbursement amount applied to the claim.',
  2, 'Y', 4, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1100, 101, NULL, 'INQUIRY', 'Inquiry',
  'Provider is asking for information, not contesting a decision. Feeds the PCIR report.',
  1, 'N', 2, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1101, 101, 1100, 'INQ_CLAIM_STATUS', 'Claim Status',
  'Provider inquiring about the current status of a submitted claim.',
  2, 'Y', 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1102, 101, 1100, 'INQ_ELIGIBILITY', 'Eligibility',
  'Provider inquiring about member eligibility, typically before or after service.',
  2, 'Y', 2, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1103, 101, 1100, 'INQ_BENEFIT', 'Benefit Inquiry',
  'Provider inquiring about member benefit coverage prior to service.',
  2, 'Y', 3, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1104, 101, 1100, 'INQ_CREDENTIALING', 'Credentialing',
  'Provider inquiring about network participation or credentialing status.',
  2, 'Y', 4, 'HAROLD', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- 4d. Call analysis v1 (Q2)
-- ---------------------------------------------------------------------
INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1201, 103, NULL, 'BENEFITS', 'Benefits',
  'Questions about what the plan covers.', 1, 'Y', 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1202, 103, 1201, 'BENEFITS_COVERAGE', 'Procedure Coverage',
  'Whether a specific procedure is covered.', 2, 'Y', 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1203, 103, NULL, 'PROVIDER_NETWORK', 'Provider Network',
  'Finding or verifying a participating provider.', 1, 'Y', 2, 'HAROLD', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- 4e. Call analysis v2 (Q3, post-clustering)
--
-- BENEFITS and PROVIDER_NETWORK keep the same category_value across
-- versions, so reporting rolls up across the quarter boundary.
-- BENEFITS_WAITING_PERIOD is new in v2 and has no v1 equivalent - that
-- is the trend-line break Tim should know about.
-- ---------------------------------------------------------------------
INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1301, 104, NULL, 'BENEFITS', 'Benefits',
  'Questions about what the plan covers.', 1, 'Y', 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1302, 104, 1301, 'BENEFITS_COVERAGE', 'Procedure Coverage',
  'Whether a specific procedure is covered.', 2, 'Y', 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1303, 104, 1301, 'BENEFITS_WAITING_PERIOD', 'Waiting Period',
  'New in Q3 clustering: confusion about major services waiting periods.',
  2, 'Y', 2, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1304, 104, NULL, 'PROVIDER_NETWORK', 'Provider Network',
  'Finding or verifying a participating provider.', 1, 'Y', 2, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1305, 104, 1304, 'FIND_A_DENTIST', 'Find a Dentist',
  'Locating an in-network general or specialty dentist.', 2, 'Y', 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1306, 104, NULL, 'CLAIM', 'Claim',
  'Claim status, payment, and processing questions.', 1, 'Y', 3, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1307, 104, 1306, 'CLAIM_STATUS', 'Claim Status',
  'Where is my claim, has it been processed.', 2, 'Y', 1, 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_category (analytic_category_id, anlyt_ctg_set_version_id,
  parent_analytic_category_id, category_value, category_name, category_desc,
  category_level, assignable_ind, display_seq, user_name, appl)
VALUES (1308, 104, NULL, 'ELIGIBILITY', 'Eligibility',
  'Who is covered, and when.', 1, 'Y', 4, 'HAROLD', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- 4f. Attribute types
--
-- CLAIM_NUMBER rescoped from v1: it now hangs off the CALL_ANALYSIS
-- CLAIM category, so it works on any claim call regardless of client.
-- A second row keeps it available across the CareSource set.
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
  'Claim identifier referenced on any claim call.', 'STRING',
  NULL, 1306, 'N', 'HAROLD', 'CALLANALYTICS');

INSERT INTO analytic_attribute_type (analytic_attribute_type_id,
  attribute_type_cd, attribute_name, attribute_desc, data_type_cd,
  analytic_category_set_id, analytic_category_id, multi_value_ind, user_name, appl)
VALUES (203, 'CLAIM_NUMBER', 'Claim Number',
  'Claim identifier referenced in a CareSource dispute or inquiry.', 'STRING',
  1, NULL, 'N', 'HAROLD', 'CALLANALYTICS');


-- =====================================================================
-- SECTION 5 - SAMPLE DATA: GROUP 2, ROUTING
--
-- Three rows. Read as "run this set against calls matching this scope".
-- NULL = any.
-- =====================================================================
INSERT INTO analytic_category_rule (analytic_category_rule_id,
  analytic_category_set_id, rule_name, plan_acronym,
  client_specified_identifier, subclient_specified_identifier,
  queue_identifier, caller_type_cd, effective_start_date, user_name, appl)
VALUES (301, 1, 'CareSource OH provider calls', 'CSOH',
  'CARESOURCE_OH', NULL, NULL, 'PROVIDER',
  DATE '2026-01-01', 'HAROLD', 'CALLANALYTICS');

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

-- No rule with caller_type_cd = 'AGENCY'. Example 4 relies on that.


-- =====================================================================
-- SECTION 6 - SAMPLE DATA: GROUP 3, FOUR EXAMPLE CALLS
--
-- transcript_id and interaction_id assume matching rows in TRANSCRIPT
-- and INTERACTION. Adjust to real demo IDs before loading, or leave the
-- FKs off TRANSCRIPT for the demo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- EXAMPLE 1 - CareSource Ohio provider, ELIGIBILITY INQUIRY
-- Routing: CareSource + call analysis = TWO RUNS.
-- Shows the merged tree resolving DISPUTE vs INQUIRY from the content.
-- ---------------------------------------------------------------------
INSERT INTO transcript_analytic_run (transcript_analytic_run_id, transcript_id,
  interaction_id, anlyt_ctg_set_version_id, analytic_category_rule_id,
  caller_type_cd, run_status_cd, model_name, prompt_version,
  run_timestamp, user_name, appl)
VALUES (5030, 55401, 88401, 101, 301, 'PROVIDER', 'COMPLETED',
  'gpt-4o', 'caresource-v4', TIMESTAMP '2026-09-08 09:14:00', 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text,
  friction_text, user_name, appl)
VALUES (6030, 5030, 1, 'Y',
  'Confirming member eligibility on the date of service after a denial',
  'Eligibility portal shows current coverage, not coverage as of a past service date',
  'BATCH', 'CALLANALYTICS');

-- Lands on INQ_ELIGIBILITY, under INQUIRY - so it feeds PCIR, not PCDR
INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7030, 6030, 1102, 0.9200, 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_attribute (trnscr_anlyt_attribute_id,
  trnscr_anlyt_reason_id, analytic_attribute_type_id, attribute_value,
  confidence_num, user_name, appl)
VALUES (8030, 6030, 203, 'CLM-2026-0043117', 0.9800, 'BATCH', 'CALLANALYTICS');

-- Second run, same transcript: general call analysis
INSERT INTO transcript_analytic_run (transcript_analytic_run_id, transcript_id,
  interaction_id, anlyt_ctg_set_version_id, analytic_category_rule_id,
  caller_type_cd, run_status_cd, model_name, prompt_version,
  run_timestamp, user_name, appl)
VALUES (5031, 55401, 88401, 104, 304, 'PROVIDER', 'COMPLETED',
  'gpt-4o', 'call-analysis-v7', TIMESTAMP '2026-09-08 09:14:06', 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text,
  friction_text, user_name, appl)
VALUES (6031, 5031, 1, 'Y',
  'Wants to know why a claim denied for eligibility',
  'Cannot view historical eligibility by service date',
  'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7031, 6031, 1308, 0.8600, 'BATCH', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- EXAMPLE 2 - Member, non-CareSource, THREE questions
-- Routing: call analysis only = ONE RUN, three reasons.
-- Shows multiple reasons, two categories on one reason, and an
-- attribute on only one of them.
-- ---------------------------------------------------------------------
INSERT INTO transcript_analytic_run (transcript_analytic_run_id, transcript_id,
  interaction_id, anlyt_ctg_set_version_id, analytic_category_rule_id,
  caller_type_cd, run_status_cd, model_name, prompt_version,
  run_timestamp, user_name, appl)
VALUES (5010, 55201, 88201, 104, 303, 'MEMBER', 'COMPLETED',
  'gpt-4o', 'call-analysis-v7', TIMESTAMP '2026-09-08 11:20:00', 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text,
  friction_text, user_name, appl)
VALUES (6010, 5010, 1, 'N',
  'Is my daughter still covered as a dependent',
  'Did not know the dependent age cutoff',
  'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7010, 6010, 1308, 0.9000, 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text,
  friction_text, user_name, appl)
VALUES (6011, 5010, 2, 'Y',
  'What would orthodontic treatment cost',
  'Could not find orthodontic benefits in the plan summary',
  'BATCH', 'CALLANALYTICS');

-- One reason, TWO categories - genuinely both coverage and waiting period
INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7011, 6011, 1302, 0.9400, 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7012, 6011, 1303, 0.7900, 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_attribute (trnscr_anlyt_attribute_id,
  trnscr_anlyt_reason_id, analytic_attribute_type_id, attribute_value,
  confidence_num, user_name, appl)
VALUES (8010, 6011, 201, 'D8080', 0.9100, 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text,
  friction_text, user_name, appl)
VALUES (6012, 5010, 3, 'N',
  'Why is there a balance on a routine cleaning',
  'Believed preventive services were fully covered',
  'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7013, 6012, 1306, 0.8300, 'BATCH', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- EXAMPLE 3 - Provider, NON-CareSource
-- Routing: call analysis only = ONE RUN. Proves provider calls do not
-- automatically get CareSource categories - only CareSource's providers
-- do.
--
-- Reason 2 lands at level 1 because Q3's only child under
-- PROVIDER_NETWORK is FIND_A_DENTIST, a member-shaped subcategory.
-- That is a FINDING, not a schema problem - see Section 8.
-- ---------------------------------------------------------------------
INSERT INTO transcript_analytic_run (transcript_analytic_run_id, transcript_id,
  interaction_id, anlyt_ctg_set_version_id, analytic_category_rule_id,
  caller_type_cd, run_status_cd, model_name, prompt_version,
  run_timestamp, user_name, appl)
VALUES (5020, 55301, 88301, 104, 304, 'PROVIDER', 'COMPLETED',
  'gpt-4o', 'call-analysis-v7', TIMESTAMP '2026-09-08 13:02:00', 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text,
  friction_text, user_name, appl)
VALUES (6020, 5020, 1, 'Y',
  'Why was this claim denied',
  'Denial code on the remittance was not explained',
  'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7020, 6020, 1307, 0.9100, 'BATCH', 'CALLANALYTICS');

-- CLAIM_NUMBER now works here too, thanks to the rescope in 4f
INSERT INTO transcript_analytic_attribute (trnscr_anlyt_attribute_id,
  trnscr_anlyt_reason_id, analytic_attribute_type_id, attribute_value,
  confidence_num, user_name, appl)
VALUES (8020, 6020, 202, 'CLM-2026-0051994', 0.9700, 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text,
  friction_text, user_name, appl)
VALUES (6021, 5020, 2, 'N',
  'Has the new hygienist been added to our roster',
  'No status visibility after submitting credentialing paperwork',
  'BATCH', 'CALLANALYTICS');

-- level 1 only - no provider-side child exists in this version
INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7021, 6021, 1304, 0.7200, 'BATCH', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- EXAMPLE 4 - Agency call. NO RULE MATCHES.
-- Recorded explicitly so "nothing applied" is distinguishable from
-- "never processed".
-- ---------------------------------------------------------------------
INSERT INTO transcript_analytic_run (transcript_analytic_run_id, transcript_id,
  interaction_id, anlyt_ctg_set_version_id, analytic_category_rule_id,
  caller_type_cd, run_status_cd, model_name, prompt_version,
  run_timestamp, user_name, appl)
VALUES (5040, 55501, 88501, NULL, NULL, 'AGENCY', 'NO_RULE_MATCH',
  NULL, NULL, TIMESTAMP '2026-09-08 14:45:00', 'BATCH', 'CALLANALYTICS');

-- ---------------------------------------------------------------------
-- EXAMPLE 5 - Quarter boundary (supporting data for Test 4)
-- A Q2 call scored under CALL_ANALYSIS v1. Nothing was reclassified when
-- v2 arrived; this row still points at the v1 category.
-- ---------------------------------------------------------------------
INSERT INTO transcript_analytic_run (transcript_analytic_run_id, transcript_id,
  interaction_id, anlyt_ctg_set_version_id, analytic_category_rule_id,
  caller_type_cd, run_status_cd, model_name, prompt_version,
  run_timestamp, user_name, appl)
VALUES (5050, 55601, 88601, 103, 303, 'MEMBER', 'COMPLETED',
  'gpt-4o', 'call-analysis-v5', TIMESTAMP '2026-05-14 08:30:00', 'BATCH', 'CALLANALYTICS');

INSERT INTO transcript_analytic_reason (trnscr_anlyt_reason_id,
  transcript_analytic_run_id, reason_seq, primary_ind, intent_text,
  friction_text, user_name, appl)
VALUES (6050, 5050, 1, 'Y',
  'Asking whether a root canal is covered',
  'Benefit summary language was ambiguous',
  'BATCH', 'CALLANALYTICS');

-- v1 category id (1202), NOT the v2 one (1302)
INSERT INTO transcript_analytic_ctg (transcript_analytic_ctg_id,
  trnscr_anlyt_reason_id, analytic_category_id, confidence_num, user_name, appl)
VALUES (7050, 6050, 1202, 0.8900, 'BATCH', 'CALLANALYTICS');

COMMIT;


-- =====================================================================
-- SECTION 7 - THE TESTS
--
-- Harold's test: given a call, what query returns the categorizations I
-- have to run? If it needs hardcoded CareSource logic, the model is
-- wrong.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TEST 1: ROUTING. Which sets apply to a CareSource provider call?
-- Note there is no client-specific logic anywhere in this query.
-- Expected: 2 rows - CARESOURCE_OH v1 and CALL_ANALYSIS v2.
-- ---------------------------------------------------------------------
SELECT s.set_code, s.set_name, v.anlyt_ctg_set_version_id,
       v.version_num, r.rule_name
FROM   analytic_category_rule r
JOIN   analytic_category_set s
       ON s.analytic_category_set_id = r.analytic_category_set_id
JOIN   analytic_category_set_version v
       ON v.analytic_category_set_id = s.analytic_category_set_id
WHERE  r.active_ind = 'Y' AND s.active_ind = 'Y'
AND    (r.client_specified_identifier IS NULL
        OR r.client_specified_identifier = 'CARESOURCE_OH')
AND    (r.caller_type_cd IS NULL OR r.caller_type_cd = 'PROVIDER')
AND    (r.plan_acronym IS NULL OR r.plan_acronym = 'CSOH')
AND    SYSDATE BETWEEN r.effective_start_date
                   AND NVL(r.effective_end_date, DATE '9999-12-31')
AND    SYSDATE BETWEEN v.effective_start_date
                   AND NVL(v.effective_end_date, DATE '9999-12-31');

-- Same query, member call at a non-CareSource client.
-- Expected: 1 row - CALL_ANALYSIS v2 only.
SELECT s.set_code, r.rule_name
FROM   analytic_category_rule r
JOIN   analytic_category_set s
       ON s.analytic_category_set_id = r.analytic_category_set_id
JOIN   analytic_category_set_version v
       ON v.analytic_category_set_id = s.analytic_category_set_id
WHERE  r.active_ind = 'Y'
AND    (r.client_specified_identifier IS NULL
        OR r.client_specified_identifier = 'ACME_DENTAL')
AND    (r.caller_type_cd IS NULL OR r.caller_type_cd = 'MEMBER')
AND    SYSDATE BETWEEN v.effective_start_date
                   AND NVL(v.effective_end_date, DATE '9999-12-31');


-- ---------------------------------------------------------------------
-- TEST 2: Everything assigned to one call, across all sets.
-- Expected for transcript 55401: the CareSource inquiry category AND the
-- call analysis category, clearly attributable to different sets.
-- ---------------------------------------------------------------------
SELECT run.interaction_id,
       s.set_code,
       rsn.reason_seq,
       rsn.primary_ind,
       NVL(parent.category_name, c.category_name) AS category,
       CASE WHEN parent.category_name IS NULL
            THEN NULL ELSE c.category_name END    AS subcategory,
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
WHERE  run.transcript_id = 55401
ORDER  BY s.set_code, rsn.reason_seq;


-- ---------------------------------------------------------------------
-- TEST 3: THE PCIR REPORT.
-- A filtered view of the one CareSource set: level-1 = INQUIRY.
-- Swap 'INQUIRY' for 'DISPUTE' to get PCDR. Same table, two reports.
-- ---------------------------------------------------------------------
SELECT run.interaction_id,
       c.category_name  AS caresource_category,
       c.category_desc,
       rsn.intent_text,
       TRUNC(run.run_timestamp) AS categorized_date
FROM   transcript_analytic_run run
JOIN   analytic_category_set_version v
       ON v.anlyt_ctg_set_version_id = run.anlyt_ctg_set_version_id
JOIN   analytic_category_set s
       ON s.analytic_category_set_id = v.analytic_category_set_id
      AND s.set_code = 'CARESOURCE_OH'
JOIN   transcript_analytic_reason rsn
       ON rsn.transcript_analytic_run_id = run.transcript_analytic_run_id
JOIN   transcript_analytic_ctg ctg
       ON ctg.trnscr_anlyt_reason_id = rsn.trnscr_anlyt_reason_id
JOIN   analytic_category c
       ON c.analytic_category_id = ctg.analytic_category_id
JOIN   analytic_category top
       ON top.analytic_category_id = c.parent_analytic_category_id
      AND top.category_value = 'INQUIRY'
ORDER  BY run.run_timestamp;


-- ---------------------------------------------------------------------
-- TEST 4: Cross-quarter rollup.
-- Grouping on category_value survives the version change; grouping on
-- analytic_category_id would split BENEFITS_COVERAGE in two.
-- ---------------------------------------------------------------------
SELECT c.category_value,
       MIN(c.category_name) AS category_name,
       COUNT(*)             AS assignment_cnt
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
ORDER  BY assignment_cnt DESC;


-- ---------------------------------------------------------------------
-- TEST 5: Tim's single top category per call.
-- ---------------------------------------------------------------------
SELECT run.interaction_id,
       s.set_code,
       NVL(parent.category_name, c.category_name) AS top_category,
       rsn.intent_text
FROM   transcript_analytic_run run
JOIN   analytic_category_set_version v
       ON v.anlyt_ctg_set_version_id = run.anlyt_ctg_set_version_id
JOIN   analytic_category_set s
       ON s.analytic_category_set_id = v.analytic_category_set_id
JOIN   transcript_analytic_reason rsn
       ON rsn.transcript_analytic_run_id = run.transcript_analytic_run_id
      AND rsn.primary_ind = 'Y'
JOIN   transcript_analytic_ctg ctg
       ON ctg.trnscr_anlyt_reason_id = rsn.trnscr_anlyt_reason_id
JOIN   analytic_category c
       ON c.analytic_category_id = ctg.analytic_category_id
LEFT   JOIN analytic_category parent
       ON parent.analytic_category_id = c.parent_analytic_category_id
WHERE  s.set_code = 'CALL_ANALYSIS'
ORDER  BY run.interaction_id;


-- ---------------------------------------------------------------------
-- TEST 6: Michael's question - which procedures are members asking about?
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
-- TEST 7: Friction analysis - what did callers not know?
-- Arguably the most valuable output and the one that does not survive a
-- one-category-per-call design.
-- ---------------------------------------------------------------------
SELECT run.caller_type_cd,
       NVL(parent.category_name, c.category_name) AS category,
       rsn.friction_text
FROM   transcript_analytic_run run
JOIN   transcript_analytic_reason rsn
       ON rsn.transcript_analytic_run_id = run.transcript_analytic_run_id
JOIN   transcript_analytic_ctg ctg
       ON ctg.trnscr_anlyt_reason_id = rsn.trnscr_anlyt_reason_id
JOIN   analytic_category c
       ON c.analytic_category_id = ctg.analytic_category_id
LEFT   JOIN analytic_category parent
       ON parent.analytic_category_id = c.parent_analytic_category_id
WHERE  rsn.friction_text IS NOT NULL
ORDER  BY run.caller_type_cd, category;


-- ---------------------------------------------------------------------
-- TEST 8: Coverage check - calls where nothing applied.
-- ---------------------------------------------------------------------
SELECT run_status_cd, caller_type_cd, COUNT(*) AS call_cnt
FROM   transcript_analytic_run
GROUP  BY run_status_cd, caller_type_cd
ORDER  BY run_status_cd;


-- =====================================================================
-- SECTION 8 - FINDINGS FROM THE SAMPLE DATA
--
-- These surfaced only because we wrote example rows instead of staring
-- at column names. Both are data fixes, not schema fixes - which is the
-- point.
--
-- A. NO PROVIDER-SIDE SUBCATEGORIES. Two of the four example calls put a
--    provider reason at level 1 because the Q3 taxonomy has no provider
--    children under PROVIDER_NETWORK or (until added here) ELIGIBILITY.
--    Suggests the clustering ran mostly on member calls, or provider
--    volume was too low to form its own cluster. Consider clustering
--    member and provider transcripts separately next quarter.
--
-- B. ATTRIBUTE SCOPING was too narrow in v1. Fixed by rescoping
--    CLAIM_NUMBER to the CLAIM category. Worth reviewing every attribute
--    the same way before load.
--
--
-- SECTION 9 - OPEN ITEMS BEFORE THIS GOES BEYOND THE DEMO
--
-- 1. CLIENT IDENTITY. Is CareSource a payer, plan, group, or client?
--    ANALYTIC_CATEGORY_RULE carries plan_acronym,
--    client_specified_identifier and subclient_specified_identifier,
--    copied from the draft. Probably one is real and the rest should go.
--
-- 2. CALLER TYPE SOURCE. Lives in the transcript_summary JSON as
--    'caller'. Two questions: is it LLM-derived or carried from
--    telephony, and what are the permitted values? If it is LLM-derived,
--    routing depends on a model output - workable, but a wrong caller
--    value silently skips an entire categorization. Recommend extracting
--    to a real column or an indexed virtual column at ingest rather than
--    JSON_VALUE on every routing lookup.
--
-- 3. ATTACHMENT POINT. Runs attach to TRANSCRIPT here; the draft
--    attached assignments to CASE. Wendy's call.
--
-- 4. PCDR vs PCIR LISTS. Modelled as separate children under DISPUTE and
--    INQUIRY. Someone needs to diff the two real lists - they looked
--    similar but nobody checked.
--
-- 5. PRIMARY CATEGORY. primary_ind gives Tim a single top category.
--    Confirm he means "the most important of the reasons found" and not
--    a separate call-level category independent of them.
--
-- 6. VALIDATION SET. Inquiry vs dispute is being separated manually
--    today, which means human-labelled calls exist somewhere. That is
--    the obvious AI-vs-human agreement check, and likely what Tim wants
--    to see before signing off on client-facing categories.
--
-- 7. GLOBAL / CSR CATEGORY. Tim mentioned something; there is also an
--    existing dropdown where a rep picks a category on the case. Still
--    unknown whether these are the same thing. If it is a real distinct
--    taxonomy, it becomes a third set - one row, no schema change.
-- =====================================================================
