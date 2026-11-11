-- LAB 1 START | Login: Studio SQL Editor (postgres), or compose exec db psql.
-- Run this entire file. This database belongs only to the Supabase lab.
BEGIN;

CREATE TABLE IF NOT EXISTS public.claimsure_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_no text UNIQUE NOT NULL,
  branch text NOT NULL CHECK (branch IN ('BKK', 'CM')),
  adjuster_id uuid NOT NULL REFERENCES auth.users(id),
  amount numeric(12,2) NOT NULL CHECK (amount >= 0),
  status text NOT NULL DEFAULT 'NEW'
    CHECK (status IN ('NEW', 'REVIEW', 'APPROVED')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS claimsure_claims_adjuster_idx
  ON public.claimsure_claims(adjuster_id);

ALTER TABLE public.claimsure_claims ENABLE ROW LEVEL SECURITY;

-- anon can SELECT, but has no applicable RLS policy: it receives zero rows.
-- Table privileges and RLS policies are separate permission checks.
REVOKE ALL ON public.claimsure_claims FROM anon, authenticated;
GRANT SELECT ON public.claimsure_claims TO anon;
GRANT SELECT, INSERT, UPDATE ON public.claimsure_claims TO authenticated;
GRANT ALL ON public.claimsure_claims TO service_role;

DROP POLICY IF EXISTS claims_read_own ON public.claimsure_claims;
CREATE POLICY claims_read_own ON public.claimsure_claims
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = adjuster_id);

DROP POLICY IF EXISTS claims_insert_own ON public.claimsure_claims;
CREATE POLICY claims_insert_own ON public.claimsure_claims
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = adjuster_id);

DROP POLICY IF EXISTS claims_update_own ON public.claimsure_claims;
CREATE POLICY claims_update_own ON public.claimsure_claims
  FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = adjuster_id)
  WITH CHECK ((SELECT auth.uid()) = adjuster_id);

COMMENT ON TABLE public.claimsure_claims IS
  'Synthetic ClaimSure tutorial: each authenticated adjuster accesses only their own claims.';

COMMIT;
NOTIFY pgrst, 'reload schema';
-- LAB 1 END | Rerunnable. No demo users or claims are created by this file.
