from __future__ import annotations

from dataclasses import dataclass
import hashlib
import re
from typing import Iterable


@dataclass(frozen=True)
class ExtractedNode:
    id: str
    type: str
    label: str
    description: str | None
    scope: str


DEFAULT_TYPE_BY_HEADING = {
    "domain": "domain",
    "topic": "topic",
    "concept": "concept",
    "technology": "technology",
    "standard": "standard",
    "protocol": "protocol",
    "algorithm": "algorithm",
    "architecture": "architecture",
    "component": "component",
    "constraint": "constraint",
    "requirement": "requirement",
    "risk": "risk",
    "decision": "decision",
    "evidence": "evidence",
    "document": "document",
    "practice": "practice",
    "language": "language",
}

TOKEN_RE = re.compile(r"(?m)^\s*[-*]\s+(?P<label>[^\n]+?)\s*$")
HEADING_RE = re.compile(r"(?m)^\s*#{1,6}\s+(?P<heading>[^\n]+?)\s*$")
KV_RE = re.compile(r"(?m)^\s*(?:type|node_type)\s*:\s*(?P<type>[A-Za-z_][A-Za-z0-9_-]*)\s*$")
SCOPE_RE = re.compile(r"(?m)^\s*scope(?:_jurisdiction)?\s*:\s*(?P<scope>[^\n]+?)\s*$")


def normalize_text(value: str) -> str:
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    value = re.sub(r"[\t\x0b\x0c ]+", " ", value.strip())
    return value


def canonical_id(label: str, node_type: str, scope: str) -> str:
    canonical = "|".join((normalize_text(label).casefold(), node_type.casefold(), normalize_text(scope).casefold()))
    return "n_" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _heading_type(heading: str) -> str | None:
    key = re.sub(r"[^a-z0-9_ -]", "", heading.casefold()).strip()
    return DEFAULT_TYPE_BY_HEADING.get(key)


def extract_nodes(document: str, *, allowed_types: Iterable[str], default_type: str = "concept", default_scope: str = "global") -> list[dict]:
    allowed = tuple(dict.fromkeys(allowed_types))
    if not allowed:
        allowed = tuple(DEFAULT_TYPE_BY_HEADING.values())
    allowed_set = set(allowed)
    if default_type not in allowed_set:
        raise ValueError("default_type must be present in allowed_types")
    text = normalize_text(document)
    lines = text.splitlines()
    heading_types: dict[int, str] = {}
    scope_by_line: dict[int, str] = {}
    current_type = default_type
    current_scope = default_scope
    for idx, line in enumerate(lines):
        h = HEADING_RE.match(line)
        if h:
            current_type = _heading_type(h.group("heading")) or current_type
            heading_types[idx] = current_type
        s = SCOPE_RE.match(line)
        if s:
            current_scope = normalize_text(s.group("scope")) or default_scope
            scope_by_line[idx] = current_scope
        if idx not in scope_by_line:
            scope_by_line[idx] = current_scope
        if idx not in heading_types:
            heading_types[idx] = current_type

    explicit_types = {i: m.group("type") for i, line in enumerate(lines) if (m := KV_RE.match(line))}
    candidates: list[tuple[int, str, str, str]] = []
    for m in TOKEN_RE.finditer(text):
        line_idx = text.count("\n", 0, m.start())
        label = normalize_text(m.group("label")).lstrip("-*").strip()
        node_type = explicit_types.get(line_idx, heading_types.get(line_idx, current_type))
        scope = scope_by_line.get(line_idx, default_scope)
        if not label or node_type not in allowed_set:
            continue
        candidates.append((line_idx, node_type, label, scope))

    seen: set[str] = set()
    nodes: list[dict] = []
    for line_idx, node_type, label, scope in candidates:
        node_id = canonical_id(label, node_type, scope)
        if node_id in seen:
            continue
        seen.add(node_id)
        description = None
        if line_idx + 1 < len(lines):
            nxt = normalize_text(lines[line_idx + 1])
            if nxt and not nxt.startswith("#") and not re.match(r"^[-*]\s+", nxt):
                description = nxt
        nodes.append(
            {
                "id": node_id,
                "type": node_type,
                "label": label,
                "description": description,
                "scope": {"domain": scope, "jurisdiction": scope if scope.count("-") == 1 and len(scope) in {2, 5} else None},
                "status": "asserted",
                "provenance": [],
                "confidence": {"overall": 1.0, "semantic": 1.0, "source": 1.0, "structural": 1.0},
            }
        )
    return nodes
