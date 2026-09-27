"""Parameters CRISpy sets on its own, and why.

There are two ways a parameter gets a value. Most of the time the question
supplies it, or it falls to a documented default and the query resolves it. This
module is about the third way, which is the one that is easy to lose.

Some parameters have to be set EXPLICITLY, to a value that is not the query's
default, because that is what reproduces A&E's own method. Nobody writes them in
the question and A&E do not write them on their sheets either. They were derived
by reconstructing published figures, and every one of them is anchored to a
number that matched.

Two kinds.

METHOD PINS are unconditional. Ask 2.2 about any premiere on any network and the
norm has to be the fiscal year to the day before that premiere, clipped to prime,
with Curse of Oak Island left in. The question never says so. If CRISpy leaves
these to the defaults the query still runs, still returns rows, and returns the
wrong norm.

CONDITIONAL PINS depend on what the question is about rather than on what it
says. A question about a Lifetime movie needs p_movies ONLY, p_grain TELECAST and
p_include_specials TRUE, none of which the person will think to mention, and all
three of which are needed before the answer can name the film.

The reason this is a module rather than prompt text: a model asked to remember
eleven method rules will remember most of them most of the time, and the failures
are silent. A pin applied in code is applied every time and shows up in the
parameter table with its reason attached, so the person reading the answer can
see that CRISpy set it and why.
"""

from __future__ import annotations
from dataclasses import dataclass


@dataclass(frozen=True)
class Pin:
    param: str
    value: object          # a literal, or a token below that the renderer resolves
    why: str               # shown to the person, in the parameter table
    evidence: str          # the figure it was derived from


# Tokens the renderer resolves at render time, because they depend on the target
# rather than being constants.
FY_START_OF_TARGET = "@FY_START_OF_TARGET"     # fiscal year start containing the target date
DAY_BEFORE_TARGET = "@DAY_BEFORE_TARGET"       # the day before the premiere being measured


# ==========================================================================
# Method pins, applied whenever the query runs
# ==========================================================================

# [S3-R1EXCL] R_1's outstanding gap is NOT pinned here, and deliberately.
#
# A&E's genre ranker carries five programmes fewer than ours: the three 90 DAY
# ... TELL titles on two telecasts each, LITTLE SINGLES on two, and LOVE IT OR
# LIST IT on one. All five aired inside their window and every AA figure
# reproduces, so it is neither a date nor a calculation.
#
# A minimum telecast count would account for most of it, and one of three used to
# live in this query before being removed for appearing in neither the PRD nor
# any check-in note. It is not coming back on the strength of a pattern fitted to
# six numbers. A ranker that silently drops titles is an editorial decision about
# what counts as a series, and a rule inferred from the answer is a rule nobody
# agreed to.
#
# The five are named. The question to A&E is why their ranker does not carry
# them, and their answer decides what goes here.


METHOD_PINS: dict[str, list[Pin]] = {

    "2.2": [
        Pin("p_norm_from", FY_START_OF_TARGET,
            "A&E build the premiere norm from the start of the fiscal year, not "
            "over a trailing twelve months.",
            "SP_7: their sections 23 and 24 both print 09/29/25 to 05/31/26."),
        Pin("p_norm_to", DAY_BEFORE_TARGET,
            "The norm stops the day before the premiere it is measuring, so a "
            "telecast is never inside its own norm.",
            "SP_7: the series runs to 13 July and the norm stops 31 May."),
        Pin("p_norm_start_2959", 2000,
            "The norm is prime 8p to 11p, and each telecast counts only for the "
            "part of itself inside that window.",
            "SP_7: 17,155 clipped minutes against 17,641 unclipped."),
        Pin("p_norm_end_2959", 2300,
            "Prime ends at 11p here, not midnight.",
            "SP_7: 8p to 12a gives 248, not their 250."),
        Pin("p_exclude_curse", False,
            "Curse of Oak Island stays IN this norm. It is excluded from 2.7's "
            "lift norm and included here, and both readings are backed by figures.",
            "SP_7: excluding it gives 223 against their 250."),
        Pin("p_include_specials", True,
            "Specials count toward this norm.",
            "SP_7: without them the night count is 138, not 142."),
    ],

    "2.1": [
        Pin("p_norm_from", FY_START_OF_TARGET,
            "When the question is about a premiere, A&E measure the time-period "
            "norm over the fiscal year to the day before it.",
            "SP_7: 245 days, 44,100 minutes and 182, all three exact."),
        Pin("p_norm_to", DAY_BEFORE_TARGET,
            "Same window as the premiere norm beside it.",
            "SP_7."),
    ],

    "2.7": [
        Pin("p_exclude_curse", True,
            "Curse of Oak Island is left OUT of the lift norm. This is the "
            "opposite of 2.2 and both are correct.",
            "HIST Greatest Mysteries: norm lift +73k."),
    ],

    "3.1": [
        # As of this patch 3.1 also defaults to 15, so this pin no longer changes
        # the run. It stays because the pin is the record of WHY: a pin that
        # agrees with a default is documentation, and a default that quietly
        # drifts away from its pin is a bug someone will have to find twice.
        Pin("p_slot_min_min", 15,
            "A half hour the series barely touches is not part of its time "
            "period. Fifteen minutes is half a half hour, so a slot has to be at "
            "least half occupied to count.",
            "R_3: without it the period is 90 minutes over three slots instead "
            "of A&E's 60 over two, and A&E reads 243 instead of 258."),
    ],

    "3.3": [
        Pin("p_premieres_only", True,
            "A programme ranker ranks premieres.",
            "R_1: their sheet is headed Premiere Program Ranker. Without it "
            "Curse of Oak Island comes back over 53 telecasts instead of 25."),
        Pin("p_genre_2_exclude", "SPORTS",
            "The first genre level cannot separate WWE SMACKDOWN from TOURNAMENT "
            "OF CHAMPIONS, because both read NON-FICTION. The second reads SPORTS "
            "against REALITY COMPETITION.",
            "R_1: without it WWE ranks third in a list it does not appear in."),
    ],
}


# ==========================================================================
# Conditional pins, applied when the question is about a certain kind of thing
# ==========================================================================

@dataclass(frozen=True)
class ConditionalPin:
    when: str              # the condition, in words, for the log
    applies_to: tuple      # query ids
    pins: tuple            # Pin objects
    why: str


CONDITIONAL_PINS: list[ConditionalPin] = [

    ConditionalPin(
        when="the question is about a movie or a movie slate",
        applies_to=("2.7", "2.8", "2.12", "1.1"),
        why=(
            "Three parameters have to move together for a movie question and a "
            "person will not think to mention any of them. Movies are excluded by "
            "default because that is right for a series question. Lifetime's "
            "movies are flagged as specials in Cable Tracks, so leaving specials "
            "out deletes the slate. And the film's title is the EPISODE: the "
            "PROGRAM is the bucket it was bought under, so at series grain the "
            "honest answer to which movie is the name of a slate."
        ),
        pins=(
            Pin("p_movies", "ONLY",
                "The question is about movies, so movies are the universe.",
                "SP_4 and SP_5 both returned nothing with the default."),
            Pin("p_include_specials", True,
                "Lifetime's movies are specials in Cable Tracks.",
                "SP_4: excluding them removes most of the 81 telecasts."),
            Pin("p_grain", "TELECAST",
                "The film is the episode, not the programme.",
                "SP_4: the answer is DOUBLE DOUBLE TROUBLE, and the programme "
                "is MOVIE- ORIGINAL PREM."),
        ),
    ),

    ConditionalPin(
        when="the question is about holiday content",
        applies_to=("2.7", "2.8", "2.12"),
        why=(
            "IS_HOLIDAY was baked on the telecast table from the start and was "
            "never exposed as a parameter, so the holiday half of a holiday "
            "question could not be asked at all. Unpinned, SP_5 returned the "
            "highest Live+3 lift of any Lifetime film - a real number, correctly "
            "computed, answering a question nobody had asked. That is the worst "
            "shape a wrong answer can take, because nothing about it looks wrong."
            "\n\n"
            "The flag is derived from PROGRAM_NAME and requires MOVIE_IND = 1, so "
            "it reaches holiday FILMS only. A holiday special that is not a film "
            "is invisible to it, on every table. If a question is about holiday "
            "programming in general rather than holiday movies, this pin is not "
            "enough and the honest answer says so."
        ),
        pins=(
            Pin("p_holiday", True,
                "The question is about holiday content, so holiday films are the "
                "universe rather than a subset of it.",
                "SP_5: VERY MERRY BEAUTY SALON, 205 to 308, +50.2%. Unpinned the "
                "query returned SEASON AVERAGE across the whole movie slate."),
        ),
    ),

    ConditionalPin(
        when="the question is about the season premiere",
        applies_to=("2.1", "2.2", "2.12"),
        why=(
            "A season premiere is one telecast, the first of the season, and "
            "A&E said so in as many words: 'do not return the full-season "
            "average'. 2.12 lists every episode of the season, so without this "
            "pin the answer is built from eight rows and the written response "
            "called the average 'the premiere'. IS_PREMIERE_CT on the tables now "
            "marks the season opener, and the query filters to it."
        ),
        pins=(
            Pin("p_premiere_only", True,
                "The question is about the season premiere, so the answer is "
                "that one telecast, with the season average beside it for context.",
                "SP_7: AERIAL ATTACKERS, 2026-06-01, 266k. Unpinned the query "
                "returned all eight episodes and the answer averaged them to 221k. "
                "On 2.2 the same pin measures that one telecast against the "
                "network's 12-month premiere norm, which is the answer A&E "
                "asked for on 24 Sep 2026: one row, premiere vs premiere norm."),
        ),
    ),

    ConditionalPin(
        when="the question is about the season's quarter hours",
        applies_to=("2.11",),
        why=(
            "Jill, 23 Sep 2026: the series snapshot wants the average quarter "
            "hour across all telecasts for the season, four lines and QH4 vs QH1, "
            "not the quarter hours of every telecast. 2.11 returns the latter by "
            "default so single-telecast questions still work; this pin switches "
            "it to the season view."
        ),
        pins=(
            Pin("p_rollup", True,
                "The question is about the season's quarter hours, so the answer "
                "is four rows, QH1 to QH4 averaged across every telecast.",
                "SP_IND_10: Skinwalker season 7, four rows instead of fifty-six."),
        ),
    ),

    ConditionalPin(
        when="the question is about the series and its lead-in",
        applies_to=("2.10",),
        why=(
            "Jill, 24 Sep 2026: not one row per telecast. The series vs its "
            "lead-in is the season average against the average of all its "
            "lead-ins, then by lead-in programme. 2.10 keeps the per-night rows "
            "by default for the overnight question; this pin switches it to the "
            "season view when the question is about the series."
        ),
        pins=(
            Pin("p_rollup", True,
                "The question is about the series and its lead-in across the "
                "season, so the answer is the season rows, not one per night.",
                "SP_IND_9: Skinwalker season 7, ALL LEAD-INS 335 vs 142, then per lead-in."),
        ),
    ),

    # [FY-DATES] REMOVED: the pin that forced p_fiscal_year to null.
    #
    # Its reasoning was sound when it was written - "leave it null so the query
    # resolves the year from A&E's calendar rather than from a date the model
    # computed" - because a model asked for the bounds of a fiscal year is right
    # most of the time, which is the worst failure rate a date can have.
    #
    # What it could not express is WHICH year. `SET fy = COALESCE($p_fiscal_year,
    # <the year the data ends in>)`, with the parameter always null, can only
    # ever answer about the current one. That was invisible for as long as every
    # benchmark asked about FY26: R_1 and R_6 both do, and both passed. Ask 3.2
    # about FY 2025 and it answers about FY26, with a rank that reads entirely
    # reasonable.
    #
    # fiscal.py now resolves the year and its bounds from the same last-Monday-of
    # -September rule the calendar table uses, so the year reaches the SQL as a
    # number and the dates as dates. Nothing is computed by the model; the pin's
    # concern is met somewhere it can also carry the answer.

    ConditionalPin(
        when="the question asks for a ranker on a specific published date",
        applies_to=("3.2", "3.3"),
        why=(
            "A ranker with no end date runs to wherever the data reaches, which "
            "is right in production and wrong against a published figure."
        ),
        pins=(
            Pin("p_fy_to", DAY_BEFORE_TARGET,
                "The fiscal year to date stops where the question says it stops.",
                "R_6: unpinned it ran five weeks past A&E's cut and returned 185 "
                "at rank 8 instead of 184 at rank 7."),
        ),
    ),
]


def method_pins_for(query_id: str) -> list[Pin]:
    return METHOD_PINS.get(query_id, [])


def conditional_pins_for(query_id: str, flags: dict) -> list[tuple[Pin, str]]:
    """Pins that apply given what the question turned out to be about.

    `flags` comes from the parameter step: is_movie_question, is_holiday_question,
    is_season_premiere_question, names_fiscal_year, has_published_cutoff. Returns pairs of pin and the reason
    to show.
    """
    key = {
        "the question is about a movie or a movie slate": bool(flags.get("is_movie_question")),
        "the question is about holiday content": bool(flags.get("is_holiday_question")),
        "the question is about the season premiere": bool(flags.get("is_season_premiere_question")),
        "the question is about the season's quarter hours": bool(flags.get("is_season_qh_question")),
        "the question is about the series and its lead-in": bool(flags.get("is_series_leadin_question")),
        "the question names a fiscal year or says this fiscal year": bool(flags.get("names_fiscal_year")),
        "the question asks for a ranker on a specific published date": bool(flags.get("has_published_cutoff")),
    }
    out = []
    for cp in CONDITIONAL_PINS:
        if query_id in cp.applies_to and key.get(cp.when):
            for p in cp.pins:
                out.append((p, cp.why))
    return out
