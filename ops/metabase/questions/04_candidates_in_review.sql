-- Candidates per run, by status and AI recommendation
-- run: the pipeline run that extracted them; verify_run: the one that checked them.
SELECT crawl_run_id AS run, verify_run_id AS verify_run, kind, status,
  COALESCE(ai_recommendation, '(not checked)') AS ai_recommendation, count(*) AS candidates
FROM candidates
GROUP BY 1, 2, 3, 4, 5
ORDER BY run DESC NULLS LAST, kind, status, candidates DESC;
