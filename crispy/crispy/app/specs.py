"""One spec per Section 1 query.

A spec is what the router chooses between and what the parameter agent fills.
It carries the question the query answers, the parameters it exposes, which of
them a question genuinely cannot proceed without, and what every other one
falls back to.

The `required` list is deliberately short. Most fields have a documented
default, and asking for a field that has one wastes the person's turn. The
network is the exception across the board: a wrong network returns zero rows
with no error, so it is asked for rather than guessed.
"""

from __future__ import annotations
from dataclasses import dataclass, field


@dataclass(frozen=True)
class QuerySpec:
    id: str
    title: str
    sql_file: str
    answers: str                     # what a person gets back, in their words
    triggers: str                    # how the router recognises it
    params: list[str]
    required: list[str] = field(default_factory=lambda: ["network"])
    defaults: dict[str, str] = field(default_factory=dict)
    needs_quarter_hours: bool = False
    needs_half_hours: bool = False
    # [SCOPE-RANKER] A ranker's subject is a FIELD, not a title. p_program on one
    # of these filters which row prints; it never scopes what is ranked. So a
    # programme left over from the previous turn does not narrow the answer, it
    # deletes it: the ranker computes over the whole network and then the output
    # filter throws every row away.
    #
    # SP_4 showed it. "Which LFT movie had the highest performance this Fiscal
    # Year" names no programme because there is no programme to name, and the
    # previous question's ALASKA STATE TROOPERS AE carried into a Lifetime movie
    # ranker. Every other parameter was right.
    is_ranker: bool = False


SPECS: dict[str, QuerySpec] = {
    "1.1": QuerySpec(
        id="1.1",
        title="Premieres vs. season norms",
        sql_file="q11_premieres_vs_season_norms.sql",
        answers=(
            "How each premiere did against its own season-to-date average: the "
            "telecast audience, the season norm, the percent change, and where the "
            "episode ranks inside its season."
        ),
        triggers=(
            "The overnight question, and the default for anything about premieres "
            "on a date. 'How did History do last night', 'give me the overnight "
            "summary for 6/12', 'how did the premieres do vs their season norms', "
            "'premieres on LFT on 2/7/26'.\n"
            "NOT for 'which episode was best or worst'. This query answers a "
            "NIGHT. Episode-level ranking across a season is 2.12, which returns "
            "every telecast with the season average and its rank."
        ),
        params=[
            "p_network", "p_rating_src", "p_target_date", "p_program", "p_season",
            "p_report_from", "p_report_to", "p_include_specials",
            "p_win_start_2959", "p_win_end_2959", "p_demo",
        ],
        defaults={
            "p_target_date": "the most recent night with data",
            "p_report_from": "unset, so a single night",
            "p_demo": "the network's own key demo",
            "p_include_specials": "TRUE, specials count toward a night that aired",
            "p_win_start_2959": "2000, the 8p-12a Overnight Summary window",
        },
    ),
    "1.2": QuerySpec(
        id="1.2",
        title="Quarter-hour movement",
        sql_file="q12_quarter_hour_movement.sql",
        answers=(
            "How the audience moved inside the episode, quarter hour by quarter "
            "hour: each segment against the one before it, against the season norm "
            "for that position, and a last-versus-first summary."
        ),
        triggers=(
            "Anything about build or decline within a telecast ON A DATE. 'Did it "
            "hold the audience', 'how did it move across the hour', 'quarter hours "
            "for last night', 'quarter-hour breakdown for X on 6/12/26'.\n"
            "A NIGHT. If the question names a programme and no date, and asks about "
            "its telecasts against a season norm, that is 2.11."
        ),
        params=[
            "p_network", "p_rating_src", "p_target_date", "p_season",
            "p_include_leadin_qh", "p_show_runover", "p_runover_max_min",
            "p_win_start_2959", "p_win_end_2959", "p_demo",
        ],
        required=["network"],
        defaults={
            "p_target_date": "the most recent night with quarter-hour data",
            "p_season": "the season the night's premiere belongs to",
            "p_include_leadin_qh": "FALSE, the chart format rather than the raw table",
            "p_show_runover": "FALSE, a trailing sub-15-minute segment is bleed",
        },
        needs_quarter_hours=True,
    ),
    "1.3": QuerySpec(
        id="1.3",
        title="Lifetime movie retention norm",
        sql_file="q13_lifetime_movie_retention_norm.sql",
        answers=(
            "The long-run lead-in retention of the Lifetime movie slate, broken out "
            "by original versus acquired, what led in, whether that lead-in was a "
            "premiere or a repeat, and whether the movie is a holiday title."
        ),
        triggers=(
            "A norm question about movies, not a single night. 'Do originals hold "
            "their lead-in better than acquired', 'what is the retention norm for "
            "holiday movies'. Scoped to Lifetime and LMN by nature."
        ),
        params=[
            "p_network", "p_rating_src", "p_demo", "p_prem_start",
            "p_leadin_start", "p_min_dur", "p_gate_by_day", "p_movie_type_col",
        ],
        required=[],
        defaults={
            "p_network": "LIF",
            "p_demo": "F25_64_AA_ESTIMATES, pinned rather than taken from the network",
            "p_gate_by_day": "TRUE, Saturdays for originals and Sundays for acquired",
        },
    ),
    "1.3b": QuerySpec(
        id="1.3b",
        title="Lead-in retention vs. season norm",
        sql_file="q13b_leadin_retention_vs_season_norm.sql",
        answers=(
            "How much of its lead-in's audience each premiere held onto that night, "
            "against how much that programme usually holds, broken out by which "
            "programme led in and whether it was a premiere or a repeat."
        ),
        triggers=(
            "'How much did it retain from its lead-in', 'did it hold The First 48's "
            "audience', lead-in retention for a specific night."
        ),
        params=[
            "p_network", "p_rating_src", "p_target_date", "p_season",
            "p_min_leadin_dur", "p_include_specials",
            "p_win_start_2959", "p_win_end_2959", "p_demo",
        ],
        defaults={
            "p_target_date": "the most recent night with data",
            "p_season": "the season the night's premiere belongs to",
            "p_min_leadin_dur": "15 minutes, so an interstitial is not a lead-in",
        },
    ),
    "1.4": QuerySpec(
        id="1.4",
        title="Network and daypart rollup",
        sql_file="q14_network_daypart_rollup.sql",
        answers=(
            "A night's delivery by daypart with telecast and premiere counts, "
            "duration-weighted. This is also the fallback when nothing premiered: "
            "PREMIERES_IN_WINDOW is what tells the answer layer to say so."
        ),
        triggers=(
            "The fallback, and only the fallback. Pick it when the question is "
            "about a network's night as a whole with no premiere in view: 'how "
            "did Lifetime do last night', 'what did A&E deliver on Tuesday'.\n"
            "Do NOT pick it for a question that asks about premieres. 'Premieres "
            "on LFT on 2/7/26' is 1.1: it names what it wants and 1.4 cannot "
            "answer it, because it reports dayparts rather than telecasts. This "
            "query exists for the case where 1.1 comes back empty, not as a "
            "general night-level answer."
        ),
        params=["p_network", "p_rating_src", "p_target_date", "p_include_specials", "p_demo"],
        defaults={"p_target_date": "the most recent night with quarter-hour data"},
        needs_quarter_hours=True,
    ),
    "1.5": QuerySpec(
        id="1.5",
        title="Additional program data",
        sql_file="q15_additional_program_data.sql",
        answers=(
            "A season telecast by telecast in the order it aired, with episode "
            "name, date, delivery and duration, plus a season average line."
        ),
        triggers=(
            "'Show me the episodes so far', 'how is the season going', 'list the "
            "telecasts', 'season 8 of Customer Wars'. Naming a programme pins it "
            "and ignores the date; leaving it blank returns whatever premiered on "
            "the night. A season only narrows this when a programme was named too."
        ),
        params=[
            "p_network", "p_rating_src", "p_target_date", "p_program",
            "p_season", "p_demo", "p_include_specials",
            "p_win_start_2959", "p_win_end_2959",
        ],
        defaults={
            "p_program": "unset, so whatever premiered on the target night",
            "p_season": "the programme's most recent season; only meaningful "
                        "alongside a programme",
            "p_target_date": "the most recent night with data",
        },
    ),
    # ======================================================================
    # SECTION 2  Series Performance Snapshot
    # ======================================================================
    "2.1": QuerySpec(
        id="2.1",
        title="Premiere average vs. the network's prime norm",
        sql_file="q21_premiere_vs_prime_norm.sql",
        answers=(
            "A season's premiere average against what the network delivers in "
            "prime generally, with the percentage between them."
        ),
        triggers=(
            "'How is Court Cam doing', 'what is the average for the latest "
            "season of X', 'how does X compare to A&E prime'. The default for a "
            "season-level performance question that names no other benchmark."
        ),
        params=["p_network","p_program","p_season","p_stream","p_demo",
                "p_include_specials","p_win_from","p_win_to",
                "p_norm_from","p_norm_to","p_movies",
                "p_premiere_only"],
        required=["network","program"],
        defaults={
            "p_season": "the most recent season, chosen by the date it ran",
            "p_win_to": "the last full Sunday with data",
            "p_norm_from": "same window as the series, unless the question is "
                           "about a premiere, in which case it is pinned",
        },
        needs_half_hours=True,
    ),
    "2.2": QuerySpec(
        id="2.2",
        title="Premiere average vs. the network's premiere norm",
        sql_file="q22_premiere_vs_premiere_norm.sql",
        answers=(
            "A season's premiere average against the average of every premiere "
            "the network ran in prime over the same fiscal year."
        ),
        triggers=(
            "'How does it compare to other premieres', 'vs the network's "
            "premiere average', and the second half of a season premiere "
            "question. Distinct from 2.1: that one benchmarks against all of "
            "prime, this one against premieres only."
        ),
        params=["p_network","p_program","p_season","p_stream","p_demo",
                "p_include_specials","p_win_from","p_win_to","p_norm_from",
                "p_norm_to","p_norm_start_2959","p_norm_end_2959",
                "p_exclude_curse","p_movies",
                "p_premiere_only"],
        required=["network","program"],
        defaults={"p_win_to": "the last full Sunday with data"},
        needs_half_hours=True,
    ),
    "2.4": QuerySpec(
        id="2.4",
        title="Season vs. the prior season",
        sql_file="q24_vs_prior_season.sql",
        answers=(
            "This season's premiere average against the previous season's, the "
            "difference in thousands and the percentage."
        ),
        triggers=(
            "'How is season 9 doing vs season 8', 'is it up or down on last "
            "season', 'vs the prior season'. Any comparison between a season and "
            "the one before it."
        ),
        params=["p_network","p_program","p_season","p_stream","p_demo",
                "p_include_specials","p_win_to","p_movies"],
        required=["network","program"],
        defaults={"p_season": "the most recent season; the prior one is found by "
                              "the date it ran, not by the label"},
    ),
    "2.5": QuerySpec(
        id="2.5",
        title="Median age vs. the network's prime norm",
        sql_file="q25_median_age.sql",
        answers="A season's median age against the network's prime median age.",
        triggers="'How old is the audience', 'median age', 'is it skewing older'.",
        params=["p_network","p_program","p_season","p_stream","p_demo",
                "p_include_specials","p_win_from","p_win_to","p_norm_from",
                "p_norm_to","p_movies"],
        required=["network","program"],
        defaults={"p_win_to": "the last full Sunday with data"},
        needs_half_hours=True,
    ),
    "2.6": QuerySpec(
        id="2.6",
        title="Male/female skew vs. the network's prime norm",
        sql_file="q26_mf_skew.sql",
        answers=(
            "How male or female a season skews, in composition points, against "
            "the network's own prime composition."
        ),
        triggers="'How female-skewed is it', 'men versus women', 'the skew'.",
        params=["p_network","p_program","p_season","p_stream","p_demo",
                "p_include_specials","p_win_from","p_win_to","p_norm_from",
                "p_norm_to","p_movies"],
        required=["network","program"],
        defaults={"p_win_to": "the last full Sunday with data"},
        needs_half_hours=True,
    ),
    "2.7": QuerySpec(
        id="2.7",
        title="Live+3 lift vs. the network's premiere norm",
        sql_file="q27_live3_lift.sql",
        answers=(
            "How much a series or a single telecast gains from Live+SD to "
            "Live+3, against the network's own premiere lift."
        ),
        triggers=(
            "'How much does it time shift', 'the L+3 lift', 'which movie had the "
            "highest lift'. Any question about playback or delayed viewing gain."
        ),
        params=["p_network","p_program","p_season","p_demo","p_include_specials",
                "p_exclude_curse","p_grain","p_win_from","p_win_to","p_movies"],
        required=["network"],
        defaults={
            "p_grain": "SERIES; a movie question pins it to TELECAST",
            "p_win_to": "the last full Sunday with Live+3 data",
        },
    ),
    "2.8": QuerySpec(
        id="2.8",
        title="Rank among all of the network's premieres",
        sql_file="q28_rank_among_premieres.sql",
        answers=(
            "Where a series or a telecast sits among every premiere the network "
            "ran in the window, with the size of the field."
        ),
        triggers=(
            "'Where does it rank', 'is it the highest this year', 'which movie "
            "was highest this fiscal year', 'best performing premiere'."
        ),
        params=["p_network","p_program","p_stream","p_demo","p_include_specials",
                "p_grain","p_win_start_2959","p_win_end_2959","p_win_from",
                "p_win_to","p_movies",
                "p_min_tcasts"],
        required=["network"],
        defaults={
            "p_program": "unset returns the whole ranker; naming one filters the "
                         "output row but never the universe",
            "p_grain": "SERIES; a movie question pins it to TELECAST",
        },
        is_ranker=True,
    ),
    "2.9": QuerySpec(
        id="2.9",
        title="The network's rank within the time period",
        sql_file="q29_network_rank_time_period.sql",
        answers=(
            "Where the network ranks against the cable competitive set in the "
            "exact half hours the series occupied."
        ),
        triggers=(
            "'How does A&E rank in that hour', 'who won the time period', "
            "'against the competition at 9pm', 'where does HIST rank among "
            "networks in X's time period'.\n"
            "This and 3.1 are near-identical in wording and split on one phrase: if "
            "the question says ENTERTAINMENT CABLE it is 3.1, otherwise it is this "
            "one. That is a thin signal and it is the only one there is.\n"
            "Needs a series to define the half hours. A question about prime or "
            "total day with no programme is 3.2."
        ),
        params=["p_network","p_program","p_season","p_stream","p_demo",
                "p_excl_by","p_include_specials","p_win_from","p_win_to",
                "p_slot_min_min"],
        required=["network","program"],
        needs_half_hours=True,
    ),
    "2.10": QuerySpec(
        id="2.10",
        title="Performance vs. the lead-in",
        sql_file="q210_vs_lead_in.sql",
        answers="How a telecast did against the programme that preceded it.",
        triggers="'How did it do against its lead-in', 'did it hold the lead-in'.",
        params=["p_network","p_program","p_season","p_stream","p_demo",
                "p_include_specials","p_win_to","p_movies",
                "p_rollup",
                "p_min_leadin_min"],
        required=["network","program"],
    ),
    "2.11": QuerySpec(
        id="2.11",
        title="Quarter-hour performance",
        sql_file="q211_quarter_hour.sql",
        answers="How the audience moved quarter hour by quarter hour inside the telecasts.",
        triggers=(
            "'Quarter hours', 'how did it build', 'where did it lose people', "
            "'quarter-hour build/decline within the telecasts vs the season QH norm'.\n"
            "A SEASON, not a night. 1.2 is the quarter hours of one telecast on a "
            "date. This is how the audience moved inside the telecasts of a series "
            "against the season norm, and a question naming a programme with no date "
            "is this one."
        ),
        params=["p_network","p_program","p_season","p_stream","p_demo","p_win_to",
                "p_rollup",
                "p_norm_basis",
                "p_norm_months"],
        required=["network","program"],
        needs_quarter_hours=True,
    ),
    "2.12": QuerySpec(
        id="2.12",
        title="Telecast level performance",
        sql_file="q212_telecast_level.sql",
        answers=(
            "Every telecast of a season with its own figure, the season average "
            "on every row, the percentage against it and its rank in the season."
        ),
        triggers=(
            "'Which episode did best', 'which was lowest', 'which episodes beat "
            "the average', 'list the episodes'. Also the query that supplies a "
            "single premiere's own figure when another query needs it as a "
            "numerator."
        ),
        params=["p_network","p_program","p_season","p_stream","p_demo",
                "p_include_specials","p_win_from","p_win_to","p_movies",
                "p_premiere_only"],
        required=["network","program"],
        defaults={"p_season": "the most recent season"},
    ),
    "2.13": QuerySpec(
        id="2.13",
        title="Repeat average vs. the daypart",
        sql_file="q213_repeat_vs_daypart.sql",
        answers="How the repeats of a series do against the daypart they air in.",
        triggers="'How do the repeats do', 'are the encores working'.",
        params=["p_network","p_program","p_season","p_stream","p_demo","p_win_from","p_win_to",
                "p_norm_basis"],
        required=["network","program"],
        defaults={"p_norm_basis": "REPEATS: the daypart average is built on repeat half hours only, "
                                  "which is how A&E compute it. ALL adds premieres."},
        needs_half_hours=True,
    ),

    # ======================================================================
    # SECTION 3  Competitive Rankers
    # ======================================================================
    "3.1": QuerySpec(
        id="3.1",
        title="Series rank based on network time period ranks",
        sql_file="q31_series_rank_time_period.sql",
        answers=(
            "Where the network ranks among entertainment cable in the time "
            "period a series occupies, with every competitor listed."
        ),
        triggers=(
            "'Where does A&E rank in Interrogation Raw's time period', 'how does "
            "the network do in that slot against everyone else'.\n"
            "Pick this over 2.9 when the question says ENTERTAINMENT CABLE, as A&E "
            "write it: 'among entertainment cable networks in X's time period'. "
            "Without that phrase it is 2.9.\n"
            "Needs a series to define the half hours. A question about prime or "
            "total day with no programme is 3.2."
        ),
        params=["p_network","p_program","p_season","p_stream","p_demo",
                "p_excl_by","p_include_specials","p_win_from","p_win_to",
                "p_slot_min_min"],
        required=["network","program"],
        defaults={"p_win_from": "the whole season; set both to one date for a single night"},
        needs_half_hours=True,
    ),
    "3.2": QuerySpec(
        id="3.2",
        title="Network ranks by daypart",
        sql_file="q32_network_ranks.sql",
        answers=(
            "The network's rank against ad-supported entertainment cable in "
            "prime and total day, with the same figures a year ago."
        ),
        triggers=(
            "'What is History's rank vs entertainment cable', 'where do we sit "
            "in prime this fiscal year', 'rank across prime and total day', "
            "'History's rank vs ad-supported entertainment cable across Prime and "
            "Total Day, FY26 thru 7/5/26'.\n"
            "DAYPARTS, NOT A SERIES. If the question names prime or total day and "
            "no programme, this is the one. 2.9 and 3.1 both need a series to "
            "define the half hours, so neither can answer a daypart question."
        ),
        params=["p_network","p_fiscal_year","p_fy_to","p_stream","p_demo",
                "p_weight_col","p_excl_by"],
        required=["network"],
        defaults={
            "p_fiscal_year": "the fiscal year the latest data falls in",
            "p_fy_to": "as far as the data reaches",
            "p_weight_col": "HH_MIN, programme minutes",
        },
        needs_half_hours=True,
    ),
    "3.3": QuerySpec(
        id="3.3",
        title="Series or genre ranker",
        sql_file="q33_series_genre_ranker.sql",
        answers=(
            "A ranker of premiere programmes across the cable competitive set, "
            "optionally narrowed to one genre."
        ),
        triggers=(
            "'Top non-fiction shows', 'where do our shows rank in cable', 'the "
            "top 3 per network', 'best performing series this fiscal year'."
        ),
        params=["p_top_n","p_genre_col","p_genre","p_genre_2_exclude","p_stream",
                "p_demo","p_excl_by","p_include_specials","p_premieres_only",
                "p_dp_from_2959","p_dp_to_2959","p_fiscal_year","p_win_to","p_movies",
                "p_min_tcasts"],
        required=[],
        defaults={
            "p_top_n": "20",
            "p_genre": "unset, every genre",
            "p_fiscal_year": "the fiscal year the latest data falls in",
        },
        needs_half_hours=True,
        is_ranker=True,
    ),
    "3.4": QuerySpec(
        id="3.4",
        title="Telecast level ranker",
        sql_file="q34_telecast_ranker.sql",
        answers=(
            "The top telecasts of a night or a week across the whole television "
            "universe, broadcast and news and sports included."
        ),
        triggers=(
            "'Top 50 telecast ranker', 'what were the biggest telecasts on "
            "Tuesday', 'the top shows last week'."
        ),
        params=["p_top_n","p_universe","p_stream","p_demo","p_dp_from_2959",
                "p_dp_to_2959","p_win_from","p_win_to"],
        required=[],
        defaults={
            "p_top_n": "10",
            "p_universe": "TV, which includes news, sports and broadcast",
            "p_win_from": "the last completed Monday to Sunday week",
        },
        is_ranker=True,
    ),
}

# The Overnight Summary is three tables, not one. A question that asks for it by
# name gets all three, in PRD order.
OVERNIGHT_SUMMARY = ["1.1", "1.2", "1.3b"]

# [SEASON-PREMIERE] A season premiere question is three queries, the same way
# the Overnight Summary is three tables.
#
# A&E answer "how did the season premiere perform" with four figures, and every
# percentage they publish is measured against the premiere itself:
#
#     266  the premiere telecast          2.12, the programme pinned
#     222  the season average             2.1, series side      266/222 = +19.8
#     182  the network time period        2.1, norm side        266/182 = +46.2
#     250  the network premieres in prime 2.2, norm side        266/250 =  +6.4
#
# So the numerator comes from one query and each denominator from another. One
# query answers a quarter of the question and looks complete doing it, which is
# the failure this list exists to prevent: SP_7 came back from 2.1 alone with a
# season average and no premiere figure to compare it to.
#
# 2.12 first, because the figure everything else is measured against has to be
# in hand before the comparisons mean anything.
SEASON_PREMIERE = ["2.12", "2.1", "2.2"]


def spec_catalogue_for_prompt() -> str:
    """The router's menu, rendered once so the prompt and the code cannot drift."""
    out = []
    for s in SPECS.values():
        out.append(f"[{s.id}] {s.title}\n  answers: {s.answers}\n  pick when: {s.triggers}")
    return "\n\n".join(out)
