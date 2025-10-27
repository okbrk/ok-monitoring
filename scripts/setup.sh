#!/usr/bin/env bash
set -euo pipefail

# Automated setup script for simplified multi-tenant observability platform
# This script provisions infrastructure and deploys the Docker Compose stack

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step() { echo -e "\n${BLUE}==== $1 ====${NC}\n"; }

# --- Pre-flight Checks ---
step "Pre-flight Checks"

info "Checking required tools..."
REQUIRED_TOOLS=("terraform" "jq" "ssh" "scp")
for cmd in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v $cmd &> /dev/null; then
        error "Command '$cmd' not found. Please install it first."
        exit 1
    fi
done
info "All required tools are installed"

# Check for .env file
if [ ! -f "$PROJECT_ROOT/.env" ]; then
    error ".env file not found. Please copy env.example to .env and fill in your values."
    exit 1
fi

# Load environment variables
set -a
source "$PROJECT_ROOT/.env"
set +a

# Check for required environment variables
REQUIRED_VARS=("HCLOUD_TOKEN" "SSH_KEY_NAME" "MY_IP_CIDR" "DOMAIN" "GRAFANA_ADMIN_PASSWORD" "POSTGRES_PASSWORD" "TAILSCALE_AUTHKEY" "WASABI_REGION" "WASABI_ENDPOINT" "S3_LOKI_ACCESS_KEY_ID" "S3_LOKI_SECRET_ACCESS_KEY" "S3_MIMIR_ACCESS_KEY_ID" "S3_MIMIR_SECRET_ACCESS_KEY" "S3_TEMPO_ACCESS_KEY_ID" "S3_TEMPO_SECRET_ACCESS_KEY" "SSH_KEY_FILE")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        error "Required environment variable '$var' is not set in .env file."
        exit 1
    fi
done
info "All required environment variables are set"

# Expand tilde in SSH_KEY_FILE
SSH_KEY_FILE="${SSH_KEY_FILE/#\~/$HOME}"

# Verify SSH key file exists
if [ ! -f "$SSH_KEY_FILE" ]; then
    error "SSH key file not found: $SSH_KEY_FILE"
    exit 1
fi
info "SSH key file found: $SSH_KEY_FILE"

# Verify SSH key exists in Hetzner
info "Verifying SSH key exists in Hetzner..."
if ! curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" \
    "https://api.hetzner.cloud/v1/ssh_keys" | \
    grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$SSH_KEY_NAME\""; then
    error "SSH key '$SSH_KEY_NAME' not found in Hetzner Cloud"
    error "Available keys:"
    curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" \
        "https://api.hetzner.cloud/v1/ssh_keys" | \
        grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' | \
        sed 's/"name"[[:space:]]*:[[:space:]]*"/  - /' | sed 's/"$//' || echo "  (none)"
    exit 1
fi
info "SSH key '$SSH_KEY_NAME' found in Hetzner"

# --- Phase 1: Provision Infrastructure ---
step "Phase 1: Provisioning Infrastructure with Terraform"

cd "$PROJECT_ROOT/infra/terraform"

info "Initializing Terraform..."
terraform init

info "Planning Terraform changes..."
terraform plan \
    -var "hcloud_token=$HCLOUD_TOKEN" \
    -var "ssh_key_name=$SSH_KEY_NAME" \
    -var "my_ip_cidr=$MY_IP_CIDR" \
    -var "location=${LOCATION:-nbg1}" \
    -out=tfplan

info "Applying Terraform configuration..."
terraform apply -auto-approve tfplan
rm -f tfplan

info "Terraform provisioning complete"

# Get server details
SERVER_IP=$(terraform output -raw server_public_ip)
SERVER_NAME=$(terraform output -raw server_name)

info "Server provisioned: $SERVER_NAME @ $SERVER_IP"

# Add server to SSH config
info "Adding server to ~/.ssh/config..."
SSH_CONFIG_ENTRY="
# Observability Platform - Added by setup script
Host ok-obs
  HostName $SERVER_IP
  User root
  IdentityFile $SSH_KEY_FILE
  StrictHostKeyChecking accept-new
"

# Check if entry already exists
if grep -q "Host ok-obs" ~/.ssh/config 2>/dev/null; then
    info "SSH config entry already exists, updating..."
    # Remove old entry and add new one
    sed -i.bak '/# Observability Platform/,/^$/d' ~/.ssh/config 2>/dev/null || true
fi

# Ensure .ssh directory exists
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Create config if it doesn't exist
touch ~/.ssh/config
chmod 600 ~/.ssh/config

# Add new entry
echo "$SSH_CONFIG_ENTRY" >> ~/.ssh/config

info "SSH config updated. You can now connect with: ssh ok-obs"

# --- Phase 2: Wait for Server and Setup Tailscale ---
step "Phase 2: Waiting for Server to Initialize"

info "Adding server to known_hosts..."
ssh-keyscan -H "$SERVER_IP" >> ~/.ssh/known_hosts 2>/dev/null

info "Waiting for SSH to become available (this may take 1-2 minutes)..."
MAX_SSH_RETRIES=60
SSH_RETRY_COUNT=0
while [ $SSH_RETRY_COUNT -lt $MAX_SSH_RETRIES ]; do
    # Now use the ok-obs alias from SSH config
    if ssh -o ConnectTimeout=5 \
           -o BatchMode=yes \
           ok-obs "echo 'SSH Ready'" &>/dev/null; then
        info "SSH is available and key authentication working!"
        break
    fi
    SSH_RETRY_COUNT=$((SSH_RETRY_COUNT + 1))
    if [ $((SSH_RETRY_COUNT % 6)) -eq 0 ]; then
        echo -n " ${SSH_RETRY_COUNT}s"
    else
        echo -n "."
    fi
    sleep 5
done
echo ""

if [ $SSH_RETRY_COUNT -eq $MAX_SSH_RETRIES ]; then
    error "Timed out waiting for SSH to become available"
    error "This usually means:"
    error "  1. SSH key '$SSH_KEY_NAME' not properly configured in Hetzner"
    error "  2. Cloud-init hasn't finished (wait 2-3 more minutes and retry)"
    error "  3. Firewall blocking SSH from your IP"
    error ""
    error "Try manually: ssh ok-obs"
    exit 1
fi

info "Waiting for Docker and Tailscale to be installed (cloud-init may take 2-5 minutes)..."
MAX_RETRIES=60
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if ssh -o ConnectTimeout=5 \
           -o BatchMode=yes \
           ok-obs "command -v docker >/dev/null 2>&1 && command -v tailscale >/dev/null 2>&1" 2>/dev/null; then
        info "Docker and Tailscale are ready!"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $((RETRY_COUNT % 6)) -eq 0 ]; then
        echo -n " ${RETRY_COUNT}s"
    else
        echo -n "."
    fi
    sleep 5
done
echo ""

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    error "Timed out waiting for Docker/Tailscale installation"
    error "Check cloud-init logs on server: ssh ok-obs 'tail -100 /var/log/cloud-init-output.log'"
    exit 1
fi

info "Verifying Docker networking is ready..."
if ssh ok-obs "docker pull hello-world" &>/dev/null; then
    info "Docker networking is ready!"
    ssh ok-obs "docker rmi hello-world" &>/dev/null || true
else
    warn "Docker networking slow, waiting 30 more seconds..."
    sleep 30
fi

info "Connecting server to Tailscale network..."
ssh ok-obs "tailscale up --authkey=${TAILSCALE_AUTHKEY} --hostname=obs-server"

info "Getting Tailscale IP..."
TAILSCALE_IP=$(ssh ok-obs "tailscale ip -4")
info "Server Tailscale IP: $TAILSCALE_IP"

# Save Tailscale IP to .env file
if grep -q "^TAILSCALE_IP=" "$PROJECT_ROOT/.env"; then
    sed -i.bak "s/^TAILSCALE_IP=.*/TAILSCALE_IP=${TAILSCALE_IP}/" "$PROJECT_ROOT/.env"
else
    echo "TAILSCALE_IP=${TAILSCALE_IP}" >> "$PROJECT_ROOT/.env"
fi
rm -f "$PROJECT_ROOT/.env.bak"

# --- Phase 3: Deploy Application Stack ---
step "Phase 3: Deploying Observability Stack"

info "Creating application directory on server..."
ssh ok-obs "mkdir -p /opt/observability && mkdir -p /opt/observability-data"

info "Copying application files to server..."
cd "$PROJECT_ROOT"

# Create tarball of required files
tar czf /tmp/obs-stack.tar.gz \
    --exclude='*.bak' \
    docker-compose.yml \
    config/ \
    scripts/tenant-management/

# Copy and extract on server
scp /tmp/obs-stack.tar.gz ok-obs:/opt/observability/
ssh ok-obs "cd /opt/observability && tar xzf obs-stack.tar.gz && rm obs-stack.tar.gz"
rm /tmp/obs-stack.tar.gz

info "Creating .env file on server..."
ssh ok-obs "cat > /opt/observability/.env" <<ENVFILE
DOMAIN=${DOMAIN}
DATA_DIR=/opt/observability-data
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
TAILSCALE_IP=${TAILSCALE_IP}
WASABI_REGION=${WASABI_REGION}
WASABI_ENDPOINT=${WASABI_ENDPOINT}
S3_LOKI_ACCESS_KEY_ID=${S3_LOKI_ACCESS_KEY_ID}
S3_LOKI_SECRET_ACCESS_KEY=${S3_LOKI_SECRET_ACCESS_KEY}
S3_MIMIR_ACCESS_KEY_ID=${S3_MIMIR_ACCESS_KEY_ID}
S3_MIMIR_SECRET_ACCESS_KEY=${S3_MIMIR_SECRET_ACCESS_KEY}
S3_TEMPO_ACCESS_KEY_ID=${S3_TEMPO_ACCESS_KEY_ID}
S3_TEMPO_SECRET_ACCESS_KEY=${S3_TEMPO_SECRET_ACCESS_KEY}
ENVFILE

info "Starting Docker Compose stack (pulling images may take 2-3 minutes)..."
MAX_DOCKER_RETRIES=3
DOCKER_RETRY=0

while [ $DOCKER_RETRY -lt $MAX_DOCKER_RETRIES ]; do
    if ssh ok-obs "cd /opt/observability && docker compose up -d" 2>&1 | tee /tmp/docker-compose-output.log; then
        if ! grep -q "Error" /tmp/docker-compose-output.log; then
            info "Docker Compose stack started successfully!"
            break
        fi
    fi

    DOCKER_RETRY=$((DOCKER_RETRY + 1))
    if [ $DOCKER_RETRY -lt $MAX_DOCKER_RETRIES ]; then
        warn "Docker pull failed, retrying in 10 seconds... (attempt $((DOCKER_RETRY + 1))/$MAX_DOCKER_RETRIES)"
        sleep 10
    fi
done

if [ $DOCKER_RETRY -eq $MAX_DOCKER_RETRIES ]; then
    error "Failed to start Docker Compose stack after $MAX_DOCKER_RETRIES attempts"
    error "Try manually: ssh ok-obs 'cd /opt/observability && docker compose up -d'"
    exit 1
fi

info "Waiting for services to become healthy..."
sleep 15

# Check service status
ssh ok-obs "cd /opt/observability && docker compose ps"

# --- Phase 4: Create S3 Buckets ---
step "Phase 4: Creating S3 Buckets on Wasabi"

info "Running Wasabi bucket creation script..."
bash "$PROJECT_ROOT/scripts/wasabi-buckets.sh"

# --- Phase 5: Create Admin Tenant ---
step "Phase 5: Initializing Admin Tenant"

info "Waiting for PostgreSQL to be ready..."
sleep 15

info "Creating admin tenant..."
ssh ok-obs "cd /opt/observability && bash scripts/tenant-management/create-tenant.sh 'Platform Admin' 'admin@${DOMAIN}' admin" | tee /tmp/admin-tenant.txt

# Extract admin API key from output
ADMIN_API_KEY=$(grep "API Key:" /tmp/admin-tenant.txt | awk '{print $3}')

# --- Phase 6: Configure DNS ---
step "Phase 6: DNS Configuration"

warn "IMPORTANT: Configure your DNS records to point to the server:"
echo ""
echo "  Domain:        ${DOMAIN}"
echo "  IP Address:    ${SERVER_IP}"
echo ""
echo "  Required DNS A records:"
echo "    ${DOMAIN}          ->  ${SERVER_IP}"
echo "    api.${DOMAIN}      ->  ${SERVER_IP}"
echo "    otlp.${DOMAIN}     ->  ${SERVER_IP}"
echo ""
info "Caddy will automatically obtain Let's Encrypt certificates once DNS is configured."

# --- Final Instructions ---
step "Setup Complete!"

echo ""
echo "========================================="
echo "Observability Platform Deployed"
echo "========================================="
echo ""
echo "Server Details:"
echo "  IP Address:    ${SERVER_IP}"
echo "  Server Name:   ${SERVER_NAME}"
echo ""
echo "Customer Data Ingestion Endpoints (PUBLIC):"
echo "  API Endpoint:  https://api.${DOMAIN}"
echo "  OTLP gRPC:     https://otlp.${DOMAIN}:443"
echo "  Health Check:  https://api.${DOMAIN}/health"
echo ""
echo "Admin Access (VPN-ONLY via Tailscale):"
echo "  Grafana:       http://${TAILSCALE_IP}:3000"
echo "  Tailscale IP:  ${TAILSCALE_IP}"
echo ""
echo "Admin Credentials:"
echo "  Username:      ${GRAFANA_ADMIN_USER:-admin}"
echo "  Password:      ${GRAFANA_ADMIN_PASSWORD}"
echo "  Platform API Key: ${ADMIN_API_KEY:-<see admin-tenant.txt>}"
echo ""
warn "IMPORTANT SECURITY NOTE:"
echo "  - Grafana is NOT publicly accessible"
echo "  - Connect to Tailscale VPN to access admin tools"
echo "  - Only public endpoints are for customer data ingestion"
echo ""
echo "Next Steps:"
echo "  1. Configure DNS A records (see above)"
echo "  2. Connect to your Tailscale network"
echo "  3. Access Grafana at http://${TAILSCALE_IP}:3000"
echo "  4. Create tenant accounts: ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/create-tenant.sh'"
echo ""
echo "Useful Commands:"
echo "  SSH to server:     ssh ok-obs"
echo "  View logs:         ssh ok-obs 'cd /opt/observability && docker compose logs -f'"
echo "  Restart services:  ssh ok-obs 'cd /opt/observability && docker compose restart'"
echo "  List tenants:      ssh ok-obs 'cd /opt/observability && bash scripts/tenant-management/list-tenants.sh'"
echo ""

cd "$PROJECT_ROOT"
info "Setup script completed successfully!"
