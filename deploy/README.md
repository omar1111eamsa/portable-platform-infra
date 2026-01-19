# Local Backend Deployment

This directory contains the **Docker Compose setup** used to run the backend stack locally
by orchestrating multiple independent service repositories.

Docker Compose builds application services from source and runs official infrastructure
images to reproduce a production-like environment on a developer machine.

---

## Required Repository Structure

Docker Compose relies on **relative build paths**.
Repositories must be structured exactly as follows:

BACKEND/
├── API-GATEWAY/
│ └── dockerfile
├── USER-SERVICE/
│ └── dockerfile
├── PORTABLE-PLATFORM/
│ └── deploy/
│ └── docker-compose.yml

---

## What Docker Compose Does

- Builds **API Gateway** and **User Service** from their Dockerfiles
- Runs official images for:
  - PostgreSQL
  - Redis
  - Consul
- Connects all services on a shared Docker network
- Enables service discovery via Consul

---

## Run Locally

From the `deploy/local` directory:

```bash
docker compose up -d --build
```

---

Exposed Services

API Gateway: http://localhost:8888

User Service: http://localhost:8081

Consul UI: http://localhost:8500

