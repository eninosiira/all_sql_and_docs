/* ============================================================================
   FILE       2.12 TELECAST-LEVEL PERFORMANCE                       (PRD 2.12)
   PURPOSE    Every episode of the season, against the season average, with its
              rank. The PRD's exact table: network, date, programme, episode,
              premiere/repeat indicator, time, day, AA (000s), vs season
              average, episode rank in season.
   SOURCE     CRIS_TELECAST_FACT [S2-T0]
   RULES      [A] first-run only, IS_FIRST_RUN_CT, per Jill; the P/R column stays
                  because the output format calls for it
              [W] the season average is DURATION-WEIGHTED across the season's
                  first-runs, which is why it can differ slightly from the plain
                  average 2.1 reports
   ============================================================================ */
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
SET p_premiere_only = FALSE;
                    -- [S2-PREM] TRUE returns the season premiere alone, the one
                    -- telecast that opened the season. FALSE, the default,
                    -- returns every telecast and marks which one it is, so
                    -- nothing already validated changes.
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
                     AND RATING_SOURCE = $p_stream);
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
scored AS (
    SELECT s.*,
        -- [W] duration weighted, and [S1-NORMKEY] scoped by the target's key
        SUM(s.DEMO * s.CONTRIBUTING_DURATION) OVER (PARTITION BY s.PROGRAM_CODE, s.NORM_KEY)
          / NULLIF(SUM(s.CONTRIBUTING_DURATION) OVER (PARTITION BY s.PROGRAM_CODE, s.NORM_KEY), 0)
                                                                   AS SEASON_AA,
        COUNT(*) OVER (PARTITION BY s.PROGRAM_CODE, s.NORM_KEY)     AS SEASON_TCASTS,
        RANK() OVER (PARTITION BY s.PROGRAM_CODE, s.NORM_KEY
                     ORDER BY ROUND(s.DEMO/1000, 0) DESC)           AS EP_RANK
    FROM series s
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    NETWORK_CODE   AS NETWORK,
    BROADCAST_DATE AS AIR_DATE,
    DAY_OF_WEEK    AS DAY,
    PROGRAM_NAME   AS PROGRAM,
    EPISODE_NAME   AS EPISODE,
    NORM_KEY       AS SEASON,
    IFF(NOT IS_FIRST_RUN_CT, 'R', 'P')                          AS PREMIERE_REPEAT,
    -- [S2-PREM] which telecast opened the season. PREMIERE_REPEAT above answers
    -- a different question, first run or repeat, and reads 'P' on every episode
    -- of a season. This one reads 1 exactly once. Named with the _CT suffix so
    -- it cannot be confused with IS_SEASON_PREMIERE, Nielsen's flag on the table.
    IS_PREMIERE_CT                                              AS IS_SEASON_PREMIERE_CT,
    START_TIME,
    ROUND(DEMO/1000, 0)                                    AS AA_000,
    ROUND(SEASON_AA/1000, 0)                               AS SEASON_AVG_000,
    ROUND((ROUND(DEMO/1000,0)
           / NULLIF(ROUND(SEASON_AA/1000,0),0) - 1) * 100, 1) AS VS_SEASON_AVG_PCT,
    EP_RANK, SEASON_TCASTS,
    $win_from               AS FROM_DATE,
    $win_to                 AS TO_DATE
FROM scored
WHERE NOT $p_premiere_only
   OR IS_PREMIERE_CT = 1
-- [RANKORDER] A&E, 24 Sep 2026: rankers come back in rank order, best first,
-- not in air-date order. EP_RANK is the season rank of each telecast.
ORDER BY EP_RANK, BROADCAST_DATE;