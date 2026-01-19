# Backend Management Service

## Overview

This repository is the **central infrastructure and deployment control plane** for the backend services of the platform.  
It is responsible for **orchestrating, configuring, and deploying backend microservices and supporting infrastructure** in a secure, reproducible, and scalable way.

**Application source code is intentionally not stored here.**  
Each backend service (e.g. user-service, api-gateway) lives in its own dedicated repository.

---

## Responsibilities of This Repository

This repository manages **how backend services run**, not **how they are implemented**.

It provides:
- Container orchestration (Docker & Docker Compose)
- Service-to-service infrastructure (Consul, Redis, PostgreSQL)
- Environment-specific deployment definitions (local / production)
- CI/CD deployment workflows
- Operational scripts for backend environments

---

## What This Repository Does NOT Contain

For clarity and security, this repository does **not** contain:
- Application business logic
- Backend service source code
- Frontend code
- Secrets, credentials, or private keys
- Environment-specific sensitive values

All secrets are expected to be injected at runtime via:
- CI/CD secrets
- Environment variables
- Secure secret managers (future)

---

## Repository Structure

portable-platform/
├── deploy/

│   ├── local/                  # Local development deployments

│   └── prod/                   # Production deployment definitions

│

├── infra/

│   ├── consul/                 # Service discovery configuration

│   ├── postgres/               # Database infrastructure

│   └── redis/                  # Cache & rate-limiting infrastructure

│

├── services/

│   ├── api-gateway/            # Deployment wiring for API Gateway

│   └── user-service/           # Deployment wiring for User Service

│

├── scripts/                    # Operational and helper scripts

│

├── .github/

│   └── workflows/              # CI/CD pipelines (build & deploy)

│
└── README.md

