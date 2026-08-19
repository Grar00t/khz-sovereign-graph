from __future__ import annotations

import hashlib
import re
from typing import Iterable

CANONICAL_TYPES = {
    "protocol", "technology", "language", "architecture", "practice", "standard",
    "component", "model", "dataset", "metric", "concept", "organization", "person",
}

TYPE_HINTS = (
    ("protocol", re.compile(r"\b(?:HTTP|HTTPS|TCP|UDP|DNS|TLS|QUIC|SSH|BGP|NTP|API)\b", re.I)),
    ("language", re.compile(r"\b(?:Python|Rust|C|C\+\+|Java|Go|JavaScript|TypeScript|SQL|Assembly|Bash)\b", re.I)),
    ("standard", re.compile(r"\b(?:ISO\s*\d+|RFC\s*\d+|FIPS\s*\d+|NIST\s+[A-Z0-9-]+|IEEE\s+[0-9.]+)\b", re.I)),
    ("technology", re.compile(r"\b(?:PostgreSQL|Supabase|Docker|Linux|Ubuntu|Windows|PostGIS|pgvector|HNSW|eBPF|nftables|seccomp|systemd|GitHub)\b", re.I)),
    ("architecture", re.compile(r"\b(?:architecture|pipeline|microservice|monorepo|graph|knowledge graph|property graph|air[- ]gapped?|zero[- ]telemetry)\b", re.I)),
    ("component", re.compile(r"\b(?:node|edge|database|index|kernel|module|controller|service|trigger|function|table|schema)\b", re.I)),
    ("metric", re.compile(r"\b(?:latency|throughput|recall|precision|confidence|coverage|completeness|score|dimension(?:s)?)\b", re.I)),
    ("model", re.compile(r"\b(?:Llama(?:\s+[0-9.]+)?|Qwen(?:\s+[0-9.]+)?|Transformer|LLM|embedding model)\b", re.I)),
)


def normalize(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip().lower())


def stable_id(label: str, node_type: str, scope: str) -> str:
    raw = f"{normalize(label)}|{normalize(node_type)}|{normalize(scope)}".encode()
    return "n_" + hashlib.sha256(raw).hexdigest()


def sentence_chunks(document: str) -> list[str]:
    text = document.replace("\r\n", "\n").strip()
    if not text:
        return []
    parts = re.split(r"(?<=[.!?؟。])\s+|\n+", text)
    return [p.strip(" \t-•*") for p in parts if p.strip(" \t-•*")]


def infer_type(label: str, sentence: str, allowed: set[str]) -> str:
    for candidate, pattern in TYPE_HINTS:
        if candidate not in allowed:
            continue
        if pattern.search(label) or pattern.search(sentence):
            return candidate
    return "concept" if "concept" in allowed else next(iter(sorted(allowed)))


def candidate_labels(sentence: str) -> list[str]:
    labels: set[str] = set()
    for match in re.findall(r"\b[A-Z][A-Za-z0-9+._/-]{2,63}(?:\s+[A-Z][A-Za-z0-9+._/-]{2,63}){0,3}\b", sentence):
        labels.add(match.strip())
    for match in re.findall(r"\b(?:[A-Za-z][A-Za-z0-9+._/-]{2,63})(?:\s+(?:graph|engine|pipeline|schema|index|service|standard|protocol))\b", sentence, re.I):
        labels.add(match.strip())
    return sorted(labels, key=lambda x: (normalize(x), x))


def extract_nodes(document: str, *, allowed_types: Iterable[str] = CANONICAL_TYPES, scope: str = "inference") -> list[dict]:
    allowed = set(allowed_types) & CANONICAL_TYPES
    if not allowed:
        allowed = set(CANONICAL_TYPES)
    dedup: dict[str, dict] = {}
    for sentence in sentence_chunks(document):
        for label in candidate_labels(sentence):
            if len(label) < 3:
                continue
            node_type = infer_type(label, sentence, allowed)
            node_id = stable_id(label, node_type, scope)
            evidence_material = f"{normalize(sentence)}"
            evidence_id = "ev_" + hashlib.sha256(evidence_material.encode()).hexdigest()
            node = {
                "id": node_id,
                "type": node_type,
                "label": label,
                "description": sentence[:2048],
                "aliases": [],
                "status": "candidate",
                "scope": scope,
                "properties": {},
                "confidence": 0.5,
                "provenance": [evidence_id],
            }
            existing = dedup.get(node_id)
            if existing is None or (len(node["description"]) > len(existing["description"])):
                dedup[node_id] = node
    return [dedup[k] for k in sorted(dedup)]
