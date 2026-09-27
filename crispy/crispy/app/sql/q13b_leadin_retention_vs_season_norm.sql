/* ============================================================================
   FILE       1.3b LEAD-IN RETENTION VS. SEASON NORM        (PRD Table 3)
   PURPOSE    Per premiere on the target night: tonight's lead-in retention, the
              season-to-date retention norm, and that norm split by lead-in
              programme and lead-in airing.
   SOURCE     AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT   [S1-T1]
              dates from AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE   [S1-T0]
                  (HIST 4-26-26 Overnights Summary Example.xlsx)
                  HAZARDOUS HISTORY WINKLER  TONIGHT 344 / 182 = 1.8901
                                             SEASON  340 / 232 = 1.4655
                  FOOD THAT BUILT AMERICA    TONIGHT 259 / 344 = 0.7529
                                             SEASON  258 / 340 = 0.7588
                  (Lead-In Examples.xlsx, sheet "INTERROGATION RAW")
                  TONIGHT                       126 / 140 = 0.9000
                  SEASON, ALL LEAD-INS  14 TC   148 / 150 = 0.9867
                  AFTER THE FIRST 48     7 TC   141 / 128 = 1.1016
                  FIRST 48: INSIDE TAPE  4 TC   150 / 179 = 0.8380
                  THE FIRST 48 PREMIERE  1 TC   162 / 186 = 0.8710
                  THE FIRST 48 REPEAT    2 TC   167 / 156 = 1.0705
              A&E's own inconsistency between workbooks, not a defect here; the
              parameter is what keeps both reproducible.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network          = 'HIST';
SET p_rating_src       = 'Live+SD';
SET p_target_date      = NULL;     -- NULL = latest night with data
SET p_season           = NULL;     -- [S1-SEASON] NULL = the season the night's
                                   -- premiere belongs to. A value pins one,
                                   -- e.g. '13' or '13B'. Sub-seasons are
                                   -- separate: '13' does not include '13B'.
SET p_min_leadin_dur   = 15;       -- ignore lead-ins shorter than this; NULL = no cutoff
SET p_include_specials = TRUE;
SET p_win_start_2959   = 2000;     -- [S1-WIN] 8:00p, see 1.1
SET p_win_end_2959     = 2400;     -- 12:00a, exclusive
SET p_demo = NULL;                 -- [S1-DEMO] NULL = DEMO_AA, the network's own
                                   -- default, which is what every validated figure
                                   -- was measured in. Otherwise name any AA column
                                   -- the source view carries, e.g.
                                   -- 'P18_49_AA_ESTIMATES', 'F25_64_AA_ESTIMATES',
                                   -- 'M25_54_AA_ESTIMATES'. Nothing is composed or
                                   -- summed: the name is the column.
SET eff_demo = (SELECT COALESCE($p_demo, 'DEMO_AA'));
SET data_max_d = (SELECT MAX(LATEST_BROADCAST_DATE)
                    FROM AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE
                    WHERE ($p_network IS NULL OR NETWORK_CODE = $p_network)
                      AND RATING_SOURCE = $p_rating_src);
-- [CAP-SUN] a target date past the latest night with data falls back to that night.
SET eff_target = (SELECT LEAST(COALESCE(TO_DATE($p_target_date), $data_max_d), $data_max_d));


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
fact AS (
    SELECT NETWORK_CODE, PROGRAM_CODE, TELECAST_NUM,
           PROGRAM_NAME, EPISODE_NAME, CT_SEASON,
           BROADCAST_DATE, DAY_OF_WEEK, START_TIME, END_TIME, BCAST_START_2959,
           CONTRIBUTING_DURATION, IS_FIRST_RUN_CT, CONTENT_TYPE,
           IDENTIFIER($eff_demo) AS DEMO_AA
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT
    WHERE ($p_network    IS NULL OR NETWORK_CODE  = $p_network)
      AND ($p_rating_src IS NULL OR RATING_SOURCE = $p_rating_src)
      AND BROADCAST_DATE <= $eff_target
      AND ($p_include_specials OR CONTENT_TYPE <> 'Special')
),
target AS (
    -- the seasons that premiered tonight  [S1-KEY]
    SELECT DISTINCT f2.NETWORK_CODE, f2.PROGRAM_CODE, f2.CT_SEASON
    FROM fact f2
    WHERE BROADCAST_DATE = $eff_target
      AND IS_FIRST_RUN_CT
      AND ($p_win_start_2959 IS NULL OR BCAST_START_2959 >= $p_win_start_2959)  -- [S1-WIN]
      AND ($p_win_end_2959   IS NULL OR BCAST_START_2959 <  $p_win_end_2959)
      -- [S1-SEASON] the SERIES only, never the lead-in. See 1.2.
      AND CT_SEASON IS NOT NULL        -- [S1-SEASON] see 1.1
      -- [S1-SEASON] narrows which of the night's premieres is in scope. The
      -- lead-in is deliberately NOT filtered by it: Cable Tracks attaches a
      -- season to premieres alone, so every repeat carries NULL.
      AND ($p_season IS NULL OR CT_SEASON = $p_season)
),
pairs AS (
    -- every premiere of those seasons paired with whatever aired immediately
    -- before it that night. The lead-in may be a repeat: that is the normal
    -- schedule shape and week 1 section 4B says to keep it and report it.
    SELECT
        p.NETWORK_CODE, p.PROGRAM_CODE, p.PROGRAM_NAME, p.EPISODE_NAME,
        -- only path from `target` to the three CTEs below that report it, and
        -- leaving it out here is what broke the compile in v16.
        p.CT_SEASON,
        t.CT_SEASON AS NORM_KEY,   -- [S1-NORMKEY] see 1.1
        p.BROADCAST_DATE, p.DAY_OF_WEEK,
        p.START_TIME, p.DEMO_AA                       AS PREM_AA,
        p.CONTRIBUTING_DURATION                       AS PREM_W,
        -- [S1-KEY] the lead-in is grouped on its code and labelled with its name
        l.PROGRAM_CODE                                AS LEADIN_CODE,
        l.PROGRAM_NAME                                AS LEADIN_PROGRAM,
        IFF(NOT l.IS_FIRST_RUN_CT, 'REPEAT', 'PREMIERE')   AS LEADIN_AIRING,
        l.DEMO_AA                                     AS LEADIN_AA,
        l.CONTRIBUTING_DURATION                       AS LEADIN_W
    FROM fact p
    JOIN target t
      ON  t.NETWORK_CODE = p.NETWORK_CODE
      AND t.PROGRAM_CODE = p.PROGRAM_CODE            -- [S1-KEY]
      AND p.CT_SEASON = t.CT_SEASON
    JOIN fact l
      ON  l.NETWORK_CODE   = p.NETWORK_CODE
      AND l.BROADCAST_DATE = p.BROADCAST_DATE
      AND l.END_TIME       = p.START_TIME             -- adjacency
      AND NOT (l.PROGRAM_CODE = p.PROGRAM_CODE AND l.TELECAST_NUM = p.TELECAST_NUM)
      AND ($p_min_leadin_dur IS NULL OR l.CONTRIBUTING_DURATION >= $p_min_leadin_dur)
    WHERE p.IS_FIRST_RUN_CT
),
tonight AS (
    SELECT
        NETWORK_CODE, PROGRAM_CODE, PROGRAM_NAME, EPISODE_NAME, CT_SEASON, NORM_KEY,
        BROADCAST_DATE, DAY_OF_WEEK, START_TIME,
        'TONIGHT'                       AS SCOPE,
        LEADIN_PROGRAM, LEADIN_AIRING,
        1                               AS TC,
        LEADIN_AA, PREM_AA
    FROM pairs
    WHERE BROADCAST_DATE = $eff_target
),
norm_pool AS (
    -- [S1-NORM] the reported night is not part of its own norm. See 1.1. The
    -- night itself is carried separately by `tonight`, so removing it here only
    -- affects what the season retention figures average over.
    SELECT * FROM pairs
    WHERE BROADCAST_DATE <> $eff_target
),
norm_all AS (
    SELECT
        NETWORK_CODE, PROGRAM_CODE, MAX(PROGRAM_NAME) AS PROGRAM_NAME, NORM_KEY,
        'SEASON - ALL LEAD-INS'         AS SCOPE,
        'ALL'                           AS LEADIN_PROGRAM,
        'ALL'                           AS LEADIN_AIRING,
        COUNT(*)                        AS TC,
        SUM(LEADIN_AA * LEADIN_W) / NULLIF(SUM(LEADIN_W), 0)                  AS LEADIN_AA,
        SUM(PREM_AA * PREM_W) / NULLIF(SUM(PREM_W), 0)                    AS PREM_AA
    FROM norm_pool
    GROUP BY NETWORK_CODE, PROGRAM_CODE, NORM_KEY
),
norm_split AS (
    SELECT
        NETWORK_CODE, PROGRAM_CODE, MAX(PROGRAM_NAME) AS PROGRAM_NAME, NORM_KEY,
        'SEASON - BY LEAD-IN'           AS SCOPE,
        MAX(LEADIN_PROGRAM)             AS LEADIN_PROGRAM,
        LEADIN_AIRING,
        COUNT(*)                        AS TC,
        SUM(LEADIN_AA * LEADIN_W) / NULLIF(SUM(LEADIN_W), 0)                  AS LEADIN_AA,
        SUM(PREM_AA * PREM_W) / NULLIF(SUM(PREM_W), 0)                    AS PREM_AA
    FROM norm_pool
    GROUP BY NETWORK_CODE, PROGRAM_CODE, NORM_KEY, LEADIN_CODE, LEADIN_AIRING
),
stacked AS (
    SELECT NETWORK_CODE, PROGRAM_CODE, PROGRAM_NAME, EPISODE_NAME, CT_SEASON, NORM_KEY,
           BROADCAST_DATE, DAY_OF_WEEK, START_TIME,
           SCOPE, LEADIN_PROGRAM, LEADIN_AIRING, TC, LEADIN_AA, PREM_AA, 1 AS SORT_ORD
    FROM tonight
    UNION ALL
    SELECT n.NETWORK_CODE, n.PROGRAM_CODE, n.PROGRAM_NAME, NULL, NULL, n.NORM_KEY,
            NULL, NULL, NULL,
           n.SCOPE, n.LEADIN_PROGRAM, n.LEADIN_AIRING, n.TC, n.LEADIN_AA, n.PREM_AA, 2
    FROM norm_all n
    UNION ALL
    SELECT n.NETWORK_CODE, n.PROGRAM_CODE, n.PROGRAM_NAME, NULL, NULL, n.NORM_KEY,
            NULL, NULL, NULL,
           n.SCOPE, n.LEADIN_PROGRAM, n.LEADIN_AIRING, n.TC, n.LEADIN_AA, n.PREM_AA, 3
    FROM norm_split n
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    NETWORK_CODE   AS NETWORK,
    PROGRAM_CODE,
    PROGRAM_NAME   AS PROGRAM,
    EPISODE_NAME   AS EPISODE,
    CT_SEASON      AS SEASON,
    BROADCAST_DATE AS AIR_DATE,
    SCOPE,
    LEADIN_PROGRAM,
    LEADIN_AIRING,
    TC,
    ROUND(LEADIN_AA/1000,0)                            AS LEADIN_000,
    ROUND(PREM_AA/1000,0)                              AS PROGRAM_000,
    -- A&E method: divide the rounded 000s
    ROUND(ROUND(PREM_AA/1000,0)
          / NULLIF(ROUND(LEADIN_AA/1000,0),0), 4)      AS RETENTION,
    $eff_target             AS TO_DATE
FROM stacked
ORDER BY PROGRAM, SORT_ORD, LEADIN_PROGRAM, LEADIN_AIRING;