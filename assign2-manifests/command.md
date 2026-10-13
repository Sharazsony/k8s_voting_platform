kubectl   logs   vote-779dcd9fb-4qk95   -n assign2   -c patch-jquery
   │       │            │                    │              │
   │       │            │                    │              └── Container select
   │       │            │                    └── Namespace select
   │       │            └── Pod select
   │       └── Action: logs dikhao
   └── Kubernetes CLI tool

kubectl exec -it deploy/vote -- sh

kubectl get quota
kubectl get netpol -n assign2

to temporary check :

kubectl -n assign2 run t1 --rm -it --restart=Never --image=busybox:1.36 \
  --labels=app=vote -- nslookup redis


# 5) vote -> redis (ALLOW)
kubectl -n assign2 run vote-redis-check --rm -it --restart=Never --image=busybox:1.36 --labels=app=vote -- sh -c 'nc -vz redis 6379'

# 6) vote -> db (DENY)
kubectl -n assign2 run vote-db-check --rm -it --restart=Never --image=busybox:1.36 --labels=app=vote -- sh -c 'nc -vz db 5432'

# 7) worker -> redis and db (ALLOW)
kubectl -n assign2 run worker-redis-check --rm -it --restart=Never --image=busybox:1.36 --labels=app=worker -- sh -c 'nc -vz redis 6379'
kubectl -n assign2 run worker-db-check --rm -it --restart=Never --image=busybox:1.36 --labels=app=worker -- sh -c 'nc -vz db 5432'

# 8) result -> db (ALLOW)
kubectl -n assign2 run result-db-check --rm -it --restart=Never --image=busybox:1.36 --labels=app=result -- sh -c 'nc -vz db 5432'

# 9) adminer -> db (ALLOW)
kubectl -n assign2 run adminer-db-check --rm -it --restart=Never --image=busybox:1.36 --labels=app=adminer -- sh -c 'nc -vz db 5432'

# 10) CoreDNS egress
kubectl -n assign2 run dns-egress-check --rm -it --restart=Never --image=busybox:1.36 --labels=app=vote -- sh -c 'nslookup kubernetes.default.svc.cluster.local'

# 11) Network policies
kubectl get networkpolicy -n assign2 -o wide
kubectl get networkpolicy -n assign2 -o yaml

# 12) Ingress hosts
kubectl get ingress -n assign2 -o jsonpath='{.items[*].spec.rules[*].host}{"\n"}'

# 13) TLS secret
kubectl get secret -n assign2 assign2-tls
kubectl describe secret -n assign2 assign2-tls

# 14) Traefik port mapping
kubectl get svc -n traefik traefik -o wide
kubectl get svc -n traefik traefik -o yaml

# 15) HTTPS from host
curl -vk https://vote.local --resolve vote.local:443:127.0.0.1
curl -vk https://result.local --resolve result.local:443:127.0.0.1
curl -vk https://adminer.local --resolve adminer.local:443:127.0.0.1


kubectl -n assign2 get pods -l app=postgres-backup
kubectl -n assign2 exec <pod-name> -- ls -l /backup


kubectl -n assign2 get pvc
kubectl -n assign2 run backup-viewer --rm -it --image=busybox \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "backup-viewer",
      "image": "busybox",
      "command": ["sh"],
      "stdin": true,
      "tty": true,
      "volumeMounts": [{
        "name": "backup",
        "mountPath": "/backup"
      }]
    }],
    "volumes": [{
      "name": "backup",
      "persistentVolumeClaim": {
        "claimName": "postgres-backup-pvc"
      }
    }]
  }
}'

ls -l /backup
cat /backup/votes-20261006-111301.sql | head

kubectl exec postgres-restore -- psql -U postgres -d postgres -f /backup/votes-20261006-061501.sql
kubectl exec -it postgres-restore -- psql -U postgres -d postgres -c '\dt'
kubectl exec -it postgres-restore -- psql -U postgres -d postgres -c 'SELECT count(*) FROM votes;'
kubectl exec -it postgres-restore -- psql -U postgres -d postgres -c 'SELECT * FROM votes LIMIT 10;'