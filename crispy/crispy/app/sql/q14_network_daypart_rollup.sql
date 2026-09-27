/* ============================================================================
   FILE       1.4  NETWORK AND DAYPART ROLLUP        (PRD no-premiere fallback)
   PURPOSE    For the reported night: the night's delivery rolled up by daypart,
              quarter-hour based and duration weighted, plus the premiere count
              that decides whether the answer uses the no-premiere wording.
   SOURCE     AUDIENCE_DEV_DB.CRIS.CRIS_QH_FACT   [S1-T2]
              dates from AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE   [S1-T0]
   VALIDATION No A&E workbook prints this exact table, so there is no single
              number to match. What must hold:
                * PREMIERES_IN_WINDOW for the OVERNIGHT row equals the row count
                  1.1 returns for the same night and parameters
                * MINUTES for TOTAL DAY equals the sum of the night's
                  CONTRIBUTING_DURATION in [S1-T2]
                * PRIME is a strict subset of OVERNIGHT, which is a strict
                  subset of TOTAL DAY, on both TELECASTS and MINUTES
              Nearest external reference: SP_7 puts HIST prime at 182 over
              09/29/25-05/31/26, which is a season-long average, not a night.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network          = 'HIST';   -- NULL = all A+E networks
SET p_rating_src       = 'Live+SD';
SET p_target_date      = NULL;     -- NULL = latest night with QH data
SET p_include_specials = TRUE;
SET p_demo = NULL;                 -- [S1-DEMO] NULL = DEMO_AA, the network's own
                                   -- default, which is what every validated figure
                                   -- was measured in. Otherwise name any AA column
                                   -- the source view carries, e.g.
                                   -- 'P18_49_AA_ESTIMATES', 'F25_64_AA_ESTIMATES',
                                   -- 'M25_54_AA_ESTIMATES'. Nothing is composed or
                                   -- summed: the name is the column.
SET eff_demo = (SELECT COALESCE($p_demo, 'DEMO_AA'));

SET data_max_d = (SELECT MAX(LATEST_QH_BROADCAST_DATE)
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

WITH qh AS (
    SELECT
        NETWORK_CODE, BROADCAST_DATE, DAY_OF_WEEK,
        PROGRAM_CODE, TELECAST_NUM, IS_FIRST_RUN_CT, CONTENT_TYPE,
        QH_START_2959,
        CAST(QH_MIN AS FLOAT) AS QH_MIN,
        IDENTIFIER($eff_demo) AS DEMO_AA
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_QH_FACT
    WHERE BROADCAST_DATE = $eff_target
      AND ($p_network    IS NULL OR NETWORK_CODE  = $p_network)
      AND ($p_rating_src IS NULL OR RATING_SOURCE = $p_rating_src)
      AND ($p_include_specials OR CONTENT_TYPE <> 'Special')
),
daypart AS (
    -- [S1-DP] boundaries taken from A&E's own report headers, in Nielsen HHMM.
    -- The upper bound is exclusive, so a quarter hour belongs to the daypart its
    -- own start falls in and a telecast straddling a boundary splits correctly.
              SELECT 1 AS ORD, 'TOTAL DAY 6A-6A'   AS DAYPART,  600 AS FROM_2959, 2960 AS TO_2959
    UNION ALL SELECT 2 AS ORD, 'OVERNIGHT 8P-12A'  AS DAYPART, 2000 AS FROM_2959, 2400 AS TO_2959
    UNION ALL SELECT 3 AS ORD, 'PRIME M-SU 8P-11P' AS DAYPART, 2000 AS FROM_2959, 2300 AS TO_2959
),
joined AS (
    SELECT d.ORD, d.DAYPART,
           q.NETWORK_CODE, q.BROADCAST_DATE, q.DAY_OF_WEEK,
           q.PROGRAM_CODE, q.TELECAST_NUM, q.IS_FIRST_RUN_CT,
           q.QH_MIN, q.DEMO_AA
    FROM qh q
    JOIN daypart d
      ON  q.QH_START_2959 >= d.FROM_2959
      AND q.QH_START_2959 <  d.TO_2959
),
rolled AS (
    SELECT
        NETWORK_CODE, BROADCAST_DATE, DAY_OF_WEEK, ORD, DAYPART,
        COUNT(DISTINCT TO_VARCHAR(PROGRAM_CODE)||'-'||TO_VARCHAR(TELECAST_NUM)) AS TELECASTS,
        COUNT(DISTINCT CASE WHEN IS_FIRST_RUN_CT
                       THEN TO_VARCHAR(PROGRAM_CODE)||'-'||TO_VARCHAR(TELECAST_NUM) END) AS PREMIERES,
        COUNT(*)                                        AS QUARTER_HOURS,
        SUM(QH_MIN)                                     AS MINUTES,
        -- duration weighted, per A&E's own weighting footnote
        SUM(DEMO_AA * QH_MIN) / NULLIF(SUM(QH_MIN),0)   AS AA_WTD
    FROM joined
    GROUP BY NETWORK_CODE, BROADCAST_DATE, DAY_OF_WEEK, ORD, DAYPART
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    NETWORK_CODE   AS NETWORK,
    BROADCAST_DATE AS AIR_DATE,
    DAY_OF_WEEK    AS DAY,
    DAYPART,
    TELECASTS,
    PREMIERES,
    -- the planner reads this to choose between the normal answer and the
    -- "no premieres aired" wording the PRD asks for
    MAX(CASE WHEN ORD = 2 THEN PREMIERES END)
        OVER (PARTITION BY NETWORK_CODE)            AS PREMIERES_IN_WINDOW,
    QUARTER_HOURS,
    MINUTES,
    ROUND(AA_WTD/1000,0)                            AS AA_000,          -- the reportable one
    $eff_target             AS TO_DATE
FROM rolled
ORDER BY NETWORK, ORD;