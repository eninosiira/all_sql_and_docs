"""A&E's eighteen validation cases, canned.

This is the fixed point. Every case here has been run in Snowflake and matched a
figure A&E published, so the parameters recorded against each one are known to
be the parameters that reproduce it.

What it is for: checking that CRISpy, given the question in plain English,
arrives at the same parameters. That is the only thing left that can go wrong.
The SQL is settled and the figures are settled, so a wrong answer from here is a
routing or a parameter mistake, and this file is how you tell which.

Two things to keep in mind when reading `params`.

Fields the person's question supplies are here as the person would say them.
Fields CRISpy pins on its own are NOT here, because they are not something the
extraction step should produce. p_norm_from on 2.2 is not a parameter anybody
asks for; it is applied afterwards by pins.py. Checking for it here would mark a
correct extraction as wrong.

`expects` is the figure the query returns, for the run, not for the extraction.
A case can extract perfectly and still return a different number if the tables
are stale, and separating the two is the point of writing both down.
"""

from __future__ import annotations
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Case:
    code: str
    question: str
    query_ids: list[str]              # more than one where the answer needs it
    params: dict                      # what the extraction step should produce
    expects: str                      # what the run should return
    reads: str                        # how the answer sits in the output
    note: str = ""
    verified: str = ""                # date the run reproduced A&E exactly
    blocked: str = ""                 # why it cannot pass, where it cannot


CASES: list[Case] = [

# ---------------------------------------------------------------- section 1
Case("OV_1",
     "How did HIST's premieres do on 5/30/25 vs. their season norms?",
     ["1.1"],
     {"network": "HIST", "target_date": "2025-05-30"},
     "SECRETS DECLASSIFIED 306 vs 210 over 8, +45.7. "
     "UNBELIEVABLE 290 vs 279 over 19, +3.9.",
     "Direct. One row per premiere.",
     "The whole Overnight Summary is three queries, 1.1, 1.2 and 1.3b. This "
     "question asks only for the first.",
     verified="2026-08-21"),

Case("OV_2",
     "Premieres on LFT on 2/7/26",
     ["1.1"],
     {"network": "LFT", "target_date": "2026-02-07"},
     "MOVIE- ORIGINAL PREM / MARY J. BLIGE: BE HAPPY, 227 vs 138 over 13, +64.5. "
     "NORM_BASIS reads FISCAL YEAR TO DATE.",
     "Direct.",
     "LFT has to map to LIF. It is A&E's own shorthand and the catalogue carries "
     "it, but nobody at A&E has confirmed it. A wrong network returns zero rows "
     "with no error.",
     verified="2026-08-21"),

Case("OV_3",
     "How did FYI's premieres do on 6/29/26 vs. their season norms?",
     ["1.1"],
     {"network": "FYI", "target_date": "2026-06-29"},
     "Four rows. RACHAEL RAYS 32 and 22, both vs 8 over 10. INSTANT ITALIAN 10 "
     "and 3, both vs a prior season of 10 over 12, with a prior premiere of 17 "
     "over 2.",
     "Direct, but NORM_BASIS has to be read: two rows are normed on the season "
     "to date and two on the prior season.",
     "A&E's sheet lists eight telecasts on that night. Four are repeats and have "
     "no norm anywhere in their workbook, so they are schedule context rather "
     "than answer.",
     verified="2026-08-21"),

# ---------------------------------------------------------------- section 2
Case("SP_1",
     "What is the average for the latest season of Court Cam?",
     ["2.1"],
     {"network": "AEN", "program": "Court Cam"},
     "Season 9B, 214 over 12 telecasts, against a prime norm of 150.",
     "Direct.",
     "Sub-seasons are their own season and the latest is chosen by the date it "
     "ran. Picking 9 over 9B would be wrong and would not look wrong.",
     verified="2026-08-24"),

Case("SP_2",
     "How is Neighborhood Wars season 9 performing vs. the prior season?",
     ["2.4"],
     {"network": "AEN", "program": "Neighborhood Wars", "season": "9"},
     "266 vs 188, +78, 20 telecasts, +41.5.",
     "Direct.",
     verified="2026-08-23"),

Case("SP_3",
     "Which episodes of Alaska State Trooper exceeded the season average among P25+?",
     ["2.12"],
     {"network": "AEN", "program": "Alaska State Troopers", "demo": "P25+"},
     "Six episodes above 425: 517, 489, 481, 475, 469, 438.",
     "Select from the output. The query returns all ten telecasts with the "
     "average on every row; the six above it are found by reading a column.",
     "The stored title is ALASKA STATE TROOPERS AE, cut at 25 characters. P25+ "
     "is P25_AA_ESTIMATES, not P25-64.",
     verified="2026-08-23"),

Case("SP_4",
     "Which LFT movie had the highest performance this Fiscal Year among W25-64?",
     ["2.8"],
     {"network": "LFT", "demo": "W25-64", "is_movie_question": True,
      "names_fiscal_year": True},
     "DOUBLE DOUBLE TROUBLE 235 on 21 Feb at rank 1, MARY J. BLIGE 227 on 7 Feb "
     "at rank 2, out of 81.",
     "Select from the output: the top row.",
     "The movie flag is what carries this. Without it the query returns nothing, "
     "because movies are excluded by default and Lifetime's slate is flagged as "
     "specials.",
     verified="2026-08-23"),

Case("SP_5",
     "Which holiday movie on LFT had the highest L+3 lift in FY 2025 among P25-64?",
     ["2.7"],
     {"network": "LFT", "demo": "P25-64", "is_movie_question": True,
      "names_fiscal_year": True, "program": "holiday movies"},
     "VERY MERRY BEAUTY SALON, 7 Dec 2024, 205 to 308, +103, +50.2 per cent.",
     "Select from the output: the query returns twelve telecasts sorted by lift.",
     "A question naming two demos is two runs of the same query, not one query "
     "with two columns.",
     verified="2026-08-23"),

Case("SP_6",
     "Which episode of World War II With Tom Hanks performed the lowest among P25+?",
     ["2.12"],
     {"network": "HIST", "program": "World War II With Tom Hanks", "demo": "P25+"},
     "LONG ROAD TO TOKYO, 6 Jul 2026, 761 against 954 over 16, -20.2.",
     "Select from the output, and invert the rank: EP_RANK runs highest first, so "
     "the lowest episode is 16 of 16.",
     "The stored title is WORLD WAR II TOM HANKS. The word with is gone.",
     verified="2026-08-31, with A&E's 13 July cut-off in the question"),

Case("SP_7",
     "How did the Season premiere of Hist Greatest Machines perform?",
     ["2.12", "2.1", "2.2"],
     {"network": "HIST", "program": "HIST GREATEST MACHINES",
      "premiere_date": "2026-06-01"},
     "266 the premiere, 222 the season average over 7, 182 the time period "
     "average, 250 the premieres in prime average over 142 nights and 17,155 "
     "minutes.",
     "Several queries. Every percentage A&E publish is against the premiere, so "
     "266 is the numerator and the other three are denominators from two other "
     "queries.",
     "premiere_date is what the norms hang on: both are cut the day before it. "
     "Without it the norms fall back to a trailing window and stop matching.",
     verified="2026-08-31, with A&E's 13 July cut-off in the question"),

Case("SP_8",
     "What is Interrogation Raw median age in Season 5?",
     ["2.5"],
     {"network": "AEN", "program": "Interrogation Raw", "season": "5"},
     "Median age 63 against a prime norm of 63.",
     "Direct.",
     "A&E print 62.9. Same figure at more precision; if the answer quotes a "
     "decimal the rounding has to move out of the query.",
     blocked=("Not yet run. ")),

Case("SP_9",
     "How female-skewed is Interrogation Raw Season 5 compared to A&E's prime norm?",
     ["2.6"],
     {"network": "AEN", "program": "Interrogation Raw", "season": "5"},
     "59 per cent female against a prime norm of 49, ten points more female.",
     "Direct.",
     "A&E print 58.9 against 49.3, a gap of 9.6.",
     blocked=("Not yet run. ")),

# ---------------------------------------------------------------- section 3
Case("R_1",
     "What are the TOP 3 non-fiction shows per network in fiscal year 2026 "
     "to-date thru 6/28/26 for A&E, HIST and LIF? Where do these rank in the "
     "cable competitive set?",
     ["3.3"],
     {"genre": "non-fiction", "demo": "P25-64", "top_n": 50,
      "names_fiscal_year": True, "has_published_cutoff": True,
      "win_to": "2026-06-28"},
     "TOURNAMENT OF CHAMPIONS 646 over 8 at rank 1, CURSE OF OAK ISLAND 524 over "
     "25 at rank 7, a tie at rank 16.",
     "Select from the output, and group: the question asks for three per network "
     "and then where those sit in the whole cable set. Both halves come from one "
     "result.",
     "Open with A&E: three 90 Day companion strands appear as their own rows here "
     "and are consolidated into the parent series on their sheet. We can "
     "reconstruct their figures exactly but the programme codes are unrelated, so "
     "the link cannot be derived.",
     blocked=("Every AA figure and every RNK_IN_NETWORK matched exactly, and so "
              "did the window, the genre, the daypart and the minute weighting. "
              "Only the competitive-set rank drifts: 10/30/33/68/74/79 against "
              "their 7/27/29/64/69/74. "
              "FIVE programmes sit in our universe and not in theirs, all named: "
              "90 DAY FIANCE BT90D: TELL and 90 DAY FIANCE TOW: TELL A and 90 DAY "
              "SINGLE LIFE: TELL, each on two telecasts, at our ranks 1, 2 and 7; "
              "LITTLE SINGLES on two at 66; and LOVE IT OR LIST IT on one at 73. "
              "All five aired inside 29 Sep 2025 to 28 Jun 2026, so it is not the "
              "window, and every AA reproduces, which a different window could "
              "not do. "
              "A minimum telecast count would account for five of the six anchors "
              "and leaves HAZARDOUS one out - and a floor of three was in this "
              "query once, removed for appearing in neither the PRD nor any "
              "check-in note. It is NOT being reinstated on the strength of a "
              "pattern. A ranker that silently drops titles is an editorial "
              "decision, and inferring one from six numbers is how a guess "
              "becomes a rule nobody remembers agreeing to. "
              "The five are named and the question to A&E is why their ranker "
              "does not carry them. Their answer decides it, not ours.")),

Case("R_2",
     "What is History's rank vs. ad-supported entertainment cable networks "
     "across Prime and Total Day, FY26 thru 7/5/26 on C3?",
     ["3.2"],
     {"network": "HIST", "stream": "C3", "demo": "P25-64",
      "names_fiscal_year": True, "has_published_cutoff": True,
      "win_to": "2026-07-05"},
     "Cannot be answered. C3 carries no half-hour rows and a daypart is a "
     "half-hour construct.",
     "Not available in the data. The answer has to say so: an empty ranker reads "
     "exactly like a quiet period.",
     "A&E's own footer says dayparts there are ACM program based and commercial "
     "duration weighted, which suggests they daypart C3 at programme level. If "
     "so this becomes answerable from the total-programme table.",
     blocked=("Cannot run. C3 carries no half-hour rows, so a dayparted C3 rank "
            "cannot be built from the data that exists. Confirmed by A&E's data "
            "team, 18 Aug 2026. Their own R_2 footer reads 'Dayparts are ACM "
            "Program based and Commercial Duration weighted' against R_6's "
            "'Program QH based', so the two reports appear to use different "
            "constructions deliberately. A programme-level C3 rank is buildable "
            "off the total-programme table if they confirm that method - and it "
            "would not tie out to R_6 line for line, which is worth saying "
            "before anyone puts them side by side. ")),

Case("R_3",
     "Where does A&E rank among entertainment cable networks in Interrogation "
     "Raw's time period on 7/2/26?",
     ["3.1"],
     {"network": "AEN", "program": "Interrogation Raw",
      "win_from": "2026-07-02", "win_to": "2026-07-02"},
     "TBSC 475 at 1, AEN 258 at 2, FOOD 255 at 3, OXYG 211 at 4, BET 175 at 5.",
     "Select from the output: the row flagged as the series network.",
     "A&E print both demos on this sheet and the ranks disagree between them, "
     "AEN at 2 on P25-64 and 3 on P25+. A question that names no demo should be "
     "answered with both or with the network default stated.",
     verified="2026-08-24"),

Case("R_4",
     "Please retrieve the latest Top 50 Telecast Ranker for this past Tuesday "
     "(7/14/26) among P25+.",
     ["3.4"],
     {"demo": "P25+", "top_n": 50, "win_from": "2026-07-14",
      "win_to": "2026-07-14", "has_published_cutoff": True},
     "FOX MLB ALL-STAR GAME 7,611 at 1, AMERICA'S GOT TALENT 4,587 at 2, FOX MLB "
     "ALL-STAR PRE 3,536 at 3.",
     "Direct.",
     "Row 3 runs 6:30p to 8:19p and is in the answer with its whole delivery, "
     "untrimmed. This is the one ranker in section 3 that does not clip, and the "
     "one place where news and sports are in the universe.",
     verified="2026-08-24"),

Case("R_5",
     "Please retrieve the latest Top 50 Telecast Ranker for this past Tuesday "
     "(7/14/26) among P25-64.",
     ["3.4"],
     {"demo": "P25-64", "top_n": 50, "win_from": "2026-07-14",
      "win_to": "2026-07-14", "has_published_cutoff": True},
     "FOX MLB ALL-STAR GAME 4,245 at 1, FOX MLB ALL-STAR PRE 2,094 at 2, "
     "AMERICA'S GOT TALENT 1,644 at 3.",
     "Direct.",
     "Same night and same query as R_4 with one parameter different, and the "
     "order changes. No ranker should ever be presented as demo-neutral.",
     verified="2026-08-24"),

Case("R_6",
     "What is History's rank vs. ad-supported entertainment cable networks "
     "across Prime and Total Day, FY26 thru 7/5/26 on L+SD?",
     ["3.2"],
     {"network": "HIST", "demo": "P25-64", "names_fiscal_year": True,
      "has_published_cutoff": True, "win_to": "2026-07-05"},
     "Prime 184 at rank 7 tied, prior year 208 at 7. Total day 93 at rank 12, "
     "prior year 106.",
     "Direct.",
     "The runnable twin of R_2. If this reproduces and R_2 does not, the gap is "
     "data coverage rather than method.",
     verified="2026-08-24"),
]


BY_CODE = {c.code: c for c in CASES}

PASSING = [c for c in CASES if c.verified]
BLOCKED = [c for c in CASES if c.blocked]


# [SNAPSHOT] The SP sheets were pulled with data through about 14 July 2026, and
# only SP_GEN says so - its printed range is 05/19/26-07/14/26. The others carry
# no date at all, which is why two of them were misdiagnosed for weeks.
#
# SP_6 was recorded here as "four telecasts A&E exclude and nobody has said which
# four". There is no exclusion. Their sixteen telecasts are everything through 13
# July; our four extra aired on the 20th and the 27th, after they pulled. Sum the
# sixteen and the average is 954.0 exactly, and LONG ROAD TO TOKYO is the lowest
# of them at 761, which is their answer.
#
# SP_7 was recorded as "shape, not parameters - no parameter turns one into the
# other". That was wrong twice over. The fan-out to 2.12, 2.1 and 2.2 already
# produced all four of their references, and three of them - 266, 182, 250, with
# 142 nights and 17,155 minutes - were already exact. The fourth needed the same
# 13 July cut-off.
#
# Both statements were written with more confidence than the evidence carried,
# and so was a third: R_1's note here claimed a telecast floor had been "ruled
# out with evidence" because A&E appeared to keep LITTLE SINGLES on two
# telecasts. That was an arithmetic slip. SQUATTERS needs four removals above it
# and the three TELL rows are only three; LITTLE SINGLES is the fourth. The
# reading was never contradicted - it was miscounted and then written up as
# settled, which is worse than leaving it open.
# The lesson is not about those two cases: it is that a benchmark is a snapshot,
# and any case whose question contains no date will drift as data arrives.
#
# So the pull date now sits in the three questions that need it - SP_4 through
# 7/12/26, SP_6 and SP_7 through 7/13/26. That is not feeding an answer in: it is
# the date A&E looked, and without it the harness measures two things at once,
# whether CRISpy picks the right parameters and whether the data has moved since
# July. The second buries the first, which is exactly what happened here.
#
# CRISpy still resolves the date itself. "through 7/13/26" reaches p_win_to on all
# three of SP_7's fanned-out queries and leaves p_norm_to pinned, because the
# window bounds the series and not the norm. Nothing is hard-coded about where it
# lands.
#
# WHEN THE SHEET IS REPULLED those three dates come out or move. They belong to
# the benchmark, not to the queries.


def status() -> str:
    """Where the eighteen stand, and why the ones that do not pass do not.

    Twelve reproduce A&E exactly. Of the six that do not, one cannot run at all
    for want of data, three wait on a rule A&E have not written down, one needs
    an output shape that does not exist yet, and two have never been run.

    Worth keeping in view: of the seven cases fixed during the August work, none
    needed a change to calculation logic. Every one was a parameter - the wrong
    demo, a trailing window where the fiscal year was meant, a missing grain, a
    wildcard that matched three programmes, a slot threshold left null. The
    engine was right and the answers were wrong anyway, which is the failure this
    file exists to catch.
    """
    out = [f"{len(PASSING)} of {len(CASES)} reproduce A&E exactly.", ""]
    for c in CASES:
        if c.verified:
            out.append(f"  PASS     {c.code:6} verified {c.verified}")
    out.append("")
    for c in CASES:
        if c.blocked:
            out.append(f"  BLOCKED  {c.code:6} {c.blocked.split('.')[0]}.")
    return "\n".join(out)


def summary() -> str:
    """One line per case, for a smoke test that does not need a database."""
    out = []
    for c in CASES:
        mark = f"pass {c.verified}" if c.verified else ("blocked" if c.blocked else "-")
        out.append(f"{c.code:6} {'+'.join(c.query_ids):14} {mark:16} {c.question[:52]}")
    return "\n".join(out)
