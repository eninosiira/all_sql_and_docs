/* ============================================================================
   FILE       2.9  NETWORK'S RANK WITHIN THE TIME PERIOD            (PRD 2.9)
   PURPOSE    How the series' network ranks against the cable landscape during
              the exact slots the series occupies.
   SOURCE     CRIS_HALFHR_FACT [S2-T1]. This is the query that requires the
              table to hold every network rather than the six.
   VALIDATION Same engine as 3.1, validated 1:1 in v6.
   METHOD     The series time period is the exact (date, half hour) slots its
              premieres occupied, so nights with no premiere drop out on their
              own and day-of-week and start time never need hardcoding. Those
              same slots are then applied to every competitor, and competitors
              are measured on ALL their programming in them: the metric is
              network delivery in the window, not premiere delivery.
   UNIVERSE   MEDIA_TYPE_CODE = 'NHI' keeps broadcast diginets out. The news and
              sports exclusion is by station code, the list A&E supplied over
              Teams in Jul-2026; stable IDs rather than network names.
              Resolved with Nielsen RDN in Jun-2026: MSNBC shares station code
              7801 with MS NOW, so legacy MSNBC rows go out too, which can move
              a rank by one against older validations. NewsNation's 6788 was
              WGN America until Feb-2021, so pre-2021 windows also drop WGN.
              'PV' is a data artifact found during 3.1 validation.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network       = 'HIST';
SET p_program       = '%SECRET SKINWALKER RANCH%';
SET p_stream        = 'Live+SD';
SET p_slot_min_min  = 15;       -- [SLOT] a half hour belongs to the series' time
                                -- period only if the series contributed at least
                                -- this many minutes to it. Same rule as 3.1.
                                -- Jill, 24 Sep 2026: rank right, every figure
                                -- wrong. Skinwalker runs 9:00 to 10:03, and the
                                -- three minutes pulled the whole 10:00 half hour
                                -- into the period for every network. HIST read
                                -- 287 over three half hours; the period is two.
SET p_demo      = 'P25_64_AA_ESTIMATES';
SET p_excl_by       = 'CODE';      -- [S2-UNIVERSE] the same switch 3.1 uses.
                                   -- 'CODE' = A&E's eighteen station codes, sent
                                   -- over Teams Jul-2026. 'NAME' = the eighteen
                                   -- network names the PRD lists in its 3.1.
                                   -- They are not the same set and A&E has not
                                   -- ruled: HLN, CNNH, ESPNN and NBATV are absent
                                   -- from the code list and so stay IN. The check
                                   -- at the end of [S3-T0] prints every network
                                   -- where the two disagree.
SET p_season        = NULL;
SET p_win_from      = NULL;
SET p_win_to        = NULL;
SET data_sun = (SELECT MAX(LATEST_FULL_SUNDAY) FROM AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE
                   WHERE NETWORK_CODE = $p_network AND RATING_SOURCE = $p_stream);
-- [CAP-SUN] the window can never run past the latest full Sunday with data, even when a
-- later date is passed in (A&E review, 27 Sep 2026: TO_DATE showed a date with no data yet).
SET win_to   = (SELECT LEAST(COALESCE(TO_DATE($p_win_to), $data_sun), $data_sun));
-- [S2-SEASONWIN] A&E, 22 Sep 2026: this rank is measured over the dates the
-- SERIES ran, not a trailing year. "This one should be based on the dates of
-- the season, May 19th to August 18th." With no explicit window the season's
-- own first and last broadcast dates are used, and both come back in
-- WINDOW_FROM and WINDOW_TO so the range behind the rank is visible.
--
-- The season is resolved FIRST, the same way every Section 2 query does it:
-- the programme's most recent season unless p_season pins one. v60 took a MIN
-- over every season the programme ever had, so the window opened in 2024.
SET tp_program_code = (SELECT PROGRAM_CODE
                       FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT
                       WHERE ($p_network IS NULL OR NETWORK_CODE = $p_network)
                      AND RATING_SOURCE = $p_stream
                      AND IS_FIRST_RUN_CT
                      AND ($p_program IS NULL OR PROGRAM_NAME ILIKE $p_program)
                      AND CT_SEASON IS NOT NULL
                      AND BROADCAST_DATE <= $win_to
                       ORDER BY BROADCAST_DATE DESC, TELECAST_NUM DESC LIMIT 1);
SET tp_season = (SELECT COALESCE($p_season, CT_SEASON)
                 FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT
                 WHERE ($p_network IS NULL OR NETWORK_CODE = $p_network)
                      AND RATING_SOURCE = $p_stream
                      AND IS_FIRST_RUN_CT
                      AND ($p_program IS NULL OR PROGRAM_NAME ILIKE $p_program)
                      AND CT_SEASON IS NOT NULL
                      AND BROADCAST_DATE <= $win_to
                   AND PROGRAM_CODE = $tp_program_code
                 ORDER BY BROADCAST_DATE DESC, TELECAST_NUM DESC LIMIT 1);
SET season_from = (SELECT MIN(BROADCAST_DATE)
                   FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT
                   WHERE ($p_network IS NULL OR NETWORK_CODE = $p_network)
                      AND RATING_SOURCE = $p_stream
                      AND IS_FIRST_RUN_CT
                      AND ($p_program IS NULL OR PROGRAM_NAME ILIKE $p_program)
                      AND CT_SEASON IS NOT NULL
                      AND BROADCAST_DATE <= $win_to
                     AND PROGRAM_CODE = $tp_program_code
                     AND CT_SEASON    = $tp_season);
SET season_to   = (SELECT MAX(BROADCAST_DATE)
                   FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT
                   WHERE ($p_network IS NULL OR NETWORK_CODE = $p_network)
                      AND RATING_SOURCE = $p_stream
                      AND IS_FIRST_RUN_CT
                      AND ($p_program IS NULL OR PROGRAM_NAME ILIKE $p_program)
                      AND CT_SEASON IS NOT NULL
                      AND BROADCAST_DATE <= $win_to
                     AND PROGRAM_CODE = $tp_program_code
                     AND CT_SEASON    = $tp_season);
SET win_from = (SELECT COALESCE(TO_DATE($p_win_from), $season_from,
                  DATEADD('day', 1, DATEADD('month', -12, $win_to))));
SET win_to   = (SELECT LEAST(COALESCE(TO_DATE($p_win_to), $season_to, $win_to), $data_sun));


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

WITH slots AS (
    -- the exact (date, half hour) the series' premieres occupied
    SELECT BROADCAST_DATE, HALFHR_START_TIME, HH_START_2959
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_HALFHR_FACT
    WHERE NETWORK_CODE  = $p_network
      AND RATING_SOURCE = $p_stream
      AND IS_FIRST_RUN_CT
      AND PROGRAM_NAME ILIKE $p_program
      AND ($p_season IS NULL OR CT_SEASON = $p_season)
      AND BROADCAST_DATE BETWEEN $win_from AND $win_to
    GROUP BY BROADCAST_DATE, HALFHR_START_TIME, HH_START_2959
    HAVING ($p_slot_min_min IS NULL OR SUM(HH_MIN) >= $p_slot_min_min)
),
competitive AS (
    SELECT h.NETWORK_CODE,
           COUNT(DISTINCT h.BROADCAST_DATE)                 AS N_DATES,
           COUNT(*)                                         AS N_HALFHRS,
           SUM(h.HH_MIN)                                    AS MINUTES,
           SUM(IDENTIFIER($p_demo) * h.HH_MIN)
             / NULLIF(SUM(h.HH_MIN), 0) / 1000              AS DEMO_AA_000
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_HALFHR_FACT h
    JOIN slots s
      ON  s.BROADCAST_DATE   = h.BROADCAST_DATE
      AND s.HALFHR_START_TIME = h.HALFHR_START_TIME
    -- [S2-UNIVERSE] the shared universe table, not a copy of the list.
    -- This query carried its own eighteen ORIGINATOR_ID literals, its own
    -- MEDIA_TYPE_CODE test and its own 'PV' exception. [S3-T0] was built to
    -- remove exactly that: its own header says the universe "is currently
    -- written out inside 2.9 and would be written out again in all four queries
    -- here", which is why the table exists. 3.1 was migrated onto it and 2.9
    -- was not, so two questions that rank the same networks over the same half
    -- hours could disagree, and only one of them carried the 'PV' artifact fix
    -- found during the 3.1 validation.
    --
    -- Migrating also brings the second reading with it. The literal list was the
    -- station codes only; IS_ENT_BY_NAME holds the PRD's names, and p_excl_by
    -- switches between them without editing SQL.
    JOIN AUDIENCE_DEV_DB.CRIS.CRIS_NETWORK_UNIVERSE u
      ON u.NETWORK_CODE = h.NETWORK_CODE
    WHERE h.RATING_SOURCE = $p_stream
      AND NOT u.IS_ARTIFACT
      AND ( ($p_excl_by = 'CODE' AND u.IS_ENT_BY_CODE)
         OR ($p_excl_by = 'NAME' AND u.IS_ENT_BY_NAME) )
    GROUP BY h.NETWORK_CODE
),
ranked AS (
    SELECT RANK() OVER (ORDER BY ROUND(DEMO_AA_000, 0) DESC) AS RNK,
           NETWORK_CODE, N_DATES, N_HALFHRS, MINUTES,
           ROUND(DEMO_AA_000, 0) AS AA_000,
           COUNT(*) OVER ()      AS UNIVERSE_SIZE
    FROM competitive
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    RNK, UNIVERSE_SIZE, NETWORK_CODE AS NETWORK,
    N_DATES, N_HALFHRS, MINUTES, AA_000,
    IFF(NETWORK_CODE = $p_network, 1, 0)                     AS IS_TARGET,
    IFF(NETWORK_CODE = $p_network, '<<< the series network', NULL) AS MARKER,
    (SELECT COUNT(*) FROM slots)     AS SLOTS_IN_PERIOD,
    (SELECT MIN(BROADCAST_DATE) FROM slots) AS PERIOD_FROM,
    (SELECT MAX(BROADCAST_DATE) FROM slots) AS PERIOD_TO,
    $p_excl_by                              AS EXCLUSION_LIST,
    $win_from               AS FROM_DATE,
    $win_to                 AS TO_DATE
FROM ranked
ORDER BY RNK;