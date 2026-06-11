# Security Policy

## Supported Versions

Security fixes target the current `main` branch until versioned releases are
published.

## Reporting a Vulnerability

Use GitHub private vulnerability reporting if it is enabled for the repository.
If it is not available, open a public issue with a short summary only and ask
for a private disclosure channel. Do not include Jenkins controller URLs,
credentials IDs tied to real systems, tokens, job logs, or exploit details in
public.

## CI/CD Safety

Do not commit:

- Jenkins credentials or tokens
- private SCM URLs
- controller hostnames that are not intentionally public
- generated Job DSL for a real environment
- logs that reveal secret values or deployment targets
