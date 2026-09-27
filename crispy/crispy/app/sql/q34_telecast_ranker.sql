/* ============================================================================
   FILE       3.4  TELECAST-LEVEL RANKERS                           (PRD 3.4)
   PURPOSE    The top individual telecasts across TV or cable for a window and a
              daypart, with episode names and a premiere indicator.
   SOURCE     CRIS_TELECAST_FACT [S3-T2] for the telecasts,
              CRIS_HALFHR_FACT [S2-T1] to decide daypart membership,
              CRIS_NETWORK_UNIVERSE [S3-T0] for the universe
   VALIDATION ACHIEVED in v6, Jul-08: set 10/10, 8 exact ranks, one adjacent swap
              at #6/#7 traced to a single -76 drift on NFL DRAFT ON ABC, and the
              span rule proven by the 6:08p game.
              Top 10 telecasts, prime, 2026-04-20 to 2026-04-26, Live+SD, P25-64:
                 #1 NFL DRAFT (ESPN)   P25-64 4,263   P2+ 6,533
                 #4 TRACKER  (CBS)     P25-64 2,678   P2+ 8,174
              TRACKER being #4 on P25-64 and #1 on P2+ is why the per-demo ranks
              below are not decoration.
   [S3-TV]    THE UNIVERSE HERE IS THE OPPOSITE OF 3.1 AND 3.2. News, sports and
              diginets are INCLUDED, confirmed by A&E. NFL DRAFT on ESPN is the
              #1 row of the validated answer, and ESPN is excluded from every
              other ranker in this section.
   [S3-SPAN]  Inclusion is by telecast, not by minute: a telecast counts if it
              starts during prime, ends during prime, or spans it. That is the
              opposite of the strict dayparting 3.1 and 3.2 use, and the AA
              reported is the telecast's whole delivery, untrimmed. Membership is
              decided by asking whether the telecast has any half hour inside the
              window, which covers all three cases at once and needs no
              arithmetic on end times that cross midnight.
   ============================================================================ */
-- [MERGE] CRIS_TELECAST_ALL_NET is gone. It existed to hold every network while
-- CRIS_TELECAST_FACT was filtered to the six; the filter is removed, so the two
-- were the same rows and one of them was dropped.

-- ===== PARAMETERS =====
SET p_top_n         = 20;
SET p_universe      = 'TV';        -- 'TV' = broadcast + cable, 'CABLE' = cable only
SET p_stream        = 'Live+SD';
SET p_demo          = 'P25_64_AA_ESTIMATES';
SET p_dp_from_2959  = 2000;        -- prime M-Su 8-11p
SET p_dp_to_2959    = 2300;
SET p_win_from      = NULL;        -- NULL = the last completed Monday-Sunday week
SET p_win_to        = NULL;
-- [CAP-SUN] window end = latest full Sunday with data, read from CRIS_LATEST_DATE (no MAX over the fact table).
SET data_max = (SELECT MAX(LATEST_FULL_SUNDAY) FROM AUDIENCE_DEV_DB.CRIS.CRIS_LATEST_DATE
                WHERE RATING_SOURCE = $p_stream);
SET last_sun = $data_max;
SET win_to   = (SELECT LEAST(COALESCE(TO_DATE($p_win_to), $last_sun), $last_sun));
SET win_from = (SELECT COALESCE(TO_DATE($p_win_from), DATEADD('day', -6, $win_to)));


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

WITH in_daypart AS (
    -- [S3-SPAN] a telecast qualifies if ANY of its half hours falls inside the
    -- window. Starts during, ends during and spans are all the same test once
    -- it is asked this way, and none of them needs end-time arithmetic.
    SELECT DISTINCT NETWORK_CODE, RATING_SOURCE, BROADCAST_DATE,
                    PROGRAM_CODE, TELECAST_NUM
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_HALFHR_FACT
    WHERE RATING_SOURCE = $p_stream
      AND BROADCAST_DATE BETWEEN $win_from AND $win_to
      AND HH_START_2959 >= $p_dp_from_2959
      AND HH_START_2959 <  $p_dp_to_2959
),
telecasts AS (
    SELECT t.NETWORK_CODE, t.BROADCAST_DATE, t.DAY_OF_WEEK,
           t.PROGRAM_NAME, t.EPISODE_NAME,
           t.START_TIME, t.END_TIME, t.BCAST_START_2959,
           t.EVENT_DURATION, t.IS_FIRST_RUN_CT, t.IS_PREMIERE_CT,
           t.MEDIAN_AGE,
           IDENTIFIER($p_demo    )  AS DEMO,
           t.P2_AA_ESTIMATES, t.P25_64_AA_ESTIMATES,
           t.F2_AA_ESTIMATES, t.M2_AA_ESTIMATES
    FROM AUDIENCE_DEV_DB.CRIS.CRIS_TELECAST_FACT t
    JOIN in_daypart d
      ON  d.NETWORK_CODE   = t.NETWORK_CODE
      AND d.RATING_SOURCE  = t.RATING_SOURCE
      AND d.BROADCAST_DATE = t.BROADCAST_DATE
      AND d.PROGRAM_CODE   = t.PROGRAM_CODE
      AND d.TELECAST_NUM   = t.TELECAST_NUM
    JOIN AUDIENCE_DEV_DB.CRIS.CRIS_NETWORK_UNIVERSE u
      ON u.NETWORK_CODE = t.NETWORK_CODE
    WHERE t.RATING_SOURCE = $p_stream
      AND t.BROADCAST_DATE BETWEEN $win_from AND $win_to
      AND NOT u.IS_ARTIFACT
      -- [S3-TV] news, sports and diginets stay IN
      AND ( $p_universe = 'TV' OR ($p_universe = 'CABLE' AND u.IS_CABLE) )
)
SELECT
    REPLACE($demo_used, '_AA_ESTIMATES', '') AS DEMO_USED,   -- [DEMOUSED]
    RANK() OVER (ORDER BY ROUND(DEMO/1000, 0) DESC)            AS RNK,
    NETWORK_CODE    AS NETWORK,
    PROGRAM_NAME    AS PROGRAM,
    EPISODE_NAME    AS EPISODE,
    BROADCAST_DATE  AS AIR_DATE,
    DAY_OF_WEEK     AS DAY,
    START_TIME, END_TIME, EVENT_DURATION,
    IFF(NOT IS_FIRST_RUN_CT, 'R', 'P')                              AS PREMIERE_REPEAT,
    IFF(IS_PREMIERE_CT = 1, 'SEASON PREMIERE', NULL)       AS SEASON_PREMIERE,
    ROUND(DEMO/1000, 0)                                        AS AA_000,
    -- per-demo ranks: TRACKER is #4 on P25-64 and #1 on P2+, so a single rank
    -- would misreport the week
    RANK() OVER (ORDER BY ROUND(P25_64_AA_ESTIMATES/1000, 0) DESC) AS RNK_P25_64,
    ROUND(P25_64_AA_ESTIMATES/1000, 0)                         AS P25_64_000,
    RANK() OVER (ORDER BY ROUND(P2_AA_ESTIMATES/1000, 0) DESC) AS RNK_P2,
    ROUND(P2_AA_ESTIMATES/1000, 0)                             AS P2_000,
    ROUND(MEDIAN_AGE, 0)                                       AS MEDIAN_AGE,
    ROUND(100.0 * F2_AA_ESTIMATES
          / NULLIF(P2_AA_ESTIMATES, 0), 0)                     AS FEMALE_PCT,
    $p_universe AS UNIVERSE, $p_stream AS STREAM,
    $win_from AS WEEK_FROM, $win_to AS WEEK_TO,
    $win_from               AS FROM_DATE,
    $win_to                 AS TO_DATE
FROM telecasts
QUALIFY RNK <= $p_top_n
ORDER BY RNK;