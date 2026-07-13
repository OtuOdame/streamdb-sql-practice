# streamdb — Analytical SQL Practice

A self-contained MySQL 8+ practice database modelling a small music-streaming
service, built to drill **analytical SQL**: from `GROUP BY` aggregation through
conditional aggregation, CTEs, and window functions.

The data is synthetic — 15 artists, 72 tracks, 40 users, and 1,500 play events
across April–June 2025.

## Schema

Four tables in a simple star-ish shape, with `plays` as the fact table:

| Table     | Grain                    | Key columns                                        |
|-----------|--------------------------|----------------------------------------------------|
| `artists` | one row per artist       | `artist_id`, `name`, `country`                     |
| `tracks`  | one row per track        | `track_id`, `artist_id` → artists, `genre`, `duration_ms` |
| `users`   | one row per listener     | `user_id`, `country`, `tier`, `signup_date`        |
| `plays`   | one row per play event   | `play_id`, `user_id` → users, `track_id` → tracks, `played_at`, `ms_played` |

## Running it

Run the files in order (each starts with `USE streamdb;` except the schema,
which creates the database):

```bash
mysql -u root -p < 01_schema.sql
mysql -u root -p < 02_seed_data.sql
mysql -u root -p < 03_queries.sql
```

Or paste them into MySQL Workbench in the same order.

## What each query demonstrates

| #   | Question it answers                                   | Technique                                             |
|-----|-------------------------------------------------------|-------------------------------------------------------|
| Q1  | Plays and minutes listened per genre                  | `GROUP BY`, `SUM`/`COUNT`                             |
| Q2  | Plays, distinct tracks & distinct listeners per artist| `COUNT(DISTINCT)` over a fan-out join                 |
| Q3  | Why `COUNT` ≠ `COUNT(DISTINCT)` after a join          | Deliberate fan-out-bug demo                          |
| Q4  | Distinct played tracks per genre                       | `COUNT(DISTINCT)`                                     |
| Q5  | Completion rate per genre (≥80% of track heard)       | Conditional aggregation (`CASE` → `AVG`)             |
| Q6  | Completion rate per artist, min 30 plays              | `HAVING` (post-aggregation filter)                   |
| Q7  | Plays per track                                        | `GROUP BY` (feeds Q8)                                 |
| Q8  | Top 3 tracks within each genre                        | `RANK() OVER (PARTITION BY … ORDER BY …)`, CTEs      |
| Q9  | Daily plays with a running total                      | `SUM() OVER` (cumulative window frame)               |
| Q10 | Day-over-day change and % change                      | `LAG()`, `NULLIF` guard                              |
| Q11 | 7-day moving average of daily plays                   | `AVG() OVER (… ROWS 6 PRECEDING)`                    |
| Q12 | Users bucketed into listening-time quartiles          | `NTILE(4)`                                            |
| Q13 | Users and minutes per quartile                        | `NTILE` in a CTE, then aggregate                     |

## Notes

- `ms_played` is the milliseconds actually listened; a play is treated as
  "completed" when `ms_played >= 0.8 * duration_ms`.
- Window frames in Q9/Q11 are **row-based**, so results assume dense daily data;
  a date with zero plays would be absent rather than zero.
