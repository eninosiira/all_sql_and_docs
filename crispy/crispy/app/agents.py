"""The three agents, and the one rule they share.

CRISpy never writes SQL at answer time. Every query is authored and validated in
the Section 1 notebook; the model's whole job is to decide which of them a
question is asking for and what to set their parameters to. That boundary is the
reason an answer can be trusted: the worst a bad plan produces is the wrong
query with the wrong parameters, visible in the output, rather than novel SQL
nobody has reviewed.

The agents are separate calls on purpose. Intent and parameters were folded into
one call at one point in the CRIS build and the model started answering from
memory when it should not have, because a single call let it conflate two
judgements. Splitting them back out cost latency and bought correctness.

[SPLIT-READ] The parameter step is two calls for the same reason, and the reason
is a real failure rather than a principle.

SP_3 asks "which episodes of Alaska State Trooper exceeded the season average
among P25+". It names no network. The single parameter agent answered HIST,
because Alaska State Troopers sounds like History, and marked it "from the
question". The resolver then searched HIST, found nothing, and fell back to a
pattern. Two failures from one guess, and the second hid the first.

The instruction not to do that was already in the prompt. It was ignored because
the same call was being asked to do two different kinds of work at once: copy
what the question says, and judge what the question is about. A model doing both
copies with judgement, and a network that is not in the question gets supplied
anyway.

So the two are separated by the kind of work rather than by the fields:

  READ      only what the question states. Network, programme, season, date,
            demo, stream. Inference is forbidden. Absent means null.
  CLASSIFY  only judgements. Is this about a movie, does it name a fiscal year,
            does it pin a published cut-off, what is the premiere date, is it
            asking about now.

The classifier's output is four booleans and a date. That is small enough to be
checked against the eighteen cases in validation.py without a database, which
matters more than it sounds: the flags are what the pins key off, and a pin that
does not fire is silent.

They run concurrently, so the split costs no wall time.
"""

from __future__ import annotations

import json
from typing import Literal

from langchain_core.prompts import ChatPromptTemplate
from langchain_openai import ChatOpenAI
from pydantic import BaseModel, Field

from .catalog import (NETWORKS, STREAMS,
                      read_content_strand, read_asks_about_now)
from .config import settings
from .specs import (OVERNIGHT_SUMMARY, SEASON_PREMIERE, SPECS,
                    spec_catalogue_for_prompt)


def llm(temperature: float | None = None) -> ChatOpenAI:
    return ChatOpenAI(
        model=settings.openai_model,
        temperature=settings.openai_temperature if temperature is None else temperature,
        api_key=settings.openai_api_key,
        timeout=settings.openai_timeout,
        max_retries=2,
    )


# ==========================================================================
# 1. Intent
# ==========================================================================

class Intent(BaseModel):
    """What kind of message this is, before anything is planned."""

    kind: Literal["ratings_question", "small_talk", "out_of_scope"] = Field(
        description=(
            "ratings_question when the message asks about linear TV performance in "
            "any phrasing, however casual. Lean toward this whenever the message "
            "carries ratings language: a network name, a demo, a programme, or "
            "words like premiere, overnight, rank, retention, quarter hour. "
            "'how'd Lifetime do last night' is a ratings question, not small talk. "
            "small_talk for greetings and conversation about CRISpy itself. "
            "out_of_scope for anything genuinely unrelated to TV ratings."
        )
    )
    reasoning: str = Field(description="One sentence, plainly worded, on why.")


INTENT_PROMPT = ChatPromptTemplate.from_messages([
    ("system",
     "You are the intent step of CRISpy, a TV ratings SQL planner for the A&E "
     "Networks research team. You do exactly one thing: sort the message into a "
     "lane. You do not answer it, plan it, or extract anything from it.\n\n"
     "Networks in scope: {networks}."),
    ("human", "{question}"),
])


async def classify_intent(question: str) -> Intent:
    chain = INTENT_PROMPT | llm().with_structured_output(Intent)
    return await chain.ainvoke({
        "question": question,
        "networks": ", ".join(f"{c} ({m['name']})" for c, m in NETWORKS.items()),
    })


# ==========================================================================
# 2. Router
# ==========================================================================

class Route(BaseModel):
    """Which of the six queries answer this, and why."""

    query_ids: list[str] = Field(
        description=(
            "One or more ids from the catalogue. Most questions are one. Return "
            "['1.1','1.2','1.3b'] when the question asks for the Overnight Summary "
            "by name, because that report is three tables. Order matters: put the "
            "query that carries the headline answer first."
        )
    )
    rationale: str = Field(
        description="Two sentences at most, in the researcher's vocabulary, not SQL's."
    )


ROUTER_PROMPT = ChatPromptTemplate.from_messages([
    ("system",
     "You are the routing step of CRISpy. You pick which pre-approved query "
     "answers the question. You never write SQL and never invent a query id.\n\n"
     "The catalogue:\n\n{catalogue}\n\n"
     "Rules that decide most of the hard cases:\n"
     "1. A question asking which item is best or worst among many is a ranking "
     "question. A lookup returns one row, so it structurally cannot answer "
     "'which one'.\n"
     "   Within a single series, episode-level ranking is 2.12, NOT 1.1. "
     "   'How did the SEASON PREMIERE perform' is 2.2: the first telecast of the "
     "season against the network's 12-month premiere norm, one row. A&E, 24 Sep "
     "2026: not the season average, and the same premiere norm 2.2 already "
     "builds, not a separate one. 2.12 can also isolate the premiere telecast "
     "when the question wants it against the season average instead.\n"
     "'Which episode did best', 'which was lowest', 'which episodes beat the "
     "season average' all return every telecast of the season with its own "
     "figure, the season average on every row and its rank inside the season, "
     "and that is 2.12. 1.1 answers a NIGHT: what premiered on a date and how "
     "it did against its norm. If the question names no date and asks which "
     "episode, it is 2.12.\n"
     "2. 'Overnight Summary' names a specific three-table report. Asked for by "
     "name, return all three. Asked for one angle of it, return only that one.\n"
     "3. A SEASON PREMIERE question is three queries: 2.12, 2.1 and 2.2. A&E "
     "answer it with four figures and every percentage they publish is measured "
     "against the premiere telecast itself, which only 2.12 returns. The season "
     "average and the two network norms are the denominators, and they come from "
     "2.1 and 2.2. Returning one of the three answers a quarter of the question "
     "while looking complete, so return all three whenever the question is about "
     "how a season premiere performed.\n\n"
     "4. RANK questions split three ways, and getting this wrong is the most "
     "common routing error.\n"
     "   a) DAYPARTS, not a series: 'rank across Prime and Total Day', 'rank "
     "vs ad-supported entertainment cable', anything naming prime or total day "
     "or a fiscal year with no programme in the question, is 3.2. Never 2.9 and "
     "never 3.1: those two need a series to define the hours.\n"
     "   b) A SERIES time period, and the question says ENTERTAINMENT CABLE: "
     "3.1. 'Where does A&E rank among entertainment cable networks in "
     "Interrogation Raw's time period'.\n"
     "   c) A SERIES time period without that phrase: 2.9. 'Where does HIST "
     "rank among networks in X's time period'.\n"
     "   b) and c) are near-identical in wording and the phrase is the only "
     "signal there is. Use it.\n"
     "5. QUARTER HOURS split on scope. 1.2 is one night: the quarter hours of "
     "a telecast on a date. 2.11 is a season: how the audience moved inside "
     "the telecasts of a series against the season quarter-hour norm. A "
     "question naming a programme and no date is 2.11.\n\n"
     "NEVER DROP AN ENTITY THE QUESTION NAMES. If a programme, a network or a "
     "date appears in the question, it must reach the parameters. A query that "
     "runs without a programme the question named answers a different question "
     "and returns a plausible number for it.\n\n"
     "6. 'Which MOVIE had the highest performance / did best this fiscal year' "
     "is 2.8 at telecast grain: a ranker of the network's films. It has come "
     "back with no route before; it is 2.8.\n\n"
     "AN EMPTY LIST IS FOR QUESTIONS THE CATALOGUE CANNOT ANSWER, not for ones "
     "that are merely hard to place. If the question names a network and asks "
     "for a rank, a daypart, a norm or a premiere, something in the catalogue "
     "answers it and returning nothing is worse than returning the closest "
     "reasonable id: an empty result reads as no data rather than as no route. "
     "Only return an empty list when the question is not about television "
     "ratings at all."),
    ("human", "{question}"),
])


async def route(question: str) -> Route:
    chain = ROUTER_PROMPT | llm().with_structured_output(Route)
    r = await chain.ainvoke({"question": question, "catalogue": spec_catalogue_for_prompt()})
    r.query_ids = [q for q in r.query_ids if q in SPECS]
    if set(r.query_ids) == set(OVERNIGHT_SUMMARY):
        r.query_ids = list(OVERNIGHT_SUMMARY)          # keep PRD order

    # [SEASON-PREMIERE] The bundle, filled in rather than hoped for.
    #
    # The prompt asks for all three and the router kept returning one, drifting
    # between 2.1 and 2.12 across runs. Both are IN the bundle, which is the
    # tell: it recognised the question and under-answered it rather than
    # misreading it. A phrase this specific is worth completing in code, the
    # same way the Overnight Summary's order is fixed here rather than trusted
    # to the prompt.
    q = question.lower()
    if ("season premiere" in q or "series premiere" in q or "premiere of" in q):
        if set(r.query_ids) & set(SEASON_PREMIERE):
            r.query_ids = list(SEASON_PREMIERE)
    return r


# ==========================================================================
# 3. Parameters
# ==========================================================================

class Read(BaseModel):
    """[SPLIT-READ] What the question SAYS. Nothing else.

    Every field here is a transcription. If the person did not say it, it is
    null, and null is not a gap: it is the documented default, which the query
    resolves better than a guess would.
    """

    network: str | None = Field(
        default=None,
        description=(
            "The network, ONLY if the question names one. AEN, HIST, LIF, LMN, "
            "FYI, VICE, and A&E's own shorthand: LFT and Lifetime mean LIF, A&E "
            "and AE mean AEN, Hist and History mean HIST, Lifetime Movie Network "
            "means LMN. Return whatever the question said and it will be mapped.\n"
            "\n"
            "DO NOT INFER IT FROM THE PROGRAMME. Not from the title, not from "
            "what the show sounds like, not from what you remember about it. A "
            "programme identifies its network and the resolver reads that from "
            "the data a step later, which is the only source that cannot be "
            "wrong about it.\n"
            "\n"
            "This is the field that broke SP_3: the question named no network, "
            "HIST was supplied because Alaska State Troopers sounds like "
            "History, and the programme is on A&E. A wrong network returns zero "
            "rows with no error, which reads as a series that is off the air."
        ),
    )
    program: str | None = Field(
        default=None,
        description=(
            "The programme name as the person said it, without wildcards. Null "
            "when the question is about a night, a network or a ranker rather "
            "than a show. 'Which movie was highest' names no programme: it asks "
            "about a field."
        ),
    )
    season: str | None = Field(
        default=None,
        description=(
            "A season label such as '9' or '13B', ONLY when the question names "
            "one.\n"
            "\n"
            "LEAVE THIS NULL for 'this season', 'the latest season', 'how is it "
            "doing' and anything else that does not carry a number. Null is not a "
            "gap: it resolves to the current season against the data, which is "
            "more reliable than a number inferred from context.\n"
            "\n"
            "Do not carry a season over from an earlier question or from another "
            "part of the same run. Twelve questions about one programme should "
            "resolve this the same way, and they only do if each is read on its "
            "own words."
        ),
    )
    target_date: str | None = Field(
        default=None,
        description=(
            "A single date as YYYY-MM-DD, ONLY when one is named. 'Last night' "
            "is not a date: it means the most recent night with DATA, which the "
            "query resolves itself, so leave this null rather than computing "
            "yesterday."
        ),
    )
    report_from: str | None = Field(default=None, description="Range start, YYYY-MM-DD, only if a range was asked for.")
    report_to: str | None = Field(default=None, description="Range end, YYYY-MM-DD, only if a range was asked for.")
    win_from: str | None = Field(
        default=None,
        description=(
            "Window start, YYYY-MM-DD, when the question gives one. A fiscal "
            "year on its own does not: the query resolves that from A&E's "
            "calendar, so leave this null and set names_fiscal_year instead."
        ),
    )
    win_to: str | None = Field(
        default=None,
        description=(
            "Window END, YYYY-MM-DD. Set it whenever the question pins how far "
            "the report runs, however that is phrased:\n"
            "  'thru 6/28/26'            -> 2026-06-28\n"
            "  'to-date through 5 July'  -> 2026-07-05\n"
            "  'as of 13 July'           -> 2026-07-13\n"
            "  'for this past Tuesday'   -> that Tuesday's date\n"
            "\n"
            "'Fiscal year 2026 to-date thru 6/28/26' contains BOTH: the fiscal "
            "year is a flag, and 6/28/26 belongs here. Setting one and not the "
            "other runs the report to wherever the data happens to reach, which "
            "is a different question from the one asked and looks deliberate.\n"
            "\n"
            "Putting the date in a note instead of in this field is the same as "
            "not reading it."
        ),
    )
    demo: str | None = Field(
        default=None,
        description=(
            "The demo as the person said it: 'A18-49', 'W25-64', 'P25+', 'total "
            "viewers'. Null when none was named, which keeps each network's own "
            "default. Note P25+ is persons 25 and over, which is not P25-64."
        ),
    )
    stream: str | None = Field(
        default=None,
        description="Playback stream if named: Live+SD, Live+3, Live+7, C3, C7. Null means Live+SD.",
    )
    focus_networks: str | None = Field(
        default=None,
        description=(
            "[S3-FOCUS] The networks the person wants ROWS for, as a comma list: "
            "'AEN,HIST,LIF'. Use whatever they said and it will be mapped.\n"
            "\n"
            "This is not the same as the network field. On a ranker the network "
            "does not narrow what is ranked, because the ranking is across the "
            "whole competitive set and that is usually half the question: 'and "
            "where do these sit in the cable set'. It narrows which rows come "
            "back.\n"
            "\n"
            "So 'top 3 per network for A&E, HIST and LIF' fills this with all "
            "three, and leaves the network field null."
        ),
    )
    per_network: int | None = Field(
        default=None,
        description=(
            "[S3-FOCUS] How many rows PER network, when the question asks for a "
            "few from each: 'top 3 per network' is 3 here, not in top_n.\n"
            "top_n is the global cut and this is the per-network one. A question "
            "that says 'per network' or 'of each' means this field, and leaving "
            "top_n null then is correct: the ranking still runs across the whole "
            "set, and only the rows returned are narrowed."
        ),
    )
    top_n: int | None = Field(
        default=None,
        description=(
            "How DEEP the ranker goes. This is not the same number as how many "
            "rows the answer shows, and confusing the two is how a correct "
            "ranker comes back empty.\n"
            "\n"
            "'Top 50 telecast ranker' means depth 50. Set it to 50.\n"
            "\n"
            "'TOP 3 non-fiction shows PER NETWORK' does NOT mean depth 3. The "
            "ranker is scored across the whole competitive set, so depth 3 "
            "returns the three biggest shows on cable and none of the networks "
            "asked about need be among them. The three per network are picked "
            "from the result afterwards. On A&E's own R_1 the third HIST title "
            "sits at rank 29, so depth 3 returns nothing usable and depth 50 "
            "returns the answer.\n"
            "\n"
            "So: a per-something top N needs depth well beyond N. Leave it null "
            "and the query default applies, which is safer than a number too "
            "small. Never set it below 20."
        ),
    )
    genre: str | None = Field(
        default=None,
        description="A genre if the question names one: 'non-fiction', 'drama', 'reality'.",
    )

    include_specials: bool | None = Field(
        default=None,
        description=(
            "Only when the question says so. FALSE for 'without specials', "
            "'series only', 'regular episodes only'. TRUE for 'include "
            "specials', 'specials too'. Null otherwise, and null is NOT 'no "
            "specials': it keeps A&E's own rule for the report.\n"
            "One trap: Lifetime and LMN movies are flagged as specials in the "
            "source metadata, so never infer FALSE from a question about movies."
        ),
    )
    movies: str | None = Field(
        default=None,
        description=(
            "EXCLUDE, ONLY or BOTH, only when the question is explicit about it. "
            "Null otherwise. Do not set this because the question is about a "
            "film; that is the classifier's job."
        ),
    )
    grain: str | None = Field(
        default=None,
        description="SERIES or TELECAST, only when the question is explicit. Null otherwise.",
    )
    notes: list[str] = Field(
        default_factory=list,
        description=(
            "Anything the person should know about how you read the question. "
            "Keep it short, and do not speculate about fields you left null: "
            "the resolver fills those from the data and saying they cannot be "
            "worked out reads as a failure when it is a handover."
        ),
    )


class Signals(BaseModel):
    """[SPLIT-READ] What the question IS ABOUT. Judgements, not transcription.

    Three booleans and a date. Every one of them decides whether a pin fires, and
    a pin that does not fire is silent, so these matter more than their size
    suggests.

    [DETERMINISTIC] Two fields were here and are not any more, because neither
    was a judgement.

    content_strand: the word is IN the question. "Which holiday movie on LFT"
    says holiday. Asking a model to notice a word it can already see is asking
    it to fail occasionally at something a match cannot fail at, and it did miss
    it on SP_5.

    asks_about_now: present tense with no period named. Two conditions, and the
    only hard part is that a NAMED season is "season 9" while "latest season" is
    the clearest case of a question about now. A regex tells those apart; a
    prompt kept getting it backwards.

    Both are now read from the question text in catalog.py and injected after
    this call. If a field can be decided by looking at the words, it is not the
    classifier's, and what is left here is what genuinely needs reading of
    intent.
    """

    is_movie_question: bool | None = Field(
        default=None,
        description=(
            "TRUE when the thing asked about is a film or a movie slate rather "
            "than a series: 'which LFT movie', 'the holiday movies', "
            "'Lifetime's originals', a named title that is a film.\n"
            "\n"
            "Three parameters move together on a movie question and the person "
            "will not think to mention any of them. Movies are excluded by "
            "default because that is right for a series. Lifetime's movies are "
            "flagged as specials, so leaving specials out deletes the slate. And "
            "the film's title is the EPISODE, because the PROGRAM is the bucket "
            "it was bought under. Get this wrong and the query returns nothing, "
            "or returns the name of a category where a film was asked for."
        ),
    )
    is_holiday_question: bool | None = Field(
        default=None,
        description=(
            "TRUE when the question is about holiday content: Christmas, "
            "holiday, festive, seasonal films.\n"
            "\n"
            "There is a flag on the data for this, and it is the only way to "
            "reach it. Matching the programme name instead looks like it works - "
            "Lifetime's holiday slate is called MOVIE- ORIGINAL HOL PREM - and "
            "breaks the moment a film is bought under a bucket spelled "
            "differently. Set this and let the flag do it.\n"
            "\n"
            "Unset, the question loses its holiday half and the query answers "
            "about every film on the network, which returns a real number, "
            "correctly computed, to a question nobody asked."
        ),
    )
    is_season_premiere_question: bool | None = Field(
        default=None,
        description=(
            "TRUE only when the question says SEASON PREMIERE, PREMIERE EPISODE, "
            "FIRST EPISODE of the season, or SEASON OPENER: 'how did the season "
            "premiere perform', 'the first episode of the season'.\n"
            "\n"
            "NOT on the word 'premiere' alone. In A&E usage 'Skinwalker's "
            "premiere' and 'premiere vs premiere norm' mean the FIRST-RUN "
            "SEASON, every new episode, and that is the default. SP_IND_2 asked "
            "'how does Skinwalker's premiere perform vs HIST's premiere average' "
            "and wants the season, 324k, not the opener, 303k.\n"
            "\n"
            "A season premiere is ONE telecast, the first of the season. It is "
            "not the season average and it is not 'premieres' in the sense of "
            "first-run episodes, which are all of them. Left unset, the query "
            "returns every episode of the season and the answer averages them: "
            "HIST GREATEST MACHINES came back as 221k over eight telecasts when "
            "the premiere, AERIAL ATTACKERS, was 266k. A&E flagged that case.\n"
            "\n"
            "Do not set this for 'how is the series doing' or 'the latest "
            "season', which are about the whole season."
        ),
    )
    is_season_qh_question: bool | None = Field(
        default=None,
        description=(
            "TRUE when the question asks about quarter hours across a SEASON: "
            "'quarter-hour build within the series' telecasts', 'how does it "
            "build across the season', 'QH1 to QH4 vs the season norm'.\n"
            "\n"
            "A season quarter-hour question wants four lines, QH1 to QH4 averaged "
            "over every telecast, not the quarter hours of each telecast in turn. "
            "Left unset, 2.11 returns every telecast's quarter hours, fifty-odd rows "
            "for a season, and the answer has to average them itself.\n"
            "\n"
            "Do not set this for a single night: 'the quarter-hour breakdown for "
            "The UnXplained on 6/12' is one telecast and goes to 1.2."
        ),
    )
    is_series_leadin_question: bool | None = Field(
        default=None,
        description=(
            "TRUE when the question asks how a SERIES performs against its "
            "lead-in: 'how does Skinwalker perform vs its lead-in', 'what does "
            "it retain from its lead-in this season'.\n"
            "\n"
            "That answer is the season: the series average against the average "
            "of all its lead-ins, then by lead-in programme. Left unset, 2.10 "
            "returns one row per night, which is right for an overnight question "
            "and wrong for a series one.\n"
            "\n"
            "Do not set this for a single night: 'the lead-in retention for The "
            "UnXplained on 6/12' is one telecast and goes to 1.3b."
        ),
    )
    fiscal_year: int | None = Field(
        default=None,
        description=(
            "WHICH fiscal year, as a four-digit number, when the question names "
            "one: 'FY 2025' -> 2025, 'FY26' -> 2026, 'fiscal year 2026 to-date' "
            "-> 2026.\n"
            "\n"
            "Leave null for 'this fiscal year' or 'FYTD' with no number - that "
            "resolves to whichever year the data is in.\n"
            "\n"
            "Do not compute the dates. A fiscal year is not a calendar one and "
            "the bounds are not guessable from the number: FY26 begins on "
            "2025-09-29 and FY25 on 2024-09-30. The number is all that is needed; "
            "the dates come from A&E's calendar.\n"
            "\n"
            "This matters most when the year named is a PAST one. 'FY 2025' is "
            "not the year in progress, and a null here answers about the current "
            "year instead - with numbers that look just as plausible."
        ),
    )
    names_fiscal_year: bool | None = Field(
        default=None,
        description=(
            "TRUE when the question names a fiscal year or says this fiscal "
            "year, FY26, FYTD, year to date. A fiscal year is not a calendar "
            "one: A&E's starts on the last Monday of September. Do not compute "
            "the dates. Set the flag and the query resolves it from A&E's own "
            "calendar."
        ),
    )
    has_published_cutoff: bool | None = Field(
        default=None,
        description=(
            "TRUE when the question pins a report to a date it was run through: "
            "'thru 6/28/26', 'as of 5 July', 'the ranker for this past Tuesday'. "
            "A ranker with no end date runs to wherever the data reaches, which "
            "is right day to day and wrong against a figure someone published."
        ),
    )
    premiere_date: str | None = Field(
        default=None,
        description=(
            "YYYY-MM-DD of the premiere being measured, when the question is "
            "about a season premiere and the date is stated or resolvable from "
            "it. Norms are cut the day before it, so without this they fall back "
            "to a trailing window and quietly stop matching A&E."
        ),
    )


class Params(Read, Signals):
    """What the rest of the pipeline sees. The two halves, merged.

    Kept as one object so nothing downstream had to change: the renderer, the
    resolver and the scope all read the same fields they always did. The split
    is in how the values are produced, not in what they are.
    """

    program_code: str | None = Field(
        default=None,
        description="Never set this. The resolver fills it after matching the programme.",
    )
    source_network: str | None = Field(default=None, description="Never set this.")
    source_season: str | None = Field(default=None, description="Never set this.")
    source_program: str | None = Field(default=None, description="Never set this.")
    source_demo: str | None = Field(default=None, description="Never set this.")
    source_stream: str | None = Field(default=None, description="Never set this.")
    alternatives: list[dict] | None = Field(default=None, description="Never set this.")
    missing_required: list[str] = Field(default_factory=list)
    # [DETERMINISTIC] filled in code, not by either model
    content_strand: str | None = Field(default=None)
    asks_about_now: bool | None = Field(default=None)


READ_PROMPT = ChatPromptTemplate.from_messages([
    ("system",
     "You are the READING step of CRISpy. You transcribe what the question "
     "says into fields. You do not decide anything.\n\n"
     "Query [{query_id}] {title}\n"
     "It answers: {answers}\n\n"
     "Defaults already documented for this query, which you must NOT ask for "
     "and must NOT fill in:\n{defaults}\n\n"
     "Today's date is {today}. Resolve a relative date against it only when the "
     "question names one. 'Last night' is not a date: it means the most recent "
     "night with DATA, which the query resolves itself.\n\n"
     "THE ONE RULE. If the question does not say it, leave it null. Not the "
     "closest thing, not what you know about the show, not what the title "
     "sounds like. A null field is filled from the data by the resolver or by "
     "the query's own default, and both of those are better sources than a "
     "guess. A guessed network in particular returns zero rows with no error, "
     "which reads as a series that is off the air rather than as a mistake.\n\n"
     "Read the question for what it asks to leave OUT as well as what it asks "
     "for. 'Without specials' or 'series only' is a parameter, not an aside, "
     "and it is the easiest kind of instruction to read past because it looks "
     "like commentary.\n\n"
     "Some parameters are not yours at all. The norm window, the prime clip, "
     "whether Curse of Oak Island belongs in a norm, the slot threshold: those "
     "are set in code after you run, to match A&E's own method, and they will "
     "overwrite anything you put there."),
    ("human", "{question}"),
])


SIGNALS_PROMPT = ChatPromptTemplate.from_messages([
    ("system",
     "You are the CLASSIFYING step of CRISpy. You do not fill in parameters. "
     "You answer four questions about what the question is ABOUT, and give one "
     "date if there is one.\n\n"
     "Query [{query_id}] {title}\n"
     "It answers: {answers}\n\n"
     "Today's date is {today}.\n\n"
     "These flags are what decides whether the parameters that reproduce A&E's "
     "own method get applied. They are not descriptive. A movie question that "
     "is not flagged as one returns an empty result, because movies are "
     "excluded by default and Lifetime's slate is flagged as specials. A season "
     "premiere with no premiere date gets a norm over the wrong window and "
     "still looks right.\n\n"
     "Answer from the question alone. When a reading is genuinely unclear, "
     "leave it null rather than choosing: a null flag means the default applies, "
     "and the defaults are what every validated case ran under."),
    ("human", "{question}"),
])


async def extract_params(question: str, query_id: str, today: str) -> Params:
    """[SPLIT-READ] Two calls, run together, merged into one object.

    Concurrent because they do not depend on each other, so the split costs
    latency only in tokens and not in wall time.

    If either call fails the whole step fails, which is the right shape: a
    reading with no flags would silently skip every pin, and flags with no
    reading have nothing to apply to. Half an answer here is worse than none,
    because the failure would be invisible in the output.
    """
    import asyncio

    spec = SPECS[query_id]
    defaults = "\n".join(f"  {k} -> {v}" for k, v in spec.defaults.items()) or "  (none)"
    ctx = {
        "question": question,
        "query_id": spec.id,
        "title": spec.title,
        "answers": spec.answers,
        "today": today,
    }

    read_chain = READ_PROMPT | llm().with_structured_output(Read)
    sig_chain = SIGNALS_PROMPT | llm().with_structured_output(Signals)

    read, signals = await asyncio.gather(
        read_chain.ainvoke({**ctx, "defaults": defaults}),
        sig_chain.ainvoke(ctx),
    )

    p = Params(**read.model_dump(), **signals.model_dump())

    # [DETERMINISTIC] Read from the words rather than asked of a model. Set
    # after the calls so nothing the model returns can overwrite them: these two
    # are not opinions.
    p.content_strand = read_content_strand(question, p.network)
    p.asks_about_now = read_asks_about_now(question)

    # The spec, not the model, decides what is required. A model that decides
    # its own required fields will eventually decide it needs none.
    p.missing_required = [f for f in spec.required if not getattr(p, f, None)]
    return p


# ==========================================================================
# Clarifying question
# ==========================================================================

CLARIFY_PROMPT = ChatPromptTemplate.from_messages([
    ("system",
     "You are CRISpy asking for the one thing you cannot proceed without. "
     "Write a single short question, no preamble and no apology. Name the "
     "options if there are few. Do not ask about anything that already has a "
     "default. Missing: {missing}. Networks: {networks}."),
    ("human", "{question}"),
])


async def clarify(question: str, missing: list[str]) -> str:
    chain = CLARIFY_PROMPT | llm(temperature=0.3)
    msg = await chain.ainvoke({
        "question": question,
        "missing": ", ".join(missing),
        "networks": ", ".join(f"{c} ({m['name']})" for c, m in NETWORKS.items()),
    })
    return msg.content.strip()
