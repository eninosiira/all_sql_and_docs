# cris-queries

The SQL behind CRIS, A&E Networks' ratings assistant: the Snowflake tables it reads, the 22 queries that answer its questions, the benchmark that proves they reproduce A&E's published figures, and CRISpy, the planner that turns a question into one of those queries with the right parameters.

Everything runs on Snowflake against `AUDIENCE_DB.UBD` (Nielsen, read only) and writes to `AUDIENCE_DEV_DB.CRIS`.

## What is in here

```
tables/      CRIS_Tables_vNN.ipynb            builds the six prepared tables
queries/     CRIS_SectionN_Queries_vNN.ipynb  the 22 queries, one cell each, set to an A&E case
             CRIS_SectionN_Queries_vNN.docx   the same, with parameters explained, for sharing
benchmark/   CRIS_Benchmark_Run_vNN.ipynb     the 32 A&E questions as CRISpy generates them
             CRIS_Benchmark_Results_vNN.xlsx  expected vs obtained, one tab per case
crispy/      the planner: routes a question, fills the parameters, renders the SQL
docs/        routing logic, knowledge transfer, change logs
```

Every file in a release carries the same version number. If the tables say v70, the queries say v70.

## The tables

Six tables, built in this order. The first three are copies of the Nielsen views, deduplicated, with the columns the queries need added once.

| table | one row is | built from |
|---|---|---|
| `CRIS_TELECAST_FACT` | one telecast, in one stream | the total-programme view |
| `CRIS_HALFHR_FACT` | one half hour of a telecast | the half-hour view, last 3 years |
| `CRIS_QH_FACT` | one quarter hour of a telecast | the quarter-hour view |
| `CRIS_LATEST_DATE` | one network and stream | the three above |
| `CRIS_NETWORK_UNIVERSE` | one network | the half-hour fact |
| `CRIS_FY_CALENDAR` | one fiscal year | A&E's `Dim_DATE` |

The rule the tables follow: classifications become columns, filters stay in the queries. A table records that a telecast is a movie, a special, a first run; it never throws one away. Whether a question includes movies is decided by the query.

Three decisions from A&E are baked in:

- **Cable Tracks decides what a premiere is.** `IS_FIRST_RUN_CT` is TRUE when Cable Tracks has catalogued the telecast; a telecast it has not catalogued is a repeat, whatever Nielsen's flag says. `IS_PREMIERE_CT` is the first first-run telecast of a season. Nielsen's `REPEAT_IND` and `IS_SEASON_PREMIERE` stay on the tables for comparison and no query reads them. Jill, 11 Sep 2026.
- **Every average is duration weighted.** Any aggregation of more than one row weights by `CONTRIBUTING_DURATION`, `HH_MIN` or `QH_MIN`. Adarsh, 11 Sep 2026.
- **The broadcast day runs 6am to 6am**, on Nielsen's 0600-2959 clock. `BROADCAST_DATE` is the date, never `CALENDAR_DATE`.

Rebuild only after Nielsen's loads have finished. Run the check cells at the end of the notebook afterwards.

## The queries

Twenty-two, by PRD section. Each opens with a `SET` block of parameters; every parameter is override-able, `NULL` takes the default.

**Section 1, the overnight summary:** 1.1 premieres vs season norms, 1.2 quarter-hour movement, 1.3 Lifetime movie retention norm, 1.3b lead-in retention vs season norm, 1.4 network daypart rollup, 1.5 additional programme data.

**Section 2, series performance:** 2.1 vs prime norm, 2.2 vs premiere norm, 2.4 vs prior season, 2.5 median age, 2.6 M/F skew, 2.7 Live+3 lift, 2.8 rank among premieres, 2.9 network rank in the time period, 2.10 vs lead-in, 2.11 quarter hour, 2.12 telecast level, 2.13 repeats vs daypart.

**Section 3, competitive rankers:** 3.1 series rank in the network's time period, 3.2 network ranks by daypart, 3.3 series genre ranker, 3.4 telecast ranker.

Defaults that matter:

- Network norms run the latest 12 months, ending on the most recent Sunday with data. Season norms are scoped by season identity, not by calendar.
- Prime is 8p-11p. The premiere norm is 8p-12a, first runs, no specials, no mini-series, no Curse of Oak Island on HIST.
- A half hour belongs to a series' time period only if the series contributed 15 minutes to it (`p_slot_min_min`).
- A season premiere is one telecast, the first of the season, against the premiere norm (`p_premiere_only` on 2.2).
- Rankers return the whole universe in rank order, with the asked programme or network marked in `IS_TARGET`. Ties are shown as `7 (tied)`.

Output columns follow A&E's format: audience figures end in `_000`, the dates a figure covers are `FROM_DATE` and `TO_DATE`, norm dates are `NORM_FROM` and `NORM_TO`, and `DEMO_USED` says which demo the query measured.

## The benchmark

Thirty-two questions from A&E's validation workbook. `CRIS_Benchmark_Run` renders each one exactly as CRISpy would and runs it in Snowflake; `CRIS_Benchmark_Results` records expected against obtained. As of v70, 19 of the 20 cases with a published figure match exactly.

Run it after any change to a query, a default, a prompt or a table. Routing that was right can stop being right, and the run is the only way to know.

## CRISpy

The planner. A question goes through three steps: intent (is this a ratings question), route (which of the 22 queries), and parameters (what did the question name, and what does its wording imply). It never writes SQL; it fills the `SET` block of a query file and returns the result with every parameter it used.

```
docker compose up -d --build
```

`/tests` runs the 32 benchmark questions through the same path as a typed question. `docs/CRIS_Routing_Logic.docx` explains the rules and carries the prompt text verbatim.

The SQL files under `crispy/app/sql` are the production copies. They carry neutral defaults; the benchmark cases live only in the notebooks and documents, applied when those are generated.

## Working with it

- To change a query, change the file under `crispy/app/sql`, regenerate the notebooks and documents, bump the version on everything, re-run the benchmark.
- To add a parameter the planner should set, add the field to `agents.py`, the flag to `renderer.py`, the pin to `pins.py` and the parameter to `specs.py`. `p_premiere_only` is the pattern.
- A parameter the planner does not extract falls to the file default. Keep defaults neutral: dates and seasons `NULL`, flags `FALSE`.
