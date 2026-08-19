begin;

create schema if not exists skg_policy;

create table if not exists skg_policy.schema_versions (
    version text primary key,
    canonical boolean not null,
    applied_at timestamptz not null default now()
);

insert into skg_policy.schema_versions(version, canonical)
values ('2.1.0', true)
on conflict (version) do update set canonical = excluded.canonical;

create table if not exists skg_policy.jurisdictions (
    jurisdiction_code text primary key,
    regime text not null,
    version text not null,
    residency_required boolean not null,
    cross_border_allowed boolean not null,
    evidence_locator text,
    evidence_sha256 text,
    effective_from date not null,
    effective_to date,
    constraint jurisdiction_code_ck check (jurisdiction_code ~ '^[A-Z]{2}(?:-[A-Z0-9]{1,6})?$'),
    constraint jurisdiction_hash_ck check (evidence_sha256 is null or evidence_sha256 ~ '^[a-f0-9]{64}$'),
    constraint jurisdiction_dates_ck check (effective_to is null or effective_to >= effective_from)
);

insert into skg_policy.jurisdictions(jurisdiction_code, regime, version, residency_required, cross_border_allowed, evidence_locator, effective_from)
values
    ('SA', 'PDPL_NCA', '2026-01', true, false, 'UNVERIFIED_ASSERTION: populate from approved Saudi legal registry before production use', date '2026-01-01'),
    ('EU', 'GDPR', '2026-01', false, true, 'UNVERIFIED_ASSERTION: map EEA transfer mechanism per deployment and DPA', date '2026-01-01'),
    ('US', 'CLOUD_ACT', '2026-01', false, true, 'UNVERIFIED_ASSERTION: assess provider/controller exposure per deployment', date '2026-01-01'),
    ('CN', 'PIPL', '2026-01', true, false, 'UNVERIFIED_ASSERTION: populate from approved Chinese legal registry before production use', date '2026-01-01'),
    ('AE', 'UAE_PDPL', '2026-01', false, true, 'UNVERIFIED_ASSERTION: map transfer conditions per deployment', date '2026-01-01')
on conflict (jurisdiction_code) do nothing;

alter table skg.nodes add column if not exists scope_jurisdiction text;

update skg.nodes
set scope_jurisdiction = upper(scope_domain)
where scope_jurisdiction is null and scope_domain in ('SA','EU','US','CN','AE');

alter table skg.nodes drop constraint if exists node_scope_jurisdiction_fk;
alter table skg.nodes add constraint node_scope_jurisdiction_fk
foreign key (scope_jurisdiction) references skg_policy.jurisdictions(jurisdiction_code);

create index if not exists idx_nodes_scope_jurisdiction on skg.nodes(scope_jurisdiction);

create or replace function skg_policy.prevent_cross_border(p_source text, p_target text)
returns boolean
language sql
stable
as $$
    select coalesce(s.scope_jurisdiction, t.scope_jurisdiction) is null
        or s.scope_jurisdiction = t.scope_jurisdiction
        or not exists (
            select 1 from skg_policy.jurisdictions j
            where j.jurisdiction_code = coalesce(s.scope_jurisdiction, t.scope_jurisdiction)
              and j.residency_required and not j.cross_border_allowed
        )
    from skg.nodes s join skg.nodes t on true
    where s.id = p_source and t.id = p_target;
$$;

create or replace function skg.audit_row_hash(p_row jsonb)
returns text
language sql
immutable
as $$
    select encode(extensions.digest(convert_to(p_row::text, 'utf8'), 'sha256'), 'hex');
$$;

create table if not exists skg_audit.chain (
    sequence_no bigint generated always as identity primary key,
    object_type text not null,
    object_id text not null,
    operation text not null,
    before_hash text,
    after_hash text,
    previous_hash text,
    chain_hash text not null,
    created_at timestamptz not null default clock_timestamp(),
    metadata jsonb not null default '{}'::jsonb
);

create unique index if not exists skg_audit_chain_unique_idx on skg_audit.chain(sequence_no, chain_hash);

create or replace function skg_audit.append_chain_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, skg, skg_audit, extensions
as $$
declare
    old_json jsonb;
    new_json jsonb;
    before_hash text;
    after_hash text;
    previous_hash text;
    object_id_value text;
    chain_value text;
begin
    if tg_op = 'DELETE' then old_json := to_jsonb(old); object_id_value := old.id;
    else new_json := to_jsonb(new); object_id_value := new.id; end if;
    before_hash := case when tg_op in ('UPDATE','DELETE') then skg.audit_row_hash(old_json) end;
    after_hash := case when tg_op in ('INSERT','UPDATE') then skg.audit_row_hash(new_json) end;
    select chain_hash into previous_hash from skg_audit.chain order by sequence_no desc limit 1;
    chain_value := skg.audit_row_hash(jsonb_build_object(
        'object_type', tg_table_schema || '.' || tg_table_name,
        'object_id', object_id_value,
        'operation', tg_op,
        'before_hash', before_hash,
        'after_hash', after_hash,
        'previous_hash', previous_hash
    ));
    insert into skg_audit.chain(object_type, object_id, operation, before_hash, after_hash, previous_hash, chain_hash)
    values (tg_table_schema || '.' || tg_table_name, object_id_value, tg_op, before_hash, after_hash, previous_hash, chain_value);
    return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists trg_nodes_audit_chain on skg.nodes;
create trigger trg_nodes_audit_chain after insert or update or delete on skg.nodes
for each row execute function skg_audit.append_chain_event();

drop trigger if exists trg_edges_audit_chain on skg.edges;
create trigger trg_edges_audit_chain after insert or update or delete on skg.edges
for each row execute function skg_audit.append_chain_event();

commit;
