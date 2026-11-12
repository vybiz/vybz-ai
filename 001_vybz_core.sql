-- VYBZ AI core schema (Supabase / PostgreSQL). Run in order. Every user table is RLS-protected.
create extension if not exists pgcrypto;

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text check (char_length(display_name) <= 80),
  avatar_path text,
  plan text not null default 'free' check (plan in ('free','creator','pro','studio')),
  credits integer not null default 0 check (credits >= 0),
  created_at timestamptz not null default now()
);

-- Explicit consent + ownership attestation, required before any voice model exists
create table voice_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  statement_version text not null,
  attests_own_voice boolean not null check (attests_own_voice),
  allows_third_party_processing boolean not null check (allows_third_party_processing),
  allows_shared_training boolean not null default false, -- separate opt-in, never implied
  consented_at timestamptz not null default now()
);

create table voice_recordings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  storage_path text not null,
  kind text not null check (kind in ('speaking','singing')),
  duration_s numeric not null check (duration_s > 0),
  sample_rate integer,
  peak_db numeric, noise_floor_db numeric, clipping_pct numeric,
  quality_score integer check (quality_score between 0 and 100),
  created_at timestamptz not null default now()
);

create table voice_models (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  consent_id uuid not null references voice_consents(id),
  provider text not null,
  provider_model_id text,                 -- written by backend only
  capability text not null check (capability in
    ('speaking_clone','singing_clone','singing_conversion','tts')),
  status text not null default 'pending' check (status in
    ('pending','training','ready','failed','deleted')),
  progress integer not null default 0 check (progress between 0 and 100),
  error text,
  created_at timestamptz not null default now()
);

create table music_projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  title text not null, genre text, bpm integer check (bpm between 40 and 240),
  musical_key text, is_favorite boolean not null default false,
  created_at timestamptz not null default now()
);

create table lyrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  project_id uuid references music_projects(id) on delete cascade,
  language text not null default 'en', body text not null,
  created_at timestamptz not null default now()
);

create table generation_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  project_id uuid references music_projects(id) on delete set null,
  state text not null default 'QUEUED' check (state in
   ('QUEUED','ANALYZING_TRENDS','SELECTING_DIRECTION','WRITING_LYRICS',
    'GENERATING_INSTRUMENTAL','GENERATING_VOCALS','ARRANGING','MIXING',
    'MASTERING','GENERATING_ARTWORK','FINALIZING','COMPLETED','FAILED')),
  progress integer not null default 0 check (progress between 0 and 100),
  attempts integer not null default 0, est_cost_credits integer,
  partial_results jsonb not null default '{}', error text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- Trend data is shared/global; each row labels measured vs estimated
create table trend_sources (
  id uuid primary key default gen_random_uuid(),
  name text unique not null, api_terms_url text, enabled boolean not null default false
);
create table trend_snapshots (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references trend_sources(id),
  region text, metric text not null, value numeric not null,
  is_estimate boolean not null, captured_at timestamptz not null default now()
);
create table trend_opportunities (
  id uuid primary key default gen_random_uuid(),
  label text not null, genre text, region text,
  growth_velocity numeric, engagement_accel numeric, cross_platform numeric,
  audience_relevance numeric, saturation numeric, regional_relevance numeric,
  short_form_fit numeric, score numeric, basis text not null check (basis in ('measured','estimated','mixed')),
  computed_at timestamptz not null default now()
);

create table audit_logs (
  id bigint generated always as identity primary key,
  user_id uuid references profiles(id) on delete set null,
  action text not null, detail jsonb, created_at timestamptz not null default now()
);

create index on voice_recordings(user_id);
create index on voice_models(user_id, status);
create index on music_projects(user_id, created_at desc);
create index on generation_jobs(user_id, state);
create index on trend_snapshots(source_id, captured_at desc);

-- RLS
alter table profiles enable row level security;
create policy own_profile on profiles for select using (id = auth.uid());
create policy upd_profile on profiles for update using (id = auth.uid())
  with check (id = auth.uid() and plan = (select plan from profiles where id = auth.uid())
              and credits = (select credits from profiles where id = auth.uid())); -- plan/credits change server-side only

do $$ declare t text; begin
  foreach t in array array['voice_consents','voice_recordings','voice_models','music_projects','lyrics','generation_jobs'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I on %I for select using (user_id = auth.uid())', t||'_sel', t);
    execute format('create policy %I on %I for delete using (user_id = auth.uid())', t||'_del', t);
  end loop;
end $$;
-- Inserts/updates for recordings, projects, lyrics: owner only
create policy rec_ins on voice_recordings for insert with check (user_id = auth.uid());
create policy proj_ins on music_projects for insert with check (user_id = auth.uid());
create policy proj_upd on music_projects for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy lyr_ins on lyrics for insert with check (user_id = auth.uid());
create policy lyr_upd on lyrics for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy cons_ins on voice_consents for insert with check (user_id = auth.uid());
-- voice_models and generation_jobs: written only by the backend (service role), users read/delete their own.

alter table trend_sources enable row level security;
alter table trend_snapshots enable row level security;
alter table trend_opportunities enable row level security;
alter table audit_logs enable row level security;
create policy trends_read on trend_opportunities for select to authenticated using (true);
create policy snaps_read on trend_snapshots for select to authenticated using (true);
create policy src_read on trend_sources for select to authenticated using (true);
-- audit_logs: no policies = service role only.

-- Storage: private bucket, files under <user_id>/...
-- insert into storage.buckets (id, name, public) values ('recordings','recordings',false);
-- create policy rec_obj on storage.objects for all to authenticated
--   using (bucket_id='recordings' and (storage.foldername(name))[1]=auth.uid()::text)
--   with check (bucket_id='recordings' and (storage.foldername(name))[1]=auth.uid()::text);
