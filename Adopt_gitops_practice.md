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


cd ~/kubernetes_assigment_2
grep -rn -i -E "password|secret|tls|key" helm/assign2/charts/*/templates/ helm/assign2/values.yaml


📖 Tumhari Command Decode
bash
kubectl create secret generic assign2-db-secret -n assign2-helm \
  --from-literal=postgres-password='YOUR_PASSWORD' \
  --dry-run=client -o yaml \
| kubeseal --controller-name sealed-secrets-controller \
           --controller-namespace kube-system \
           --format yaml \
> helm/assign2/charts/security/templates/sealed-db-secret.yaml
Part	Matlab
kubectl create secret generic	Plain secret banao
assign2-db-secret	Secret ka naam
-n assign2-helm	Namespace (important — kubeseal isse use karega)
--from-literal=postgres-password='...'	Key-value pair
--dry-run=client	Cluster pe apply mat karo, sirf YAML generate karo
-o yaml	YAML output
| kubeseal	Pipe karke seal karo
--controller-name	Controller ka naam
--controller-namespace	Controller kahan hai
--format yaml	Output YAML me
> .../sealed-db-secret.yaml	File me save karo


# GPG se encrypt karke cloud me daal sakte ho
gpg --symmetric --cipher-algo AES256 ~/sealed-secrets-key-backup.yaml
# Ye .gpg file banti hai, use safe jagah rakho


cd ~/kubernetes_assigment_2

# Ensure directory exists
mkdir -p helm/assign2/charts/security/templates

# Seal karo
kubectl create secret generic assign2-db-secret -n assign2-helm \
  --from-literal=postgres-password='postgres' \
  --dry-run=client -o yaml \
| kubeseal --controller-name sealed-secrets-controller \
           --controller-namespace kube-system \
           --format yaml \
> helm/assign2/charts/security/templates/sealed-db-secret.yaml



🔑 Public key kahan use ho rahi hai?
Tumhare command me public key kubeseal ke andar automatically use ho rahi hai. Tumne explicitly di nahi — kubeseal khud fetch karta hai.

bash
kubeseal --controller-name sealed-secrets-controller \
         --controller-namespace kube-system


Ye annotation Argo CD ko batata hai ki is resource ko baaki resources se PEHLE deploy karo.

-1 matlab pehle, 0 matlab normal/baad me, 1 matlab aur baad me.


vim helm/assign2/charts/security/templates/sealed-db-secret.yaml
metadata: section me add karo:

yaml
metadata:
  name: assign2-db-secret
  namespace: assign2-helm
  annotations:
    argocd.argoproj.io/sync-wave: "-1"     # ← Ye add karo


# /tmp me generate karo (secure, temporary)
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=vote.local" \
  -addext "subjectAltName=DNS:vote.local,DNS:result.local,DNS:adminer.local"

# /tmp me generate karo (secure, temporary)
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=vote.local" \
  -addext "subjectAltName=DNS:vote.local,DNS:result.local,DNS:adminer.local"



  Argocd:
  username: admin
  password: LXWyqUZprzW7PxH0