-- Power reactor units missing capacity
-- Capacity is stored on units; a power plant with no units counts as its own unit.
SELECT COALESCE(site.name, f.name) AS plant, f.name AS unit, f.nrc_docket, f.verification_status AS status
FROM facilities f
LEFT JOIN facilities site ON site.id = f.parent_id
WHERE COALESCE(f.facility_type, site.facility_type) = 'power_reactor'
  AND f.capacity_mw IS NULL
  AND (f.parent_id IS NOT NULL OR NOT EXISTS (SELECT 1 FROM facilities u WHERE u.parent_id = f.id))
ORDER BY plant, unit;
