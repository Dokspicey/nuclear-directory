-- Candidates by status and AI recommendation
SELECT kind, status, COALESCE(ai_recommendation, '(not checked)') AS ai_recommendation, count(*) AS candidates
FROM candidates
GROUP BY 1, 2, 3
ORDER BY 1, 2, 4 DESC;
