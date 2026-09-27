/* ============================================================================
   FILE       3.2  NETWORK RANKS                                    (PRD 3.2)
   PURPOSE    An A+E network against the cable landscape for a fiscal year, in
              both universes and both dayparts, with the aligned year-ago rank.
   SOURCE     CRIS_HALFHR_FACT [S2-T1], CRIS_NETWORK_UNIVERSE [S3-T0],
              CRIS_FY_CALENDAR [S3-T1]
   VALIDATION A&E benchmark R_6. HIST, FY26 through 5 Jul 2026, Live+SD, P25-64:
                Prime 8-11p      184, ent-cable rank 7 tied, prior 208 rank 7 tied
                Total Day 6a-6a   93, ent-cable rank 12,     prior 106 rank 10 tied
              Requires [S3-FYTO] = '2026-07-05'. Unpinned it runs to 9 Aug and
              returns 185 at rank 8 and 92 at rank 12, which is five extra weeks
              rather than a different method.
              Their prime duration is 50,400 minutes on every network - 280 days
              x 180 - the same construction that made SP_7's 44,100 checkable.
              R_2 is the same question on C3 and CANNOT run: [S3-C3] confirmed
              zero half-hour rows on ACM - Live+3. Their footer for it reads
              "Dayparts are ACM Program based and Commercial Duration weighted",
              which suggests A&E daypart C3 at PROGRAMME level rather than on half
              hours - a construction the total-program table could support. Open
              with A&E, with their own wording attached.
   [S3-ACM]   C3 is 'ACM - Live+3' and C7 is 'ACM - Live+7'. Those are the view's
              own labels: case when viewtype_name = 'C3' then 'ACM - Live+3'.
              Two things about the ACM streams are unresolved and both live here.
              First, ACM - Live+1 and ACM - Live+2 carry every telecast twice,
              6,558 keys against 13,116 rows, and the keys are not null. [S2-T1]
              collapses them and [S3-T9] confirms zero survive, but which copy is
              authoritative is unconfirmed. ACM - Live+3 and ACM - Live+7 do not
              show the pattern, which is why this query is runnable at all.
              Second, the weighting: ACM streams are weighted on COMMERCIAL
              minutes, not programme minutes, and v6 flagged that as the number
              one knob to validate. p_weight_col exposes it.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network       = 'HIST';
SET p_fiscal_year   = NULL;        -- NULL = the fiscal year the latest data falls in
SET p_fy_to         = NULL;   -- [S3-FYTO] where the fiscal year to date STOPS.
                              -- NULL = as far as the data reaches, which is the
                              -- right production default and the wrong benchmark
                              -- one.
                              --
                              -- 3.2 was the only query in the project with no
                              -- date bound at all. R_6 ran to 9 Aug against A&E's
                              -- 5 Jul and came back 185 at rank 8 instead of 184
                              -- at rank 7 - five extra weeks of data, not a
                              -- method difference. The prior-year window moves
                              -- with it, so the aligned comparison stays aligned.
SET p_stream        = 'Live+SD';   -- [S3-C3] C3. C7 = 'ACM - Live+7'; also
                                        -- 'Live+SD', 'Live+3'. RUN THE COVERAGE
                                        -- CELL ABOVE FIRST. C3 exists at Total
                                        -- Program level and NOT in the half-hour
                                        -- view, so a dayparted C3 rank is not
                                        -- computable from the data A&E holds.
                                        -- Confirmed twice: [D10] measured it, and
                                        -- Elias confirmed it to A&E in the week 10
                                        -- check-in. 'Live+SD' is the only stream
                                        -- that returns a complete answer today.
SET p_demo          = 'P25_64_AA_ESTIMATES';  -- LIF/LMN: F25_64_..., VICE: P18_49_...
SET p_weight_col    = 'HH_MIN';  -- [S3-ACM] 'HH_MIN' for programme weighting
SET p_excl_by       = 'CODE';
-- the fiscal year, and how far into it the data actually goes
-- [CAP-SUN] window end = latest full Sunday with data, read from CRIS_LATEST_DATE (no MAX over the fact table).
SET data_max = (SELECT MAX(LATEST_FULL_SUNDAY) FROM AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE
                WHERE RATING_SOURCE = $p_stream);
SET fy = (SELECT COALESCE($p_fiscal_year,
            (SELECT MAX(FISCAL_YEAR) FROM AUDIENCE_DEV_DB.CRIS.CRIS_FY_CALENDAR
             WHERE FY_START <= $data_max)));
SET fy_start   = (SELECT FY_START FROM AUDIENCE_DEV_DB.CRIS.CRIS_FY_CALENDAR WHERE FISCAL_YEAR = $fy);
SET fy_to      = (SELECT LEAST(COALESCE(TO_DATE($p_fy_to), $data_max), COALESCE(
                    (SELECT FY_END FROM AUDIENCE_DEV_DB.CRIS.CRIS_FY_CALENDAR WHERE FISCAL_YEAR = $fy),
                    $data_max)));
-- aligned year-ago: the same number of days into the prior fiscal year
SET pfy_start  = (SELECT PRIOR_FY_START FROM AUDIENCE_DEV_DB.CRIS.CRIS_FY_CALENDAR WHERE FISCAL_YEAR = $fy);
SET pfy_to     = (SELECT DATEADD('day', DATEDIFF('day', $fy_start, $fy_to), $pfy_start));


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

WITH dayparts AS (
              SELECT 1 AS ORD, 'PRIME M-SU 8P-11P' AS DAYPART, 2000 AS FROM_2959, 2300 AS TO_2959
    UNION ALL SELECT 2,         'TOTAL DAY 6A-6A',               600,               2960
),
periods AS (
              SELECT 'CURRENT'  AS PERIOD, $fy_start  AS D_FROM, $fy_to  AS D_TO
    UNION ALL SELECT 'YEAR AGO',           $pfy_start,           $pfy_to
),
measured AS (
    SELECT p.PERIOD, d.ORD, d.DAYPART, h.NETWORK_CODE,
           u.IS_CABLE, u.IS_ENT_BY_CODE, u.IS_ENT_BY_NAME,
           SUM(IDENTIFIER($p_demo    ) * COALESCE(IDENTIFIER($p_weight_col), h.HH_MIN))
             / NULLIF(SUM(COALESCE(IDENTIFIER($p_weight_col), h.HH_MIN)), 0) AS AA,
           SUM(h.HH_MIN) AS MINUTES
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_HALFHR_FACT h
    JOIN AUDIENCE_DEV_DB.CRIS.CRIS_NETWORK_UNIVERSE u
      ON u.NETWORK_CODE = h.NETWORK_CODE
    JOIN periods p
      ON h.BROADCAST_DATE BETWEEN p.D_FROM AND p.D_TO
    JOIN dayparts d
      ON h.HH_START_2959 >= d.FROM_2959 AND h.HH_START_2959 < d.TO_2959
    WHERE h.RATING_SOURCE = $p_stream
      AND u.IS_CABLE
      AND NOT u.IS_ARTIFACT
    GROUP BY p.PERIOD, d.ORD, d.DAYPART, h.NETWORK_CODE,
             u.IS_CABLE, u.IS_ENT_BY_CODE, u.IS_ENT_BY_NAME
),
ranked AS (
    -- the two universes are ranked separately, as the PRD requires. Ties share a
    -- rank, and the rank is taken on the rounded 000s that the answer displays.
    SELECT m.*,
        DENSE_RANK() OVER (PARTITION BY PERIOD, ORD
                     ORDER BY ROUND(AA/1000, 0) DESC)          AS RNK_ALL_CABLE,
        DENSE_RANK() OVER (PARTITION BY PERIOD, ORD,
                     IFF( ($p_excl_by = 'CODE' AND IS_ENT_BY_CODE)
                       OR ($p_excl_by = 'NAME' AND IS_ENT_BY_NAME), 1, 0)
                     ORDER BY ROUND(AA/1000, 0) DESC)          AS RNK_ENT_CABLE,
        -- [TIES] Jill, 24 Sep 2026: ties must be shown. A network is tied when
        -- another one in the same entertainment-cable set has the same rounded
        -- figure in the same period.
        COUNT(*) OVER (PARTITION BY PERIOD, ORD,
                     IFF( ($p_excl_by = 'CODE' AND IS_ENT_BY_CODE)
                       OR ($p_excl_by = 'NAME' AND IS_ENT_BY_NAME), 1, 0),
                     ROUND(AA/1000, 0)) > 1                    AS TIED_ENT_CABLE,
        COUNT(*) OVER (PARTITION BY PERIOD, ORD, ROUND(AA/1000, 0)) > 1 AS TIED_ALL_CABLE,
        COUNT(*) OVER (PARTITION BY PERIOD, ORD)               AS N_ALL_CABLE,
        -- [ENTDENOM] the entertainment-cable size, over the same partition as
        -- the rank it belongs to. It was missing: the query returned
        -- RNK_ENT_CABLE and then printed only N_ALL_CABLE, so "rank 7" arrived
        -- with no denominator and 7 of 100 read exactly like 7 of 119.
        COUNT_IF( ($p_excl_by = 'CODE' AND IS_ENT_BY_CODE)
               OR ($p_excl_by = 'NAME' AND IS_ENT_BY_NAME) )
            OVER (PARTITION BY PERIOD, ORD)                     AS N_ENT_CABLE
    FROM measured m
),
net AS (
    -- [ALLNETS] p_network NULL returns the whole ranker, every cable network in
    -- both dayparts. A single code returns that network's two rows, as before.
    -- [FULLUNIVERSE] A&E, 24 Sep 2026: even "where does History rank" returns
    -- every network, so the reader sees who is above and below. The asked
    -- network is marked in IS_TARGET; the written answer focuses on it.
    SELECT * FROM ranked
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    c.DAYPART,
    c.NETWORK_CODE                                             AS NETWORK,
    $fy                                                        AS FISCAL_YEAR,
    $fy_start AS FY_FROM, $fy_to AS FY_TO,
    $pfy_start AS PRIOR_FROM, $pfy_to AS PRIOR_TO,
    ROUND(c.AA/1000, 0)                                        AS AA_000,
    IFF($p_network IS NOT NULL AND c.NETWORK_CODE = $p_network, 1, 0) AS IS_TARGET,
    c.RNK_ALL_CABLE                                            AS RANK_ALL_CABLE,
    c.TIED_ALL_CABLE                                           AS TIED_ALL_CABLE,
    c.RNK_ALL_CABLE || IFF(c.TIED_ALL_CABLE, ' (tied)', '')    AS RANK_ALL_CABLE_LABEL,
    -- [ENTONLY] the entertainment-cable rank exists only for networks in that
    -- set. News and sports networks rank among all cable, never here: without
    -- this, ESPN read #1 among entertainment cable because DENSE_RANK restarts
    -- inside each group.
    IFF( ($p_excl_by = 'CODE' AND c.IS_ENT_BY_CODE)
      OR ($p_excl_by = 'NAME' AND c.IS_ENT_BY_NAME), TRUE, FALSE)  AS IS_ENT_CABLE,
    IFF( ($p_excl_by = 'CODE' AND c.IS_ENT_BY_CODE)
      OR ($p_excl_by = 'NAME' AND c.IS_ENT_BY_NAME), c.RNK_ENT_CABLE, NULL) AS RANK_ENT_CABLE,
    IFF( ($p_excl_by = 'CODE' AND c.IS_ENT_BY_CODE)
      OR ($p_excl_by = 'NAME' AND c.IS_ENT_BY_NAME), c.TIED_ENT_CABLE, NULL) AS TIED,
    IFF( ($p_excl_by = 'CODE' AND c.IS_ENT_BY_CODE)
      OR ($p_excl_by = 'NAME' AND c.IS_ENT_BY_NAME),
        c.RNK_ENT_CABLE || IFF(c.TIED_ENT_CABLE, ' (tied)', ''), NULL) AS RANK_ENT_CABLE_LABEL,
    ROUND(y.AA/1000, 0)                                        AS AA_000_YEAR_AGO,
    y.RNK_ALL_CABLE                                            AS RANK_ALL_CABLE_YEAR_AGO,
    y.RNK_ALL_CABLE || IFF(y.TIED_ALL_CABLE, ' (tied)', '')    AS RANK_ALL_CABLE_YEAR_AGO_LABEL,
    IFF( ($p_excl_by = 'CODE' AND y.IS_ENT_BY_CODE)
      OR ($p_excl_by = 'NAME' AND y.IS_ENT_BY_NAME), y.RNK_ENT_CABLE, NULL) AS RANK_ENT_CABLE_YEAR_AGO,
    IFF( ($p_excl_by = 'CODE' AND y.IS_ENT_BY_CODE)
      OR ($p_excl_by = 'NAME' AND y.IS_ENT_BY_NAME),
        y.RNK_ENT_CABLE || IFF(y.TIED_ENT_CABLE, ' (tied)', ''), NULL) AS RANK_ENT_CABLE_YEAR_AGO_LABEL,
    ROUND((ROUND(c.AA/1000,0)
           / NULLIF(ROUND(y.AA/1000,0),0) - 1) * 100, 1)       AS PCT_VS_YEAR_AGO,
    c.N_ALL_CABLE                                              AS UNIVERSE_ALL_CABLE,
    c.N_ENT_CABLE                                              AS UNIVERSE_ENT_CABLE,   -- [ENTDENOM]
    $p_stream AS STREAM, $p_demo     AS DEMO,
    $p_weight_col AS WEIGHTED_ON, $p_excl_by AS EXCLUSION_LIST,
    $fy_to                  AS TO_DATE
FROM net c
LEFT JOIN net y ON y.NETWORK_CODE = c.NETWORK_CODE
               AND y.ORD = c.ORD AND y.PERIOD = 'YEAR AGO'
WHERE c.PERIOD = 'CURRENT'
ORDER BY c.ORD, c.RNK_ALL_CABLE, c.NETWORK_CODE;