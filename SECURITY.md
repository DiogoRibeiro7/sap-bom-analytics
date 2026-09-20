# Security Policy

## Supported versions

Security fixes are applied to the most recent released version.

| Version | Supported |
| --- | --- |
| 0.1.1 | Yes |
| 0.1.0 | No |

Users of 0.1.0 should upgrade because its dependency constraints permit versions affected by published security advisories.

## Reporting a vulnerability

Please do not disclose sensitive vulnerability details in a public issue.

Use GitHub's private **Report a vulnerability** / Security Advisory flow for this repository when available.

If private reporting is unavailable, open a minimal public issue stating only that you need a private channel for a security report. Do not include exploit details, credentials, private data, or proof-of-concept material in that issue.

## Dependency security

The repository uses several independent controls:

- Dependabot for Python and GitHub Actions updates;
- dependency review on pull requests;
- `pip-audit` in CI and before releases;
- CodeQL analysis for Python;
- CycloneDX SBOM generation for releases;
- SHA-256 release checksums;
- GitHub artifact attestations backed by Sigstore/OIDC.

## Release verification

GitHub release artifacts can be checked against `SHA256SUMS`.

For releases generated after provenance attestation was enabled, GitHub attestations can also be verified with the GitHub CLI:

```bash
gh attestation verify <artifact> --repo DiogoRibeiro7/sap-bom-analytics
```
