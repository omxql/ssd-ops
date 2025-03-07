#!/bin/bash

# Ensure the script stops if any command fails (optional but recommended for debugging)
set -e

# Check if the correct number of arguments are passed (host and organisationname)
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <host> <organisationname>"
    exit 1
fi

# Assign command-line arguments to variables
HOST=$1
ORG_NAME=$2

installHelm() {
  if command -v helm > /dev/null; then return; fi
  echo 'Installing helm CLI tool...'
  curl -fsSL -o get-helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
  chmod +x get-helm.sh
  ./get-helm.sh
}

installYq() {
  if command -v yq > /dev/null; then return; fi
  echo 'Installing yq CLI tool...'
  wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O $PWD/yq
  chmod +x $PWD/yq
  cp -v $PWD/yq /usr/local/bin/yq
}

VALUES_FILE="$PWD/ssd-minimal-values.yaml"
[ ! -s $VALUES_FILE ] && curl -OL https://raw.githubusercontent.com/OpsMx/enterprise-ssd/2025-01/charts/ssd/ssd-minimal-values.yaml

installHelm
installYq
[ ! -s $VALUES_FILE ] && exit 1

exit 0

# Install K3s
echo "Installing K3s..."
curl -sfL https://get.k3s.io | sh -
sleep 30s  

# Wait for K3s to be fully ready
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "Waiting for K3s node to become ready..."

# Wait for K3s node to be in "Ready" state
until kubectl get nodes | grep -q "Ready"; do
  echo "Waiting for node to be ready..."
  sleep 5
done

# Print a confirmation once the node is in Ready state
echo "K3s node is in Ready state."

# Installing Cert-Manager and its dependencies
echo "Installing Cert-Manager..."
helm repo add jetstack https://charts.jetstack.io --force-update
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.16.1 --set crds.enabled=true
echo "Cert-Manager installation complete."

# Installing Ingress-Nginx
echo "Installing Ingress-Nginx..."
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
echo "Ingress-Nginx installation complete."
sleep 60s

# Add your custom Helm repository
echo "Adding custom Helm repository for SSD..."
helm repo update
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm repo add opsmxssd https://opsmx.github.io/enterprise-ssd
kubectl create ns ssd

# Define the path to the values.yaml file
VALUES_FILE="/root/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"

# Use yq to modify the values.yaml file dynamically based on the command-line arguments
echo "Modifying values.yaml with host ($HOST) and organisationname ($ORG_NAME) parameters..."
yq eval -i ".global.ssdUI.host = \"$HOST\" | .organisationname = \"$ORG_NAME\"" "$VALUES_FILE"

# Install SSD with the modified values.yaml
echo "Installing SSD with the modified values.yaml..."
helm install ssd opsmxssd/ssd -f "$VALUES_FILE" -n ssd --timeout=600s
echo "SSD installation complete."

echo "Script execution complete."
