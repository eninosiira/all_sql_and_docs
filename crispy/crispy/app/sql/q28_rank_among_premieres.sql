/* ============================================================================
   FILE       2.8  RANK AMONG ALL OF NET'S PREMIERES                (PRD 2.8)
   PURPOSE    Where the series - or the individual telecast - sits among every
              premiere the network ran in the window.
   SOURCE     CRIS_TELECAST_FACT [S2-T0]
   VALIDATION SERIES grain, unchanged from v5:
                HIST, 2024-09-30 to 2025-09-28, DEMO_AA, prime 2000-2400,
                specials excluded -> HIST GREATEST MYSTERIES #16 of 37, AA 237.
              TELECAST grain, new, A&E benchmark SP_4:
                LIF, 2025-09-29 to 2026-07-12, F25_64_AA_ESTIMATES,
                p_movies = 'ONLY', specials included, prime 2000-2400 ->
                #1 DOUBLE DOUBLE TROUBLE   235  2026-02-21
                #2 MARY J. BLIGE: BE HAPPY 227  2026-02-07
                The 227 is the same figure OV_2 validated, so the two agree.
   NOTE       Prime here is 8:00p-12:00a, not the 8-11p of 2.1. That is A&E's
              own scope for this ranker, from the file "HISTORY FISCAL 2025
              (08:00P-12:00A)". Pinning a programme filters only the output row:
              the universe and the ranks are computed over the whole network.
              A&E also applies manual per-programme overrides (include a 5pm
              episode, drop one outside prime) which no rule reproduces.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_network       = 'LIF';
SET p_program       = NULL;  -- NULL = the whole ranker
SET p_stream        = 'Live+SD';
SET p_demo      = 'DEMO_AA';
SET p_include_specials = FALSE;
SET p_grain         = 'SERIES';    -- [S2-GRAIN] 'SERIES' | 'TELECAST'
                                   -- A&E's SP_4 answer names DOUBLE DOUBLE
                                   -- TROUBLE, which is an EPISODE_NAME. On
                                   -- Lifetime the PROGRAM_NAME is the slate
                                   -- bucket (LIFETIME ORIGINAL, MOVIE- ACQUIRED
                                   -- HOL PREM), so a ranker grouped by
                                   -- programme can never name the film that
                                   -- won. "Which movie" is a telecast question
                                   -- and "which series" is a programme one, so
                                   -- the grain is a parameter rather than a
                                   -- rewrite. SERIES is the default and keeps
                                   -- the GREATEST MYSTERIES case unchanged.
SET p_win_start_2959 = 2000;       -- 8:00p.  NULL = no lower bound
SET p_win_end_2959   = 2400;       -- 12:00a, exclusive. NULL = no upper bound
SET p_win_from      = NULL;
SET p_win_to        = NULL;
SET p_movies        = 'EXCLUDE';  -- [MOVIES] 'EXCLUDE' | 'ONLY' | 'BOTH'
SET p_min_tcasts    = NULL;        -- [MINTC] A&E, Trial 2: no universal telecast
                                   -- floor. NULL keeps every series; a number
                                   -- drops those with fewer telecasts than it.
                                  -- A&E, week 10, reported as fatal: a hard
                                  -- MOVIE_IND = 0 deletes the answer to any
                                  -- question about Lifetime, because Lifetime's
                                  -- premiere slate IS movies. Excluding them is
                                  -- right for a series question and wrong for a
                                  -- movie one, which makes it a parameter rather
                                  -- than a rule.
                                  -- EXCLUDE keeps the behaviour every validated
                                  -- series case was measured under.
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

WITH universe AS (
    SELECT NETWORK_CODE, PROGRAM_CODE,
           -- [S2-GRAIN] one row per programme, or one row per telecast. The
           -- unique key of the fact table is PROGRAM_CODE + TELECAST_NUM, so
           -- TELECAST_NUM is enough to split the group inside a programme.
           IFF($p_grain = 'TELECAST', TO_VARCHAR(TELECAST_NUM), '~SERIES~') AS GRAIN_KEY,
           MAX(PROGRAM_NAME) AS PROGRAM_NAME,
           IFF($p_grain = 'TELECAST', MAX(EPISODE_NAME), 'SERIES AVERAGE')  AS EPISODE_NAME,
           COUNT(*)          AS TCASTS,
           SUM(IDENTIFIER($p_demo) * CONTRIBUTING_DURATION)
             / NULLIF(SUM(CONTRIBUTING_DURATION), 0) AS SERIES_AA,   -- [WAVG] duration weighted, Adarsh 11 Sep 2026.
           -- [S2-NOSEASONDATES] A&E, 22 Sep 2026: "for number seven we don't
           -- want those dates in there because it's confusing... that should be
           -- the last 12 months." The season's dates are still computed, the
           -- ranker needs them to scope a series, but they no longer reach the
           -- output. WINDOW_FROM and WINDOW_TO carry the range that was ranked.
           MIN(BROADCAST_DATE) AS FROM_DATE,
           MAX(BROADCAST_DATE) AS TO_DATE
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT
    WHERE NETWORK_CODE   = $p_network
      AND RATING_SOURCE  = $p_stream
      AND IS_FIRST_RUN_CT
      AND ( $p_movies = 'BOTH'
         OR ($p_movies = 'EXCLUDE' AND MOVIE_IND = 0)
         OR ($p_movies = 'ONLY'    AND MOVIE_IND = 1) )
      AND ($p_include_specials OR CONTENT_TYPE <> 'Special')
      AND BROADCAST_DATE BETWEEN $win_from AND $win_to
      -- [S2-NULLSAFE] NULL means "no bound", not "match nothing". Written bare,
      -- BCAST_START_2959 >= NULL evaluates to NULL and the ranker returns zero
      -- rows with no error, which reads exactly like a network that aired
      -- nothing. That is what emptied SP_4 on the first benchmark run: the cell
      -- set both ends to NULL meaning "all day" and got silence. Every
      -- parameter is override-able and NULL activates the default, so the
      -- guard has to say so.
      AND ($p_win_start_2959 IS NULL OR BCAST_START_2959 >= $p_win_start_2959)
      AND ($p_win_end_2959   IS NULL OR BCAST_START_2959 <  $p_win_end_2959)
    GROUP BY NETWORK_CODE, PROGRAM_CODE,
             IFF($p_grain = 'TELECAST', TO_VARCHAR(TELECAST_NUM), '~SERIES~')
    HAVING ($p_min_tcasts IS NULL OR COUNT(*) >= $p_min_tcasts)   -- [MINTC]
    -- [S2-FLOOR] no minimum telecast count. There is no such rule: the floor of
    -- three was carried here with a comment crediting A&E and neither the PRD nor
    -- any check-in note contains it. A series that aired twice is a series that
    -- aired twice, and dropping it from a ranker is a silent editorial decision
    -- about what counts. If A&E wants a floor they can say so and it comes back
    -- as a parameter with their name on it.
),
ranked AS (
    SELECT u.*,
           -- ranked on the rounded 000s, ties share a rank, per A&E
           RANK()   OVER (ORDER BY ROUND(SERIES_AA/1000, 0) DESC) AS RNK,
           COUNT(*) OVER ()                                       AS UNIVERSE_SIZE
    FROM universe u
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    RNK, UNIVERSE_SIZE,
    IFF($p_program IS NOT NULL AND PROGRAM_NAME ILIKE $p_program, 1, 0) AS IS_TARGET,
    NETWORK_CODE AS NETWORK,
    PROGRAM_NAME AS PROGRAM,
    EPISODE_NAME AS EPISODE,
    TCASTS,
    ROUND(SERIES_AA/1000, 0) AS AA_000,
    $p_grain  AS GRAIN,
    $win_from AS FROM_DATE, $win_to AS TO_DATE
FROM ranked
-- [FULLRANKER] Jill, 24 Sep 2026: show every eligible series, not only the one
-- asked about. The programme is marked in IS_TARGET; nothing is filtered.
WHERE TRUE
ORDER BY RNK;
