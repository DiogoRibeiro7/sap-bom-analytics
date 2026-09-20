# SAP BOM Analytics 0.1.1

This security patch tightens dependency constraints after newly disclosed vulnerabilities affected versions permitted by 0.1.0.

## Security fixes

- `pyarrow >=23.0.1,<26.0` excludes the affected range for CVE-2026-25087.
- `pymdown-extensions >=11.0.2,<12.0` excludes vulnerable releases affected by path traversal and high-severity ReDoS advisories.
- `mkdocs-material >=9.7.7,<10.0` excludes the DOM XSS-affected releases.
- `markdown >=3.8.1,<4.0` excludes the Python-Markdown denial-of-service advisory.

## Preventive controls

CI and the release workflow now run `pip-audit` against the installed Python environment. Dependabot is also configured for Python dependencies and GitHub Actions.

No database schema or analytical behavior changes are included in 0.1.1.
