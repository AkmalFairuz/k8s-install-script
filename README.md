# k8s-install-script

A Bash script to install Kubernetes on Ubuntu 24.04 or later nodes.

## Usage:

- To install Kubernetes on a single node (control-plane and worker):
```bash
curl -sSL https://raw.githubusercontent.com/AkmalFairuz/k8s-install-script/master/install-k8s.sh | \
    bash -s -- \
    --hostname=k8s-node1 \
    --mode=control-plane-and-worker
```

- To install Kubernetes on a control-plane node (without worker):
```bash
curl -sSL https://raw.githubusercontent.com/AkmalFairuz/k8s-install-script/master/install-k8s.sh | \
    bash -s -- \
    --hostname=k8s-control-plane \
    --mode=control-plane
```

- To install Kubernetes on a worker node and join it to an existing cluster:
```bash
curl -sSL https://raw.githubusercontent.com/AkmalFairuz/k8s-install-script/master/install-k8s.sh | \
    bash -s -- \
    --hostname=k8s-worker1 \
    --mode=worker \
    --join-token=TOKEN \
    --master=20.0.0.1:6443 \
    --discovery-token-ca-cert-hash=HASH
```

## Arguments:
- `--hostname`: The hostname to set for this node (required)
- `--mode`: The installation mode, either 'control-plane', 'worker', or 'control-plane-and-worker' (required)
- `--pod-network-cidr`: The CIDR for the pod network (optional, default: 10.244.0.0/16)
- `--service-cidr`: The CIDR for the service network (optional, default: 10.96.0.0/12)
- `--join-token`: The token to use for joining the cluster (required for worker)
- `--master`: The address of the control plane to join (required for worker, example: 20.0.0.1:6443)
- `--discovery-token-ca-cert-hash`: The hash of the CA cert for discovery (required for worker)
- `--version`: The Kubernetes version to install (optional, example: 1.35)
- `--with-flannel`: Whether to install Flannel as the CNI plugin (optional, default: false)