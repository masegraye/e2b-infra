# Local Development Environment for E2B

This guide explains how to run the complete E2B infrastructure locally for development and testing purposes.

## Prerequisites

- **Docker** and **Docker Compose**
- **Node.js** >= 18
- **pnpm** package manager
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
- **Docker-reverse-proxy** (port 8081) - Docker registry proxy

### 2. Bootstrap Development Credentials

The local environment requires a user account with API keys. Create one by inserting a user into the database:

```bash
# Create a development user (this automatically creates team and API keys)
docker compose -f docker-compose.dev.yml exec postgres psql -U postgres -d e2b -c "INSERT INTO auth.users (email) VALUES ('dev@example.com') RETURNING *;"

# Get the generated API key
docker compose -f docker-compose.dev.yml exec postgres psql -U postgres -d e2b -c "SELECT api_key FROM team_api_keys ORDER BY created_at DESC LIMIT 1;"
```

Copy the returned API key (format: `e2b_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`).

### 3. Configure Environment Variables

Create a `.env.local` file in the e2b-E2B root directory:

```bash
cd /path/to/e2b-E2B
cat > .env.local << EOF
# Local Development Environment Variables for E2B
E2B_DEBUG=true
E2B_API_KEY=your_api_key_from_step_2_here
E2B_ADMIN_TOKEN=dev-admin-token-123
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

## Architecture

The local development setup includes:

1. **PostgreSQL** - Stores users, teams, API keys, templates, and sandboxes
2. **ClickHouse** - Analytics and metrics storage  
3. **Redis** - Caching layer
4. **API Service** - Main REST API (Go with Gin framework)
5. **Orchestrator** - Manages sandbox lifecycle and templates
6. **Proxy Services** - Handle client connections and Docker registry operations

## Development Workflow

1. Start the infrastructure: `docker compose -f docker-compose.dev.yml up`
2. Create development credentials (one time)
3. Configure `.env.local` file with your API key
4. Make changes to source code (hot reloading active)
5. Test with CLI: `./e2b-local <command>`
6. Access services:
   - API: http://localhost:3000
   - Client Proxy: http://localhost:8080  
   - Docker Registry Proxy: http://localhost:8081

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