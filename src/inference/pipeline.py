from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import re
from typing import Any, Iterable, Protocol

from .deterministic_extract import extract_nodes as deterministic_extract_nodes

WEIGHTS = {
    "semantic": 0.40,
    "lexical": 0.10,
    "structural": 0.20,
    "type_compatibility": 0.15,
    "evidence": 0.15,
}

REJECT_THRESHOLD = 0.70
REVIEW_THRESHOLD = 0.80
AUTO_ACCEPT_THRESHOLD = 0.92
EVIDENCE_REQUIRED = {"contradicts", "conflicts_with", "supersedes", "causes", "mitigates"}


def normalize_text(value: str) -> str:
    value = value.strip().lower()
    return re.sub(r"\s+", " ", value)


def stable_semantic_id(label: str, node_type: str, scope: str) -> str:
    canonical = "|".join((normalize_text(label), normalize_text(node_type), normalize_text(scope))).encode("utf-8")
    return "n_" + hashlib.sha256(canonical).hexdigest()


def stable_edge_id(source: str, edge_type: str, target: str) -> str:
    return "e_" + hashlib.sha256(f"{source}|{edge_type}|{target}".encode("utf-8")).hexdigest()


class Embedder(Protocol):
    model_name: str
    dimensions: int

    def encode(self, texts: list[str]) -> list[list[float]]: ...


class Store(Protocol):
    def retrieve_candidates(self, node: dict[str, Any], *, top_k: int) -> list[dict[str, Any]]: ...
    def insert_candidate_edge(self, edge: dict[str, Any]) -> None: ...
    def validate_and_promote(self, edge: dict[str, Any]) -> bool: ...
    def audit_event(self, event_type: str, object_type: str, object_id: str, details: dict[str, Any]) -> None: ...


@dataclass
class PipelineConfig:
    top_k: int = 20
    weights: dict[str, float] = field(default_factory=lambda: dict(WEIGHTS))
    reject_threshold: float = REJECT_THRESHOLD
    review_threshold: float = REVIEW_THRESHOLD
    auto_accept_threshold: float = AUTO_ACCEPT_THRESHOLD
    allowed_types: tuple[str, ...] = (
        "domain", "topic", "concept", "practice", "technology", "language", "standard", "protocol",
        "algorithm", "architecture", "component", "constraint", "requirement", "risk", "decision",
        "evidence", "document",
    )
    default_scope: str = "global"

    def validate(self) -> None:
        if set(self.weights) != set(WEIGHTS):
            raise ValueError("scoring weights must match canonical v2.0.0 keys")
        if abs(sum(self.weights.values()) - 1.0) > 1e-9:
            raise ValueError("scoring weights must sum to 1")
        if not 1 <= self.top_k <= 200:
            raise ValueError("top_k must be in [1, 200]")
        if not 0 <= self.reject_threshold <= self.review_threshold <= self.auto_accept_threshold <= 1:
            raise ValueError("thresholds must satisfy 0 <= reject <= review <= auto_accept <= 1")


def extract_nodes(document: str, *, allowed_types: Iterable[str]) -> list[dict[str, Any]]:
    types = tuple(dict.fromkeys(allowed_types))
    return deterministic_extract_nodes(document, allowed_types=types or PipelineConfig().allowed_types)


def generate_embeddings(nodes: list[dict[str, Any]], embedder: Embedder) -> None:
    if not nodes:
        return
    texts = [f"{n.get('label', '')}\n{n.get('description') or ''}" for n in nodes]
    vectors = embedder.encode(texts)
    if len(vectors) != len(nodes):
        raise ValueError("embedder returned wrong number of vectors")
    for node, vector in zip(nodes, vectors):
        if len(vector) != embedder.dimensions:
            raise ValueError("embedding dimension mismatch")
        node["retrieval"] = {
            "embedding_model": embedder.model_name,
            "embedding_dimensions": embedder.dimensions,
            "embedding": vector,
        }


def score_candidates(source: dict[str, Any], candidates: list[dict[str, Any]], *, config: PipelineConfig) -> list[dict[str, Any]]:
    config.validate()
    scored: list[dict[str, Any]] = []
    for candidate in candidates[:config.top_k]:
        score_parts = {k: min(1.0, max(0.0, float(candidate.get(k, 0.0)))) for k in WEIGHTS}
        overall = sum(config.weights[k] * score_parts[k] for k in config.weights)
        decision = "reject" if overall < config.reject_threshold else "review" if overall < config.auto_accept_threshold else "auto_accept"
        scored.append({"source": source, "target": candidate, "score": score_parts, "overall": overall, "decision": decision})
    scored.sort(key=lambda x: (-x["overall"], x["target"].get("id", "")))
    return scored


def validate_relation(source: dict[str, Any], target: dict[str, Any], edge_type: str, *, evidence_ids: list[str], known_edges: list[dict[str, Any]], max_known_edges: int = 10000) -> tuple[bool, str]:
    if source.get("id") == target.get("id"):
        return False, "self_reference"
    if edge_type in EVIDENCE_REQUIRED and not evidence_ids:
        return False, "evidence_required"
    known = known_edges[:max_known_edges]
    if any(e.get("source") == source.get("id") and e.get("target") == target.get("id") and e.get("type") == edge_type and e.get("status") == "validated" for e in known):
        return False, "duplicate_edge"
    if edge_type == "depends_on":
        cursor = source.get("id")
        visited: set[str] = set()
        depth = 0
        adjacency: dict[str, list[str]] = {}
        for edge in known:
            if edge.get("type") == "depends_on" and edge.get("status") == "validated":
                adjacency.setdefault(str(edge.get("source")), []).append(str(edge.get("target")))
        while cursor and depth < 128:
            if cursor in visited:
                return False, "cycle_detected"
            visited.add(cursor)
            if cursor == target.get("id"):
                return False, "cycle_detected"
            nxt = adjacency.get(cursor, [])
            cursor = nxt[0] if nxt else None
            depth += 1
    return True, "ok"


def persist_edge(store: Store, source: dict[str, Any], target: dict[str, Any], edge_type: str, score: dict[str, Any], evidence_ids: list[str]) -> dict[str, Any]:
    edge = {
        "id": stable_edge_id(source["id"], edge_type, target["id"]),
        "source": source["id"],
        "target": target["id"],
        "type": edge_type,
        "status": "candidate",
        "origin": "model_assisted",
        "confidence": {"overall": float(score["overall"]), "semantic": score["score"]["semantic"], "source": score["score"]["evidence"], "structural": score["score"]["structural"]},
        "score": score["score"],
        "reason": {"decision": score["decision"]},
        "provenance": list(dict.fromkeys(evidence_ids)),
    }
    store.insert_candidate_edge(edge)
    store.audit_event("edge_created", "edge", edge["id"], edge)
    return edge


def run(document: str, embedder: Embedder, store: Store, *, config: PipelineConfig | None = None) -> list[dict[str, Any]]:
    config = config or PipelineConfig()
    config.validate()
    nodes = extract_nodes(normalize_text(document), allowed_types=config.allowed_types)
    generate_embeddings(nodes, embedder)
    edges: list[dict[str, Any]] = []
    for node in nodes:
        candidates = store.retrieve_candidates(node, top_k=config.top_k)[:config.top_k]
        for result in score_candidates(node, candidates, config=config):
            if result["decision"] != "auto_accept":
                continue
            target = result["target"]
            edge_type = target.get("proposed_edge_type", "related_to")
            ok, reason = validate_relation(node, target, edge_type, evidence_ids=list(target.get("evidence_ids", [])), known_edges=edges)
            if not ok:
                continue
            edge = persist_edge(store, node, target, edge_type, result, list(target.get("evidence_ids", [])))
            edge["validation_reason"] = reason
            if store.validate_and_promote(edge):
                edge["status"] = "validated"
            edges.append(edge)
    return edges
