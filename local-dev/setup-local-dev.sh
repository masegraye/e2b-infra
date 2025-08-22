#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOCKER_HOSTNAME=${DOCKER_HOSTNAME:-docker.localhost}
CERT_DIR="local-dev/certs"
HOSTS_FILE=""

# Detect OS and set hosts file path
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    HOSTS_FILE="/etc/hosts"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    HOSTS_FILE="/etc/hosts"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    HOSTS_FILE="/c/Windows/System32/drivers/etc/hosts"
else
    echo -e "${RED}Unsupported OS: $OSTYPE${NC}"
    exit 1
fi

echo -e "${BLUE}🚀 E2B Local Development Setup${NC}"
echo "=============================================="
echo "Setting up local E2B development environment..."
echo

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to add hosts entry
add_hosts_entry() {
    local hostname=$1
    local ip="127.0.0.1"
    
    echo -e "${YELLOW}📋 Checking hosts file configuration...${NC}"
    
    # Check if entry already exists
    if grep -q "$ip $hostname" "$HOSTS_FILE" 2>/dev/null; then
        echo -e "${GREEN}✓ Hosts entry already exists: $ip $hostname${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}⚠️  Need to add hosts entry: $ip $hostname${NC}"
    echo "This requires sudo access to modify $HOSTS_FILE"
    echo
    
    # Try to add the entry
    if command_exists sudo; then
        echo "$ip $hostname" | sudo tee -a "$HOSTS_FILE" > /dev/null
        echo -e "${GREEN}✓ Added hosts entry: $ip $hostname${NC}"
    else
        echo -e "${RED}❌ sudo not available. Please manually add this line to $HOSTS_FILE:${NC}"
        echo "   $ip $hostname"
        echo
        read -p "Press Enter when you've added the hosts entry..."
    fi
}

# Function to generate certificates
generate_certificates() {
    local hostname=$1
    
    echo -e "${YELLOW}🔐 Generating SSL certificates for $hostname...${NC}"
    
    # Create certs directory if it doesn't exist
    mkdir -p "$CERT_DIR"
    
    # Check if certificates already exist
    if [[ -f "$CERT_DIR/$hostname.crt" && -f "$CERT_DIR/$hostname.key" ]]; then
        echo -e "${GREEN}✓ SSL certificates already exist${NC}"
        return 0
    fi
    
    # Generate self-signed certificate
    openssl req -x509 -newkey rsa:4096 -keyout "$CERT_DIR/$hostname.key" -out "$CERT_DIR/$hostname.crt" -days 365 -nodes \
        -subj "/C=US/ST=CA/L=SF/O=E2B/OU=Dev/CN=$hostname" \
        -addext "subjectAltName=DNS:$hostname,DNS:localhost,IP:127.0.0.1" \
        2>/dev/null
    
    echo -e "${GREEN}✓ Generated SSL certificates in $CERT_DIR/${NC}"
}

# Function to check and start infrastructure
setup_infrastructure() {
    echo -e "${YELLOW}🐳 Setting up Docker infrastructure...${NC}"
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker is not running. Please start Docker and try again.${NC}"
        exit 1
    fi
    
    # Build and start services
    echo "Building and starting services..."
    docker compose -f docker-compose.dev.yml up --build -d
    
    echo -e "${GREEN}✓ Infrastructure started${NC}"
}

# Function to setup database and extract credentials
setup_credentials() {
    echo -e "${YELLOW}🔑 Setting up development credentials...${NC}"
    
    # Wait for database to be ready
    echo "Waiting for database to be ready..."
    local retries=30
    while ! docker compose -f docker-compose.dev.yml exec -T postgres pg_isready -U postgres >/dev/null 2>&1; do
        ((retries--))
        if [[ $retries -eq 0 ]]; then
            echo -e "${RED}❌ Database failed to start${NC}"
            exit 1
        fi
        sleep 2
        echo -n "."
    done
    echo
    
    # Create user if not exists
    echo "Creating development user..."
    docker compose -f docker-compose.dev.yml exec -T postgres psql -U postgres -d e2b -c \
        "INSERT INTO auth.users (email) VALUES ('dev@example.com') ON CONFLICT (email) DO NOTHING;" >/dev/null 2>&1 || true
    
    # Get API key
    API_KEY=$(docker compose -f docker-compose.dev.yml exec -T postgres psql -U postgres -d e2b -t -c \
        "SELECT api_key FROM team_api_keys ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | tr -d ' \n\r')
    
    # Get access token  
    ACCESS_TOKEN=$(docker compose -f docker-compose.dev.yml exec -T postgres psql -U postgres -d e2b -t -c \
        "SELECT access_token FROM team_access_tokens ORDER BY created_at DESC LIMIT 1;" 2>/dev/null | tr -d ' \n\r')
    
    if [[ -z "$API_KEY" || -z "$ACCESS_TOKEN" ]]; then
        echo -e "${RED}❌ Failed to extract credentials from database${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Extracted development credentials${NC}"
}

# Function to create .env.local file
create_env_file() {
    local e2b_dir="../e2b-E2B"
    
    echo -e "${YELLOW}📄 Creating .env.local file...${NC}"
    
    # Check if e2b-E2B directory exists
    if [[ ! -d "$e2b_dir" ]]; then
        echo -e "${YELLOW}⚠️  E2B directory not found at $e2b_dir${NC}"
        echo "Please specify the path to your e2b-E2B directory:"
        read -p "Path: " e2b_dir
        
        if [[ ! -d "$e2b_dir" ]]; then
            echo -e "${RED}❌ Directory not found: $e2b_dir${NC}"
            exit 1
        fi
    fi
    
    # Create .env.local file
    cat > "$e2b_dir/.env.local" << EOF
# Local Development Environment Variables for E2B
# This file contains credentials for connecting to your local e2b-infra

# Set to true to connect to local infrastructure (http://localhost:3000)
E2B_DEBUG=true

# API key generated from local database (used for sandbox operations)
E2B_API_KEY=$API_KEY

# Access token generated from local database (used for template operations)
E2B_ACCESS_TOKEN=$ACCESS_TOKEN

# Admin token for infrastructure management endpoints
E2B_ADMIN_TOKEN=dev-admin-token-123

# Use localhost domain for HTTPS Docker registry via nginx proxy
E2B_DOMAIN=localhost
EOF
    
    echo -e "${GREEN}✓ Created .env.local file in $e2b_dir${NC}"
    echo -e "${BLUE}   API Key: $API_KEY${NC}"
    echo -e "${BLUE}   Access Token: $ACCESS_TOKEN${NC}"
}

# Function to build CLI
build_cli() {
    local e2b_dir="../e2b-E2B"
    
    echo -e "${YELLOW}🔨 Building E2B CLI...${NC}"
    
    if [[ ! -d "$e2b_dir/packages/cli" ]]; then
        echo -e "${YELLOW}⚠️  CLI directory not found, skipping CLI build${NC}"
        return 0
    fi
    
    # Check if pnpm is available
    if ! command_exists pnpm; then
        echo -e "${YELLOW}⚠️  pnpm not found, skipping CLI build${NC}"
        echo "   Install pnpm and run: cd $e2b_dir/packages/cli && pnpm install && pnpm build"
        return 0
    fi
    
    # Build CLI
    cd "$e2b_dir/packages/cli"
    pnpm install >/dev/null 2>&1
    pnpm build >/dev/null 2>&1
    cd - >/dev/null
    
    echo -e "${GREEN}✓ Built E2B CLI${NC}"
}

# Function to test setup
test_setup() {
    echo -e "${YELLOW}🧪 Testing setup...${NC}"
    
    # Test API endpoint
    if curl -s http://localhost:3000/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓ API service responding${NC}"
    else
        echo -e "${YELLOW}⚠️  API service not responding (may still be starting)${NC}"
    fi
    
    # Test Docker registry
    if curl -k -s https://$DOCKER_HOSTNAME/v2/ >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Docker registry responding${NC}"
    else
        echo -e "${YELLOW}⚠️  Docker registry not responding (may still be starting)${NC}"
    fi
    
    # Test local registry
    if curl -s http://localhost:5001/v2/ >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Local registry responding${NC}"
    else
        echo -e "${YELLOW}⚠️  Local registry not responding${NC}"
    fi
}

# Function to display next steps
show_next_steps() {
    local e2b_dir="../e2b-E2B"
    
    echo
    echo -e "${GREEN}🎉 Local development environment setup complete!${NC}"
    echo "=============================================="
    echo
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Wait for all services to fully start (check with: docker compose -f docker-compose.dev.yml logs)"
    echo "2. Test Docker login: echo \"$ACCESS_TOKEN\" | docker login $DOCKER_HOSTNAME -u _e2b_access_token --password-stdin"
    echo "3. Build templates: cd $e2b_dir && ./e2b-local template build"
    echo
    echo -e "${BLUE}Useful commands:${NC}"
    echo "• View services: docker compose -f docker-compose.dev.yml ps"
    echo "• View logs: docker compose -f docker-compose.dev.yml logs [service-name]"
    echo "• Stop services: docker compose -f docker-compose.dev.yml down"
    echo "• Access API: http://localhost:3000"
    echo "• Access Docker Registry: https://$DOCKER_HOSTNAME"
    echo
    echo -e "${BLUE}Troubleshooting:${NC}"
    echo "• See local-dev.md for detailed troubleshooting steps"
    echo "• Registry catalog: curl -s http://localhost:5001/v2/_catalog"
    echo
}

# Main setup function
main() {
    echo -e "${BLUE}Starting setup with Docker hostname: $DOCKER_HOSTNAME${NC}"
    echo
    
    # Check prerequisites
    echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
    
    if ! command_exists docker; then
        echo -e "${RED}❌ Docker not found. Please install Docker first.${NC}"
        exit 1
    fi
    
    if ! command_exists openssl; then
        echo -e "${RED}❌ OpenSSL not found. Please install OpenSSL first.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Prerequisites check passed${NC}"
    echo
    
    # Run setup steps
    add_hosts_entry "$DOCKER_HOSTNAME"
    echo
    
    generate_certificates "$DOCKER_HOSTNAME"  
    echo
    
    setup_infrastructure
    echo
    
    setup_credentials
    echo
    
    create_env_file
    echo
    
    build_cli
    echo
    
    test_setup
    echo
    
    show_next_steps
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "E2B Local Development Setup Script"
        echo
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --hostname HOST     Set Docker hostname (default: docker.localhost)"
        echo
        echo "Environment Variables:"
        echo "  DOCKER_HOSTNAME     Docker hostname to use (default: docker.localhost)"
        echo
        exit 0
        ;;
    --hostname)
        if [[ -z "${2:-}" ]]; then
            echo -e "${RED}❌ --hostname requires a value${NC}"
            exit 1
        fi
        DOCKER_HOSTNAME="$2"
        shift 2
        ;;
    "")
        # No arguments, proceed with setup
        ;;
    *)
        echo -e "${RED}❌ Unknown argument: $1${NC}"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main setup
main "$@"