/* ============================================================================
   FILE       3.1  SERIES RANK BASED ON NETWORK TIME PERIOD RANKS   (PRD 3.1)
   PURPOSE    Where the series' NETWORK ranks against entertainment cable during
              the exact slots the series occupies. The series is not ranked
              against other series; it is ranked through its network.
   SOURCE     CRIS_HALFHR_FACT [S2-T1], CRIS_NETWORK_UNIVERSE [S3-T0]
   VALIDATION A&E benchmark R_3. AEN, Interrogation Raw, 2026-07-02, one night,
              their section is "Program Based Dayparts, THU 9P-10P".
                RANKS reproduce exactly on P25-64, first run:
                  TBSC #1, AEN #2, FOOD #3, OXYG #4, BET #5
                AAs need [S3-SLOTMIN] = 15. Without it the period is 90 minutes
                over three slots instead of their 60 over two, because the
                telecast ends at 10:01p and one minute lands in the next half
                hour. That diluted every network equally, which is why the ranks
                held: AEN 243 against their 258, TBSC 462 against 475.
              A&E print BOTH demos on this sheet, which settles [S3-DEMO]: it is
              a parameter of the question. On P25+ they have AEN at #3.
              OLD TARGETS, unverified and now superseded: Customer Wars -> #4,
              Alaska State Troopers -> #5. Neither was checkable for want of a
              demo, and neither came from A&E.
   [S3-DEMO]  The PRD says A25-64 and its worked example sorts on P25-64. v6
              switched to A25+ (P25_AA_ESTIMATES) citing the Hearst sheets.
              [S2-T1] carries P25-64 and not P25+, so this defaults to P25-64.
              If A&E confirms A25+, the column has to be added to [S2-T1] first;
              it is not a parameter change. Until then #4 and #5 are unverifiable.
   [S1-SEASON] Does not apply here. A&E's rule covers calculations that compare
              SEASONS. 3.1 compares NETWORKS against each other inside a set of
              time slots; the season only picks which slots those are, and no
              season average or season rank is computed. The same is true of 3.2,
              3.3 and 3.4, which work on fiscal years, dayparts and weeks.
   METHOD     Program-based strict dayparting, per the PRD: only the minutes
              inside the series' actual time period count, and the exact (date,
              half hour) slots the series' premieres occupied are what define it.
              Nights with no premiere fall out on their own, and day of week and
              start time never have to be hardcoded.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network       = 'AEN';
SET p_program       = '%INTERROGATION RAW%';
SET p_season        = NULL;        -- NULL = most recent season of the series
SET p_stream        = 'Live+SD';
SET p_demo          = 'P25_64_AA_ESTIMATES';   -- [S3-DEMO] see the header
SET p_excl_by       = 'CODE';      -- 'CODE' = A&E's station codes, 'NAME' = the PRD list
SET p_include_specials = FALSE;    -- [S3-SPECIALS] rankers drop specials by
                                   -- default, per A&E. The flag is CONTENT_TYPE,
                                   -- built from Cable Tracks CT_GENRE_1 with
                                   -- IS_SPECIAL as backup. John confirmed in
                                   -- week 8 that CT Genre 1 carries the special
                                   -- indicator and is safe to use, which is what
                                   -- replaced matching on the programme name.
SET p_win_from      = NULL;        -- NULL = the whole season
SET p_win_to        = NULL;
SET p_slot_min_min  = 15;
                              -- [SLOTMIN] WAS NULL, MEANING ANY CONTRIBUTION AT
                              -- ALL, and that alone was R_3's whole gap.
                              -- A&E define Interrogation Raw's period as THU
                              -- 9P-10P, sixty minutes. The telecast runs 9:00 to
                              -- 10:01p, so one minute landed in the 10:00 half
                              -- hour and the period became three half hours and
                              -- ninety minutes instead of two and sixty.
                              -- That third half hour is a different time period
                              -- for EVERY network, which is why the whole board
                              -- came back uniformly light - AEN 243 against 258,
                              -- TBSC 462 against 475, rank order correct
                              -- throughout. With the threshold: 2 slots, 60
                              -- minutes, TBSC 475 at rank 1, AEN 258 at rank 2.
                              -- 15 rather than 30 so a programme that genuinely
                              -- starts at 9:15 survives, while one- and
                              -- two-minute spills from an odd runtime do not.   -- [S3-SLOTMIN] minimum minutes the series must
                              -- contribute to a half hour before that half hour
                              -- counts as part of its time period. NULL = any
                              -- contribution at all, which is what every earlier
                              -- run used.
                              --
                              -- R_3 is why it exists. A&E define Interrogation
                              -- Raw's period as THU 9P-10P, 60 minutes. The
                              -- telecast runs 9:00 to 10:01p, so one minute lands
                              -- in the 10:00 half hour and 3.1 counted that half
                              -- hour as part of the period - 90 minutes over three
                              -- slots instead of 60 over two.
                              --
                              -- Every network is diluted by the same extra half
                              -- hour, so the RANKS survived: A&E came back #2 as
                              -- they should. The AAs did not - 243 against their
                              -- 258, TBSC 462 against 475, FOOD 221 against 255.
                              --
                              -- 15 reproduces their period: half of a half hour,
                              -- so a slot has to be at least half occupied to
                              -- belong to the series. That threshold is OURS,
                              -- inferred from one case. A&E has not stated a rule
                              -- and may simply be reading a declared daypart off
                              -- the schedule, which is a different construction
                              -- that happens to agree here.


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

WITH season_pick AS (
    -- the season in scope, by the series' most recent premiere
    SELECT CT_SEASON
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_HALFHR_FACT
    WHERE NETWORK_CODE  = $p_network
      AND RATING_SOURCE = $p_stream
      AND IS_FIRST_RUN_CT
      AND PROGRAM_NAME ILIKE $p_program
      AND CT_SEASON IS NOT NULL          -- [S3-SEASON] see below
      AND ($p_include_specials OR CONTENT_TYPE <> 'Special')
    QUALIFY ROW_NUMBER() OVER (ORDER BY BROADCAST_DATE DESC) = 1
),
slots AS (
    -- the exact (date, half hour) the series' premieres occupied.
    -- [S3-SLOTMIN] grouped rather than DISTINCT so the series' own contribution
    -- to each half hour can be measured and thresholded. With p_slot_min_min
    -- NULL this returns exactly what DISTINCT returned.
    SELECT h.BROADCAST_DATE, h.HALFHR_START_TIME,
           SUM(h.HH_MIN) AS SERIES_MIN
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_HALFHR_FACT h
    WHERE h.NETWORK_CODE  = $p_network
      AND h.RATING_SOURCE = $p_stream
      AND h.IS_FIRST_RUN_CT
      AND h.PROGRAM_NAME ILIKE $p_program
      -- [S3-SEASON] A&E, Jul-2026: a calculation whose axis is the SEASON may
      -- not use telecasts with no season. Not a parameter. The slots this
      -- ranker measures are the slots one SEASON occupied, so a telecast Cable
      -- Tracks has not catalogued cannot contribute one.
      AND h.CT_SEASON IS NOT NULL
      AND ($p_include_specials OR h.CONTENT_TYPE <> 'Special')
      AND ( $p_season IS NOT NULL AND h.CT_SEASON = $p_season
         OR $p_season IS NULL AND h.CT_SEASON = (SELECT CT_SEASON FROM season_pick) )
      AND ($p_win_from IS NULL OR h.BROADCAST_DATE >= TO_DATE($p_win_from))
      AND ($p_win_to   IS NULL OR h.BROADCAST_DATE <= TO_DATE($p_win_to))
    GROUP BY h.BROADCAST_DATE, h.HALFHR_START_TIME
    HAVING ($p_slot_min_min IS NULL OR SUM(h.HH_MIN) >= $p_slot_min_min)
),
competitive AS (
    -- every eligible network measured on ALL its programming in those slots:
    -- the metric is network delivery in the window, not premiere delivery
    SELECT h.NETWORK_CODE,
           COUNT(DISTINCT h.BROADCAST_DATE)               AS N_DATES,
           COUNT(*)                                       AS N_HALFHRS,
           SUM(h.HH_MIN)                                  AS MINUTES,
           SUM(IDENTIFIER($p_demo    ) * h.HH_MIN)
             / NULLIF(SUM(h.HH_MIN), 0)                   AS DEMO_AA
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_HALFHR_FACT h
    JOIN slots s
      ON  s.BROADCAST_DATE    = h.BROADCAST_DATE
      AND s.HALFHR_START_TIME = h.HALFHR_START_TIME
    JOIN AUDIENCE_DEV_DB.CRIS.CRIS_NETWORK_UNIVERSE u
      ON u.NETWORK_CODE = h.NETWORK_CODE
    WHERE h.RATING_SOURCE = $p_stream
      AND ( ($p_excl_by = 'CODE' AND u.IS_ENT_BY_CODE)
         OR ($p_excl_by = 'NAME' AND u.IS_ENT_BY_NAME) )
    GROUP BY h.NETWORK_CODE
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    RANK() OVER (ORDER BY ROUND(DEMO_AA/1000, 0) DESC)     AS RNK,
    COUNT(*) OVER ()                                       AS UNIVERSE_SIZE,
    NETWORK_CODE                                           AS NETWORK,
    IFF(NETWORK_CODE = $p_network, 1, 0)                     AS IS_TARGET,
    IFF(NETWORK_CODE = $p_network, '<<< the series network', NULL) AS MARKER,
    N_DATES, N_HALFHRS, MINUTES,
    ROUND(DEMO_AA/1000, 0)                                 AS AA_000,
    $p_demo                                                AS DEMO,
    $p_stream                                              AS STREAM,
    $p_excl_by                                             AS EXCLUSION_LIST,
    (SELECT COUNT(*) FROM slots)                           AS SLOTS,
    -- [S3-SLOTMIN] how much of each slot the series itself filled. If SLOT_MIN
    -- is 1 somewhere, a telecast is bleeding a minute into a half hour it does
    -- not really occupy and that half hour is dragging every network's average.
    (SELECT MIN(SERIES_MIN) FROM slots)                    AS SLOT_MIN_MINUTES,
    (SELECT SUM(SERIES_MIN) FROM slots)                    AS SERIES_MINUTES,
    (SELECT MIN(BROADCAST_DATE) FROM slots)                AS PERIOD_FROM,
    (SELECT MAX(BROADCAST_DATE) FROM slots)                AS PERIOD_TO
FROM competitive
ORDER BY RNK;