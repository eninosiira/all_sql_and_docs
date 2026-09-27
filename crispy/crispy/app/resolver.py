"""Turning a phrase into a parameter that exists.

CRISpy reads parameters out of a question and produces valid SQL. That much was
already true, and the SQL ran clean against the warehouse. But it wrote `HIST`,
`%SKINWALKER%` and `7` without ever checking that any of them exist, and on the
examples tried the text happened to match the data.

The failure mode when it does not match is the quiet one: a value the warehouse
does not hold returns zero rows and no error. Nothing looks wrong. It reads
exactly like a quiet week.

## Why this runs SQL rather than Python

The two CSVs are loaded into SQLite at startup and every lookup below is a real
query against real tables. That is deliberate and it is the point of the module.

CRIS runs against Snowflake from Vercel and cannot load a CSV. If CRISpy did its
matching in Python, whoever ports this would not be translating a query, they
would be inventing one, and the SQL that shipped would be SQL nobody had tested.
Written as SQL here, the same statements run there: `CRIS_RESOLVER_PROGRAM` and
`CRIS_RESOLVER_CONTEXT` already exist in `AUDIENCE_DEV_DB.CRIS` with these
column names, so the port is a connection change and a schema prefix.

Anywhere the two dialects differ is marked `PORTING:` in the SQL itself.

## Three rules the queries encode

**Resolve, never answer.** These lookups turn a phrase into a parameter and
stop. Every figure in an answer comes from a reviewed Section 1 to 3 query. The
moment a number can come from here instead, an answer exists that no reviewed
query produced.

**Ambiguity is a question, not a tie to break.** Two networks carrying the same
title, or both `13` and `13B` existing, is something to ask about. A&E decided
sub-seasons are separate seasons, so picking one silently contradicts that
decision rather than approximating it.

**A failed match stays failed.** If a programme does not resolve, say so.
Widening the pattern is how "Wars" comes back with four different shows and the
answer is about the wrong one.
"""

from __future__ import annotations

import csv
import re
import sqlite3
from pathlib import Path

DATA = Path(__file__).parent / "data"

# Nielsen keeps PROGRAM_NAME in a 25-character field. A title at that length has
# almost certainly been cut, which is why an equality test against what someone
# typed finds nothing: the stored title for the new World War II series is
# WORLD WAR II TOM HANKS, with the word "with" gone entirely.
NAME_FIELD_WIDTH = 25

# Words too common to identify a programme on their own. "Wars" alone matches
# Customer Wars, Neighborhood Wars, Road Wars and Storage Wars.
STOPWORDS = {
    "the", "a", "an", "of", "and", "with", "on", "in", "at", "for", "to",
    "show", "season", "series", "episode", "tv", "my", "is", "it",
}

TABLES = {
    "CRIS_RESOLVER_PROGRAM": "cris_resolver_program.csv",
    "CRIS_RESOLVER_CONTEXT": "cris_resolver_context.csv",
}


def _load(con: sqlite3.Connection) -> None:
    """Mirror the two Snowflake tables into SQLite, column names intact.

    Types are deliberately loose. SQLite has no boolean and Snowflake exports
    TRUE and FALSE as text, so the queries compare against the strings rather
    than casting. `= 'TRUE'` reads the same in both dialects and needs no port.
    """
    for table, filename in TABLES.items():
        path = DATA / filename
        if not path.exists():
            raise FileNotFoundError(
                f"{path} is missing. Export it from Snowflake with "
                f"CRIS_Resolver_Tables and drop the CSV in app/data/."
            )
        with path.open(encoding="utf-8-sig", newline="") as f:
            rows = list(csv.DictReader(f))
        if not rows:
            raise ValueError(f"{path} has a header but no rows.")

        cols = list(rows[0].keys())
        quoted = ", ".join('"%s"' % c for c in cols)
        con.execute("CREATE TABLE %s (%s)" % (table, quoted))
        con.executemany(
            "INSERT INTO %s VALUES (%s)" % (table, ", ".join("?" * len(cols))),
            [tuple(r[c] for c in cols) for r in rows],
        )

    # Matching runs on the name, so it earns an index even at this size.
    con.execute("CREATE INDEX ix_prog_name ON CRIS_RESOLVER_PROGRAM(PROGRAM_NAME)")
    con.execute("CREATE INDEX ix_prog_key ON CRIS_RESOLVER_PROGRAM(NETWORK_CODE, PROGRAM_CODE)")
    con.execute("CREATE INDEX ix_ctx_key ON CRIS_RESOLVER_CONTEXT(NETWORK_CODE, RATING_SOURCE)")
    con.commit()


# ==========================================================================
# The queries. Each of these is what CRIS runs against Snowflake.
# ==========================================================================

# Match a phrase against the stored titles, ranked by how the match was made.
#
# The ranking is the substance. A title that genuinely exists must never lose to
# a longer one that merely contains it, and the truncation case has to beat
# everything except an exact hit, because there the stored title is a prefix of
# what the person said rather than the other way round.
#
#   0 EXACT        the phrase is the stored title
#   1 PREFIX       the phrase starts with the stored title   <- truncation
#   2 STARTS_WITH  the stored title starts with the phrase
#   3 CONTAINS     the stored title contains the phrase
#   4 word match   fed in through extra_codes, see below
#
# PORTING: UPPER, LIKE, CASE and || behave identically in Snowflake. The temp
# table extra_codes becomes a bind list: IN (SELECT VALUE FROM TABLE(FLATTEN(...)))
# or simply IN (?, ?, ...) built from the same Python set.
Q_PROGRAM = """
SELECT NETWORK_CODE,
       PROGRAM_CODE,
       PROGRAM_NAME,
       NAME_LEN,
       NAME_TRUNCATED,
       NETWORKS_WITH_THIS_TITLE,
       MAX(CAST(TELECASTS AS INTEGER)) AS TELECASTS,
       MAX(SEASON_TO)                  AS LAST_AIRED,
       CASE
           WHEN UPPER(PROGRAM_NAME) = UPPER(:phrase)                  THEN 0
           WHEN UPPER(:phrase) LIKE UPPER(PROGRAM_NAME) || '%'        THEN 1
           WHEN UPPER(PROGRAM_NAME) LIKE UPPER(:phrase) || '%'        THEN 2
           WHEN UPPER(PROGRAM_NAME) LIKE '%' || UPPER(:phrase) || '%' THEN 3
           ELSE 4
       END AS MATCH_RANK
FROM CRIS_RESOLVER_PROGRAM
WHERE (:network IS NULL OR NETWORK_CODE = :network)
  AND ( UPPER(PROGRAM_NAME) = UPPER(:phrase)
     OR UPPER(:phrase) LIKE UPPER(PROGRAM_NAME) || '%'
     OR UPPER(PROGRAM_NAME) LIKE UPPER(:phrase) || '%'
     OR UPPER(PROGRAM_NAME) LIKE '%' || UPPER(:phrase) || '%'
     OR PROGRAM_CODE IN (SELECT value FROM extra_codes) )
GROUP BY NETWORK_CODE, PROGRAM_CODE, PROGRAM_NAME, NAME_LEN,
         NAME_TRUNCATED, NETWORKS_WITH_THIS_TITLE
ORDER BY MATCH_RANK, TELECASTS DESC
"""

# Distinct programme names, for the word-level pass.
Q_ALL_NAMES = """
SELECT DISTINCT NETWORK_CODE, PROGRAM_CODE, PROGRAM_NAME
FROM CRIS_RESOLVER_PROGRAM
WHERE (:network IS NULL OR NETWORK_CODE = :network)
"""

# Every season one programme has, most recent first.
#
# Ordered by SEASON_FROM and never by the label, because labels are free text:
# 2026B sorts before 2026C alphabetically but not chronologically, and 13B
# sorts before 2 in any string comparison.
#
# MATCHES_REQUEST does the work that a blind write of '7' used to do. CT_SEASON
# is free text, so a question saying "season 7" can need '7', '07', '2026' or
# '7B' depending on the series, and SEASON_NUMERIC exists only so the two can be
# compared. What a query receives is always CT_SEASON verbatim.
Q_SEASONS = """
SELECT CT_SEASON,
       SEASON_NUMERIC,
       IS_SUB_SEASON,
       CAST(TELECASTS AS INTEGER) AS TELECASTS,
       SEASON_FROM,
       SEASON_TO,
       IS_CURRENT_SEASON,
       CASE
           WHEN :asked IS NULL                                    THEN 0
           WHEN CT_SEASON = :asked                                THEN 1
           WHEN :asked_num IS NOT NULL
            AND CAST(SEASON_NUMERIC AS INTEGER) = CAST(:asked_num AS INTEGER) THEN 1
           ELSE 0
       END AS MATCHES_REQUEST
FROM CRIS_RESOLVER_PROGRAM
WHERE NETWORK_CODE = :network
  AND PROGRAM_CODE = :program_code
ORDER BY SEASON_FROM DESC
"""

# What "last night" means for one network and stream, and which demo a question
# that names none resolves to.
#
# Two things live here that nothing else can work out. "Last night" is not
# yesterday: it is the most recent night with data, and it differs by network,
# by stream, and between total-program and quarter-hour because quarter-hour
# posts later. And the default demo is not in the Nielsen file at all, which is
# why DEMO_SOURCE travels beside it and VICE reads as an assumption.
Q_CONTEXT = """
SELECT NETWORK_CODE, RATING_SOURCE,
       LATEST_BROADCAST_DATE, LATEST_QH_BROADCAST_DATE, LATEST_FULL_SUNDAY,
       QH_LAG_DAYS, DEFAULT_DEMO, DEMO_SOURCE, CAN_BE_DAYPARTED, IS_AE
FROM CRIS_RESOLVER_CONTEXT
WHERE NETWORK_CODE = :network
  AND RATING_SOURCE = :stream
"""

Q_DEFAULT_DEMO = """
SELECT DEFAULT_DEMO, DEMO_SOURCE
FROM CRIS_RESOLVER_CONTEXT
WHERE NETWORK_CODE = :network
  AND DEFAULT_DEMO IS NOT NULL
  AND DEFAULT_DEMO <> ''
LIMIT 1
"""

# Whether any network carries half hours on this stream. The ACM streams carry
# none, which makes a dayparted C3 question unanswerable from the data rather
# than merely empty, and that is worth saying before the query runs instead of
# after it comes back looking like a quiet period.
Q_DAYPARTABLE = """
SELECT SUM(CASE WHEN CAN_BE_DAYPARTED = 'TRUE' THEN 1 ELSE 0 END) AS N
FROM CRIS_RESOLVER_CONTEXT
WHERE RATING_SOURCE = :stream
"""

# [FY-ASOF] the newest broadcast date anywhere on a stream. Used to anchor a
# fiscal year for the rankers, which have no single network to ask about, so that
# "this fiscal year" ends where the data ends rather than where the calendar does.
Q_LATEST_ANY = """
SELECT MAX(LATEST_BROADCAST_DATE) AS D
FROM CRIS_RESOLVER_CONTEXT
WHERE RATING_SOURCE = :stream
"""

Q_SUMMARY = """
SELECT (SELECT COUNT(*) FROM CRIS_RESOLVER_PROGRAM)                     AS SEASONS,
       (SELECT COUNT(DISTINCT PROGRAM_CODE) FROM CRIS_RESOLVER_PROGRAM) AS PROGRAMS,
       (SELECT COUNT(DISTINCT NETWORK_CODE) FROM CRIS_RESOLVER_PROGRAM) AS NETWORKS,
       (SELECT COUNT(*) FROM CRIS_RESOLVER_PROGRAM
         WHERE NAME_TRUNCATED = 'TRUE')                                 AS TRUNCATED,
       (SELECT COUNT(*) FROM CRIS_RESOLVER_PROGRAM
         WHERE CAST(NETWORKS_WITH_THIS_TITLE AS INTEGER) > 1)           AS AMBIGUOUS,
       (SELECT COUNT(*) FROM CRIS_RESOLVER_CONTEXT)                     AS CONTEXT_ROWS
"""

_RANK_NAME = {0: "EXACT", 1: "PREFIX", 2: "STARTS_WITH", 3: "CONTAINS"}


def _neg_date(d: str | None) -> str:
    """Sort key that puts the most recent date first without reversing the
    whole tuple, which would flip the match rank too."""
    if not d:
        return "9999-99-99"
    return "".join(chr(ord("9") - (ord(c) - ord("0"))) if c.isdigit() else c
                   for c in d)


def _cand(how: str, r) -> dict:
    return {
        "network": r["NETWORK_CODE"],
        "program_code": r["PROGRAM_CODE"],
        "program_name": r["PROGRAM_NAME"],
        "match": how,
        "telecasts": int(r["TELECASTS"] or 0),
        "truncated": r["NAME_TRUNCATED"] == "TRUE",
        "last_aired": r["LAST_AIRED"],
    }


def _words(text: str) -> set[str]:
    return {w for w in re.findall(r"[A-Z0-9']+", text.upper())
            if w.lower() not in STOPWORDS}


class Resolver:
    """Every lookup CRISpy runs before writing SQL, written as SQL."""

    def __init__(self) -> None:
        self.con = sqlite3.connect(":memory:", check_same_thread=False)
        self.con.row_factory = sqlite3.Row
        _load(self.con)

    def _q(self, sql: str, **params) -> list[sqlite3.Row]:
        return self.con.execute(sql, params).fetchall()

    # ----------------------------------------------------------------------
    # programme
    # ----------------------------------------------------------------------

    def _word_candidates(self, phrase: str, network: str | None) -> dict[str, int]:
        """Programme codes whose distinctive words all appear in the phrase.

        The one part that is not SQL, because neither dialect tokenises and
        intersects words without a UDF. It is what catches WORLD WAR II TOM
        HANKS against "World War II with Tom Hanks": the stored title lost
        "with" to the 25-character field, so nothing contains anything, but
        every word survives.

        PORTING: keep this in the application layer and bind the resulting codes
        into the query. Snowflake takes the same shape.
        """
        q_words = _words(phrase)
        if not q_words:
            return {}
        out: dict[str, int] = {}
        for r in self._q(Q_ALL_NAMES, network=network):
            n_words = _words(r["PROGRAM_NAME"])
            if not n_words:
                continue
            shared = len(q_words & n_words)
            if shared and (shared == len(n_words) or shared >= 2):
                out[r["PROGRAM_CODE"]] = shared
        return out

    def find_program(self, phrase: str, network: str | None = None,
                     active_since: str | None = None) -> dict:
        """Match a phrase against the stored titles.

        active_since narrows an otherwise ambiguous match to programmes that
        have aired since that date, and is passed only when the question is in
        the present tense. "How is Skinwalker Ranch doing" against SECRET, last
        aired a week ago, and BEYOND, last aired over a year ago, is not really
        a question about which: one of them is not doing anything. Asking anyway
        makes someone confirm the obvious.

        It narrows and never widens. If both are current the question stands, and
        if the filter would leave nothing the unfiltered list is returned, because
        a question about a series that ended is still a fair question.
        """
        if not phrase:
            return {"status": "no_program", "candidates": []}

        extra = self._word_candidates(phrase, network)
        self.con.execute("DROP TABLE IF EXISTS extra_codes")
        self.con.execute("CREATE TEMP TABLE extra_codes (value TEXT)")
        if extra:
            self.con.executemany("INSERT INTO extra_codes VALUES (?)",
                                 [(c,) for c in extra])

        rows = self._q(Q_PROGRAM, phrase=phrase.strip(), network=network)

        # [RESOLVER-NETWORK] A network the model supplied is a guess until the
        # data agrees with it. If the programme is nowhere on that network, try
        # every network before giving up, because the likeliest reason for the
        # miss is that the network was wrong rather than that the title was.
        #
        # SP_3 is why. "Which episodes of Alaska State Trooper exceeded the
        # season average" names no network at all, and the model answered HIST:
        # the title sounds like History. The resolver then searched HIST's
        # catalogue, found nothing, and fell back to the pattern '%TROOPER%'.
        # Two failures from one guess, and the second hid the first.
        #
        # The rule the extraction step is given is to leave the network null
        # when the question does not say one, and this is the backstop for when
        # it does not. A programme found on exactly one other network settles
        # it: a series airs where it airs.
        network_corrected = None
        if not rows and network:
            wide = self._q(Q_PROGRAM, phrase=phrase.strip(), network=None)
            found_on = {r["NETWORK_CODE"] for r in wide}
            if len(found_on) == 1:
                network_corrected = next(iter(found_on))
                rows = wide
            elif wide:
                # on several networks, so the network is a real question rather
                # than a mistake to fix quietly. Offer them all.
                rows = wide

        if not rows:
            return {
                "status": "not_found",
                "candidates": [],
                "message": (
                    "No programme in the data matches %r. Nielsen stores titles "
                    "in a %d-character field, so a long title is held cut short; "
                    "try a distinctive word from it." % (phrase, NAME_FIELD_WIDTH)
                ),
            }

        scored = []
        for r in rows:
            rank = r["MATCH_RANK"]
            shared = extra.get(r["PROGRAM_CODE"], 0)
            if rank == 4:
                # word-level only: every stored word present beats some of them
                total = len(_words(r["PROGRAM_NAME"]))
                rank = 4 if shared == total else 5
                how = "ALL_WORDS" if rank == 4 else "WORDS"
            else:
                how = _RANK_NAME[rank]
            scored.append((rank, -shared, how, r))

        # Within a rank, the most recently aired first. Sorting by telecast count
        # alone puts STORAGE WARS TEXAS, which ended in 2014, above CUSTOMER
        # WARS, which is on air now: a question asked today is far more likely
        # to be about the latter, and the list is what someone has to choose
        # from, so its order is the answer's usability.
        scored.sort(key=lambda t: (t[0], t[1],
                                   _neg_date(t[3]["LAST_AIRED"]),
                                   -int(t[3]["TELECASTS"] or 0)))
        best = (scored[0][0], scored[0][1])
        top = [(how, r) for rank, sh, how, r in scored if (rank, sh) == best]

        narrowed_by_recency: list[str] | bool = False
        if len(top) > 1 and active_since:
            live = [(how, r) for how, r in top
                    if (r["LAST_AIRED"] or "") >= active_since]
            # only when it settles the question outright. Narrowing three to two
            # still needs asking, and doing it silently would hide a candidate.
            if len(live) == 1:
                dropped = [_cand(how, r) for how, r in top
                           if r["PROGRAM_NAME"] != live[0][1]["PROGRAM_NAME"]]
                top = live
                # the full record of each, not just the name: the answer offers
                # them as one click, and a click needs a PROGRAM_CODE
                narrowed_by_recency = dropped

        cands = [_cand(how, r) for how, r in top]

        if len(top) == 1:
            r = top[0][1]
            return {
                "status": "resolved",
                "network": r["NETWORK_CODE"],
                "program_code": r["PROGRAM_CODE"],
                "program_name": r["PROGRAM_NAME"],
                "match": top[0][0],
                # the names dropped for being off air, so the answer can say
                # which candidates it set aside rather than silently choosing
                "narrowed_by_recency": narrowed_by_recency,
                "candidates": cands,
                # [RESOLVER-NETWORK] set when the network asked for held no such
                # programme and exactly one other network did. The caller shows
                # it, because a network moving under the person is worth saying
                # out loud even when the new one is right.
                "network_corrected_from": (network if network_corrected
                                           and network_corrected != network else None),
            }

        networks = {r["NETWORK_CODE"] for _, r in top}
        # What resolves it depends on why it is ambiguous. Two programmes on
        # different networks are one title in two places, and the network
        # separates them. Two programmes on the same network are two different
        # series that happen to share a word, and no network name will help:
        # saying otherwise sends someone off to add a detail that changes
        # nothing.
        if len(networks) > 1:
            # naming the network only settles it if each network has one
            per_net = {}
            for _, r in top:
                per_net[r["NETWORK_CODE"]] = per_net.get(r["NETWORK_CODE"], 0) + 1
            if max(per_net.values()) == 1:
                msg = ("%r matches %d programmes, one on each of %s. Naming the "
                       "network resolves it."
                       % (phrase, len(top), ", ".join(sorted(networks))))
            else:
                msg = ("%r matches %d programmes across %d networks, and more "
                       "than one on some of them, so pick one."
                       % (phrase, len(top), len(networks)))
        else:
            msg = ("%r matches %d different programmes on %s. They are separate "
                   "series, so pick one."
                   % (phrase, len(top), next(iter(networks))))
        return {
            "status": "ambiguous",
            "candidates": cands,
            "message": msg,
        }

    # ----------------------------------------------------------------------
    # season
    # ----------------------------------------------------------------------

    def find_season(self, network: str, program_code: str,
                    asked: str | None = None) -> dict:
        digits = re.sub(r"[^0-9]", "", asked or "")
        rows = self._q(Q_SEASONS, network=network, program_code=program_code,
                       asked=asked, asked_num=digits or None)
        if not rows:
            return {"status": "not_found", "seasons": []}

        listing = [
            {
                "ct_season": r["CT_SEASON"],
                "telecasts": int(r["TELECASTS"] or 0),
                "from": r["SEASON_FROM"],
                "to": r["SEASON_TO"],
                "current": r["IS_CURRENT_SEASON"] == "TRUE",
                "sub_season": r["IS_SUB_SEASON"] == "TRUE",
            }
            for r in rows
        ]

        def scope(r):
            return ("Season %s, %s to %s, %d telecasts"
                    % (r["CT_SEASON"], r["SEASON_FROM"], r["SEASON_TO"],
                       int(r["TELECASTS"] or 0)))

        if not asked:
            cur = next((r for r in rows if r["IS_CURRENT_SEASON"] == "TRUE"), rows[0])
            return {"status": "resolved", "ct_season": cur["CT_SEASON"],
                    "scope": scope(cur), "seasons": listing,
                    # [PREMIERE-DATE] the raw dates, not only the sentence. The
                    # first telecast of a season IS its premiere, and that is a
                    # fact about the data rather than something to be read out
                    # of a question: "the season premiere of Greatest Machines"
                    # names no date, and 1 June 2026 is nowhere in the words.
                    "season_from": cur["SEASON_FROM"],
                    "season_to": cur["SEASON_TO"]}

        hits = [r for r in rows if r["MATCHES_REQUEST"] == 1]

        if not hits:
            return {
                "status": "not_found",
                "seasons": listing,
                "message": ("That series has no season %s. It has %d: %s."
                            % (asked, len(rows),
                               ", ".join(r["CT_SEASON"] for r in rows))),
            }

        if len(hits) > 1:
            return {
                "status": "ambiguous",
                "seasons": listing,
                "candidates": [r["CT_SEASON"] for r in hits],
                # A&E, week 10: sub-seasons are separate seasons. Choosing one
                # here would contradict that rather than approximate it.
                "message": ("Season %s exists as %s. These are separate seasons, "
                            "so which one?"
                            % (asked, " and ".join(repr(r["CT_SEASON"]) for r in hits))),
            }

        return {"status": "resolved", "ct_season": hits[0]["CT_SEASON"],
                "scope": scope(hits[0]), "seasons": listing,
                "season_from": hits[0]["SEASON_FROM"],
                "season_to": hits[0]["SEASON_TO"]}

    # ----------------------------------------------------------------------
    # network, demo, date, stream
    # ----------------------------------------------------------------------

    def network_context(self, network: str, stream: str = "Live+SD"):
        rows = self._q(Q_CONTEXT, network=network, stream=stream)
        return rows[0] if rows else None

    def default_demo(self, network: str) -> tuple[str | None, str | None]:
        rows = self._q(Q_DEFAULT_DEMO, network=network)
        return ((rows[0]["DEFAULT_DEMO"], rows[0]["DEMO_SOURCE"])
                if rows else (None, None))

    def latest_night(self, network: str, stream: str = "Live+SD",
                     quarter_hour: bool = False) -> dict:
        c = self.network_context(network, stream)
        if not c:
            return {"status": "not_found",
                    "message": "No coverage recorded for %s on %s." % (network, stream)}

        night = (c["LATEST_QH_BROADCAST_DATE"] if quarter_hour
                 else c["LATEST_BROADCAST_DATE"])
        if quarter_hour and not night:
            return {
                "status": "not_daypartable",
                "message": ("%s carries no quarter-hour rows, so it cannot answer "
                            "a dayparted question. C3 and C7 exist at total-program "
                            "level only." % stream),
            }
        out = {"status": "resolved", "date": night,
               "latest_full_sunday": c["LATEST_FULL_SUNDAY"]}
        lag = c["QH_LAG_DAYS"]
        if lag and str(lag) not in ("0", "", "None"):
            out["note"] = ("Quarter-hour data for %s is %s day(s) behind total "
                           "program, so 1.2 and 1.4 answer about an earlier night "
                           "than 1.1." % (network, lag))
        return out

    def latest_any(self, stream: str = "Live+SD"):
        """The last night with data on a stream, across every network.

        The ranker queries have no single network to ask about, and a fiscal year
        anchored on the calendar instead runs past the data: SP_4 came back
        ending 2026-09-01 against a warehouse that stops on 2026-08-09. Nothing
        sat in the gap, so the figures were right and the window was not, which
        is the kind of wrong that stays hidden until the day it isn't.
        """
        rows = self._q(Q_LATEST_ANY, stream=stream)
        return rows[0]["D"] if rows and rows[0]["D"] else None

    def can_be_dayparted(self, stream: str) -> bool:
        rows = self._q(Q_DAYPARTABLE, stream=stream)
        return bool(rows and (rows[0]["N"] or 0) > 0)

    def summary(self) -> dict:
        r = self._q(Q_SUMMARY)[0]
        return {k.lower(): r[k] for k in r.keys()}


_resolver: Resolver | None = None


def get_resolver() -> Resolver:
    """One instance, loaded once. Three thousand rows in memory costs nothing
    and beats rebuilding the database per request."""
    global _resolver
    if _resolver is None:
        _resolver = Resolver()
    return _resolver
