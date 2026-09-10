# Call Analytics walkthrough — spoken script

Read this out as written. Stage cues are in *[square brackets and italics]* — don't read those.

Roughly 35–40 minutes of talking. Expect interruptions, which is the point.

---

## Slide 1 — Title

Thanks for making the time.

Before I start, one thing to set expectations. Nothing here is built. These are proposed tables, and every row of data you're about to see is completely made up. There's no real member or provider content anywhere in this deck.

The reason I made up data is deliberate. Last time we looked at the draft diagram, none of us could confidently say what half those tables were for. Not me, not you, and Wendy wrote it. Column names on their own don't tell you much. It's a lot easier to argue with a row of data than with a column name.

So what I want out of the next hour is two things. First, your reaction to the shape — if something looks wrong or missing, stop me, don't wait until the end. Second, there are six open questions at the back that I need answers to, and some of them one of you can probably answer in a minute.

Let's go.

*[next slide]*

---

## Slide 2 — The job

Quick orientation before we get into tables.

The job, in one sentence: for every interaction that comes in, work out why the person contacted us, and store that in a way that lets several different reports — each of which wants a different category list — all be served from the same data.

Four boxes on the screen. *[point at boxes 1 and 2]* The first two already work today. A call ends, we transcribe it, we summarize it, it lands in Oracle. That's done, that's not what we're talking about.

*[point at box 3]* Everything in this deck is about the third box. Nothing else.

And the fourth box is the reports, which we'll get to at the end.

One number worth holding onto: about fifteen hundred interactions a day. I mention it because it's small. At that volume we don't need to design for performance — no partitioning, no clever indexing, batch processing is completely fine. So if anyone's worried about scale, that's the answer, and we can move on.

*[next slide]*

---

## Slide 3 — Use cases

This is the "what are we actually covering" question a few of you asked. There are three use cases, and one that I genuinely can't describe yet.

*[point at card 1]* First one is CareSource Ohio. They're a client. They asked us for two reports — PCDR for provider disputes, PCIR for provider inquiries. They handed us the category lists themselves, each category with a written definition. So we read the call, we pick a category from their list, we store it.

Two constraints on that. It only applies to provider calls, and it only applies to CareSource.

And here's a correction from earlier in the week that actually changed the design. I originally assumed we'd know whether a call was a dispute or an inquiry from the queue it came in on. We don't. There's no queue that separates them. Today we're doing that manually, and the plan is for the AI to do it by reading the transcript. That matters, and I'll come back to it.

*[point at card 2]* Second use case is the general call analysis. This one's ours, not a client's. We cluster transcripts to find out what people are actually calling about, we build our own category and subcategory list from that, and we apply it broadly. It changes every quarter when we re-cluster. This is also where the richer stuff lives — which procedure they asked about, multiple reasons on one call, what they didn't know.

*[point at card 3]* Third one. I'm going to be honest — I don't know what this is. Tim mentioned something about a global category. There's also an existing dropdown today where a rep picks a category on the case. Nobody has confirmed whether those are the same thing or two different things. It's one of my open questions at the end.

The line at the bottom is the one I'd underline. CareSource isn't a special kind of thing. They're just the first client who asked for their own categories. The pattern is "a client hands us a list and wants a report" — and there will be a second client. So I've tried to design for that rather than hard-coding CareSource into everything.

*[next slide]*

---

## Slide 4 — Why one category column won't do

This is the most important slide in the deck, so I'm going to slow down.

Everything that comes after depends on these three points. If you disagree with any of them, stop me here, because otherwise we'll spend forty minutes on a design built on something you think is wrong.

*[point at 1]* First. One interaction can need two categorizations. A CareSource provider call gets CareSource's categories *and* ours. Two different lists, two different audiences, and both have to stay attributable — we need to know which category came from which list. One column can't hold two answers.

*[point at 2]* Second. One interaction can have several reasons. Someone calls and asks "can you help me find a dentist" and then "by the way, is a crown covered?" That's one call and two genuinely different questions. If we store one category, we lose one of them.

Now — separately — Tim wants a single top category for the overall call. Those are two different requirements and people tend to collapse them into one. We handle Tim's requirement with a flag on the primary reason. We don't handle it by throwing away the other reasons.

*[point at 3]* Third, and this came out of a conversation with Harold. Our database doesn't actually store calls. It stores *interactions*. An interaction can be a telephone call, a web chat, and potentially later an email, a letter, a fax. Web chats are already sitting in these tables today. So the categorization anchors on the interaction, not on the call and not on the transcript.

The question I'd expect here is: isn't this over-engineered? And my answer is that the first two aren't hypothetical — they're live requirements right now. And the third one costs us nothing. It's literally a choice of which column we use as the foreign key.

Any pushback on those three before I move on?

*[next slide]*

---

## Slide 5 — The three groups

Alright. Nine new tables.

I know nine sounds like a lot, so let me say the mitigating thing straight away: only four of them ever get large. The other five are small reference tables.

They fall into three groups.

*[point at 1]* Group one is configuration. What taxonomies exist. Category sets, their dated versions, the categories inside them, and what extra detail we want to extract. Four tables, maybe fifty rows total, changes a couple of times a year.

*[point at 2]* Group two is routing. Which taxonomy applies to which interaction. One table. Three rows today.

*[point at 3]* Group three is results. What actually got assigned. Four tables, and this is the only group that grows.

The reason I split them this way isn't tidiness — it's that they have completely different lifecycles. Configuration is edited by people. Routing is edited maybe twice a year. Results are written by a batch process and never updated. Three different rates of change.

*[point at the line at the bottom]* And if you only remember one thing from this deck, make it this. Group one is a menu. Group two says which menu this diner gets. Group three records what they ordered.

Next few slides go group by group. For each one I'll show you the concept and then the actual rows.

*[next slide]*

---

## Slide 6 — Configuration: sets and versions

Group one.

*[point at the top-left table]* Two category sets. That's it. Everything CareSource wants and everything we want lives in two rows of one table.

*[point at the top-right table]* Then versions. A version is a dated edition of a set. CareSource is on version one. Call analysis has two versions — the Q2 list and the Q3 list that came out of clustering.

*[point at the left card]* The thing worth explaining is why versions exist at all. Assignments point at a *version*, not at a set. So when Q3 clustering produces a new list, last quarter's calls keep pointing at the Q2 list. Forever. We never go back and reclassify history — that was a confirmed requirement, only new calls get the new set.


*[next slide]*

---

## Slide 7 — Configuration: sample rows

Here's what those tables actually look like with data in them. Slow down with me on this one.

*[point at the top two tables]* Top left, the two sets. Top right, the three versions. Nothing surprising there.

*[point at the bottom table]* The bottom one is the interesting table. This is ANALYTIC_CATEGORY — the actual categories.

*[point at rows 1000 and 1004]* Look at these two rows. Row 1000 is Dispute, level one, no parent. Row 1004 is Payment Amount, level two, and its parent is 1000. That parent column is the whole mechanism — that's what makes Payment Amount a subcategory of Dispute.

*[point at rows 1301 and 1302]* Same pattern down here, but this is our own taxonomy instead of CareSource's. Benefits, and Procedure Coverage underneath it.

*[point at row 1308]* And then this one. Eligibility, level one, no parent, no children. A category that doesn't need a subcategory just sits at level one. If a client gave us a completely flat list of twelve categories, every row would look like this.

So one table holds a flat client list and a two-level internal taxonomy at the same time. That's what the parent column buys us, and it's why we don't need separate tables per client.

*[point at the bottom strip]* Last thing on this slide. CATEGORY_VALUE — that code in the fourth column — is the stable identifier. Row ids change with every version. The code doesn't. So when you report quarter over quarter, you group on the code, not the id.

Does anything about these rows look wrong, or is there a field you'd expect to see that isn't here?

*[next slide]*

---

## Slide 8 — The CareSource tree

I want to be upfront that this part changed.

My first version had PCDR and PCIR as two completely separate category sets, and I routed to one or the other based on the queue. That was wrong. There is no queue that tells us dispute from inquiry — it comes out of analyzing the call. Which means it can't be a routing decision, because we don't know the answer until after we've already done the work.

So instead, dispute and inquiry become the top level of one tree. *[point at the tree]* One CareSource set. Dispute on the left with its list underneath, inquiry on the right with its list underneath. The model reads the call and picks a path down.

And then each report is just a filter on that top level. PCDR is everything under Dispute. PCIR is everything under Inquiry. Same table, two reports.

There's a practical benefit too. If CareSource adds a category next year that applies to both reports, we add it once in the right place. If we'd kept two separate lists, someone would have to remember to add it twice, and eventually they'd forget and the lists would quietly drift apart.

*[point at the strip at the bottom]* Now, this is a real ask, not a rhetorical one. Somebody needs to put the two actual CareSource lists side by side and compare the *definitions* — not the labels. You can see Claim Status appears under both branches. If the definitions genuinely differ — one is "contesting an outcome" and the other is "asking for status" — then those are two real categories and this tree is right. If the definitions are identical and only the report differs, we can simplify this further.

That's a ten-minute job and it decides the shape. Can someone own it?

*[next slide]*

---

## Slide 9 — Routing

Group two. One table.

And I'll say plainly: this table does not exist in the draft model at all. That's the main structural gap I found.

What the draft does instead is put the client identifier on each individual category row. Two problems with that. One, the same client value gets repeated across all twenty-four CareSource rows. Two — and this is the real problem — there's still nowhere to say "only provider calls."

*[point at the table]* So here's the routing table. The whole thing. Three rows.

Rule 301: for CareSource, provider calls, telephone — run the CareSource set.

Rules 303 and 304: for any client, member calls and provider calls, any channel — run the call analysis set.

A dash means "any." So the blanks in rules 303 and 304 are what make them apply everywhere.

*[point at the three cards]* Which gives you three possible outcomes. A CareSource provider call matches rules 301 and 304 — two sets, two categorizations. Anyone else matches one. An agency call matches nothing at all.

Here's the claim I'd like you to test. The query that does this has no CareSource logic in it anywhere. It just matches the call's attributes against rows in a table. That's the entire reason adding a second client is data rather than code.

*[point at the bottom strip]* And one sequencing point that's easy to miss. Caller type is an *input* to this table. We have to know it before we can route. Which means caller type can't itself be the output of a categorization run — that would be circular. Routing would need the answer to a run that routing hasn't decided to do yet.

That ties directly to one of my open questions, so hold that thought.

*[next slide]*

---

## Slide 10 — Results: the chain

Group three. Concept on this slide, real rows on the next one.

Four levels. *[point at each in turn]*

A **run** is one categorization job — one interaction, one category set. So our CareSource provider call produces two runs.

A **reason** is one distinct question the person asked. It carries the intent phrase and the friction note.

A **category** is the actual assignment.

An **attribute** is the extracted detail — procedure code, claim number.

Why four levels and not fewer? The run layer is what keeps two categorizations of the same call apart. The reason layer is what lets one call carry several questions. Given the requirements we agreed on slide four, neither is optional.

*[point at the left card]* These anchor on the interaction — not the call, not the transcript. That's the polymorphism point from earlier.

*[point at the right card]* And they're written once by the batch process and never updated. This is the group that grows.

Let me show you what it actually looks like.

*[next slide]*

---

## Slide 11 — Results: sample rows

This is the slide that matters most. Everything before it was setup.

This is one call — the CareSource provider call — written out as actual rows across all four tables. Let me trace one path through it slowly.

*[point at run 5030]* Start here. Run 5030. It belongs to interaction 88401, and it ran category set version 101, which is the CareSource set. Caller was a provider, channel was telephone, status completed.

*[point at reason 6030]* Now down to the reason table. Reason 6030 — see the second column, run_id 5030 — that's what ties it back up to that run. One question, flagged primary. Here's the intent: confirming eligibility on the date of service. And here's the friction: the portal shows only current coverage.

*[point at ctg row 7030]* Down to the category table. Row 7030 points reason 6030 at category 1102.

And 1102 — *[gesture back]* — is a row we looked at four slides ago. It's Inquiry, then Eligibility, in the CareSource list.

*[point at the attribute row]* And the claim number hangs off that same reason.

That's one path. Now the second one, faster.

*[point at run 5031]* Run 5031. Same interaction — 88401, same number. Different set version, 104, our call analysis taxonomy. Its own reason, its own category.

And that's the whole mechanism. Two rows in the run table with the same interaction id. Nothing clever, no special columns, no conditional logic. Same conversation, categorized twice, and you can always tell which categorization came from which list.

*[point at the empty attribute row]* One thing someone usually asks — why does reason 6031 have no attribute? Because claim number is scoped to the categories where it makes sense. That scoping is configured in a table, not hard-coded. So if we later decide claim number matters somewhere else, that's a row, not a code change.

Let me stop here. Reactions? Does this hold together?

*[next slide]*

---

## Slide 12 — Example 1

Same call as the last slide, now in plain language rather than rows.

*[point at the two intent lines]* Read these two side by side. Same conversation, two framings. CareSource cares that it was an eligibility inquiry, because that's what goes in their report. We care that it was an eligibility problem, because that's what feeds our trends. Both are correct. Neither overwrites the other.

*[point at the two friction lines]* But here's the bit I actually find interesting. Look at the friction on both runs. They're describing the same underlying gap — our portal shows current eligibility, but not eligibility as of a past service date. That's why the provider had to phone us at all.

That's a concrete, fixable thing. And notice that neither report would have surfaced it. The CareSource report just says "eligibility inquiry." Our trend report just says "eligibility." The reason we know what to fix is that we captured what the caller didn't know.

That's the argument for the friction field. Categories tell you what people called about. Friction tells you why they had to call, which is the thing you can actually act on.

If anyone thinks that's scope creep — it's one text column on a table we're building anyway, and it comes out of the same model call. It's close to free.

*[next slide]*

---

## Slide 13 — Example 2

Different call. A member, not CareSource. Over about eight minutes she asks three separate things.

*[point at the three rows]* Is my daughter still covered as a dependent. What would braces cost. And why is there a balance on a routine cleaning.

Three genuinely different questions in one call.

Now let me make the alternative concrete. If we stored one category per call, we'd keep "Benefits" — and we would lose the dependent question, lose the billing question, and lose all three of those friction notes. That's most of the value of the call gone.

*[point at the star on row 2]* The star is the primary flag. That's the single category Tim's report shows. Worth noting it's a separate thing from the sequence number, which is just ordering. Even a call with one question gets a primary flag, because Tim's report always needs a value.

*[point at row 2's category cell]* Row two also carries *two* categories. The braces question is genuinely both a coverage question and a waiting-period question. Because the assignment is its own table rather than columns on the row, that costs us nothing.

And the procedure code — D8080 — attaches to row two only. Row one has no procedure. Row three has a completely different shape of detail. That's exactly why attributes are rows and not columns.

*[point at the bottom]* Three portal gaps out of one eight-minute phone call. That, to me, is the value case for the whole project.

*[next slide]*

---

## Slide 14 — Examples 3 and 4

Two quick ones to finish.

*[point at the left card]* This is a web chat. A member messaging in about whether a filling is covered.

This is the answer to "why not just put the category on the call." It isn't a call. But it routes and stores through exactly the same tables, with no special handling at all, because we anchored on the interaction.

Also worth noticing — it fails the CareSource rule on two counts. Wrong caller type and wrong channel. Even if this member belonged to CareSource, it still wouldn't pick up their categories.

*[point at the right card]* And this one's an agency call. No rule matches. We have no agency categories.

But we still write a row, marked NO_RULE_MATCH. That's deliberate. It makes "we looked and nothing applied" distinguishable from "we never processed this." Which means we can *prove* coverage instead of assuming it. If the batch silently skipped calls, we'd have no way of knowing.

*[point at the bottom strip]* And that's the summary of the whole design. Four interactions. Four completely different shapes. One schema, and no conditional logic anywhere in it.

*[next slide]*

---

## Slide 15 — What comes back out

Quickly, what we get out of all this.

*[point at the first two]* PCDR and PCIR — the two CareSource is waiting on. Both are a filter on the same set, which I don't think is obvious from how the requirement was written, so it's worth saying out loud.

*[point at the middle two]* Tim's top category, which is the primary flag. And Michael's question about which procedures people are asking about, which is the attribute table.

*[point at friction]* Friction analysis. Nobody asked for this one and I suspect it'll turn out to be the most useful thing here.

*[point at coverage]* And the coverage check — runs grouped by status, which proves nothing got missed.

*[point at the bottom strip]* One gotcha I'd rather land now than in three months. When you report across a quarter boundary, group on the stable category code, not the row id. If you group on the id, a category that carried through two versions splits into two lines for no reason and it looks like a trend that isn't there.

*[next slide]*

---

## Slide 16 — Open questions

Right. This is where I need you.

Two things. First — reactions on the shape. Anything wrong, anything missing, anything you'd do differently? Say it now, because changing it this week is cheap and changing it after we've loaded data isn't.

*[pause for reactions]*

Second, six questions.

*[point at 1]* What is CareSource in our data? Payer, plan, group, client? I've got three columns in the routing table because I don't know which one is real. Somebody in this room can probably answer this in a minute.

*[point at 2]* The caller field in the summary JSON — is it produced by the summarization model, or is it carried in from telephony? This matters more than it sounds. If it's a model output, then our routing depends on a model output. And a wrong caller value would silently skip an entire categorization with no error raised anywhere. I'd want a spot check on accuracy before we rely on it.

*[point at 3]* The PCDR and PCIR definitions — different or just differently labelled? That's the ten-minute diff I mentioned. It decides the tree shape.

*[point at 4]* What does Tim mean by "top category"? Does he mean the most important of the reasons we found, or a separate call-level category that's independent of them? Those two designs look identical until a multi-topic call turns up, and then they diverge. That one needs Tim, not us.

*[point at 5]* Where are the manually labelled dispute and inquiry calls? We're doing that separation by hand today, which means human-labelled examples exist somewhere. That's our AI-versus-human accuracy check. And honestly, I think it's the first thing Tim will ask for before he signs off on anything that goes to a client.

*[point at 6]* And the last one, which nobody has raised yet. What happens when the AI is wrong? If CareSource disputes a categorization on one of their reports, somebody has to be able to correct it. Right now nothing in this model records that a human changed something. That's a schema question, not just a process one, so I'd rather answer it before we build than after.

*[point at the bottom line]* Next steps from my side: load these tables into the demo database, run the test queries against them, then take this to Tim and Wendy — with the example rows, not with a diagram.

That's everything. What have I got wrong?



Hi Wendy,

We've drafted a set of tables for storing call categorizations, building on the model you put together. The structure holds up, but it assumes we can look at an interaction and tell which client, plan, or group it belongs to — and we don't think that's a single lookup. That's the main thing we need your help with.

Agenda:

1. Deriving call attributes from an interaction — the blocker
   - Given an interaction_id, what's the path to member/provider, plan, payer, group and subgroup?
   - Is there any single field that identifies the client, or is it always a traversal?
   - Does every interaction have a case? Can a case span multiple interactions?
   - Any existing views or queries that already resolve this?

2. Queue
   - Where does the call queue live in the schema? Is there a reference table?
   - Is it reliable enough to key routing rules on?

3. Inquiry vs dispute, and existing classification
   - What is case_reason_type_id, and how many values does it have?
   - Where does a CSR mark a case as a dispute?
   - Can we use these deterministic fields rather than an LLM for this?

4. Routing criteria and how to store them
   - We need rules like "CareSource + provider + these queues → apply these categories", and later ones scoped by plan, group, or state.
   - Fixed columns per criterion, or attribute/value rows? Which fits the existing schema better?
   - How generic should we make it for future client-specific requirements?

5. Exception handling
   - What should happen when no rule matches, or the required attributes can't be resolved?

6. Questions on your draft
   - GLOBAL_ANALYTIC_CATEGORY — what was it intended to hold?
   - CATEGORY_VERSION — was that for taxonomy changes over time?
   - Where were plan_acronym and client_specified_identifier meant to be populated from?

Goal: agree on the routing criteria and the data elements we need, before we finalize the table design and processing flow.

Item 1 is the one that blocks us — if that's all we get through, it's a good meeting. If you have a few minutes beforehand it may be worth a look, since it's likely something you'd need to check rather than recall.

Thanks,
[your name]