"""What CRISpy knows before anyone asks it anything.

Everything in this module is settled fact from the CRIS Section 1 notebook or
from a decision A&E made in a check-in. None of it is inferred at runtime, and
none of it is left to the model to remember: the model reads it as context and
picks from it, which is the difference between a planner and a guess.
"""

from __future__ import annotations

import re

# --------------------------------------------------------------------------
# Networks
# --------------------------------------------------------------------------
# A wrong network returns zero rows with no error, which looks exactly like a
# quiet night rather than a mistake. So the network is never inferred from
# anything but the question itself or the programme named in it.

NETWORKS: dict[str, dict] = {
    "AEN":  {"name": "A&E",       "aliases": ["a&e", "ae", "aen", "a and e", "a+e"]},
    "HIST": {"name": "History",   "aliases": ["history", "history channel", "hist", "the history channel"]},
    "LIF":  {"name": "Lifetime",  "aliases": ["lifetime", "lif", "lft"]},
    "LMN":  {"name": "LMN",       "aliases": ["lmn", "lifetime movie network", "lifetime movies"]},
    "FYI":  {"name": "FYI",       "aliases": ["fyi"]},
    "VICE": {"name": "VICE",      "aliases": ["vice", "vice tv", "viceland"]},
}

# --------------------------------------------------------------------------
# Demos
# --------------------------------------------------------------------------
# A demo is a column name from the source view. Nothing is composed or summed:
# the name IS the column, so a figure in an answer traces back to the DDL with
# no translation step in between.
#
# DEMO_AA is the per-network default, resolved inside the prepared table. It is
# the reason one run across several networks gives each of them its own demo.
# Leaving p_demo NULL is therefore not "no demo", it is "each network's own".

DEFAULT_DEMO_BY_NETWORK = {
    "AEN":  "P25_64_AA_ESTIMATES",
    "HIST": "P25_64_AA_ESTIMATES",
    "FYI":  "P25_64_AA_ESTIMATES",
    "LIF":  "F25_64_AA_ESTIMATES",
    "LMN":  "F25_64_AA_ESTIMATES",
    "VICE": "P18_49_AA_ESTIMATES",
}

# The demos a question is likely to name, mapped to their column. This is a
# convenience layer over the view, not a restriction: any AA column the view
# carries is valid, and DEMO_ALIASES only saves the model from having to know
# that W25-64 is spelled F25_64_AA_ESTIMATES.
DEMO_ALIASES: dict[str, str] = {
    "a25-64": "P25_64_AA_ESTIMATES", "p25-64": "P25_64_AA_ESTIMATES",
    "a25-54": "P25_54_AA_ESTIMATES", "p25-54": "P25_54_AA_ESTIMATES",
    "a18-49": "P18_49_AA_ESTIMATES", "p18-49": "P18_49_AA_ESTIMATES",
    "a18-34": "P18_34_AA_ESTIMATES", "p18-34": "P18_34_AA_ESTIMATES",
    "a35-54": "P35_54_AA_ESTIMATES",
    "a18+":   "P18_AA_ESTIMATES",    "a25+": "P25_AA_ESTIMATES",
    "p25+":   "P25_AA_ESTIMATES",    "p2+":  "P2_AA_ESTIMATES",
    "total viewers": "P2_AA_ESTIMATES", "p2": "P2_AA_ESTIMATES",
    "w25-64": "F25_64_AA_ESTIMATES", "f25-64": "F25_64_AA_ESTIMATES",
    "w25-54": "F25_54_AA_ESTIMATES", "w18-49": "F18_49_AA_ESTIMATES",
    "w18-34": "F18_34_AA_ESTIMATES", "w18+":   "F18_AA_ESTIMATES",
    "m25-64": "M25_64_AA_ESTIMATES", "m25-54": "M25_54_AA_ESTIMATES",
    "m18-49": "M18_49_AA_ESTIMATES", "m18-34": "M18_34_AA_ESTIMATES",
    "households": "HH_AA_ESTIMATES", "hh": "HH_AA_ESTIMATES",
}

# 14 columns exist at telecast level and not at quarter-hour. A demo can
# therefore answer in 1.1 and return nothing in 1.2. That is the file, not the
# build, and CRISpy says so rather than returning an empty table.
QUARTER_HOUR_MISSING_DEMOS = {
    "P35_49_AA_ESTIMATES", "P50_64_AA_ESTIMATES",
    "M35_49_AA_ESTIMATES", "M35_54_AA_ESTIMATES",
    "F35_49_AA_ESTIMATES", "F35_54_AA_ESTIMATES",
    "M50PLUS_AA_ESTIMATES", "F50PLUS_AA_ESTIMATES",
    "M55PLUS_AA_ESTIMATES", "F55PLUS_AA_ESTIMATES",
    "M50_64_AA_ESTIMATES", "F50_64_AA_ESTIMATES",
    "M2_17_AA_ESTIMATES", "F2_17_AA_ESTIMATES",
}

# --------------------------------------------------------------------------
# Playback streams
# --------------------------------------------------------------------------
STREAMS = ["Live+SD", "Live+3", "Live+7", "ACM - Live+3", "ACM - Live+7"]
DEFAULT_STREAM = "Live+SD"

STREAM_ALIASES = {
    # L+SD is how A&E write it in their own questions, and it was the one
    # shorthand missing while l+3 and l+7 were both here. Unmapped it passes
    # through as the literal 'L+SD', which matches no RATING_SOURCE in the data:
    # zero rows, no error, and a ranker that reads like a quiet fiscal year.
    "live+sd": "Live+SD", "live sd": "Live+SD", "lsd": "Live+SD",
    "l+sd": "Live+SD", "l sd": "Live+SD", "same day": "Live+SD",
    "live+3": "Live+3", "l+3": "Live+3", "live plus 3": "Live+3",
    "live+7": "Live+7", "l+7": "Live+7", "live plus 7": "Live+7",
    "c3": "ACM - Live+3", "acm live+3": "ACM - Live+3",
    "c7": "ACM - Live+7", "acm live+7": "ACM - Live+7",
}

# The ACM streams carry no quarter-hour rows at all. Confirmed twice: measured
# in the notebook's discovery pass, and confirmed by A&E in the week 10
# check-in. Any question that needs a quarter hour on C3 or C7 is unanswerable
# from the data, and saying so beats returning an empty table.
STREAMS_WITHOUT_QUARTER_HOURS = {"ACM - Live+3", "ACM - Live+7"}

# And no half-hour rows either, which is a bigger hole because every dayparted
# answer is built on half hours: prime is the half hours whose own start falls
# between 8p and 11p. This is A&E's R_2, the one case in their whole validation
# workbook that cannot be answered. Measured: ACM - Live+3 returns zero half-hour
# rows across zero networks.
#
# Their own footer on that sheet reads "Dayparts are ACM Program based and
# Commercial Duration weighted", which suggests they daypart C3 at PROGRAMME
# level rather than on half hours. If that is confirmed the total-programme table
# could support it and this stops being a dead end. Open with A&E.
STREAMS_WITHOUT_HALF_HOURS = {"ACM - Live+3", "ACM - Live+7"}


def resolve_network(text: str) -> str | None:
    """Map free text to a network code, or None. Never guesses."""
    if not text:
        return None
    t = text.strip().lower()
    for code, meta in NETWORKS.items():
        if t == code.lower() or t in meta["aliases"] or t == meta["name"].lower():
            return code
    return None


def resolve_demo(text: str | None, network: str | None) -> tuple[str | None, str | None]:
    """Return (column, note).

    A named demo outside the recognised set falls back to the network default
    and says so. It never substitutes the nearest available range: adults 25-64
    and adults 25-54 are different audiences, and presenting one as the other
    misstates the answer rather than approximating it.
    """
    if not text:
        return None, None                      # NULL = the network's own default
    t = text.strip().lower().replace(" ", "")
    for key, col in DEMO_ALIASES.items():
        if t == key.replace(" ", ""):
            return col, None
    if text.strip().upper().endswith("_AA_ESTIMATES"):
        return text.strip().upper(), None      # named the column outright
    fallback = DEFAULT_DEMO_BY_NETWORK.get(network or "", "the network default")
    return None, (
        f"{text!r} is not a demo CRISpy recognises, so the query keeps the network "
        f"default ({fallback}). It does not substitute the closest match."
    )


def resolve_stream(text: str | None) -> str:
    if not text:
        return DEFAULT_STREAM
    return STREAM_ALIASES.get(text.strip().lower(), text.strip())


# --------------------------------------------------------------------------
# Content strands
# --------------------------------------------------------------------------
# [CONTENT-STRAND] Words that describe CONTENT but are stored as part of a
# programme NAME, so the only way to filter on them is a name pattern.
#
# SP_5 is the case. "Which holiday movie on LFT had the highest L+3 lift" turns
# on the word holiday, and there is no holiday column anywhere in the query. On
# Lifetime the slate is carried as four buckets:
#
#     MOVIE- ORIGINAL PREM          originals
#     MOVIE- ACQUIRED PREM          acquired
#     MOVIE- ORIGINAL HOL PREM      originals, Christmas
#     MOVIE- ACQUIRED HOL PREM      acquired, Christmas
#
# so the only thing separating the holiday titles is the HOL in the bucket
# name. The benchmark cell reaches it with p_program = '%HOL PREM%', which is
# not really a programme filter: it is a content filter smuggled in through a
# name pattern.
#
# CONFIRMED with A&E, Aug-2026: there is no holiday indicator in the data. The
# bucket name is how they identify it. So this is not a workaround standing in
# for a proper flag, and it should not be marked as one: it IS the convention,
# and reproducing it is reproducing their method rather than approximating it.
#
# That is worth stating plainly, because a name pattern looks like a shortcut
# and someone will eventually try to replace it with a "real" column. There is
# no real column. Removing this would remove the only way the question can be
# answered.
#
# The model cannot derive it either way. It would have to know how Lifetime
# codes its slate, and that is nowhere it can read. So it sits here beside
# LFT -> LIF, because it is the same kind of fact: a word A&E use, mapped to
# what the data holds.
#
# What this is NOT: a rule about holidays. It is a rule about how ONE network
# names ONE slate. Scoped to LIF and LMN, and it stays scoped until the
# convention is shown somewhere else.
#
# What to watch instead of a flag: the bucket names themselves. This depends on
# HOL PREM surviving in PROGRAM_NAME, so a renamed bucket breaks it silently and
# the ranker comes back short with no error. If the SP_5 case ever stops
# reproducing VERY MERRY BEAUTY SALON, check the names before checking anything
# else.

CONTENT_STRANDS: dict[str, dict] = {
    "holiday": {
        "pattern": "%HOL PREM%",
        "networks": ("LIF", "LMN"),
        "aliases": ["holiday", "christmas", "xmas", "festive", "holiday movie",
                    "holiday movies", "christmas movie", "christmas movies"],
        "note": (
            "Lifetime carries its Christmas slate as MOVIE- ORIGINAL HOL PREM "
            "and MOVIE- ACQUIRED HOL PREM. There is no holiday flag in the data: "
            "the bucket name is how A&E identify it, confirmed Aug-2026, so "
            "matching on the name is their method rather than a substitute for it."
        ),
    },
}


def resolve_content_strand(text: str | None, network: str | None) -> tuple[str | None, str | None]:
    """[CONTENT-STRAND] A content word to a programme-name pattern, or nothing.

    Returns (pattern, note). Nothing on a network the strand is not defined for,
    because a pattern that means something on Lifetime means nothing on History
    and would filter a ranker down to zero rows without saying why.
    """
    if not text:
        return None, None
    t = text.strip().lower()
    # [CONTENT-STRAND] resolved the same way as the reader's, so the two cannot
    # disagree about what LFT means
    code = resolve_network(network) if network else None
    for _, strand in CONTENT_STRANDS.items():
        if t in strand["aliases"] or any(a in t for a in strand["aliases"]):
            if code and code not in strand["networks"]:
                return None, (
                    f"{text!r} is only defined as a content strand on "
                    f"{' and '.join(strand['networks'])}, so it was not applied "
                    f"to {network}."
                )
            return strand["pattern"], strand["note"]
    return None, None


# --------------------------------------------------------------------------
# Deterministic reads
# --------------------------------------------------------------------------
# [DETERMINISTIC] Two fields that were on the classifier and should never have
# been, because neither is a judgement.
#
# content_strand: the word is IN the question. "Which holiday movie on LFT" says
# holiday. There is nothing to infer, and asking a model to notice a word it can
# already see is asking it to fail occasionally at something a match cannot fail
# at. It missed it on SP_5.
#
# asks_about_now: present tense with no period named. Two conditions.
#
# The rule that follows from those two: if a field can be decided by looking at
# the words, it is not the classifier's. What is left there is what genuinely
# needs reading of intent, and a smaller surface fails less.

_NOW_MARKERS = (
    "how is ", "how's ", "how are ", "what is the average", "what's the average",
    "what is ", "is doing", "doing now", "performing", "averaging", "so far",
    "currently", "right now", "this season",
)

# Anything here means a period was NAMED, so the question is not about now even
# when it is phrased in the present tense. "How is season 3 doing" is about
# season 3.
_PERIOD_MARKERS = (
    "fiscal", "last year", "prior season", "previous season",
    "every season", "all seasons", "over the years", "each season", "history of",
    "since ", "between ", "thru ", "through ",
    "compared to last", "vs last", "versus last",
)

# A NAMED season is the word followed by a label: season 9, season 13B, season
# 2026. "Latest season" and "the season average" are not named seasons, and the
# first is the clearest possible case of a question about now.
#
# The word alone was in the list at first and it read SP_1 backwards: "what is
# the average for the LATEST SEASON of Court Cam" came out as a period question,
# so the season was left to the default and the panel lost the 9B it used to
# show. The season the query resolved was the same, which is exactly why it
# would have gone unnoticed.
_NAMED_SEASON = re.compile(r"\bseasons?\s+(\d|[a-z]?\d)", re.I)

# A named fiscal year or an explicit date range. FY on its own is caught by
# "fiscal" above; this catches FY26 and dates.
_NAMED_PERIOD = re.compile(
    r"\bfy\s?\d{2,4}\b|\b(19|20)\d{2}\b|\d{1,2}/\d{1,2}/\d{2,4}", re.I)


def read_content_strand(question: str, network: str | None) -> str | None:
    """[DETERMINISTIC] The strand word, from the question, or nothing.

    Matched on the question text rather than asked of a model, because the word
    is already there. Scoped the same way the strand itself is: a word that
    means something on Lifetime means nothing on History, and applying it there
    would empty a ranker without saying why.
    """
    if not question:
        return None
    q = question.lower()
    # [CONTENT-STRAND] The network arrives as the question said it, not as a
    # code: this runs inside the reading step, before main.py maps the alias. So
    # "which holiday movie on LFT" arrives with LFT, which is not in the strand's
    # network list, and the strand was silently skipped on the one case it was
    # written for. Map it here rather than depending on the caller's ordering.
    code = resolve_network(network) if network else None
    for name, strand in CONTENT_STRANDS.items():
        if code and code not in strand["networks"]:
            continue
        for alias in strand["aliases"]:
            if alias in q:
                return name
    return None


def read_asks_about_now(question: str) -> bool | None:
    """[DETERMINISTIC] Is this about the current season, or across time.

    Returns None rather than False when neither reading is clear, because None
    means the query's own default applies and the default is what every
    validated case ran under. Guessing False here would widen a season question
    to a programme's whole history: eighty rows for someone who wanted twelve.
    """
    if not question:
        return None
    q = question.lower()
    if (any(m in q for m in _PERIOD_MARKERS)
            or _NAMED_SEASON.search(q) or _NAMED_PERIOD.search(q)):
        return False
    if any(m in q for m in _NOW_MARKERS):
        return True
    return None
