/* ============================================================================
   FILE       2.4  PREMIERE PERFORMANCE VS. PRIOR SEASON            (PRD 2.4)
   PURPOSE    One row per series: the season in scope against the one before it.
   SOURCE     CRIS_TELECAST_FACT [S2-T0]
   VALIDATION AEN, 'MY STRANGE ARREST' exact, not a wildcard: the wildcard also
              catches the MY STRANGE ARREST SPECIAL strand, which hijacked the
              v6 run and produced 159k / -33.6%.
              A&E illustrative shape from an older pull: S3 about 170k, roughly
              -20% against S2.
   [S1-SEASON-B] THIS IS THE QUERY THAT MAKES THE SEASON VARIANT MATTER. The prior
              season comes from LAG over the season key, so on raw labels the
              season before 13B is 13 and a series is compared against itself.
              The merged variant collapses them first and compares 13 with 12.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network       = 'AEN';
SET p_program       = '%NEIGHBORHOOD WARS%';
SET p_season        = NULL;        -- NULL = most recent season for the series
SET p_stream        = 'Live+SD';
SET p_demo          = 'DEMO_AA';   -- [S2-DEMO] the network's own default. Any AA
                                   -- column the source view carries can be named
                                   -- instead: 'P25_64_AA_ESTIMATES',
                                   -- 'F25_64_AA_ESTIMATES', 'P18_49_AA_ESTIMATES',
                                   -- 'P25_AA_ESTIMATES', 'M25_54_AA_ESTIMATES'.
                                   -- The name is the column; nothing is summed.
SET p_include_specials = TRUE;
SET p_win_from      = NULL;        -- NULL = trailing 12 months to the last full Sunday
SET p_win_to        = NULL;
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
seasons AS (
    -- every season of the series, not just the latest: 2.4 needs the pair.
    -- Seasons with no CT_SEASON cannot be ordered against each other, so they
    SELECT f.NETWORK_CODE, f.PROGRAM_CODE,
           MAX(f.PROGRAM_NAME)  AS PROGRAM_NAME,
           f.CT_SEASON,
           COUNT(*)             AS TCASTS,
           SUM(IDENTIFIER($p_demo) * f.CONTRIBUTING_DURATION)
             / NULLIF(SUM(f.CONTRIBUTING_DURATION), 0) AS SEASON_AA,   -- [WAVG] duration weighted, Adarsh 11 Sep 2026.
           MIN(f.BROADCAST_DATE) AS FROM_DATE,
           MAX(f.BROADCAST_DATE) AS TO_DATE,
           MIN(f.START_TIME)     AS START_TIME,
           MAX(f.DAY_OF_WEEK)    AS DAY_OF_WEEK
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT f
    WHERE ($p_network IS NULL OR f.NETWORK_CODE = $p_network)
      AND f.RATING_SOURCE = $p_stream
      AND f.IS_FIRST_RUN_CT
      AND ( $p_movies = 'BOTH'
         OR ($p_movies = 'EXCLUDE' AND f.MOVIE_IND = 0)
         OR ($p_movies = 'ONLY'    AND f.MOVIE_IND = 1) )
      AND ($p_include_specials OR f.CONTENT_TYPE <> 'Special')
      AND ($p_program IS NULL OR f.PROGRAM_NAME ILIKE $p_program)
      AND f.CT_SEASON IS NOT NULL
      AND f.BROADCAST_DATE <= $win_to
    GROUP BY f.NETWORK_CODE, f.PROGRAM_CODE, f.CT_SEASON
),
paired AS (
    SELECT s.*,
        -- [S1-SEASON-B] ordered by when the season actually ran, not by the label:
        -- season names are free text and do not sort reliably.
        LAG(CT_SEASON) OVER (PARTITION BY NETWORK_CODE, PROGRAM_CODE
                              ORDER BY FROM_DATE)               AS PRIOR_SEASON,
        LAG(SEASON_AA)  OVER (PARTITION BY NETWORK_CODE, PROGRAM_CODE
                              ORDER BY FROM_DATE)               AS PRIOR_AA,
        LAG(TCASTS)     OVER (PARTITION BY NETWORK_CODE, PROGRAM_CODE
                              ORDER BY FROM_DATE)               AS PRIOR_TCASTS,
        LAG(FROM_DATE)  OVER (PARTITION BY NETWORK_CODE, PROGRAM_CODE
                              ORDER BY FROM_DATE)               AS PRIOR_FROM,
        LAG(TO_DATE)    OVER (PARTITION BY NETWORK_CODE, PROGRAM_CODE
                              ORDER BY FROM_DATE)               AS PRIOR_TO,
        ROW_NUMBER() OVER (PARTITION BY NETWORK_CODE, PROGRAM_CODE
                           ORDER BY FROM_DATE DESC)             AS RECENCY
    FROM seasons s
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    NETWORK_CODE  AS NETWORK,
    PROGRAM_NAME  AS PROGRAM,
    CT_SEASON    AS SEASON,
    FROM_DATE, TO_DATE, DAY_OF_WEEK, START_TIME,
    TCASTS,
    ROUND(SEASON_AA/1000, 0)                                   AS SEASON_AA_000,
    PRIOR_SEASON,
    PRIOR_FROM, PRIOR_TO, PRIOR_TCASTS,
    ROUND(PRIOR_AA/1000, 0)                                    AS PRIOR_AA_000,
    ROUND(SEASON_AA/1000,0) - ROUND(PRIOR_AA/1000,0)           AS DIFF_000,
    ROUND((ROUND(SEASON_AA/1000,0)
           / NULLIF(ROUND(PRIOR_AA/1000,0),0) - 1) * 100, 1)   AS PCT_VS_PRIOR,
    CASE WHEN PRIOR_SEASON IS NULL       THEN 'NO PRIOR SEASON IN RANGE'
         WHEN PRIOR_TCASTS = 1           THEN 'PRIOR SEASON HAS ONE TELECAST'
         ELSE NULL END                                         AS CAVEAT
FROM paired
WHERE ($p_season IS NOT NULL AND CT_SEASON = $p_season) OR ($p_season IS NULL AND RECENCY = 1)
ORDER BY NETWORK, PROGRAM;