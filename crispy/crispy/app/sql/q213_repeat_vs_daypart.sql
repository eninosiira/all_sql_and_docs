/* ============================================================================
   FILE       2.13 REPEAT AVERAGE VS. DAYPART                       (PRD 2.13)
   PURPOSE    The series' repeat telecasts against the daypart they actually
              aired in, to show whether repeats help or hurt that daypart.
   SOURCE     CRIS_HALFHR_FACT [S2-T1]
   RULES      [D1] the daypart comes from where the repeats actually aired. A
                  series repeating in two dayparts gets a row for each.
              [D2] the daypart average is the network's daypart, same window,
                  demo and stream, duration weighted. [S2-DPNORM] repeats only
                  by default (Jill's 128); p_norm_basis = 'ALL' adds premieres.
   [S1-DP]    Dayparts are clock boundaries from A&E's own report headers, not
              the REPORTED_DAYPART label v6 used. Prime is M-Su 8-11p and Total
              Day is 6a-6a; the full grid is still outstanding, which is why the
              boundaries live in one CTE that takes one row per daypart.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network       = 'HIST';
SET p_program       = '%SECRET SKINWALKER RANCH%';
SET p_stream        = 'Live+SD';
SET p_demo      = 'DEMO_AA';
SET p_norm_basis    = 'REPEATS';  -- [S2-DPNORM] what the daypart average is built on.
                                  -- 'REPEATS' = every repeat half hour on the network in the
                                  -- daypart, which reproduces Jill's 128 for HIST M-SU 8P-12A
                                  -- (diagnostic of 27 Sep 2026; all programming gives 164).
                                  -- 'ALL' = premieres and repeats, what v73 and earlier did.
SET p_win_from      = NULL;
SET p_win_to        = NULL;
SET data_sun = (SELECT MAX(LATEST_FULL_SUNDAY) FROM AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE
                   WHERE NETWORK_CODE = $p_network AND RATING_SOURCE = $p_stream);
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

WITH daypart AS (
    -- [S2-DP] A&E's repeat-analysis grid, Kristen 9 Sep 2026. These dayparts are
    -- for this question only: prime is a different daypart elsewhere. Upper
    -- bound exclusive. 2400 is midnight, 2960 the end of the broadcast day.
              SELECT 1 AS ORD, 'M-SU 8P-12A'   AS DAYPART, 2000 AS FROM_2959, 2400 AS TO_2959, 'ALL' AS DOW
    UNION ALL SELECT 2,        'M-SU 12A-6A',              2400,               2960,            'ALL'
    UNION ALL SELECT 3,        'M-F 6A-12P',                600,               1200,            'WEEKDAY'
    UNION ALL SELECT 4,        'M-F 12P-4P',               1200,               1600,            'WEEKDAY'
    UNION ALL SELECT 5,        'M-F 4P-8P',                1600,               2000,            'WEEKDAY'
    UNION ALL SELECT 6,        'SAT-SUN 6A-12P',            600,               1200,            'WEEKEND'
    UNION ALL SELECT 7,        'SAT-SUN 12P-4P',           1200,               1600,            'WEEKEND'
    UNION ALL SELECT 8,        'SAT-SUN 4P-8P',            1600,               2000,            'WEEKEND'
),
hh AS (
    SELECT h.*, d.ORD, d.DAYPART, IDENTIFIER($p_demo) AS DEMO
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_HALFHR_FACT h
    JOIN daypart d
      ON h.HH_START_2959 >= d.FROM_2959 AND h.HH_START_2959 < d.TO_2959
      AND ( d.DOW = 'ALL'
         OR (d.DOW = 'WEEKDAY' AND DAYOFWEEKISO(h.BROADCAST_DATE) <= 5)
         OR (d.DOW = 'WEEKEND' AND DAYOFWEEKISO(h.BROADCAST_DATE) >= 6) )
    WHERE h.NETWORK_CODE  = $p_network
      AND h.RATING_SOURCE = $p_stream
      AND h.BROADCAST_DATE BETWEEN $win_from AND $win_to
),
repeats AS (
    -- [D1] only the dayparts the series' repeats actually landed in
    SELECT ORD, DAYPART,
           MAX(PROGRAM_NAME) AS PROGRAM_NAME,
           COUNT(DISTINCT TO_VARCHAR(PROGRAM_CODE)||'-'||TO_VARCHAR(TELECAST_NUM)) AS REPEAT_TCASTS,
           SUM(DEMO * HH_MIN) / NULLIF(SUM(HH_MIN), 0) AS REPEAT_AA,
           SUM(HH_MIN) AS REPEAT_MIN
    FROM hh
    WHERE NOT IS_FIRST_RUN_CT
      AND PROGRAM_NAME ILIKE $p_program
    GROUP BY ORD, DAYPART
),
dp_norm AS (
    -- [D2] the network's whole daypart, premieres and repeats
    SELECT ORD, DAYPART,
           SUM(DEMO * HH_MIN) / NULLIF(SUM(HH_MIN), 0) AS DAYPART_AA,
           SUM(HH_MIN) AS DAYPART_MIN,
           COUNT(*)    AS DAYPART_HALFHRS
    FROM hh
    WHERE $p_norm_basis = 'ALL' OR NOT IS_FIRST_RUN_CT   -- [S2-DPNORM]
    GROUP BY ORD, DAYPART
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    $p_network       AS NETWORK,
    r.PROGRAM_NAME   AS PROGRAM,
    r.DAYPART,
    r.REPEAT_TCASTS,
    ROUND(r.REPEAT_AA/1000, 0)                                 AS REPEAT_AA_000,
    ROUND(n.DAYPART_AA/1000, 0)                                AS DAYPART_AVG_000,
    ROUND(r.REPEAT_AA/1000,0) - ROUND(n.DAYPART_AA/1000,0)     AS DIFF_000,
    ROUND((ROUND(r.REPEAT_AA/1000,0)
           / NULLIF(ROUND(n.DAYPART_AA/1000,0),0) - 1) * 100, 1) AS PCT_VS_DAYPART,
    CASE WHEN ROUND(r.REPEAT_AA/1000,0) > ROUND(n.DAYPART_AA/1000,0) THEN 'LIFTS THE DAYPART'
         WHEN ROUND(r.REPEAT_AA/1000,0) < ROUND(n.DAYPART_AA/1000,0) THEN 'DRAGS THE DAYPART'
         ELSE 'IN LINE' END                                    AS VERDICT,
    n.DAYPART_HALFHRS,
    $p_norm_basis    AS DAYPART_NORM_BASIS,
    $win_from AS FROM_DATE, $win_to AS TO_DATE
FROM repeats r
JOIN dp_norm n ON n.ORD = r.ORD
ORDER BY r.ORD;