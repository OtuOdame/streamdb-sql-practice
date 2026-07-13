-- ================================================================
-- streamdb : practice DB for GROUP BY, CTEs & window functions
-- MySQL 8+  |  Paste into Workbench and run.
-- ================================================================
DROP DATABASE IF EXISTS streamdb;
CREATE DATABASE streamdb;
USE streamdb;

CREATE TABLE artists (
    artist_id INT PRIMARY KEY,
    name      VARCHAR(80) NOT NULL,
    country   VARCHAR(60)
);

CREATE TABLE tracks (
    track_id    INT PRIMARY KEY,
    title       VARCHAR(120) NOT NULL,
    artist_id   INT NOT NULL,
    genre       VARCHAR(40),
    duration_ms INT NOT NULL,
    FOREIGN KEY (artist_id) REFERENCES artists(artist_id)
);

CREATE TABLE users (
    user_id      INT PRIMARY KEY,
    display_name VARCHAR(60) NOT NULL,
    country      VARCHAR(60),
    tier         VARCHAR(10),          -- 'Free' or 'Premium'
    signup_date  DATE
);

CREATE TABLE plays (
    play_id   INT PRIMARY KEY,
    user_id   INT NOT NULL,
    track_id  INT NOT NULL,
    played_at DATETIME NOT NULL,
    ms_played INT NOT NULL,           -- milliseconds actually listened
    FOREIGN KEY (user_id)  REFERENCES users(user_id),
    FOREIGN KEY (track_id) REFERENCES tracks(track_id)
);
