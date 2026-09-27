"""CRISpy: a prompt goes in, a parameterised CRIS query comes out.

    intent  ->  route  ->  parameters  ->  resolve  ->  render
                              |               |
                              +-- missing? ---+-- ambiguous?
                                      |
                                   ask, and stop

Nothing here executes SQL. CRISpy plans and prints; running the query is a
person's decision, in Snowflake, with the parameter block in front of them.

## Carrying context between turns

A question rarely arrives alone. "How is Skinwalker Ranch doing" followed by
"what about last week" is one conversation, and treating the second as a fresh
question loses the programme.

What is not done is send the transcript to the model. That is how CRIS 2.0
produced its worst reported failure: a network from an unrelated question
earlier in a long conversation carried into a later one, and the answer looked
entirely normal. The interim advice to testers was to name the network every
time and start a new conversation per topic, which is a workaround for a design
problem rather than a fix.

Instead the client holds an explicit scope: network, programme, season, demo,
stream, date. A new question overwrites only the fields it mentions, everything
carried is labelled "carried from the previous question" in the panel, and one
button clears it. Carry-over that can be seen is carry-over that can be caught.

## Answering a question CRISpy asked

When the resolver cannot choose between two programmes it asks, and that reply
is not a new question: it is the missing piece of the plan already made. So the
pending plan is kept and the reply fills the hole, without going back through
intent and routing. Clicking a choice sends the PROGRAM_CODE rather than a
phrase, which removes the ambiguity outright rather than matching again and
hoping it lands differently.
"""

from __future__ import annotations

import asyncio
import datetime as dt
import json
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel

from .agents import classify_intent, clarify, extract_params, route

# How recently a programme must have aired to count as the one a present-tense
# question is about. Six months spans a full season gap, so a series between
# seasons still counts as current, while one that ended over a year ago does
# not. Wide enough to keep a hiatus, narrow enough to drop a finished show.
ACTIVE_WINDOW_DAYS = 183
from .catalog import NETWORKS, resolve_network
from .renderer import render
from .resolver import get_resolver
from .specs import SPECS

BASE = Path(__file__).parent

app = FastAPI(title="CRISpy", version="1.1", docs_url="/api")
app.mount("/static", StaticFiles(directory=BASE / "static"), name="static")
templates = Jinja2Templates(directory=BASE / "templates")


class Scope(BaseModel):
    """What survives from one question to the next.

    Deliberately short. Every field here is one a follow-up can inherit without
    changing what the question means, and nothing else is carried: the query
    type is re-decided every turn, because "and the quarter hours?" is a
    different question about the same subject rather than the same question.
    """
    network: str | None = None
    program: str | None = None
    program_code: str | None = None
    season: str | None = None
    demo: str | None = None
    stream: str | None = None


class Pending(BaseModel):
    """A question CRISpy asked, held open until it is answered."""
    field: str                    # what is missing: program, season, network
    question: str                 # the original question, replayed once filled
    query_ids: list[str] = []


from .cases import CASES as _TEST_CASES


class Ask(BaseModel):
    question: str = ""
    scope: Scope | None = None
    pending: Pending | None = None
    choice: dict | None = None    # a clicked option, already unambiguous


SAMPLES = [
    "How is Skinwalker Ranch doing?",
    "Give me the Overnight Summary for History on 6/12/26",
    "How did Lifetime do last night in W25-64?",
    "Which episode of World War II with Tom Hanks did worst?",
    "Quarter hours for A&E's premieres on 4/26/26",
    "How much did last night's premiere retain from its lead-in?",
]


@app.get("/")
async def index(request: Request):
    return templates.TemplateResponse(
        request,
        "index.html",
        {"samples": SAMPLES, "networks": NETWORKS, "specs": list(SPECS.values())},
    )


@app.get("/tests")
async def tests(request: Request):
    """The seventeen A&E questions on one page, run through the normal path.

    Every question here goes through /api/plan exactly as a typed one does. The
    page holds no expected output and no stored answer - it is a harness, not a
    fixture. What it removes is the transcription step, which matters because
    half of these turn on a single token: P25+ against P25-64 is the difference
    between 517 and 242, and a mistyped date passes silently.
    """
    return templates.TemplateResponse(
        request, "tests.html", {"cases": _TEST_CASES},
    )


@app.get("/healthz")
async def healthz():
    return {"ok": True}


# ==========================================================================
# resolution
# ==========================================================================

def resolve_params(p, notes: list[str], question: str = "") -> dict | None:
    """Check each extracted value against the resolver tables, in place.

    Returns a choice when the data cannot settle it, and None when it can.

    Three outcomes per field, and the middle one is why this exists. Resolved:
    the value becomes what the data actually holds, so a truncated title becomes
    the stored title and "season 7" becomes whichever string that series really
    uses. Ambiguous: a choice, because A&E decided sub-seasons are separate
    seasons and two networks carrying one title is a question rather than a tie.
    Not found: a note, and the query still runs, because the person may know
    something this snapshot does not.
    """
    r = get_resolver()

    if p.program:
        # a clicked choice arrives already resolved, so skip the matching
        if getattr(p, "program_code", None) and getattr(p, "source_program", None):
            hit = {"status": "resolved", "program_name": p.program,
                   "program_code": p.program_code, "network": p.network,
                   "match": "CHOSEN"}
        else:
            # A present-tense question is about something on air. Where that
            # settles an otherwise ambiguous match outright, take it: asking
            # someone to choose between a series that aired last week and one
            # that ended over a year ago, when they asked how it is doing, is
            # making them confirm the obvious.
            active_since = None
            if getattr(p, "asks_about_now", None) is True:
                active_since = (dt.date.today()
                                - dt.timedelta(days=ACTIVE_WINDOW_DAYS)).isoformat()
            hit = r.find_program(p.program, p.network, active_since=active_since)

        if hit["status"] == "resolved":
            # The stored title, not the phrase. A wildcard built from what the
            # person typed undoes the resolution: '%SKINWALKER%' matches both
            # SECRET SKINWALKER RANCH and BEYOND SKINWALKER RANCH, so a question
            # about one comes back as two series averaged together.
            p.program = hit["program_name"]
            p.program_code = hit["program_code"]
            if not p.network:
                # the network from the programme, which is the one inference
                # that is always safe: a programme airs where it airs
                p.network = hit["network"]
                p.source_network = "read from the programme"
                notes.append(f"Network read from the programme: {hit['network']}.")
            elif hit.get("network_corrected_from"):
                # [RESOLVER-NETWORK] the network was supplied and the data
                # disagrees. The data wins, because a programme airs where it
                # airs and a network nobody stated is a guess.
                #
                # SP_3 is the case: the question names no network, the model
                # offered HIST because Alaska State Troopers sounds like
                # History, the resolver found nothing in HIST and fell back to a
                # pattern. Two failures from one guess, and the second hid the
                # first.
                was = hit["network_corrected_from"]
                p.network = hit["network"]
                p.source_network = "corrected from the programme"
                notes.append(
                    f"{hit['program_name']} is on {hit['network']}, not {was}, "
                    f"so the network was corrected. {was} did not come from the "
                    "question."
                )
            elif p.network != hit["network"]:
                # supplied, found, and different: say so rather than run a query
                # that will come back empty
                notes.append(
                    f"{hit['program_name']} is on {hit['network']}, but the "
                    f"question was read as {p.network}. Running it on "
                    f"{p.network} would return nothing."
                )
            if hit["match"] not in ("EXACT", "CHOSEN"):
                notes.append(
                    f"Matched {hit['program_name']!r} in the data "
                    f"({hit['match'].replace('_', ' ').lower()})."
                )
            if hit.get("narrowed_by_recency"):
                # Answered rather than asked, so the candidate that was set
                # aside has to come back as one click. A note alone makes the
                # person who wanted the other one retype the whole question,
                # which is the cost of guessing right most of the time.
                p.source_program = "the one currently on air"
                p.alternatives = [
                    {
                        "label": c["program_name"],
                        "sub": " · ".join(filter(None, [
                            c["network"],
                            f"{c['telecasts']} telecasts" if c.get("telecasts") else None,
                            f"last aired {c['last_aired']}" if c.get("last_aired") else None,
                        ])),
                        "value": {"program": c["program_name"],
                                  "program_code": c["program_code"],
                                  "network": c["network"]},
                    }
                    for c in hit["narrowed_by_recency"]
                ]

        elif hit["status"] == "ambiguous":
            return {
                "field": "program",
                "message": hit["message"],
                "options": [
                    {
                        "label": c["program_name"],
                        "sub": " · ".join(filter(None, [
                            c["network"],
                            f"{c['telecasts']} telecasts" if c.get("telecasts") else None,
                            f"last aired {c['last_aired']}" if c.get("last_aired") else None,
                        ])),
                        "value": {"program": c["program_name"],
                                  "program_code": c["program_code"],
                                  "network": c["network"]},
                    }
                    for c in hit["candidates"][:8]
                ],
            }
        else:
            notes.append(hit.get("message", f"{p.program!r} not found in the data."))
            return None

        # season only means something once the programme is known
        code, net = hit.get("program_code"), p.network or hit.get("network")
        if code and net:
            sea = r.find_season(net, code, p.season)

            if sea["status"] == "resolved":
                if p.season and sea["ct_season"] != p.season:
                    notes.append(f"Season {p.season!r} is stored as "
                                 f"{sea['ct_season']!r}; using that.")
                    p.season = sea["ct_season"]
                    p.source_season = "corrected to how the data stores it"
                elif not p.season and getattr(p, "asks_about_now", None) is True:
                    # "How is X performing" is a question about now. Without a
                    # season pinned, 1.1 returns every telecast the programme
                    # ever aired: eighty-three rows answering a question nobody
                    # asked. The resolver already knows which season is current.
                    p.season = sea["ct_season"]
                    p.source_season = "current season, read as a question about now"
                    notes.append(
                        "Read as a question about now, so scoped to the current "
                        "season. Ask for a season by name, or for every season, "
                        "to widen it."
                    )
                notes.append(sea["scope"])

                # [PREMIERE-DATE] The first telecast of the season IS its
                # premiere, and the resolver has just worked out when that was.
                #
                # SP_7 is why this is here rather than in the classifier. "How
                # did the Season premiere of Hist Greatest Machines perform"
                # names no date: 1 June 2026 is nowhere in the words, it is a
                # fact about the data. The classifier was being asked for a
                # premiere_date it had no way to know, so it returned nothing,
                # so the norm pins had nothing to anchor to and stood down. They
                # said so rather than falling back quietly, which is why this was
                # visible at all.
                #
                # Only when the question is about a premiere. A season's start
                # date is not the premiere of anything if nobody asked about one,
                # and pinning a norm window off it would move a figure for a
                # reason the question never gave.
                if sea.get("season_from") and not getattr(p, "premiere_date", None):
                    if _asks_about_premiere(question):
                        p.premiere_date = sea["season_from"]
                        notes.append(
                            f"The season premiere is {sea['season_from']}, taken "
                            "from the data rather than the question. The norms are "
                            "cut the day before it, which is A&E's method."
                        )

            elif sea["status"] == "ambiguous":
                # A&E, week 10: sub-seasons are separate seasons. Picking one
                # contradicts that rather than approximating it.
                return {
                    "field": "season",
                    "message": sea["message"],
                    "options": [
                        {
                            "label": f"Season {s['ct_season']}",
                            "sub": f"{s['telecasts']} telecasts · {s['from']} to {s['to']}",
                            "value": {"season": s["ct_season"]},
                        }
                        for s in sea["seasons"]
                        if s["ct_season"] in sea.get("candidates", [])
                    ],
                }

            elif sea["status"] == "not_found" and p.season:
                notes.append(sea.get("message", ""))
                p.season = None

    if p.network:
        demo, source = r.default_demo(p.network)
        if not p.demo and source and "assumption" in source.lower():
            notes.append(
                f"{p.network} has no confirmed key demo; {demo} is a SiiRA "
                "assumption rather than an A&E decision."
            )
        night = r.latest_night(p.network, p.stream or "Live+SD")
        if night["status"] == "resolved" and not (p.target_date or p.report_from):
            notes.append(f"Latest night with data for {p.network}: {night['date']}.")
        if night.get("note"):
            notes.append(night["note"])

    return None


def _asks_about_premiere(question: str) -> bool:
    """[PREMIERE-DATE] Is this a question about a season premiere.

    Deliberate that this is a word match rather than a model call, for the same
    reason content_strand is: the phrase is in the question. What the model
    cannot supply is the DATE, and that comes from the data.
    """
    q = (question or "").lower()
    return ("season premiere" in q or "premiere of" in q
            or "premiered" in q or "series premiere" in q)


def apply_scope(p, scope: Scope | None, notes: list[str],
                query_id: str | None = None) -> None:
    """Fill blanks from the previous turn, and say which ones were filled.

    Only blanks. A question that names a network overrides a carried one, always,
    because the whole hazard of carry-over is a stale value winning over a stated
    one. And every field taken from scope is labelled in the panel, so a wrong
    inheritance is visible in the answer rather than buried in a number.

    [SCOPE-DEDUCIBLE] A blank is not always a blank. A programme identifies its
    network on its own, so when the question names one the network is not a hole
    to be filled from the last turn, it is a fact about to be worked out. Carrying
    it anyway does two kinds of damage at once, and SP_1 showed both:

        Q1  ...FYI...
        Q2  "What is the average for the latest season of Court Cam?"

    Court Cam is A&E. The old order filled the network from the previous turn
    before the resolver ran, so the resolver went looking for Court Cam inside
    FYI's catalogue, did not find it, and fell back to the pattern '%COURT%'.
    Two symptoms, one cause: a wrong network AND an unresolved programme. And a
    wrong network returns zero rows with no error, which reads as a series that
    is off the air.

    So the network is left alone whenever a programme is in view. The resolver
    deduces it a step later, and if what it deduces differs from what the last
    turn held, the programme wins and the note says so.

    This is the twin of the missing_required bug fixed earlier: that one asked
    for a field it was about to work out, this one carries a field it is about to
    work out. Both come from settling something before the resolver has spoken.
    """
    if not scope:
        return
    carried = []
    if not p.network and scope.network and not p.program:
        p.network = scope.network
        p.source_network = "carried from the previous question"
        carried.append(f"network {scope.network}")
    elif not p.network and scope.network and p.program:
        notes.append(
            f"The previous question was about {scope.network}, but this one names "
            f"{p.program}, so the network is taken from the programme instead of "
            "being carried over."
        )
    # [SCOPE-PROGRAM] two reasons a programme does not carry, and SP_4 hit both
    # at once: "Which LFT movie had the highest performance this Fiscal Year"
    # inherited ALASKA STATE TROOPERS AE from the question before it.
    #
    # One, a programme belongs to a network. When the question names a different
    # one, the previous title cannot still be the subject: Alaska State Troopers
    # is not on Lifetime, so carrying it turns a valid ranker into zero rows.
    #
    # Two, a ranker has no subject to inherit. "Which movie was highest" names no
    # programme because there is none to name; it asks about a field. p_program
    # on a ranker filters which row PRINTS, it does not scope what is ranked, so
    # a stale title does not narrow the answer, it deletes it. The ranker
    # computes over all 81 telecasts and the output filter throws them all away.
    #
    # Both failures are silent. An empty ranker reads as a network that aired
    # nothing.
    ranker = bool(query_id and SPECS.get(query_id) and SPECS[query_id].is_ranker)
    network_changed = bool(p.network and scope.network and p.network != scope.network)
    if not p.program and scope.program and not ranker and not network_changed:
        p.program = scope.program
        p.program_code = scope.program_code
        p.source_program = "carried from the previous question"
        carried.append(scope.program)
    elif not p.program and scope.program and ranker:
        notes.append(
            f"{scope.program} was not carried into this one: it asks for a "
            "ranker, and a ranker has no single programme as its subject. "
            "Naming one here would filter the result down to it rather than "
            "narrow what is ranked."
        )
    elif not p.program and scope.program and network_changed:
        notes.append(
            f"{scope.program} was not carried into this one: it is a "
            f"{scope.network} programme and this question is about {p.network}."
        )
    if not p.season and scope.season and p.program == scope.program:
        # season only carries with its programme: season 7 of one series is not
        # season 7 of another
        p.season = scope.season
        p.source_season = "carried from the previous question"
        carried.append(f"season {scope.season}")
    # [SCOPE-FOLLOWUP] Demo and stream carry only into a genuine follow-up.
    #
    # A question that names a DIFFERENT programme is not a follow-up. It is
    # another question that happens to come after this one, and nothing in it
    # should be inherited.
    #
    # This is the bug that ran four cases on the wrong stream. SP_5 asks for the
    # L+3 lift, legitimately. SP_6, SP_7, SP_8 and SP_9 each name a different
    # programme and mention no stream, and all four inherited Live+3. Every
    # figure A&E publish is Live+SD, so all four would have come back different
    # and none of them would have said why.
    #
    # "And in March?" or "and in W25-54?" still inherit, because those name no
    # programme and are the case carry-over exists for.
    # A change in EITHER direction. SP_6 slipped through the first version of
    # this because SP_5 named no programme at all - it asked about a slate - so
    # the scope held nothing to compare against and Live+3 carried into a
    # question about World War II. Naming a programme where the last turn had
    # none is just as much a new question as swapping one for another.
    _prog = (p.program or "").strip().upper()
    _prev = (scope.program or "").strip().upper()
    new_question = bool((_prog or _prev) and _prog != _prev)
    if not p.demo and scope.demo and not new_question:
        p.demo = scope.demo
        p.source_demo = "carried from the previous question"
        carried.append(scope.demo)
    if not p.stream and scope.stream and not new_question:
        p.stream = scope.stream
        p.source_stream = "carried from the previous question"
        carried.append(scope.stream)
    if new_question and (scope.demo or scope.stream):
        subject = p.program or "This"
        notes.append(
            f"{subject} is not what the last question was about, so this was "
            "read as a new question rather than a follow-up: the demo and the "
            "stream were not carried over."
        )
    if carried:
        notes.append("Carried from the previous question: " + ", ".join(carried) + ".")


def scope_from(p) -> dict:
    """What survives into the next question.

    [SCOPE-DEDUCIBLE] Deliberately no date and no report range. A stale network
    empties a result, which is at least visible once you look; a stale date fills
    it with the wrong night, which is not visible at all. Anything whose wrongness
    would be silent stays out of scope and is asked for or defaulted instead.
    """
    return {
        "network": p.network,
        "program": p.program,
        "program_code": getattr(p, "program_code", None),
        "season": p.season,
        "demo": p.demo,
        "stream": p.stream,
    }


# ==========================================================================
# the pipeline, as a generator so each step can be shown as it lands
# ==========================================================================

async def run(ask: Ask):
    """Yield one event per step. The final event carries the answer.

    A generator rather than a function because the pipeline makes three model
    calls and takes several seconds, and a spinner for that long tells the person
    nothing. Naming each step as it completes shows what CRISpy understood while
    it is still deciding, which is also the fastest way to catch it understanding
    the wrong thing.
    """
    today = dt.date.today().isoformat()
    scope = ask.scope
    notes: list[str] = []

    # ---- a clicked choice: fill the hole, do not re-plan ------------------
    if ask.choice and ask.pending:
        yield {"type": "step", "step": "Choice",
               "detail": "Filling in the answer and rerunning the plan already made."}
        question = ask.pending.question
        query_ids = ask.pending.query_ids
        param_sets = await asyncio.gather(
            *(extract_params(question, qid, today) for qid in query_ids)
        )
        for p in param_sets:
            for k, v in (ask.choice or {}).items():
                setattr(p, k, v)
            if "program_code" in (ask.choice or {}):
                p.source_program = "chosen from the options offered"
                if "network" in (ask.choice or {}):
                    # the network arrived attached to the programme that was
                    # picked, so it was not stated either
                    p.source_network = "from the programme chosen"
            if "season" in (ask.choice or {}):
                p.source_season = "chosen from the options offered"
            apply_scope(p, scope, notes, query_ids[0] if query_ids else None)
    else:
        question = (ask.question or "").strip()
        if not question:
            yield {"type": "final", "payload": {"kind": "empty",
                   "message": "Ask a ratings question to get started."}}
            return

        # ---- 1. what kind of message is this ------------------------------
        intent = await classify_intent(question)
        yield {"type": "step", "step": "Intent", "detail": intent.reasoning}

        if intent.kind == "small_talk":
            yield {"type": "final", "payload": {
                "kind": "message",
                "message": (
                    "CRISpy plans Section 1 queries: overnight premieres against "
                    "season norms, quarter-hour movement, lead-in retention, the "
                    "daypart rollup, and season detail. Ask about a night, a "
                    "network or a series."
                )}}
            return
        if intent.kind == "out_of_scope":
            yield {"type": "final", "payload": {
                "kind": "message",
                "message": (
                    "That one is outside what CRISpy covers. It answers linear TV "
                    "performance questions for A&E, History, Lifetime, LMN, FYI "
                    "and VICE."
                )}}
            return

        # ---- 2. which queries answer it -----------------------------------
        routed = await route(question)
        yield {"type": "step", "step": "Router", "detail": routed.rationale}

        if not routed.query_ids:
            yield {"type": "final", "payload": {
                "kind": "message",
                "message": (
                    "No Section 1 query covers that. Section 1 handles the "
                    "overnight: premieres against season norms, quarter hours, "
                    "lead-in retention, the daypart rollup and season detail. "
                    "Competitive ranks and prior-season comparisons live in "
                    "Sections 2 and 3."
                )}}
            return

        query_ids = routed.query_ids

        # ---- 3. parameters, one agent per query ----------------------------
        param_sets = await asyncio.gather(
            *(extract_params(question, qid, today) for qid in query_ids)
        )
        for p in param_sets:
            # A&E write LFT for Lifetime, and the model was given the codes
            # rather than the abbreviations, so it hands back either an alias or
            # nothing. Map it here: an unrecognised code reaches SQL as a
            # filter that matches no rows, which is the silent failure this
            # whole layer exists to prevent.
            if p.network:
                code = resolve_network(p.network)
                if code:
                    if code != p.network:
                        notes.append(f"Read {p.network!r} as {code}.")
                    p.network = code
                else:
                    notes.append(
                        f"{p.network!r} is not one of the six networks, so it "
                        "was dropped rather than passed to the query."
                    )
                    p.network = None
            apply_scope(p, scope, notes, query_ids[0] if query_ids else None)
            # Recomputed after the scope fills blanks. It used to be settled
            # inside the extraction, before carry-over ran, so a field the
            # previous turn had already answered still came back as missing and
            # CRISpy asked for something it was holding.
            #
            # A named programme excuses the network, because the resolver reads
            # it from the programme a step later and a programme airs where it
            # airs. Asking first would be asking for something about to be
            # worked out.
            p.missing_required = [
                f for f in SPECS[query_ids[0]].required
                if not getattr(p, f, None)
                and not (f == "network" and p.program)
            ]

        stated = [f for f in ("network", "program", "season", "demo", "stream")
                  if getattr(param_sets[0], f, None)]
        yield {"type": "step", "step": "Parameters",
               "detail": ("Read from the question: " + ", ".join(stated)
                          if stated else "Nothing named; every default applies.")}

        missing: list[str] = []
        for p in param_sets:
            for f in p.missing_required:
                if f not in missing:
                    missing.append(f)
        if missing:
            yield {"type": "final", "payload": {
                "kind": "clarify",
                "message": await clarify(question, missing),
                "pending": {"field": missing[0], "question": question,
                            "query_ids": query_ids},
                "options": ([{"label": code, "sub": meta["name"],
                              "value": {"network": code}}
                             for code, meta in NETWORKS.items()]
                            if "network" in missing else []),
            }}
            return

    # ---- 4. resolve against the data --------------------------------------
    # The step CRISpy did not have. Up to here every parameter is a claim read
    # out of a question; this is where each one is checked against what the
    # warehouse actually holds. A value nobody verified produces zero rows and
    # no error, which reads exactly like a quiet week.
    choice = None
    for p in param_sets:
        choice = resolve_params(p, notes, question) or choice
    yield {"type": "step", "step": "Resolver",
           "detail": (choice["message"] if choice
                      else (notes[-1] if notes else "Every value checked against the data."))}

    if choice:
        yield {"type": "final", "payload": {
            "kind": "clarify",
            "message": choice["message"],
            "options": choice["options"],
            "pending": {"field": choice["field"], "question": question,
                        "query_ids": query_ids},
        }}
        return

    # ---- 5. render ---------------------------------------------------------
    results = [render(qid, p, today) for qid, p in zip(query_ids, param_sets)]
    for r in results:
        r["notes"] = list(r.get("notes", [])) + notes

    alts = getattr(param_sets[0], "alternatives", None)
    yield {"type": "final", "payload": {
        "kind": "plan",
        "results": results,
        "scope": scope_from(param_sets[0]),
        # a candidate answered past rather than asked about, offered as one click
        "alternatives": alts or [],
        "pending": ({"field": "program", "question": question,
                     "query_ids": query_ids} if alts else None),
    }}


@app.post("/api/plan")
async def plan(ask: Ask):
    """Server-sent events, one per step, ending with the answer."""

    async def stream():
        steps = []
        try:
            async for ev in run(ask):
                if ev["type"] == "step":
                    steps.append({"step": ev["step"], "detail": ev["detail"]})
                    yield f"data: {json.dumps(ev)}\n\n"
                else:
                    payload = dict(ev["payload"])
                    payload["trace"] = steps
                    yield f"data: {json.dumps({'type': 'final', 'payload': payload})}\n\n"
        except Exception as exc:                     # noqa: BLE001
            yield "data: " + json.dumps({
                "type": "final",
                "payload": {
                    "kind": "message",
                    "message": f"The planner stopped: {exc}",
                    "trace": steps,
                },
            }) + "\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache",
                                      "X-Accel-Buffering": "no"})
