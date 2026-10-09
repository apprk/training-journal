create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  display_name text
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create table if not exists public.exercise_master (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  name text not null,
  muscle_group text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint exercise_master_owner_name unique (user_id, name)
);

create table if not exists public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  performed_at date not null default current_date,
  started_at timestamptz,
  ended_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.workout_exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references public.workout_sessions(id) on delete cascade,
  exercise_id uuid references public.exercise_master(id) on delete set null,
  name text not null,
  muscle_group text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.workout_sets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  exercise_id uuid not null references public.workout_exercises(id) on delete cascade,
  set_number integer not null,
  weight_kg numeric(7,2),
  reps integer,
  rpe numeric(3,1),
  rest_seconds integer,
  duration_seconds integer,
  distance_m numeric(10,2),
  notes text,
  created_at timestamptz not null default now(),
  unique (exercise_id, set_number)
);

create table if not exists public.running_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null,
  duration_seconds integer not null check (duration_seconds >= 0),
  distance_km numeric(9,3) not null check (distance_km >= 0),
  calories integer,
  average_heart_rate integer,
  max_heart_rate integer,
  notes text,
  source text not null default 'manual' check (source in ('manual','apple_health','import','other')),
  external_data_id text,
  imported_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, source, external_data_id)
);
create table if not exists public.body_composition_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  measured_at timestamptz not null,
  weight_kg numeric(7,2),
  body_fat_pct numeric(5,2),
  fat_mass_kg numeric(7,2),
  muscle_mass_kg numeric(7,2),
  bmi numeric(5,2),
  basal_metabolic_rate integer,
  visceral_fat numeric(6,2),
  body_water_pct numeric(5,2),
  other_metrics jsonb not null default '{}'::jsonb,
  source text not null default 'manual' check (source in ('manual','apple_health','import','other')),
  external_data_id text,
  imported_at timestamptz,
  image_url text,
  created_at timestamptz not null default now(),
  unique (user_id, source, external_data_id)
);
create table if not exists public.ai_analysis_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  content text not null,
  recommendations text,
  period_start date,
  period_end date,
  data_types text[] not null default '{}',
  model text,
  created_at timestamptz not null default now()
);

create index if not exists workout_sessions_owner_date on public.workout_sessions(user_id, performed_at desc);
create index if not exists workout_exercises_owner_session on public.workout_exercises(user_id, session_id);
create index if not exists workout_sets_owner_exercise on public.workout_sets(user_id, exercise_id);
create index if not exists running_sessions_owner_date on public.running_sessions(user_id, started_at desc);
create index if not exists body_records_owner_date on public.body_composition_records(user_id, measured_at desc);
create index if not exists ai_reports_owner_date on public.ai_analysis_reports(user_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.exercise_master enable row level security;
alter table public.workout_sessions enable row level security;
alter table public.workout_exercises enable row level security;
alter table public.workout_sets enable row level security;
alter table public.running_sessions enable row level security;
alter table public.body_composition_records enable row level security;
alter table public.ai_analysis_reports enable row level security;

drop policy if exists owner_all on public.profiles;
create policy owner_all on public.profiles for all to authenticated using (id = auth.uid()) with check (id = auth.uid());
-- Tables use user_id as the ownership column except profiles (id).
drop policy if exists owner_all on public.exercise_master;
drop policy if exists owner_all on public.workout_sessions;
drop policy if exists owner_all on public.workout_exercises;
drop policy if exists owner_all on public.workout_sets;
drop policy if exists owner_all on public.running_sessions;
drop policy if exists owner_all on public.body_composition_records;
drop policy if exists owner_all on public.ai_analysis_reports;
create policy owner_all on public.exercise_master for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy owner_all on public.workout_sessions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy owner_all on public.workout_exercises for all to authenticated
using (user_id = auth.uid() and exists (select 1 from public.workout_sessions s where s.id = session_id and s.user_id = auth.uid()))
with check (user_id = auth.uid() and exists (select 1 from public.workout_sessions s where s.id = session_id and s.user_id = auth.uid()));
create policy owner_all on public.workout_sets for all to authenticated
using (user_id = auth.uid() and exists (select 1 from public.workout_exercises e where e.id = exercise_id and e.user_id = auth.uid()))
with check (user_id = auth.uid() and exists (select 1 from public.workout_exercises e where e.id = exercise_id and e.user_id = auth.uid()));
create policy owner_all on public.running_sessions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy owner_all on public.body_composition_records for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy owner_all on public.ai_analysis_reports for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('body-composition-images','body-composition-images',false,10485760,array['image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do nothing;
drop policy if exists "Users manage own body images" on storage.objects;
create policy "Users manage own body images" on storage.objects for all to authenticated
using (bucket_id = 'body-composition-images' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'body-composition-images' and (storage.foldername(name))[1] = auth.uid()::text);

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
