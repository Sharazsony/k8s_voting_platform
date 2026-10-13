# Helm Deployment Guide for Assign2

This document explains the Helm-based deployment approach for the Kubernetes assignment. It is intended as a separate operational guide for the chart and a clean alternative to the main project README.

---

## 1. Goal

The goal is to deploy the full assignment stack as a single Helm release while keeping the implementation organized using subcharts and clear responsibilities.

The application includes:
- Vote app
- Result app
- Redis
- PostgreSQL
- Worker
- Adminer
- Traefik ingress
- TLS configuration
- Network policies
- Quotas
- HPA
- Priority classes
- PDBs

---

## 2. Chart structure

The recommended structure is:

```text
helm/
└── assign2/
    ├── Chart.yaml
    ├── values.yaml
    ├── README.md
    ├── templates/
    │   ├── namespace.yaml
    │   ├── NOTES.txt
    │   └── tls-secret.yaml
    ├── charts/
    │   ├── data/
    │   │   ├── Chart.yaml
    │   │   └── values.yaml
    │   ├── app/
    │   │   ├── Chart.yaml
    │   │   └── values.yaml
    │   ├── ingress/
    │   │   ├── Chart.yaml
    │   │   └── values.yaml
    │   └── security/
    │       ├── Chart.yaml
    │       └── values.yaml
    └── .helmignore
```

### Subchart responsibilities

- `data`: PostgreSQL + Redis
- `app`: vote, result, worker, adminer
- `ingress`: Traefik, ingress rules, TLS secret
- `security`: RBAC, network policies, pods priority, quotas, PDB, HPA

This keeps a single release while dividing the stack by responsibility.

---

## 3. Helm best practices used

- One umbrella chart for one release
- Subcharts for logical boundaries
- Root-level values for shared configuration
- Namespace driven by `{{ .Release.Namespace }}`
- Deterministic naming for resources
- Dependencies declared in `Chart.yaml`
- `helm dependency update` before installation
- Use `helm lint` and `helm template` before deployment

---

## 4. Recommended values approach

The root `values.yaml` should contain global values such as:

```yaml
global:
  namespace: assign2
  appName: assign2
  ingress:
    className: traefik
    hosts:
      - vote.local
      - result.local
      - adminer.local
  tls:
    enabled: true
    secretName: assign2-tls
```

Subcharts should be configured separately for their own modules, for example:

```yaml
data:
  postgresql:
    enabled: true
  redis:
    enabled: true

app:
  vote:
    replicaCount: 2
  result:
    replicaCount: 1
  worker:
    replicaCount: 1
  adminer:
    replicaCount: 1
```

---

## 5. Namespace handling

The chart should install into its own namespace:

```bash
kubectl create namespace assign2
```

Then install with:

```bash
helm upgrade --install assign2 ./helm/assign2 \
  --namespace assign2 \
  --create-namespace
```

This keeps the assignment isolated and easier to manage.

---

## 6. Dependency update

Before installation, update chart dependencies:

```bash
helm dependency update ./helm/assign2
```

---

## 7. Validation commands

Run chart validation before install:

```bash
helm lint ./helm/assign2
helm template assign2 ./helm/assign2 --namespace assign2
```

After install:

```bash
kubectl get all -n assign2
kubectl get ingress -n assign2
kubectl get ingressclass -A
kubectl get networkpolicy -n assign2
kubectl get hpa -n assign2
kubectl get quota -n assign2
```

Check application access:

```bash
curl -k -I --resolve vote.local:8443:127.0.0.1 https://vote.local:8443/
curl -k -I --resolve result.local:8443:127.0.0.1 https://result.local:8443/
curl -k -I --resolve adminer.local:8443:127.0.0.1 https://adminer.local:8443/adminer
```

---

## 8. Notes

This chart is designed to match the assignment requirements while keeping the deployment professional and maintainable.

The main idea is:
- one release
- one namespace
- multiple subcharts
- clean ownership of Kubernetes resources
- easier upgrades and rollback

---

## 9. Next step

After this chart folder is created and populated, the next phase is to install it into the dedicated namespace and validate the live cluster state.
