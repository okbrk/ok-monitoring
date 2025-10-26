#!/usr/bin/env bash
set -euo pipefail

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO] ${1}${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] ${1}${NC}"
}

# --- Pre-flight Checks ---
info "Running pre-flight checks..."
for cmd in terraform kubectl helmfile jq aws step ts; do
    if ! command -v $cmd &> /dev/null; then
        warn "Command '$cmd' not found. Please install it first."
        exit 1
    fi
done

if [ ! -f "k8s/observability/secrets.env" ]; then
    warn "secrets.env file not found at k8s/observability/secrets.env. Please create it by following the README."
    exit 1
fi
source k8s/observability/secrets.env

# Check for necessary environment variables
REQUIRED_VARS=("HCLOUD_TOKEN" "SSH_KEY_NAME" "MY_IP_CIDR" "LOCATION" "TS_AUTHKEY")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var-}" ]; then # Using -z and parameter expansion to check if var is unset or empty
        warn "Required environment variable '$var' is not set in k8s/observability/secrets.env."
        exit 1
    fi
done

info "Pre-flight checks passed."

# --- Phase 1: Provision Infrastructure ---
info "Phase 1: Provisioning infrastructure with Terraform..."
(cd infra/terraform && \
    terraform init && \
    terraform apply -auto-approve \
    -var "hcloud_token=$HCLOUD_TOKEN" \
    -var "ssh_key_name=$SSH_KEY_NAME" \
    -var "my_ip_cidr=$MY_IP_CIDR" \
    -var "location=$LOCATION")
info "Terraform provisioning complete."

# --- Phase 2: Get Node IPs ---
info "Phase 2: Gathering node IP addresses..."
NODE0_PUBLIC_IP=$(cd infra/terraform && terraform output -json node_public_ips | jq -r '.[0]')
NODE1_PUBLIC_IP=$(cd infra/terraform && terraform output -json node_public_ips | jq -r '.[1]')
NODE2_PUBLIC_IP=$(cd infra/terraform && terraform output -json node_public_ips | jq -r '.[2]')
NODE0_PRIVATE_IP=$(cd infra/terraform && terraform output -json node_private_ips | jq -r '.[0]')
NODE1_PRIVATE_IP=$(cd infra/terraform && terraform output -json node_private_ips | jq -r '.[1]')
NODE2_PRIVATE_IP=$(cd infra/terraform && terraform output -json node_private_ips | jq -r '.[2]')
info "Node IPs gathered."

# --- Phase 3: Configure VPN & Bootstrap k3s ---
info "Phase 3: Configuring VPN and bootstrapping k3s..."
info "Cloning repo and installing Tailscale on all nodes..."
ssh-keyscan $NODE0_PUBLIC_IP $NODE1_PUBLIC_IP $NODE2_PUBLIC_IP >> ~/.ssh/known_hosts 2>/dev/null

ssh root@$NODE0_PUBLIC_IP "git clone https://github.com/okbrk/ok-monitoring.git && cd ok-monitoring/scripts && TS_AUTHKEY=$TS_AUTHKEY bash tailscale-up.sh" &
ssh root@$NODE1_PUBLIC_IP "git clone https://github.com/okbrk/ok-monitoring.git && cd ok-monitoring/scripts && TS_AUTHKEY=$TS_AUTHKEY bash tailscale-up.sh" &
ssh root@$NODE2_PUBLIC_IP "git clone https://github.com/okbrk/ok-monitoring.git && cd ok-monitoring/scripts && TS_AUTHKEY=$TS_AUTHKEY bash tailscale-up.sh" &
wait
info "Tailscale installed on all nodes. Please approve subnet routes in the Tailscale admin console."
read -p "Press [Enter] to continue once routes are approved..."

info "Getting node-0's Tailscale IP..."
NODE0_TS_IP=$(ssh root@$NODE0_PUBLIC_IP "tailscale ip -4")
sed -i '' "s/GRAFANA_NODE_TS_IP=.*/GRAFANA_NODE_TS_IP=${NODE0_TS_IP}/" k8s/observability/secrets.env
source k8s/observability/secrets.env
info "GRAFANA_NODE_TS_IP set to: $GRAFANA_NODE_TS_IP"

info "Bootstrapping k3s server on node-0..."
ssh root@$NODE0_PUBLIC_IP "cd ok-monitoring/scripts && bash bootstrap-k3s.sh server ${NODE0_PRIVATE_IP} ${GRAFANA_NODE_TS_IP}"

info "Getting k3s join token..."
K3S_TOKEN=$(ssh root@$NODE0_PUBLIC_IP "cat /var/lib/rancher/k3s/server/node-token")
K3S_URL="https://$(echo $NODE0_PRIVATE_IP):6443"

info "Bootstrapping k3s agents on node-1 and node-2..."
ssh root@$NODE1_PUBLIC_IP "export K3S_URL='$K3S_URL'; export K3S_TOKEN='$K3S_TOKEN'; cd ok-monitoring/scripts && bash bootstrap-k3s.sh agent ${NODE1_PRIVATE_IP}" &
ssh root@$NODE2_PUBLIC_IP "export K3S_URL='$K3S_URL'; export K3S_TOKEN='$K3S_TOKEN'; cd ok-monitoring/scripts && bash bootstrap-k3s.sh agent ${NODE2_PRIVATE_IP}" &
wait
info "k3s bootstrap complete."

# --- Phase 4: Configure Local Kubectl ---
info "Phase 4: Configuring local kubectl..."
mkdir -p ~/.kube
ssh root@$NODE0_PUBLIC_IP "cat /etc/rancher/k3s/k3s.yaml" | sed "s/127.0.0.1/$GRAFANA_NODE_TS_IP/" | sed "s/$NODE0_PRIVATE_IP/$GRAFANA_NODE_TS_IP/" > ~/.kube/config-hetzner
export KUBECONFIG=~/.kube/config-hetzner
info "Kubeconfig saved to ~/.kube/config-hetzner. Waiting for nodes to become ready..."

while [ $(kubectl get nodes --no-headers | grep "Ready" | wc -l) -ne 3 ]; do
    info "Waiting for all 3 nodes to be Ready..."
    sleep 10
done
info "All nodes are Ready."
kubectl get nodes -o wide

# --- Phase 5: Deploy Kubernetes Services ---
info "Phase 5: Deploying all Kubernetes services..."

info "Deploying base services (metrics-server, cert-manager)..."
helmfile -f k8s/base/helmfile.yaml apply

info "Waiting for base services to be ready..."
kubectl -n cert-manager wait --for=condition=Ready pods --all --timeout=5m
kubectl -n kube-system wait --for=condition=Ready pods -l app.kubernetes.io/name=metrics-server --timeout=2m

info "Deploying internal DNS..."
sed -i '' "s/__GRAFANA_NODE_TS_IP__/${GRAFANA_NODE_TS_IP}/" k8s/net-dns/coredns.yaml
kubectl apply -f k8s/net-dns/coredns.yaml
info "Please configure split DNS for 'ok' in the Tailscale admin console, pointing to ${GRAFANA_NODE_TS_IP}."
read -p "Press [Enter] to continue once split DNS is configured..."

info "Deploying internal PKI..."
# This part is complex to automate safely. For now, we follow the manual steps.
# In a real-world scenario, you'd use a pre-existing CA or a more robust automated process.
warn "Manual step required for PKI setup. Following README Step 8a..."
mkdir -p ./.pki && cd ./.pki
STEPPASS=$(openssl rand -base64 20)
step ca init --name="ok-ca" --provisioner="admin" --dns="ca.ok" \
--address=":8443" --password-file <(echo -n "$STEPPASS") --provisioner-password-file <(echo -n "$STEPPASS")
kubectl create namespace step-ca --dry-run=client -o yaml | kubectl apply -f -
kubectl -n step-ca create secret generic step-ca-password --from-literal "password=${STEPPASS}"
kubectl -n step-ca create secret generic step-ca-certs --from-file=./certs/root_ca.crt --from-file=./certs/intermediate_ca.crt
kubectl -n step-ca create secret generic step-ca-secrets --from-file=./secrets/intermediate_ca_key --from-file=./secrets/root_ca_key
step ca provisioner add acme --type ACME
cat > ca.json <<EOL
{
    "root": "/home/step/certs/root_ca.crt",
    "key": "/home/step/secrets/root_ca_key",
    "address": ":9000",
    "dns": ["step-ca.step-ca.svc.cluster.local"],
    "db": {"type": "badgerv2", "dataSource": "/home/step/db"},
    "authority": { "provisioners": [ { "type": "ACME", "name": "acme" } ] }
}
EOL
kubectl -n step-ca create secret generic step-ca-config --from-file=ca.json
cd .. && rm -rf ./.pki
kubectl apply -f k8s/pki/step-ca.yaml
kubectl apply -f k8s/pki/cluster-issuer.yaml
info "PKI deployed. Waiting for it to become ready..."
kubectl -n step-ca wait --for=condition=Ready pods --all --timeout=2m

info "Deploying Ingress Controller..."
helmfile -f k8s/ingress/nginx-helmfile.yaml apply
kubectl -n ingress-nginx wait --for=condition=Ready pods --all --timeout=5m

info "Creating Wasabi buckets..."
bash scripts/wasabi-buckets.sh

info "Deploying Observability Stack..."
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl -n observability create secret generic obs-secrets --from-env-file k8s/observability/secrets.env
helmfile -f k8s/observability/helmfile.yaml apply
kubectl apply -f k8s/observability/grafana-cert.yaml
info "Observability stack deployment initiated. It may take 5-10 minutes for all pods to become ready."

# --- Final Instructions ---
info "--- SETUP COMPLETE ---"
info "It may take several minutes for all observability pods to start up."
info "You can monitor the progress with: kubectl get pods -n observability -w"
info "Once ready, you can access Grafana at: https://grafana.ok"
