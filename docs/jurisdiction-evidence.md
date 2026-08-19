# Jurisdiction Evidence

The runtime mapping in `db/migrations/002_canonical_v2_1_hardening.sql` is intentionally conservative seed data, not a legal conclusion.

Each jurisdiction row contains an explicit evidence locator. Rows whose locator begins with `UNVERIFIED_ASSERTION:` require replacement with an approved legal or regulatory source and its SHA-256 digest before a production compliance claim is made.

Verification query:

```sql
select jurisdiction_code, regime, version, residency_required, cross_border_allowed, evidence_locator, evidence_sha256
from skg_policy.jurisdictions
order by jurisdiction_code;
```

Production status remains `UNVERIFIED ASSERTION` until authoritative evidence is inserted and independently reviewed.
