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