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
PATH=$PATH:/usr/local/bin

echo "Current OS platform details..."
echo "-----------------------------"
cat /etc/os-release
echo "-----------------------------"
echo 

installGit() {
  if command -v git > /dev/null; then return; fi
  echo 'Installing git CLI tool...'
  if grep -q 'ID_LIKE=.*debian' /etc/os-release; then
    apt update && sudo apt install -y git
  elif grep -q 'ID_LIKE=.*rhel\|centos\|fedora' /etc/os-release; then
    dnf install -y git
  else
    echo "Unsupported OS"
    exit 1
  fi
}

#installHelm() {
#  if command -v helm > /dev/null; then return; fi
#  echo 'Installing helm CLI tool...'
#  curl -fsSL -o helm3.tar.gz https://get.helm.sh/helm-v3.17.1-linux-amd64.tar.gz
#  tar -zxvf helm3.tar.gz
#  cp -v  linux-amd64/helm /usr/local/bin/
#  $PATH
#  command -v helm
#}


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
  curl -fsSL -o yq  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
  chmod +x $PWD/yq
  cp -v $PWD/yq /usr/local/bin/yq
}

installGit
installHelm
installYq

VALUES_FILE="$PWD/ssd-minimal-values.yaml"
[ ! -s $VALUES_FILE ] && curl -OL https://raw.githubusercontent.com/OpsMx/enterprise-ssd/2025-01/charts/ssd/ssd-minimal-values.yaml
[ ! -s $VALUES_FILE ] && exit 1

#exit 0

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

mkdir -p $HOME/.kube
cp -v /etc/rancher/k3s/k3s.yaml $HOME/.kube/k3s.yaml
export KUBECONFIG=$HOME/.kube/k3s.yaml

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
helm repo add opsmxssd https://opsmx.github.io/enterprise-ssd
kubectl create ns ssd

# Use yq to modify the values.yaml file dynamically based on the command-line arguments
echo "Modifying values.yaml with host ($HOST) and organisationname ($ORG_NAME) parameters..."
yq eval -i ".global.ssdUI.host = \"$HOST\" | .organisationname = \"$ORG_NAME\"" "$VALUES_FILE"

# Install SSD with the modified values.yaml
echo "Installing SSD with the modified values.yaml..."
helm install ssd opsmxssd/ssd -f "$VALUES_FILE" -n ssd --timeout=600s

echo -e "\n\n"
echo "Installation is completed, but please verify all the pods are up and running before use."
echo "It takes about 7 to 15 mins for all the pods to be RUNNING depending on the Cluster performance"
echo "Wish you good luck with OpsMx SSD!"
