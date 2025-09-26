#!/bin/bash
set -o xtrace

# EKS bootstrap script will be automatically appended by the EKS module
# This script runs before the standard EKS bootstrap

# Optimize containerd for large image downloads
cat >> /etc/containerd/config.toml << 'EOF'

# Optimizations for large image pulls
[plugins."io.containerd.grpc.v1.cri"]
  max_concurrent_downloads = 6
  enable_unprivileged_ports = true
  
[plugins."io.containerd.grpc.v1.cri".registry]
  config_path = "/etc/containerd/certs.d"
  
[plugins."io.containerd.grpc.v1.cri".registry.mirrors]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
    endpoint = ["https://registry-1.docker.io"]
    
# Increase timeouts for large images (14GB+)
[timeouts]
  "io.containerd.timeout.shim.cleanup" = "15s"
  "io.containerd.timeout.shim.load" = "15s"
  "io.containerd.timeout.shim.shutdown" = "10s"
  "io.containerd.timeout.task.state" = "5s"
  "io.containerd.timeout.bolt.open" = "10s"

EOF

# Restart containerd to apply new configuration
systemctl restart containerd

# Configure Docker daemon for better performance (if docker is installed)
if command -v docker &> /dev/null; then
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "max-concurrent-downloads": 6,
  "max-concurrent-uploads": 3,
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
    systemctl restart docker || true
fi

# Configure kubelet for better image pulling
mkdir -p /etc/kubernetes/kubelet
cat > /etc/kubernetes/kubelet/kubelet-config.json << 'EOF'
{
  "kind": "KubeletConfiguration",
  "apiVersion": "kubelet.config.k8s.io/v1beta1",
  "serializeImagePulls": false,
  "maxParallelImagePulls": 10,
  "imageMinimumGCAge": "5m",
  "imageGCHighThresholdPercent": 85,
  "imageGCLowThresholdPercent": 80,
  "registryPullQPS": 10,
  "registryBurst": 20
}
EOF

# Optimize system for large file operations
echo 'vm.dirty_ratio = 15' >> /etc/sysctl.conf
echo 'vm.dirty_background_ratio = 5' >> /etc/sysctl.conf
echo 'vm.dirty_expire_centisecs = 12000' >> /etc/sysctl.conf
echo 'vm.dirty_writeback_centisecs = 1500' >> /etc/sysctl.conf
echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_rmem = 4096 87380 134217728' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem = 4096 65536 134217728' >> /etc/sysctl.conf
sysctl -p

# Pre-warm common base images to reduce future pull times
echo "Pre-warming common container images..."
containerd ctr images pull docker.io/library/alpine:latest &
containerd ctr images pull docker.io/library/ubuntu:22.04 &
wait

echo "Container runtime optimizations complete"
