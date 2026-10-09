Next steps: question grouping and the claims report

The frozen outputs are the baseline: 5,170 calls and 10,406 de-identified question rows, with validation passed. Work only from the de-identified question and call CSVs. Open a clean transcript only where a step below says so. All earlier privacy rules still apply: no raw text, no TRANSCRIPT_ID, outputs in ./output/.

Goal (from my manager, for the chatbot team building a claims agent): the most-asked claims questions, their percentages, drill-downs with examples, and what's needed to answer each one.

1. Group similar questions

Normalize the 10,406 questions into roughly 30–60 standard question groups under a few themes. For example, "where is my claim" and "status of my claim" go into one group.
Automated matching (keywords or embeddings) is fine as a first pass. Then review every group yourself: split or merge as needed. For each of the top 20 groups, read 10 random members and confirm they belong.
Give each group a clear standard question name.
Report the % of questions left ungrouped or in "other".

2. Tag scope per group and exclude non-claims

Tag every group as claims | pretreatment | benefits_coverage | other.
claims: status, payment/EOB, what I owe on a claim, denial, appeal/reconsideration, correction/resubmission, COB on a claim, overpayment/recoupment, reimbursement
pretreatment: authorizations, predeterminations, estimates
benefits_coverage: what's covered, limits, maximums, deductibles, frequency rules, plan changes or comparisons, when no submitted claim is involved
other: find a dentist/network, portal, ID cards, eligibility dates, transfers, etc.
Timing rule: a question about a service already performed or a claim already submitted is claims, even if it mentions coverage, frequency or network. A question about a planned service is pretreatment or benefits_coverage.
If a group mixes scopes, split it. If individual questions are ambiguous on timing, check the clean transcript for that call_no. Don't guess.
Keep excluded rows in the files with their scope tag; don't delete them.

3. Recompute on claims only

Claims call = a call with at least one claims question. Report the revised count vs the original 5,170.
If a call's primary question is non-claims but it has a claims question, use its first claims question as the claims primary.
Report how many calls and questions were excluded, by scope.
Show pretreatment as a separate block, with headline numbers both with and without it.

4. Rankings

For each claims group (and separately for pretreatment):

number of calls, % of all 12,712 calls, % of claims calls, % of claims questions
primary vs secondary count
resolved_on_call rate (yes / no / unclear)
member vs provider vs other split
3–5 de-identified example questions

Also produce an all-questions view across all scopes for context.

5. Group-level enrichment

For the groups that cover about 80% of claims questions, one row per group, not per question:

info_needed: the data, system or knowledge a bot would need to answer it (e.g. claim lookup by member and date of service, denial reason codes with a plain-language explanation, appeal process and deadlines, EOB access)
bot_suitability: full / partial / handoff, with a one-line reason

I'll review this with a claims SME, so send it to me as a draft.

6. Lightweight taxonomy

After seeing the groups, roll them up into a few themes (e.g. claim status, denial/appeal, payment/reimbursement, COB, corrections/resubmission, pretreatment). This is a roll-up of groups; no per-row recoding.

7. Quality checks

Blind recheck: re-assign 100 random claims questions to groups without looking at the existing assignment, and report agreement.
Review the "other" or ungrouped bucket and propose new groups if any pattern covers more than about 1% of questions.
Confirm that every percentage reconciles to its base (call and question counts add up).

8. Deliverables (in ./output/)

grouped_questions.csv: question_id, call_no, caller_type, caller_question, is_primary, resolved_on_call, group_id, group_name, theme, scope
claims_summary.md: one page covering claims volume, top 10 claims questions with %, key drill-downs, and recommended first bot intents
claims_analysis.xlsx with these tabs: Top claims questions, Caller type split, Resolution by group, Drill-downs with examples, info_needed by group, Pretreatment, All questions (context), Notes. Notes covers the method, de-identification, the two-week date range, the blind-recheck result, and the caveat that claims share is a floor because only keyword-filtered calls were extracted.

9. Before building the deliverables, send me:

the group list with scope tags and counts
the revised claims call count
the info_needed draft

I'll confirm before you finalize.