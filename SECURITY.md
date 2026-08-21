# Security

nomen has no accounts, no persistence, and no generate-time network.

Report vulnerabilities through GitHub's private reporting on this repository. Do not open a public issue for an exploitable finding.

The HTTP server (`nomen serve`) is plain HTTP, bound for local use. Put a reverse proxy in front if it must face a network.
