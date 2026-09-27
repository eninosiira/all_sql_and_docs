/* ============================================================================
   FILE       2.11 QUARTER-HOUR PERFORMANCE                         (PRD 2.11)
   PURPOSE    Each first-run telecast broken into its quarter hours, against the
              season norm for the same position.
   SOURCE     CRIS_QH_FACT, built in section 1 [S1-T2]
   RULES      [Q1] the short first QH is kept: an offset start such as :05 is
                   real programme time, not noise
              [Q2] only the trailing runover is dropped
              [Q3] the norm per position is LEAVE-ONE-OUT, so an episode never
                   norms against itself
              [Q4] delta from one QH to the next inside the episode
              [Q5] last against first QH per episode
   [S1-2959]  Ordering is by the quarter hour's own start. v6 v1 ordered by the
              EPISODE start, identical on every QH row of that episode, so the
              position came out arbitrary: a 2-minute runover appeared
              mid-episode and the runover filter dropped a real 13-minute QH1.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network       = 'HIST';
SET p_program       = '%SECRET SKINWALKER RANCH%';
SET p_stream        = 'Live+SD';
SET p_norm_basis    = 'TIME_PERIOD';  -- [QH-NORM] what the QH norm is built on.
                                      -- A&E, 24 Sep 2026: the latest 12 months of
                                      -- the network's first-run premieres airing
                                      -- in the SAME time period as the programme,
                                      -- all days of the week, with NO specials,
                                      -- mini-series or Curse exclusions, because
                                      -- what matters here is the within-telecast
                                      -- build, not the audience level. 'SEASON'
                                      -- keeps the old norm: the same series'
                                      -- other telecasts, leave-one-out.
SET p_norm_months   = 12;
SET p_rollup        = FALSE;       -- [QH-ROLLUP] TRUE returns four rows for the
                                   -- season: QH1 to QH4 averaged across every
                                   -- telecast, duration weighted, plus QH4 vs
                                   -- QH1. Jill, 23 Sep 2026: "the average QH
                                   -- across all telecasts for the season". FALSE,
                                   -- the default, returns every telecast's
                                   -- quarter hours as before. The NORM column on
                                   -- the roll-up is the position norm this query
                                   -- already builds; Jill is confirming with the
                                   -- team what the norm should be based on.
SET p_demo      = 'DEMO_AA';
SET p_season        = NULL;
SET p_runover_max_min = 15;
SET p_win_to   = NULL;
SET data_sun = (SELECT LATEST_FULL_SUNDAY FROM AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE
                 WHERE NETWORK_CODE = $p_network AND RATING_SOURCE = $p_stream);
-- [CAP-SUN] the window can never run past the latest full Sunday with data, even when a
-- later date is passed in (A&E review, 27 Sep 2026: TO_DATE showed a date with no data yet).
SET win_to   = (SELECT LEAST(COALESCE(TO_DATE($p_win_to), $data_sun), $data_sun));


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

WITH base AS (
    SELECT f.NETWORK_CODE, f.PROGRAM_CODE, f.TELECAST_NUM,
           f.PROGRAM_NAME, f.EPISODE_NAME, f.CT_SEASON,
           f.BROADCAST_DATE, f.QTR_START_TIME, f.QH_START_2959, f.EP_START_2959,
           CAST(f.QH_MIN AS INT) AS QH_MIN,
           IDENTIFIER($p_demo) AS DEMO
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_QH_FACT f
    WHERE f.NETWORK_CODE  = $p_network
      AND f.RATING_SOURCE = $p_stream
      AND f.IS_FIRST_RUN_CT
      AND f.PROGRAM_NAME ILIKE $p_program
      AND f.BROADCAST_DATE <= $win_to
      AND ($p_season IS NULL OR f.CT_SEASON = $p_season)
      AND f.CT_SEASON IS NOT NULL),
scoped AS (
    -- the season in scope: the most recent one unless pinned
    SELECT b.* FROM base b
    JOIN (SELECT PROGRAM_CODE, CT_SEASON
          FROM base
          QUALIFY ROW_NUMBER() OVER (PARTITION BY PROGRAM_CODE
                                     ORDER BY BROADCAST_DATE DESC) = 1) t
      ON t.PROGRAM_CODE = b.PROGRAM_CODE
     AND EQUAL_NULL(t.CT_SEASON, b.CT_SEASON)
),
seq AS (
    SELECT s.*,
        ROW_NUMBER() OVER (PARTITION BY PROGRAM_CODE, TELECAST_NUM
                           ORDER BY QH_START_2959)  AS QH_NUM,
        COUNT(*)     OVER (PARTITION BY PROGRAM_CODE, TELECAST_NUM) AS TOTAL_QH
    FROM scoped s
),
kept AS (
    -- [Q1] short QH1 kept, [Q2] trailing runover dropped
    SELECT * FROM seq
    WHERE NOT (QH_NUM = TOTAL_QH AND QH_MIN < $p_runover_max_min)
),
tp_norm AS (
    -- [QH-NORM] every first-run telecast on the network in the norm window that
    -- starts in the same half hour and runs the same number of quarter hours as
    -- the programme, position by position. "If Skinwalker airs 9-10, compare to
    -- premieres airing 9-10; if a show is two hours, follow that window."
    SELECT n.QH_NUM,
           SUM(n.DEMO * n.QH_MIN) / NULLIF(SUM(n.QH_MIN), 0) AS TP_NORM_AA,
           COUNT(DISTINCT n.PROGRAM_CODE || '|' || n.TELECAST_NUM || '|' || n.BROADCAST_DATE) AS TP_NORM_TC
    FROM (
        SELECT f.PROGRAM_CODE, f.TELECAST_NUM, f.BROADCAST_DATE, f.EP_START_2959,
               CAST(f.QH_MIN AS INT) AS QH_MIN, IDENTIFIER($p_demo) AS DEMO,
               ROW_NUMBER() OVER (PARTITION BY f.PROGRAM_CODE, f.TELECAST_NUM
                                  ORDER BY f.QH_START_2959) AS QH_NUM,
               COUNT(*) OVER (PARTITION BY f.PROGRAM_CODE, f.TELECAST_NUM) AS TOTAL_QH
        FROM AUDIENCE_DEV_DB.CRIS.CRIS_QH_FACT f
        WHERE f.NETWORK_CODE  = $p_network
          AND f.RATING_SOURCE = $p_stream
          AND f.IS_FIRST_RUN_CT
          AND f.BROADCAST_DATE BETWEEN DATEADD('day', 1, DATEADD('month', -$p_norm_months, $win_to))
                                   AND $win_to
    ) n
    JOIN (SELECT DISTINCT FLOOR(EP_START_2959 / 100) * 100 + IFF(MOD(EP_START_2959, 100) >= 30, 30, 0) AS START_HH,
                          TOTAL_QH
          FROM seq) shape
      ON  FLOOR(n.EP_START_2959 / 100) * 100 + IFF(MOD(n.EP_START_2959, 100) >= 30, 30, 0) = shape.START_HH
      AND n.TOTAL_QH = shape.TOTAL_QH
    WHERE NOT (n.QH_NUM = n.TOTAL_QH AND n.QH_MIN < $p_runover_max_min)
    GROUP BY n.QH_NUM
),
normed AS (
    SELECT k.*,
        t.TP_NORM_AA, t.TP_NORM_TC,
        -- [Q3] leave-one-out: subtract this episode from its own position norm
        -- [QH-WEIGHTED] duration weighted, as the Overnight Summary does it.
        -- A&E, 10 Sep 2026. A short quarter hour used to count the same as a
        -- full one, so a truncated QH1 pulled the position norm toward itself.
        IFF($p_norm_basis = 'TIME_PERIOD', t.TP_NORM_AA,
            (SUM(k.DEMO * k.QH_MIN) OVER (PARTITION BY k.PROGRAM_CODE, k.CT_SEASON, k.QH_NUM)
               - k.DEMO * k.QH_MIN)
              / NULLIF(SUM(k.QH_MIN) OVER (PARTITION BY k.PROGRAM_CODE, k.CT_SEASON, k.QH_NUM)
                       - k.QH_MIN, 0))                                 AS NORM_AA,
        IFF($p_norm_basis = 'TIME_PERIOD', t.TP_NORM_TC,
            COUNT(*) OVER (PARTITION BY k.PROGRAM_CODE, k.CT_SEASON, k.QH_NUM) - 1) AS NORM_TC,
        LAG(k.DEMO) OVER (PARTITION BY k.PROGRAM_CODE, k.TELECAST_NUM
                        ORDER BY k.QH_NUM)                             AS PREV_AA,
        FIRST_VALUE(k.DEMO) OVER (PARTITION BY k.PROGRAM_CODE, k.TELECAST_NUM
                        ORDER BY k.QH_NUM
                        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS QH1_AA,
        LAST_VALUE(k.DEMO)  OVER (PARTITION BY k.PROGRAM_CODE, k.TELECAST_NUM
                        ORDER BY k.QH_NUM
                        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LAST_AA
    FROM kept k
    LEFT JOIN tp_norm t ON t.QH_NUM = k.QH_NUM
),
normed_mv AS (
    -- [QH-NORMMOVE] the norm's own movement, position to position, so the
    -- series' QH1 -> QH4 drift can be read against the norm's QH1 -> QH4 drift
    -- (A&E review 27 Sep 2026, template #15: "compare series movement vs norm").
    SELECT n.*,
        LAG(n.NORM_AA) OVER (PARTITION BY n.PROGRAM_CODE, n.TELECAST_NUM
                        ORDER BY n.QH_NUM)                              AS NORM_PREV_AA,
        FIRST_VALUE(n.NORM_AA) OVER (PARTITION BY n.PROGRAM_CODE, n.TELECAST_NUM
                        ORDER BY n.QH_NUM
                        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS NORM_QH1_AA,
        LAST_VALUE(n.NORM_AA)  OVER (PARTITION BY n.PROGRAM_CODE, n.TELECAST_NUM
                        ORDER BY n.QH_NUM
                        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS NORM_LAST_AA
    FROM normed n
),
season_qh AS (
    SELECT NETWORK_CODE, PROGRAM_NAME, CT_SEASON, QH_NUM,
           SUM(DEMO * QH_MIN)    / NULLIF(SUM(QH_MIN), 0)  AS QH_AA,
           SUM(NORM_AA * QH_MIN) / NULLIF(SUM(QH_MIN), 0)  AS QH_NORM,
           MAX(NORM_TC)                                    AS QH_NORM_TC,
           SUM(QH_MIN)                                     AS QH_MIN,
           COUNT(*)                                        AS TELECASTS
    FROM normed_mv
    WHERE $p_rollup
    GROUP BY NETWORK_CODE, PROGRAM_NAME, CT_SEASON, QH_NUM
),
rolled AS (
    SELECT s.*,
           LAG(QH_AA) OVER (PARTITION BY NETWORK_CODE, PROGRAM_NAME, CT_SEASON ORDER BY QH_NUM) AS PREV_AA,
           FIRST_VALUE(QH_AA) OVER (PARTITION BY NETWORK_CODE, PROGRAM_NAME, CT_SEASON ORDER BY QH_NUM)  AS QH1_AA,
           LAST_VALUE(QH_AA)  OVER (PARTITION BY NETWORK_CODE, PROGRAM_NAME, CT_SEASON ORDER BY QH_NUM
                                    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LAST_AA,
           LAG(QH_NORM) OVER (PARTITION BY NETWORK_CODE, PROGRAM_NAME, CT_SEASON ORDER BY QH_NUM) AS NORM_PREV_AA,
           FIRST_VALUE(QH_NORM) OVER (PARTITION BY NETWORK_CODE, PROGRAM_NAME, CT_SEASON ORDER BY QH_NUM) AS NORM_QH1_AA,
           LAST_VALUE(QH_NORM)  OVER (PARTITION BY NETWORK_CODE, PROGRAM_NAME, CT_SEASON ORDER BY QH_NUM
                                    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS NORM_LAST_AA
    FROM season_qh s
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    NETWORK_CODE   AS NETWORK,
    BROADCAST_DATE AS AIR_DATE,
    PROGRAM_NAME   AS PROGRAM,
    EPISODE_NAME   AS EPISODE,
    CT_SEASON     AS SEASON,
    'QH' || QH_NUM AS QUARTER_HOUR,
    QTR_START_TIME AS QH_START,
    QH_MIN,
    ROUND(DEMO/1000, 0)                                            AS AA_000,
    -- [Q4]
    CASE WHEN PREV_AA IS NOT NULL
         THEN ROUND((ROUND(DEMO/1000,0)/NULLIF(ROUND(PREV_AA/1000,0),0)-1)*100, 1) END
                                                                   AS VS_PRIOR_QH_PCT,
    ROUND(NORM_AA/1000, 0)                                         AS NORM_AA_000,
    NORM_TC,
    ROUND((ROUND(DEMO/1000,0)/NULLIF(ROUND(NORM_AA/1000,0),0)-1)*100, 1) AS VS_NORM_PCT,
    -- [Q5]
    ROUND((ROUND(LAST_AA/1000,0)/NULLIF(ROUND(QH1_AA/1000,0),0)-1)*100, 1) AS LAST_VS_FIRST_PCT,
    -- [QH-NORMMOVE] the norm's own movement on the same two measures
    CASE WHEN NORM_PREV_AA IS NOT NULL
         THEN ROUND((ROUND(NORM_AA/1000,0)/NULLIF(ROUND(NORM_PREV_AA/1000,0),0)-1)*100, 1) END
                                                                   AS NORM_VS_PRIOR_QH_PCT,
    ROUND((ROUND(NORM_LAST_AA/1000,0)/NULLIF(ROUND(NORM_QH1_AA/1000,0),0)-1)*100, 1) AS NORM_LAST_VS_FIRST_PCT,
    $win_to                 AS TO_DATE
FROM normed_mv
WHERE NOT $p_rollup
UNION ALL
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,
    NETWORK_CODE   AS NETWORK,
    NULL           AS AIR_DATE,
    PROGRAM_NAME   AS PROGRAM,
    'SEASON AVERAGE ' || TELECASTS || ' TELECASTS' AS EPISODE,
    CT_SEASON      AS SEASON,
    'QH' || QH_NUM AS QUARTER_HOUR,
    NULL           AS QH_START,
    QH_MIN,
    ROUND(QH_AA/1000, 0)                                           AS AA_000,
    CASE WHEN PREV_AA IS NOT NULL
         THEN ROUND((ROUND(QH_AA/1000,0)/NULLIF(ROUND(PREV_AA/1000,0),0)-1)*100, 1) END
                                                                   AS VS_PRIOR_QH_PCT,
    ROUND(QH_NORM/1000, 0)                                         AS NORM_AA_000,
    QH_NORM_TC                                                     AS NORM_TC,
    ROUND((ROUND(QH_AA/1000,0)/NULLIF(ROUND(QH_NORM/1000,0),0)-1)*100, 1) AS VS_NORM_PCT,
    ROUND((ROUND(LAST_AA/1000,0)/NULLIF(ROUND(QH1_AA/1000,0),0)-1)*100, 1) AS LAST_VS_FIRST_PCT,
    CASE WHEN NORM_PREV_AA IS NOT NULL
         THEN ROUND((ROUND(QH_NORM/1000,0)/NULLIF(ROUND(NORM_PREV_AA/1000,0),0)-1)*100, 1) END
                                                                   AS NORM_VS_PRIOR_QH_PCT,
    ROUND((ROUND(NORM_LAST_AA/1000,0)/NULLIF(ROUND(NORM_QH1_AA/1000,0),0)-1)*100, 1) AS NORM_LAST_VS_FIRST_PCT,
    $win_to                 AS TO_DATE
FROM rolled
ORDER BY 3 NULLS LAST, 7;