-- AI spend by month
-- Same rule as the budget guard (DataQuality::Budget): calls count in the
-- month they were made; runs from before by_month existed count by start month.
WITH usage AS (
  SELECT m.key AS month, (m.value ->> 'calls')::int AS calls, (m.value ->> 'total_tokens')::bigint AS tokens,
    (m.value ->> 'cost')::numeric AS cost
  FROM crawl_runs, jsonb_each(stats -> 'llm' -> 'by_month') AS m
  UNION ALL
  SELECT to_char(started_at, 'YYYY-MM'), (stats -> 'llm' ->> 'calls')::int, (stats -> 'llm' ->> 'total_tokens')::bigint,
    (stats -> 'llm' ->> 'cost')::numeric
  FROM crawl_runs
  WHERE stats -> 'llm' IS NOT NULL AND stats -> 'llm' -> 'by_month' IS NULL
)
SELECT month, sum(calls) AS calls, sum(tokens) AS tokens, round(sum(cost), 4) AS cost_usd
FROM usage
GROUP BY month
ORDER BY month DESC;
