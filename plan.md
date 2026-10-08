ROLE
You are helping me analyze two weeks of Delta Dental call transcripts for the chatbot team, which is about to build a claims agent. They need to know which claims questions callers ask, how often, and what it takes to answer each one. This is a one-off analysis: Python scripts plus Excel/Markdown outputs. Do not create database objects or change anything in the database.

PARAMETERS (ask me to confirm before Step 1)
- START_DATE = 2026-09-21, END_DATE = 2026-10-04 (inclusive, two full weeks, US/Eastern)
- CLASSIFY_SAMPLE_SIZE = 600 claims calls (for the percentages)
- DISCOVERY_SAMPLE_SIZE = 350 claims calls (for building the categories)

DATA SOURCE (Oracle, read-only)
- Table R_CST.TRANSCRIPT: TRANSCRIPT_ID, TRANSCRIPTION (CLOB JSON with metadata incl. duration and fileName), TRANSCRIPTION_RAW_DATA (CLOB JSON with a "combinedPhrases" array whose items have "text"; it may also have a per-speaker "phrases" array), LAST_MODIFIED_TIMESTAMP.
- Call date: parse it from the fileName (e.g. "IRCall_300114499050241008.wav", where the last 6 digits are YYMMDD = 2024-10-08). LAST_MODIFIED_TIMESTAMP can be days later than the call, so query with LAST_MODIFIED_TIMESTAMP >= START_DATE and <= END_DATE + 14 days, then keep only rows whose fileName date is within START_DATE..END_DATE. If a fileName can't be parsed, fall back to LAST_MODIFIED_TIMESTAMP and count how often that happens.
- If a transcript appears more than once for the same fileName, keep the latest row.
- Connection from environment variables ORACLE_USER, ORACLE_PASSWORD, ORACLE_DSN. Use python-oracledb (thin mode). Never hard-code credentials.

PRIVACY RULES (override everything else)
1. Raw transcripts contain PHI/PII. Never open, print, summarize or read raw transcript text into this conversation. Handle it only inside scripts.
2. When debugging raw data, print only counts, lengths, JSON keys and statistics.
3. Read transcript text only from ./clean/, and only after I confirm the de-identification spot-check.
4. No mapping from placeholders back to original values.
5. Outputs use a new sequential call_no, never TRANSCRIPT_ID. The call_no -> TRANSCRIPT_ID/fileName/date map lives only in ./raw/.
6. Folders: ./raw/ (PHI, in .gitignore, never shared), ./clean/, ./output/, ./scripts/. Create the .gitignore first.

STEP 1 – Extract all calls in the window (scripts/01_extract.py)
- Pull every transcript in the window per the date rules above.
- Build one text per call. If speaker information exists, label the lines "Agent:" / "Caller:" (work out which channel is the agent from the greeting "Welcome to Delta Dental" / "Thank you for calling" being spoken first; report how confident that is). Otherwise join the combinedPhrases text.
- Write ./raw/transcripts_raw.jsonl {call_no, text} and ./raw/id_map.csv {call_no, transcript_id, file_name, call_date, duration_seconds}.
- Print: rows queried, rows kept in the window, duplicates removed, parse failures, calls per day, average length.

STEP 2 – De-identify all calls (scripts/02_deidentify.py)
- Presidio analyzer + anonymizer (spaCy en_core_web_lg). Use multiprocessing; it must handle ~15,000 calls.
- Replace: PERSON -> [NAME], PHONE_NUMBER -> [PHONE], EMAIL_ADDRESS -> [EMAIL], US_SSN -> [SSN], addresses/LOCATION -> [ADDRESS], CREDIT_CARD and bank numbers -> [CARD].
- Custom recognizers: runs of 6+ digits incl. spaced or dashed -> [ID_NUMBER]; spoken digit sequences of 4+ number words incl. "oh"/"zero" -> [ID_NUMBER]; dates of birth spoken or numeric -> [DOB]; zip codes -> [ZIP]; NPI, group, claim and member numbers -> [ID_NUMBER]. Dollar amounts are NOT PHI; keep them, since they matter for claims questions.
- Keep dental, benefit and claims vocabulary intact (procedure names, CDT codes like D2740, "deductible", "EOB", "denied", plan names, "Delta Dental").
- Write ./clean/transcripts_clean.jsonl {call_no, text} and ./output/deid_stats.csv (placeholder counts per call). Print totals only.
- Write ./raw/spotcheck_sample.txt with 40 random calls showing original and cleaned text side by side, for ME only. Do not open it.
- STOP and tell me: "De-identification done. Please review ./raw/spotcheck_sample.txt and confirm." Wait. If I report misses, fix the recognizers and rerun.

STEP 3 – Identify claims calls (scripts/03_claims_filter.py), after my confirmation
- Definition of a claims call (agreed): the caller asks about anything to do with claims, including claim status, payment, denial, what they owe, EOBs, reimbursement, submitting or resubmitting, appeals and disputes, coordination of benefits on a claim, AND pre-treatment questions about coverage or estimated cost for a procedure (predeterminations/estimates). Applies to member and provider callers.
- First pass: keyword/phrase rules on ./clean text, tuned for recall (claim, EOB, explanation of benefits, denied, denial, paid, payment, reimburse, balance, owe, bill, statement, appeal, resubmit, processed, predetermination, pre-treatment estimate, estimate, "is it covered", "how much will I pay", "out of pocket", coordination of benefits, etc.).
- Then validate it yourself by reading clean text: 60 random flagged calls (is each really claims-related?) and 60 random unflagged calls (did we miss any?). Adjust the rules and repeat until precision and recall both look above ~90%. Report the estimates.
- Write ./output/claims_calls.csv {call_no, call_date, flagged_by} and print: total calls, claims calls, claims % of all calls.

STEP 4 – Discover the claims question types (you decide the method)
- Take a random DISCOVERY_SAMPLE_SIZE of claims calls. I am NOT giving you categories. Build them bottom-up.
- You may write and run Python to chunk, sample, embed, cluster or count. Briefly explain your approach.
- For each call, list each distinct claims question (a call can have several), with: caller_type (member / provider / other / unknown), the question in 5–8 plain words, and notes.
- From these, build a two-level taxonomy (category -> question type), e.g. Claim status / Denial reason / Patient balance / EOB explanation / Payment & reimbursement / Submission & resubmission / Appeal / Pre-treatment coverage & estimate / COB, but derive the real list from the data. For the largest 3 categories, go one level deeper (e.g. denial: frequency limit, waiting period, missing information, not a covered benefit). Categories must not overlap; anything that doesn't fit goes into "Other – explain".
- For each question type, write down:
  - definition
  - 3–5 typical caller phrasings (paraphrased, de-identified)
  - what the caller provides (member ID, claim number, date of service, provider name...)
  - what the agent needed to look up (claim status, paid amount, denial/remark code, EOB, eligibility, accumulators...)
  - how it was usually resolved (answered / sent EOB or form / transferred / reprocessing or ticket / told to contact provider or other party)
  - bot suitability: Self-service (answerable from a data lookup) / Assisted (needs explanation or judgment, bot can draft) / Human (dispute, appeal, exception)
- Save as ./output/claims_taxonomy.md and STOP for my review before Step 5.

STEP 5 – Classify ALL claims calls
Only start after I approve the taxonomy from Step 4. This step replaces the 600-call sample: every claims call is classified, so all percentages are exact counts over the full two weeks.

PRIVACY (unchanged)
Read transcript text only from ./clean/. Never open ./raw/. Outputs use call_no only. Paraphrases must come from de-identified text and keep placeholders such as [NAME] or [ID_NUMBER]; never reconstruct or guess removed details.

A. SET-UP (do this before classifying anything)
1. Freeze the taxonomy. Write ./output/claims_taxonomy_frozen.json with a short code for every category, question type and sub-type (e.g. STAT = Claim status, DEN.FREQ = Denial – frequency limit), plus a one-line definition and 1–2 example phrasings for each. Include OTHER at each level. Do not change the taxonomy during Step 5; questions that don't fit get OTHER with a note.
2. Trim the input with a script. Write scripts/05a_trim.py to remove IVR prompts, hold messages, standard greetings and closings, and repeated identity-verification boilerplate from ./clean text, keeping every caller question and agent answer. Save as ./clean/claims_trimmed.jsonl (claims calls only). Report average length before and after.
3. Build the calibration set. Choose 20 claims calls from the discovery sample that cover the main question types, classify them using the format below, and save them as ./output/calibration.csv. STOP and ask me to review it before continuing.
4. Create the work queue. ./output/queue.csv lists every claims call_no in random order with status = pending.
5. Write ./output/STEP5_INSTRUCTIONS.md containing this whole step, the taxonomy codes and the output formats, so any new chat session can resume exactly the same way.

B. OUTPUT FORMAT
Per question – one row per claims question in ./output/claims_questions.csv:
- call_no
- caller_type: member / provider / other / unknown
- category_code, question_type_code, sub_type_code (from the frozen taxonomy)
- caller_question: the caller's question paraphrased in 10–20 words from the de-identified text, e.g. "Why was my crown claim from last month denied when my dentist said it was covered?"
- procedure_or_service: crown, cleaning, filling, root canal, extraction, denture, implant, x-ray, exam, orthodontics, periodontal, other, none
- info_needed: what the agent had to look up or tell the caller to answer, one or more of: claim status, paid amount, patient balance, denial reason, EOB copy, eligibility, deductible/maximum used, frequency/waiting period rule, provider network status, payment/check details, appeal process, other
- is_primary: true for the main reason for the call (exactly one per call)
- resolved_on_call: yes / no / unclear
- resolution_type: answered / sent EOB or document / reprocessing or ticket opened / transferred / told to contact provider or other party / callback / unclear
- bot_suitability: self-service (answerable from a data lookup) / assisted (needs explanation or judgment) / human (dispute, appeal, exception)
- note: only when a code is OTHER or something is unclear

Per call – one row per call in ./output/claims_calls_coded.csv:
- call_no, number_of_claims_questions, has_non_claims_topics (true/false), not_claims (true if the call is not about claims at all; such calls get no question rows), batch_no

C. CLASSIFICATION LOOP
- Take the next 25 pending calls from queue.csv and read them from ./clean/claims_trimmed.jsonl.
- Classify each call into the formats above, using only what is in the transcript. If unsure, use OTHER or unclear; never guess.
- After each batch: append the rows to both CSVs immediately, mark the calls done in queue.csv, and update ./output/progress.json (batches done, calls done, calls remaining, timestamp).
- Every 10 batches, report: calls done / remaining, the top 5 question types so far, % coded OTHER, and % flagged not_claims.

D. CONSISTENCY CHECKS
- Every 20 batches, re-classify the 20 calibration calls without looking at your earlier answers and compare. If agreement on question_type_code is below 90%, stop and tell me which codes are drifting.
- At the start of every new chat session, read STEP5_INSTRUCTIONS.md and the frozen taxonomy, re-run the calibration check, then continue from queue.csv.

E. COMPLETION CHECKS
- Confirm every queued call is done, there are no duplicate call_no rows in claims_calls_coded.csv, and every non-not_claims call has exactly one is_primary question.
- Blind re-check: re-classify 100 random completed calls and report agreement by category. If it is below 90% for any category, tell me before producing the report.
- OTHER review: group everything coded OTHER by its notes, with counts, and suggest whether any new question types are needed. Wait for my decision before reclassifying.
- Report the not_claims count and rate. These are keyword-filter false positives and are excluded from all claims percentages, but reported separately along with the corrected claims share of all calls.
Then continue to Step 6.

STEP 6 – REPORT CHANGES (apply to the Step 6 instructions)
- All percentages are exact counts over all classified claims calls (excluding not_claims). Remove margin-of-error columns.
- Overview: total calls in window, claims calls (after removing not_claims), claims % of all calls, member vs provider split, with and without the pre-treatment coverage category.
- Top questions: for each question type and sub-type ranked by volume, show count, % of claims calls (primary reason), % of claims questions, member/provider split, % resolved on call, bot suitability, and 5 varied caller_question examples.
- Procedure drill-down: question type × procedure_or_service counts and %.
- Info needed: for each question type, the share of each info_needed value (which data lookups the claims agent must support).
- Question catalog and sample phrasings sheets as before, using caller_question for the examples.
- claims_summary.md: top 10 claims questions with %, a drill-down with examples for the top 5, what each needs to be answered, a suggested build order for the claims agent (high volume and self-service first), surprises, and method notes (de-identified, AI-classified, full two-week count, keyword filter accuracy, consistency check results).

WORKING STYLE
- Before each step, tell me your plan in 3–5 lines, then build it.
- Small readable scripts; a README in ./scripts explaining how to rerun.
- If the data looks different from what I described, stop and ask.
















Calibration looks good overall. Before approving, apply these changes to the frozen taxonomy and output format, then re-run the 20 calibration calls:

Add field scope = claims / benefits_coverage. Use benefits_coverage for questions about plan benefits, maximums, deductibles, frequencies or whether a service is covered, when no specific submitted claim is involved. Keep all other fields the same.
Caller type rule: anyone calling on behalf of a member (spouse, parent, guardian) = member. Use other only for brokers, employers or unidentified third parties.
Extend procedure_or_service with: night guard, bridge, sedation/anesthesia, oral surgery, sealant/fluoride, deep cleaning/scaling.
Extend info_needed with: submission instructions, documentation requirements.
Add an automated check that every call has exactly one is_primary = TRUE, and report how many rows use other in each field.
Show me the updated calibration output, then I'll approve Step 5.