"""A&E's fiscal year, resolved once and turned into dates.

A fiscal year can be named in any question that accepts a window, which is all
twenty-two. It was being handled three different ways - `p_fiscal_year` on 3.2
and 3.3, `p_fy_to` on 3.2 alone, and a `names_fiscal_year` flag everywhere else
that let each query fall back to its own default. Three vocabularies for one
idea, and R_1 showed what that costs: the planner set `p_fiscal_year` to null and
`p_win_to` to a date, half in each language, and the run went to whichever year
the data happened to reach.

The rule here is that a fiscal year always arrives at the SQL as two dates. The
queries keep one pair of window parameters and never learn what a fiscal year is.

WHY THE DATES ARE COMPUTED AND NOT ASKED FOR
A fiscal year is not a calendar one, so a model asked for its bounds will be
right most of the time - which is the worst failure rate a date can have, because
nothing downstream can tell a wrong year from a right one. FY26 begins on
2025-09-29 and FY25 on 2024-09-30, and neither is guessable from the number.

CRIS_FY_CALENDAR holds the same boundaries in the warehouse. This module has to
agree with it; if the two ever disagree the calendar is right, because that is
what the SQL joins against.
"""

from __future__ import annotations

from datetime import date, timedelta


def _last_monday_of_september(year: int) -> date:
    d = date(year, 9, 30)
    while d.weekday() != 0:          # Monday
        d -= timedelta(days=1)
    return d


def fy_start(fiscal_year: int) -> date:
    """First day of a fiscal year. FY26 starts in September 2025."""
    return _last_monday_of_september(fiscal_year - 1)


def fy_end(fiscal_year: int) -> date:
    """Last day, which is the day before the next one begins."""
    return fy_start(fiscal_year + 1) - timedelta(days=1)


def fy_containing(d: date) -> int:
    """Which fiscal year a date falls in."""
    start = _last_monday_of_september(d.year)
    return d.year + 1 if d >= start else d.year


def bounds(fiscal_year: int, as_of: date | None = None) -> tuple[str, str]:
    """The window for a fiscal year, as ISO dates.

    `as_of` truncates a year still in progress. Without it, asking for the
    current fiscal year returns a window running months past the last night with
    data - which is not wrong exactly, but it reports an end date the data cannot
    support and invites the reader to believe the gap is a quiet period.
    """
    start = fy_start(fiscal_year)
    end = fy_end(fiscal_year)
    if as_of and as_of < end:
        end = as_of
    return start.isoformat(), end.isoformat()


def resolve(fiscal_year: int | None,
            names_fiscal_year: bool,
            win_from: str | None,
            win_to: str | None,
            latest: str | None) -> tuple[str | None, str | None, str | None]:
    """Turn whatever the question said about a fiscal year into a window.

    Returns (win_from, win_to, label). The label is what the answer should say it
    measured, and it exists because "FY 2025" and "FY 2026" produce numbers that
    look equally plausible: without the label, a run against the wrong year is
    indistinguishable from a run against the right one.

    An explicit date always wins over the fiscal year that contains it. That is
    what "fiscal year 2026 to-date thru 6/28/26" means: the year gives the start,
    the date gives the end, and neither is redundant.
    """
    if not (fiscal_year or names_fiscal_year):
        return win_from, win_to, None

    as_of = date.fromisoformat(latest) if latest else None

    if fiscal_year is None:
        # "this fiscal year", with no number: whichever one the data is in.
        # Anchored on the data rather than on today, so a run during a lull does
        # not roll into a fiscal year that has barely started.
        if as_of is None:
            return win_from, win_to, None
        fiscal_year = fy_containing(as_of)

    start, end = bounds(fiscal_year, as_of)

    # A date the question actually gave outranks the computed bound.
    out_from = win_from or start
    out_to = win_to or end

    label = f"FY{fiscal_year % 100:02d} ({out_from} to {out_to})"
    if win_to and win_to < end:
        label += " to-date"
    return out_from, out_to, label
