# Docker Secrets

Create the following files **before** running `docker compose` so credentials are loaded from Docker secrets instead of being committed to the repository:

```
config/secrets/google_client_id
config/secrets/google_client_secret
config/secrets/github_client_id
config/secrets/github_client_secret
config/secrets/linkedin_client_id
config/secrets/linkedin_client_secret
```

Each file should contain the raw secret value with no extra whitespace. Docker mounts these files at `/run/secrets/*`, and the service reads them via the `_FILE` environment variables in `docker/docker-compose.yml`.
