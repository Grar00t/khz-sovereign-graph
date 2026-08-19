create schema if not exists skg;
create schema if not exists skg_audit;

create or replace function skg.normalize_text(p_value text)
returns text
language sql
immutable
strict
as $$
  select regexp_replace(lower(btrim(p_value)), '\\s+', ' ', 'g');
$$;

create or replace function skg.canonical_node_id(p_label text, p_type text, p_scope text)
returns text
language sql
immutable
strict
as $$
  select 'n_' || encode(digest(
    skg.normalize_text(p_label) || '|' ||
    skg.normalize_text(p_type) || '|' ||
    skg.normalize_text(p_scope),
    'sha256'
  ), 'hex');
$$;

create or replace function skg.canonical_edge_id(p_source text, p_edge_type text, p_target text)
returns text
language sql
immutable
strict
as $$
  select 'e_' || encode(digest(p_source || '|' || p_edge_type || '|' || p_target, 'sha256'), 'hex');
$$;

alter table skg.nodes
  drop constraint if exists node_id_ck,
  add constraint node_id_ck canonical check (id ~ '^n_[a-f0-9]{64}$');

alter table skg.edges
  drop constraint if exists edge_id_ck,
  add constraint edge_id_ck canonical check (id ~ '^e_[a-f0-9]{64}$');

alter table skg.evidence
  drop constraint if exists evidence_id_ck,
  add constraint evidence_id_ck canonical check (id ~ '^ev_[a-f0-9]{64}$');

alter table skg.nodes
  drop constraint if exists node_type_ck;
alter table skg.nodes
  add constraint node_type_ck check (node_type in (
    'protocol','technology','language','architecture','practice','standard',
    'component','model','dataset','metric','concept','organization','person'
  ));

alter table skg.edges
  drop constraint if exists edge_type_ck;
alter table skg.edges
  add constraint edge_type_ck check (edge_type in (
    'implements','depends_on','supports','enables','extends','validates',
    'contradicts','derived_from','related_to','part_of','instance_of','supersedes'
  ));

create index if not exists idx_nodes_embedding_hnsw_cosine
  on skg.nodes using hnsw ((embedding::vector(1536)) vector_cosine_ops)
  where embedding is not null;

create or replace function skg.bounded_traverse(
  p_start_id text,
  p_max_hops integer default 4,
  p_edge_types text[] default null,
  p_limit integer default 1000
)
returns table(node_id text, depth integer, path text[])
language sql
stable
as $$
with recursive walk(node_id, depth, path, visited) as (
  select n.id, 0, array[n.id], array[n.id]
  from skg.nodes n
  where n.id = p_start_id
  union all
  select
    case when e.source_id = w.node_id then e.target_id else e.source_id end,
    w.depth + 1,
    w.path || case when e.source_id = w.node_id then e.target_id else e.source_id end,
    w.visited || case when e.source_id = w.node_id then e.target_id else e.source_id end
  from walk w
  join skg.edges e
    on (e.source_id = w.node_id or (e.direction = 'symmetric' and e.target_id = w.node_id))
   and e.status = 'validated'
   and (p_edge_types is null or e.edge_type = any(p_edge_types))
  where w.depth < greatest(0, least(p_max_hops, 64))
    and not (case when e.source_id = w.node_id then e.target_id else e.source_id end = any(w.visited))
)
select node_id, depth, path
from walk
order by depth, node_id
limit greatest(1, least(p_limit, 10000));
$$;

create table if not exists skg_audit.events (
  event_id bigint generated always as identity primary key,
  event_type text not null,
  object_type text not null,
  object_id text not null,
  before_hash text,
  after_hash text,
  evidence_id text references skg.evidence(id) on delete restrict,
  previous_chain_hash text not null default repeat('0', 64),
  chain_hash text not null,
  created_at timestamptz not null default clock_timestamp(),
  metadata jsonb not null default '{}'::jsonb,
  constraint audit_chain_hash_ck check (chain_hash ~ '^[a-f0-9]{64}$'),
  constraint audit_prev_hash_ck check (previous_chain_hash ~ '^[a-f0-9]{64}$')
);

create or replace function skg_audit.hash_event(
  p_event_type text,
  p_object_type text,
  p_object_id text,
  p_before_hash text,
  p_after_hash text,
  p_evidence_id text,
  p_previous_chain_hash text,
  p_created_at timestamptz,
  p_metadata jsonb
)
returns text
language sql
immutable
as $$
  select encode(digest(
    coalesce(p_event_type,'') || '|' ||
    coalesce(p_object_type,'') || '|' ||
    coalesce(p_object_id,'') || '|' ||
    coalesce(p_before_hash,'') || '|' ||
    coalesce(p_after_hash,'') || '|' ||
    coalesce(p_evidence_id,'') || '|' ||
    coalesce(p_previous_chain_hash, repeat('0',64)) || '|' ||
    to_char(p_created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' ||
    coalesce(p_metadata::text, '{}'),
    'sha256'
  ), 'hex');
$$;

create or replace function skg_audit.append_chain_hash()
returns trigger
language plpgsql
as $$
declare
  prev_hash text;
begin
  if tg_op <> 'INSERT' then
    raise exception 'skg_audit.events is append-only';
  end if;

  select e.chain_hash
    into prev_hash
    from skg_audit.events e
   order by e.event_id desc
   limit 1;

  new.previous_chain_hash := coalesce(prev_hash, repeat('0', 64));
  new.created_at := coalesce(new.created_at, clock_timestamp());
  new.chain_hash := skg_audit.hash_event(
    new.event_type,
    new.object_type,
    new.object_id,
    new.before_hash,
    new.after_hash,
    new.evidence_id,
    new.previous_chain_hash,
    new.created_at,
    new.metadata
  );
  return new;
end;
$$;

drop trigger if exists trg_audit_chain_insert on skg_audit.events;
create trigger trg_audit_chain_insert
before insert on skg_audit.events
for each row execute function skg_audit.append_chain_hash();

drop trigger if exists trg_audit_append_only on skg_audit.events;
create or replace function skg_audit.reject_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'skg_audit.events is append-only';
end;
$$;
create trigger trg_audit_append_only
before update or delete on skg_audit.events
for each row execute function skg_audit.reject_mutation();
