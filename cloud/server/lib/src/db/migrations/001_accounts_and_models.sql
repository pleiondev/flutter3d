-- The whole schema the first release needs: who has an account, who is signed
-- in, what was uploaded, and what is being rate limited.
--
-- Written as one migration rather than five because none of it has shipped yet;
-- from the second release on, every change is its own numbered file and this
-- one is never edited again.

create extension if not exists citext;

-- **Case folded, because a mailbox is.** `Ann@example.com` and
-- `ann@example.com` reach the same person, and a service that let them be two
-- accounts would send the reset letter to an account nobody signs into.
create table users (
  id                bigserial primary key,
  email             citext      not null unique,
  handle            text        not null unique,
  display_name      text        not null,
  password_hash     text        not null,
  email_verified_at timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- The session token itself is never stored: the row holds its SHA-256, so a
-- copy of this table is not a set of working cookies.
create table sessions (
  id           bigserial primary key,
  user_id      bigint      not null references users (id) on delete cascade,
  token_sha256 bytea       not null unique,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at   timestamptz not null,
  user_agent   text,
  ip           inet
);

create index sessions_by_user on sessions (user_id);
create index sessions_by_expiry on sessions (expires_at);

-- One table for both letters. The purpose is a column rather than two tables
-- because everything else about them is identical — issued, expires, used once
-- — and two tables would be two places to fix a mistake about single use.
create table email_tokens (
  id           bigserial primary key,
  user_id      bigint      not null references users (id) on delete cascade,
  purpose      text        not null check (purpose in ('verify', 'reset')),
  token_sha256 bytea       not null unique,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  used_at      timestamptz
);

create index email_tokens_by_user on email_tokens (user_id, purpose);

create table models (
  id             bigserial primary key,
  owner_id       bigint      not null references users (id) on delete cascade,
  slug           text        not null,
  title          text        not null,
  description    text        not null default '',
  visibility     text        not null default 'private'
                 check (visibility in ('private', 'public')),
  -- Null while the model is private: a licence is chosen at publication, and a
  -- default one would be a licence nobody picked.
  licence        text,
  source_format  text        not null,
  triangle_count integer     not null default 0,
  size_bytes     bigint      not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  -- The slug is not unique, even per owner: a model's address is
  -- `/m/<id>-<slug>`, so the id already tells two chairs apart and the slug is
  -- there for the person reading the link.
  published_at   timestamptz
);

create index models_by_owner on models (owner_id, updated_at desc);

create index models_public_recent on models (published_at desc)
  where visibility = 'public';

-- Content, addressed by its own hash. Two people who upload the same cube have
-- one file on disk and two rows here.
create table model_files (
  id           bigserial primary key,
  model_id     bigint      not null references models (id) on delete cascade,
  kind         text        not null check (kind in ('source', 'preview')),
  blob_sha256  text        not null,
  bytes        bigint      not null,
  content_type text        not null,
  filename     text        not null,
  created_at   timestamptz not null default now(),

  unique (model_id, kind)
);

create index model_files_by_blob on model_files (blob_sha256);

-- Attempts worth counting: sign-in, registration, password reset. Kept in the
-- database rather than in memory so that a restart is not a way to clear the
-- count, and swept by the same job that sweeps expired sessions.
create table rate_events (
  bucket     text        not null,
  at         timestamptz not null default now()
);

create index rate_events_by_bucket on rate_events (bucket, at desc);
