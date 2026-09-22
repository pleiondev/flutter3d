-- Projects, so a model can live inside one or stand alone, and category plus
-- full-text search, so the public showcase can be browsed and searched.

-- A folder an owner keeps their own models in. Nothing about visibility or
-- publication lives here — grouping a model under a project is not a second
-- place `canView`/`canEdit` gets decided; every model still carries its own
-- `owner_id` and its own `visibility`, project or no project.
create table projects (
  id          bigserial primary key,
  owner_id    bigint      not null references users (id) on delete cascade,
  slug        text        not null,
  title       text        not null,
  description text        not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- The same shape `models_by_owner` already has: a cabinet or a project list
-- reads one owner's rows, most recently changed first.
create index projects_by_owner on projects (owner_id, updated_at desc);

-- Nullable, because a model does not have to sit in a project at all, and
-- `set null` rather than `cascade` is what makes "delete a project, its
-- models become personal" a fact of this constraint alone — no application
-- code walks a deleted project's models to detach them, because by the time
-- any of it would run, the constraint has already done it.
alter table models add column project_id bigint references projects (id) on delete set null;

-- Looked up on every move and on a project's own page: which models currently
-- sit in one project, most recently changed first — the same reason
-- `models_by_owner` exists for the owner-wide list. Partial, since most rows
-- (every model with no project) have nothing to answer here.
create index models_by_project on models (project_id, updated_at desc)
  where project_id is not null;

-- A model's own category, chosen at publication the same way its licence is
-- — null while private, because a private model does not need one, and
-- constrained to a short fixed list for the same reason `licence` is a known
-- set of values rather than free text: the showcase's category filter only
-- ever chooses from this list, never matches whatever a client happened to
-- send.
alter table models add column category text
  check (category in (
    'characters', 'props', 'environments', 'vehicles', 'architecture',
    'abstract', 'other'
  ));

-- What the public showcase's own search reads — title weighted above
-- description, `english` config, and `stored` so a search does not
-- recompute this from every row on every query. This exists to serve the
-- showcase's search box alone; nothing else in this service searches a
-- model by its content.
alter table models add column search tsvector
  generated always as (
    setweight(to_tsvector('english', title), 'A') ||
    setweight(to_tsvector('english', description), 'B')
  ) stored;

create index models_search on models using gin (search);
