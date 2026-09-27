/* ============================================================================
   FILE       2.10 PERFORMANCE VS. LEAD-IN                          (PRD 2.10)
   PURPOSE    The series' hourly block against the block that led into it.
   SOURCE     CRIS_TELECAST_FACT [S2-T0]
   VALIDATION AEN, Customer Wars. Customer Wars is a half-hour show airing two
              episodes back to back at 10p and 10:30p, which is exactly why the
              block logic exists: a telecast-level join makes the 10:30p
              episode's lead-in Customer Wars itself and silently drops it.
              Per Kristen, week 1 section 6B: average the half hours and treat
              them as an hourly block, so Customer Wars 10-11p reads against
              Road Wars 9-10p.
   [BLK1]     SERIES BLOCK = every contiguous first-run episode of the series on
              the same night, duration weighted, starting at the first episode.
   [BLK2]     LEAD-IN BLOCK = the programme adjacent to the block start, then
              its own contiguous run walked backwards.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network       = 'HIST';
SET p_program       = '%SECRET SKINWALKER RANCH%';
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
SET p_min_leadin_min = 15;      -- [SHORTS] Jill, 24 Sep 2026: when History Shorts
                                -- airs right before the series, the short is not
                                -- the lead-in; go back to the programme before it.
                                -- Anything shorter than this many minutes is
                                -- stepped over. NULL turns the rule off.
SET p_adjacent_min  = 5;        -- [ADJACENT] a programme leads in if it ends within
                                -- this many minutes of the block start, not only
                                -- on the exact second. Nielsen books the 8pm
                                -- Skinwalker repeat as ending 20:58 because a
                                -- two-minute short inside it is carved out, so
                                -- exact adjacency found nothing on five nights.
SET p_rollup        = FALSE;    -- [LEADIN-ROLLUP] Jill, 24 Sep 2026: not one row
                                -- per telecast. TRUE returns the season: the
                                -- series average against the average of all its
                                -- lead-ins, then one row per lead-in programme.
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
night AS (
    -- everything the network aired on the nights the series ran, so the walk
    -- back has something to walk over. Repeats included: a lead-in is often one.
    SELECT f.NETWORK_CODE, f.BROADCAST_DATE, f.PROGRAM_CODE, f.TELECAST_NUM,
           f.PROGRAM_NAME, f.START_TIME, f.END_TIME, f.BCAST_START_2959,
           f.CONTRIBUTING_DURATION, f.IS_FIRST_RUN_CT, f.DEMO
    FROM fact f
    WHERE f.BROADCAST_DATE IN (SELECT DISTINCT BROADCAST_DATE FROM series)
),
blk AS (
    -- [BLK1] contiguous first-run episodes of the series on one night
    SELECT s.NETWORK_CODE, s.BROADCAST_DATE, s.PROGRAM_CODE,
           MAX(s.PROGRAM_NAME)  AS PROGRAM_NAME,
           MAX(s.NORM_KEY)      AS NORM_KEY,
           COUNT(*)             AS EPISODES,
           MIN(s.START_TIME)    AS BLOCK_START,
           MAX(s.END_TIME)      AS BLOCK_END,
           SUM(s.DEMO * s.CONTRIBUTING_DURATION)
             / NULLIF(SUM(s.CONTRIBUTING_DURATION), 0) AS BLOCK_AA,
           SUM(s.CONTRIBUTING_DURATION) AS BLOCK_MIN
    FROM series s
    GROUP BY s.NETWORK_CODE, s.BROADCAST_DATE, s.PROGRAM_CODE
),
shorts AS (
    SELECT NETWORK_CODE, BROADCAST_DATE, START_TIME, END_TIME
    FROM night
    WHERE $p_min_leadin_min IS NOT NULL
      AND CONTRIBUTING_DURATION < $p_min_leadin_min
),
blk_adj AS (
    SELECT b.*, COALESCE(sh.START_TIME, b.BLOCK_START) AS ADJ_START
    FROM blk b
    LEFT JOIN shorts sh
      ON  sh.NETWORK_CODE   = b.NETWORK_CODE
      AND sh.BROADCAST_DATE = b.BROADCAST_DATE
      AND TO_TIME(sh.END_TIME) <= TO_TIME(b.BLOCK_START)
      AND TIMEDIFF('minute', TO_TIME(sh.END_TIME), TO_TIME(b.BLOCK_START)) <= COALESCE($p_adjacent_min, 0)
),
leadin_pick AS (
    -- [BLK2a] which programme handed off to the block. One row per block.
    --
    -- This used to be a correlated subquery with LIMIT 1 inside the WHERE of
    -- the CTE below, and it had three problems at once. Snowflake will not
    -- evaluate that shape at all ("unsupported subquery type"). The LIMIT had
    -- no ORDER BY, so when two programmes ended at the same minute the result
    -- was whichever the scan reached first, and two identical runs could report
    -- different lead-ins. And it was correlated per block, which is work
    -- repeated for every row.
    --
    -- As a joined CTE with QUALIFY it is one pass, and the pick is stated:
    -- longest contiguous run wins, PROGRAM_CODE breaks the tie, so the answer
    -- never depends on scan order.
    SELECT b.NETWORK_CODE, b.BROADCAST_DATE,
           b.PROGRAM_CODE AS SERIES_CODE,
           n.PROGRAM_CODE AS LEADIN_CODE,
           MIN(n.START_TIME) AS RUN_START
    FROM blk_adj b
    JOIN night n
      ON  n.NETWORK_CODE   = b.NETWORK_CODE
      AND n.BROADCAST_DATE = b.BROADCAST_DATE
      AND TO_TIME(n.END_TIME) <= TO_TIME(b.ADJ_START)
      AND TIMEDIFF('minute', TO_TIME(n.END_TIME), TO_TIME(b.ADJ_START)) <= COALESCE($p_adjacent_min, 0)
      AND ($p_min_leadin_min IS NULL OR n.CONTRIBUTING_DURATION >= $p_min_leadin_min)      -- adjacency, exact
      -- [BLK2c] exclude only what is IN the block, not the programme itself.
      -- It used to read n.PROGRAM_CODE <> b.PROGRAM_CODE, which threw away a
      -- repeat of the same series. A&E, Trial 2: "a repeat of the same program
      -- can also be a valid lead-in." Secret Skinwalker Ranch airs three repeats
      -- and then the premiere at 9pm, so the only adjacent programme was itself
      -- and every night came back with no lead-in at all.
      -- The block is the night's FIRST RUNS, so excluding those keeps the
      -- Customer Wars case intact: its 10:30p episode still cannot lead into its
      -- own 10p episode.
      AND NOT (n.PROGRAM_CODE = b.PROGRAM_CODE AND n.IS_FIRST_RUN_CT)
    GROUP BY b.NETWORK_CODE, b.BROADCAST_DATE, b.PROGRAM_CODE, n.PROGRAM_CODE
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY b.NETWORK_CODE, b.BROADCAST_DATE, b.PROGRAM_CODE
        ORDER BY SUM(n.CONTRIBUTING_DURATION) DESC, n.PROGRAM_CODE) = 1
),
leadin_seed AS (
    -- [BLK2b] that programme's whole contiguous run, duration weighted.
    --
    -- Bounded below by RUN_START, not open-ended. It used to take every airing
    -- of the chosen programme earlier that night, so a lead-in that also ran in
    -- the afternoon had its afternoon delivery averaged into the hand-off and
    -- the retention came out wrong for a reason nothing in the output showed.
    SELECT p.NETWORK_CODE, p.BROADCAST_DATE, p.SERIES_CODE,
           p.LEADIN_CODE, MAX(n.PROGRAM_NAME) AS LEADIN_PROGRAM,
           MIN(n.START_TIME) AS LEADIN_START, MAX(n.END_TIME) AS LEADIN_END,
           SUM(n.DEMO * n.CONTRIBUTING_DURATION)
             / NULLIF(SUM(n.CONTRIBUTING_DURATION), 0) AS LEADIN_AA,
           SUM(n.CONTRIBUTING_DURATION) AS LEADIN_MIN,
           COUNT(*) AS LEADIN_EPISODES,
           MAX(IFF(n.IS_FIRST_RUN_CT, 0, 1)) AS LEADIN_REPEAT
    FROM leadin_pick p
    JOIN blk b
      ON  b.NETWORK_CODE   = p.NETWORK_CODE
      AND b.BROADCAST_DATE = p.BROADCAST_DATE
      AND b.PROGRAM_CODE   = p.SERIES_CODE
    JOIN night n
      ON  n.NETWORK_CODE   = p.NETWORK_CODE
      AND n.BROADCAST_DATE = p.BROADCAST_DATE
      AND n.PROGRAM_CODE   = p.LEADIN_CODE
      AND n.START_TIME    >= p.RUN_START
      AND n.END_TIME      <= b.BLOCK_START
      AND ($p_min_leadin_min IS NULL OR n.CONTRIBUTING_DURATION >= $p_min_leadin_min)
    GROUP BY p.NETWORK_CODE, p.BROADCAST_DATE, p.SERIES_CODE, p.LEADIN_CODE
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    b.NETWORK_CODE   AS NETWORK,
    b.BROADCAST_DATE AS AIR_DATE,
    b.PROGRAM_NAME   AS PROGRAM,
    b.NORM_KEY       AS SEASON,
    b.EPISODES, b.BLOCK_START, b.BLOCK_END, b.BLOCK_MIN,
    ROUND(b.BLOCK_AA/1000, 0)                              AS BLOCK_AA_000,
    l.LEADIN_PROGRAM,
    CASE WHEN l.LEADIN_PROGRAM IS NULL THEN 'NO LEAD-IN'
         WHEN l.LEADIN_REPEAT = 1      THEN 'REPEAT'
         ELSE 'PREMIERE' END                                    AS LEADIN_AIRING,
    l.LEADIN_START, l.LEADIN_END, l.LEADIN_EPISODES, l.LEADIN_MIN,
    ROUND(l.LEADIN_AA/1000, 0)                             AS LEADIN_AA_000,
    ROUND(ROUND(b.BLOCK_AA/1000,0)
          / NULLIF(ROUND(l.LEADIN_AA/1000,0),0), 4)        AS RETENTION,
    ROUND((ROUND(b.BLOCK_AA/1000,0)
           / NULLIF(ROUND(l.LEADIN_AA/1000,0),0) - 1) * 100, 1) AS PCT_VS_LEADIN,
    $win_from               AS FROM_DATE,
    $win_to                 AS TO_DATE
FROM blk b
LEFT JOIN leadin_seed l
  ON  l.NETWORK_CODE   = b.NETWORK_CODE
  AND l.BROADCAST_DATE = b.BROADCAST_DATE
  AND l.SERIES_CODE    = b.PROGRAM_CODE
WHERE NOT $p_rollup

UNION ALL
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,
    NETWORK_CODE   AS NETWORK,
    NULL           AS AIR_DATE,
    PROGRAM_NAME   AS PROGRAM,
    NORM_KEY       AS SEASON,
    SUM(EPISODES)  AS EPISODES,
    NULL AS BLOCK_START, NULL AS BLOCK_END,
    SUM(BLOCK_MIN) AS BLOCK_MIN,
    ROUND(SUM(BLOCK_AA * BLOCK_MIN) / NULLIF(SUM(BLOCK_MIN),0) / 1000, 0)        AS BLOCK_AA_000,
    COALESCE(LEADIN_PROGRAM, 'ALL LEAD-INS')                                       AS LEADIN_PROGRAM,
    IFF(GROUPING(LEADIN_PROGRAM) = 1, 'ALL',
        IFF(MAX(LEADIN_REPEAT) = 1, 'REPEAT', 'PREMIERE'))                         AS LEADIN_AIRING,
    NULL AS LEADIN_START, NULL AS LEADIN_END,
    SUM(LEADIN_EPISODES) AS LEADIN_EPISODES,
    SUM(LEADIN_MIN)      AS LEADIN_MIN,
    ROUND(SUM(LEADIN_AA * LEADIN_MIN) / NULLIF(SUM(LEADIN_MIN),0) / 1000, 0)     AS LEADIN_AA_000,
    ROUND(ROUND(SUM(BLOCK_AA * BLOCK_MIN) / NULLIF(SUM(BLOCK_MIN),0) / 1000, 0)
          / NULLIF(ROUND(SUM(LEADIN_AA * LEADIN_MIN) / NULLIF(SUM(LEADIN_MIN),0) / 1000, 0), 0), 4) AS RETENTION,
    ROUND((ROUND(SUM(BLOCK_AA * BLOCK_MIN) / NULLIF(SUM(BLOCK_MIN),0) / 1000, 0)
           / NULLIF(ROUND(SUM(LEADIN_AA * LEADIN_MIN) / NULLIF(SUM(LEADIN_MIN),0) / 1000, 0), 0) - 1) * 100, 1) AS PCT_VS_LEADIN,
    $win_from AS FROM_DATE,
    $win_to   AS TO_DATE
FROM (
    SELECT b.NETWORK_CODE, b.PROGRAM_NAME, b.NORM_KEY, b.EPISODES, b.BLOCK_MIN, b.BLOCK_AA,
           l.LEADIN_PROGRAM, l.LEADIN_REPEAT, l.LEADIN_EPISODES, l.LEADIN_MIN, l.LEADIN_AA
    FROM blk b
    JOIN leadin_seed l
      ON  l.NETWORK_CODE   = b.NETWORK_CODE
      AND l.BROADCAST_DATE = b.BROADCAST_DATE
      AND l.SERIES_CODE    = b.PROGRAM_CODE
    WHERE $p_rollup
)
GROUP BY NETWORK_CODE, PROGRAM_NAME, NORM_KEY, ROLLUP(LEADIN_PROGRAM)
ORDER BY 3 NULLS LAST, 11;