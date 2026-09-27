/* ============================================================================
   FILE       1.2  OVERNIGHT SUMMARY - QUARTER HOURS VS. SEASON NORMS  (PRD Table 2)
   PURPOSE    Per quarter hour of each premiere on the target night: AA, % vs the
              prior QH, the season norm for that QH position, the norm's own % vs
              prior, and the "last full QH vs QH1" summary for both.
   SOURCE     AUDIENCE_DEV_DB.CRIS.CRIS_QH_FACT   [S1-T2]
              dates from AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE   [S1-T0]
   VALIDATION (1) HIST, Live+SD, 2026-05-17, defaults
                  (CRIS - Quarter Hour Examples.xlsx, sheet "Hist Examples")
                  HAZARDOUS HISTORY WINKLER  344 / 347 / 345 / 318
                                     norms   338 / 356 / 355 / 323
                                     last vs QH1  -7.6% actual, -4.4% norm
                  FOOD THAT BUILT AMERICA    294 / 302 / 327 / 311
                                     norms   307 / 271 / 281 / 248
                                     last vs QH1  +5.8% actual, -19.2% norm
              (2) HIST, Live+SD, 2026-04-26, with p_include_leadin_qh = TRUE and
                  p_show_runover = TRUE -> A&E's 11-row table.
                  [D12] confirms the inputs: 319 and 354 on the first two
                  premiere quarter hours, 182 on the 8:45p repeat.
                  (HIST 4-26-26 Overnights Summary Example.xlsx)
                  lead-in QH 182 (norm 230), HHW 319/354/354/344/367
                  (norms 324/346/352/334/363), FTBA 336/268/252/212/204
                  (norms 323/263/257/221/209)
              Each case is reproduced by pinning p_target_date to its night.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network           = 'HIST';
SET p_rating_src        = 'Live+SD';
SET p_target_date       = NULL;    -- NULL = latest night with QH data
SET p_season            = NULL;    -- [S1-SEASON] NULL = the season the night's
                                   -- premiere belongs to, resolved from the
                                   -- telecast itself. A value pins one, e.g.
                                   -- '13' or '13B'. Sub-seasons are separate:
                                   -- '13' does not include '13B'.
SET p_include_leadin_qh = FALSE;   -- TRUE = keep the repeat lead-in and chain across programmes
SET p_show_runover      = FALSE;   -- TRUE = keep the trailing short QH as a flagged row
SET p_runover_max_min   = 15;      -- trailing QH shorter than this is a runover
SET p_win_start_2959    = 2000;    -- [S1-WIN] 8:00p, see 1.1
SET p_win_end_2959      = 2400;    -- 12:00a, exclusive
SET p_demo = NULL;                 -- [S1-DEMO] NULL = DEMO_AA, the network's own
                                   -- default, which is what every validated figure
                                   -- was measured in. Otherwise name any AA column
                                   -- the source view carries, e.g.
                                   -- 'P18_49_AA_ESTIMATES', 'F25_64_AA_ESTIMATES',
                                   -- 'M25_54_AA_ESTIMATES'. Nothing is composed or
                                   -- summed: the name is the column.
SET eff_demo = (SELECT COALESCE($p_demo, 'DEMO_AA'));
-- [S1-T0] lookup instead of a MAX over ~295M rows. This reads the QUARTER HOUR
-- max date, not the total-program one: QH can post later, and resolving the
-- target night from the wrong side returns an empty result with no error.
SET data_max_d = (SELECT LATEST_QH_BROADCAST_DATE
                    FROM AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE
                    WHERE NETWORK_CODE = $p_network
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
target AS (
    -- the seasons that premiered on the reported night
    -- [S1-KEY] identity is PROGRAM_CODE; PROGRAM_NAME is carried for display only
    SELECT DISTINCT f2.NETWORK_CODE, f2.PROGRAM_CODE, f2.CT_SEASON
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_QH_FACT f2
    WHERE f2.BROADCAST_DATE = $eff_target
      AND f2.IS_FIRST_RUN_CT
      AND ($p_rating_src IS NULL OR f2.RATING_SOURCE = $p_rating_src)
      AND ($p_network    IS NULL OR f2.NETWORK_CODE  = $p_network)
      AND ($p_win_start_2959 IS NULL OR f2.EP_START_2959 >= $p_win_start_2959)  -- [S1-WIN]
      AND ($p_win_end_2959   IS NULL OR f2.EP_START_2959 <  $p_win_end_2959)
      -- [S1-SEASON] the per-position norm is a season comparison, see 1.1. Only
      -- the SERIES is filtered here. Cable Tracks attaches a season to premieres
      -- alone, so every repeat carries NULL and the lead-in is never compared
      -- against its own season; filtering it would empty the lead-in mode.
      AND f2.CT_SEASON IS NOT NULL
      -- [S1-SEASON] pinning a season narrows which of the night's premieres is
      -- in scope. It cannot reach a season that did not air on the target night:
      -- the norm is built for the telecast being reported, not for an arbitrary
      -- season of the same programme.
      AND ($p_season IS NULL OR f2.CT_SEASON = $p_season)
),
prem AS (
    -- every premiere QH of those seasons up to the reported night
    SELECT
        f.NETWORK_CODE, f.PROGRAM_CODE, f.TELECAST_NUM,
        f.PROGRAM_NAME, f.EPISODE_NAME, f.CT_SEASON,
        t.CT_SEASON AS NORM_KEY,   -- [S1-NORMKEY] see 1.1
        f.BROADCAST_DATE, f.DAY_OF_WEEK,
        f.QTR_START_TIME, f.QH_START_2959, f.EP_START_2959,
        CAST(f.QH_MIN AS INT) AS QH_MIN,
        f.IS_FIRST_RUN_CT, IDENTIFIER($eff_demo) AS DEMO_AA
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_QH_FACT f
    JOIN target t
      ON  t.NETWORK_CODE = f.NETWORK_CODE
      AND t.PROGRAM_CODE = f.PROGRAM_CODE            -- [S1-KEY]
      AND f.CT_SEASON = t.CT_SEASON
    WHERE ($p_rating_src IS NULL OR f.RATING_SOURCE = $p_rating_src)
      AND f.BROADCAST_DATE <= $eff_target
      AND f.IS_FIRST_RUN_CT
),
span AS (
    -- [S1-LEADIN] the season's own date range, taken from its premieres
    SELECT NETWORK_CODE, PROGRAM_CODE, NORM_KEY,
           MIN(BROADCAST_DATE) AS SEASON_FROM,
           MAX(BROADCAST_DATE) AS SEASON_TO
    FROM prem
    GROUP BY NETWORK_CODE, PROGRAM_CODE, NORM_KEY
),
leadin AS (
    -- [S1-LEADIN] Cable Tracks only attaches a season to premiere telecasts, so
    -- every repeat arrives with CT_SEASON NULL. [D11] on 2026-04-26: the 9p
    -- premiere reads season 2, its own 8p repeat reads NULL, and [D13] shows the
    -- season keys not matching. Scoping repeats by season key therefore drops
    -- the lead-in entirely, which is what the previous version did.
    -- They are scoped by the season's date span instead, which is what makes
    -- A&E's lead-in norm of 230 reachable: the 8:45p quarter hour across the two
    -- nights the season has run, 278 and 182.
    SELECT
        f.NETWORK_CODE, f.PROGRAM_CODE, f.TELECAST_NUM,
        f.PROGRAM_NAME, f.EPISODE_NAME, f.CT_SEASON,
        s.NORM_KEY,
        f.BROADCAST_DATE, f.DAY_OF_WEEK,
        f.QTR_START_TIME, f.QH_START_2959, f.EP_START_2959,
        CAST(f.QH_MIN AS INT) AS QH_MIN,
        f.IS_FIRST_RUN_CT, IDENTIFIER($eff_demo) AS DEMO_AA
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_QH_FACT f
    JOIN span s
      ON  s.NETWORK_CODE = f.NETWORK_CODE
      AND s.PROGRAM_CODE = f.PROGRAM_CODE
    WHERE $p_include_leadin_qh
      AND NOT f.IS_FIRST_RUN_CT
      AND ($p_rating_src IS NULL OR f.RATING_SOURCE = $p_rating_src)
      AND f.BROADCAST_DATE BETWEEN s.SEASON_FROM AND s.SEASON_TO
),
base AS (
    SELECT * FROM prem
    UNION ALL
    SELECT * FROM leadin
),
seq AS (
    -- [S1-QH] number the QHs inside a telecast. The telecast is now identified by
    -- PROGRAM_CODE + TELECAST_NUM; v5 approximated it with programme name,
    -- episode name and start hour/minute.
    SELECT b.*,
        ROW_NUMBER() OVER (PARTITION BY NETWORK_CODE, BROADCAST_DATE,
                           PROGRAM_CODE, TELECAST_NUM
                           ORDER BY QH_START_2959)                    AS QH_NUM,
        COUNT(*)     OVER (PARTITION BY NETWORK_CODE, BROADCAST_DATE,
                           PROGRAM_CODE, TELECAST_NUM)                AS TOTAL_QH
    FROM base b
),
flagged AS (
    -- only the TRAILING short QH is a runover. A short QH1 is a real first
    -- quarter hour shortened by the previous programme's overrun and is kept:
    -- on 2026-05-17 FTBA's QH1 is 12 minutes and A&E keeps it, while the
    -- 3-minute QH5 is dropped.
    SELECT s.*,
        CASE WHEN QH_NUM = TOTAL_QH AND QH_MIN < $p_runover_max_min
             THEN 1 ELSE 0 END                                        AS IS_RUNOVER
    FROM seq s
),
norm AS (
    -- Season norm per programme, season, airing type and QH position.
    -- Built from `flagged`, not from `kept`, so trimming the displayed rows can
    -- never thin a norm. REPEAT_IND is part of the key: premieres are normed
    -- against premieres and the repeat lead-in against its own repeats, which is
    -- how A&E's 230 arises.
    SELECT NETWORK_CODE, PROGRAM_CODE, NORM_KEY, IS_FIRST_RUN_CT, QH_NUM,
           SUM(DEMO_AA * QH_MIN) / NULLIF(SUM(QH_MIN), 0) AS NORM_AA,  -- [WAVG] duration weighted, Adarsh 11 Sep 2026: every aggregation.
           COUNT(*)     AS NORM_TC
    FROM flagged
    -- [S1-NORM] the reported night is not part of its own norm. See 1.1. Here it
    -- is a filter rather than a NULL because this CTE only ever feeds the norm;
    -- the displayed rows come from `kept`, so dropping the night costs nothing.
    WHERE BROADCAST_DATE <> $eff_target
      AND ($p_show_runover OR IS_RUNOVER = 0)
    -- [S1-SEASON-B] the group key is the same key the join below uses
    GROUP BY NETWORK_CODE, PROGRAM_CODE, NORM_KEY, IS_FIRST_RUN_CT, QH_NUM
),
kept AS (
    SELECT * FROM flagged
    WHERE ($p_show_runover OR IS_RUNOVER = 0)
      -- [S1-LEADIN] the lead-in contributes exactly one displayed row, the
      -- quarter hour it hands off on. A&E's 11-row table shows 08:45P alone,
      -- not all four quarter hours of the 8P repeat. Its earlier nights stay in
      -- `flagged` and so still feed the norm above.
      AND ( IS_FIRST_RUN_CT
            OR BROADCAST_DATE <> $eff_target
            OR QH_NUM = TOTAL_QH )
),
joined AS (
    SELECT k.*, n.NORM_AA, n.NORM_TC
    FROM kept k
    LEFT JOIN norm n
      ON  n.NETWORK_CODE = k.NETWORK_CODE
      AND n.PROGRAM_CODE = k.PROGRAM_CODE            -- [S1-KEY]
      AND EQUAL_NULL(n.NORM_KEY, k.NORM_KEY)        -- [S1-NORMKEY]
      AND n.IS_FIRST_RUN_CT   = k.IS_FIRST_RUN_CT              -- [S1-LEADIN]
      AND n.QH_NUM       = k.QH_NUM
),
night AS (
    SELECT * FROM joined WHERE BROADCAST_DATE = $eff_target
),
calc AS (
    SELECT n.*,
        -- [S1-QHCHAIN] with the lead-in off, "vs prior QH" is empty on QH1 of
        -- each premiere, which is the chart format. With it on, the comparison
        -- chains across the whole night in broadcast order, which reproduces
        -- A&E's raw 11-row table.
        CASE WHEN $p_include_leadin_qh
             THEN LAG(DEMO_AA) OVER (PARTITION BY NETWORK_CODE, BROADCAST_DATE
                                     ORDER BY QH_START_2959)
             ELSE LAG(DEMO_AA) OVER (PARTITION BY NETWORK_CODE, BROADCAST_DATE,
                                     PROGRAM_CODE, TELECAST_NUM
                                     ORDER BY QH_NUM)
        END                                                           AS PREV_AA,
        LAG(NORM_AA) OVER (PARTITION BY NETWORK_CODE, BROADCAST_DATE,
                           PROGRAM_CODE, TELECAST_NUM
                           ORDER BY QH_NUM)                           AS PREV_NORM_AA,
        FIRST_VALUE(DEMO_AA) OVER (PARTITION BY NETWORK_CODE, BROADCAST_DATE,
                           PROGRAM_CODE, TELECAST_NUM ORDER BY QH_NUM
                           ROWS BETWEEN UNBOUNDED PRECEDING
                                    AND UNBOUNDED FOLLOWING)          AS QH1_AA,
        FIRST_VALUE(NORM_AA) OVER (PARTITION BY NETWORK_CODE, BROADCAST_DATE,
                           PROGRAM_CODE, TELECAST_NUM ORDER BY QH_NUM
                           ROWS BETWEEN UNBOUNDED PRECEDING
                                    AND UNBOUNDED FOLLOWING)          AS QH1_NORM_AA,
        MAX(CASE WHEN IS_RUNOVER = 0 THEN QH_NUM END)
            OVER (PARTITION BY NETWORK_CODE, BROADCAST_DATE,
                  PROGRAM_CODE, TELECAST_NUM)                         AS LAST_FULL_QH
    FROM night n
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    NETWORK_CODE     AS NETWORK,
    BROADCAST_DATE   AS AIR_DATE,
    DAY_OF_WEEK      AS DAY,
    PROGRAM_NAME     AS PROGRAM,
    EPISODE_NAME     AS EPISODE,
    CT_SEASON        AS SEASON,
    IFF(NOT IS_FIRST_RUN_CT, 'LEAD-IN (REPEAT)', 'QH' || QH_NUM)           AS QUARTER_HOUR,
    QTR_START_TIME   AS QH_START,
    QH_START_2959    AS QH_START_2959,
    QH_MIN, IS_RUNOVER,
    ROUND(DEMO_AA/1000,0)                                             AS AA_000,
    -- shown on the runover row too: A&E's 4/26 sheet prints +6.7% on the
    -- 3-minute QH5 (367 vs 344). The runover is excluded from FINAL_VS_QH1
    -- below, not from its own step change.
    CASE WHEN PREV_AA IS NOT NULL
         THEN ROUND((ROUND(DEMO_AA/1000,0)
                     / NULLIF(ROUND(PREV_AA/1000,0),0) - 1) * 100, 1)
    END                                                               AS VS_PRIOR_QH_PCT,
    ROUND(NORM_AA/1000,0)                                             AS NORM_AA_000,
    CASE WHEN PREV_NORM_AA IS NOT NULL
         THEN ROUND((ROUND(NORM_AA/1000,0)
                     / NULLIF(ROUND(PREV_NORM_AA/1000,0),0) - 1) * 100, 1)
    END                                                               AS NORM_VS_PRIOR_QH_PCT,
    NORM_TC,
    -- last full QH vs QH1, telecast and norm (A&E method: rounded 000s)
    ROUND((ROUND(MAX(CASE WHEN QH_NUM = LAST_FULL_QH THEN DEMO_AA END)
                 OVER (PARTITION BY NETWORK_CODE, BROADCAST_DATE,
                       PROGRAM_CODE, TELECAST_NUM) / 1000, 0)
           / NULLIF(ROUND(QH1_AA/1000,0),0) - 1) * 100, 1)            AS FINAL_VS_QH1_PCT,
    ROUND((ROUND(MAX(CASE WHEN QH_NUM = LAST_FULL_QH THEN NORM_AA END)
                 OVER (PARTITION BY NETWORK_CODE, BROADCAST_DATE,
                       PROGRAM_CODE, TELECAST_NUM) / 1000, 0)
           / NULLIF(ROUND(QH1_NORM_AA/1000,0),0) - 1) * 100, 1)       AS FINAL_VS_QH1_NORM_PCT,
    $eff_target             AS TO_DATE
FROM calc
-- [S1-2959] order by the episode's place in the broadcast night, then by QH.
-- Sorting on START_TIME put a 12:30a episode ahead of a 10p one from the same night.
ORDER BY EP_START_2959, QH_NUM;