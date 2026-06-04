alter table public.site_alerts
add column if not exists acknowledged_at timestamptz,
add column if not exists acknowledged_by uuid references auth.users(id) on delete set null;

