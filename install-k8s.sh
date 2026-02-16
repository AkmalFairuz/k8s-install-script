#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

# Only Ubuntu >= 24.04 is supported
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "ubuntu" ]; then
        echo "Error: This script only supports Ubuntu."
        exit 1
    fi
    VERSION_NUM=$(echo "$VERSION_ID" | tr -d '.')
    if [ "$VERSION_NUM" -lt 2404 ]; then
        echo "Error: Your Ubuntu version ($VERSION_ID) is too old."
        echo "This script requires Ubuntu 24.04 (Noble Numbat) or newer."
        exit 1
    fi
    echo "Check OK: Running on Ubuntu $VERSION_ID ($VERSION_CODENAME)"
else
    echo "Error: /etc/os-release not found. Cannot verify OS version."
    exit 1
fi

INTERACTIVE=true
for arg in "$@"; do
  if [[ "$arg" == "--no-interactive" ]]; then
    INTERACTIVE=false
    echo "Running in non-interactive mode. Skipping prompts."
    break
  fi
done

if [ "$INTERACTIVE" = true ]; then
  echo "Before we begin, let's gather some information about your desired Kubernetes setup."
  if [ -z "$K8S_HOSTNAME" ]; then
    read -p "> Enter Hostname [$(hostname)]: " K8S_HOSTNAME
    K8S_HOSTNAME=${K8S_HOSTNAME:-$(hostname)}
  fi

  if [ -z "$K8S_INSTALL_MODE" ]; then
    echo "Select Installation Mode:"
    echo "1) control-plane"
    echo "2) worker"
    echo "3) control-plane-and-worker"
    echo "If you don't know which one to choose, 'control-plane-and-worker' is a good option for single-node clusters."
    read -p "> Selection (1-3): " MODE_CHOICE
    case $MODE_CHOICE in
      1) K8S_INSTALL_MODE="control-plane" ;;
      2) K8S_INSTALL_MODE="worker" ;;
      3) K8S_INSTALL_MODE="control-plane-and-worker" ;;
      *) echo "Invalid selection"; exit 1 ;;
    esac
  fi

  if [ "$K8S_INSTALL_MODE" = "worker" ]; then
    read -p "> Enter Master API Server IP/Endpoint (e.g., 192.168.1.10:6443): " K8S_MASTER
    read -p "> Enter Join Token: " K8S_JOIN_TOKEN
    read -p "> Enter Discovery Token CA Cert Hash: " K8S_DISCOVERY_TOKEN_CA_CERT_HASH
  else
    read -p "> Pod Network CIDR [10.244.0.0/16]: " K8S_POD_NETWORK_CIDR
    K8S_POD_NETWORK_CIDR=${K8S_POD_NETWORK_CIDR:-"10.244.0.0/16"}
    read -p "> Install Flannel CNI? (y/n): " INSTALL_FLANNEL
    [[ "$INSTALL_FLANNEL" =~ ^[Yy]$ ]] && K8S_WITH_FLANNEL=true
  fi
fi

for arg in "$@"
do
  case $arg in
    --hostname=*)
      K8S_HOSTNAME="${arg#*=}"
      ;;
    --mode=*)
      K8S_INSTALL_MODE="${arg#*=}"
      ;;
    --pod-network-cidr=*)
      K8S_POD_NETWORK_CIDR="${arg#*=}"
      ;;
    --join-token=*)
      K8S_JOIN_TOKEN="${arg#*=}"
      ;;
    --master=*)
      K8S_MASTER="${arg#*=}"
      ;;
    --discovery-token-ca-cert-hash=*)
      K8S_DISCOVERY_TOKEN_CA_CERT_HASH="${arg#*=}"
      ;;
    --version=*)
      K8S_VERSION="${arg#*=}"
      ;;
    --service-cidr=*)
      K8S_SERVICE_CIDR="${arg#*=}"
      ;;
    --with-flannel)
      K8S_WITH_FLANNEL=true
      ;;
    --with-flannel=*)
      K8S_WITH_FLANNEL="${arg#*=}"
      ;;
    *)
      ;;
  esac
done

if [ -z "$K8S_VERSION" ]; then
  K8S_VERSION="1.35"
fi
if [ -z "$K8S_HOSTNAME" ]; then
  echo "error: --hostname is required"
  exit 1
fi
if [ -z "$K8S_INSTALL_MODE" ]; then
  echo "error: --mode is required"
  exit 1
fi

if [ "$K8S_INSTALL_MODE" != "control-plane" ] && [ "$K8S_INSTALL_MODE" != "worker" ] && [ "$K8S_INSTALL_MODE" != "control-plane-and-worker" ]; then
  echo "error: --mode must be either 'control-plane', 'worker', or 'control-plane-and-worker'"
  exit 1
fi

if [ "$K8S_INSTALL_MODE" = "worker" ]; then
  if [ -z "$K8S_JOIN_TOKEN" ]; then
    echo "error: --join-token is required for worker mode"
    exit 1
  fi
  if [ -z "$K8S_MASTER" ]; then
    echo "error: --master is required for worker mode"
    exit 1
  fi
  if [ -z "$K8S_DISCOVERY_TOKEN_CA_CERT_HASH" ]; then
    echo "error: --discovery-token-ca-cert-hash is required for worker mode"
    exit 1
  fi
fi

if [ "$K8S_INSTALL_MODE" = "control-plane" ] || [ "$K8S_INSTALL_MODE" = "control-plane-and-worker" ]; then
  if [ -z "$K8S_POD_NETWORK_CIDR" ]; then
    echo "warning: --pod-network-cidr not specified, using default: 10.244.0.0/16"
    K8S_POD_NETWORK_CIDR="10.244.0.0/16"
  fi
  if [ -z "$K8S_SERVICE_CIDR" ]; then
    echo "warning: --service-cidr not specified, using default: 10.96.0.0/12"
    K8S_SERVICE_CIDR="10.96.0.0/12"
  fi
fi

hostnamectl set-hostname "$K8S_HOSTNAME"
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system
apt-get update -y
apt-get install --no-install-recommends -y ca-certificates curl gnupg conntrack
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get -y update
apt-get install --no-install-recommends -y containerd.io
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml >/dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v"$K8S_VERSION"/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
"deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

apt-get -y update
apt-get install --no-install-recommends -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

if [ "$K8S_INSTALL_MODE" = "control-plane" ] || [ "$K8S_INSTALL_MODE" = "control-plane-and-worker" ]; then
  kubeadm init --pod-network-cidr="$K8S_POD_NETWORK_CIDR" --service-cidr="$K8S_SERVICE_CIDR" --ignore-preflight-errors=NumCPU
  mkdir -p $HOME/.kube
  cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  chown $(id -u):$(id -g) $HOME/.kube/config
  if [ "$K8S_INSTALL_MODE" = "control-plane-and-worker" ]; then
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
  fi
  if [ "$K8S_WITH_FLANNEL" = true ]; then
    kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
  fi
  if [ -d "/home/ubuntu" ]; then
    echo "==> Setting up kubeconfig for 'ubuntu' user"
    mkdir -p /home/ubuntu/.kube
    cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
    chown -R ubuntu:ubuntu /home/ubuntu/.kube
  fi
fi

if [ "$K8S_INSTALL_MODE" = "worker" ]; then
  kubeadm join "$K8S_MASTER" --token "$K8S_JOIN_TOKEN" --discovery-token-ca-cert-hash "$K8S_DISCOVERY_TOKEN_CA_CERT_HASH"
fi

echo "==> Script completed successfully. Kubernetes '$K8S_VERSION' should now be installed in '$K8S_INSTALL_MODE' mode."
echo "NOTE: Recommended to reboot the system after installation to ensure all changes take effect properly! You can do this by running: 'reboot'"
exit 0