# CRISpy v74 - complete

Full app. Unzip, then:

    docker compose up -d --build

The `--build` matters: templates and CSS are copied into the image, so a plain
restart will serve the old page.

## v74: 2.13 daypart norm on repeats only

**2.13 takes `p_norm_basis`**, default `REPEATS`. Jill's daypart figure for
HIST M-SU 8P-12A is 128; every half hour of the daypart gives 164, repeats only
gives 128 exactly (diagnostic run 27 Sep 2026). `ALL` restores the old
behaviour. Output adds `DAYPART_NORM_BASIS`. specs.py lists the new parameter.

## v73: Aya's review of 27 Sep

**Every query caps its window end at the latest full Sunday with data**
(`[CAP-SUN]`). SP_4 printed TO_DATE 2026-09-27 on data ending 2026-09-20
because the planner passed the fiscal-year end as `p_win_to`. Section 1 caps
the target night at the latest night loaded. 3.2, 3.3 and 3.4 read that Sunday
from `CRIS_LATEST_DATE` instead of scanning the fact table.

**2.11 adds `NORM_VS_PRIOR_QH_PCT` and `NORM_LAST_VS_FIRST_PCT`**, the norm's
own movement, so answer template #15 (series QH1->QH4 vs norm QH1->QH4) can be
filled from one row set.

No table change. Requires `CRIS_Tables_v73` (= v72, renamed).

## v61: reviewed rule by rule

All 22 queries checked against everything agreed with A&E. Three corrections.

**2.4 and 2.8 were still simple averages.** They used AVG(IDENTIFIER($p_demo))
and the v57 migration, which looked for AVG( followed by a column name, missed
them. Both weighted now. They are SP_2 and SP_4, so those figures may move
where telecast durations differ.

**2.8 and 3.3 take `p_min_tcasts`**, NULL by default. A&E: no universal
telecast floor, but make the count adjustable.

**2.12's new column is `IS_SEASON_PREMIERE_CT`**, so it cannot be confused
with Nielsen's IS_SEASON_PREMIERE on the table.

## v60: the Trial 3 feedback

From A&E's call of 22 Sep and Aya's list. Requires `CRIS_Tables_v72`.

**2.10, the lead-in that was always NULL.** The logic did include repeats; a
guard excluded the whole programme, and Secret Skinwalker Ranch is preceded by
its own repeat, so every night came back with nothing. It now excludes only the
night's first runs, so Customer Wars still cannot lead into itself.

**2.12** takes `p_premiere_only` and returns `IS_SEASON_PREMIERE`. A season
premiere question was answering with the season average over eight telecasts.

**2.9** measures over the dates the series ran. **2.8** drops the season dates
from its output. **1.4** drops AA_K_UNWEIGHTED.

**Every query** returns `WINDOW_FROM` and `WINDOW_TO`, and `NORM_FROM` and
`NORM_TO` where it builds its own norm.

Still with A&E: the season roll-up for 2.11, the same for 2.10, and the 12a to
4a daypart.

## v58: the set carries one version

No change from v17. Renumbered to v58 so CRISpy, the table build, the three query
notebooks and the three documents all carry the same number. All 22 queries run
without error against `CRIS_Tables_v72`.

## v17: every average is duration weighted

Adarsh, 11 Sep 2026: any aggregation of more than one row is weighted. Eight
queries moved from a simple average: 1.1, 1.2, 1.3, 1.3b, 1.5, 2.1, 2.2, 2.7.
Requires `CRIS_Tables_v72`.

## v16: Cable Tracks decides what a premiere is

Every query now reads Cable Tracks rather than Nielsen, per the tech biweekly of
18 Sep 2026. Requires `CRIS_Tables_v72`.

    IS_FIRST_RUN_CT   episode level, first run or repeat   replaces REPEAT_IND
    IS_PREMIERE_CT    season level, first episode           replaces IS_SEASON_PREMIERE

21 of the 22 queries changed. The one place the swap is not a rename is 2.10's
lead-in flag: `MAX(REPEAT_IND)` became `MAX(IFF(IS_FIRST_RUN_CT, 0, 1))`, because
a plain rename would have marked every lead-in the wrong way round.

A night Cable Tracks has not yet catalogued now returns no premieres. That is the
rule applied as agreed, and it reads the same as a quiet night.

## v15: CRIS_TELECAST_ALL_NET is merged away

The six-network filter came off `CRIS_TELECAST_FACT` in the table build, so the
two tables held identical rows. 3.4 was the only query naming the all-network
one and now reads the telecast fact. Six tables instead of seven.

Requires `CRIS_Tables_v54`. Drop the old table by hand once the rebuild is
verified.

## v14: the Trial 2 feedback

Six changes, all from A&E's working sessions of 9 to 11 September.

**Network norms go back to the latest 12 months** `[NORM12]`, ending on the most
recent Sunday with data. Twelve queries. This reverts the fiscal-year default
from v10, which was wrong: A&E's rule is that prime norm, premiere norm, median
age norm and M/F norm all run twelve months, and only the SEASON norm stays
season-based. It also explains why their "vs Prime Norm" sheet stopped
reproducing.

**2.13 takes A&E's repeat-analysis daypart grid** `[S2-DP]`, eight dayparts with
a weekday and weekend split, replacing the six that had no documented source.
Kristen was explicit that these belong to the repeat question alone: prime is a
different daypart elsewhere, so 3.2 keeps 8p-11p.

**3.2 uses DENSE_RANK** so tied networks get the same rank. R_6 returned 11 where
A&E print "10 (tied)".

**2.11 weights the quarter-hour norm by duration**, as the Overnight Summary
does. A short quarter hour used to count the same as a full one, so a truncated
QH1 pulled its own position norm toward itself.

**3.3 no longer returns the competitive-set rank.** A ranker asked for within a
network reports the rank within that network. It is still computed, because
`p_top_n` cuts on it.

**Still blocked, both on A&E.** Season Premiere in 2.2 needs the Cable Tracks
premiere flag Adarsh is checking on. The half-season logic, parts A and B, is
with Jill.

## v13: two of the v12 fixes went too far

v12 fixed SP_6, SP_IND_10 and SP_IND_8, and broke two cases that had been passing.
Both are corrected here and both were, again, prompt text.

**R_6 came back with no route at all.** An empty list, no query and no parameters,
on the case that reproduces 184 at rank 7 and 93 at rank 12. R_2 is the same
question with a different stream and it routed to 3.2 in the same run, so this
was the model hesitating rather than a rule firing. Two changes: 3.2 now says
plainly that a question naming prime or total day with no programme is a daypart
question that 2.9 and 3.1 structurally cannot answer, and the router is told that
an empty list is for questions the catalogue cannot answer, not for ones that are
merely hard to place. An empty result reads as no data rather than as no route,
which is the worse failure.

**R_3 moved from 3.1 to 2.9**, which was my rule doing exactly what I wrote and
what I wrote being wrong. R_3 and SP_IND_8 are near-identical questions:

    R_3        where does A&E rank among ENTERTAINMENT CABLE networks
               in Interrogation Raw's time period
    SP_IND_8   where does HIST rank among networks
               in Secret Skinwalker Ranch's time period

They go to different queries because the workbook labels them differently, not
because they ask different things, and the only textual signal between them is
the phrase "entertainment cable". Both entries now key on it explicitly and say
that the signal is thin, so nobody later mistakes it for a principle.

## v12: three routing fixes, all of them prompt text

Running the thirty-two showed three questions going to the wrong query. None of
them was a calculation problem and none needed code. `agents.py` and `specs.py`
changed, and every changed line is a string the model reads.

**SP_6 was going to 1.1 instead of 2.12**, and this was not the model wandering.
The router prompt said so in as many words: *"Within a single series, that
ranking is 1.1, which returns every episode with its rank inside the season when
a programme is named."* Meanwhile the 2.12 spec lists its own triggers as
*"Which episode did best, which was lowest, which episodes beat the average"*.
The prompt and the catalogue disagreed, and the prompt won. 1.1 answers a NIGHT;
episode-level ranking across a season is 2.12, and 2.12 is what reproduces A&E's
954 over sixteen telecasts.

**SP_IND_10 was going to 1.2 instead of 2.11, and dropping the programme.** Both
queries are about quarter hours and nothing in the catalogue said which was
which. They split on scope: 1.2 is one night, 2.11 is a season. Both entries now
say so and point at each other.

**SP_IND_8 was going to 3.1 instead of 2.9.** Those two were described almost
identically, both as "where the network ranks in the time period a series
occupies". Each now says what it adds over the other.

Two general rules were added to the router as well. **Never drop an entity the
question names**, because SP_IND_10 ran without a programme that was written in
the question and returned a plausible number for a different question. And
**leave `p_season` null unless the question names a number**, because across the
twelve Skinwalker questions the season resolved to `7` in four, `NULL` in six and
was absent in two. Null is not a gap: it resolves to the current season against
the data, which is more reliable than a number inferred from context.

## The benchmark: thirty-two questions

`app/cases.py` is the only file that changed. No query, agent, resolver, pin or
renderer was touched, and the fifteen new entries are questions as text and
nothing else.

They come from the CRIS 2.0 validation workbook and they test something the
original seventeen do not.

**OV_IND_1, OV_IND_2 and OV_IND_3** are the three halves of OV_SUM asked one at a
time. Their figures must match the corresponding section of OV_SUM exactly. If
asking for the premiere line on its own returns something different from asking
for the whole summary, the difference is in how the question was read, because it
is the same query over the same night either way.

**SP_IND_1 through SP_IND_12** put one programme, Secret Skinwalker Ranch,
through all twelve Section 2 queries in turn. Same show, same season, twelve
different questions. Anything that resolves differently between them, whether the
season or the network or the demo or the window, is a parameter problem rather
than a calculation one, and this set is the cheapest way to see it.

None of the fifteen carries a date. They are worded exactly as A&E wrote them.

## The test page, at `/tests`

Seventeen questions from A&E's expected-outputs sheet, on one page, each wired to
the same `/api/plan` a typed question uses. **Run all seventeen** goes through
them one at a time; **Copy everything** puts the whole run on the clipboard as
plain text, ready to paste.

There is no expected output anywhere on that page, and none in the app. The
questions live in `app/cases.py` as text; what each should return stays in A&E's
sheet. That separation is the point - the page exists to watch CRISpy reach an
answer on its own, and a module the app can import is a module the app could
shortcut through.

Two things about how it behaves:

**Sequential, not parallel.** Seventeen concurrent planner calls would finish
sooner and tell you less: a rate limit or a model timeout would land on an
arbitrary subset and read as a routing failure.

**A clarify is not a failure.** If CRISpy asks which programme you meant, it
found the question ambiguous against the catalogue and said so rather than
guessing. For `Court Cam`, which matches three programmes, that is the correct
behaviour and the page records it as such.

The section shown against each question is where the sheet says the answer should
come from. It is a label, not a routing instruction. If CRISpy picks a different
query, that disagreement is the result.

## Fiscal years now arrive as dates

A fiscal year can be named in any question that takes a window, which is all
twenty-two, and it was being handled three ways: `p_fiscal_year` on 3.2 and 3.3,
`p_fy_to` on 3.2 alone, and a bare `names_fiscal_year` flag everywhere else that
let each query fall back to its own default.

R_1 showed what that cost. The planner returned `p_fiscal_year` null and
`p_win_to` a date - half in each language - and the start was left to whatever
the data happened to reach.

SP_5 showed the sharper version. It asks for **FY 2025**, a year that has already
ended, and both window bounds came back null. The template filled that with a
trailing fifty-two weeks, so the query answered about FY26 and said nothing about
having done so. The numbers would have looked entirely reasonable.

`app/fiscal.py` now resolves any mention of a fiscal year into two dates before
the SQL is touched. The queries keep one pair of window parameters and never
learn what a fiscal year is. `p_fiscal_year` is no longer set from the question
at all.

The dates are computed rather than asked of the model, because a fiscal year is
not a calendar one: FY26 begins on 2025-09-29 and FY25 on 2024-09-30, neither
guessable from the number. A model asked for those bounds is right most of the
time, which is the worst failure rate a date can have.

Every run that resolves a fiscal year now carries a note saying which one and
between which dates. Without it, a run against the wrong year is indistinguishable
from a run against the right one.

## Where the eighteen stand: 14 pass

    python -c "from app.validation import status; print(status())"

Two of the four that do not are simply unrun. The other two are R_1 and R_2, and
both wait on A&E rather than on code.

**SP_6 and SP_7 now pass, and neither needed a change to anything.** Both were
recorded here as method failures - SP_6 as "four telecasts A&E exclude and nobody
has said which four", SP_7 as "shape, not parameters, no parameter turns one into
the other". Both statements were wrong, and both were written with more
confidence than the evidence carried.

The SP sheets were pulled with data through about 14 July 2026, and only SP_GEN
says so. SP_6's sixteen telecasts are everything through 13 July; our four extra
aired on the 20th and 27th, after they pulled. Sum the sixteen and the average is
954.0 exactly, with LONG ROAD TO TOKYO lowest at 761 - their answer. SP_7 was
worse: three of its four references were already exact, and the fourth needed the
same cut-off.

**The pull date now sits in the three questions that need it** - SP_4 through
7/12/26, SP_6 and SP_7 through 7/13/26.

That is not feeding an answer in. It is the date A&E looked. Without it the
harness measures two things at once, whether CRISpy picks the right parameters
and whether the data has moved since July, and the second buries the first. It
did: SP_6 came back with twenty telecasts against their sixteen for no reason but
four airings in late July, and that was read as a method failure for weeks.

CRISpy still resolves the date itself. "through 7/13/26" reaches `p_win_to` on all
three of SP_7's fanned-out queries and leaves `p_norm_to` pinned at 2026-05-31,
because the window bounds the series and not the norm. Nothing is hard-coded
about where the value lands.

When the sheet is repulled those three dates come out or move. They belong to the
benchmark, not to the queries.

**R_1 comes down to five named programmes.** Every AA figure and every rank in
network matched exactly, and so did the window, the genre, the daypart and the
weighting. Only the competitive-set rank drifts, and the deltas show five titles
in our universe and not theirs: the three 90 DAY ... TELL rows on two telecasts
each, LITTLE SINGLES on two, and LOVE IT OR LIST IT on one. All five aired inside
their window, so it is not a date, and every AA reproduces, which a different
window could not do.

A minimum telecast count would fit most of the pattern, and one of three used to
live in the query before being removed as undocumented. **It is not being
reinstated.** Fitting a rule to six numbers and calling it A&E's method is how a
guess becomes a standard nobody remembers agreeing to. The five are named; the
question is why their ranker does not carry them.

## Two follow-ups from the v6 run

Both were CRISpy generating a parameter it should not have, and both are fixed
here rather than left for whoever reads the output to notice.

**The fiscal year is anchored on the data, not the calendar.** `fiscal.py` was
being handed today's date, so SP_4 came back running to 2026-09-01 against a
warehouse that stops on 2026-08-09 - a window claiming three weeks of reach it
did not have. Nothing sat in the gap, so the figures were right and the window
was not, which is the kind of wrong that stays hidden until the day it isn't. It
now asks the resolver for the last night with data, per network, or across the
stream where a ranker has no single network.

**`p_fiscal_year` reaches 3.2 and 3.3 again.** Those two have no `p_win_from` at
all: they derive their window from `p_fiscal_year` through the calendar table.
A `ConditionalPin` was forcing it to null, and its reasoning was sound when it was
written - leave the year to the query rather than to a date the model computed.
What it could not express is WHICH year. `COALESCE($p_fiscal_year, <the year the
data ends in>)` with the parameter always null can only ever answer about the
current one.

That was invisible for as long as every benchmark asked about FY26. R_1 and R_6
both do, and both passed. **Ask 3.2 about FY 2025 and it answered about FY26**,
with a rank that read entirely reasonable. The pin is removed, with the reasoning
kept in `pins.py` so nobody reinstates it.

## The trailing fifty-two week default is gone

All twelve queries that carried it now default to the fiscal year to date. A
trailing year is not a period A&E report on - it starts on an arbitrary Monday
and belongs to no year anyone is measured against. SP_4 asked about "this Fiscal
Year" and the trailing default answered from 2025-08-11, seven weeks before FY26
began, which is why its third-ranked telecast had aired before the year in
question.

## A holiday signal

`p_holiday` existed after v5 and nothing set it. SP_5 filtered on
`p_program = '%HOL PREM%'` instead - matching the slate name by wildcard, which is
the approach the flag was built to replace and which breaks the moment a film is
bought under a bucket spelled differently. The classifier now has
`is_holiday_question`, and the pin fires from it.

## Also in this build

**`DEMO_USED` on all 22 queries.** `DEMO_AA` is a real column carrying each
network's own key demo, so a query runs on it and never states what it measured.
Read back, `DEMO_AA` says nothing: it is P25-64 on AEN, HIST and FYI, F25-64 on
LIF and LMN, P18-49 on VICE. SP_3 and SP_6 both failed on that - the question
asked for P25+, the default answered on P25-64, and 242 came back where 438 was
expected. A wrong demo does not look wrong, it looks like a number.

**`p_slot_min_min` defaults to 15 in 3.1.** It was NULL, meaning any contribution
at all. A&E define Interrogation Raw's period as THU 9P-10P; the telecast runs
9:00 to 10:01p, so one minute landed in the 10:00 half hour and the period became
three half hours and ninety minutes instead of two and sixty. That third half
hour is a different time period for every network in the comparison, which is why
the whole board came back uniformly light. With the threshold: 2 slots, 60
minutes, TBSC 475 at rank 1, AEN 258 at rank 2.

**`p_holiday` in 2.7.** `IS_HOLIDAY` was baked on the telecast table from the
start and never exposed, so the holiday half of SP_5 could not be asked. Unpinned,
the query returned the highest Live+3 lift of any Lifetime film - a real number,
correctly computed, answering a question nobody had asked. Two smaller fixes came
with it: `p_program` NULL broke the `ILIKE`, and `IS_HOLIDAY` had to be carried
through both source CTEs.

**`UNIVERSE_ENT_CABLE` in 3.2.** The query returned two ranks over two universes
and printed only one denominator, so "rank 7" arrived with nothing to divide by
and 7 of 100 read exactly like 7 of 119.

**A holiday pin in `pins.py`**, and a note on the 3.1 slot pin explaining that it
now agrees with the query default. A pin that agrees with a default is
documentation; a default that quietly drifts away from its pin is a bug someone
has to find twice.

## What this does not do

CRISpy plans SQL. It does not execute against Snowflake, so `/tests` gives you
seventeen query plans, not seventeen answers. Comparing those answers to the
sheet is still a run in Snowflake and a read by a person.
