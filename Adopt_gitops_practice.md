Install the Sealed Secrets controller and the kubeseal CLI
Seal the secrets and change the chart to use them
Check the chart from a fresh clone, then push to Git
Install Argo CD
Hand the release over from the Helm CLI to Argo CD


# 1. Pehle purana (galat) repo remove karo (agar add hua ho to)
helm repo remove sealed-secrets

# 2. Naya sahi repo add karo
helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets

# 3. Repo update karo
helm repo update

# 4. Ab install karo (tumhara command wahi rahega)
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system \
  --set fullnameOverride=sealed-secrets-controller

# 5. Verify karo
kubectl get pods -n kube-system | grep sealed


# Purani galat file delete karo (agar bani ho)
rm -f kubeseal-*.tar.gz kubeseal

# Sahi repo se version fetch karo
KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami/sealed-secrets/releases/latest | grep -Po '"tag_name": "v\K[0-9.]+')
KUBESEAL_VERSION=${KUBESEAL_VERSION:-0.40.0}  # Fallback

echo "Installing kubeseal v${KUBESEAL_VERSION}"

# Sahi URL se download karo
curl -OL "https://github.com/bitnami/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"

# Verify karo ki file ab valid hai (size ~23MB hona chahiye)
ls -lh kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz

# Extract
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal

# Install
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Verify
kubeseal --version



kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > ~/sealed-secrets-key-backup.yaml