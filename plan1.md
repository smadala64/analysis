New task: build a call taxonomy for ALL calls, not just claims

Goal: using every call from 2026-09-21 to 2026-10-04 (12,712 calls), create a two-level taxonomy (category → subcategory) that can classify all future calls. It must be general, not tuned to this sample, because it will later be tested on a different time period. All existing privacy rules apply: work only from de-identified data in ./clean/, never read or print ./raw/, never output TRANSCRIPT_ID, write outputs to ./output/.

1. Complete the question extraction

The 5,170 screened calls are already done (10,406 questions, frozen). Extract questions from the remaining 7,542 unscreened calls using the same question_first method and columns (call_no, caller_type, caller_question, is_primary, resolved_on_call).
Calls with no real question (hang-ups, wrong numbers, IVR-only, silence) get a single row with caller_question = “no question” and a reason.
Validate and freeze the combined file: every one of the 12,712 calls appears, with no duplicates.

2. Build the taxonomy bottom-up

Group all questions into standard question groups. Start from the existing 38 groups and extend them for non-claims topics.
Roll the groups up into categories (aim for about 8–15) and subcategories (about 3–10 per category).
Rules:
Mutually exclusive: each question fits exactly one subcategory.
Collectively exhaustive: “Other” stays under 5% of questions.
Business-friendly names, e.g. “Claims → Denial explanation”, “Eligibility → Coverage dates”.
Subcategories describe what the caller wants. Details like procedure, claim status, denial reason or plan type are not subcategories; list them as drill-down attributes for each subcategory.
Caller type (member / provider / other) is a separate dimension that applies across all categories, not a category.
A call can have several questions, so it can belong to several subcategories. Each call has one primary.
For each category and subcategory, write: a definition, include and exclude rules, 3–5 de-identified example questions, and the drill-down attributes.

3. Validate

Coverage: % of questions and calls classified (not “Other”), overall and by caller type.
Blind recheck: re-assign 200 random questions without looking at the existing assignment, and report agreement at category and subcategory level.
Hold-out check: build the taxonomy on a random 80% of calls, then classify the other 20% and report how many fit without needing new subcategories.

4. Rank

Volume per category and subcategory: call count, % of all 12,712 calls, % of questions, member vs provider split, and resolved-on-call rate.

5. Deliverables

taxonomy_v1.xlsx with tabs: Overview (key numbers), Taxonomy (category, subcategory, definition, include/exclude rules, drill-down attributes, examples), Volumes, Validation, and Notes (method, date range, de-identification, caveats)
taxonomy_v1.json: the same taxonomy in machine-readable form
all_questions_classified.csv: every question with its category and subcategory

6. Checkpoint first. After step 2, send me the draft category and subcategory list with volumes and the “Other” rate. Wait for my review before running validation and building the final deliverables.