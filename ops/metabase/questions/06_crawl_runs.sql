-- Crawl runs by day
SELECT started_at::date AS day, source_kind, stage, status, count(*) AS runs,
  round(avg(extract(epoch FROM finished_at - started_at)))::int AS avg_seconds
FROM crawl_runs
GROUP BY 1, 2, 3, 4
ORDER BY day DESC, source_kind, stage, status;
