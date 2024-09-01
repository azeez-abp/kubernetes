#!/usr/bin/bash

set -euo pipefail

# Update the System
sudo apt-get update
sudo apt-get upgrade -y

# Kill any running unattended-upgrades process
PR=$(sudo pgrep unattended-upgrades)
if [[ -n "$PR" ]]; then
    sudo kill -9 "$PR"
    echo "Process $PR killed."
else
    echo "No unattended-upgrades process found."
fi

# Check for firewall
firew="$(sudo iptables --version | awk '{print $1" version " $2}')"

if [[ -n "$firew" ]]; then
    echo "$firew detected"
else
    echo "Firewall iptables not detected"
    exit 1
fi

# Configure firewall rules for worker nodes
worker-port() {
    # Allow incoming traffic on port 10255 (kubectl API)
    sudo iptables -A INPUT -p tcp --dport 10255 -j ACCEPT

    # Allow incoming traffic on port 30000-32767 (Service NodePort range)
    sudo iptables -A INPUT -p tcp --dport 30000:32767 -j ACCEPT
}

setup-cri-requirement() {
    # Load necessary kernel modules
    sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

    sudo modprobe overlay
    sudo modprobe br_netfilter

    # Apply sysctl parameters for Kubernetes
    sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

    sudo sysctl --system

    # Verify modules have been loaded
    lsmod | grep -e br_netfilter -e overlay
}

setup-cri-requirement
worker-port

# Install required packages
sudo apt-get install -y curl apt-transport-https gnupg2 software-properties-common

# Disable Swap
sudo swapoff -a
# Remove or comment out swap entry in /etc/fstab to make the change permanent.

# Set up Kubernetes APT repository and install components
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet=1.30.1-1.1 kubeadm=1.30.1-1.1 kubectl=1.30.1-1.1
sudo apt-mark hold kubelet kubeadm kubectl

# Install and configure Containerd
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install -y containerd.io

# Configure Containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -e 's/SystemdCgroup = false/SystemdCgroup = true/g' -i /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Install and configure crictl
export VER="v1.26.0"
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$VER/crictl-$VER-linux-amd64.tar.gz
tar zxvf crictl-$VER-linux-amd64.tar.gz
sudo mv crictl /usr/local/bin
sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock --set image-endpoint=unix:///run/containerd/containerd.sock

# Join the Kubernetes cluster
read -p 'Enter the kubeadm join command from the master node: ' JOIN_COMMAND
sudo $JOIN_COMMAND

# Start and enable kubelet
sudo systemctl start kubelet
sudo systemctl enable kubelet

# Verify the node has joined the cluster
kubectl get nodes
