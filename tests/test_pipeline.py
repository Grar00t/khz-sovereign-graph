from src.inference.pipeline import PipelineConfig, score_candidates, validate_relation


def test_score_candidates_is_deterministic():
    source = {"id": "n_" + "a" * 64}
    candidates = [
        {"id": "n_" + "b" * 64, "semantic": 1, "lexical": .5, "structural": .5, "type_compatibility": .5, "evidence": .5},
        {"id": "n_" + "c" * 64, "semantic": .9, "lexical": .9, "structural": .9, "type_compatibility": .9, "evidence": .9},
    ]
    a = score_candidates(source, candidates, config=PipelineConfig())
    b = score_candidates(source, candidates, config=PipelineConfig())
    assert a == b
    assert a[0]["decision"] == "review"


def test_validate_relation_rejects_cycles_and_missing_evidence():
    source = {"id": "n_" + "a" * 64}
    target = {"id": "n_" + "b" * 64}
    ok, reason = validate_relation(source, target, "causes", evidence_ids=[], known_edges=[])
    assert not ok and reason == "evidence_required"
    ok, reason = validate_relation(
        source,
        target,
        "depends_on",
        evidence_ids=[],
        known_edges=[
            {"source": target["id"], "target": source["id"], "type": "depends_on", "status": "validated"}
        ],
    )
    assert not ok and reason == "cycle_detected"
