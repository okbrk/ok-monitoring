# Scalable Observability Cluster on Hetzner with k3s and Tailscale

This guide provides a complete walkthrough for building a private, scalable observability stack using Grafana, Loki, Mimir, and Tempo on a k3s cluster hosted on Hetzner Cloud. All access is secured via Tailscale, with no public ingress.

The cluster state you provided indicates potential issues with storage, core DNS, and application startup order. This guide is designed to address that by building the environment incrementally and verifying each component before proceeding.

## Table of Contents

1.  [Prerequisites](#1-prerequisites)
2.  [Environment Setup](#2-environment-setup)
3.  [Provision Infrastructure (Terraform)](#3-provision-infrastructure-terraform)
4.  [Bootstrap Kubernetes (k3s)](#4-bootstrap-kubernetes-k3s)
5.  [Configure VPN (Tailscale)](#5-configure-vpn-tailscale)
6.  [Deploy Base Services](#6-deploy-base-services)
7.  [Configure Internal DNS (CoreDNS)](#7-configure-internal-dns-coredns)
8.  [Configure Internal PKI (step-ca)](#8-configure-internal-pki-step-ca)
9.  [Deploy Ingress Controller](#9-deploy-ingress-controller)
10. [Create Object Storage (Wasabi)](#10-create-object-storage-wasabi)
11. [Deploy Observability Stack](#11-deploy-observability-stack)
12. [Accessing Grafana](#12-accessing-grafana)

---

## 1) Prerequisites

Before you begin, ensure you have the following tools installed locally:
- [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) (>= 1.0)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [helm](https://helm.sh/docs/intro/install/)
- [helmfile](https://github.com/helmfile/helmfile#installation)
- [jq](https://stedolan.github.io/jq/download/)
- [aws-cli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (for Wasabi S3)
- [step-cli](https://smallstep.com/docs/step-cli/installation)
- [Tailscale](https://tailscale.com/download/)

You will also need accounts for:
- [Hetzner Cloud](https://www.hetzner.com/cloud)
- [Tailscale](https://login.tailscale.com/login)
- [Wasabi](https://wasabi.com/)
- An OIDC provider (e.g., Google, GitHub, Auth0) for Grafana SSO.

---

## 2) Environment Setup

All required secrets and configuration variables will be managed in a single file for simplicity. For production, you should encrypt this file using [SOPS](https://github.com/getsops/sops).

### a) Create the Secrets File

Create a file named `k8s/observability/secrets.env` and populate it with the following variables. Replace the placeholder values with your actual secrets and configuration.

```bash
# k8s/observability/secrets.env

# Hetzner
export HCLOUD_TOKEN="<your-hetzner-cloud-api-token>"
export SSH_KEY_NAME="<your-ssh-key-name-in-hcloud>"
export MY_IP_CIDR="<your-public-ip>/32" # e.g. 1.2.3.4/32
export LOCATION="nbg1"

# Tailscale
export TS_AUTHKEY="<your-tailscale-auth-key>"

# Wasabi
export WASABI_REGION="eu-central-1"
export WASABI_ENDPOINT="https://s3.${WASABI_REGION}.wasabisys.com"
export S3_LOKI_ACCESS_KEY_ID="<your-loki-access-key>"
export S3_LOKI_SECRET_ACCESS_KEY="<your-loki-secret-key>"
export S3_TEMPO_ACCESS_KEY_ID="<your-tempo-access-key>"
export S3_TEMPO_SECRET_ACCESS_KEY="<your-tempo-secret-key>"
export S3_MIMIR_ACCESS_KEY_ID="<your-mimir-access-key>"
export S3_MIMIR_SECRET_ACCESS_KEY="<your-mimir-secret-key>"

# Grafana / OIDC
export GRAFANA_ADMIN_USER="admin"
export GRAFANA_ADMIN_PASSWORD="<generate-a-strong-password>"
export OIDC_CLIENT_ID="<your-oidc-client-id>"
export OIDC_CLIENT_SECRET="<your-oidc-client-secret>"
export OIDC_AUTH_URL="<your-oidc-auth-url>"
export OIDC_TOKEN_URL="<your-oidc-token-url>"
export OIDC_API_URL="<your-oidc-api-url>"
export OIDC_ALLOWED_DOMAINS="<your-domain.com>"

# Default Tenant for Grafana Stack
export DEFAULT_TENANT="global"

# Placeholder for a node's Tailscale IP, to be filled in later
export GRAFANA_NODE_TS_IP=""
```
**Note:** The `SSH_KEY_NAME` must match the name of an SSH key you have already added to your Hetzner Cloud project.

### b) Source the Environment

In your terminal, source this file to load the variables into your environment. You will need to do this in any new terminal session you use to interact with the cluster.

```bash
source k8s/observability/secrets.env
```
Verify that a variable is set:
```bash
echo $HCLOUD_TOKEN
```

---

## 3) Provision Infrastructure (Terraform)

This step will create the virtual machines, private network, and firewall on Hetzner Cloud.

### a) Review Terraform Files

The files in `infra/terraform/` define the infrastructure:
- `main.tf`: Provider configuration and locals.
- `network.tf`: A private network for the nodes.
- `firewall.tf`: Firewall rules to allow SSH, Tailscale, and internal traffic only.
- `nodes.tf`: The three `cx22` servers (1 master, 2 agents) that will form the cluster.
- `cloud-init.yaml`: A basic cloud-init script to install necessary packages on boot.

### b) Destroy Existing Infrastructure (Recommended)

To ensure a clean start, destroy any infrastructure you may have created previously.

```bash
# Ensure you are in the correct directory
cd infra/terraform

# Source the environment variables if you haven't already
source ../../k8s/observability/secrets.env

# Destroy any existing resources
terraform init
terraform destroy -auto-approve \
  -var "hcloud_token=$HCLOUD_TOKEN" \
  -var "ssh_key_name=$SSH_KEY_NAME" \
  -var "my_ip_cidr=$MY_IP_CIDR" \
  -var "location=$LOCATION"
```

### c) Apply Terraform

Now, provision the new infrastructure.

```bash
# Apply the Terraform configuration
terraform apply -auto-approve \
  -var "hcloud_token=$HCLOUD_TOKEN" \
  -var "ssh_key_name=$SSH_KEY_NAME" \
  -var "my_ip_cidr=$MY_IP_CIDR" \
  -var "location=$LOCATION"

# Go back to the root directory
cd ../..
```

### d) Verify

After Terraform completes, it will output the public and private IP addresses of your new nodes.
1.  Make a note of these IPs.
2.  Try to SSH into one of the nodes to confirm they are running and accessible. Replace `<node-0-public-ip>` with the public IP of `ok-node-0`.

    ```bash
    ssh root@<node-0-public-ip>
    ```

You should be able to connect successfully. This confirms your infrastructure is ready for the next step.

---

## 4) Configure VPN (Tailscale)

Before installing k3s, we will install Tailscale on all nodes. This allows us to get the master node's stable Tailscale IP and provide it to k3s during installation. This ensures the API server's certificate is valid for the IP we will use for `kubectl`.

### a) Install Tailscale on All Nodes

Run the `tailscale-up.sh` script on all three nodes.

```bash
# Get node public IPs
NODE0_PUBLIC_IP=$(cd infra/terraform && terraform output -json node_public_ips | jq -r '.[0]')
NODE1_PUBLIC_IP=$(cd infra/terraform && terraform output -json node_public_ips | jq -r '.[1]')
NODE2_PUBLIC_IP=$(cd infra/terraform && terraform output -json node_public_ips | jq -r '.[2]')

# Run on node-0
ssh root@$NODE0_PUBLIC_IP "git clone https://github.com/okbrk/ok-monitoring.git && cd ok-monitoring/scripts && TS_AUTHKEY=$TS_AUTHKEY bash tailscale-up.sh"

# Run on node-1
ssh root@$NODE1_PUBLIC_IP "git clone https://github.com/okbrk/ok-monitoring.git && cd ok-monitoring/scripts && TS_AUTHKEY=$TS_AUTHKEY bash tailscale-up.sh"

# Run on node-2
ssh root@$NODE2_PUBLIC_IP "git clone https://github.com/okbrk/ok-monitoring.git && cd ok-monitoring/scripts && TS_AUTHKEY=$TS_AUTHKEY bash tailscale-up.sh"
```

### b) Approve Subnet Routes and Record IP

1.  In the Tailscale Admin Console, approve the subnet routes advertised by your nodes.
2.  Get the Tailscale IP for `ok-node-0` and save it to your environment.

```bash
# Get the Tailscale IP for ok-node-0
NODE0_TS_IP=$(ssh root@$NODE0_PUBLIC_IP "tailscale ip -4")

# Save this IP to your secrets.env file for later steps
sed -i '' "s/GRAFANA_NODE_TS_IP=.*/GRAFANA_NODE_TS_IP=${NODE0_TS_IP}/" k8s/observability/secrets.env
source k8s/observability/secrets.env
echo "GRAFANA_NODE_TS_IP is now set to: $GRAFANA_NODE_TS_IP"
```

---

## 5) Bootstrap Kubernetes (k3s)

Now, with the Tailscale IP handy, we can install k3s correctly.

### a) Install k3s on the First Node (Server)

SSH into `ok-node-0` and run the bootstrap script, providing both its private IP and its new Tailscale IP. The Tailscale IP will be added to the server's TLS certificate.

```bash
# From your local machine
NODE0_PUBLIC_IP=$(cd infra/terraform && terraform output -json node_public_ips | jq -r '.[0]')
NODE0_PRIVATE_IP=$(cd infra/terraform && terraform output -json node_private_ips | jq -r '.[0]')

# SSH to node-0 and run the script with private IP and Tailscale IP
ssh root@$NODE0_PUBLIC_IP <<EOF
cd ok-monitoring/scripts
bash bootstrap-k3s.sh server ${NODE0_PRIVATE_IP} ${GRAFANA_NODE_TS_IP}
EOF
```

### b) Get Cluster Join Token

```bash
# From your local machine
K3S_TOKEN=$(ssh root@$NODE0_PUBLIC_IP "cat /var/lib/rancher/k3s/server/node-token")
export K3S_URL="https://$(echo $NODE0_PRIVATE_IP):6443"
```

### c) Install k3s on Worker Nodes

```bash
# Get public and private IPs for node-1 and node-2
NODE1_PUBLIC_IP=$(cd infra/terraform && terraform output -json node_public_ips | jq -r '.[1]')
NODE1_PRIVATE_IP=$(cd infra/terraform && terraform output -json node_private_ips | jq -r '.[1]')
NODE2_PUBLIC_IP=$(cd infra/terraform && terraform output -json node_public_ips | jq -r '.[2]')
NODE2_PRIVATE_IP=$(cd infra/terraform && terraform output -json node_private_ips | jq -r '.[2]')

# Install on node-1
ssh root@$NODE1_PUBLIC_IP "export K3S_URL='$K3S_URL'; export K3S_TOKEN='$K3S_TOKEN'; \
    cd ok-monitoring/scripts && bash bootstrap-k3s.sh agent ${NODE1_PRIVATE_IP}"

# Install on node-2
ssh root@$NODE2_PUBLIC_IP "export K3S_URL='$K3S_URL'; export K3S_TOKEN='$K3S_TOKEN'; \
    cd ok-monitoring/scripts && bash bootstrap-k3s.sh agent ${NODE2_PRIVATE_IP}"
```

### d) Retrieve and Merge Kubeconfig

This time, the `k3s.yaml` file generated on the server will contain the private IP. We will replace it with the Tailscale IP to ensure `kubectl` works from our local machine.

```bash
# Retrieve the kubeconfig and replace the server's private IP with its Tailscale IP
mkdir -p ~/.kube
ssh root@$NODE0_PUBLIC_IP "cat /etc/rancher/k3s/k3s.yaml" | sed "s/127.0.0.1/$GRAFANA_NODE_TS_IP/" | sed "s/$NODE0_PRIVATE_IP/$GRAFANA_NODE_TS_IP/" > ~/.kube/config-hetzner

# Set your KUBECONFIG environment variable
export KUBECONFIG=~/.kube/config-hetzner
echo "export KUBECONFIG=~/.kube/config-hetzner" >> ~/.zshrc
source ~/.zshrc
```

### e) Verify Cluster Health

```bash
kubectl get nodes -o wide
```
This command should now succeed, showing 3 `Ready` nodes.

---

## 6) Deploy Base Services

With a healthy cluster and working VPN, it's time to deploy the foundational services: `metrics-server` and `cert-manager`. These are defined in `k8s/base/helmfile.yaml`. `cert-manager` is crucial for handling TLS certificates, and `metrics-server` is needed for pod autoscaling and resource monitoring.

### a) Review the Helmfile

The `k8s/base/helmfile.yaml` is configured to:
- Install `metrics-server` in the `kube-system` namespace. The `--kubelet-insecure-tls` argument is often necessary for k3s setups.
- Install `cert-manager` and its CRDs in a dedicated `cert-manager` namespace.

### b) Deploy the Services

Use `helmfile` to apply the configuration.

```bash
helmfile -f k8s/base/helmfile.yaml apply
```

### c) Verify Deployment

This is another critical verification point. The problems you saw before with `cert-manager` pods failing to start can often be caught here.

Wait a few minutes for the pods to be pulled and started, then run:
```bash
kubectl get pods -A
```

You should see:
- The `metrics-server` pod running in the `kube-system` namespace.
- Three `cert-manager` pods (`cert-manager`, `cert-manager-cainjector`, `cert-manager-webhook`) running in the `cert-manager` namespace.

**All of these pods must be `1/1 Running` before you proceed.**

- If the `cert-manager-webhook` pod is stuck or failing, it can prevent many other Kubernetes resources from being created. Check its logs for errors:
  ```bash
  kubectl logs -n cert-manager -l app.kubernetes.io/name=webhook
  ```
- A common issue is the webhook pod starting before the CRDs are fully registered. If you see errors related to this, you might need to wait a bit longer, or sometimes a simple uninstall and reinstall of the Helm chart can fix it. `helmfile destroy` and `helmfile apply` can be used.

---

## 7) Configure Internal DNS (CoreDNS)

For services like `grafana.ok` to resolve correctly within your private network, you need an internal DNS server. We will deploy CoreDNS as a `DaemonSet` on all nodes, making it authoritative for the `.ok` domain.

### a) Review CoreDNS Configuration

The `k8s/net-dns/coredns.yaml` file is configured to:
- Deploy CoreDNS as a `DaemonSet`, ensuring it runs on every node.
- Use `hostNetwork: true` and `hostPort: 53` to expose CoreDNS directly on each node's IP address on the standard DNS port. This simplifies the Tailscale setup.
- Define a zone file for `ok.` with a placeholder `__GRAFANA_NODE_TS_IP__` for the `grafana.ok` A record.

### b) Deploy CoreDNS

First, replace the placeholder in the manifest with the actual Tailscale IP you saved earlier. Then, apply the manifest.

```bash
# Replace placeholder with the real IP
sed -i '' "s/__GRAFANA_NODE_TS_IP__/${GRAFANA_NODE_TS_IP}/" k8s/net-dns/coredns.yaml

# Apply the manifest
kubectl apply -f k8s/net-dns/coredns.yaml
```

### c) Configure Tailscale Split DNS

Now, tell your Tailscale network (tailnet) to use your new CoreDNS server for any queries ending in `.ok`.

1.  Go to the [DNS page](https://login.tailscale.com/admin/dns) in the Tailscale admin console.
2.  In the "Nameservers" section, click "Add nameserver" and select "Split DNS".
3.  For the domain, enter `ok` (without the dot).
4.  For the nameserver, enter the Tailscale IP of **one** of your nodes (e.g., `$GRAFANA_NODE_TS_IP`). Since CoreDNS is running on all nodes, any of them will work.
5.  Save the changes.

It may take a minute for the new DNS settings to propagate to all devices on your tailnet.

### d) Verify DNS Resolution

This step is crucial to confirm that your private DNS is working correctly.

1.  Ensure your local machine is connected to Tailscale.
2.  Use `dig` or a similar tool to query `grafana.ok`. The query should be answered by your node's Tailscale IP and return the same IP.

    ```bash
    dig grafana.ok
    ```
    The `ANSWER SECTION` should show `grafana.ok. 60 IN A <your-node-ts-ip>`.

3.  Test that a non-`.ok` domain still resolves through the public internet.

    ```bash
    dig google.com
    ```
    This should resolve to Google's public IP addresses.

**Do not proceed until `grafana.ok` resolves to the correct Tailscale IP.**

---

## 8) Configure Internal PKI (step-ca)

To issue valid TLS certificates for internal services like `grafana.ok`, we will set up our own Public Key Infrastructure (PKI) using `step-ca`. `cert-manager` will be configured to communicate with `step-ca` via the ACME protocol to automate certificate issuance.

### a) Initialize step-ca and Create Secrets

`step-ca` requires a root CA certificate and key, as well as a provisioner key. For a production setup, the root key should be generated offline and kept secure. For this guide, we'll generate them locally and store them as Kubernetes secrets.

```bash
# Create a working directory
mkdir -p ./.pki
cd ./.pki

# 1. Generate Root CA and Intermediate keys and certs
STEPPASS=$(openssl rand -base64 20)
step ca init --name="ok-ca" --provisioner="admin" --dns="ca.ok" \
--address=":8443" --password-file <(echo -n "$STEPPASS") --provisioner-password-file <(echo -n "$STEPPASS")

# 2. Create the Kubernetes secrets for step-ca
kubectl create namespace step-ca --dry-run=client -o yaml | kubectl apply -f -

kubectl -n step-ca create secret generic step-ca-password --from-literal "password=${STEPPASS}"

kubectl -n step-ca create secret generic step-ca-certs \
  --from-file=./certs/root_ca.crt \
  --from-file=./certs/intermediate_ca.crt

kubectl -n step-ca create secret generic step-ca-secrets \
  --from-file=./secrets/intermediate_ca_key \
  --from-file=./secrets/root_ca_key

# 3. Create the ACME provisioner
step ca provisioner add acme --type ACME

# 4. Create step-ca configuration
cat > ca.json <<EOL
{
    "root": "/home/step/certs/root_ca.crt",
    "key": "/home/step/secrets/root_ca_key",
    "address": ":9000",
    "dns": ["step-ca.step-ca.svc.cluster.local"],
    "db": {"type": "badgerv2", "dataSource": "/home/step/db"},
    "authority": {
        "provisioners": [
            {
                "type": "ACME",
                "name": "acme"
            }
        ]
    }
}
EOL

kubectl -n step-ca create secret generic step-ca-config --from-file=ca.json

# Clean up local files
cd ..
rm -rf ./.pki
```

### b) Deploy step-ca

Apply the Kubernetes manifest to deploy `step-ca`. The `CrashLoopBackOff` you saw previously was likely due to missing or misconfigured secrets. The updated manifest uses a `PersistentVolumeClaim` for the database to ensure it survives pod restarts.

```bash
kubectl apply -f k8s/pki/step-ca.yaml
```

### c) Create the ClusterIssuer

Now, create the `ClusterIssuer`. This `cert-manager` resource tells `cert-manager` how to connect to `step-ca` to request certificates.

```bash
kubectl apply -f k8s/pki/cluster-issuer.yaml
```

### d) Verify PKI Health

Check that the `step-ca` pod is running and that the `ClusterIssuer` is ready.

```bash
kubectl get pods -n step-ca
```
The `step-ca` pod should be `1/1 Running`. If it's in a crash loop, check the logs for errors related to passwords or file paths: `kubectl logs -n step-ca -l app=step-ca`.

```bash
kubectl get clusterissuer step-ca-issuer
```
The issuer should have a `STATUS` of `Ready`. If not, describe it to see the errors: `kubectl describe clusterissuer step-ca-issuer`.

---

## 9) Deploy Ingress Controller

The NGINX Ingress Controller will route traffic from the outside world (in our case, the "outside world" is our private Tailscale network) to services inside the cluster. We will deploy it with a `NodePort` service, exposing it on high-numbered ports on each node, which is a secure alternative to a public `LoadBalancer`.

### a) Review the Ingress Configuration

- `k8s/ingress/nginx-helmfile.yaml`: Defines the Helm release for the NGINX ingress controller.
- `k8s/ingress/nginx-values.yaml`: Configures the ingress controller to use a `NodePort` service, specifically mapping HTTP to port `30080` and HTTPS to port `30443` on each node.

### b) Deploy the Ingress Controller

Use `helmfile` to deploy NGINX.

```bash
helmfile -f k8s/ingress/nginx-helmfile.yaml apply
```

### c) Verify the Deployment

Check that the ingress controller pods are running and that the `NodePort` service has been created correctly.

```bash
kubectl get pods -n ingress-nginx
```
You should see one or more `ingress-nginx-controller` pods in the `Running` state.

```bash
kubectl get svc -n ingress-nginx
```
Look for the `ingress-nginx-controller` service. It should be of type `NodePort`, and you should see the port mappings (e.g., `80:30080/TCP` and `443:30443/TCP`).

Now, test connectivity to the NodePort from your local machine (while on Tailscale).

```bash
# This should return a "404 Not Found" from NGINX, which is a success
curl -k https://$GRAFANA_NODE_TS_IP:30443
```
Getting a 404 response confirms that the ingress controller is running and accessible over the VPN. It's a 404 because we haven't created any `Ingress` resources for it to route traffic to yet.

---

## 10) Create Object Storage (Wasabi)

The observability stack (Loki, Mimir, Tempo) will use S3-compatible object storage for long-term data retention. We'll use Wasabi for this. The `scripts/wasabi-buckets.sh` script automates the creation of the necessary buckets.

### a) Configure AWS CLI for Wasabi

The `aws` CLI needs to be configured with credentials for your Wasabi account.

```bash
aws configure
AWS Access Key ID [None]: <enter your Wasabi root or IAM user access key>
AWS Secret Access Key [None]: <enter your Wasabi secret key>
Default region name [None]: ${WASABI_REGION}
Default output format [None]: json
```

### b) Run the Bucket Creation Script

This script will create buckets for Loki, Tempo, Mimir, and Grafana backups, and apply some basic lifecycle policies to expire old data.

```bash
# Ensure environment variables are sourced
source k8s/observability/secrets.env

# Run the script
bash scripts/wasabi-buckets.sh
```

### c) Verify Bucket Creation

Use the `aws` CLI to list your buckets and confirm they were created.

```bash
aws --endpoint-url "$WASABI_ENDPOINT" s3 ls
```
You should see `loki-logs`, `tempo-traces`, `mimir-metrics`, and `grafana-backups` in the output.

---

## 11) Deploy Observability Stack

Now it's time to deploy the main event: the Grafana observability stack. This includes Grafana itself, plus Loki for logs, Mimir for metrics, and Tempo for traces.

### a) Create the Secrets

The Helm charts for the observability stack are configured to use a single Kubernetes secret that is populated from the `secrets.env` file.

```bash
# Create the observability namespace first
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# Create the secret from your environment file
kubectl -n observability create secret generic obs-secrets --from-env-file k8s/observability/secrets.env
```

### b) Deploy the Stack with Helmfile

This command will deploy Grafana, Loki, Mimir, Tempo, and Alertmanager. It will take a few minutes for all the images to be pulled and pods to start.

```bash
helmfile -f k8s/observability/helmfile.yaml apply
```

### c) Issue the TLS Certificate for Grafana

Once Grafana is deployed, we need to create a `Certificate` resource to tell `cert-manager` to issue a TLS certificate for `grafana.ok` from our `step-ca` `ClusterIssuer`.

```bash
kubectl apply -f k8s/observability/grafana-cert.yaml
```

### d) Verify the Full Stack

This is the final and most complex verification step. Many pods will be created.

```bash
kubectl get pods -n observability -w
```
Wait and watch until all pods are in the `Running` state. This may take 5-10 minutes. You are looking for pods related to `grafana`, `loki`, `mimir`, `tempo`, and `alertmanager`. If any pods get stuck in `Pending` or `CrashLoopBackOff`, investigate them:
- `kubectl -n observability describe pod <pod-name>` to check for scheduling or volume mounting issues.
- `kubectl -n observability logs <pod-name>` to check for application-level errors. S3 credential errors are a common issue to look for here.

Finally, verify that the TLS certificate was issued successfully.
```bash
kubectl -n observability get certificate grafana-ok-cert
```
The `READY` column should say `True`. If not, describe the certificate and also check the `cert-manager` pod logs for errors.

---

## 12) Accessing Grafana

Once all the components are running and the TLS certificate is ready, you can access your private Grafana instance.

1.  **Ensure you are connected to your Tailscale VPN.**
2.  Open a web browser and navigate to: **`https://grafana.ok`**
3.  You should see the Grafana login page. Your browser should trust the TLS certificate because it was issued by the root CA you created (you may need to import `root_ca.crt` into your browser or system keychain if you get a warning, though `step-ca` ACME should be trusted within the cluster).
4.  Log in using your configured OIDC provider or the local Grafana admin user (`$GRAFANA_ADMIN_USER` / `$GRAFANA_ADMIN_PASSWORD`).
5.  Explore the pre-configured datasources for Loki, Mimir, and Tempo.

Congratulations! You now have a fully private, scalable observability stack.
