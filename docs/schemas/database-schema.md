# Database Schema Documentation

## Overview

The AI Continuous Delivery system uses two Supabase projects:
- **Supabase A**: Archon MCP data storage
- **Supabase B**: Control-plane for CI/CD orchestration

## Control-Plane Schema (Supabase B)

### Core Tables

#### `specs` - Project Specifications
Stores ingested project specifications from email or API.

```sql
create table specs (
  id uuid primary key default gen_random_uuid(),
  repo text not null,           -- GitHub repository (e.g., "ljniox/ai-continuous-delivery")
  branch text not null,         -- Target branch for development
  storage_path text not null,   -- Path to spec file in storage
  sha text,                     -- Git commit SHA if applicable
  created_at timestamptz default now(),
  created_by text               -- Email or API user identifier
);
```

#### `sprints` - Sprint Planning
Links specifications to executable sprint plans with Definition of Done criteria.

```sql
create table sprints (
  id uuid primary key default gen_random_uuid(),
  spec_id uuid references specs(id) on delete cascade,
  label text not null,          -- Sprint identifier (e.g., "S1")
  dod_json jsonb not null,      -- Executable DoD criteria
  state text not null default 'PLANNED',  -- PLANNED/RUNNING/DONE/FAILED
  created_at timestamptz default now()
);
```

**DoD JSON Structure:**
```json
{
  "coverage_min": 0.80,      // Minimum test coverage (0.0-1.0)
  "e2e_pass": true,          // E2E tests must pass
  "lighthouse_min": 85,      // Minimum Lighthouse performance score
  "lint_pass": true,         // Linting must pass
  "type_check": true         // Type checking must pass
}
```

#### `runs` - CI/CD Executions
Tracks individual pipeline executions with results and metadata.

```sql
create table runs (
  id uuid primary key default gen_random_uuid(),
  sprint_id uuid references sprints(id) on delete cascade,
  ci_run_id text,               -- GitHub Actions run ID
  started_at timestamptz default now(),
  finished_at timestamptz,
  result text,                  -- PASSED/FAILED
  summary_json jsonb            -- Execution summary and metrics
);
```

**Summary JSON Structure:**
```json
{
  "status": "PASSED",
  "tests": {
    "python": {"passed": 3, "failed": 0, "coverage": 0.85},
    "e2e": {"passed": 2, "failed": 0}
  },
  "lighthouse": {"score": 92},
  "artifacts": ["junit", "coverage", "playwright-report"],
  "duration_seconds": 180
}
```

#### `artifacts` - Generated Artifacts
Stores metadata about test reports, coverage data, and other generated files.

```sql
create table artifacts (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references runs(id) on delete cascade,
  kind text,                    -- junit|coverage|playwright|lighthouse|logs
  storage_path text not null,   -- Path in storage bucket
  size bigint,                  -- File size in bytes
  created_at timestamptz default now()
);
```

#### `status_events` - Event Log
Real-time status updates throughout the pipeline execution.

```sql
create table status_events (
  id bigserial primary key,
  run_id uuid,
  phase text,                   -- SPEC_RECEIVED|PLANNING|BUILD|TESTS_PASSED|FAILED|MERGED
  message text,
  metadata jsonb,
  created_at timestamptz default now()
);
```

### Indexes and Performance

```sql
-- Performance indexes
create index idx_runs_sprint_id on runs(sprint_id);
create index idx_artifacts_run_id on artifacts(run_id);
create index idx_status_events_run_id on status_events(run_id);
create index idx_status_events_created_at on status_events(created_at desc);
```

### Row Level Security (RLS)

All tables implement RLS policies to ensure data access control:

```sql
-- Example RLS policy for specs table
create policy "Authenticated users can read specs"
  on specs for select
  using (auth.role() = 'authenticated');

create policy "Service role can insert specs"
  on specs for insert
  with check (auth.role() = 'service_role');
```

## Relationships

```
specs (1) ──────── (*) sprints
                       │
                       │ (1)
                       │
                       ▼
                    (*) runs
                       │
                       │ (1)
                       │
                       ▼
                    (*) artifacts
                       │
                       │ (*)
                       │
                       ▼
                    (*) status_events
```

## Data Lifecycle

1. **Spec Ingestion**: Email/API creates `specs` record
2. **Sprint Planning**: Claude Code analysis creates `sprints` record
3. **Execution**: GitHub Actions creates `runs` record
4. **Status Updates**: Continuous `status_events` logging
5. **Artifact Generation**: Test results stored as `artifacts`
6. **Cleanup**: Configurable retention policies for old data