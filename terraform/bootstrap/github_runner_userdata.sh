#!/bin/bash
set -e

# Enable logging
exec > >(tee /var/log/user-data.log) 2>&1
echo "Starting GitHub runner setup at $(date)"

# Update system
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install Docker
echo "Installing Docker..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Install GitHub runner
echo "Setting up GitHub runner..."
cd /home/ubuntu

# Download the runner
echo "Downloading GitHub Actions runner..."
RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^v//')
echo "Latest runner version: $${RUNNER_VERSION}"
curl -o actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz

# Extract the installer
echo "Extracting runner..."
tar xzf ./actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz
chown -R ubuntu:ubuntu /home/ubuntu

# Configure the runner as ubuntu user
echo "Configuring runner for repository: ${github_repository}"
echo "Runner name: ${runner_name}"
echo "Runner labels: ${runner_labels}"
sudo -u ubuntu bash -c 'cd /home/ubuntu && ./config.sh --url https://github.com/${github_repository} --token ${github_token} --name ${runner_name}-$(date +%s) --labels ${runner_labels} --unattended'

# Install the service
echo "Installing and starting runner service..."
./svc.sh install ubuntu
./svc.sh start

echo "GitHub runner setup complete at $(date)"
echo "Runner should now be visible in GitHub repository settings"
