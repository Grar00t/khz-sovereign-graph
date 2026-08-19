begin;

create extension if not exists pgtap;

select plan(8);

select ok(exists (select 1 from pg_proc where pronamespace = 'skg'::regnamespace and proname = 'bounded_traverse'), 'bounded_traverse exists');
select ok(exists (select 1 from pg_proc where pronamespace = 'skg'::regnamespace and proname = 'provision_hnsw'), 'provision_hnsw exists');
select ok(exists (select 1 from pg_trigger where tgname = 'trg_nodes_audit_chain'), 'node audit trigger exists');
select ok(exists (select 1 from pg_trigger where tgname = 'trg_edges_audit_chain'), 'edge audit trigger exists');
select ok(exists (select 1 from pg_class where relnamespace = 'skg_audit'::regnamespace and relname = 'chain'), 'audit chain exists');
select ok(exists (select 1 from pg_class where relnamespace = 'skg_policy'::regnamespace and relname = 'jurisdictions'), 'jurisdiction table exists');
select ok((select count(*) from skg_policy.jurisdictions) >= 5, 'jurisdiction seed set exists');
select ok((select count(*) from skg_policy.schema_versions where version = '2.1.0' and canonical) = 1, 'v2.1 canonical marker exists');

select * from finish();
rollback;
