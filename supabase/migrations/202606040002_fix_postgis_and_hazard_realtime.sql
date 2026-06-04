create extension if not exists postgis with schema extensions;

do $$
declare
  spatial_ref_table regclass;
begin
  spatial_ref_table := to_regclass('extensions.spatial_ref_sys');
  if spatial_ref_table is null then
    spatial_ref_table := to_regclass('public.spatial_ref_sys');
  end if;

  if spatial_ref_table is null then
    raise exception 'PostGIS spatial_ref_sys table was not found.';
  end if;

  execute format(
    'insert into %s (srid, auth_name, auth_srid, srtext, proj4text)
     values ($1, $2, $3, $4, $5)
     on conflict (srid) do nothing',
    spatial_ref_table
  )
  using
    4326,
    'EPSG',
    4326,
    'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4326"]]',
    '+proj=longlat +datum=WGS84 +no_defs';
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'hazards'
  ) then
    alter publication supabase_realtime add table public.hazards;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'assign_hazards'
  ) then
    alter publication supabase_realtime add table public.assign_hazards;
  end if;
end $$;
