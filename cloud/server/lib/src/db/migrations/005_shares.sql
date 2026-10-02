-- N10: levels shared behind short codes, and the reports against them. See
-- `shares/share_store.dart`.

create table shares (
  -- Crockford base 32 of the address, seven characters unless a different
  -- bundle already holds those; see `shares/short_code.dart`.
  code        text        primary key check (code ~ '^[0-9A-HJKMNP-TV-Z]{7,51}$'),
  -- The SHA-256 of `bundle`, hex. Unique, so a bundle shared twice is one row
  -- however the two requests interleave.
  address     text        not null unique check (address ~ '^[0-9a-f]{64}$'),
  game        text        not null,
  level_hash  text        not null,
  title       text,
  has_run     boolean     not null,
  -- **Text, not jsonb.** jsonb keeps neither key order nor the exact spelling
  -- of a number, and the address is the hash of these bytes: a code has to
  -- open exactly what its address names.
  bundle      text        not null,
  status      text        not null
    check (status in ('published', 'pending', 'removed')),
  -- Why a moderator decided as they did; what a removed code answers with.
  note        text,
  created_at  timestamptz not null default now()
);

-- The moderation queue reads what still waits, oldest first.
create index shares_pending on shares (created_at) where status = 'pending';

-- Reports a moderator has not answered yet. Publishing a level again answers
-- them, and they are deleted then.
create table share_reports (
  id          bigserial   primary key,
  code        text        not null references shares (code) on delete cascade,
  reason      text        not null,
  reported_at timestamptz not null default now()
);

create index share_reports_by_code on share_reports (code, id);
