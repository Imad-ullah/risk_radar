create or replace function public.set_user_location_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = statement_timestamp();
  return new;
end;
$$;

drop trigger if exists set_user_location_updated_at
  on public.user_locations;

create trigger set_user_location_updated_at
before insert or update on public.user_locations
for each row
execute function public.set_user_location_updated_at();

update public.user_locations
set updated_at = statement_timestamp()
where updated_at > statement_timestamp();
