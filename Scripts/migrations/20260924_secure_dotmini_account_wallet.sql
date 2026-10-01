-- Restrict Supabase PostgREST access to the authenticated owner. The API
-- server connects directly to Postgres and continues to manage plans/credit.
BEGIN;

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gpu_wallets ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON public.users FROM anon, authenticated;
REVOKE ALL PRIVILEGES ON public.gpu_wallets FROM anon, authenticated;

GRANT SELECT ON public.users TO authenticated;
GRANT UPDATE (name, display_name, "displayName") ON public.users TO authenticated;
GRANT SELECT ON public.gpu_wallets TO authenticated;

COMMIT;
