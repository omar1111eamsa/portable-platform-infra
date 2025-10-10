# ==============================================
# User Management Service Makefile
# ==============================================

NAME = user_management_service
BUILD_DIR = build

# Default target
all: build

# ----------------------------------------------
# BUILD COMMANDS
# ----------------------------------------------

build:
	@echo "🔧 Configuring and building $(NAME)..."
	@mkdir -p $(BUILD_DIR)
	@cd $(BUILD_DIR) && cmake .. && make -j$$(nproc)
	@echo "✅ Build complete."

rebuild: fclean build

# ----------------------------------------------
# CLEAN COMMANDS
# ----------------------------------------------

clean:
	@echo "🧹 Cleaning object files..."
	@cd $(BUILD_DIR) && make clean || true

fclean:
	@echo "🧽 Full clean: removing build directory..."
	@rm -rf $(BUILD_DIR)
	@echo "✅ Clean complete."

# ----------------------------------------------
# RUN COMMAND
# ----------------------------------------------

run: build
	@echo "🚀 Running $(NAME)..."
	@./$(BUILD_DIR)/$(NAME)

# ----------------------------------------------
# HELP
# ----------------------------------------------

help:
	@echo "Usage:"
	@echo "  make build      - Configure and compile the project"
	@echo "  make rebuild    - Clean and rebuild from scratch"
	@echo "  make clean      - Remove object files"
	@echo "  make fclean     - Full clean (remove build dir)"
	@echo "  make run        - Build and run the binary"
	@echo "  make help       - Show this help message"
	@echo "  make docker-build - Build Docker images (service + tests)"
	@echo "  make docker-run   - Start the docker-compose stack"
	@echo "  make docker-test  - Run unit tests inside Docker"
	@echo "  make docker-integration - Run HTTP integration tests via Docker"
	@echo "  make perf-smoke - Execute local latency smoke test"

# ----------------------------------------------
# DOCKER COMMANDS
# ----------------------------------------------

DOCKER_COMPOSE := docker compose -f docker/docker-compose.yml

docker-build:
	@echo "🐳 Building Docker images..."
	@$(DOCKER_COMPOSE) build

docker-run:
	@echo "🚢 Starting docker-compose stack..."
	@$(DOCKER_COMPOSE) up user_service

docker-test:
	@echo "🧪 Running unit tests inside Docker..."
	@$(DOCKER_COMPOSE) run --rm user_service_tests

docker-integration:
	@echo "🔗 Running integration tests inside Docker..."
	@set -e; \
	trap '$(DOCKER_COMPOSE) down >/dev/null 2>&1 || true' EXIT; \
	$(DOCKER_COMPOSE) up -d user_service postgres redis >/dev/null; \
	sleep 3; \
	$(DOCKER_COMPOSE) run --rm integration_tests

perf-smoke:
	@echo "⏱  Running performance smoke script..."
	@./scripts/perf_smoke.sh
