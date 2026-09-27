"""The thirty-two questions in A&E's validation workbook.

Questions only. What each one should return lives in that sheet and deliberately
does not live here: the point of the test page is to watch CRISpy reach an answer
on its own, and a module the app can import is a module the app can shortcut
through. Nothing outside the test page reads this file, and the test page reads
only the text.

`section` is where the sheet says the answer should come from. It is a label, not
a routing instruction - if CRISpy picks a different query, that disagreement is
the finding, and pre-empting it here would hide exactly what we are testing.
"""

# [SNAPSHOT] A&E pulled these sheets with data through about 14 July 2026. The
# warehouse now reaches 18 August, so three of the questions have moved on since
# the sheet was written, and three carry a date here that A&E did not type into
# the question itself.
#
#     SP_4   through 7/12/26   its window is fiscal-year-to-date and grows weekly
#     SP_6   through 7/13/26   their sixteen telecasts are everything to that day
#     SP_7   through 7/13/26   their seven, and the season average of 222
#
# The date is not an answer being fed in. It is the date they looked. Without it
# the harness measures two things at once - whether CRISpy picks the right
# parameters, and whether the data has changed since July - and the second buries
# the first. SP_6 came back with twenty telecasts against their sixteen for no
# reason but four airings in late July, and that was read as a method failure for
# weeks.
#
# CRISpy resolves the date itself: "through 7/13/26" reaches p_win_to on all
# three of SP_7's fanned-out queries and leaves p_norm_to pinned at 2026-05-31,
# because the window bounds the series and not the norm. Nothing about where the
# value lands is hard-coded here.
#
# The remaining fourteen need no date. Six already carry one A&E wrote into the
# question, and the rest cover seasons that closed before the sheet was pulled.
#
# WHEN THE SHEET IS REPULLED these three dates come out again, or move to
# whatever the new pull date is. They belong to the benchmark, not to the query.

# [CONSISTENCY] Fifteen questions were added from the CRIS 2.0 workbook, and they
# test something the original seventeen do not.
#
# OV_IND_1, OV_IND_2 and OV_IND_3 are the three halves of OV_SUM asked one at a
# time. Their figures MUST match the corresponding section of OV_SUM exactly. If
# asking for the premiere line on its own returns something different from asking
# for the whole summary, the difference is in how the question was read, because
# it is the same query over the same night either way.
#
# SP_IND_1 through SP_IND_12 are one programme, Secret Skinwalker Ranch, put
# through all twelve Section 2 queries in turn. Same show, same season, twelve
# different questions. Anything that resolves differently between them - the
# season, the network, the demo, the window - is a parameter problem rather than
# a calculation one, and this set is the cheapest way to see it.
#
# Deliberately no dates on any of the fifteen. They are worded as A&E wrote them.

CASES = [
    {"code": "OV_1",
     "question": " How did HIST's premieres do on 5/30/25 vs. their season norms?",
     "section": "Section 1.1  Premieres vs Season Norms"},
    {"code": "OV_2",
     "question": " Premieres on LFT on 2/7/26",
     "section": "Section 1.1  Premieres vs Season Norms"},
    {"code": "OV_SUM",
     "question": " Give me the Overnights Summary for History on 6/12/26.",
     "section": "Group: runs all 3 overnight queries for one network + date"},
    {"code": "SP_1",
     "question": " What is the average for the latest season of Court Cam?",
     "section": "Section 2.1  Prime Norm"},
    {"code": "SP_2",
     "question": " How is Neighborhood Wars season 9 performing vs. the prior season?",
     "section": "Section 2.4  Vs Prior Season"},
    {"code": "SP_3",
     "question": " Which episodes of Alaska State Trooper exceeded the season average among P25+?",
     "section": "Section 2.12  Telecast Level"},
    {"code": "SP_4",
     "question": " Which LFT movie had the highest performance this Fiscal Year among W25-64 through 7/12/26?",
     "section": "Section 2.8  Rank Among Premieres"},
    {"code": "SP_5",
     "question": " Which holiday movie on LFT had the highest L+3 lift in FY 2025 among P25-64?",
     "section": "Section 2.7  Live+3 Lift"},
    {"code": "SP_6",
     "question": " Which episode of World War II With Tom Hanks performed the lowest among P25+ through 7/13/26?",
     "section": "Section 2.12  Telecast Level"},
    {"code": "SP_7",
     "question": " How did the Season premiere of Hist Greatest Machines perform through 7/13/26?",
     "section": "Section 2.2  Premiere Average"},
    {"code": "SP_GEN",
     "question": " How is Secret Skinwalker Ranch performing on the History Channel?",
     "section": ""},
    {"code": "R_1",
     "question": " What are the TOP 3 non-fiction shows per network in fiscal year 2026 to-date thru 6/28/26? A&E, HIST and LIF.",
     "section": "Section 3.3  Genre Ranker"},
    {"code": "R_2",
     "question": " What is History's rank vs. ad-supported entertainment cable networks across Prime and Total Day? FY26 thru 7/5/26 C3",
     "section": "Section 3.2  Network Ranks (C3)"},
    {"code": "R_3",
     "question": " Where does A&E rank among entertainment cable networks in Interrogation Raw's time period (7/2/26)?",
     "section": "Section 3.1  Series Rank (Network TP)"},
    {"code": "R_4",
     "question": " Please retrieve the latest Top 50 Telecast Ranker for this past Tuesday. (7/14/26, P25+)",
     "section": "Section 3.4  Telecast Ranker (P25+)"},
    {"code": "R_5",
     "question": " Please retrieve the latest Top 50 Telecast Ranker for this past Tuesday. (7/14/26, P25-64)",
     "section": "Section 3.4  Telecast Ranker (P25-64)"},
    {"code": "R_6",
     "question": " What is History's rank vs. ad-supported entertainment cable networks across Prime and Total Day? FY26 thru 7/5/26 L+SD",
     "section": "Section 3.2  Network Ranks (Live+SD)"},

    # ---- the three halves of OV_SUM, asked separately -------------------------
    # Each must match its section of OV_SUM to the number.
    {"code": "OV_IND_1",
     "question": " How did HIST's premiere perform on 6/12/26 vs. its season norm?",
     "section": "Section 1.1  Premieres vs Season Norms"},
    {"code": "OV_IND_2",
     "question": " Give me the quarter-hour breakdown for the unxplained on history on 6/12/26.",
     "section": "Section 1.2  Quarter-Hour Movement"},
    {"code": "OV_IND_3",
     "question": " What was the lead-in retention for the unxplained on history on 6/12/26 vs. its season norm?",
     "section": "Section 1.3b  Lead-In Retention vs Season Norm"},

    # ---- one programme through all twelve Section 2 queries ------------------
    # The section labels below are where the workbook says each should land. They
    # are not routing instructions: a disagreement is the finding.
    {"code": "SP_IND_1",
     "question": " How does Secret Skinwalker Ranch's premiere perform vs. HIST's prime norm?",
     "section": "Section 2.1  Premiere vs Prime Norm"},
    {"code": "SP_IND_2",
     "question": " How does Secret Skinwalker Ranch's premiere perform vs. HIST's premiere average?",
     "section": "Section 2.2  Premiere vs Premiere Norm"},
    {"code": "SP_IND_3",
     "question": " How is Secret Skinwalker Ranch performing vs. its prior season?",
     "section": "Section 2.4  Vs Prior Season"},
    {"code": "SP_IND_4",
     "question": " What is Secret Skinwalker Ranch's median age vs. HIST's prime norm?",
     "section": "Section 2.5  Median Age"},
    {"code": "SP_IND_5",
     "question": " What is Secret Skinwalker Ranch's M/F skew vs. HIST's prime norm?",
     "section": "Section 2.6  M/F Skew"},
    {"code": "SP_IND_6",
     "question": " How much does Secret Skinwalker Ranch lift from Live+SD to Live+3?",
     "section": "Section 2.7  Live+3 Lift"},
    {"code": "SP_IND_7",
     "question": " Where does Secret Skinwalker Ranch rank among all of HIST's premiere series?",
     "section": "Section 2.8  Rank Among Premieres"},
    {"code": "SP_IND_8",
     "question": " Where does HIST rank among networks in Secret Skinwalker Ranch's time period?",
     "section": "Section 2.9  Network Rank, Time Period"},
    {"code": "SP_IND_9",
     "question": " How does Secret Skinwalker Ranch perform vs. its lead-in?",
     "section": "Section 2.10  Vs Lead-In"},
    {"code": "SP_IND_10",
     "question": " What is the quarter-hour build/decline within Secret Skinwalker Ranch's telecasts vs. the season QH norm?",
     "section": "Section 2.11  Quarter Hour"},
    {"code": "SP_IND_11",
     "question": " Show me episode-level performance for Secret Skinwalker Ranch this season.",
     "section": "Section 2.12  Telecast Level"},
    {"code": "SP_IND_12",
     "question": " Do Secret Skinwalker Ranch's repeats help or hurt the daypart they air in?",
     "section": "Section 2.13  Repeats vs Daypart"},
]
