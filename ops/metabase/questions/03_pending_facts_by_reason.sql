-- Pending facts by reason
-- Facts waiting for a human, by kind and the reason on their latest audit
-- event (held-back seed links carry their pending_reason).
SELECT fact, COALESCE(reason, '(no reason recorded)') AS reason, count(*) AS facts
FROM (
  SELECT 'company' AS fact, t.id,
    (SELECT e.reason FROM verification_events e
      WHERE e.subject_type = 'Organization' AND e.subject_id = t.id ORDER BY e.id DESC LIMIT 1) AS reason
  FROM organizations t WHERE t.verification_status = 'pending'
  UNION ALL
  SELECT 'plant' AS fact, t.id,
    (SELECT e.reason FROM verification_events e
      WHERE e.subject_type = 'Facility' AND e.subject_id = t.id ORDER BY e.id DESC LIMIT 1) AS reason
  FROM facilities t WHERE t.verification_status = 'pending'
  UNION ALL
  SELECT 'company role' AS fact, t.id,
    (SELECT e.reason FROM verification_events e
      WHERE e.subject_type = 'OrganizationRole' AND e.subject_id = t.id ORDER BY e.id DESC LIMIT 1) AS reason
  FROM organization_roles t WHERE t.verification_status = 'pending'
  UNION ALL
  SELECT 'company technology' AS fact, t.id,
    (SELECT e.reason FROM verification_events e
      WHERE e.subject_type = 'OrganizationTechnology' AND e.subject_id = t.id ORDER BY e.id DESC LIMIT 1) AS reason
  FROM organization_technologies t WHERE t.verification_status = 'pending'
  UNION ALL
  SELECT 'company link' AS fact, t.id,
    (SELECT e.reason FROM verification_events e
      WHERE e.subject_type = 'Relationship' AND e.subject_id = t.id ORDER BY e.id DESC LIMIT 1) AS reason
  FROM relationships t WHERE t.verification_status = 'pending'
  UNION ALL
  SELECT 'plant link' AS fact, t.id,
    (SELECT e.reason FROM verification_events e
      WHERE e.subject_type = 'FacilityRelationship' AND e.subject_id = t.id ORDER BY e.id DESC LIMIT 1) AS reason
  FROM facility_relationships t WHERE t.verification_status = 'pending'
) pending
GROUP BY fact, reason
ORDER BY facts DESC, fact;
