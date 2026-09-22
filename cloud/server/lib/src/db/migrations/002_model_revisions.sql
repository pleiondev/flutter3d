-- Revision history for a model's source file, added for the cabinet's "save
-- back" stage. `model_files` still holds the current source — what
-- `/files/<id>/source` serves — so this table is everything a save replaced:
-- `revisionsOf` lists what changed, and `revisionFile` can still serve an
-- older upload by its own id.
--
-- **Append-only.** A row here is inserted once and never updated — the whole
-- reason to keep revisions is that an earlier save stays exactly as it was,
-- not as a copy that could itself drift.

create table model_revisions (
  id             bigserial primary key,
  model_id       bigint      not null references models (id) on delete cascade,
  blob_sha256    text        not null,
  bytes          bigint      not null,
  content_type   text        not null,
  filename       text        not null,
  triangle_count integer     not null default 0,
  created_at     timestamptz not null default now(),
  -- Never null: a save only ever happens through `_editing`, which checks for
  -- a signed-in session before any of this runs, so there is always somebody
  -- to ask about a change. No `on delete cascade` to `users`: deleting a
  -- model already takes every one of its revisions with it through
  -- `model_id`, so by the time a user row itself is deleted — which cascades
  -- through `models.owner_id` first — nothing here still points at them.
  created_by     bigint      not null references users (id)
);

-- Listing a model's history newest-first, the only order `revisionsOf` reads
-- it in.
create index model_revisions_by_model on model_revisions (model_id, created_at desc);

-- The same reason `model_files_by_blob` exists: `isReferenced` runs this
-- lookup for every blob a delete considers freeing, and once revisions exist
-- a blob can be kept alive by one of these rows alone, after a later save has
-- already moved `model_files` on to a different hash.
create index model_revisions_by_blob on model_revisions (blob_sha256);
