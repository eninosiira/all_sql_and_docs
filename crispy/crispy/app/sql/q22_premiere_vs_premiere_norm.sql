/* ============================================================================
   FILE       2.2  PREMIERE PERFORMANCE VS. NET'S PREMIERE AVERAGE  (PRD 2.2)
   PURPOSE    The series against the network's own premiere slate, rather than
              against all of prime.
   SOURCE     CRIS_TELECAST_FACT [S2-T0]
   VALIDATION A&E benchmark SP_7, HIST GREATEST MACHINES.
                series  222 over 7 telecasts, 1 Jun - 13 Jul 2026
                norm    250, over 142 nights and 17,155 prime minutes,
                        29 Sep 2025 - 31 May 2026, prime 8-11p
              Three numbers, all three from their own printed section 24.
              Reached by [S2-NORMWIN] + [S2-NORMCLIP] together: the window alone
              gives 241 over 285 telecasts, and the clip closes the rest.

              Four rules hold it up, each backed by a figure rather than an
              opinion. Window: fiscal year start to the day before the premiere.
              Daypart: prime 8-11p, CLIPPED. Curse of Oak Island: IN - excluding
              it gives 223. Specials: IN - without them the night count is 138,
              not 142.

              [S2-CURSE] p_exclude_curse is FALSE here and TRUE in 2.7. The two
              norms disagree and both are backed by data: 2.7's lift norm is
              validated excluding Curse (GREATEST MYSTERIES, +73k) and this one
              only reproduces including it. Per query, not global.

              NOT A VALIDATION CASE: the PRD's Parent Wars example. Its 172
              series figure is real and validated, but the "-3% below A&E's
              premiere norm" is prose in an Example Response Format, and the
              ~177 that was chased for weeks is that rounded percentage inverted.
              A printed Nielsen section beats a worked example in the spec.
   ============================================================================ */
-- [PREMNORM] the premiere norm, as Jill ran it on 23 Sep 2026: 9/14/25 to
-- 9/13/26, M-Su 8p-12a strict, no repeats, no Curse of Oak Island, no specials,
-- no mini-series. Two defaults changed to match: the norm window closes at
-- midnight (2400) rather than 11pm, and specials are out. There is no
-- mini-series flag on the tables; that one is still open. Jill counted 392
-- telecasts across 32 series and CRIS 390: same series, two telecasts short.
-- ===== PARAMETERS =====
SET p_network       = 'HIST';
SET p_program       = '%GREATEST MACHINES%';
SET p_season        = NULL;        -- NULL = most recent season for the series
SET p_stream        = 'Live+SD';
SET p_demo          = 'DEMO_AA';   -- [S2-DEMO] the network's own default. Any AA
                                   -- column the source view carries can be named
                                   -- instead: 'P25_64_AA_ESTIMATES',
                                   -- 'F25_64_AA_ESTIMATES', 'P18_49_AA_ESTIMATES',
                                   -- 'P25_AA_ESTIMATES', 'M25_54_AA_ESTIMATES'.
                                   -- The name is the column; nothing is summed.
SET p_include_specials = FALSE;
SET p_win_from      = NULL;        -- NULL = trailing 12 months to the last full Sunday
SET p_win_to        = NULL;
SET p_norm_from     = NULL;   -- [S2-NORMWIN] the NORM's own window, separate from
SET p_norm_to       = NULL;   -- the series'. NULL on either = same as the series
SET p_norm_start_2959 = 2000;  -- [S2-NORMCLIP] the norm's daypart, 8:00p
SET p_norm_end_2959   = 2400;  -- to 11:00p, exclusive. NULL on either = no bound.
                               -- A&E's section 24 is labelled PRIME M-SU 8P-11P.
                               -- 2.2 had no daypart at all, so its norm covered
                               -- the whole broadcast day.
                              -- window, which is what every validated case ran
                              -- under, so nothing moves until this is set.
                              --
                              -- It exists because A&E uses two windows in one
                              -- answer. Their SP_7 sheet runs the series to 13
                              -- July and cuts both norms at 31 May, the day
                              -- before the premiere - sections 23 and 24 print
                              -- 09/29/25-05/31/26 while the season average
                              -- covers 06/01-07/13. One p_win_to cannot do both:
                              -- setting it to the norm's end date cut the series
                              -- off before its own premiere and returned an empty
                              -- cell, which is what happened to sp_7a.
                              --
                              -- Their SP_9 sheet settles that this is a choice
                              -- and not a rule: it prints TWO A&E time-period
                              -- averages side by side, section 153 on the fiscal
                              -- year to date and section 154 on a trailing twelve
                              -- months. So the window belongs to the question.
SET data_sun = (SELECT MAX(LATEST_FULL_SUNDAY) FROM AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE
                   WHERE ($p_network IS NULL OR NETWORK_CODE = $p_network)
                     AND RATING_SOURCE = $p_stream);
-- [CAP-SUN] the window can never run past the latest full Sunday with data, even when a
-- later date is passed in (A&E review, 27 Sep 2026: TO_DATE showed a date with no data yet).
SET win_to   = (SELECT LEAST(COALESCE(TO_DATE($p_win_to), $data_sun), $data_sun));
SET win_from = (SELECT COALESCE(TO_DATE($p_win_from),
                  -- [NORM12] network norms run the latest 12 months, ending on
                  -- the most recent Sunday with data. A&E, 10 Sep 2026. Season
                  -- norms stay season-based; this is only the network ones.
                  DATEADD('day', 1, DATEADD('month', -12, $win_to))));
SET norm_to   = (SELECT COALESCE(TO_DATE($p_norm_to),   $win_to));
SET norm_from = (SELECT COALESCE(TO_DATE($p_norm_from), $win_from));
SET p_premiere_only = FALSE;    -- [SEASONPREM] A&E, 24 Sep 2026: "how did the
                                -- season premiere perform" is the FIRST telecast
                                -- of the season against the network's latest
                                -- 12-month premiere norm, the same norm this
                                -- query already builds. TRUE measures that one
                                -- telecast; FALSE, the default, the season.
SET p_exclude_curse = TRUE;   -- HIST only: Curse of Oak Island out of the norm,
SET p_movies        = 'EXCLUDE';  -- [MOVIES] 'EXCLUDE' | 'ONLY' | 'BOTH'
                                  -- A&E, week 10, reported as fatal: a hard
                                  -- MOVIE_IND = 0 deletes the answer to any
                                  -- question about Lifetime, because Lifetime's
                                  -- premiere slate IS movies. Excluding them is
                                  -- right for a series question and wrong for a
                                  -- movie one, which makes it a parameter rather
                                  -- than a rule.
                                  -- EXCLUDE keeps the behaviour every validated
                                  -- series case was measured under.
                              -- per the standing rule in v6's 2.2 and 2.7


-- [DEMOUSED] resolve p_demo to a real column name and return it with the answer.
-- DEMO_AA is a real column carrying each network's own key demo, so a query runs
-- on it and never states what it measured. Read back, "DEMO_AA" tells a consumer
-- nothing: it is P25-64 on AEN, HIST and FYI, F25-64 on LIF and LMN, P18-49 on
-- VICE. SP_3 and SP_6 both failed on that - the question asked for P25+, the
-- default answered on P25-64, and 242 came back where 438 was expected. A wrong
-- demo does not look wrong, it looks like a number.
SET demo_used = (SELECT IFF(UPPER(COALESCE($p_demo,'DEMO_AA')) = 'DEMO_AA',
                     CASE $p_network
                          WHEN 'AEN'  THEN 'P25_64_AA_ESTIMATES'
                          WHEN 'HIST' THEN 'P25_64_AA_ESTIMATES'
                          WHEN 'FYI'  THEN 'P25_64_AA_ESTIMATES'
                          WHEN 'LIF'  THEN 'F25_64_AA_ESTIMATES'
                          WHEN 'LMN'  THEN 'F25_64_AA_ESTIMATES'
                          -- VICE is a SiiRA assumption, never confirmed by A&E
                          WHEN 'VICE' THEN 'P18_49_AA_ESTIMATES'
                          ELSE 'UNRESOLVED - no default demo outside the six'
                     END,
                     UPPER($p_demo)));

WITH
fy AS (
    -- [YEARSEASON] the fiscal year each date belongs to.
    --
    -- Cable Tracks labels some programmes by calendar year rather than by
    -- season: MOVIE- ORIGINAL PREM carries CT_SEASON 2026 for everything
    -- Lifetime premiered in 2026. Partitioning a norm by that partitions it by
    -- January, so a February premiere is measured against whatever aired in the
    -- five weeks before it.
    --
    -- Where the label is a year, the season it stands for is the fiscal year.
    -- A&E's own corrected pull for the 7 February 2026 Lifetime premiere proves
    -- it: their thirteen telecasts run from 4 October to 31 January, spanning
    -- CT_SEASON 2025 and 2026, and what those thirteen share is FY26. Trailing
    -- twelve months would give 39 telecasts and a norm of 140, so the data tells
    -- the readings apart and only the fiscal year reproduces 138 and +64.5.
    --
    -- 156 programmes of 1,503 carry year labels and 3,606 telecasts of 29,291.
    -- Lifetime and LMN are 42% of them, being the movie slate, and VICE another
    -- quarter, being the dailies. A programme with a real season number is
    -- untouched, which is why the HIST cases reproduce unchanged.
    SELECT FISCAL_YEAR, FY_START, FY_END
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_FY_CALENDAR
),
fact AS (
    -- [S2-SEASON] no restated CT_SEASON. f.* already carries it, and naming it
    -- again put the same column in the projection twice, so every later
    -- reference was ambiguous. It survived as the residue of
    -- `f.CT_SEASON AS SEASON_KEY`: dropping the alias left the duplicate.
    SELECT f.*, IDENTIFIER($p_demo) AS DEMO
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT f
    WHERE ($p_network IS NULL OR f.NETWORK_CODE = $p_network)
      AND f.RATING_SOURCE = $p_stream
      AND f.BROADCAST_DATE <= $win_to
      AND ( $p_movies = 'BOTH'
         OR ($p_movies = 'EXCLUDE' AND f.MOVIE_IND = 0)
         OR ($p_movies = 'ONLY'    AND f.MOVIE_IND = 1) )
      AND ($p_include_specials OR f.CONTENT_TYPE <> 'Special')
),
target AS (
    -- [S1-KEY] the series, and which of its seasons is in scope
    SELECT f2.NETWORK_CODE, f2.PROGRAM_CODE, f2.CT_SEASON,
           -- [YEARSEASON] a year label is not a season, so there the partition
           -- becomes the fiscal year the telecast falls in
           IFF(REGEXP_LIKE(f2.CT_SEASON, '^(19|20)[0-9]{2}[A-Za-z]?$'),
               'FY' || fy.FISCAL_YEAR, f2.CT_SEASON)                 AS NORM_KEY,
           REGEXP_LIKE(f2.CT_SEASON, '^(19|20)[0-9]{2}[A-Za-z]?$')   AS IS_YEAR_LABEL,
           fy.FY_START, fy.FY_END
    FROM fact f2
    LEFT JOIN fy
      ON f2.BROADCAST_DATE BETWEEN fy.FY_START AND fy.FY_END
    WHERE f2.IS_FIRST_RUN_CT
      AND ($p_program IS NULL OR f2.PROGRAM_NAME ILIKE $p_program)
      AND ($p_season  IS NULL OR f2.CT_SEASON = $p_season)
      -- [S2-SEASON] A&E, Jul-2026: a calculation that compares SEASONS may not
      -- use telecasts with no season. Not a parameter. Cable Tracks is the
      -- authority; where it has not catalogued a telecast the series does not
      -- appear in this answer rather than appearing against a guess.
      AND f2.CT_SEASON IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY f2.NETWORK_CODE, f2.PROGRAM_CODE
                               ORDER BY f2.BROADCAST_DATE DESC, f2.TELECAST_NUM DESC) = 1
),
series AS (
    -- [S2-SEASON] the season's premieres, scoped by
    -- the target's key so a partially tracked season is not split in two.
    SELECT f.*, t.NORM_KEY, t.IS_YEAR_LABEL
    FROM fact f
    JOIN target t
      ON  t.NETWORK_CODE = f.NETWORK_CODE
      AND t.PROGRAM_CODE = f.PROGRAM_CODE
      -- [S2-SEASON] the season, and only the season. No premiere-anchored
      -- fallback and no trailing window: a comparison whose axis is the
      -- season cannot be made against an approximation of one.
      -- [YEARSEASON] the season, unless the label is a year, in which case the
      -- season it stands for is the fiscal year. Matching on CT_SEASON there
      -- cuts the window at 1 January.
      AND ( (NOT t.IS_YEAR_LABEL AND f.CT_SEASON = t.CT_SEASON)
         OR (t.IS_YEAR_LABEL
             AND f.BROADCAST_DATE BETWEEN t.FY_START AND t.FY_END) )
    WHERE f.IS_FIRST_RUN_CT
),
net_norm AS (
    -- [S2-NORMCLIP] the network's premiere slate over the window, on HALF HOURS
    -- rather than telecasts.
    --
    -- It read CRIS_TELECAST_FACT and averaged whole telecasts. A&E clips each
    -- one to the part that falls inside the daypart - their legend says so:
    -- "+ - Broadcast Prime Portion Used". AERIAL ATTACKERS runs 22:03-23:05 and
    -- contributes 57 minutes to 8-11p, not 62. Across HIST's FY26-to-premiere
    -- slate that is 486 minutes of tail past 11p, and the tails are the low
    -- part of the hour, so dropping them lifts the average.
    --
    -- A telecast row cannot do this. It is indivisible: it cannot give 57 of
    -- its 62 minutes to a daypart and keep the rest out. That is the whole
    -- reason CRIS_HALFHR_FACT exists and why 2.1's prime norm already reads it.
    --
    -- Reproduces A&E's section 24 on three numbers at once, HIST 29 Sep 2025 to
    -- 31 May 2026, prime 8-11p, specials in, Curse in:
    --     142 nights   17,155 minutes   250 AA (P25-64)
    -- Their T/C of 142 is a count of NIGHTS, not telecasts - the same slate is
    -- 266 telecasts - and their Duration is clipped prime minutes. Unclipped the
    -- window holds 17,641.
    --
    -- Weighted by contributing minutes, per their footer: "Live, LSD, Live+3,
    -- Live+7 Program Weighting: Program Duration."
    SELECT NETWORK_CODE,
           SUM(IDENTIFIER($p_demo) * HH_MIN)
             / NULLIF(SUM(HH_MIN), 0)                    AS NET_PREM_AA,
           SUM(HH_MIN)                                   AS NET_PREM_MIN,
           COUNT(DISTINCT BROADCAST_DATE)                AS NET_NIGHTS,
           COUNT(DISTINCT PROGRAM_CODE || '|' || TELECAST_NUM
                          || '|' || BROADCAST_DATE)      AS NET_TCASTS,
           COUNT(DISTINCT PROGRAM_CODE)                  AS NET_PROGRAMMES
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_HALFHR_FACT
    -- IS_AE_NETWORK, as 2.1's prime norm does. CRIS_HALFHR_FACT holds the whole
    -- cable landscape for section 3, so a NULL p_network here would norm an A+E
    -- premiere against every network Nielsen measures.
    WHERE IS_AE_NETWORK
      AND ($p_network IS NULL OR NETWORK_CODE = $p_network)
      AND RATING_SOURCE = $p_stream
      AND IS_FIRST_RUN_CT
      AND BROADCAST_DATE BETWEEN $norm_from AND $norm_to
      -- [S2-NORMCLIP] the daypart, on the half hour's OWN start
      AND ($p_norm_start_2959 IS NULL OR HH_START_2959 >= $p_norm_start_2959)
      AND ($p_norm_end_2959   IS NULL OR HH_START_2959 <  $p_norm_end_2959)
      -- the same content rules the telecast side runs under, on the same
      -- derived column. CONTENT_TYPE is NOT the same test as IS_SPECIAL = 0:
      -- the table builds it as 'Special' when CT_GENRE_1 is SPECIAL **or**
      -- IS_SPECIAL is 1, so IS_SPECIAL alone would let genre-coded specials
      -- through and the norm would stop matching the telecast side's universe.
      AND ( $p_movies = 'BOTH'
         OR ($p_movies = 'EXCLUDE' AND MOVIE_IND = 0)
         OR ($p_movies = 'ONLY'    AND MOVIE_IND = 1) )
      AND ($p_include_specials OR CONTENT_TYPE <> 'Special')
      AND NOT ($p_exclude_curse AND NETWORK_CODE = 'HIST'
               AND UPPER(PROGRAM_NAME) LIKE '%CURSE%OAK ISLAND%')
    GROUP BY NETWORK_CODE
),
measured AS (
    -- [SEASONPREM] with p_premiere_only the series side is one telecast, the one
    -- IS_PREMIERE_CT marks as the season opener; otherwise the whole season.
    SELECT *
    FROM series
    WHERE NOT $p_premiere_only OR IS_PREMIERE_CT = 1
),
ser AS (
    SELECT NETWORK_CODE, PROGRAM_CODE, MAX(PROGRAM_NAME) AS PROGRAM_NAME,
           MAX(IFF($p_premiere_only, EPISODE_NAME, NULL)) AS PREMIERE_EPISODE,
           -- [S2-SEASON] NORM_KEY is selected as well as grouped on. It was in the
           -- GROUP BY and not in the SELECT, so the final query's s.NORM_KEY had
           -- nothing to resolve against. It went missing when NORM_BASIS was
           -- removed and the two shared a line.
           NORM_KEY,
           COUNT(*) AS TCASTS,
           MIN(BROADCAST_DATE) AS FROM_DATE,
           MAX(BROADCAST_DATE) AS TO_DATE,
           SUM(DEMO * CONTRIBUTING_DURATION) / NULLIF(SUM(CONTRIBUTING_DURATION), 0) AS SERIES_AA  -- [WAVG] duration weighted, Adarsh 11 Sep 2026: every aggregation.
    FROM measured
    GROUP BY NETWORK_CODE, PROGRAM_CODE, NORM_KEY
)
SELECT
    s.NETWORK_CODE  AS NETWORK,
    s.PROGRAM_NAME  AS PROGRAM,
    s.NORM_KEY      AS SEASON,
    IFF($p_premiere_only, 'SEASON PREMIERE', 'SEASON')             AS MEASURED,
    s.PREMIERE_EPISODE,
    s.FROM_DATE                                                    AS AIR_DATE,
    s.TO_DATE, s.TCASTS,
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,
    ROUND(s.SERIES_AA/1000, 0)                                     AS SERIES_AA_000,
    $norm_from AS NORM_FROM, $norm_to AS NORM_TO,
    ROUND(n.NET_PREM_AA/1000, 0)                                   AS PREMIERE_NORM_000,
    ROUND((ROUND(s.SERIES_AA/1000,0)
           / NULLIF(ROUND(n.NET_PREM_AA/1000,0),0) - 1) * 100, 1)  AS PCT_VS_NORM,
    ROUND(s.SERIES_AA/1000, 0) - ROUND(n.NET_PREM_AA/1000, 0)      AS DIFF_000,
    CASE WHEN ROUND(s.SERIES_AA/1000,0) > ROUND(n.NET_PREM_AA/1000,0) THEN 'ABOVE'
         WHEN ROUND(s.SERIES_AA/1000,0) < ROUND(n.NET_PREM_AA/1000,0) THEN 'BELOW'
         ELSE 'IN LINE' END                                        AS VERDICT,
    n.NET_TCASTS AS NORM_TCASTS, n.NET_PROGRAMMES AS NORM_PROGRAMMES
FROM ser s
JOIN net_norm n ON n.NETWORK_CODE = s.NETWORK_CODE
ORDER BY SERIES_AA_000 DESC;