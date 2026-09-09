# Call Analytics — Categorization Data Model

**A walkthrough for the team**

Draft for discussion. All example data in this document is fabricated — no real member, provider, or call content.

---

## 1. What we are trying to do

For every call that comes into the contact center, figure out **why the person called**, and store that in a way that supports several different reports which each want a different category list.

Transcripts and summaries already land in Oracle today. This model covers what happens next.

---

## 2. The use cases

There are three, plus one that is still undefined.

### 2.1 CareSource Ohio — provider reporting

CareSource is a client. They asked for two reports:

- **PCDR** — provider disputes
- **PCIR** — provider inquiries

They handed us the category lists, each category with a written definition. We read the call, pick the right category, store it.

Two constraints: **provider calls only**, and **CareSource only**. A member call never gets these categories, and neither does a provider call for a different client.

Whether a call is a dispute or an inquiry is determined by AI from the transcript. It is not something we know up front from the queue.

### 2.2 General call analysis

This one is ours, not a client's. We cluster transcripts to discover what people actually call about, build our own category and subcategory list from that, and apply it to all calls.

It changes each quarter when we re-cluster. This is also where the richer detail lives — which procedure they asked about, what they did not know, multiple reasons on one call.

### 2.3 Global / CSR category

Tim mentioned something. There is also an existing dropdown where a rep picks a category on the case. **We do not yet know whether these are the same thing.** Open item.

---

## 3. The two things that make this harder than it looks

### 3.1 One call can need more than one categorization

A CareSource provider call gets **CareSource's categories AND our general ones**. Both. They are different lists, produced for different audiences, and they have to stay tellable apart in reporting.

This is why a single category column on the call does not work.

### 3.2 One call can have more than one reason

A member calls and asks three things: is my daughter still covered, what would braces cost, and why is there a balance on a cleaning.

That is one call, three distinct reasons, each with its own category. If we store one category per call we lose two thirds of what the caller actually wanted.

Tim separately wants **one top category** for the overall call. That is a different requirement, not the same one — we handle it with a flag on the primary reason.

---

## 4. The tables, in three groups

Nine new tables. Only four of them ever get large.

### Group 1 — Configuration: what taxonomies exist

| Table | Holds |
|---|---|
| `ANALYTIC_CATEGORY_SET` | A named taxonomy. Two rows today: CareSource and Call Analysis. |
| `ANALYTIC_CATEGORY_SET_VERSION` | A dated edition of a set. Q2 clustering and Q3 clustering are two versions. |
| `ANALYTIC_CATEGORY` | The categories themselves, with parent/child for subcategories. |
| `ANALYTIC_ATTRIBUTE_TYPE` | What extra detail to extract, and for which categories. |

Reference data. Loaded by hand or by a clustering run. Slow-changing, small. Nothing here refers to a specific call.

### Group 2 — Routing: which taxonomy applies to which call

| Table | Holds |
|---|---|
| `ANALYTIC_CATEGORY_RULE` | "Run this set against calls matching this scope." Three rows today. |

### Group 3 — Results: what actually got assigned

| Table | Holds |
|---|---|
| `TRANSCRIPT_ANALYTIC_RUN` | One row per categorization job executed on a transcript. |
| `TRANSCRIPT_ANALYTIC_REASON` | One row per distinct reason the person called. |
| `TRANSCRIPT_ANALYTIC_CTG` | The category assigned to a reason. |
| `TRANSCRIPT_ANALYTIC_ATTRIBUTE` | Extracted detail — procedure code, claim number. |

Written by the batch process, never updated. This is what grows — roughly 1,500 calls a day.

**The shape of it:** Group 1 is a menu. Group 2 says which menu this diner gets. Group 3 records what they ordered.

---

## 5. Group 1 in detail — the configuration

### 5.1 The two category sets

| id | set_code | derivation | depth |
|---|---|---|---|
| 1 | CARESOURCE_OH | CLIENT_SUPPLIED | 2 |
| 3 | CALL_ANALYSIS | CLUSTERING | 2 |

### 5.2 Versions

| id | set | version | effective |
|---|---|---|---|
| 101 | CareSource | v1 | Jan 1 2026 → open |
| 103 | Call Analysis | v1 | Apr 1 → Jun 30 |
| 104 | Call Analysis | v2 | Jul 1 → open |

Assignments point at a **version**, not at a set. That is how a call keeps forever the exact category list it was scored against.

Confirmed requirement: **historical calls are never reclassified.** Only new calls get the new set.

### 5.3 The CareSource tree

PCDR and PCIR are not two separate sets. They are two branches of one set:

```
CARESOURCE_OH  (v1)
│
├── DISPUTE                    ← level 1, feeds the PCDR report
│   ├── Claim Status
│   ├── Eligibility
│   ├── Other Insurance
│   └── Payment Amount
│
└── INQUIRY                    ← level 1, feeds the PCIR report
    ├── Claim Status
    ├── Eligibility
    ├── Benefit Inquiry
    └── Credentialing
```

**Why one set and not two:** dispute vs inquiry is decided by AI from the transcript. We cannot route to PCDR or PCIR up front, because we do not know which one applies until after we have analyzed the call. Making it the top level of one tree means one run, one prompt, and the model picks a path down.

The two reports become **filtered views of the same set** — filter on level 1.

> **Still to confirm:** are the real PCDR and PCIR lists actually different? They looked similar in the meeting but nobody has compared them. If they are identical, this collapses further.

### 5.4 The Call Analysis tree (v2, from Q3 clustering)

```
CALL_ANALYSIS  (v2)
│
├── Benefits
│   ├── Procedure Coverage
│   └── Waiting Period        ← new in Q3
├── Provider Network
│   └── Find a Dentist
├── Claim
│   └── Claim Status
└── Eligibility
```

A flat client list and a two-level internal list store in the same table. A flat set simply has every row at level 1 with no parent.

### 5.5 Attribute types

| code | scoped to |
|---|---|
| PROCEDURE_CODE | the Procedure Coverage category |
| CLAIM_NUMBER | the Claim category |
| CLAIM_NUMBER | the whole CareSource set |

This answers "what extra aspect do we extract, and for which calls." Procedure code matters on a coverage question; it is meaningless on a credentialing call. Adding a new aspect later is **a row, not a schema change**.

---

## 6. Group 2 in detail — routing

Three rows. `NULL` means "any".

| set | client | caller_type |
|---|---|---|
| CARESOURCE_OH | CARESOURCE_OH | PROVIDER |
| CALL_ANALYSIS | *(any)* | MEMBER |
| CALL_ANALYSIS | *(any)* | PROVIDER |

Given a call, one query against this table returns the list of category sets to run. **There is no CareSource logic anywhere in that query** — it just matches the call's attributes against the rules.

Three possible outcomes:

- CareSource provider call → **2 sets**
- Any other member or provider call → **1 set**
- Agency call → **0 sets**

> **Note on queue:** an earlier version of this design routed on queue. That turned out to be wrong — inquiry vs dispute is determined by AI, not by which queue the call arrived on. The queue column stays in the table, nullable, for a future client whose scope genuinely is queue-based.

---

## 7. Worked examples

Four calls, covering every routing outcome.

### Example 1 — CareSource Ohio provider, eligibility inquiry

*A provider phones about whether a patient was eligible on the date of service, because a claim came back denied.*

**Routing:** CareSource + provider → **two runs.**

**Run 1 — CareSource**

| field | value |
|---|---|
| set version | CareSource v1 |
| intent | Confirming member eligibility on the date of service after a denial |
| friction | Eligibility portal shows current coverage, not coverage as of a past service date |
| category | Inquiry → Eligibility |
| attribute | CLAIM_NUMBER = CLM-2026-0043117 |

The model walked the tree: not a dispute (they have not appealed yet), so **Inquiry**, then Eligibility beneath it. This row feeds PCIR. PCDR does not see it.

**Run 2 — Call Analysis**

| field | value |
|---|---|
| set version | Call Analysis v2 |
| intent | Wants to know why a claim denied for eligibility |
| friction | Cannot view historical eligibility by service date |
| category | Eligibility |

**Two framings of one conversation.** CareSource cares that it was an eligibility inquiry, for their report. We care that it was an eligibility problem, for our trend analysis. Both correct. Neither overwrites the other.

Note the friction is the same underlying gap both times: the portal shows current eligibility, not eligibility as of a past service date. **That is a concrete portal fix, and neither report would have surfaced it on its own.**

---

### Example 2 — Member, non-CareSource, three questions

*A member asks three things over eight minutes.*

**Routing:** member, any client → **one run.** The CareSource rule fails on both client and caller type.

| seq | primary | intent | friction | category |
|---|---|---|---|---|
| 1 | N | Is my daughter still covered as a dependent | Did not know the dependent age cutoff | Eligibility |
| 2 | **Y** | What would orthodontic treatment cost | Could not find ortho benefits in the plan summary | Benefits → Procedure Coverage **and** Benefits → Waiting Period |
| 3 | N | Why is there a balance on a routine cleaning | Believed preventive was fully covered | Claim |

Attribute on reason 2 only: `PROCEDURE_CODE = D8080`.

Three things worth pointing out:

- `reason_seq` is just ordering. `primary_ind` is a different job — it marks the one category Tim's single-value report shows.
- **Reason 2 carries two categories.** The braces question is genuinely both a coverage question and a waiting-period question. Because assignment is its own table rather than columns on the reason, that costs nothing.
- Reason 1 sits at level 1 with no subcategory. That is fine and normal.

**What reports get out of this call:** Tim's single-category report shows "Benefits". Michael's procedure question picks up D8080 in the member ortho count. Friction analysis surfaces three separate portal gaps — all actionable, none of which survive a one-category-per-call design.

---

### Example 3 — Provider, non-CareSource

*An office manager asks why a claim was denied, and separately whether a new hygienist has been added to the roster.*

**Routing:** provider, wrong client → **one run.** Provider calls do not automatically get CareSource categories — only CareSource's providers do.

| seq | primary | intent | friction | category |
|---|---|---|---|---|
| 1 | **Y** | Why was this claim denied | Denial code on the remittance was not explained | Claim → Claim Status |
| 2 | N | Has the new hygienist been added to our roster | No status visibility after submitting credentialing paperwork | Provider Network |

Attribute on reason 1: `CLAIM_NUMBER = CLM-2026-0051994`.

Reason 2 lands at level 1 because the Q3 taxonomy's only child under Provider Network is "Find a Dentist" — a member-shaped subcategory. **See the findings in section 10.**

---

### Example 4 — Agency call

**Routing:** no rule has `caller_type = AGENCY` → **zero sets.**

We write one run row with status `NO_RULE_MATCH` and stop.

This is deliberate. Recording it explicitly means "we looked and nothing applied" is distinguishable from "we never processed this call" — so we can prove coverage rather than assume it.

---

### The four side by side

| | Ex 1: CareSource provider | Ex 2: Member | Ex 3: Provider | Ex 4: Agency |
|---|---|---|---|---|
| Runs | 2 | 1 | 1 | 1 (no match) |
| Reasons | 1 per run | 3 | 2 | 0 |
| Categories | 2 | 4 | 2 | 0 |
| Attributes | 1 | 1 | 1 | 0 |

**Four shapes. One schema. No conditional logic anywhere.**

---

## 8. What happens to a call, step by step

1. Call ends. Transcript and summary land in Oracle. *(Happens today.)*
2. Read caller type from the summary JSON, plus client and plan from the interaction.
3. Query the routing table. Returns zero, one, or two category sets.
4. **If zero** — write a `NO_RULE_MATCH` run row and stop.
5. **For each set that matched:** resolve which version is in force on the call's receipt date, load that version's categories.
6. Call the model once per set. Pass the transcript plus that set's categories and definitions. Ask back: the reasons, which is primary, and for each reason its category, intent phrase, and friction note.
7. Write the run row, with the raw response, model name, and prompt version.
8. Write reason rows.
9. Write category rows.
10. Check which attribute types are in scope for the assigned categories. Extract and write any that apply.

Steps 5–10 repeat per set.

Reporting is a separate read path afterward.

---

## 9. How reports come out

| Report | Query |
|---|---|
| **PCDR** | CareSource set, level-1 category = DISPUTE |
| **PCIR** | CareSource set, level-1 category = INQUIRY |
| **Tim's top category** | Call Analysis set, reasons where `primary_ind = 'Y'` |
| **Procedures by caller type** | Attributes where type = PROCEDURE_CODE, grouped |
| **Friction analysis** | All reasons with a friction note, grouped by category |
| **Coverage check** | Run rows grouped by status — proves nothing was missed |

**Cross-quarter reporting:** group on `category_value`, not on `analytic_category_id`. The stable code survives a version change; the id does not. A category that only exists in v2 (like Waiting Period) will show a break in the trend line at the quarter boundary — worth flagging to Tim before he sees it in a chart.

---

## 10. What we learned from writing the example data

Both of these surfaced only because we wrote out sample rows instead of reviewing column names. Both are data fixes, not schema fixes — which is the point of the exercise.

**A. The Q3 taxonomy has no provider-side subcategories.** Two of the four example calls put a provider reason at level 1, because the clustering produced member-shaped children (Find a Dentist) and nothing for roster, credentialing, or remittance questions. This suggests the clustering ran mostly on member calls, or provider volume was too low to form its own cluster. **Recommendation: cluster member and provider transcripts separately next quarter.**

**B. Attribute scoping was too narrow.** Claim number was initially scoped to the CareSource set only, so it would not have been captured on a non-CareSource claim call. Fixed. Worth reviewing every attribute the same way before load.

---

## 11. Open items

| # | Item | Who |
|---|---|---|
| 1 | Is CareSource a payer, plan, group, or client? The rule table carries all three columns until we know which is real. | Wendy / data team |
| 2 | Is `caller` in the summary JSON LLM-derived or carried from telephony? What are the permitted values? If it is LLM-derived, routing depends on a model output — a wrong value silently skips an entire categorization. | Michael |
| 3 | Assignments attach to TRANSCRIPT here; the draft attached them to CASE. If a case spans multiple interactions, case-level assignment loses which call produced which category. | Wendy |
| 4 | Are the real PCDR and PCIR lists actually different? Nobody has diffed them. | Whoever holds the CareSource spec |
| 5 | Does "top category" mean the most important of the reasons found, or a separate call-level category independent of them? The two designs look identical until a multi-topic call arrives. | Tim |
| 6 | Inquiry vs dispute is being separated manually today — so human-labelled calls exist. That is our AI-vs-human agreement check, and likely what Tim wants before signing off on client-facing categories. | Team |
| 7 | Is the global / CSR category the same as the existing case dropdown? If it is a real distinct taxonomy, it becomes a third set — one row, no schema change. | Tim |

---

## 12. Why this shape

Three things worth defending if the room pushes back:

**Adding a client is data, not DDL.** A second client asking for their own report is one row in the set table, one routing rule, and their categories loaded in. No code change, no migration.

**Nothing is ever reclassified.** Assignments point at a version. Last quarter's calls keep last quarter's categories permanently. That was a confirmed requirement, and it is why the version table exists.

**The run/reason/category split is what lets one call carry several answers.** Two categorizations from different sets, multiple reasons per call, multiple categories per reason — all three fall out of the same structure rather than needing special handling.

---

## Appendix — proposed table list

**Group 1: Configuration**
- `ANALYTIC_CATEGORY_SET`
- `ANALYTIC_CATEGORY_SET_VERSION`
- `ANALYTIC_CATEGORY`
- `ANALYTIC_ATTRIBUTE_TYPE`

**Group 2: Routing**
- `ANALYTIC_CATEGORY_RULE`

**Group 3: Results**
- `TRANSCRIPT_ANALYTIC_RUN`
- `TRANSCRIPT_ANALYTIC_REASON`
- `TRANSCRIPT_ANALYTIC_CTG`
- `TRANSCRIPT_ANALYTIC_ATTRIBUTE`

Existing tables used but not changed: `INTERACTION`, `INTERACTION_CASE`, `CASE`, `INTERACTION_TRANSCRIPT`, `TRANSCRIPT`, `TRANSCRIPT_SUMMARY`, `TRANSCRIPT_GRIEVANCE`.

Full DDL, sample data, and eight test queries are in the accompanying SQL file.
