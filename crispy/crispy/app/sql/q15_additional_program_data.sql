/* ============================================================================
   FILE       1.5  ADDITIONAL PROGRAM DATA                 (PRD, after Table 3)
   PURPOSE    For each programme in scope, its most recent season telecast by
              telecast, with episode name, air date, time, delivery and
              duration, plus the season average.
   SOURCE     AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT   [S1-T1]
              dates from AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE   [S1-T0]
   VALIDATION AEN, Live+SD, p_program = '%ALASKA STATE TROOPERS%'
              (Answers to Sample Questions.xlsx, sheet SP_3)
                SEASON AVERAGE   10 TCs   224   duration 600
                901 SUMMER SOLSTICE            242
                902 WILD AND DANGEROUS         212
                903 LOST IN THE WOODS          117
                906 MAKE YOURSELF KNOWN        251
                904 NO WAY OUT                 209
                905 ON THE RUN                 240
                908 COLD TRUTH AND CONSEQ      272
                907 ONE BAD DECISION           262
                909 WINTER IS COMING           164
                910 SHOTS IN THE SNOW          274
              The average is on the raw estimates, rounded once: 2,243 / 10 =
              224.3 -> 224. Averaging the printed values gives the same answer
              here, which is why this case cannot distinguish the two; 1.1's
              FTBA case can, and does.
              Note the episodes air out of numeric order, 906 before 904. Order
              is by air date, never by episode name.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network          = 'AEN';
SET p_rating_src       = 'Live+SD';
SET p_target_date      = NULL;     -- NULL = latest night with data
SET p_program          = NULL;     -- NULL = whatever premiered on the target
                                   -- night; a LIKE pattern pins one programme
                                   -- and ignores the night
SET p_season           = NULL;     -- [S1-SEASON] NULL = the programme's most
                                   -- recent season. A value pins one, e.g. '8'
                                   -- or '13B'; sub-seasons are separate.
                                   --
                                   -- Only meaningful alongside p_program. A
                                   -- season number exists inside a programme,
                                   -- not across the schedule: 'season 8' on its
                                   -- own is not a scope, it is season 8 of
                                   -- whatever happens to have one. Set without
                                   -- p_program it would silently drop every
                                   -- programme whose current season is labelled
                                   -- differently, so it is ignored instead and
                                   -- SEASON_PIN_IGNORED says so on every row.
SET p_demo = NULL;                 -- [S1-DEMO] NULL = DEMO_AA, the network's own
                                   -- default, which is what every validated figure
                                   -- was measured in. Otherwise name any AA column
                                   -- the source view carries, e.g.
                                   -- 'P18_49_AA_ESTIMATES', 'F25_64_AA_ESTIMATES',
                                   -- 'M25_54_AA_ESTIMATES'. Nothing is composed or
                                   -- summed: the name is the column.
SET eff_demo = (SELECT COALESCE($p_demo, 'DEMO_AA'));
SET p_include_specials = TRUE;
SET p_win_start_2959   = 2000;     -- [S1-WIN] 8:00p, applies only to the
SET p_win_end_2959     = 2400;     -- overnight path, see 1.1
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
scoped AS (
    SELECT
        NETWORK_CODE, PROGRAM_CODE, TELECAST_NUM,
        PROGRAM_NAME, EPISODE_NAME, CT_SEASON,
        BROADCAST_DATE, DAY_OF_WEEK, START_TIME, BCAST_START_2959,
        CONTRIBUTING_DURATION, CONTENT_TYPE,
        IDENTIFIER($eff_demo) AS DEMO
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT
    WHERE ($p_network    IS NULL OR NETWORK_CODE  = $p_network)
      AND ($p_rating_src IS NULL OR RATING_SOURCE = $p_rating_src)
      AND IS_FIRST_RUN_CT
      AND BROADCAST_DATE <= $eff_target
      AND ($p_include_specials OR CONTENT_TYPE <> 'Special')
),
target AS (
    -- One rule for both ways in: the season of the programme's most recent
    -- premiere at or before the target date. With p_program left NULL the scope
    -- is the night's premieres, and that most recent telecast IS the night's,
    -- so the two paths agree by construction rather than by a second branch.
    SELECT f2.NETWORK_CODE, f2.PROGRAM_CODE, f2.CT_SEASON
    FROM scoped f2
    -- every reference qualified, see 1.2
    WHERE ( $p_program IS NULL
            AND f2.BROADCAST_DATE = $eff_target
            AND ($p_win_start_2959 IS NULL OR f2.BCAST_START_2959 >= $p_win_start_2959)
            AND ($p_win_end_2959   IS NULL OR f2.BCAST_START_2959 <  $p_win_end_2959) )
       OR ( $p_program IS NOT NULL AND f2.PROGRAM_NAME ILIKE $p_program )
    -- [S1-SEASON] the SEASON AVERAGE row is a season calculation, so a
    -- programme with no season is not reported at all rather than reported
    -- against an approximation
    AND f2.CT_SEASON IS NOT NULL        -- [S1-SEASON] see 1.1
    -- [S1-SEASON] the pin only applies when a programme was named. See the
    -- parameter note: on its own it is not a scope.
    AND ($p_season IS NULL OR $p_program IS NULL OR f2.CT_SEASON = $p_season)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY f2.NETWORK_CODE, f2.PROGRAM_CODE
                               ORDER BY f2.BROADCAST_DATE DESC,
                                        f2.TELECAST_NUM DESC) = 1
),
season AS (
    -- [S1-NORMKEY] no NORM_KEY column. It used to carry the target's season so
    -- the three-tier rule could scope a pool whose own CT_SEASON differed. With
    -- the tiers gone the join is an equality, so NORM_KEY and CT_SEASON are the
    -- same value under two names, and a second name for one thing is what made
    -- the UNION below fall out of step.
    SELECT s.*
    FROM scoped s
    JOIN target t
      ON  t.NETWORK_CODE = s.NETWORK_CODE
      AND t.PROGRAM_CODE = s.PROGRAM_CODE            -- [S1-KEY]
      AND s.CT_SEASON = t.CT_SEASON
),
rolled AS (
    SELECT
        NETWORK_CODE, PROGRAM_CODE, PROGRAM_NAME,
        CT_SEASON,
        COUNT(*)               AS TCASTS,
        SUM(DEMO * CONTRIBUTING_DURATION) / NULLIF(SUM(CONTRIBUTING_DURATION), 0) AS DEMO_AVG,  -- [WAVG] duration weighted, Adarsh 11 Sep 2026: every aggregation.
        SUM(CONTRIBUTING_DURATION) AS TOTAL_DURATION,
        MIN(BROADCAST_DATE)    AS SEASON_FROM,
        MAX(BROADCAST_DATE)    AS SEASON_TO
    FROM season
    GROUP BY NETWORK_CODE, PROGRAM_CODE, PROGRAM_NAME, CT_SEASON
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED] in both branches
    NETWORK_CODE          AS NETWORK,
    PROGRAM_NAME          AS PROGRAM,
    CT_SEASON             AS SEASON,
    -- [S1-SEASON] a pin given without a programme was ignored, and the answer
    -- has to say so rather than look as though it was honoured
    IFF($p_season IS NOT NULL AND $p_program IS NULL,
        'SEASON PIN IGNORED: needs a programme', NULL) AS SEASON_PIN_IGNORED,
    0                     AS SORT_ORD,
    'SEASON AVERAGE'      AS EPISODE,
    SEASON_FROM           AS AIR_DATE,
    SEASON_TO             AS SEASON_THROUGH,
    NULL                  AS DAY,
    NULL                  AS START_TIME,
    TCASTS,
    ROUND(DEMO_AVG/1000,0) AS AA_000,
    TOTAL_DURATION        AS DURATION,
    $eff_target             AS TO_DATE
FROM rolled
UNION ALL
-- both branches carry the same thirteen columns in the same order
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    NETWORK_CODE, PROGRAM_NAME, CT_SEASON,
    IFF($p_season IS NOT NULL AND $p_program IS NULL,
        'SEASON PIN IGNORED: needs a programme', NULL),
    1, EPISODE_NAME,
    BROADCAST_DATE, NULL, DAY_OF_WEEK, START_TIME,
    1,
    ROUND(DEMO/1000,0),
    CONTRIBUTING_DURATION,
    $eff_target             AS TO_DATE
FROM season
-- air date, never episode name: A&E's own season list runs 903, 906, 904, 905
ORDER BY PROGRAM, SORT_ORD, AIR_DATE;