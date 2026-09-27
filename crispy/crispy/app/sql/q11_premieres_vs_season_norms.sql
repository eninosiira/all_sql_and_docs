/* ============================================================================
   FILE       1.1  OVERNIGHT SUMMARY - PREMIERES VS. SEASON NORMS   (PRD Table 1)
   PURPOSE    Per premiere on the target night: telecast AA, the programme's
              season norm, % change vs that norm, and the premiere's rank within
              its own season.
   SOURCE     AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT   [S1-T1]
              dates from AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE   [S1-T0]

   VALIDATION (1) HIST, Live+SD, 2025-05-30   (OV_1)
                  SECRETS DECLASSIFIED / 9 SPY TECH   306  norm 210   8 TC  +45.7
                  UNBELIEVABLE WITH DAN A. / 30       290  norm 279  19 TC   +3.9
              (2) LIF, Live+SD, 2026-02-07   (OV_2)   [S1-YEARSEASON]
                  MOVIE- ORIGINAL PREM / MARY J. BLIGE: BE HAPPY
                  227  norm 138  13 TC  +64.5
                  The norm runs 4 Oct 2025 to 31 Jan 2026 across CT_SEASON 2025
                  and 2026; what those thirteen share is FY26 to date.
              (3) FYI, Live+SD, 2026-06-29   (OV_3)   [S1-NORMNIGHT] [S1-PRIORSEASON]
                  RACHAEL RAYS MEAL IN MIN / POPCORN CHICKEN  32  norm 8  10 TC
                  RACHAEL RAYS MEAL IN MIN / SLIDERS, SKEWERS 22  norm 8  10 TC
                  INSTANT ITALIAN / TIRAMISU BROWNIES  10  prior season 10, 12 TC
                                                           prior premiere 17,  2 TC
                  INSTANT ITALIAN / RICE REINVENTED     3  same two references
                  A&E's own ten telecasts, 25 May to 22 Jun, are
                  13,11,9,5,7,5,5,7,12,4 = 78, and 78/10 = 7.8 -> 8.
                  The prior INSTANT ITALIAN season, 10 Mar to 14 Apr 2025, is
                  16,18,11,5,7,2,4,3,12,15,14,18 = 125, and 125/12 = 10.4 -> 10.
                  Its premiere night is (16+18)/2 = 17.
              (4) A&E's answer workbook, sheet SP_8
                  INTERROGATION RAW  telecast 126  norm 147  15 TC

   [S1-REPEATS] The Overnight Summary in A&E's workbook lists the whole 8p-12a
              schedule, repeats included: on 29 June FYI ran four repeats around
              the premieres and all eight appear in their section 156. None of
              those repeats has a season norm - their three Season Norms sections
              cover the two programmes, not the repeat telecasts.

              So the repeats are schedule context, not answer. CRIS answers about
              premieres and the repeats stay available as lead-in, which is why
              IS_FIRST_RUN_CT is a column on the fact table and not a filter baked
              into it. Their sheet carries a Program Lead-In section too, with
              STORAGE WARS at 7:30p, for exactly that reason.

              This is OUR reading of their report, not a rule A&E stated. If they
              ever want the full night it is a display parameter, not a change of
              calculation.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network            = 'HIST';   -- NULL = all A+E networks
SET p_rating_src         = 'Live+SD';
SET p_target_date        = NULL;     -- NULL = latest night with data
SET p_program            = NULL;   -- [S1-SCOPE] NULL = every premiere in scope.
                                   -- A LIKE pattern such as '%SKINWALKER%' pins one
                                   -- programme. Nielsen truncates PROGRAM_NAME to 25
                                   -- characters, so a full title can fail to match
                                   -- where a pattern will not.
SET p_season             = NULL;   -- NULL = the season each premiere belongs to.
                                   -- A value pins one, e.g. '2'.
SET p_report_from        = NULL;   -- NULL = a single night, per p_target_date.
SET p_report_to          = NULL;   -- Both set = every premiere in that range.
SET p_include_specials   = TRUE;     -- FALSE = drop CONTENT_TYPE = 'Special'
-- [S1-WIN] the Overnight Summary is an 8p-12a report. Every "Overnight Summary
-- 8p-12a" section in A&E's answer workbook stays inside it. NULL on either bound
-- widens to the whole broadcast day.
SET p_win_start_2959     = 2000;     -- 8:00p
SET p_win_end_2959       = 2400;     -- 12:00a, exclusive
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
fy AS (
    -- [S1-YEARSEASON] the fiscal year each date belongs to.
    --
    -- Needed because Cable Tracks labels some programmes by calendar year
    -- rather than by season: MOVIE- ORIGINAL PREM carries CT_SEASON 2026 for
    -- everything Lifetime premiered in 2026. Partitioning a norm by that
    -- partitions it by January.
    --
    -- 156 programmes of 1,503 are labelled this way and 3,606 telecasts of
    -- 29,291, so it is a minority and not a corner: Lifetime and LMN account
    -- for 42% of them, being the movie slate, and VICE for a quarter, being
    -- the dailies.
    SELECT FISCAL_YEAR, FY_START, FY_END
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_FY_CALENDAR
),
target AS (
    -- which series premiered on the reported night, and in which season.
    -- [S1-KEY] PROGRAM_CODE, not PROGRAM_NAME. Nielsen's name is a 25-character
    -- field that can be restated between revisions, and the season itself
    -- arrives through the Cable Tracks join on PROGRAM_CODE + TELECAST_NUM, so
    -- grouping the norm on the name mixes two different identity axes. The name
    -- is display only from here on.
    SELECT DISTINCT t0.NETWORK_CODE, t0.PROGRAM_CODE, t0.CT_SEASON,
           -- [S1-YEARSEASON] a year label is not a season, so where it appears
           -- the partition becomes the fiscal year the telecast falls in.
           IFF(REGEXP_LIKE(t0.CT_SEASON, '^(19|20)[0-9]{2}[A-Za-z]?$'),
               'FY' || fy.FISCAL_YEAR, t0.CT_SEASON)          AS NORM_KEY,
           REGEXP_LIKE(t0.CT_SEASON, '^(19|20)[0-9]{2}[A-Za-z]?$') AS IS_YEAR_LABEL,
           fy.FY_START, fy.FY_END
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT t0
    LEFT JOIN fy
      ON t0.BROADCAST_DATE BETWEEN fy.FY_START AND fy.FY_END
    -- [S1-SCOPE] two ways in, one CTE.
    --   no programme      the premieres of one night, or of a date range
    --   a programme       that programme's season, whole, ignoring the date
    -- Naming a programme drops the date bound on purpose: "how is Skinwalker
    -- doing" is a season question, and requiring a date to answer it would
    -- return one row and call it a season.
    WHERE ( ($p_program IS NULL
             AND t0.BROADCAST_DATE BETWEEN COALESCE(TO_DATE($p_report_from), $eff_target)
                                    AND COALESCE(TO_DATE($p_report_to),   $eff_target))
         OR ($p_program IS NOT NULL AND t0.PROGRAM_NAME ILIKE $p_program
             AND t0.BROADCAST_DATE <= $eff_target) )
      AND ($p_season IS NULL OR t0.CT_SEASON = $p_season)
      -- [S1-REPEATS] premieres only. The repeats on the night are schedule
      -- context and stay available to 1.3 as lead-in.
      AND t0.IS_FIRST_RUN_CT
      AND ($p_rating_src IS NULL OR t0.RATING_SOURCE = $p_rating_src)
      AND ($p_network    IS NULL OR t0.NETWORK_CODE  = $p_network)
      AND ($p_include_specials OR t0.CONTENT_TYPE <> 'Special')
      AND ($p_win_start_2959 IS NULL OR t0.BCAST_START_2959 >= $p_win_start_2959)
      AND ($p_win_end_2959   IS NULL OR t0.BCAST_START_2959 <  $p_win_end_2959)
      -- [S1-SEASON] A&E, Jul-2026: a calculation that compares SEASONS may not
      -- use telecasts with no season. Not a parameter. Cable Tracks is the
      -- authority. Both the season norm and the season rank are comparisons
      -- ACROSS a season, so a telecast Cable Tracks has not catalogued cannot
      -- take part in either: it does not appear rather than appearing against
      -- an approximation.
      AND t0.CT_SEASON IS NOT NULL
),
base AS (
    -- the whole of those seasons, up to the reported night. The season is scoped
    -- by identity, not by a calendar window, so a season that has been running
    -- longer than a year still comes through complete.
    SELECT f.NETWORK_CODE, f.PROGRAM_CODE, f.TELECAST_NUM,
           f.PROGRAM_NAME, f.EPISODE_NAME, f.CT_SEASON,
           f.BROADCAST_DATE, f.DAY_OF_WEEK, f.START_TIME, f.BCAST_START_2959,
           IDENTIFIER($eff_demo) AS DEMO_AA, f.CONTENT_TYPE,
           f.CONTRIBUTING_DURATION AS W,
           -- [S1-NORMKEY] the norm is scoped by the TARGET's key, so one
           -- season is one partition. CT_SEASON stays for display only.
           t.NORM_KEY,
           t.IS_YEAR_LABEL
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT f
    JOIN target t
      ON  t.NETWORK_CODE = f.NETWORK_CODE
      AND t.PROGRAM_CODE = f.PROGRAM_CODE            -- [S1-KEY]
      -- [S1-SEASON] the season, and only the season. No premiere-anchored
      -- fallback and no trailing window: a comparison whose axis is the
      -- season cannot be made against an approximation of one.
      --
      -- [S1-YEARSEASON] unless the label is a year, in which case the season it
      -- stands for is the fiscal year. Matching on CT_SEASON there would cut the
      -- norm at 1 January: A&E's own corrected pull for the 7 February 2026
      -- Lifetime premiere runs from 4 October, spanning CT_SEASON 2025 and 2026,
      -- and what those thirteen telecasts share is FY26. Trailing twelve months
      -- would give 39 telecasts and a norm of 140, so the data tells the two
      -- readings apart and this is the one that reproduces 138 and +64.5.
      AND ( (NOT t.IS_YEAR_LABEL AND f.CT_SEASON = t.CT_SEASON)
         OR (t.IS_YEAR_LABEL
             AND f.BROADCAST_DATE BETWEEN t.FY_START AND t.FY_END) )
    WHERE f.IS_FIRST_RUN_CT
      AND ($p_rating_src IS NULL OR f.RATING_SOURCE = $p_rating_src)
      AND f.BROADCAST_DATE <= $eff_target        -- the only date limit that matters
      AND ($p_include_specials OR f.CONTENT_TYPE <> 'Special')
),
prog AS (
    -- [S1-PRIORSEASON] the programmes in scope, so the history below is pulled
    -- once for them rather than for the network.
    SELECT DISTINCT NETWORK_CODE, PROGRAM_CODE FROM target
),
hist AS (
    -- [S1-PRIORSEASON] every season those programmes have run, up to the
    -- reported night. `base` holds only the target season, so a season premiere
    -- has nothing in it to be normed against; this is where the previous season
    -- comes from.
    SELECT f.NETWORK_CODE, f.PROGRAM_CODE, f.BROADCAST_DATE,
           f.CT_SEASON,
           IFF(REGEXP_LIKE(f.CT_SEASON, '^(19|20)[0-9]{2}[A-Za-z]?$'),
               'FY' || fy.FISCAL_YEAR, f.CT_SEASON)           AS NORM_KEY,
           IDENTIFIER($eff_demo) AS DEMO_AA,
           f.CONTRIBUTING_DURATION AS W
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT f
    JOIN prog p
      ON  p.NETWORK_CODE = f.NETWORK_CODE
      AND p.PROGRAM_CODE = f.PROGRAM_CODE
    LEFT JOIN fy
      ON f.BROADCAST_DATE BETWEEN fy.FY_START AND fy.FY_END
    WHERE f.IS_FIRST_RUN_CT
      AND ($p_rating_src IS NULL OR f.RATING_SOURCE = $p_rating_src)
      AND f.BROADCAST_DATE <= $eff_target
      AND ($p_include_specials OR f.CONTENT_TYPE <> 'Special')
      AND f.CT_SEASON IS NOT NULL
),
span AS (
    -- one row per season of each programme, with its own average
    SELECT NETWORK_CODE, PROGRAM_CODE, NORM_KEY,
           MIN(BROADCAST_DATE) AS S_FROM,
           MAX(BROADCAST_DATE) AS S_TO,
           SUM(DEMO_AA * W) / NULLIF(SUM(W), 0) AS S_AVG,  -- [WAVG] duration weighted, Adarsh 11 Sep 2026: every aggregation.
           COUNT(*)            AS S_TC
    FROM hist
    GROUP BY 1,2,3
),
tgt_span AS (
    SELECT NETWORK_CODE, PROGRAM_CODE, NORM_KEY,
           MIN(BROADCAST_DATE) AS SEASON_START
    FROM base
    GROUP BY 1,2,3
),
prior_pick AS (
    -- [S1-PRIORSEASON] the season that ended most recently before this one
    -- started. Chosen by date and not by label, because season names are free
    -- text and 2B does not sort after 2 in any useful way.
    SELECT t.NETWORK_CODE, t.PROGRAM_CODE, t.NORM_KEY,
           s.NORM_KEY AS PRIOR_KEY,
           s.S_AVG    AS PRIOR_AVG,
           s.S_TC     AS PRIOR_TC,
           s.S_FROM   AS PRIOR_FROM,
           s.S_TO     AS PRIOR_TO
    FROM tgt_span t
    JOIN span s
      ON  s.NETWORK_CODE = t.NETWORK_CODE
      AND s.PROGRAM_CODE = t.PROGRAM_CODE
      AND s.NORM_KEY    <> t.NORM_KEY
      AND s.S_TO         < t.SEASON_START
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t.NETWORK_CODE, t.PROGRAM_CODE, t.NORM_KEY
                               ORDER BY s.S_TO DESC) = 1
),
prior_prem AS (
    -- [S1-PRIORSEASON] and the prior season's own premiere night, which A&E
    -- prints as a second reference: their section 160 is INSTANT ITALIAN on
    -- 10 Mar 2025 alone, (16+18)/2 = 17.
    SELECT pp.NETWORK_CODE, pp.PROGRAM_CODE, pp.NORM_KEY,
           SUM(h.DEMO_AA * h.W) / NULLIF(SUM(h.W), 0) AS PRIOR_PREM_AVG,  -- [WAVG] duration weighted, Adarsh 11 Sep 2026: every aggregation.
           COUNT(*)       AS PRIOR_PREM_TC
    FROM prior_pick pp
    JOIN hist h
      ON  h.NETWORK_CODE   = pp.NETWORK_CODE
      AND h.PROGRAM_CODE   = pp.PROGRAM_CODE
      AND h.NORM_KEY       = pp.PRIOR_KEY
      AND h.BROADCAST_DATE = pp.PRIOR_FROM
    GROUP BY 1,2,3
),
std AS (
    SELECT b.*,
        -- [S1-NORMNIGHT] the norm excludes the WHOLE REPORT NIGHT, not just the
        -- telecast being measured.
        --
        -- This replaces leave-one-out. A&E's OV_3 pull settles it: their norm
        -- for RACHAEL RAYS MEAL IN MIN on 29 June is 8 over 10 telecasts, with
        -- the window printed as 25 May to 22 Jun - the week before. Their ten
        -- telecasts are 13,11,9,5,7,5,5,7,12,4, which sum to 78, and 78/10 is
        -- 7.8. Leave-one-out gives 100/11 and 110/11, which is the 9 and 10 the
        -- previous version returned.
        --
        -- The two rules are identical wherever a programme premieres once a
        -- night, which is every case validated before OV_3: OV_1 and OV_2 both
        -- have SEASON_NORM_TC exactly one below EPS_IN_SEASON. FYI airs two
        -- episodes back to back and that is where they separate.
        --
        -- It also fixes something nobody had flagged: leave-one-out gave the two
        -- premieres of the same programme on the same night two DIFFERENT norms,
        -- 9 and 10. A&E prints one norm per programme per night, which is what
        -- excluding the night produces.
        --
        -- Written against the row's own BROADCAST_DATE rather than $eff_target
        -- so it still behaves over a date range or a pinned programme, where
        -- every telecast prints and each is measured against its season minus
        -- its own night.
        (SUM(DEMO_AA * W) OVER (PARTITION BY b.NETWORK_CODE, b.PROGRAM_CODE, b.NORM_KEY)
         - SUM(DEMO_AA * W) OVER (PARTITION BY b.NETWORK_CODE, b.PROGRAM_CODE, b.NORM_KEY,
                                  b.BROADCAST_DATE))
        / NULLIF(
            SUM(W) OVER (PARTITION BY b.NETWORK_CODE, b.PROGRAM_CODE, b.NORM_KEY)
            - SUM(W) OVER (PARTITION BY b.NETWORK_CODE, b.PROGRAM_CODE, b.NORM_KEY,
                          b.BROADCAST_DATE), 0)                AS PROG_STD_AVG,
        COUNT(*) OVER (PARTITION BY b.NETWORK_CODE, b.PROGRAM_CODE, b.NORM_KEY)
          - COUNT(*) OVER (PARTITION BY b.NETWORK_CODE, b.PROGRAM_CODE, b.NORM_KEY,
                           b.BROADCAST_DATE)                      AS PROG_STD_TC,
        -- A&E CONFIRMED (Jill, Jul-9-2026): "How it ranks within that series
        -- current season" -> the episode's rank among ITS OWN series' season
        -- telecasts, not a network-wide rank. Ties share rank (RANK, not
        -- ROW_NUMBER) and rank on the rounded 000s per A&E's rounding rule.
        RANK() OVER (PARTITION BY b.NETWORK_CODE, b.PROGRAM_CODE, b.NORM_KEY
                     ORDER BY ROUND(b.DEMO_AA/1000,0) DESC)       AS STD_RANK,
        -- STD_UNIVERSE counts every telecast of the season and is the "of N
        -- episodes" denominator, so it deliberately does NOT drop anything.
        COUNT(*) OVER (PARTITION BY b.NETWORK_CODE, b.PROGRAM_CODE, b.NORM_KEY)
                                                                  AS STD_UNIVERSE
    FROM base b
),
joined AS (
    -- [S1-PRIORSEASON] the norm actually used. The season's own telecasts where
    -- there are any before tonight; the previous season where there are not.
    SELECT s.*,
           pk.PRIOR_KEY, pk.PRIOR_AVG, pk.PRIOR_TC, pk.PRIOR_FROM, pk.PRIOR_TO,
           pm.PRIOR_PREM_AVG, pm.PRIOR_PREM_TC,
           IFF(s.PROG_STD_TC > 0, s.PROG_STD_AVG, pk.PRIOR_AVG)   AS EFF_NORM,
           IFF(s.PROG_STD_TC > 0, s.PROG_STD_TC,  pk.PRIOR_TC)    AS EFF_TC,
           CASE WHEN s.PROG_STD_TC > 0 AND s.IS_YEAR_LABEL THEN 'FISCAL YEAR TO DATE'
                WHEN s.PROG_STD_TC > 0                     THEN 'SEASON TO DATE'
                WHEN pk.PRIOR_KEY IS NOT NULL
                 AND s.IS_YEAR_LABEL                       THEN 'PRIOR FISCAL YEAR'
                WHEN pk.PRIOR_KEY IS NOT NULL              THEN 'PRIOR SEASON'
                ELSE 'NO NORM' END                                AS NORM_BASIS
    FROM std s
    LEFT JOIN prior_pick pk
      ON  pk.NETWORK_CODE = s.NETWORK_CODE
      AND pk.PROGRAM_CODE = s.PROGRAM_CODE
      AND pk.NORM_KEY     = s.NORM_KEY
    LEFT JOIN prior_prem pm
      ON  pm.NETWORK_CODE = s.NETWORK_CODE
      AND pm.PROGRAM_CODE = s.PROGRAM_CODE
      AND pm.NORM_KEY     = s.NORM_KEY
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    NETWORK_CODE                 AS NETWORK,
    BROADCAST_DATE               AS AIR_DATE,
    DAY_OF_WEEK                  AS DAY,
    PROGRAM_NAME                 AS PROGRAM,
    EPISODE_NAME                 AS EPISODE,
    CT_SEASON                    AS SEASON,
    CONTENT_TYPE,
    START_TIME,
    BCAST_START_2959             AS START_2959,
    ROUND(DEMO_AA/1000,0)        AS TELECAST_000,       -- premiere delivery
    ROUND(EFF_NORM/1000,0)       AS SEASON_NORM_000,    -- the norm actually used
    EFF_TC                       AS SEASON_NORM_TC,
    -- which window the norm was built over, because a reader has no way to tell
    -- from the number alone whether it is this season, this fiscal year, or the
    -- season before
    NORM_BASIS,
    -- Change vs the norm (A&E method: compute on the rounded 000s)
    ROUND((ROUND(DEMO_AA/1000,0)
           / NULLIF(ROUND(EFF_NORM/1000,0),0) - 1) * 100, 1)      AS CHANGE_VS_NORM_PCT,
    -- [S1-PRIORSEASON] the second reference, and it prints ONLY for a season
    -- premiere. A&E gives it only there, and printing it everywhere caused a
    -- real misreading in the v10 run: RACHAEL RAYS' prior-season premiere also
    -- averaged 8, the same as its season norm, so CHANGE_VS_NORM_PCT and
    -- CHANGE_VS_PRIOR_PREMIERE_PCT both read +300.0 and looked like one of the
    -- two was wrong. Blanking them outside the prior-season case removes the
    -- coincidence rather than explaining it.
    --
    -- To see them on every row instead, drop the three IFFs. The underlying
    -- figures are computed either way; this is display.
    IFF(NORM_BASIS IN ('PRIOR SEASON','PRIOR FISCAL YEAR'),
        PRIOR_KEY, NULL)                                          AS PRIOR_SEASON,
    IFF(NORM_BASIS IN ('PRIOR SEASON','PRIOR FISCAL YEAR'),
        ROUND(PRIOR_PREM_AVG/1000,0), NULL)                       AS PRIOR_PREMIERE_000,
    IFF(NORM_BASIS IN ('PRIOR SEASON','PRIOR FISCAL YEAR'),
        PRIOR_PREM_TC, NULL)                                      AS PRIOR_PREMIERE_TC,
    IFF(NORM_BASIS IN ('PRIOR SEASON','PRIOR FISCAL YEAR'),
        ROUND((ROUND(DEMO_AA/1000,0)
               / NULLIF(ROUND(PRIOR_PREM_AVG/1000,0),0) - 1) * 100, 1), NULL)
                                                     AS CHANGE_VS_PRIOR_PREMIERE_PCT,
    STD_RANK                     AS EP_RANK_IN_SEASON,  -- e.g. #3 of its own series
    STD_UNIVERSE                 AS EPS_IN_SEASON,      -- ...of 8 episodes
    -- [S1-NORM] a norm of nothing is not a norm, and a norm of one or two is
    -- reportable but is not a benchmark. The answer layer has to say so.
    CASE WHEN EFF_TC IS NULL OR EFF_TC = 0
              THEN 'NO NORM: SEASON PREMIERE WITH NO PRIOR SEASON'
         WHEN PROG_STD_TC = 0
              THEN 'SEASON PREMIERE: NORMED ON PRIOR SEASON'
         WHEN EFF_TC < 3
              THEN 'THIN NORM: ' || EFF_TC || ' TELECAST(S)'
    END                          AS NORM_CAVEAT,
    $eff_target             AS TO_DATE
FROM joined
-- [S1-SCOPE] what gets reported, as opposed to what built the norm. The norm is
-- always the whole season; this line only decides which of its telecasts print.
WHERE ( ($p_program IS NULL
         AND BROADCAST_DATE BETWEEN COALESCE(TO_DATE($p_report_from), $eff_target)
                                AND COALESCE(TO_DATE($p_report_to),   $eff_target))
     OR  $p_program IS NOT NULL )
ORDER BY BROADCAST_DATE DESC, DEMO_AA DESC;
