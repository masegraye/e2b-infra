# E2B Infrastructure - Local Development with Docker Compose

This guide explains how to run the E2B infrastructure locally using Docker Compose for development purposes.

## Prerequisites

- Docker and Docker Compose installed
- Go 1.24+ (for local testing)
- Make (for running build commands)

## Quick Start

1. **Copy the environment file**:
   ```bash
   cp .env.dev.example .env.dev
   ```

2. **Start the development environment**:
   ```bash
   docker-compose -f docker-compose.dev.yml up
   ```

3. **Access the services**:
   - API: http://localhost:3000
   - Client Proxy: http://localhost:8080
   - Docker Reverse Proxy: http://localhost:8081
   - PostgreSQL: localhost:5432
   - ClickHouse: localhost:8123 (HTTP), localhost:9000 (TCP)
   - Redis: localhost:6379

## Architecture

The Docker Compose setup includes:

- **postgres**: PostgreSQL database with automatic migration
- **clickhouse**: ClickHouse for analytics data
- **redis**: Redis for caching
- **api**: Main REST API service
- **orchestrator**: Sandbox orchestration service (with privileged access)
- **client-proxy**: Routes traffic between API and orchestrator
- **docker-reverse-proxy**: Docker registry authentication
- **db-migrator**: Runs database migrations on startup
- **clickhouse-migrator**: Runs ClickHouse migrations

## Development Features

### Hot Reloading
All Go services use [Air](https://github.com/cosmtrek/air) for automatic code reloading:
- Code changes trigger automatic rebuilds
- No need to restart containers during development
- Maintains fast iteration cycles

### Volume Mounts
Source code is mounted into containers:
- `./packages/<service>/` → `/app` in container
- `./packages/shared/` → `/shared` (shared libraries)
- Changes to local files immediately reflect in containers

### Service Dependencies
Services start in correct order:
1. Database services (postgres, clickhouse, redis)
2. Migrations (db-migrator, clickhouse-migrator)
3. Core services (api, orchestrator)
4. Proxy services (client-proxy, docker-reverse-proxy)

## Configuration

### Environment Variables
Edit `.env.dev` to customize:
- Database connection strings
- Service ports and timeouts
- Feature flags
- Resource limits

### Development Overrides
Key differences from production:
- `GIN_MODE=debug` for detailed API logging
- `ENVIRONMENT=development` for dev-specific behaviors
- Relaxed security settings for local development
- Simplified networking (no TLS/certificates)

## Working with Individual Services

### Rebuilding a Service
```bash
docker-compose -f docker-compose.dev.yml build api
docker-compose -f docker-compose.dev.yml up -d api
```

### Viewing Logs
```bash
# All services
docker-compose -f docker-compose.dev.yml logs -f

# Specific service
docker-compose -f docker-compose.dev.yml logs -f api
```

### Running Commands in Containers
```bash
# Access API container shell
docker-compose -f docker-compose.dev.yml exec api sh

# Run tests in orchestrator
docker-compose -f docker-compose.dev.yml exec orchestrator go test ./...
```

### Database Operations
```bash
# Connect to PostgreSQL
docker-compose -f docker-compose.dev.yml exec postgres psql -U e2b -d e2b

# Connect to ClickHouse
docker-compose -f docker-compose.dev.yml exec clickhouse clickhouse-client
```

## Limitations

### What Works Locally
- API endpoints and authentication
- Database operations and migrations
- Service-to-service communication
- Basic orchestrator functionality

### What Requires Additional Setup
- **Firecracker VMs**: Requires Linux with specific kernel modules
- **Sandbox creation**: Needs Firecracker and networking setup
- **Template building**: Requires cloud storage integration
- **Production networking**: Container isolation and custom networks

### Orchestrator Limitations
The orchestrator runs in privileged mode but may still need:
- Host networking configuration
- Kernel modules for Firecracker
- Additional system dependencies

## Troubleshooting

### Common Issues

**Port conflicts**:
```bash
# Check if ports are in use
lsof -i :3000  # API port
lsof -i :5432  # PostgreSQL port
```

**Database connection issues**:
```bash
# Check if migrations completed
docker-compose -f docker-compose.dev.yml logs db-migrator
```

**Service startup order**:
```bash
# Restart with dependencies
docker-compose -f docker-compose.dev.yml down
docker-compose -f docker-compose.dev.yml up
```

### Debugging
- Enable verbose logging in `.env.dev`
- Use `docker-compose logs -f <service>` for real-time logs
- Access container shells with `docker-compose exec <service> sh`

## Connecting E2B SDK

To use the E2B SDK with your local infrastructure:

```javascript
import { Sandbox } from '@e2b/code-interpreter'

const sandbox = await Sandbox.create({
  domain: 'localhost:3000',
  // You'll need to create an API key in the local database
  // or modify the auth middleware for development
})
```

## Production Differences

This setup is optimized for development:
- Uses local databases instead of managed cloud services
- Simplified networking without TLS
- Debug logging enabled
- Privileged containers for orchestrator access
- Hot reloading for fast iteration

For production deployment, use the Terraform-based cloud infrastructure described in the main README.