/* ============================================================================
   FILE       3.3  SERIES OR GENRE RANKERS                          (PRD 3.3)
   PURPOSE    The top N programmes across cable for a window, a daypart and an
              optional genre. A genre ranker is a series ranker with a genre
              filter, nothing more.
   SOURCE     CRIS_HALFHR_FACT [S2-T1], CRIS_NETWORK_UNIVERSE [S3-T0],
              CRIS_FY_CALENDAR [S3-T1]
   VALIDATION A&E benchmark R_1. Non-fiction, FY26 through 28 Jun 2026, prime,
              Live+SD, P25-64, premieres only:
                 #1 TOURNAMENT OF CHAMPIONS (FOOD)  646  over  8 telecasts
                 #2 1000-LB SISTERS         (TLC)   635  over 10
                 #7 CURSE OF OAK ISLAND     (HIST)  524  over 25
                #16 SISTER WIVES and SUDDENLY AMISH both 434, both #16
                HIST's top three: CURSE #7, WORLD WAR II #27, HAZARDOUS #29
              Requires [S3-PREMIERES]. Without it the same window returns CURSE
              over 53 telecasts at 362 and TOURNAMENT over 17 at 412.
              [S3-GENRE2] closes the sports half of "All Exclusions": WWE
              SMACKDOWN carries CT_GENRE_2 SPORTS and came back at #3 on 35
              telecasts at 679 before it existed.
              STILL OPEN: their header also reads "All Exclusions & Mini-Series"
              and our list carries entries theirs does not, such as 90 DAY FIANCE
              BT90D over two telecasts. Whatever that exclusion is, it is not
              reproduced here and it is a question for A&E.

              Earlier target, same query on a window ending 2026-04-26:
                 #1 TOURNAMENT OF CHAMPIONS (FOOD)  646
                 #5 CURSE OF OAK ISLAND     (HIST)  528
                #12 SISTER WIVES and SUDDENLY AMISH both 434, both #12,
                    and the next row is #14
                #20 HOLIDAY BAKING                  393
              Reproduce with p_win_to = '2026-04-26'.
   [S3-WEIGHT] The series average is weighted by minutes. Curse of Oak Island
              over the same 25 telecasts and 1,637 minutes A&E print reads 528.2
              flat and 524.0 weighted; theirs is 524. The programmes that already
              matched are those whose telecasts are all one length, where the two
              agree. 3.1 and 3.2 have always weighted; 3.3 was the exception.
   [S3-DP12A] The daypart here is 8:00p to 12:00a, matching 2.8. Network norms
              use 8-11p and programme rankers run to midnight; 3.3 was the one
              ranker on the wrong side of that. Three of R_1's four figure gaps
              were this alone, all of them telecasts running past eleven.
   [S3-FOCUS]  R_1 asks for the top 3 PER NETWORK and where those sit in the
              cable set, and the answer A&E print is eight rows. p_top_n cut by
              global position only, so reaching Lifetime's second title at cable
              rank 368 meant asking for 400 rows to find eight. p_focus_networks
              and p_per_network cut by network instead, on the same ranking.
              R_1 = focus 'AEN,HIST,LIF', per_network 3, top_n NULL.
   [S3-GENRE] Two genre sources, and they are not equivalent.
              CT_GENRE_1 is Cable Tracks, which is A&E's licensed metadata and
              is what v6 used to reach the numbers above, so it is the default.
              PROG_TYPE_ALPHA is Nielsen's own taxonomy, Appendix Table C, and
              [S2-T1] reported it populated on 100% of 30.7M rows across all 174
              networks. It is the fallback if Cable Tracks turns out to be thin
              on competitors. p_genre_col picks.
   ============================================================================ */
-- ===== PARAMETERS =====
SET p_top_n         = 20;    -- [S3-FOCUS] how many of the GLOBAL ranking to
SET p_min_tcasts    = NULL;        -- [MINTC] A&E, Trial 2: no universal telecast
                                   -- floor. NULL keeps every series; a number
                                   -- drops those with fewer telecasts than it.
                             -- return. NULL = no global cut, which is what a
                             -- per-network question wants.
SET p_focus_networks = NULL; -- [S3-FOCUS] which networks to return rows for, as
                             -- a comma list: 'AEN,HIST,LIF'. NULL = all of them.
                             -- This does NOT narrow what is ranked. The RANK()
                             -- below is always computed across the whole
                             -- competitive set, because the second half of a
                             -- question like R_1 is "and where do these sit in
                             -- the cable set", which a filtered universe cannot
                             -- answer.
SET p_per_network    = NULL; -- [S3-FOCUS] how many rows per network. NULL = all.
                             --
                             -- Why these two exist. p_top_n cut by GLOBAL
                             -- position and nothing else, so a question about
                             -- three networks had to ask for a deep slice of the
                             -- whole cable and hope they were in it. On A&E's own
                             -- R_1 answer Lifetime's second title is at cable
                             -- rank 368, so p_top_n would have to be 400 to
                             -- return eight rows, and the caller gets 400 rows to
                             -- find 8.
                             --
                             -- With these, R_1 is focus 'AEN,HIST,LIF' and
                             -- per_network 3, and it returns exactly the eight
                             -- rows A&E print. The aggregation is unchanged and
                             -- so is the ranking; only which rows survive the
                             -- QUALIFY is different.
SET p_genre_col     = 'CT_GENRE_1';        -- [S3-GENRE] or 'PROG_TYPE_ALPHA'
SET p_genre         = 'NON-FICTION';     -- NULL = every genre
SET p_genre_2_exclude = 'SPORTS';  -- [S3-GENRE2] second-genre exclusion, one
                                  -- LIKE pattern. NULL = exclude nothing.
                                  --
                                  -- CT_GENRE_1 cannot separate WWE SMACKDOWN from
                                  -- TOURNAMENT OF CHAMPIONS: both read
                                  -- NON-FICTION. CT_GENRE_2 reads SPORTS against
                                  -- REALITY COMPETITION, and A&E's R_1 sheet
                                  -- prints a Genre 2 column carrying exactly
                                  -- those values with the sports rows absent.
                                  --
                                  -- Without it WWE SMACKDOWN came back at #3 of a
                                  -- ranker it does not appear in at all, on 35
                                  -- telecasts at 679.
                                  --
                                  -- REQUIRES CRIS_Tables_v17 or later. CT_GENRE_2
                                  -- was not stored before it.
SET p_stream        = 'Live+SD';
SET p_demo          = 'P25_64_AA_ESTIMATES';
SET p_excl_by       = 'CODE';
SET p_include_specials = FALSE;    -- [S3-SPECIALS] rankers drop specials by
                                   -- default, per A&E. The flag is CONTENT_TYPE,
                                   -- built from Cable Tracks CT_GENRE_1 with
                                   -- IS_SPECIAL as backup. John confirmed in
                                   -- week 8 that CT Genre 1 carries the special
                                   -- indicator and is safe to use, which is what
                                   -- replaced matching on the programme name.
SET p_premieres_only = TRUE;  -- [S3-PREMIERES] premiere telecasts only.
                              -- A&E's R_1 sheet is headed "Premiere Program
                              -- Ranker", and 3.3 had no repeat filter at all. The
                              -- counts show it plainly: CURSE OF OAK ISLAND came
                              -- back over 53 telecasts against their 25,
                              -- TOURNAMENT OF CHAMPIONS 17 against 8, 1000-LB
                              -- SISTERS 21 against 10 - about double in every
                              -- case, with the average sunk to match. Backing out
                              -- CURSE's 28 repeats puts them near 217 against the
                              -- premieres' 524.
                              --
                              -- TRUE is the default because a programme ranker is
                              -- a ranker of premieres unless someone says
                              -- otherwise. FALSE ranks everything the network
                              -- aired, repeats included, which is a different
                              -- question and a legitimate one.
SET p_dp_from_2959  = 2000;   -- [S3-DP12A] prime M-Su 8:00p to 12:00a, not the
SET p_dp_to_2959    = 2400;   -- 8-11p the network norms use.
                              --
                              -- Programme rankers run to midnight and network
                              -- norms stop at eleven. 2.8 already said so in its
                              -- own header, citing A&E's file name "HISTORY
                              -- FISCAL 2025 (08:00P-12:00A)"; 3.3 was the one
                              -- ranker not following it.
                              --
                              -- Three of R_1's four remaining figure gaps are
                              -- this one setting, and each is a telecast running
                              -- past eleven:
                              --
                              --   SLEEPING WITH A KILLER  four telecasts in their
                              --     count and three in ours. Lifetime ran an
                              --     eighteen-episode marathon that Sunday and the
                              --     fourth in prime starts 23:03, so at 8-11p it
                              --     does not fall short, it disappears. Their
                              --     241 minutes are 60+63+60+58; ours were 180.
                              --
                              --   CURSE OF OAK ISLAND  runs 9:00 to 11:05p. At
                              --     8-11p we counted 120 minutes of 125, their
                              --     duration 1,637 against our 1,632, and the
                              --     average read 528 against their 524 because
                              --     the minutes dropped are the low tail of the
                              --     night.
                              --
                              --   WORLD WAR II TOM HANKS  the same five minutes.
                              --
                              -- Leave 3.1 and 3.2 alone: both are validated at
                              -- 8-11p against R_3 and R_6 and reproduce exactly.
                              -- The rule is not "prime is midnight", it is that
                              -- these two families of query use different ones.
SET p_fiscal_year   = NULL;
SET p_win_to        = NULL;                -- NULL = as far as the data goes
SET p_movies        = 'EXCLUDE';  -- [MOVIES] 'EXCLUDE' | 'ONLY' | 'BOTH'
                                  -- A&E, week 10, reported as fatal: a hard
                                  -- MOVIE_IND = 0 deletes the answer to any
                                  -- question about Lifetime, because Lifetime's
                                  -- premiere slate IS movies. Excluding them is
                                  -- right for a series question and wrong for a
                                  -- movie one, which makes it a parameter rather
                                  -- than a rule.
                                  -- EXCLUDE keeps the behaviour every validated
                                  -- series case was measured under.
-- [CAP-SUN] window end = latest full Sunday with data, read from CRIS_LATEST_DATE (no MAX over the fact table).
SET data_max = (SELECT MAX(LATEST_FULL_SUNDAY) FROM AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE
                WHERE RATING_SOURCE = $p_stream);
SET fy = (SELECT COALESCE($p_fiscal_year,
            (SELECT MAX(FISCAL_YEAR) FROM AUDIENCE_DEV_DB.CRIS.CRIS_FY_CALENDAR
             WHERE FY_START <= $data_max)));
SET win_from = (SELECT FY_START FROM AUDIENCE_DEV_DB.CRIS.CRIS_FY_CALENDAR WHERE FISCAL_YEAR = $fy);
SET win_to   = (SELECT LEAST(COALESCE(TO_DATE($p_win_to), $data_max), $data_max));


-- [DEMOUSED] resolve p_demo to a real column name and return it with the answer.
-- DEMO_AA is a real column carrying each network's own key demo, so a query runs
-- on it and never states what it measured. Read back, "DEMO_AA" tells a consumer
-- nothing: it is P25-64 on AEN, HIST and FYI, F25-64 on LIF and LMN, P18-49 on
-- VICE. SP_3 and SP_6 both failed on that - the question asked for P25+, the
-- default answered on P25-64, and 242 came back where 438 was expected. A wrong
-- demo does not look wrong, it looks like a number.
SET demo_used = (SELECT UPPER(COALESCE($p_demo,
                     'DEMO_AA - resolves per network, unresolved here because this
                      query has no single network')));

WITH scoped AS (
    SELECT h.NETWORK_CODE, h.PROGRAM_CODE, h.PROGRAM_NAME,
           IDENTIFIER($p_genre_col)                            AS GENRE,
           h.TELECAST_NUM, h.HH_MIN,
           IDENTIFIER($p_demo    )                             AS DEMO
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_HALFHR_FACT h
    JOIN AUDIENCE_DEV_DB.CRIS.CRIS_NETWORK_UNIVERSE u
      ON u.NETWORK_CODE = h.NETWORK_CODE
    WHERE h.RATING_SOURCE = $p_stream
      AND h.BROADCAST_DATE BETWEEN $win_from AND $win_to
      AND h.HH_START_2959 >= $p_dp_from_2959
      AND h.HH_START_2959 <  $p_dp_to_2959
      AND ( ($p_excl_by = 'CODE' AND u.IS_ENT_BY_CODE)
         OR ($p_excl_by = 'NAME' AND u.IS_ENT_BY_NAME) )
      AND ($p_include_specials OR h.CONTENT_TYPE <> 'Special')
      -- [S3-PREMIERES] premieres only, unless asked otherwise
      AND (NOT $p_premieres_only OR h.IS_FIRST_RUN_CT)
      -- [S3-GENRE2] and the second-genre exclusion
      AND ($p_genre_2_exclude IS NULL
           OR h.CT_GENRE_2 IS NULL
           OR UPPER(h.CT_GENRE_2) NOT LIKE UPPER($p_genre_2_exclude))
      AND ( $p_movies = 'BOTH'
         OR ($p_movies = 'EXCLUDE' AND h.MOVIE_IND = 0)
         OR ($p_movies = 'ONLY'    AND h.MOVIE_IND = 1) )
),
per_telecast AS (
    -- the telecast's delivery INSIDE the daypart, which is what the PRD asks
    -- for: "Compute Telecast AA Impressions inside 8-11p"
    SELECT NETWORK_CODE, PROGRAM_CODE, TELECAST_NUM,
           MAX(PROGRAM_NAME) AS PROGRAM_NAME,
           MAX(GENRE)        AS GENRE,
           SUM(DEMO * HH_MIN) / NULLIF(SUM(HH_MIN), 0) AS TELECAST_AA,
           SUM(HH_MIN)       AS MINUTES
    FROM scoped
    GROUP BY NETWORK_CODE, PROGRAM_CODE, TELECAST_NUM
),
per_series AS (
    -- [S1-KEY] grouped on network and PROGRAM_CODE: the PRD is explicit that the
    -- same series on two networks must not merge, and the code carries that for
    -- free where a name would not.
    SELECT NETWORK_CODE, PROGRAM_CODE,
           MAX(PROGRAM_NAME)   AS PROGRAM_NAME,
           MAX(GENRE)          AS GENRE,
           COUNT(*)            AS TELECASTS,
           -- [S3-WEIGHT] weighted by minutes, not a plain average of telecast
           -- averages. A series whose telecasts run 60 and 125 minutes is not
           -- described by treating both as one vote.
           --
           -- This was the last figure gap on R_1 and it isolates cleanly. Curse
           -- of Oak Island over 25 telecasts and 1,637 minutes, the same count
           -- and the same duration A&E print:
           --
           --     simple average of telecast averages   528.2
           --     weighted by minutes                   524.0
           --     A&E                                   524
           --
           -- The programmes that already matched are the ones whose telecasts
           -- are all the same length, where the two methods agree: Storage Wars,
           -- World War II, Hazardous History. Curse mixes 60 and 125 minute
           -- episodes and that is where they separate.
           --
           -- per_telecast above already weights this way to roll half hours into
           -- a telecast. This is the same weighting one level up, and 3.1 and
           -- 3.2 have always done it. 3.3 was the only ranker averaging flat.
           SUM(TELECAST_AA * MINUTES)
             / NULLIF(SUM(MINUTES), 0)  AS SERIES_AA,
           SUM(MINUTES)        AS MINUTES
    FROM per_telecast
    GROUP BY NETWORK_CODE, PROGRAM_CODE
    -- [S3-FLOOR] no minimum telecast count. There is no such rule. The floor of
    -- three was carried here crediting the PRD, and the PRD does not contain it;
    -- neither does any check-in note. Dropping a two-telecast series from a
    -- ranker is an editorial decision about what counts as a series, made
    -- silently. If A&E wants a floor it comes back with their name on it.
    HAVING ($p_genre IS NULL OR MAX(GENRE) ILIKE $p_genre)
       AND ($p_min_tcasts IS NULL OR COUNT(*) >= $p_min_tcasts)   -- [MINTC]
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    -- [R1-NORANK] The competitive-set rank is computed but not returned. A&E,
    -- 10 Sep 2026: a ranker asked for within a network reports the rank within
    -- that network. p_top_n still cuts on it, so it stays in the QUALIFY.
    RANK() OVER (PARTITION BY NETWORK_CODE
                 ORDER BY ROUND(SERIES_AA/1000, 0) DESC)       AS RNK_IN_NETWORK,
    PROGRAM_NAME    AS PROGRAM,
    NETWORK_CODE    AS NETWORK,
    GENRE,
    TELECASTS,
    MINUTES,
    ROUND(SERIES_AA/1000, 0)                                   AS AA_000,
    $p_demo     AS DEMO, $p_stream AS STREAM,
    $win_from AS FROM_DATE, $win_to AS TO_DATE,
    $p_excl_by AS EXCLUSION_LIST
FROM per_series
-- RANK() and not ROW_NUMBER(): A&E's sheet puts SISTER WIVES and SUDDENLY AMISH
-- both at #12 on 434 and resumes at #14. QUALIFY on the rank, not on a row
-- number, so a tie at the boundary returns both rows rather than one of them.
--
-- [S3-FOCUS] three ways to narrow and each one optional, so the caller gets a
-- short answer whichever way the question was asked:
--
--   top 20 of cable      top_n 20,  focus NULL,          per_network NULL   20 rows
--   R_1, 3 per network   top_n NULL, focus AEN,HIST,LIF, per_network 3       8 rows
--   where do mine rank   top_n NULL, focus HIST,         per_network NULL   40 rows
--   one programme        top_n NULL, focus HIST,         plus p_genre         1 row
--
-- None of them changes the ranking. RNK_IN_NETWORK is always the position
-- inside one network; these only decide which rows come back.
QUALIFY ($p_top_n IS NULL
         OR RANK() OVER (ORDER BY ROUND(SERIES_AA/1000, 0) DESC) <= $p_top_n)
    AND ($p_focus_networks IS NULL
         OR ARRAY_CONTAINS(NETWORK_CODE::VARIANT, SPLIT($p_focus_networks, ',')))
    AND ($p_per_network IS NULL OR RNK_IN_NETWORK <= $p_per_network)
ORDER BY NETWORK, RNK_IN_NETWORK, AA_000 DESC, PROGRAM;