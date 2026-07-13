-- ================================================================
-- streamdb : analytical queries
-- Run 01_schema.sql and 02_seed_data.sql first, then this file.
-- ================================================================
USE streamdb;

-- ================================================================
-- ANALYTICAL QUERIES
-- Each block is annotated with what it answers + the key technique.
-- ================================================================

-- Q1 | Genre popularity: total plays and total minutes listened per genre.
--      Plain GROUP BY aggregation over the plays -> tracks join.
--      (ms_played / 60000 is fractional in MySQL, so SUM then ROUND gives minutes.)
SELECT genre, COUNT(*) AS total_plays,
	ROUND(SUM(ms_played / 60000)) AS total_minutes
FROM plays p
JOIN tracks t ON p.track_id = t.track_id
GROUP BY genre
ORDER BY total_plays DESC;

-- Q2 | Artist leaderboard: plays, distinct tracks, and distinct listeners per artist.
--      The joins fan out to one row per play; COUNT(DISTINCT ...) collapses that
--      back to true track/listener counts.
SELECT a.name, COUNT(p.track_id) AS total_plays, COUNT(DISTINCT t.track_id) AS track_count, COUNT(DISTINCT p.user_id) AS distinct_listeners
FROM artists a 
JOIN tracks t ON a.artist_id = t.artist_id
JOIN plays p ON t.track_id = p.track_id
GROUP BY name
ORDER BY total_plays DESC;

-- Q3 | DELIBERATE demo of a classic bug: COUNT() over a fan-out join counts JOINED ROWS
--      (i.e. plays), not tracks. join_rows vs distinct_tracks makes the gap visible.
SELECT a.name,
       COUNT(t.track_id)          AS join_rows,       -- one row per play after the fan-out
       COUNT(DISTINCT t.track_id) AS distinct_tracks  -- the real track count
FROM artists a
JOIN tracks t ON a.artist_id = t.artist_id
JOIN plays  p ON t.track_id  = p.track_id
GROUP BY a.name;

-- Q4 | Distinct tracks that have been played, per genre.
--      COUNT(DISTINCT t.track_id) counts unique tracks (not plays) despite the fan-out.
--      NB: joining to plays means this only counts tracks with >= 1 play; query the
--      tracks table alone if you want every track in the catalogue per genre.
SELECT t.genre, COUNT(DISTINCT t.track_id) AS tracks_played_per_genre
FROM tracks t
JOIN plays p ON t.track_id = p.track_id
GROUP BY genre;

-- Q5 | Completion rate per genre: a play "completes" when >= 80% of the track was heard.
--      CASE builds a 1/0 flag; AVG of that 1/0 = the proportion completed (the rate).
SELECT t.genre,
	COUNT(*) AS total_plays,
    SUM(CASE WHEN p.ms_played >= 0.8 * t.duration_ms THEN 1 ELSE 0 END) AS completed_plays,
    ROUND(
		AVG(CASE WHEN p.ms_played >= 0.8 * t.duration_ms THEN 1 ELSE 0 END),
        3
    ) AS completion_rate
FROM plays p
JOIN tracks t ON p.track_id = t.track_id
GROUP BY genre
ORDER BY completion_rate DESC;

-- Q6 | Same completion rate, per artist, only for artists with >= 30 plays.
--      HAVING filters AFTER aggregation (WHERE can't see COUNT(*); HAVING can).
SELECT a.name,
	COUNT(*) AS total_plays,
    ROUND(
		AVG(CASE WHEN p.ms_played >= 0.8 * t.duration_ms THEN 1 ELSE 0 END),
        3
    ) AS completion_rate
FROM artists a
JOIN tracks t ON a.artist_id = t.artist_id
JOIN plays p ON t.track_id = p.track_id
GROUP BY name
HAVING COUNT(*) >= 30
ORDER BY completion_rate DESC;

-- Q7 | Plays per track: the raw per-track counts that feed the ranking in Q8.
SELECT t.track_id, t.title, t.genre,
	COUNT(*) AS plays
FROM tracks t
JOIN plays p ON t.track_id = p.track_id
GROUP BY t.track_id, t.title, t.genre;

-- Q8 | Top 3 tracks within each genre.
--      CTE #1 counts plays per track; CTE #2 uses RANK() OVER (PARTITION BY genre
--      ORDER BY plays DESC) to rank inside each genre; outer query keeps rank <= 3.
--      RANK() leaves gaps on ties (1,1,3) -> a genre can return >3 rows on ties.
WITH track_plays AS (
	SELECT t.track_id, t.title, t.genre,
		COUNT(*) AS plays
	FROM tracks t
    JOIN plays p ON t.track_id = p.track_id
    GROUP BY t.track_id, t.title, t.genre
), ranked AS (
	SELECT title, genre, plays,
		RANK() OVER (PARTITION BY genre ORDER BY plays DESC) AS genre_rank
	FROM track_plays
)
SELECT genre, title, plays, genre_rank
FROM ranked
WHERE genre_rank <= 3
ORDER BY genre, genre_rank;

-- Q9 | Daily plays with a running (cumulative) total.
--      SUM() OVER (ORDER BY day ROWS UNBOUNDED PRECEDING -> CURRENT ROW) = running sum.
WITH daily AS (
	SELECT DATE(played_at) AS play_day,
		COUNT(*) AS plays
	FROM plays
    GROUP BY DATE(played_at)
)
SELECT play_day, plays,
	SUM(plays) OVER (
		ORDER BY play_day
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total
FROM daily
ORDER BY play_day;

-- Q10 | Day-over-day change in plays.
--       LAG() pulls the previous day's value; subtract for the delta, then divide
--       (NULLIF guards against divide-by-zero) for the percentage change.
WITH daily AS (
	SELECT DATE(played_at) as play_day,
		COUNT(*) AS plays
	FROM plays
    GROUP BY DATE(played_at)
)
SELECT play_day, plays,
	LAG(plays) OVER (ORDER BY play_day) AS prev_day_plays,
    plays - LAG(plays) OVER (ORDER BY play_day) AS day_change,
    ROUND (
		(plays - LAG(plays) OVER (ORDER BY play_day))
        / NULLIF(LAG(plays) OVER (ORDER BY play_day), 0) * 100,
        1
    ) AS pct_change
FROM daily
ORDER BY play_day;

-- Q11 | 7-day moving average of daily plays.
--       AVG() OVER (... ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) = today + prior 6 ROWS.
--       Note: it's 7 *rows*, not 7 *calendar days* — any date with zero plays is absent,
--       so a gap would let the window reach back further than a week.
WITH daily AS (
	SELECT DATE(played_at) AS play_date, 
		COUNT(*) AS plays
	FROM plays
    GROUP BY DATE(played_at)
)
SELECT play_date, plays,
	ROUND(
		AVG(plays) OVER (ORDER BY play_date
			ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ),
        1
    ) AS moving_avg_7d
FROM daily
ORDER BY play_date;


-- Q12 | Bucket users into 4 listening-time quartiles by total ms played.
--       NTILE(4) OVER (ORDER BY total_ms) splits users into 4 equal-sized groups;
--       quartile 1 = lightest listeners, quartile 4 = heaviest.
WITH user_totals AS (
	SELECT u.user_id, u.display_name,
		SUM(p.ms_played) AS total_ms
	FROM users u
    JOIN plays p ON u.user_id = p.user_id
    GROUP BY u.user_id, u.display_name
)
SELECT user_id, display_name,
	ROUND(total_ms / 60000, 1) AS total_minutes,
    NTILE(4) OVER (ORDER BY total_ms) AS quartile
FROM user_totals
ORDER by total_ms;


-- Q13 | Summarise those quartiles: how many users and how many total minutes per bucket.
--       NTILE is assigned in a CTE first, then aggregated by quartile (you can't GROUP BY
--       a window function in the same SELECT that defines it).
WITH user_totals AS (
    SELECT u.user_id, SUM(p.ms_played) AS total_ms
    FROM users u
    JOIN plays p ON u.user_id = p.user_id
    GROUP BY u.user_id
),
bucketed AS (
    SELECT user_id,
           total_ms,
           NTILE(4) OVER (ORDER BY total_ms) AS quartile
    FROM user_totals
)
SELECT quartile,
       COUNT(*) AS num_users,
       ROUND(SUM(total_ms) / 60000, 1) AS total_minutes
FROM bucketed
GROUP BY quartile
ORDER BY quartile;
