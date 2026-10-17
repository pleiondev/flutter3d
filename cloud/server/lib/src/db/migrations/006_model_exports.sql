-- "Download as…": a model written out in another format, kept so the second
-- request for it is a file read and not a conversion. See
-- `convert/exporter.dart` and `/files/<id>/as/<format>`.
--
-- **Keyed by what was written, not by who asked.** The same source bytes
-- (`source_sha256`) written in the same format by the same writers
-- (`writer_version`) give the same file, so a hit for one model serves
-- another that holds the same file. The row is still per model, so deleting
-- a model takes its rows with it and `isReferenced` knows which blobs are
-- still wanted.
--
-- **Only for the source a model has now.** Replacing the source drops the
-- rows for the old one (`dropStaleExports`), and their blobs are freed the
-- way every other blob here is: once `isReferenced` says nothing points at
-- them.

create table model_exports (
  id             bigserial primary key,
  model_id       bigint      not null references models (id) on delete cascade,
  source_sha256  text        not null,
  format         text        not null,
  writer_version integer     not null,
  blob_sha256    text        not null,
  bytes          bigint      not null,
  content_type   text        not null,
  created_at     timestamptz not null default now(),

  unique (model_id, source_sha256, format, writer_version)
);

-- A hit is looked up by what was written, whichever model it was written for.
create index model_exports_by_key
  on model_exports (source_sha256, format, writer_version);

-- The same reason `model_files_by_blob` exists: `isReferenced` asks this for
-- every blob a delete considers freeing.
create index model_exports_by_blob on model_exports (blob_sha256);
