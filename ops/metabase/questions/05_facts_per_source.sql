-- Facts per source
SELECT s.url, s.source_kind, count(e.id) AS facts,
  count(DISTINCT e.subject_type || ':' || e.subject_id) AS records
FROM sources s
LEFT JOIN evidence e ON e.source_id = s.id
GROUP BY s.id, s.url, s.source_kind
ORDER BY facts DESC, s.url;
