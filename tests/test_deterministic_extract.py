from src.inference.deterministic_extract import extract_nodes


def test_extract_nodes_is_deterministic_and_content_addressed():
    doc = """# Technology\n- PostgreSQL\n- PostgreSQL\n\nscope: SA\n- Data sovereignty\n"""
    a = extract_nodes(doc, allowed_types=("technology", "concept"), default_scope="global")
    b = extract_nodes(doc, allowed_types=("technology", "concept"), default_scope="global")
    assert a == b
    assert len(a) == 2
    assert all(n["id"].startswith("n_") and len(n["id"]) == 66 for n in a)
    assert all(len(n["provenance"]) == 0 for n in a)


def test_extract_nodes_rejects_ontology_invention():
    doc = "- Something\n"
    nodes = extract_nodes(doc, allowed_types=("technology",))
    assert nodes == []
