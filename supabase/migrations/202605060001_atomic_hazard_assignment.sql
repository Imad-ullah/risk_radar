create or replace function public.assign_hazard_to_hse(
  p_hazard_id uuid,
  p_assigned_to uuid,
  p_assigned_at timestamptz default now()
)
returns jsonb
language plpgsql
as $$
declare
  hazard_row public.hazards%rowtype;
  assigned_row public.assign_hazards%rowtype;
begin
  select *
    into hazard_row
    from public.hazards
   where id = p_hazard_id
   for update;

  if not found then
    select *
      into assigned_row
      from public.assign_hazards
     where id = p_hazard_id
     for update;

    if found then
      update public.assign_hazards
         set assigned_to = p_assigned_to,
             assigned_at = p_assigned_at,
             status = 'assigned'
       where id = p_hazard_id
       returning * into assigned_row;

      return jsonb_build_object(
        'success', true,
        'status', 'already_assigned',
        'hazard', to_jsonb(assigned_row)
      );
    end if;

    raise exception 'Hazard % was not found for assignment', p_hazard_id
      using errcode = 'P0002';
  end if;

  insert into public.assign_hazards (
    id,
    worker_id,
    hazard_type,
    description,
    severity,
    latitude,
    longitude,
    status,
    created_at,
    image_url,
    orphaned,
    resolved_at,
    ranking_score,
    officer_uid,
    voice_note_url,
    assigned_to,
    assigned_at,
    current_site_id
  )
  values (
    hazard_row.id,
    hazard_row.worker_id,
    hazard_row.hazard_type,
    hazard_row.description,
    hazard_row.severity,
    hazard_row.latitude,
    hazard_row.longitude,
    'assigned',
    hazard_row.created_at,
    hazard_row.image_url,
    hazard_row.orphaned,
    hazard_row.resolved_at,
    hazard_row.ranking_score,
    hazard_row.officer_uid,
    hazard_row.voice_note_url,
    p_assigned_to,
    p_assigned_at,
    hazard_row.current_site_id
  )
  on conflict (id) do update
     set assigned_to = excluded.assigned_to,
         assigned_at = excluded.assigned_at,
         status = 'assigned'
  returning * into assigned_row;

  delete from public.hazards
   where id = p_hazard_id;

  return jsonb_build_object(
    'success', true,
    'status', 'assigned',
    'hazard', to_jsonb(assigned_row)
  );
end;
$$;

grant execute on function public.assign_hazard_to_hse(uuid, uuid, timestamptz)
  to authenticated;
