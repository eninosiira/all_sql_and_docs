# CRISpy

A question goes in, a parameterised CRIS query comes out.

CRISpy does not write SQL and does not run it. Every query it returns was
authored and validated in the CRIS notebooks, comments and validation cases
intact. The planner's whole job is to decide which of the twenty-two a question
is asking for and what to point it at. That boundary is why the output can be
trusted: the worst a bad plan produces is the wrong query with visible
parameters, not novel SQL nobody has reviewed.

Covers Sections 1 to 3: overnight summaries, series performance, and the
competitive rankers.

## Run it

```bash
cp .env.example .env        # then put your OPENAI_API_KEY in it
docker compose up --build
```

Open http://localhost:8000. The benchmark page is at `/tests`.

`OPENAI_MODEL` in `.env` is read at startup and never hardcoded, so moving to a
newer model is an env change and a restart. Editing anything in `app/sql/` takes
effect on the next request, because compose mounts that directory read-only and
the templates are read per request. A query fix does not need a rebuild.

No Snowflake credentials are needed. CRISpy writes SQL; you run it.

## How a question becomes SQL

```
  prompt
    |
    +- 1  Intent agent      is this a ratings question at all?
    |
    +- 2  Router agent      which of the twenty-two answers it?
    |                       returns several when one question needs several:
    |                       an Overnight Summary is three tables, and a season
    |                       premiere is measured against three references
    |
    +- 3  Parameter agents  one per routed query, in parallel
    |        +- missing something required? ask, and stop here
    |
    +- 4  Resolver          every value checked against what the warehouse holds
    |        +- ambiguous? offer the options rather than guess
    |
    +- 5  Renderer          rewrites the SET block of the validated template
                            and touches nothing below it
```

The agents are separate LLM calls on purpose. Folding intent and memory into one
call is what made an earlier version answer from memory when it should not have:
a single call let the model conflate two judgements.

## Why the parameters are the hard part

The queries were already right. What went wrong went wrong upstream of them.

A&E's benchmark asks which episodes beat the season average **among P25+**. Run
on the network's default demo, which is P25-64 on A&E and History, the query
returns 242 where 517 was expected. Nothing errors and nothing looks odd. **A
wrong demo does not look wrong. It looks like a number** - which matters more
here than it would elsewhere, because what reads these results is often a model
rather than a person who might notice that Alaska State Troopers does not
usually do 242.

Every case that failed during validation failed this way, and none of them
needed a change to any calculation:

| what was wrong | what it produced |
|---|---|
| demo left on the network default | 242 against an expected 517 |
| window defaulting to a trailing year | a ranker whose third row aired before the fiscal year began |
| holiday flag in the data but never exposed | the best lift of any film, for a question about holiday films |
| wildcards in a programme name | three programmes returned as one answer |
| slot threshold left null | a 61-minute telecast claiming a third half hour, widening the period for every network in the comparison |

So the design assumption is that the parameters are where accuracy lives.
`pins.py` records the rules that are not obvious, `fiscal.py` resolves a fiscal
year into dates rather than asking a model to compute one, and every query
returns the demo, window and grain it actually measured on.

## What it asks for, and what it does not

Only the network, and only when nothing else identifies one. Everything else has
a documented default, and asking about a field that has one wastes the turn.

| field | default |
|---|---|
| date | the most recent night with data. "Last night" and no date resolve identically |
| demo | the network's own key demo, so one run across networks gives each its own |
| stream | Live+SD |
| window | fiscal year to date |
| specials | included in overnights, excluded from rankers, per A&E |
| season | whichever season each premiere belongs to |

The network is the exception because a wrong one returns zero rows and no error,
which reads as a quiet night rather than a mistake.

## The resolver

`app/data/` holds two CSVs exported from Snowflake: about three thousand rows of
programme and season identity, and seventy-two rows of network, date and demo
context. Neither holds an audience figure. They are identity, not measurement,
which is why they fit in a repository at all.

**The lookups are SQL, not Python, and that is the point.** The CSVs load into
SQLite at startup and every lookup is a real query against
`CRIS_RESOLVER_PROGRAM` and `CRIS_RESOLVER_CONTEXT`. Those tables already exist
in `AUDIENCE_DEV_DB.CRIS` with the same column names, so porting is a connection
change rather than a rewrite. Anywhere the two dialects differ is marked
`PORTING:` in `app/resolver.py`.

It exists because a parameter read out of a question is a claim rather than a
fact. CRISpy produced valid SQL from the first day and the SQL ran clean, but it
wrote `HIST`, `%SKINWALKER%` and `7` without checking that any of them exist.

What it settles before the SQL is written:

- **The stored title.** Nielsen keeps `PROGRAM_NAME` in a 25-character field, so
  the World War II series is stored as `WORLD WAR II TOM HANKS`, with "with"
  gone. An equality test against the full phrase finds nothing.
- **The network**, read from the programme rather than guessed.
- **The season string.** `CT_SEASON` is free text, so "season 7" can need `7`,
  `07`, `2026` or `7B` depending on the series.
- **Which season is current**, which is the only meaning "how is it doing" has.
- **What "last night" is**, which is not yesterday: it is the most recent night
  with data, and it differs by network and by stream.
- **Whether a stream can be dayparted.** The ACM streams carry no quarter-hour
  rows, so a C3 daypart question is unanswerable rather than empty.

Two things it will not do. It does not break ties: two networks carrying one
title, or both `13` and `13B` existing, is a question, because A&E decided
sub-seasons are separate seasons. And it does not answer: it turns a phrase into
a parameter and stops, so every figure still comes from a reviewed query.

Regenerate the CSVs with `CRIS_Resolver_Tables` whenever the prepared tables are
rebuilt. A stale resolver does not fail. It confidently rejects a season that
started three weeks ago.

## The A&E benchmark

`/tests` runs A&E's seventeen validation questions through the same path a typed
question takes. Nothing about any answer is stored where the app can reach it:
`validation.py` is a test fixture and no runtime module imports it.

**All seventeen route to the right query.** Of the sixteen that have a published
figure, fifteen reproduce it exactly.

### Section 1, Overnight Summary

- [x] **OV_1** - HIST premieres, 30 May 2025, against season norms

  `SECRETS DECLASSIFIED / 9 SPY TECH` 306 against a norm of 210 over 8
  telecasts, +45.7. `UNBELIEVABLE WITH DAN A. / 30` 290 against 279 over 19,
  +3.9.

- [x] **OV_2** - LIF premieres, 7 Feb 2026 - `[S1-YEARSEASON]`

  227 against a norm of **138 over thirteen telecasts** running 4 Oct 2025 to
  31 Jan 2026. One night in, thirteen telecasts of norm out. Those thirteen span
  `CT_SEASON` 2025 and 2026, because Cable Tracks labels the Lifetime movie
  slate by calendar year; what they share is FY26. Matching on `CT_SEASON` cuts
  the norm at 1 January, and a trailing twelve months gives 39 telecasts and 140.
  Only the fiscal-year reading returns 138, so the data itself tells the readings
  apart.

- [x] **OV_SUM** - the full Overnight Summary for HIST, 12 June 2026

  One question, three queries. Premiere at -37.1 against norm, quarter hours
  151 / 168 / 168 / 141, lead-in 114 into 158.

### Section 2, Series Performance

- [x] **SP_1** - average for the latest season of Court Cam

  `AEN / COURT CAM / 9B` 214 over 12 telecasts, one row. The wildcards matter:
  `%COURT CAM%` matches `COURT CAM`, `COURT CAM: UNDER OATH` and
  `COURT CAM SPECIALS`, and returns all three as one answer.

- [x] **SP_2** - Neighborhood Wars season 9 against the prior season

  266 against 188, +78 over 20 telecasts, +41.5. A&E print +41; they have agreed
  decimals can be dropped.

- [x] **SP_3** - Alaska State Trooper episodes above the season average, P25+

  517, 489, 481, 475, 469, 438 against a season average of 425. **This is the
  demo case.** On the network default it returned 242 against 224.

- [x] **SP_4** - best-performing LFT movie this fiscal year, W25-64

  `DOUBLE DOUBLE TROUBLE` 235 at rank 1, `MARY J. BLIGE: BE HAPPY` 227 at 2.
  Needs `p_grain = TELECAST`: on Lifetime the PROGRAM is the slate a film was
  bought under and the film's own title is the EPISODE, so a series-grain ranker
  returns the name of a category.

- [x] **SP_5** - best L+3 lift among LFT holiday movies, FY 2025, P25-64

  `VERY MERRY BEAUTY SALON` 205 to 308, +103, +50.2%. Three parameters together,
  none optional: the holiday flag, telecast grain, and a **closed** fiscal year
  of 30 Sep 2024 to 28 Sep 2025 rather than the one in progress.

- [x] **SP_6** - lowest episode of World War II With Tom Hanks, P25+

  `LONG ROAD TO TOKYO`, 6 July 2026, 761 against a season average of 954 over
  16 telecasts, -20.2, ranked 16 of 16.

- [x] **SP_7** - how the season premiere of HIST Greatest Machines performed

  Four references from three queries: the premiere `AERIAL ATTACKERS` at 266,
  season average 222 over 7 telecasts (+19.8%), HIST time period 8-11p at 182,
  HIST premieres in Prime at 250 over 142 nights and 17,155 minutes.

- **SP_GEN** - how Secret Skinwalker Ranch is performing

  Runs and returns a full snapshot. A&E's sheet publishes no figure for this one,
  so there is nothing to match against.

### Section 3, Competitive Rankers

- [x] **R_3** - where A&E ranks in Interrogation Raw's time period, 2 July 2026

  TBS 475 at rank 1, A&E 258 at rank 2, out of 97. **The slot threshold case.**
  Interrogation Raw runs 9:00 to 10:01pm, so one minute lands in the 10:00 half
  hour. With no threshold the period became three half hours and ninety minutes
  instead of two and sixty, and that third half hour is a different time period
  for every network in the comparison. The whole board came back about 6% light
  with the rank order intact, which is what a period definition looks like and
  what a demo error never does.

- [x] **R_4** - Top 50 Telecast Ranker, 14 July 2026, P25+

  FOX MLB ALL-STAR GAME 7611, AMERICA'S GOT TALENT-TUE 4587, FOX MLB ALL-STAR
  PRE 3536. Needs `p_universe = TV`: this is the one ranker whose universe
  includes broadcast, news and sports, and the top three would not appear at all
  under `CABLE`.

- [x] **R_5** - the same ranker on P25-64

  4245, 2094, 1644. The order changes, which is the demo doing its job.

- [x] **R_6** - History against ad-supported entertainment cable, FY26 to 5 July

  Prime 184 at entertainment-cable rank 7 of 100, year ago 208 at rank 7, -11.5.
  Total Day 93 at rank 12, year ago 106 at rank 10, -12.3.

- **R_2** - the same question on C3

  **Returns nothing, and that is the answer.** C3 carries no half-hour rows and a
  daypart is a half-hour construct. Confirmed with A&E's data team, 18 Aug 2026.
  Their own R_2 footer reads "Dayparts are ACM Program based and Commercial
  Duration weighted" against R_6's "Program QH based", so the two reports appear
  to use different constructions deliberately. A programme-level C3 rank is
  buildable off the total-programme table if they confirm that method, and it
  would not tie out to R_6 line for line.

- [ ] **R_1** - top 3 non-fiction shows per network, FY26 through 28 June 2026

  **The one open gap, and it is narrow.**

  Every audience figure matches: 524, 378, 361, 298, 284, 273, 126, 20. Every
  `RANK IN NETWORK` matches: 1, 2, 3 on each of the three networks. So does the
  window, the genre, the daypart and the minute weighting.

  Only the competitive-set rank differs. We return 10, 30, 33, 68, 74, 79 where
  A&E print 7, 27, 29, 64, 69, 74. The deltas run 3, 3, 4, 4, 5, 5, which is
  **five programmes sitting in our universe and not in theirs**:

  | programme | network | telecasts | AA | our rank |
  |---|---|---|---|---|
  | 90 DAY FIANCE BT90D: TELL | TLC | 2 | 793 | 1 |
  | 90 DAY FIANCE TOW: TELL A | TLC | 2 | 711 | 2 |
  | 90 DAY SINGLE LIFE: TELL | TLC | 2 | 560 | 7 |
  | LITTLE SINGLES | TLC | 2 | 301 | 66 |
  | LOVE IT OR LIST IT | HGTV | 1 | 289 | 73 |

  All five aired inside A&E's own window, and every audience figure reproduces.
  A different window could not do both, so this is neither a date nor a
  calculation.

  Four readings have been tested against the data and none survives. **Not the
  window**, as above. **Not the second genre**: the three TELL rows carry
  `CT_GENRE_2 = REALITY REAL LIFE`, and so do seventeen titles in the top eighty
  that A&E keep, one of them on nineteen telecasts. **Not a mini-series or
  special marker**: `CT_GENRE_1`, `CT_GENRE_2`, `CT_GENRE_3`, `PROG_TYPE_ALPHA`,
  `CONTENT_TYPE` and `IS_SPECIAL` are identical on those rows and on
  `CURSE OF OAK ISLAND`, which they include.

  A minimum telecast count would account for most of the pattern and leave
  `HAZARDOUS HISTORY` one out. A floor of three was in this query once and was
  removed for appearing in neither the PRD nor any check-in note. **It has not
  been reinstated.** Fitting a rule to six numbers and calling it A&E's method is
  how a guess becomes a standard nobody remembers agreeing to, and a ranker that
  silently drops titles is an editorial decision about what counts as a series.

  Their ranker reaches at least 368 places and drops five titles, which is the
  shape of a curated list rather than a filter. The five are named; the question
  is why their ranker does not carry them.

### A note on three of the questions

A&E pulled these sheets with data through about 14 July 2026 and the warehouse
now reaches later than that, so three questions carry the pull date: SP_4 through
7/12/26, SP_6 and SP_7 through 7/13/26.

**That date is not an answer being fed in. It is the date they looked.** Without
it the harness measures two things at once, whether CRISpy picks the right
parameters and whether the data has moved since July, and the second buries the
first. It did: SP_6 came back with twenty telecasts against their sixteen for no
reason but four airings in late July, and that was recorded as a method failure
for weeks. SP_7 was recorded as needing an output shape that did not exist. Both
were wrong, and both were written up with more confidence than the evidence
carried.

CRISpy still resolves the date itself. "through 7/13/26" reaches `p_win_to` on
all three of SP_7's fanned-out queries and leaves `p_norm_to` pinned at
2026-05-31, because the window bounds the series and not the norm. Nothing is
hard-coded about where the value lands.

When the sheet is repulled those three dates come out or move. They belong to
the benchmark, not to the queries.

## Things it refuses to fudge

**A demo it does not recognise falls back and says so.** It never substitutes the
nearest range. Adults 25-64 and adults 25-54 are different audiences, and
presenting one as the other misstates the answer rather than approximating it.
Outside the six A&E networks there is no default demo at all, and `DEMO_USED`
reads `UNRESOLVED` rather than measuring something nobody chose.

**C3 and C7 cannot be dayparted.** Ask for one and CRISpy says the data does not
support it instead of returning an empty table that looks like a quiet period.
This is a PRD-versus-data conflict for A&E, not a bug to fix here.

**Fourteen demos exist at telecast level and not at quarter-hour.** A demo can
answer in 1.1 and return nothing in 1.2. CRISpy flags it up front.

**Programme names become patterns, never literals.** Nielsen truncates
`PROGRAM_NAME` at 25 characters, so an equality test on the full title finds
nothing. The renderer matches on the most distinctive word, which survives the
truncation.

**A fiscal year is computed, not asked for.** FY26 begins on 2025-09-29 and FY25
on 2024-09-30, and neither is guessable from the number. A model asked for those
bounds is right most of the time, which is the worst failure rate a date can
have. `fiscal.py` resolves the year and the queries take two ordinary dates.

**A Nielsen month is not resolved locally.** It starts on the Monday of the week
containing the first. If a question names one and it cannot be resolved against
A&E's calendar dimension, CRISpy says so rather than doing the arithmetic itself
and being a week out.

## Layout

```
app/
  main.py       FastAPI, the pipeline, the /tests page
  config.py     env settings
  catalog.py    networks, demos, streams, and the data limits above
  specs.py      one spec per query: params, required fields, defaults
  agents.py     intent, router, parameters, clarify
  resolver.py   every value checked against the warehouse
  fiscal.py     fiscal years resolved to dates, in one place
  pins.py       rules that are not obvious, with the evidence for each
  renderer.py   parameter injection into the validated templates
  cases.py      A&E's seventeen questions, as text
  validation.py what each case returns, and why the open ones are open
  sql/          the twenty-two queries, verbatim from the notebooks
  templates/    the chat page and the benchmark page
  static/       stylesheet and front end
```

## Adding a query

Drop the file into `app/sql/`, add a `QuerySpec` in `specs.py`, and the router
picks it up: its menu is generated from the specs, so the prompt and the code
cannot drift apart. No agent code changes.
