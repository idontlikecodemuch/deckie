-- Makes engine-m.db, a stand-in for Engine DJ's Engine Library/Database2/m.db (its Track table's columns as the
-- open-source endjine crate lists them, the ones Deckie reads and a few more), for SQLiteReader and the Engine DJ
-- reader's tests: 512-byte pages so the table spans interior pages, a title long enough to overflow, an
-- INTEGER PRIMARY KEY (the rowid), and a column added by ALTER TABLE after the first rows.
--   rm -f engine-m.db && sqlite3 engine-m.db < engine-m.sql
PRAGMA page_size = 512;
PRAGMA journal_mode = DELETE;
CREATE TABLE Information (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, schemaVersionMajor INTEGER, schemaVersionMinor INTEGER);
INSERT INTO Information (uuid, schemaVersionMajor, schemaVersionMinor) VALUES ('test-uuid', 2, 18);
CREATE TABLE Track (id INTEGER PRIMARY KEY AUTOINCREMENT, playOrder INTEGER, length INTEGER, bpm INTEGER, year INTEGER,
  path TEXT, filename TEXT, bitrate INTEGER, bpmAnalyzed REAL, albumArtId INTEGER, fileBytes INTEGER, title TEXT,
  artist TEXT, album TEXT, genre TEXT, comment TEXT, label TEXT, composer TEXT, remixer TEXT, key INTEGER,
  rating INTEGER, CONSTRAINT C_path UNIQUE (path));
INSERT INTO Track (path, filename, fileBytes, title, artist, key, bpmAnalyzed) VALUES
  ('../Music/House/01 Song A.mp3', '01 Song A.mp3', 123456, 'Song A', 'Artist A', 1, 124.0),
  ('../Music/House/02 Song B.mp3', '02 Song B.mp3', 223456, 'Song B', 'Artist B', 0, 125.5),
  ('/Volumes/Stick/Set/Song C.flac', 'Song C.flac', 323456, NULL, NULL, 23, 120.0);
WITH RECURSIVE n(i) AS (SELECT 4 UNION ALL SELECT i + 1 FROM n WHERE i < 60)
INSERT INTO Track (path, filename, fileBytes, title, artist, key, bpmAnalyzed)
  SELECT '../Music/Filler/' || i || '.mp3', i || '.mp3', i * 1000, 'Filler ' || i, 'Nobody', i % 24, -1.5 * i FROM n;
INSERT INTO Track (path, filename, fileBytes, title, artist, key) VALUES
  ('../Music/Long/long.mp3', 'long.mp3', 999, 'A title long enough to spill past its page: ' || hex(zeroblob(400)), 'Long', 7);
ALTER TABLE Track ADD COLUMN lastEditTime DATETIME;
INSERT INTO Track (path, filename, fileBytes, title, artist, key, lastEditTime) VALUES
  ('../Music/New/new.mp3', 'new.mp3', 5, 'Newer', 'Late', 12, '2026-11-13 10:00:00');
