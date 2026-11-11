-- LAB 3 START | Login: Studio SQL Editor (postgres), after Lab 2 Auth users exist.
-- Default demo emails match .env.example. The helper adapts these two emails
-- when DEMO_BKK_EMAIL / DEMO_CM_EMAIL are customized in the private .env.
BEGIN;

DO $$
BEGIN
  IF (SELECT count(*) FROM auth.users
      WHERE email IN ('adjuster.bkk@claimsure.example.com',
                      'adjuster.cm@claimsure.example.com')) <> 2 THEN
    RAISE EXCEPTION 'Create both confirmed Auth demo users in Lab 2 first';
  END IF;
END $$;

INSERT INTO public.claimsure_claims
  (claim_no, branch, adjuster_id, amount, status)
SELECT v.claim_no, v.branch, u.id, v.amount, v.status
FROM (VALUES
  ('CLM-BKK-001', 'BKK', 'adjuster.bkk@claimsure.example.com', 12500.00, 'NEW'),
  ('CLM-BKK-002', 'BKK', 'adjuster.bkk@claimsure.example.com', 28000.00, 'REVIEW'),
  ('CLM-CM-001',  'CM',  'adjuster.cm@claimsure.example.com',  8900.00, 'NEW'),
  ('CLM-CM-002',  'CM',  'adjuster.cm@claimsure.example.com', 16500.00, 'APPROVED')
) AS v(claim_no, branch, email, amount, status)
JOIN auth.users u ON u.email = v.email
ON CONFLICT (claim_no) DO UPDATE SET
  branch = EXCLUDED.branch,
  adjuster_id = EXCLUDED.adjuster_id,
  amount = EXCLUDED.amount,
  status = EXCLUDED.status;

SELECT claim_no, branch, amount, status
FROM public.claimsure_claims ORDER BY claim_no;

COMMIT;
ANALYZE auth.users;
ANALYZE public.claimsure_claims;
-- LAB 3 END | Expected: 4 synthetic claims. SQL Editor runs as an admin;
-- seeing all four rows here does not prove that application RLS works.
