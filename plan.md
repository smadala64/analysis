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

STEP 5 – Classify a sample for percentages (after I approve the taxonomy)
- Draw a NEW random sample of CLASSIFY_SAMPLE_SIZE claims calls (exclude the discovery sample if possible).
- For every call, read the clean text and record each claims question with: call_no, caller_type, category, question_type, sub_type (if applicable), is_primary (main reason of the call), resolved_on_call (yes/no/unclear), resolution_type, bot_suitability. No transcript quotes in this file. Save to ./output/claims_questions.csv.
- Also record per call: number of claims questions and whether the call had non-claims topics too.
- Use only what's in the transcript. If unsure, mark Other or unclear; never guess.
- Report progress every 50 calls.

STEP 6 – Compute and package (scripts/06_report.py; all numbers from code)
Produce ./output/claims_analysis.xlsx with sheets:
- Overview: window, total calls, claims calls and % of all calls, member vs provider split, sample sizes, 95% margin of error for sample-based percentages, keyword-filter precision/recall estimates.
- By category: count and % per call (primary reason) AND per question, split member / provider, with margin of error.
- By question type: same, at the question-type and sub-type level.
- Question catalog: one row per question type, with definition, % of claims calls, % of claims questions, member/provider split, typical phrasings, caller provides, agent looks up, usual resolution, % resolved on call, bot suitability.
- Sample phrasings: 5–10 de-identified example phrasings per question type (for chatbot intent design and test cases).
- Data: claims_questions.csv.
And ./output/claims_summary.md, a 1–2 page plain-English summary for the chatbot team covering:
  - how big claims is
  - the top 10 claims question types with % (member vs provider)
  - for each of the top 5: what callers ask, what's needed to answer, and how suitable it is for the bot
  - a suggested priority order for the claims agent (high volume + self-service first)
  - surprises
  - method and caveats (sample-based, de-identified, AI-classified, keyword filter accuracy)

WORKING STYLE
- Before each step, tell me your plan in 3–5 lines, then build it.
- Small readable scripts; a README in ./scripts explaining how to rerun.
- If the data looks different from what I described, stop and ask.