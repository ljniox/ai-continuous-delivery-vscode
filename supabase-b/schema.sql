-- Schéma SQL pour Supabase Projet B (Control-Plane)
-- Tables pour la gestion des specs, sprints, runs et artifacts

-- Table des spécifications reçues par email
create table specs (
  id uuid primary key default gen_random_uuid(),
  repo text not null,
  branch text not null,
  storage_path text not null,
  sha text,
  created_at timestamptz default now(),
  created_by text
);

-- Table des sprints planifiés
create table sprints (
  id uuid primary key default gen_random_uuid(),
  spec_id uuid references specs(id) on delete cascade,
  label text not null,      -- e.g. "S1"
  dod_json jsonb not null,  -- critères exécutables
  state text not null default 'PLANNED', -- PLANNED/RUNNING/DONE/FAILED
  created_at timestamptz default now()
);

-- Table des exécutions CI/CD
create table runs (
  id uuid primary key default gen_random_uuid(),
  sprint_id uuid references sprints(id) on delete cascade,
  ci_run_id text,
  started_at timestamptz default now(),
  finished_at timestamptz,
  result text,              -- PASSED/FAILED
  summary_json jsonb
);

-- Table des artefacts générés (rapports, logs, etc.)
create table artifacts (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references runs(id) on delete cascade,
  kind text,                -- junit|coverage|lighthouse|logs
  storage_path text not null,
  size bigint,
  created_at timestamptz default now()
);

-- Table des événements de statut
create table status_events (
  id bigserial primary key,
  run_id uuid,
  phase text,               -- SPEC_RECEIVED|PLANNING|BUILD|TESTS_PASSED|FAILED|MERGED
  message text,
  ts timestamptz default now()
);

-- Activation RLS (Row Level Security)
alter table specs enable row level security;
alter table sprints enable row level security;
alter table runs enable row level security;
alter table artifacts enable row level security;
alter table status_events enable row level security;

-- Politique RLS : autoriser insert/select seulement via service role
create policy "Service role can manage specs" on specs
  for all using (auth.role() = 'service_role');

create policy "Service role can manage sprints" on sprints
  for all using (auth.role() = 'service_role');

create policy "Service role can manage runs" on runs
  for all using (auth.role() = 'service_role');

create policy "Service role can manage artifacts" on artifacts
  for all using (auth.role() = 'service_role');

create policy "Service role can manage status_events" on status_events
  for all using (auth.role() = 'service_role');