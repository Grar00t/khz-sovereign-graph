begin;

create or replace function skg.bounded_traverse(
    p_start_id text,
    p_max_depth integer default 8,
    p_max_rows integer default 1000,
    p_edge_types text[] default null
)
returns table(node_id text, depth integer, path text[])
language sql
stable
as $$
with recursive walk as (
    select n.id as node_id, 0 as depth, array[n.id]::text[] as path
    from skg.nodes n
    where n.id = p_start_id
    union all
    select e.target_id, w.depth + 1, w.path || e.target_id
    from walk w
    join skg.edges e on e.source_id = w.node_id and e.status = 'validated'
    where w.depth < least(greatest(p_max_depth, 0), 64)
      and cardinality(w.path) < least(greatest(p_max_rows, 1), 1000)
      and (p_edge_types is null or e.edge_type = any(p_edge_types))
      and not (e.target_id = any(w.path))
    limit least(greatest(p_max_rows, 1), 1000)
)
select node_id, depth, path from walk order by depth, node_id limit least(greatest(p_max_rows, 1), 1000);
$$;

create or replace function skg.provision_hnsw(p_dimensions integer default 1536)
returns void
language plpgsql
as $$
begin
    if p_dimensions not between 2 and 4096 then
        raise exception 'embedding dimensions must be between 2 and 4096';
    end if;
    execute format(
        'create index if not exists idx_nodes_embedding_hnsw_%s on skg.nodes using hnsw ((embedding::vector(%s)) vector_cosine_ops) with (m=16, ef_construction=64)',
        p_dimensions, p_dimensions
    );
end;
$$;

commit;
