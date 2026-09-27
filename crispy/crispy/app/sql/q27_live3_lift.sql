/* ============================================================================
   FILE       2.7  LIVE+3 TIME-SHIFTING LIFT VS. PREMIERE NORM      (PRD 2.7)
   PURPOSE    How much the series - or the individual telecast - gains from
              Live+SD to Live+3, against the network's premiere norm for the
              same lift.
   SOURCE     CRIS_TELECAST_FACT [S2-T0]
   VALIDATION SERIES grain, unchanged from v5:
                HIST, HIST GREATEST MYSTERIES: 237 -> 307, lift +70k (+23%),
                HIST norm excluding Curse of Oak Island +73k.
              TELECAST grain, new, A&E benchmark SP_5:
                LIF, 2024-09-30 to 2025-09-28, p_program '%HOL PREM%',
                p_movies = 'ONLY' ->
                VERY MERRY BEAUTY SALON, 2024-12-07
                  P25_64_AA_ESTIMATES 205 -> 308, +103, +50.2%
                  F25_64_AA_ESTIMATES 173 -> 262,  +89, +51.4%
                The programme-grain figures behind those telecasts already
                reproduce exactly against A&E's own pull: the five ORIGINAL
                HOL PREM average 170 -> 223 in P25-64 and the seven ACQUIRED
                100 -> 118, so only the grain was ever wrong here.
   [S1-DUP]   THIS IS THE QUERY THE DEDUP MATTERS MOST FOR. [D5] counted 37
              doubled keys on Live+3, from the daily and weekly deliveries of
              the same telecast. v6 reads the view directly and averages both
              copies; this reads the deduplicated table.
   NOTE       Only telecasts posted in BOTH streams are compared. Live+3 lands
              about three days after Live+SD, so an unmatched recent telecast
              would drag the lift down for a reason that has nothing to do with
              time shifting.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network       = 'HIST';
SET p_program       = NULL;
SET p_season        = NULL;
SET p_demo      = 'DEMO_AA';
SET p_include_specials = FALSE;   -- series only for the norm, per the week-8 rule
SET p_exclude_curse = TRUE;
SET p_norm_start_2959 = 2000;   -- [L3NORM] the premiere-norm population is prime,
SET p_norm_end_2959   = 2400;   -- 8p-12a, the recipe Jill used for 2.2. Jill,
                                -- 24 Sep 2026: the HIST norm was "close but off,
                                -- most likely exclusions"; this norm had no
                                -- time-of-day window at all.
SET p_grain         = 'SERIES';   -- [S2-GRAIN] 'SERIES' | 'TELECAST'
                                  -- Same reason as 2.8. "Which holiday movie
                                  -- had the highest lift" is a question about a
                                  -- telecast: on Lifetime the film's title is
                                  -- the EPISODE_NAME and the PROGRAM_NAME is
                                  -- the bucket it was bought under. At SERIES
                                  -- grain the answer to SP_5 can only ever come
                                  -- back as "MOVIE- ORIGINAL HOL PREM", which
                                  -- is the slate rather than the film.
                                  -- SERIES is the default and keeps the
                                  -- GREATEST MYSTERIES case unchanged.
SET p_win_from      = NULL;
SET p_win_to        = NULL;
SET p_holiday            = NULL;
                                  -- [HOL] restrict to holiday films. TRUE returns
                                  -- only them, FALSE excludes them, NULL ignores
                                  -- the distinction and is the old behaviour.
                                  --
                                  -- IS_HOLIDAY was baked on CRIS_TELECAST_FACT
                                  -- from the start and never exposed, so the
                                  -- holiday half of SP_5 could not be asked at
                                  -- all: the query returned the highest lift of
                                  -- any Lifetime film, which reads like an answer.
                                  --
                                  -- The flag is derived from PROGRAM_NAME and
                                  -- requires MOVIE_IND = 1, so a holiday special
                                  -- that is not a film is not reachable through
                                  -- it. On Lifetime the marker sits on the slate
                                  -- a film was bought under, MOVIE- ORIGINAL HOL
                                  -- PREM, while the film's own title is the
                                  -- EPISODE_NAME - which is why SP_5 needs this
                                  -- together with p_grain = 'TELECAST'.
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
SET data_sun = (SELECT MAX(LATEST_FULL_SUNDAY) FROM AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE
                   WHERE ($p_network IS NULL OR NETWORK_CODE = $p_network)
                     AND RATING_SOURCE = 'Live+3');
-- [CAP-SUN] the window can never run past the latest full Sunday with data, even when a
-- later date is passed in (A&E review, 27 Sep 2026: TO_DATE showed a date with no data yet).
SET win_to   = (SELECT LEAST(COALESCE(TO_DATE($p_win_to), $data_sun), $data_sun));
SET win_from = (SELECT COALESCE(TO_DATE($p_win_from),
                  -- [NORM12] network norms run the latest 12 months, ending on
                  -- the most recent Sunday with data. A&E, 10 Sep 2026. Season
                  -- norms stay season-based; this is only the network ones.
                  DATEADD('day', 1, DATEADD('month', -12, $win_to))));


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

WITH lsd AS (
    -- Each stream is scoped in its own single-source CTE. Two reasons, both of
    -- which broke the first draft: IDENTIFIER($p_demo) cannot resolve when
    -- two sources in the same CTE each carry that column, and the season key
    -- expression needs an alias that exists here.
    SELECT NETWORK_CODE, PROGRAM_CODE, TELECAST_NUM,
           PROGRAM_NAME, EPISODE_NAME, CT_SEASON,
           BROADCAST_DATE, CONTENT_TYPE, BCAST_START_2959,
           IS_HOLIDAY,                    -- [HOL] carried so ser can filter on it.
                                          -- Live+3 does not need it: the join is
                                          -- on the telecast key and the flag is a
                                          -- property of the telecast, identical
                                          -- in both streams.
           CONTRIBUTING_DURATION AS W,
           IDENTIFIER($p_demo) AS AA
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT
    WHERE RATING_SOURCE  = 'Live+SD'
      AND NETWORK_CODE   = $p_network
      AND IS_FIRST_RUN_CT
      AND ( $p_movies = 'BOTH'
         OR ($p_movies = 'EXCLUDE' AND MOVIE_IND = 0)
         OR ($p_movies = 'ONLY'    AND MOVIE_IND = 1) )
      AND BROADCAST_DATE BETWEEN $win_from AND $win_to
),
l3 AS (
    SELECT NETWORK_CODE, PROGRAM_CODE, TELECAST_NUM, BROADCAST_DATE,
           IDENTIFIER($p_demo) AS AA
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT
    WHERE RATING_SOURCE  = 'Live+3'
      AND NETWORK_CODE   = $p_network
      AND IS_FIRST_RUN_CT
      AND ( $p_movies = 'BOTH'
         OR ($p_movies = 'EXCLUDE' AND MOVIE_IND = 0)
         OR ($p_movies = 'ONLY'    AND MOVIE_IND = 1) )
      AND BROADCAST_DATE BETWEEN $win_from AND $win_to
),
both AS (
    -- One row per telecast carrying both streams. The join is on the telecast
    -- key [S1-KEY], and it is INNER on purpose: Live+3 lands about three days
    -- after Live+SD, so a recent telecast present in only one stream drops out
    -- rather than entering with a lift of zero and dragging the average down
    -- for a reason that has nothing to do with time shifting.
    SELECT
        lsd.NETWORK_CODE, lsd.PROGRAM_CODE, lsd.TELECAST_NUM,
        lsd.PROGRAM_NAME, lsd.EPISODE_NAME, lsd.CT_SEASON,
        lsd.BROADCAST_DATE, lsd.CONTENT_TYPE, lsd.IS_HOLIDAY, lsd.BCAST_START_2959,   -- [HOL]
        lsd.AA AS LSD_AA,
        lsd.W  AS W,
        l3.AA  AS L3_AA
    FROM lsd
    JOIN l3
      ON  l3.NETWORK_CODE   = lsd.NETWORK_CODE
      AND l3.PROGRAM_CODE   = lsd.PROGRAM_CODE
      AND l3.TELECAST_NUM   = lsd.TELECAST_NUM
      AND l3.BROADCAST_DATE = lsd.BROADCAST_DATE
),
ser AS (
    SELECT NETWORK_CODE, PROGRAM_CODE, MAX(PROGRAM_NAME) AS PROGRAM_NAME, CT_SEASON,
           -- [S2-GRAIN] one row per programme-season, or one per telecast
           IFF($p_grain = 'TELECAST', TO_VARCHAR(TELECAST_NUM), '~SERIES~') AS GRAIN_KEY,
           IFF($p_grain = 'TELECAST', MAX(EPISODE_NAME), 'SEASON AVERAGE')  AS EPISODE_NAME,
           MIN(BROADCAST_DATE) AS FROM_DATE,
           MAX(BROADCAST_DATE) AS TO_DATE,
           COUNT(*) AS TCASTS,
           SUM(LSD_AA * W) / NULLIF(SUM(W), 0) AS LSD_AA,
           SUM(L3_AA * W) / NULLIF(SUM(W), 0) AS L3_AA  -- [WAVG] duration weighted, Adarsh 11 Sep 2026: every aggregation.
    FROM both
    WHERE ($p_program IS NULL OR PROGRAM_NAME ILIKE $p_program)
      AND ($p_season IS NULL OR CT_SEASON = $p_season)
      AND ($p_holiday IS NULL OR IS_HOLIDAY = $p_holiday)   -- [HOL]
      AND CT_SEASON IS NOT NULL
    GROUP BY NETWORK_CODE, PROGRAM_CODE, CT_SEASON,
             IFF($p_grain = 'TELECAST', TO_VARCHAR(TELECAST_NUM), '~SERIES~')
    -- [S2-GRAIN] the collapse to the latest season is a SERIES-grain rule. At
    -- telecast grain it would keep one telecast per programme and delete the
    -- ranker, so the window is what scopes the answer instead.
    QUALIFY $p_grain = 'TELECAST'
         OR ROW_NUMBER() OVER (PARTITION BY NETWORK_CODE, PROGRAM_CODE
                               ORDER BY MAX(BROADCAST_DATE) DESC) = 1
),
norm AS (
    -- The norm is the network's premiere slate and does not follow the grain:
    -- a telecast is still measured against the network, not against itself.
    SELECT NETWORK_CODE,
           SUM(LSD_AA * W) / NULLIF(SUM(W), 0) AS NORM_LSD,
           SUM(L3_AA * W) / NULLIF(SUM(W), 0) AS NORM_L3,
           COUNT(*) AS NORM_TCASTS  -- [WAVG] duration weighted, Adarsh 11 Sep 2026: every aggregation.
    FROM both
    WHERE ($p_include_specials OR CONTENT_TYPE <> 'Special')
      AND ($p_norm_start_2959 IS NULL OR BCAST_START_2959 >= $p_norm_start_2959)
      AND ($p_norm_end_2959   IS NULL OR BCAST_START_2959 <  $p_norm_end_2959)
      AND NOT ($p_exclude_curse AND NETWORK_CODE = 'HIST'
               AND UPPER(PROGRAM_NAME) LIKE '%CURSE%OAK ISLAND%')
    GROUP BY NETWORK_CODE
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    s.NETWORK_CODE AS NETWORK,
    s.PROGRAM_NAME AS PROGRAM,
    s.EPISODE_NAME AS EPISODE,
    s.CT_SEASON   AS SEASON,
    s.FROM_DATE, s.TO_DATE,
    s.TCASTS,
    ROUND(s.LSD_AA/1000, 0)                                        AS LIVE_SD_000,
    ROUND(s.L3_AA/1000, 0)                                         AS LIVE_3_000,
    ROUND(s.L3_AA/1000,0) - ROUND(s.LSD_AA/1000,0)                 AS LIFT_000,
    ROUND((ROUND(s.L3_AA/1000,0)
           / NULLIF(ROUND(s.LSD_AA/1000,0),0) - 1) * 100, 1)       AS LIFT_PCT,
    ROUND(n.NORM_L3/1000,0) - ROUND(n.NORM_LSD/1000,0)             AS NORM_LIFT_000,
    ROUND((ROUND(n.NORM_L3/1000,0)
           / NULLIF(ROUND(n.NORM_LSD/1000,0),0) - 1) * 100, 1)     AS NORM_LIFT_PCT,
    n.NORM_TCASTS,
    CASE WHEN (ROUND(s.L3_AA/1000,0) - ROUND(s.LSD_AA/1000,0))
            > (ROUND(n.NORM_L3/1000,0) - ROUND(n.NORM_LSD/1000,0)) THEN 'TIME SHIFTS MORE'
         WHEN (ROUND(s.L3_AA/1000,0) - ROUND(s.LSD_AA/1000,0))
            < (ROUND(n.NORM_L3/1000,0) - ROUND(n.NORM_LSD/1000,0)) THEN 'TIME SHIFTS LESS'
         ELSE 'IN LINE' END                                        AS VERDICT,
    $p_grain AS GRAIN,
    $win_from AS NORM_FROM,
    $win_to   AS NORM_TO
FROM ser s
JOIN norm n ON n.NETWORK_CODE = s.NETWORK_CODE
ORDER BY LIFT_000 DESC;
