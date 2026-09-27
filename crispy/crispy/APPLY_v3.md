# CRISpy patch 3 — follow-ups, choices, streaming

Unzip over the project root, then:

    docker compose up -d --build

Hard-reload afterwards (Ctrl+Shift+R). The JS, CSS and template all changed.

## Files

    app/main.py              rewritten: scope, pending questions, SSE
    app/resolver.py          structured choices, recency narrowing
    app/agents.py            asks_about_now, provenance fields, A&E shorthand
    app/specs.py             routing triggers for 1.1 and 1.4
    app/renderer.py          exact titles, provenance per field
    app/static/app.js        rewritten: event stream, buttons, scope bar
    app/static/app.css       styling, and softer corners throughout
    app/templates/index.html composer nesting, the drumstick mark, and the
                             textarea is no longer `required` because a clicked
                             choice submits with it empty
    app/data/*.csv           unchanged, included so the folder is complete

## What changed

**Follow-ups work.** The client holds a scope: network, programme, season, demo,
stream. A new question overwrites only what it names, and everything inherited
is labelled "carried from the previous question" in amber. A bar above the
composer shows what the next question will inherit, with a Clear button.

The transcript is deliberately not sent to the model. That is how CRIS 2.0
produced its worst reported failure: a network from an unrelated question
carried into a later one and the answer looked entirely normal. Carry-over that
can be seen is carry-over that can be caught.

Two rules inside it. A stated value always beats a carried one, because the
hazard is a stale value winning over a fresh one. And a season only carries with
its programme, since season 7 of one series is not season 7 of another.

**Answering CRISpy's own question no longer restarts the plan.** The pending
plan is held and the reply fills the hole, skipping intent and routing.

**Choices are buttons.** Clicking sends the PROGRAM_CODE rather than a phrase,
so the ambiguity is removed outright rather than matched again.

**A present-tense question resolves to the series that is on air.** "How is
Skinwalker Ranch doing" matched SECRET, which aired last week, and BEYOND, which
last aired over a year ago, and asked which. One of them is not doing anything.
When the question is present tense and exactly one candidate has aired in the
last six months, it answers with that one and offers the other as a single
button underneath: *Did you mean BEYOND SKINWALKER RANCH · HIST · 8 telecasts ·
last aired 2025-07-22*.

Answering rather than asking is only right if the other option stays one click
away. A note alone would make whoever wanted the other one retype the question,
which is the cost of guessing right most of the time.

It narrows only when that settles it outright: three candidates down to two
still gets asked. And a question that is not present tense still gets the full
list, because asking about a series that ended is a fair question.

**The ambiguity message says what would actually resolve it.** It used to read
"naming the network resolves it" regardless, which is false when both matches
are on the same network: SECRET and BEYOND are two different HIST series and no
network name separates them.

**Three bugs found on "Premieres on LFT on 2/7/26".**

LFT is A&E's own shorthand for Lifetime and the model had only been given the
codes, so it discarded the network rather than returning something unrecognised.
Whatever it returns is now mapped through the alias table, and a network that
maps to nothing is dropped with a note rather than passed to SQL, where it would
have become a filter matching no rows.

`missing_required` was settled inside the extraction, before carry-over ran, so
a field the previous turn had already answered still came back as missing and
CRISpy asked for something it was holding. It is recomputed after the scope
fills the blanks.

And the router sent it to 1.4, the daypart rollup, which cannot answer a
question about premieres: it reports dayparts rather than telecasts. 1.4 is the
fallback for when 1.1 comes back empty, not a general night-level answer, and
both triggers now say so. This is the failure the validation log named first:
six of fifteen questions routed to a template that could not answer them even in
principle.

**The pipeline streams.** Three model calls take several seconds, and a spinner
says nothing for that long. Each step appears as it lands — Intent, Router,
Parameters, Resolver — so what CRISpy understood is visible while it is still
deciding, which is the fastest way to catch it understanding the wrong thing.

**Softer corners, and a drumstick.** Cards, buttons and the composer are rounded
now, and chips are pills. The wordmark has a drumstick beside it: the only thing
on the page not trying to be serious, which suits a tool whose job is making the
serious part checkable.

## Try it

1. **How is Skinwalker Ranch doing?** — answers with SECRET, and offers BEYOND
   as a button underneath.
2. **Click BEYOND** — re-answers for that series without asking anything.
3. **Quarter hours** — two words. Inherits network, programme and season, all
   marked *carried from the previous question* in amber, with the bar above the
   composer showing them.
4. **Compare every season of Skinwalker Ranch** — not present tense, so it asks
   properly and shows both.
5. **Clear**, then something unrelated — nothing inherited.
6. **Premieres on LFT on 2/7/26** — should route to 1.1, read LFT as LIF, and
   answer without asking which network. The benchmark expects one row: MOVIE-
   ORIGINAL PREM, Mary J. Blige: Be Happy, 227 against a norm of 138 over 13
   telecasts, +64.5%.
