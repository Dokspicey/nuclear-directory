-- Companies by status
SELECT verification_status AS status, count(*) AS companies
FROM organizations
GROUP BY verification_status
ORDER BY companies DESC;
