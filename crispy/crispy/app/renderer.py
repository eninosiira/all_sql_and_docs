"""Turning a plan into runnable SQL.

The template is the notebook's own query, byte for byte, including its comments
and its validation cases. The renderer rewrites the SET lines at the top and
touches nothing below them. That is the whole contract: the person reading the
output is reading the query that was reviewed, with a parameter block they can
see and check.
"""

from __future__ import annotations

import re
from pathlib import Path

from .catalog import (
    DEFAULT_DEMO_BY_NETWORK,
    resolve_content_strand,
    resolve_network,
    QUARTER_HOUR_MISSING_DEMOS,
    STREAMS_WITHOUT_QUARTER_HOURS,
    STREAMS_WITHOUT_HALF_HOURS,
    resolve_demo,
    resolve_stream,
)
from .specs import SPECS
from .resolver import get_resolver
from .pins import (
    METHOD_PINS, FY_START_OF_TARGET, DAY_BEFORE_TARGET,
    method_pins_for, conditional_pins_for,
)
from datetime import date, timedelta
from . import fiscal

SQL_DIR = Path(__file__).parent / "sql"

# a SET line, captured so the original alignment and trailing comment survive
SET_RE = re.compile(
    r"^(?P<lead>SET\s+)(?P<name>p_\w+)(?P<pad>\s*)=(?P<gap>\s*)"
    r"(?P<value>.*?)(?P<tail>\s*;)(?P<comment>.*)$"
)


def _lit(value) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def _like(program: str, resolved: bool = False) -> str:
    """The pattern for p_program.

    Once the resolver has matched a programme, this is the stored title with no
    wildcards around it: p_program is compared with ILIKE, so an exact string is
    an exact match. That is the whole value of resolving. Widening it back to
    '%SKINWALKER%' would pull BEYOND SKINWALKER RANCH into a question about
    SECRET SKINWALKER RANCH and average two series together.

    Unresolved, it falls back to the most distinctive word, because Nielsen
    truncates PROGRAM_NAME at 25 characters and an equality test against a long
    title finds nothing. That path is a guess, and it is only taken when the
    resolver could not answer.
    """
    if resolved:
        return program.upper()
    words = [w for w in re.findall(r"[A-Za-z0-9']+", program) if len(w) > 3]
    stop = {"the", "with", "and", "from", "that", "this", "show", "season"}
    core = [w for w in words if w.lower() not in stop] or words
    core.sort(key=len, reverse=True)
    return "%" + core[0].upper() + "%" if core else "%" + program.upper() + "%"


def _fy_start(d: str | None) -> str | None:
    """A&E's fiscal year begins on the last Monday of September.

    Computed here rather than asked of the model, because a fiscal year is not a
    calendar one and a model that computes it will be right most of the time,
    which is the worst failure rate for a date.
    """
    if not d:
        return None
    y = date.fromisoformat(d)
    def last_monday_sept(year: int) -> date:
        dd = date(year, 9, 30)
        while dd.weekday() != 0:
            dd -= timedelta(days=1)
        return dd
    start = last_monday_sept(y.year)
    if y < start:
        start = last_monday_sept(y.year - 1)
    return start.isoformat()


def _resolve_token(tok, target: str | None):
    if tok == FY_START_OF_TARGET:
        return _fy_start(target)
    if tok == DAY_BEFORE_TARGET:
        if not target:
            return None
        return (date.fromisoformat(target) - timedelta(days=1)).isoformat()
    return tok


def _single_date(params, sql: str) -> str | None:
    """[DATE-BRIDGE] One date named, on a query with no p_target_date.

    A date in a question is a fact the person supplied. What it is NOT is a
    field: 1.1 keeps a single night in p_target_date, and 3.1 and 3.4 have no
    such parameter, so for them one date is a window of one day with the same
    value at both ends.

    Which field it lands in depends on the query, and the person has no way to
    know that. Asking them to write "from 7/2/26 to 7/2/26" would be asking them
    to know the shape of the SQL, which is the thing CRISpy exists to spare them.

    R_3 and R_4 both need it. "Where does A&E rank in Interrogation Raw's time
    period ON 7/2/26" left both ends null, so the slots came from the whole of
    season 5 - eight Thursdays - and the competitive ranking averaged a season
    where A&E's sheet prints 07/02/26-07/02/26.

    Only where p_target_date is absent. Where the query has one, the date
    belongs there and this must not shadow it.
    """
    if "SET p_target_date" in sql:
        return None
    return getattr(params, "target_date", None)


def _win_from(params, sql: str) -> str | None:
    """[DATE-BRIDGE] The series window start.

    Deliberately does NOT touch p_norm_from. 2.1, 2.2, 2.5 and 2.6 carry two
    windows on purpose: the series runs to one date and the norm is cut at
    another, which on SP_7 is 13 July against 31 May. The norm pair is set by
    the method pins from the premiere date, and a date the person named is about
    the series, never about the norm.
    """
    # One end of a window, on its own, is a window of one day.
    #
    # R_5 is why. "For this past Tuesday (7/14/26)" put the date straight into
    # win_to and left win_from empty, so the ranker covered 8 to 14 July rather
    # than the Tuesday. R_3 had the same question shape and the reader put the
    # date in target_date instead, which the single-date bridge already caught.
    # The same fact arrives by two routes depending on how the model reads the
    # phrase, and a bridge that covers one of them covers half the cases.
    #
    # A range genuinely asked for always gives both ends, so there is nothing to
    # lose: a lone win_to means one day, not a week ending there.
    return (getattr(params, "win_from", None)
            or _single_date(params, sql)
            or getattr(params, "win_to", None))


def render(query_id: str, params, today: str) -> dict:
    """Return the finished SQL plus everything the answer layer needs to explain it."""
    spec = SPECS[query_id]
    sql = (SQL_DIR / spec.sql_file).read_text()

    network = (params.network or "").upper() or None
    stream = resolve_stream(params.stream)
    demo_col, demo_note = resolve_demo(params.demo, network)

    notes: list[str] = list(params.notes or [])
    if demo_note:
        notes.append(demo_note)

    # Two things the data cannot do, said before the query runs rather than
    # discovered as an empty result afterwards.
    if spec.needs_quarter_hours and stream in STREAMS_WITHOUT_QUARTER_HOURS:
        notes.append(
            f"{stream} carries no quarter-hour rows, so this query cannot answer on it. "
            "C3 and C7 exist at total-program level only. Run it on Live+SD, or take "
            "the requirement back to A&E."
        )
    if spec.needs_half_hours and stream in STREAMS_WITHOUT_HALF_HOURS:
        notes.append(
            f"{stream} carries no half-hour rows, so this query cannot answer on it. "
            "A daypart is a half-hour construct: prime is the half hours whose own "
            "start falls inside 8p to 11p. This is A&E's own R_2, and the same "
            "question on Live+SD reproduces their published figures exactly, so the "
            "gap is data coverage rather than method. Their footer on that report "
            "says dayparts there are programme based and commercial duration "
            "weighted, which is worth putting back to them."
        )
    if spec.needs_quarter_hours and demo_col in QUARTER_HOUR_MISSING_DEMOS:
        notes.append(
            f"{demo_col} exists at telecast level but not in the quarter-hour view, so "
            "this query returns nothing on it while 1.1 would answer. That is the file, "
            "not the build."
        )

    # [FY-DATES] A fiscal year can be named in any question that takes a window,
    # which is all twenty-two, so it is resolved once here and arrives at every
    # query as two ordinary dates.
    #
    # The year matters more than it looks. FY26 begins on 2025-09-29 and FY25 on
    # 2024-09-30, neither guessable from the number, and a question naming a PAST
    # fiscal year answered against the current one returns figures that are just
    # as plausible as the right ones. SP_5 asks for FY 2025 and came back with
    # both window bounds null, which the template then filled with a trailing
    # fifty-two weeks - a different year, reported without a word about it.
    # [FY-ASOF] anchored on the last night WITH DATA, not on the calendar. The
    # first version passed today's date and SP_4 came back running to 2026-09-01
    # while the data stopped on 2026-08-09 - a window claiming three weeks of
    # reach it did not have. Nothing was in the gap so the figures held, which is
    # the problem: it would have kept holding right up until it didn't.
    _as_of = today
    try:
        _r = get_resolver()
        _n = _r.latest_night(network, stream or "Live+SD") if network else None
        if _n and _n.get("status") == "resolved" and _n.get("date"):
            _as_of = str(_n["date"])
        elif not network:
            # a ranker with no single network: the widest date any of them reach
            _as_of = str(_r.latest_any(stream or "Live+SD") or today)
    except Exception:                                    # noqa: BLE001
        # A resolver failure must not take the query with it. Falling back to
        # today is the old behaviour and is wrong by at most a few weeks of
        # empty window, which is visible in the output rather than silent.
        pass

    _fy_from, _fy_to, _fy_label = fiscal.resolve(
        fiscal_year=getattr(params, "fiscal_year", None),
        names_fiscal_year=bool(getattr(params, "names_fiscal_year", False)),
        win_from=getattr(params, "win_from", None),
        win_to=getattr(params, "win_to", None),
        latest=_as_of,
    )
    _fy = (_fy_from, _fy_to)
    _fy_year = None
    if _fy_label:
        # "FY25 (...)" -> 2025. Taken from the label so there is exactly one
        # place the year is decided.
        _m = re.match(r"FY(\d{2})", _fy_label)
        if _m:
            _fy_year = 2000 + int(_m.group(1))
    if _fy_label:
        # The label travels with the answer. Without it a run against the wrong
        # fiscal year is indistinguishable from a run against the right one.
        notes.append(f"Fiscal year resolved to {_fy_label}.")

    values: dict[str, object] = {
        "p_network": network,
        # [PARAM-BRIDGE] Section 1 calls the stream p_rating_src and Sections 2
        # and 3 call it p_stream. Only the first was mapped, so thirteen queries
        # never received a stream the person had asked for.
        #
        # R_2 is where that turns dangerous rather than merely wrong. It asks for
        # C3, the coverage guard sees C3 and warns that the question cannot be
        # answered, and the SQL runs on Live+SD and returns numbers. A warning
        # and a result saying opposite things is worse than either alone.
        "p_rating_src": stream,
        "p_stream": stream,
        "p_target_date": params.target_date,
        # [PARAM-BRIDGE] read and then dropped. The reader has had win_from,
        # win_to, top_n and genre since the split, and none of them had a bridge
        # to the SQL, so "thru 6/28/26" and "top 3" were extracted, shown, and
        # thrown away. The template defaults then answered a different question
        # while looking deliberate.
        "p_win_from": _fy[0] if _fy[0] is not None else _win_from(params, sql),
        "p_win_to": _fy[1] if _fy[1] is not None else (
            getattr(params, "win_to", None) or _single_date(params, sql)),
        # [DATE-BRIDGE] 3.2 scopes a fiscal year to date with p_fy_to and has no
        # p_win_to at all, so a cut-off read out of the question landed in a
        # field that query does not have. R_6's own note said it: "FY26 named;
        # thru date captured in win_to". Captured, and nowhere the SQL would look.
        #
        # Same reasoning as the single date. The value is in the question; which
        # field carries it is a fact about the query, and the person cannot be
        # expected to know that 3.2 spells its window differently from 3.1.
        # [FY-DATES] p_fy_to is now fed from the same resolution as p_win_to, so
        # 3.2 cannot drift away from every other query on the same question.
        "p_fy_to": _fy[1] or getattr(params, "win_to", None),
        # [FY-YEAR] 3.2 and 3.3 have no p_win_from at all: they derive their
        # window from p_fiscal_year through the calendar table. So the resolved
        # YEAR has to reach them as a year, or the start silently falls back to
        # whichever fiscal year the data happens to end in.
        #
        # That is only invisible while the question is about the CURRENT year.
        # R_1 and R_6 both ask about FY26, which is why null worked there. Ask
        # 3.2 about FY 2025 with this unset and it answers about FY26, with a
        # rank that looks entirely reasonable.
        "p_fiscal_year": _fy_year,
        "p_report_from": params.report_from,
        "p_report_to": params.report_to,
        "p_season": params.season,
        "p_program": (_like(params.program,
                     resolved=bool(getattr(params, "program_code", None)))
                     if params.program else None),
    }

    # [CONTENT-STRAND] A content word narrows through the programme name,
    # because that is where the data keeps it. Only when no programme was
    # named: a strand narrows a slate, it does not override a title.
    strand_pat, strand_note = resolve_content_strand(
        getattr(params, "content_strand", None), network)
    if strand_note:
        notes.append(strand_note)
    if strand_pat and not params.program:
        values["p_program"] = strand_pat
        notes.append(
            f"{getattr(params, 'content_strand', '')!r} was matched on the "
            f"programme name as {strand_pat}, because the data carries it in the "
            "bucket name rather than as a flag."
        )
    if params.include_specials is not None:
        values["p_include_specials"] = params.include_specials
    # [S3-FOCUS] the networks to return rows for, mapped through the catalogue
    # so LFT and Lifetime arrive as LIF the same way a single network does.
    focus = getattr(params, "focus_networks", None)
    if focus:
        codes = [resolve_network(x.strip()) for x in str(focus).split(",") if x.strip()]
        codes = [c for c in codes if c]
        if codes:
            values["p_focus_networks"] = ",".join(codes)
            # Naming networks to focus on is not asking for a global top N, and
            # the two cuts fight each other: the template default of 20 would
            # cut the ranking at position 20 before the focus ever sees a row
            # further down. On A&E's own R_1 that loses Lifetime entirely, whose
            # second title is at cable rank 368.
            #
            # So the global cut is lifted whenever a focus is given, UNLESS the
            # question actually asked for a top N. "Top 20 of cable" keeps its
            # 20; "top 3 per network" and "where do my shows rank" do not have
            # one to keep.
            if not getattr(params, "top_n", None):
                values["p_top_n"] = None
                notes.append(
                    "The global cut was lifted because the question asks about "
                    "particular networks rather than for a top N of cable. The "
                    "ranking still runs across the whole competitive set, so the "
                    "cable rank stays comparable; only the rows returned are "
                    "narrowed."
                )
    if getattr(params, "per_network", None):
        values["p_per_network"] = params.per_network

    if getattr(params, "top_n", None):
        # [RANKER-DEPTH] A floor, because depth and display are different
        # numbers and the question usually states the second one.
        #
        # R_1 asks for the TOP 3 per network across A&E, HIST and LIF. Read as
        # depth 3, the ranker returns the three biggest shows on cable and none
        # of those networks is among them: a correct query, a valid result, and
        # no answer. HIST's third title is at rank 29.
        #
        # 20 is the query's own default and the lowest depth any validated case
        # ran at. A question that genuinely wants a shallow list still gets one,
        # because the answer layer shows the top N of what comes back; nothing
        # is lost by ranking deeper than the reader asked.
        depth = int(params.top_n)
        if depth < 20 and spec.is_ranker:
            notes.append(
                f"The ranker runs to depth 20 rather than {depth}. A top {depth} "
                "per network is picked from the result, and a ranker scored "
                "across the whole competitive set can easily place none of the "
                "networks asked about in its first few rows."
            )
            depth = 20
        values["p_top_n"] = depth
    if getattr(params, "genre", None):
        # the genre arrives as the person said it; the SQL wants a LIKE pattern
        g = str(params.genre).strip().upper().replace(" ", "%").replace("-", "%")
        values["p_genre"] = f"%{g}%"

    # [PARAM-BRIDGE] p_demo is written ONLY when the question named a demo.
    #
    # It used to be written always, so an unnamed demo overwrote whatever the
    # template had with NULL. That is right for the queries whose own default IS
    # NULL, meaning each network resolves its own, and wrong everywhere else.
    #
    # 3.3 is the case that showed it: its template pins P25_64_AA_ESTIMATES,
    # because a ranker across 174 networks needs ONE demo for all of them, and
    # A&E's sheet says P25-64. Overwriting that with NULL leaves
    # IDENTIFIER(NULL), which does not resolve to a column at all: the query
    # fails to compile rather than returning something wrong.
    #
    # Leaving the line alone is safe in both directions, because every template
    # already carries the default that query should have.
    if demo_col:
        values["p_demo"] = demo_col

    # A season pin only means something where a season is on one side of the
    # comparison. Saying so beats letting it look honoured.
    if params.season:
        if query_id in ("1.3", "1.4"):
            notes.append(
                f"Season {params.season} was ignored: {spec.title} has no season on "
                "either side of its comparison."
            )
            values["p_season"] = None
        elif query_id == "1.5" and not params.program:
            notes.append(
                f"Season {params.season} needs a programme to mean anything: a season "
                "number lives inside a programme, not across a schedule. Name the "
                "series and it will be applied."
            )
        elif query_id in ("1.2", "1.3b"):
            notes.append(
                f"Season {params.season} narrows which of that night's premieres is in "
                "scope. It cannot reach a season that did not air that night."
            )

    # 1.3 pins its own demo and its own network by design: it is the Lifetime
    # movie norm and should read the same wherever it is pointed.
    if query_id == "1.3":
        values.pop("p_demo", None)
        values["p_network"] = network or "LIF"

    # [WEIGHT-BY-STREAM] The ACM currencies are weighted on COMMERCIAL minutes
    # and everything else on programme minutes. That is not a preference: A&E
    # print it on the reports themselves, "Commercial Duration weighted" on the
    # C3 sheet and "Program QH based" on the Live+SD one.
    #
    # The template carries COMMERCIAL_DURATION because it was written for R_2,
    # which is the C3 case. R_6 is the same question on Live+SD and inherited it,
    # which would have weighted a programme-based daypart on commercial minutes
    # and moved every figure for a reason nobody asked for.
    #
    # Tied to the stream rather than left as a default, because the two always
    # travel together and getting them out of step is silent.
    if "SET p_weight_col" in sql:
        values["p_weight_col"] = ("COMMERCIAL_DURATION"
                                  if str(stream).startswith("ACM") else "HH_MIN")

    # ------------------------------------------------------------------
    # Pins. Parameters CRISpy sets itself, because A&E's method needs them and
    # neither the question nor the query default supplies them.
    #
    # They go in LAST and they win. A pin is not a suggestion: it is the thing
    # that separates a query that runs from a query that reproduces. Each one
    # lands in pin_notes with its reason and the figure it was derived from, so
    # the person reading the answer can see what was set on their behalf.
    # ------------------------------------------------------------------
    pin_notes: list[dict] = []
    target_for_pins = params.target_date or getattr(params, "premiere_date", None)

    for pin in method_pins_for(query_id):
        val = _resolve_token(pin.value, target_for_pins)
        if isinstance(pin.value, str) and pin.value.startswith("@") and val is None:
            # the token needed a date the question never gave; say so rather
            # than silently falling back to the default window
            notes.append(
                f"{pin.param} could not be pinned because no date is in view. "
                f"{pin.why} Give a date and the norm will follow A&E's method."
            )
            continue
        values[pin.param] = val
        pin_notes.append({"param": pin.param, "value": val,
                          "why": pin.why, "evidence": pin.evidence,
                          "kind": "method"})

    flags = {
        "is_movie_question": bool(getattr(params, "is_movie_question", False)),
        "is_holiday_question": bool(getattr(params, "is_holiday_question", False)),
        "is_season_premiere_question": bool(getattr(params, "is_season_premiere_question", False)),
        "is_season_qh_question": bool(getattr(params, "is_season_qh_question", False)),
        "is_series_leadin_question": bool(getattr(params, "is_series_leadin_question", False)),
        "names_fiscal_year": bool(getattr(params, "names_fiscal_year", False)),
        "has_published_cutoff": bool(getattr(params, "has_published_cutoff", False)),
    }
    for pin, why in conditional_pins_for(query_id, flags):
        val = _resolve_token(pin.value, target_for_pins)
        # The same guard the method loop has, and it was missing here. A pin
        # whose value is a token needing a date the question never gave resolves
        # to None, and writing that None into values overwrites whatever was
        # already there.
        #
        # R_6 is where it showed. The cut-off "thru 7/5/26" reached p_fy_to
        # through the date bridge, and then this loop replaced it with None
        # because the p_fy_to pin wanted a premiere date that a ranking question
        # does not have. A pin standing down must leave the field as it found
        # it, not blank it.
        if isinstance(pin.value, str) and pin.value.startswith("@") and val is None:
            continue
        values[pin.param] = val
        pin_notes.append({"param": pin.param, "value": val,
                          "why": pin.why, "evidence": pin.evidence,
                          "kind": "conditional", "condition": why})

    applied: dict[str, str] = {}
    out_lines: list[str] = []
    for line in sql.splitlines():
        m = SET_RE.match(line)
        if not m or m.group("name") not in values:
            out_lines.append(line)
            continue
        name = m.group("name")
        new = _lit(values[name])
        applied[name] = new
        out_lines.append(
            f"{m.group('lead')}{name}{m.group('pad')}={m.group('gap')}{new}"
            f"{m.group('tail')}{m.group('comment')}"
        )

    # A pin that reports itself as applied but never reached a SET line is worse
    # than no pin at all: it says the method was followed when it was not. The
    # renderer only rewrites lines that exist, so anything left over gets moved
    # out of the pin list and into a note.
    unreachable = [pn for pn in pin_notes if pn["param"] not in applied]
    pin_notes = [pn for pn in pin_notes if pn["param"] in applied]
    for pn in unreachable:
        notes.append(
            f"{pn['param']} does not exist on {spec.title}, so it was not applied. "
            "If this query needs it, the parameter has to be added to the SQL "
            "rather than pinned from here."
        )

    panel = [
        {
            "field": "Network",
            "value": network or "all six A+E networks",
            "source": (getattr(params, "source_network", None)
                       or ("from the question" if params.network
                           else "not named, so all six")),
        },
        {
            "field": "Program",
            "value": params.program or "every premiere in scope",
            "source": (getattr(params, "source_program", None)
                       or ("matched in the data, exact title"
                           if getattr(params, "program_code", None)
                           else "pattern, unresolved" if params.program
                           else "not named, so the whole night")),
        },
        {
            "field": "Season",
            "value": params.season or "whichever each premiere belongs to",
            "source": (getattr(params, "source_season", None)
                       or ("from the question" if params.season
                           else "default, whichever each premiere belongs to")),
        },
        {
            "field": "Date",
            "value": (params.target_date
                      or (f"{params.report_from} to {params.report_to}"
                          if params.report_from and params.report_to
                          else "most recent night with data")),
            "source": ("from the question"
                       if params.target_date or params.report_from
                       else "default, resolved from CRIS_LATEST_DATE"),
        },
        {
            # [PANEL-DEMO] When no demo is named, p_demo goes to the query as
            # NULL and the QUERY resolves the network's own default. CRISpy
            # does not choose it.
            #
            # The panel used to print CRISpy's own DEFAULT_DEMO_BY_NETWORK
            # here and label it "network default, per A&E", which said two
            # untrue things at once: that a value had been set when the SQL
            # read NULL, and that the table came from A&E when we wrote it
            # ourselves. VICE's entry in it is flagged as an unconfirmed
            # assumption, so "per A&E" was exactly wrong on the one row that
            # most needed the caveat.
            #
            # The figure is still shown, because a reader wants to know which
            # demo they are looking at. What changed is that it no longer
            # claims to be a decision.
            "field": "Demo",
            "value": (demo_col if demo_col else
                      DEFAULT_DEMO_BY_NETWORK.get(network or "", "DEMO_AA")
                      + " (resolved by the query)"),
            # [SCOPE-FOLLOWUP] source_demo is set when the value was
            # inherited. Without it a carried demo read "from the question",
            # which is the one thing a parameter panel must never say about
            # a value the person did not give.
            "source": (getattr(params, "source_demo", None)
                       or ("from the question" if demo_col
                           else "not named, so the query resolves the "
                                "network's own default")),
        },
        {
            "field": "Stream",
            "value": stream,
            # [SCOPE-FOLLOWUP] same as the demo. A carried stream saying
            # "from the question" is how four cases ran on Live+3 while the
            # panel reported it as asked for.
            "source": (getattr(params, "source_stream", None)
                       or ("from the question" if params.stream else "default")),
        },
        {
            "field": "Specials",
            "value": ("included" if params.include_specials is not False
                      else "excluded"),
            "source": ("from the question" if params.include_specials is not None
                       else "default: a special that aired counts toward the night"),
        },
    ] + [
        # Pins appear in the same table as everything else, so a person
        # scanning the parameters sees them without being told to look.
        {
            "field": pn["param"],
            "value": ("NULL" if pn["value"] is None else str(pn["value"])),
            "source": ("set by CRISpy to match A&E's method"
                       if pn["kind"] == "method"
                       else "set by CRISpy for this kind of question"),
            "why": pn["why"],
            "evidence": pn["evidence"],
        }
        for pn in pin_notes
    ]

    # [PANEL-APPLIED] A row that names a parameter the query does not have is a
    # row about something that did not happen.
    #
    # R_1 is the case. "Top 3 non-fiction shows per network for A&E, HIST and
    # LIF" showed Network AEN, from the question. 3.3 has no p_network at all:
    # it is a ranker over the whole cable competitive set, and the three
    # networks in that question group the OUTPUT rather than filter the
    # universe. So the SQL was right and the panel described a filter that was
    # never applied, which is worse than a wrong value because it is
    # unfalsifiable from the screen.
    #
    # This is the fourth variant of one pattern: a carried demo shown as stated,
    # a pin reporting itself applied when it reached no SET line, a network
    # shown resolved where it was used raw, and now a parameter shown for a
    # query that does not take it. Whenever a value is transformed or dropped
    # between where it is used and where it is displayed, the display
    # eventually lies. The panel is the tool everything else is audited with, so
    # it costs double there.
    PANEL_PARAM = {
        "Network": "p_network", "Program": "p_program", "Season": "p_season",
        "Demo": "p_demo", "Stream": ("p_stream", "p_rating_src"),
        "Specials": "p_include_specials",
    }
    sql_text = "\n".join(out_lines)
    for row in panel:
        names = PANEL_PARAM.get(row["field"])
        if not names:
            continue
        names = (names,) if isinstance(names, str) else names
        if not any(f"SET {n}" in sql_text for n in names):
            row["value"] = "not a parameter of this query"
            if spec.is_ranker and row["field"] in ("Network", "Program"):
                # The useful thing to say is not that the parameter is absent
                # but WHY: this ranker is scored over the whole competitive set,
                # so a network or a title named in the question groups the
                # OUTPUT rather than narrowing what is ranked. Saying only "not
                # a parameter" would read as a limitation when it is the point.
                row["source"] = (
                    f"{spec.title} is scored over the whole competitive set, so "
                    "anything named in the question groups the result rather "
                    "than filtering it. Every network stays in the ranking."
                )
            else:
                row["source"] = (
                    f"{spec.title} does not take {names[0]}. Anything read from "
                    "the question for it was not applied."
                )

    return {
        "query_id": query_id,
        "title": spec.title,
        "answers": spec.answers,
        "sql": "\n".join(out_lines),
        "applied": applied,
        "notes": notes,
        # Every field, with where its value came from. The point is not the
        # value: it is that a default and a stated value look identical in the
        # SQL, and only one of them is something the person chose. A reader who
        # cannot tell them apart cannot tell whether the query answers the
        # question they asked.
        "resolved": panel,
        "pins": pin_notes,
    }
