ROLE
You are helping me run a one-off test: find out why people called Delta Dental over the last 1–2 weeks, using a sample of call transcripts. This is a quick analysis, not a product. Keep everything simple: Python scripts plus CSV/Excel outputs. Do not create database tables or change anything in the database.

DATA SOURCE (Oracle, read-only)
- Table: R_CST.TRANSCRIPT
- Columns: TRANSCRIPT_ID (NUMBER), TRANSCRIPTION (CLOB, JSON), TRANSCRIPTION_RAW_DATA (CLOB, JSON), LAST_MODIFIED_TIMESTAMP (TIMESTAMP WITH TIME ZONE), USER_NAME, APPL
- Use TRANSCRIPTION_RAW_DATA. It is JSON with a "combinedPhrases" array; each item has a "text" field holding the conversation. It may also contain a per-speaker "phrases" array (with channel/speaker info). Inspect the structure on ONE record by printing only the JSON keys, never the text values, and use speaker info if it exists.
- LAST_MODIFIED_TIMESTAMP is when the row was last updated, not the call date. The call date is also in the file name inside TRANSCRIPTION metadata (for example "IRCall_300114499050241008.wav", where the last 6 digits are YYMMDD). Extract it as call_date when possible.
- Connection details come from environment variables: ORACLE_USER, ORACLE_PASSWORD, ORACLE_DSN. Never hard-code credentials. Use the python-oracledb package (thin mode).

HARD RULES ON PRIVACY (these override everything else)
1. The raw transcripts contain PHI/PII. You must NEVER open, print, summarize or read the contents of raw transcript files or query results into this conversation. Work with them only through the scripts you write.
2. When you inspect or debug, print only counts, lengths, JSON keys and placeholder statistics, never transcript text.
3. You may read transcript text ONLY from the de-identified file, and ONLY after I confirm in this chat that I have spot-checked it.
4. Do not store any mapping from placeholders back to original values.
5. Do not use the database TRANSCRIPT_ID in any output file. Use a new sequential call_no (1, 2, 3...). Keep a separate private file mapping call_no -> TRANSCRIPT_ID and call_date in the raw folder only.
6. Folder layout: ./raw/ (PHI, never shared, add to .gitignore), ./clean/ (de-identified), ./output/ (results). Create a .gitignore that excludes ./raw/.

STEP 1 – Size and sample
Write scripts/01_extract.py that:
- Counts rows in the window (parameter DAYS, default 14).
- Pulls a random sample (parameter SAMPLE_SIZE, default 500) using ORDER BY DBMS_RANDOM.VALUE FETCH FIRST :n ROWS ONLY, filtered on LAST_MODIFIED_TIMESTAMP >= SYSTIMESTAMP - NUMTODSINTERVAL(:days,'DAY').
- Reads the CLOBs, parses the JSON, and builds one text string per call (speaker-labelled lines like "Agent: ..." / "Caller: ..." if speaker info exists, otherwise the joined combinedPhrases text).
- Writes ./raw/transcripts_raw.jsonl as {"call_no", "text"} and ./raw/id_map.csv as call_no, transcript_id, call_date, duration_seconds.
- Prints only: total rows in the window, rows sampled, average text length, and the number of rows that failed to parse.

STEP 2 – De-identify
Write scripts/02_deidentify.py using presidio-analyzer and presidio-anonymizer (spaCy en_core_web_lg) that:
- Detects and replaces: PERSON -> [NAME], PHONE_NUMBER -> [PHONE], EMAIL_ADDRESS -> [EMAIL], US_SSN -> [SSN], DATE_TIME -> [DATE], LOCATION/addresses -> [ADDRESS], CREDIT_CARD -> [CARD].
- Adds custom regex recognizers for:
  - member/subscriber IDs and other long ID numbers: any run of 6+ digits, including digits separated by spaces or dashes -> [ID_NUMBER]
  - spoken digit sequences, e.g. "five five two one eight nine" or "five five two, one eight nine" (4+ number words in a row, including "oh"/"zero") -> [ID_NUMBER]
  - dates of birth in spoken or numeric form ("March fifth nineteen eighty", "3/5/1980") -> [DOB]
  - zip codes -> [ZIP] (keep them out; we only need to know a zip was given)
  - group numbers, claim numbers, NPI (10 digits) -> [ID_NUMBER]
- Keeps dental and benefit vocabulary intact (procedure names, "crown", "deductible", "maximum", plan names such as PPO/Premier) and "Delta Dental".
- Writes ./clean/transcripts_clean.jsonl as {"call_no", "text"}.
- Writes ./output/deid_stats.csv with counts of each placeholder type per call, and prints totals only.
- Writes ./raw/spotcheck_sample.txt containing 40 random calls showing original and cleaned text side by side, for ME to review. You must not open this file.
Then STOP and tell me: "De-identification done. Please review ./raw/spotcheck_sample.txt and confirm before I read any transcripts." Wait for my confirmation. If I report misses, update the recognizers and rerun.

STEP 3 – Discover why people called (only after I confirm the spot-check)
Work only from ./clean/transcripts_clean.jsonl. I am NOT giving you a category list. Your job is to discover it.
- Decide your own approach. You may write and run Python to chunk, sample, embed, cluster or count; explain briefly what you chose and why.
- For each call, capture each distinct reason for calling in 5–8 words, plus caller type (member / provider / other / unknown). Save to ./output/topics.csv (no transcript quotes).
- From the topics, build the categories and subcategories bottom-up: group similar reasons, name each group, write a one-line definition and count calls in each.
- Then go one level deeper on the 3 largest categories: what specific kinds of questions sit inside them (e.g. within claims: denial reason, payment status, EOB confusion) and what details would make them actionable (procedure, plan feature, delivery method, etc.).
- Report anything unexpected, and anything that doesn't fit, rather than forcing it into a category.
- All counts must come from code over the full file, not from your reading of a subset. Say which numbers are exact counts and which are estimates from a sample.

STEP 4 – Write it up
./output/category_list.md (discovered categories, subcategories and definitions), ./output/call_reasons_summary.xlsx (counts and % by category/subcategory and caller type), and ./output/call_reasons_summary.md (one page: top reasons, deep-dive findings for the top 3 categories, surprises, and 1–2 de-identified example snippets per top subcategory).

STEP 5 – Summarize
Write scripts/05_summary.py that produces ./output/call_reasons_summary.xlsx with sheets:
- Summary: calls by primary category with count and % of calls, split by caller type
- Subcategories: topics by category and final_subcategory with count and %
- Topics: the full topics_final.csv
- Notes: sample size, date window, number of calls with multiple topics, % resolved on call, and the method (random sample, de-identified, AI-classified, not a census)
Then write ./output/call_reasons_summary.md: a one-page plain-English summary with the top 10 reasons, member vs provider differences, anything surprising, and, for each of the top 5 subcategories, 1–2 short de-identified example snippets taken from ./clean only.

DELIVERABLES
./output/call_reasons_summary.xlsx, ./output/call_reasons_summary.md, ./output/category_list.md, ./output/topics_final.csv, ./output/deid_stats.csv, plus the scripts in ./scripts/ with a short README explaining how to rerun them.

WORKING STYLE
- Before writing code, show me the plan for each step in 3–5 lines, then build it.
- Prefer small, readable scripts over a framework.
- If anything is unclear about the data (for example the JSON structure differs from what I described), stop and ask rather than guess.