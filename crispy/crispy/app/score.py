"""Score the reading and the classifying steps against A&E's eighteen cases.

    python -m app.score            everything
    python -m app.score SP_4 SP_7  just those

What it measures, and why the two are reported separately.

The READING step is transcription, so a miss there is a field that was invented
or dropped. The one that matters most is the network: a wrong network returns
zero rows with no error, which reads as a series that is off the air.

The CLASSIFYING step is judgement, and its misses are quieter. A movie question
not flagged as one returns an empty result. A season premiere with no premiere
date gets a norm over the wrong window and still looks right. Four booleans and a
date decide whether the parameters that reproduce A&E's method get applied at
all, so this is the score to watch when tuning the prompt.

Neither number says the SQL is wrong. The SQL reproduces seventeen of the
eighteen and that is settled. This measures whether a question in plain English
arrives at the parameters that were proved to work.
"""

from __future__ import annotations

import asyncio
import re
import sys

from .agents import extract_params, route
from .catalog import resolve_demo, resolve_stream
from .renderer import render
from .validation import CASES, BY_CODE

TODAY = "2026-08-12"

# Fields the reading step is graded on. program is compared loosely, because the
# resolver is what turns a phrase into a stored title and that is not this
# step's job: "Alaska State Trooper" is a correct reading of a question that
# says Alaska State Trooper, even though the data holds ALASKA STATE TROOPERS AE.
READ_FIELDS = ["network", "program", "season", "demo", "stream",
               "win_from", "win_to", "top_n", "genre"]
SIGNAL_FIELDS = ["is_movie_question", "names_fiscal_year",
                 "has_published_cutoff", "premiere_date"]

# [BRIDGE-CHECK] Which SET line each extracted field is supposed to become.
#
# This is the third thing scored, and it exists because the first two both
# passed while the answer was wrong. R_1 asks for the top 3 thru 6/28/26. The
# reader extracted top_n 50 and win_to 2026-06-28, validation.py expected
# exactly those, the comparison agreed, and the SQL came out with p_top_n 20 and
# p_win_to NULL because the renderer had no bridge for either.
#
#     question -> [extraction] -> [renderer] -> SQL
#                  scored                        not scored
#
# Two verified points with nobody watching the span between them. The same shape
# as the panel bugs: a value transformed or dropped between where it is produced
# and where it is used, and no test looking at the join.
#
# p_stream is here under both names, because Section 1 calls it p_rating_src and
# Sections 2 and 3 call it p_stream, and only one of the two was mapped for
# thirteen queries.
BRIDGE = {
    "network": ("p_network",),
    "season": ("p_season",),
    "demo": ("p_demo",),
    "stream": ("p_stream", "p_rating_src"),
    "top_n": ("p_top_n",),
    "win_from": ("p_win_from",),
    "win_to": ("p_win_to",),
    "genre": ("p_genre",),
}


def _bridge_misses(p, sql: str) -> list[str]:
    """Fields the reader produced that never reached a SET line.

    A field the query does not take is not a miss: 3.3 has no p_network and is
    right not to, because it ranks over the whole competitive set. What counts
    is a field the query DOES take, arriving with a value, and the SET line
    still carrying something else.
    """
    out = []
    for field, names in BRIDGE.items():
        val = getattr(p, field, None)
        if val in (None, "", []):
            continue
        # Three fields are TRANSLATED on the way in, deliberately, so the raw
        # word would never appear in the SQL and comparing against it would
        # report a miss on every correct run. Resolve them the same way the
        # renderer does before comparing: a demo label becomes a column name, a
        # stream shorthand becomes a currency, and a genre becomes a LIKE
        # pattern.
        if field == "demo":
            col, _ = resolve_demo(str(val), getattr(p, "network", None))
            if not col:
                continue                  # unrecognised: the query keeps its own
            val = col
        elif field == "stream":
            val = resolve_stream(str(val))
        elif field == "genre":
            val = str(val).strip().upper().replace(" ", "%").replace("-", "%")
        line = None
        for n in names:
            m = re.search(rf"^SET {n}\s*=\s*([^;]+);", sql, re.M)
            if m:
                line = m.group(1).strip()
                break
        if line is None:
            continue                      # not a parameter of this query
        if str(val).strip().upper().strip("'%") not in line.upper():
            out.append(f"{field}={val!r} extracted, but {names[0]} reads {line}")
    return out


def _norm(v):
    if v is None:
        return None
    if isinstance(v, bool):
        return v
    return str(v).strip().upper()


def _loose_program(got, want) -> bool:
    """A phrase matches if either contains the other, once punctuation is gone."""
    if not want:
        return not got
    if not got:
        return False
    a = "".join(c for c in str(got).upper() if c.isalnum() or c == " ").split()
    b = "".join(c for c in str(want).upper() if c.isalnum() or c == " ").split()
    return bool(set(a) & set(b))


async def score_one(case) -> dict:
    r = await route(case.question)
    routed = list(r.query_ids or [])
    # A case answered by several queries counts as routed if the router picked
    # any of them: SP_7 needs three, and which one comes first is the answer
    # layer's business rather than the router's.
    qid = routed[0] if routed else case.query_ids[0]

    p = await extract_params(case.question, qid, TODAY)

    read_misses, signal_misses = [], []

    for f in READ_FIELDS:
        want = case.params.get(f)
        got = getattr(p, f, None)
        if f == "program":
            ok = _loose_program(got, want)
        elif want is None:
            # An invented value is a miss even when nothing was expected. This is
            # the SP_3 failure and it has to count against the score.
            ok = got is None
        else:
            ok = _norm(got) == _norm(want)
        if not ok:
            read_misses.append(f"{f}: got {got!r}, expected {want!r}")

    for f in SIGNAL_FIELDS:
        want = case.params.get(f)
        got = getattr(p, f, None)
        # a null flag and a false flag mean the same thing to the pins
        if want in (None, False) and got in (None, False):
            continue
        if _norm(got) != _norm(want):
            signal_misses.append(f"{f}: got {got!r}, expected {want!r}")

    sql = render(qid, p, TODAY)["sql"]

    return {
        "code": case.code,
        "bridge_misses": _bridge_misses(p, sql),
        "routed": qid,
        "route_ok": bool(set(routed) & set(case.query_ids)),
        "all_routed": "/".join(routed) or "(none)",
        "expected_route": "/".join(case.query_ids),
        "read_misses": read_misses,
        "signal_misses": signal_misses,
    }


async def main(codes: list[str]) -> None:
    cases = [BY_CODE[c] for c in codes] if codes else CASES
    results = await asyncio.gather(*(score_one(c) for c in cases))

    route_ok = sum(r["route_ok"] for r in results)
    read_ok = sum(not r["read_misses"] for r in results)
    sig_ok = sum(not r["signal_misses"] for r in results)
    bridge_ok = sum(not r["bridge_misses"] for r in results)
    n = len(results)

    for r in results:
        flag = "ok  " if (r["route_ok"] and not r["read_misses"]
                          and not r["signal_misses"]
                          and not r["bridge_misses"]) else "MISS"
        print(f"{flag} {r['code']:6} -> {r['routed']}")
        if not r["route_ok"]:
            print(f"       route: got {r['all_routed']}, "
                  f"expected {r['expected_route']}")
        for m in r["read_misses"]:
            print(f"       read:   {m}")
        for m in r["signal_misses"]:
            print(f"       signal: {m}")
        for m in r["bridge_misses"]:
            print(f"       bridge: {m}")

    print()
    print(f"routing     {route_ok}/{n}")
    print(f"reading     {read_ok}/{n}")
    print(f"classifying {sig_ok}/{n}")
    print(f"bridge      {bridge_ok}/{n}")
    print()
    print("A miss in reading is a field invented or dropped. A miss in "
          "classifying is a pin that will not fire, which shows up as an empty "
          "result or as a norm over the wrong window rather than as an error. A "
          "miss in the bridge is a value the reader got right that never reached "
          "the SQL, which is invisible in both of the other two.")


if __name__ == "__main__":
    asyncio.run(main([a.upper() for a in sys.argv[1:]]))
