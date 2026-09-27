/* ============================================================================
   FILE       1.3  LIFETIME MOVIE LEAD-IN RETENTION - NORM (aggregated)
   PURPOSE    One row per Premiere type x Lead-in type x Lead-in airing x Holiday.
              Retention norm = Avg Premiere AA / Avg Lead-in AA.
   SOURCE     AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT   [S1-T1]
              window from AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE   [S1-T0]
   VALIDATION LIF, Live+SD, defaults. Compare against
              "CRIS Life Movie Lead-In Example.xlsx", sheets
              "Past 12 Retention Norm-ORIG" and "-ACQ".
              Retention is Avg(premiere) / Avg(lead-in), not the average of the
              per-night ratios; A&E's own sheets compute it that way.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network      = 'LIF';
SET p_rating_src   = 'Live+SD';
SET p_demo         = 'F25_64_AA_ESTIMATES';   -- [S1-DEMO] W25-64. This query pins
                                   -- its demo rather than taking DEMO_AA: it is the
                                   -- Lifetime movie norm and it should read the same
                                   -- whichever network it is pointed at.
SET eff_demo = (SELECT COALESCE($p_demo, 'DEMO_AA'));
SET p_prem_start   = '20:00:00';   -- premiere start time; NULL = any time
SET p_leadin_start = '18:00:00';   -- lead-in start (6P-8P repeat); NULL = adjacency only
SET p_min_dur      = 15;           -- shorts cutoff in minutes; NULL = no cutoff
SET p_gate_by_day  = TRUE;         -- TRUE = require Sat (orig) / Sun (acq)
SET p_movie_type_col = 'MOVIE_TYPE';  -- 'MOVIE_TYPE_EXT' to include THEATRICAL etc.
-- [NORM12] the latest 12 months, ending on the most recent Sunday with data.
-- A&E, 10 Sep 2026. Season norms stay season-based; this is a network norm.
SET win_to_d   = (SELECT LATEST_FULL_SUNDAY FROM AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE
                  WHERE NETWORK_CODE = $p_network AND RATING_SOURCE = $p_rating_src);
SET win_from_d = (SELECT DATEADD('day', 1, DATEADD('month', -12, $win_to_d)));
SET orig_from  = $win_from_d;  SET orig_to = $win_to_d;
SET acq_from   = $orig_from;   SET acq_to  = $orig_to;


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
    SELECT
        PROGRAM_NAME, BROADCAST_DATE, DAY_OF_WEEK,
        IS_FIRST_RUN_CT, START_TIME, END_TIME,
        CONTRIBUTING_DURATION AS CONTRIB_DUR,
        IDENTIFIER($eff_demo)         AS DEMO_AA,        -- [S1-DEMO]
        IDENTIFIER($p_movie_type_col) AS MOVIE_TYPE,     -- configurable rule
        IS_HOLIDAY
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT
    -- the two program-level indicators and the dedup are applied in [S1-T1]
    WHERE MOVIE_IND = 1
      AND ($p_network    IS NULL OR NETWORK_CODE  = $p_network)
      AND ($p_rating_src IS NULL OR RATING_SOURCE = $p_rating_src)
),
pairs AS (
    SELECT
        p.MOVIE_TYPE AS PREM_TYPE,
        l.MOVIE_TYPE AS LEADIN_TYPE,
        -- the dimension A&E asked for in week 1 section 4C and confirmed in week
        -- 2 section 4D: report the lead-in's premiere/repeat status, do not
        -- filter on it. A&E's own lead-in workbooks split the norm exactly this
        -- way, so the dimension is theirs rather than an invention here.
        IFF(NOT l.IS_FIRST_RUN_CT, 'REPEAT', 'PREMIERE') AS LEADIN_AIRING,
        p.IS_HOLIDAY,
        p.DEMO_AA AS PREM_AA, l.DEMO_AA AS LEADIN_AA,
        p.CONTRIB_DUR AS PREM_W, l.CONTRIB_DUR AS LEADIN_W
    FROM base p
    JOIN base l
      ON  l.BROADCAST_DATE = p.BROADCAST_DATE
      AND l.END_TIME       = p.START_TIME               -- adjacency, always on
      AND l.MOVIE_TYPE IS NOT NULL
      AND ($p_leadin_start IS NULL OR l.START_TIME  = $p_leadin_start)
      AND ($p_min_dur      IS NULL OR l.CONTRIB_DUR >= $p_min_dur)
    WHERE p.IS_FIRST_RUN_CT
      AND p.MOVIE_TYPE IN ('ORIGINAL','ACQUIRED')
      AND ($p_prem_start IS NULL OR p.START_TIME = $p_prem_start)
      AND (   (p.MOVIE_TYPE = 'ORIGINAL'
                AND ($p_gate_by_day = FALSE OR p.DAY_OF_WEEK = 'Saturday')
                AND p.BROADCAST_DATE >= $orig_from AND p.BROADCAST_DATE <= $orig_to)
           OR (p.MOVIE_TYPE = 'ACQUIRED'
                AND ($p_gate_by_day = FALSE OR p.DAY_OF_WEEK = 'Sunday')
                AND p.BROADCAST_DATE >= $acq_from  AND p.BROADCAST_DATE <= $acq_to) )
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    PREM_TYPE, LEADIN_TYPE, LEADIN_AIRING, IS_HOLIDAY,
    COUNT(*)                                          AS TC,
    ROUND((SUM(LEADIN_AA * LEADIN_W) / NULLIF(SUM(LEADIN_W), 0))/1000,0)                      AS LEADIN_000,
    ROUND((SUM(PREM_AA * PREM_W) / NULLIF(SUM(PREM_W), 0))/1000,0)                        AS PREM_000,
    ROUND(ROUND((SUM(PREM_AA * PREM_W) / NULLIF(SUM(PREM_W), 0))/1000,0)
          / NULLIF(ROUND((SUM(LEADIN_AA * LEADIN_W) / NULLIF(SUM(LEADIN_W), 0))/1000,0),0), 4) AS RETENTION_NORM,
    $win_from_d             AS FROM_DATE,
    $win_to_d               AS TO_DATE
FROM pairs
GROUP BY PREM_TYPE, LEADIN_TYPE, LEADIN_AIRING, IS_HOLIDAY
ORDER BY PREM_TYPE, LEADIN_TYPE, LEADIN_AIRING, IS_HOLIDAY;