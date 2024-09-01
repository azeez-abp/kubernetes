# This is a set of script that automate the deployment kubernetes using kubeadm
- Start  install script and follow the prompt
- once a master has been initialized, other once will join as worker







Install kubectl
curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl