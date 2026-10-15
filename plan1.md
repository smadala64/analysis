What to say:

“We gave the Copilot coding agent a prompt that works from the data up, not from a predefined list. It runs on de-identified transcripts only. First it extracts each caller question from every call. Then it groups similar questions and rolls them up into roughly 8–15 categories, each with 3–10 subcategories. The rules: each question fits exactly one subcategory, ‘Other’ stays under 5%, names are business-friendly, and details like procedure or denial reason are captured as drill-down attributes rather than extra subcategories. Then it validates the result with a blind recheck, a held-out sample, and a coverage check, and it pauses for our review before finalizing.”

Prompt summary to share:

Goal: using all calls from 9/21–10/4 (12,712 calls), create a two-level taxonomy (category → subcategory) that can classify all future calls.

Privacy: work only on de-identified transcripts (Presidio). No PHI, no transcript IDs in outputs.

Extract each caller question from every call: caller type, the question (short paraphrase), primary yes/no, resolved on the call. Calls with no question are tagged with a reason (hang-up, IVR-only, etc.).
Group similar questions bottom-up, then roll them up into about 8–15 categories with about 3–10 subcategories each.
Mutually exclusive: each question fits exactly one subcategory.
Exhaustive: “Other” under 5%.
Subcategories describe what the caller wants. Details like procedure, claim status or denial reason are drill-down attributes, not subcategories.
Caller type (member/provider) is a separate dimension.
A call can have several topics, with one primary.
Each subcategory gets a definition, include/exclude rules, examples, and its drill-down attributes.
Validate: coverage %, a 200-question blind recheck, and an 80/20 hold-out test.
Rank: volume per category and subcategory, member vs provider split, resolved-on-call rate.
Checkpoint: share the draft list for human review before finalizing.