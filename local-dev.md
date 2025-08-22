# Local Development Environment for E2B

This guide explains how to run the complete E2B infrastructure locally for development and testing purposes.

## Quick Setup

For a quick automated setup, use the provided setup script:

```bash
./local-dev/setup-local-dev.sh
```

This script will:
- Configure your hosts file (requires sudo)
- Generate SSL certificates
- Start all services
- Extract development credentials
- Create .env.local file for the E2B CLI
- Build the CLI (if pnpm is available)

For custom hostname:
```bash
DOCKER_HOSTNAME=registry.mylocal.dev ./local-dev/setup-local-dev.sh
```

## Template Building Setup

To successfully build templates in the local environment, follow these additional steps after the initial setup:

### 1. Create Template Database Entries

Templates must exist in the database before they can be built. For each template you want to build:

```bash
# Get team and user IDs
docker compose -f docker-compose.dev.yml exec -T postgres psql -U postgres -d e2b -c "SELECT t.id as team_id, u.id as user_id FROM teams t JOIN users_teams ut ON t.id = ut.team_id JOIN auth.users u ON u.id = ut.user_id LIMIT 1;"

# Create template entry (replace TEMPLATE_ID, TEAM_ID, USER_ID with actual values)
docker compose -f docker-compose.dev.yml exec -T postgres psql -U postgres -d e2b -c "INSERT INTO envs (id, team_id, created_by, updated_at) VALUES ('TEMPLATE_ID', 'TEAM_ID', 'USER_ID', CURRENT_TIMESTAMP) ON CONFLICT (id) DO NOTHING;"
```

**Important**: Use the exact `template_id` from your `e2b.toml` file, not the `template_name`.

### 2. Template Build Process

With the database entry created, you can now build templates:

```bash
cd /path/to/your/template/directory
E2B_DEBUG=true E2B_API_KEY=your_api_key E2B_ACCESS_TOKEN=your_access_token ../../e2b-local template build
```

The build process will:
1. ✅ Create/update template in database
2. ✅ Login to local Docker registry (`docker.localhost`)  
3. ✅ Build Docker image with template Dockerfile
4. ✅ Push image to local registry via docker-reverse-proxy
5. ✅ Trigger orchestrator build process
6. ⚠️ Build Firecracker VM (may fail due to envd dependencies)

### 3. Common Issues and Solutions

**404 Template Not Found**: 
- Ensure template exists in database with exact ID from `e2b.toml`
- Check `template_id` in your config file matches database entry

**409 Alias Conflict**:
- Clean up old test templates: `DELETE FROM envs WHERE id = 'old_template_id';`

**Docker Push Errors**:
- Verify docker-reverse-proxy logs show "Development mode: proxying to local registry"
- Check nginx proxy is running: `docker compose logs docker-registry-proxy`
- Ensure certificates exist in `local-dev/certs/`

**Build Failure (`/fc-envd/envd: no such file or directory`)**:
- This is expected in local development - the Firecracker environment daemon is not available
- The Docker registry and template creation parts are working correctly

### 4. Template Management APIs

The API provides endpoints for template management:

**Create New Template** (POST `/templates`):
```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"dockerfile": "FROM ubuntu:latest", "alias": "my-template"}' \
     http://localhost:3000/templates
```

**Rebuild Existing Template** (POST `/templates/{templateID}`):
```bash  
curl -H "Authorization: Bearer YOUR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"dockerfile": "FROM ubuntu:latest"}' \
     http://localhost:3000/templates/your-template-id
```

**Trigger Build** (POST `/templates/{templateID}/builds/{buildID}`):
```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
     -X POST \
     http://localhost:3000/templates/your-template-id/builds/your-build-id
```

These APIs handle the database operations automatically, including:
- Creating/updating entries in the `envs` table
- Managing build records in `env_builds` table  
- Handling template aliases in `env_aliases` table

## What Was Fixed for Template Building

The template building functionality required several components to work together:

### 1. Docker Registry Authentication Chain
- **nginx proxy** (`docker-registry-proxy`) terminates HTTPS and forwards to docker-reverse-proxy
- **docker-reverse-proxy** handles authentication via access tokens and proxies to local registry
- **local-registry** (Docker Registry v2) stores the actual container images

### 2. Environment Variable Configuration
The docker-reverse-proxy now supports full configuration via environment variables:
- `LOCAL_REGISTRY_URL` - URL of local registry backend
- `EXTERNAL_REGISTRY_DOMAIN` - External domain for client access
- `LOCAL_REGISTRY_HOST` - Internal host for Location header rewriting
- `E2B_REGISTRY_NAMESPACE` - Registry namespace (e2b/custom-envs)

### 3. Development Mode Detection
When `ENVIRONMENT=development`, the proxy automatically:
- Returns dummy tokens instead of calling GCP APIs
- Proxies to local registry instead of GCP registry  
- Skips URL rewriting for namespace conversion
- Removes authorization headers when forwarding to local registry
- Rewrites Location headers from internal to external domains

### 4. Database Prerequisites
Templates must exist in the `envs` table before building:
- Template ID must match exactly between `e2b.toml` and database
- Templates require `team_id`, `created_by`, and `updated_at` fields
- The API will handle creating build records and aliases automatically

### 5. Build Flow (Now Working)
1. ✅ CLI reads template config (`e2b.toml`)
2. ✅ API validates template exists in database  
3. ✅ CLI logs into Docker registry (`docker login docker.localhost`)
4. ✅ CLI builds Docker image with template
5. ✅ CLI pushes image through nginx → docker-reverse-proxy → local-registry
6. ✅ API triggers orchestrator build process
7. ⚠️ Orchestrator attempts Firecracker build (expected to fail in local dev)

## Prerequisites

- **Docker** and **Docker Compose**
- **Node.js** >= 18
- **pnpm** package manager (for CLI building)
- **OpenSSL** (for certificate generation)
- **PostgreSQL client tools** (optional, for direct database access)

## Quick Start

### 1. Start the Local Infrastructure

```bash
cd /path/to/e2b-infra
docker compose -f docker-compose.dev.yml up --build
```

This will start all required services:
- **PostgreSQL** (port 5432) - Main database
- **ClickHouse** (ports 8123, 9000) - Analytics database  
- **Redis** (port 6379) - Caching
- **API** (port 3000) - Main API service with hot reloading
- **Orchestrator** (ports 5007-5008) - Orchestration service
- **Client-proxy** (port 8080) - Client proxy service
- **Docker-reverse-proxy** (internal) - Docker registry backend
- **Docker-registry-proxy** (ports 80, 443) - HTTPS Docker registry proxy

### 2. Bootstrap Development Credentials

The local environment requires a user account with API keys. Create one by inserting a user into the database:

```bash
# Create a development user (this automatically creates team and API keys)
docker compose -f docker-compose.dev.yml exec postgres psql -U postgres -d e2b -c "INSERT INTO auth.users (email) VALUES ('dev@example.com') RETURNING *;"

# Get the generated API key
docker compose -f docker-compose.dev.yml exec postgres psql -U postgres -d e2b -c "SELECT api_key FROM team_api_keys ORDER BY created_at DESC LIMIT 1;"
```

Copy the returned API key (format: `e2b_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`).

**Get the Access Token for Template Operations:**

```bash
# Get the generated access token (needed for template building)
docker compose -f docker-compose.dev.yml exec postgres psql -U postgres -d e2b -c "SELECT access_token FROM team_access_tokens ORDER BY created_at DESC LIMIT 1;"
```

Copy the returned access token (format: `sk_e2b_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`).

### 3. Configure Environment Variables

Create a `.env.local` file in the e2b-E2B root directory:

```bash
cd /path/to/e2b-E2B
cat > .env.local << EOF
# Local Development Environment Variables for E2B
E2B_DEBUG=true
E2B_API_KEY=your_api_key_from_step_2_here
E2B_ACCESS_TOKEN=your_access_token_from_step_2_here
E2B_ADMIN_TOKEN=dev-admin-token-123
E2B_DOMAIN=localhost
EOF
```

### 4. Build and Use the CLI

```bash
# Navigate to the CLI package
cd /path/to/e2b-E2B/packages/cli

# Install dependencies (if not already installed)
pnpm install

# Build the CLI
pnpm build

# Go back to the e2b-E2B root and use the convenient wrapper script
cd ..
./e2b-local sandbox list
```

## CLI Usage Examples

Using the convenient wrapper script (recommended):

```bash
# From the e2b-E2B root directory

# List sandboxes
./e2b-local sandbox list

# Get CLI help
./e2b-local --help

# List sandbox commands
./e2b-local sandbox --help

# List templates (when available)
./e2b-local template list
```

Alternatively, using environment variables directly:

```bash
# From packages/cli directory
E2B_DEBUG=true E2B_API_KEY=e2b_xxx node dist/index.js sandbox list
```

## Admin API Usage

The admin token provides access to infrastructure management endpoints:

```bash
# List orchestrator nodes
curl -H "X-Admin-Token: dev-admin-token-123" http://localhost:3000/admin/nodes

# Get specific node details
curl -H "X-Admin-Token: dev-admin-token-123" http://localhost:3000/admin/nodes/{nodeID}
```

These endpoints are useful for:
- Monitoring cluster health
- Debugging orchestration issues
- Managing node status during development

## SDK Usage

When using the E2B SDKs with your local infrastructure:

### JavaScript/TypeScript
```javascript
import { Sandbox } from "e2b";

const sandbox = new Sandbox({
  debug: true, // This makes it connect to localhost:3000
  apiKey: "e2b_your_api_key_here"
});
```

### Python
```python
from e2b import Sandbox

sandbox = Sandbox(
  debug=True,  # This makes it connect to localhost:3000
  api_key="e2b_your_api_key_here"
)
```

## Environment Configuration

The local development environment uses these key configurations:

- **`E2B_DEBUG=true`** - Makes SDKs/CLI connect to `http://localhost:3000`
- **`ENVIRONMENT=development`** - Sets the API service to development mode
- **`ADMIN_TOKEN=dev-admin-token-123`** - Admin token for node management endpoints

## Database Access

You can access the PostgreSQL database directly for debugging:

```bash
# Connect to the database
docker compose -f docker-compose.dev.yml exec postgres psql -U postgres -d e2b

# List all tables
\dt

# Check users and teams
SELECT * FROM auth.users;
SELECT * FROM teams;
SELECT * FROM team_api_keys;
```

## Docker Registry Setup for Template Building

The local environment includes a complete Docker registry system that enables template building functionality without requiring cloud dependencies. This setup consists of multiple components working together to provide a seamless Docker registry experience.

### Host File Configuration

Add the following entry to your system's hosts file (`/etc/hosts` on macOS/Linux, `C:\Windows\System32\drivers\etc\hosts` on Windows):

```
127.0.0.1 docker.localhost
```

### Self-Signed Certificate Generation

The development environment uses self-signed certificates for HTTPS. These are automatically generated by the setup script, but if you need to regenerate them manually:

```bash
cd /path/to/e2b-infra

# Create certs directory
mkdir -p local-dev/certs

# Generate self-signed certificate for docker.localhost (or your custom hostname)
openssl req -x509 -newkey rsa:4096 -keyout local-dev/certs/docker.localhost.key -out local-dev/certs/docker.localhost.crt -days 365 -nodes \
  -subj "/C=US/ST=CA/L=SF/O=E2B/OU=Dev/CN=docker.localhost" \
  -addext "subjectAltName=DNS:docker.localhost,DNS:localhost,IP:127.0.0.1"
```

## Environment Variable Configuration

The docker-reverse-proxy service now supports configuration via environment variables for flexible deployment:

### Registry Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LOCAL_REGISTRY_URL` | `http://local-registry:5000` | URL of the local Docker registry container |
| `EXTERNAL_REGISTRY_DOMAIN` | `docker.localhost` | External domain name for registry access via HTTPS |
| `LOCAL_REGISTRY_HOST` | `local-registry:5000` | Host:port for local registry (used in Location header rewriting) |
| `E2B_REGISTRY_NAMESPACE` | `e2b/custom-envs` | Repository namespace for E2B templates |
| `DOCKER_HOSTNAME` | `docker.localhost` | Hostname for the Docker registry (used in nginx config) |

### Environment Mode Variables

| Variable | Value | Description |
|----------|-------|-------------|
| `ENVIRONMENT` | `development` | Enables development mode (local registry, dummy tokens, etc.) |

### Example Custom Configuration

To use a different hostname (e.g., `registry.local`):

```bash
# Set environment variables
export DOCKER_HOSTNAME=registry.local
export EXTERNAL_REGISTRY_DOMAIN=registry.local

# Run setup script
./local-dev/setup-local-dev.sh --hostname registry.local

# Or start services manually
docker compose -f docker-compose.dev.yml up --build
```

The setup script automatically configures all these variables based on your chosen hostname.

### Docker Registry Architecture

The local setup includes three Docker registry components:

1. **local-registry** - Official Docker Registry v2 container that stores images locally
2. **docker-reverse-proxy** - Go service that handles authentication and proxies to local registry
3. **docker-registry-proxy** - Nginx HTTPS proxy that terminates SSL and forwards to docker-reverse-proxy

The complete request flow:
```
Docker CLI → nginx (docker.localhost:443) → docker-reverse-proxy → local-registry:5000 → local storage
```

### Development Mode Configuration

The docker-reverse-proxy automatically detects development mode via `ENVIRONMENT=development` and:

- **Returns dummy tokens** instead of calling GCP token APIs
- **Proxies to local registry** (`http://local-registry:5000`) instead of GCP registry
- **Skips URL rewriting** - preserves E2B namespace format instead of converting to GCP format
- **Removes authorization headers** when forwarding to local registry (no auth required)
- **Rewrites Location headers** in responses from `local-registry:5000` to `docker.localhost`

### Template Building Workflow

```bash
# Navigate to a directory with a Dockerfile and e2b.toml
cd /path/to/your/template

# Build and push the template
./e2b-local template build

# The CLI will:
# 1. Login to docker.localhost using your access token (gets dummy token)
# 2. Build the Docker image with the template configuration
# 3. Push the image through the proxy chain to local registry storage
# 4. Register the template with the orchestrator
```

### Local Registry Storage

Images are stored persistently in the `registry_data` Docker volume. You can inspect what's stored:

```bash
# List repositories in local registry
curl -s http://localhost:5001/v2/_catalog

# List tags for a repository
curl -s http://localhost:5001/v2/{repository}/tags/list

# The local registry is also temporarily exposed on port 5001 for debugging
```

### Code Changes Made for Local Development

The following minimal code changes were made to support local development:

1. **Token Generation** (`packages/docker-reverse-proxy/internal/handlers/token.go`):
   - Added development mode check to return dummy tokens instead of calling GCP

2. **Registry Proxy Target** (`packages/docker-reverse-proxy/internal/handlers/store.go`):
   - Added development mode detection to proxy to local registry instead of GCP
   - Added Location header rewriting to fix registry redirects

3. **URL Path Handling** (`packages/docker-reverse-proxy/internal/handlers/proxy.go`):
   - Skip GCP namespace rewriting in development mode
   - Remove authorization headers when proxying to local registry

4. **Docker Compose Configuration** (`docker-compose.dev.yml`):
   - Added `local-registry` service with Docker Registry v2
   - Added `LOCAL_REGISTRY_URL` environment variable
   - Added persistent `registry_data` volume

## Hot Reloading

All Go services (API, orchestrator, client-proxy, docker-reverse-proxy) support hot reloading using Air. Changes to source code will automatically rebuild and restart the services.

## Troubleshooting

### Services Not Starting
Check service logs:
```bash
docker compose -f docker-compose.dev.yml logs <service-name>
```

### Authentication Errors
Verify your API key:
```bash
docker compose -f docker-compose.dev.yml exec postgres psql -U postgres -d e2b -c "SELECT api_key, created_at FROM team_api_keys ORDER BY created_at DESC;"
```

### Database Issues
Reset the database:
```bash
docker compose -f docker-compose.dev.yml down -v
docker compose -f docker-compose.dev.yml up --build
```

### CLI Build Issues
Ensure you're using pnpm (not npm) in the workspace:
```bash
cd /path/to/e2b-E2B
pnpm install
cd packages/cli
pnpm build
```

### Docker Registry Connection Issues
If template building fails with Docker registry errors:

```bash
# Verify host file configuration
ping docker.localhost  # Should resolve to 127.0.0.1

# Check if nginx proxy is running
docker compose -f docker-compose.dev.yml logs docker-registry-proxy

# Verify certificate files exist
ls -la local-dev/certs/docker.localhost.*

# Test HTTPS connection manually
curl -k https://docker.localhost/v2/
```

### Template Build Authentication Errors
If you get authentication errors during template building:

```bash
# Verify your access token is correct
docker compose -f docker-compose.dev.yml exec postgres psql -U postgres -d e2b -c "SELECT access_token FROM team_access_tokens ORDER BY created_at DESC;"

# Update your .env.local file with the correct access token
# Ensure it starts with sk_e2b_

# Try the template build again
./e2b-local template build
```

### Docker Login Issues
If Docker login fails for the local registry:

```bash
# Clear any existing Docker login sessions
docker logout docker.localhost

# Manually test Docker login with your access token
echo "your_access_token_here" | docker login docker.localhost -u _e2b_access_token --password-stdin

# If successful, template building should work
```

### Template Push/Pull Issues
If Docker push/pull operations fail:

```bash
# Check if all registry services are running
docker compose -f docker-compose.dev.yml ps local-registry docker-reverse-proxy docker-registry-proxy

# Check docker-reverse-proxy logs for errors
docker compose -f docker-compose.dev.yml logs docker-reverse-proxy --tail=20

# Test direct access to local registry (for debugging)
curl -s http://localhost:5001/v2/

# Test token generation
curl -k -s "https://docker.localhost/v2/token?service=registry&scope=repository:e2b/custom-envs/test:pull,push" -u "_e2b_access_token:your_access_token_here"
```

### Registry Connection Issues
If you see connection timeouts or failures:

```bash
# Restart the entire registry stack
docker compose -f docker-compose.dev.yml restart local-registry docker-reverse-proxy docker-registry-proxy

# Check nginx proxy configuration
docker compose -f docker-compose.dev.yml exec docker-registry-proxy nginx -t

# Verify internal registry connectivity
docker compose -f docker-compose.dev.yml exec docker-reverse-proxy curl -i http://local-registry:5000/v2/
```

### Reset Registry Data
If you need to clear all stored registry data:

```bash
# Stop services
docker compose -f docker-compose.dev.yml down

# Remove registry data volume
docker volume rm e2b-infra_registry_data

# Restart infrastructure
docker compose -f docker-compose.dev.yml up --build
```

## Architecture

The local development setup includes:

1. **PostgreSQL** - Stores users, teams, API keys, templates, and sandboxes
2. **ClickHouse** - Analytics and metrics storage  
3. **Redis** - Caching layer
4. **API Service** - Main REST API (Go with Gin framework)
5. **Orchestrator** - Manages sandbox lifecycle and templates
6. **Client Proxy** - Handles WebSocket connections for sandbox access
7. **Docker Registry Services** - Local Docker registry with HTTPS proxy for template storage

## Development Workflow

1. **Start the infrastructure**: `docker compose -f docker-compose.dev.yml up --build`
2. **Configure host file**: Add `127.0.0.1 docker.localhost` to `/etc/hosts`
3. **Create development credentials** (one time):
   - Create database user and extract API key + access token
4. **Configure `.env.local` file** with API key and access token
5. **Build CLI**: `cd packages/cli && pnpm build`
6. **Verify registry setup**: Test `docker login docker.localhost` works
7. **Make changes to source code** (hot reloading active)
8. **Test with CLI**: `./e2b-local <command>`
9. **Build templates**: `./e2b-local template build` in template directories
10. **Access services**:
    - API: http://localhost:3000
    - Client Proxy: http://localhost:8080  
    - Docker Registry (HTTPS): https://docker.localhost
    - Local Registry (HTTP, debug): http://localhost:5001

## Project Files

After setup, your e2b-E2B directory will contain:

- `.env.local` - Your development environment variables (git-ignored)
- `e2b-local` - Convenient CLI wrapper script (git-ignored)
- Standard e2b project files...

## Differences from Production

- **No cloud dependencies** - Everything runs in containers
- **Simplified authentication** - Direct API key usage, no OAuth
- **Development-friendly settings** - Debug logging, hot reloading
- **In-memory/local storage** - No external storage requirements
- **Relaxed security** - Suitable for development only

This local setup provides a complete E2B development environment without requiring cloud resources or complex deployment procedures.