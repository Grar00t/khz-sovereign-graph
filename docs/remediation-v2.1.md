# Canonical v2.1 Remediation

## Authority

The canonical interchange contract is `schema/canonical_knowledge_graph_v2.1.0.json`. Legacy v1.0 and v2.0 schemas remain historical compatibility artifacts.

## Deterministic extraction

`src/inference/pipeline.py` delegates deterministic extraction to `scripts/extract_nodes.py`. Extraction is lexical/regex based, bounded, stable, and content-addressed. It does not promote extracted material to asserted truth.

## Database controls

`sql/002_canonical_v2_1_runtime.sql` supplies canonical ID helpers, HNSW cosine indexing for 1536-dimensional embeddings, bounded recursive traversal, and an append-only SHA-256 audit chain.

## Network controls

The Linux and Windows enforcement scripts install default-deny outbound rules with loopback exceptions. These are host controls, not proof of physical air-gap status.

## Kernel boundary

`arch/x86_64/memory_bounds.S` provides a bounded pointer primitive callable from C/C++. It operates at user privilege; it is not a Ring-0 isolation claim.
