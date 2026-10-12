-- Sites and units by status
-- A site is a top-level record with its own page (a power plant, mill, mine,
-- fuel plant or test reactor); a unit sits under one.
SELECT CASE WHEN parent_id IS NULL THEN 'site' ELSE 'unit' END AS level,
  verification_status AS status, count(*) AS records
FROM facilities
GROUP BY 1, 2
ORDER BY 1, 3 DESC;
