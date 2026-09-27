"""Wrappers: SQL that sits on top of a query's result, not beside it.

Some questions are a query plus a reading. "Top 3 non-fiction shows PER NETWORK,
and where do they rank in the cable set" is one ranker and two groupings of it.
The figures are already right; what is missing is a shape.

The obvious way to get that shape is to let the model write SQL. This is the
other way, and the difference is worth being exact about.

A wrapper never touches the rules. It takes the query verbatim, as a CTE, and
reads its output columns. Everything the query knows stays inside it: that a
programme ranker ranks premieres only, that CT_GENRE_2 SPORTS comes out, that
identity is PROGRAM_CODE and never the truncated name, that a norm runs from the
fiscal year start to the day before the premiere and is clipped to prime. Roughly
twenty-five rules, at least eight of which cannot be derived from the schema
because they were reconstructed from figures A&E published.

A generated query would have to carry all of them and would look correct without
any of them. That is the failure mode this project has spent weeks on: no error,
rows returned, a different number.

A wrapper cannot make that mistake. The worst it can do is group or cut wrongly,
and both are visible in the first row of the result.

So the model chooses a shape from a named set. It does not write one.

WHAT A WRAPPER NEEDS FROM THE QUERY UNDER IT

Depth. The wrapper reads what the query returned, so anything cut before it is
gone. R_1 is the case: A&E's own answer puts Lifetime's second title at rank 368
of the cable set. A ranker capped at 50 has nothing for the wrapper to group, and
Lifetime comes back empty rather than short.

So a wrapper raises the depth of the query beneath it, and the fine cut happens
on top. Deep below, narrow above.
"""

from __future__ import annotations
from dataclasses import dataclass


@dataclass(frozen=True)
class Wrapper:
    name: str
    applies_to: tuple          # query ids this shape makes sense on
    triggers: str              # how the router recognises it, in words
    min_depth: int             # what the inner query has to reach
    why: str
    sql: str                   # {inner} is the query, verbatim


TOP_N_PER_GROUP = Wrapper(
    name="top_n_per_group",
    applies_to=("3.3", "3.4"),
    triggers=(
        "top N per network, top N of each network, the best three on each of "
        "these networks, how do our shows rank on each network. Anything asking "
        "for a few from EACH of several groups rather than a few overall."
    ),
    min_depth=500,
    why=(
        "A&E's R_1 asks for the top 3 non-fiction shows per network AND where "
        "those sit in the cable competitive set. Both halves come from one "
        "ranker: the second is the RNK the query already returns, and the first "
        "is a rank within each network's own rows.\n"
        "\n"
        "Depth 500 rather than the 50 the question implies, because the ranker "
        "is scored across the whole competitive set and the per-network cut "
        "happens afterwards. Lifetime's second title is at cable rank 368 on "
        "A&E's own answer, so a ranker capped at 50 returns nothing for Lifetime "
        "at all. Cut deep below and narrow on top."
    ),
    sql="""WITH ranked AS (
{inner}
)
SELECT
    NETWORK,
    PROGRAM,
    AA_K,
    -- the rank inside the network, which is what "top 3 per network" asks for
    ROW_NUMBER() OVER (PARTITION BY NETWORK ORDER BY AA_K DESC) AS RANK_IN_NETWORK,
    -- and the rank the inner query already computed across the whole set, which
    -- is the second half of the question and would be destroyed by filtering
    -- the universe down to these networks
    RNK                                                          AS RANK_IN_CABLE,
    TELECASTS,
    GENRE
FROM ranked
WHERE ($w_groups IS NULL
       OR ARRAY_CONTAINS(NETWORK::VARIANT, SPLIT($w_groups, ',')))
QUALIFY RANK_IN_NETWORK <= $w_per_group
ORDER BY NETWORK, RANK_IN_NETWORK""",
)


ABOVE_AVERAGE = Wrapper(
    name="above_average",
    applies_to=("2.12",),
    triggers=(
        "which episodes beat the average, which were above the season average, "
        "which ones underperformed. A comparison of every row against a figure "
        "the query already puts on every row."
    ),
    min_depth=0,
    why=(
        "SP_3 asks which episodes of Alaska State Trooper exceeded the season "
        "average. 2.12 returns all ten telecasts with SEASON_AVG_K on every row "
        "and the percentage already computed, so the answer is a filter on a "
        "column rather than a calculation.\n"
        "\n"
        "It is written down as a wrapper anyway, because doing it in the answer "
        "layer means the six rows are chosen somewhere nobody can review, and "
        "the direction is easy to invert: SP_6 asks for the LOWEST, on the same "
        "query, and EP_RANK runs highest first."
    ),
    sql="""WITH telecasts AS (
{inner}
)
SELECT *
FROM telecasts
WHERE ($w_direction = 'ABOVE' AND VS_SEASON_AVG_PCT > 0)
   OR ($w_direction = 'BELOW' AND VS_SEASON_AVG_PCT < 0)
ORDER BY AA_K DESC""",
)


WRAPPERS: dict[str, Wrapper] = {
    w.name: w for w in (TOP_N_PER_GROUP, ABOVE_AVERAGE)
}


def wrappers_for(query_id: str) -> list[Wrapper]:
    return [w for w in WRAPPERS.values() if query_id in w.applies_to]


def wrap(inner_sql: str, wrapper: Wrapper, params: dict) -> tuple[str, list[str]]:
    """Put the query inside the wrapper, and set the wrapper's own parameters.

    The inner query is indented and otherwise untouched, including its comments,
    so what runs is visibly the query that was reviewed. A wrapper that rewrote
    the thing underneath it would be a generated query wearing a costume.

    The inner QUALIFY has to go: it cuts at p_top_n before the wrapper can see
    anything, and the whole point is to cut deep below and narrow on top.
    """
    notes: list[str] = []

    body = inner_sql
    # lift the inner cut, and say so
    import re
    m = re.search(r"^QUALIFY RNK <= \$p_top_n\s*$", body, re.M)
    if m:
        body = body[:m.start()] + "-- QUALIFY lifted: the wrapper cuts instead\n" + body[m.end():]
        notes.append(
            "The ranker's own cut was lifted so the grouping happens over the "
            "full ranking. Cutting at the query and again at the wrapper would "
            "hide every row past the first cut, which on A&E's own R_1 answer "
            "would lose Lifetime entirely: its second title is at cable rank 368."
        )

    body = body.rstrip().rstrip(";")

    # The inner query's SET statements have to stay at the top level. Snowflake
    # will not take a SET inside a WITH, so the two halves are separated here:
    # everything up to the first WITH or SELECT is preamble and runs first, and
    # only the SELECT body goes inside the CTE.
    #
    # The preamble is left exactly as it is, comments and all, because it is the
    # part carrying the parameters someone reviewed.
    lines = body.splitlines()
    cut = next((i for i, l in enumerate(lines)
                if l.startswith(("WITH ", "SELECT"))), 0)
    preamble = "\n".join(lines[:cut]).rstrip()
    select_body = "\n".join(lines[cut:])

    indented = "\n".join("    " + l if l.strip() else l
                         for l in select_body.splitlines())

    sets = "\n".join(f"SET {k} = {v};" for k, v in params.items())
    sql = (f"-- ===== WRAPPER: {wrapper.name} =====\n"
           f"-- The query below is {wrapper.name}'s inner query, verbatim. Its\n"
           "-- parameters and its rules are untouched; the wrapper only reads the\n"
           "-- columns it returns.\n"
           f"{preamble}\n\n"
           f"-- ----- wrapper parameters -----\n{sets}\n\n"
           + wrapper.sql.format(inner=indented) + ";\n")
    return sql, notes
