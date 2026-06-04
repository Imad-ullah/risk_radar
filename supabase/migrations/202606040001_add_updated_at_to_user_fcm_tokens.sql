alter table public.user_fcm_tokens
add column if not exists updated_at timestamptz not null default now();

