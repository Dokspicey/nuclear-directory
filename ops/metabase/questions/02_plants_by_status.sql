-- Plants and units by status
-- A site is a plant (its own page); a unit sits under one.
SELECT CASE WHEN parent_id IS NULL THEN 'plant' ELSE 'unit' END AS level,
  verification_status AS status, count(*) AS records
FROM facilities
GROUP BY 1, 2
ORDER BY 1, 3 DESC;
