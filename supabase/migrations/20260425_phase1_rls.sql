-- ============================================================================
-- BookMyHospital Phase 1 - RLS placeholder migration
-- NOTE:
-- This file is intentionally a no-op so schema migration can run first.
-- Actual RLS policies are applied in:
--   20260425_phase3_rls_after_schema.sql
-- ============================================================================

do $$
begin
  raise notice 'Skipping early RLS migration. Policies will be applied in phase3 RLS migration.';
end $$;
