-- N7: runs players agreed to send, as what they did rather than what they
-- pressed. The input is replayed and dropped; see `telemetry_store.dart`.

create table telemetry_runs (
  id               bigserial   primary key,
  game             text        not null,
  level_hash       text        not null,
  level            text        not null,
  outcome          text        not null
    check (outcome in ('won', 'lost', 'unfinished')),
  steps            integer     not null check (steps > 0),
  -- `[[x, z], ...]`, sampled every few steps of the replay.
  trail            jsonb       not null,
  -- The hash, never the key: a leaked table erases nothing.
  erase_key_sha256 text        not null,
  -- The record of consent the run was taken under.
  policy           text        not null,
  consented_at     timestamptz not null,
  received_at      timestamptz not null default now()
);

-- A heatmap reads one level's newest runs.
create index telemetry_runs_by_level on telemetry_runs (level_hash, id desc);
