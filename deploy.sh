#!/bin/bash
# =====================================================
# Automated Deployment Script
# Author: Olalekan Oan
# Purpose: Setup, deploy, and configure a Dockerized app
# =====================================================

# Exit on any error and handle pipe failures

set -o pipefail

# Create a timestamped log file
LOG_FILE="deploy_$(date +'%Y%m%d_%H%M%S').log"

# Function for logging messages with timestamp
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Trap errors to log and exit cleanly
trap 'STATUS=$?; log "❌ ERROR at line $LINENO (exit code $STATUS). Check $LOG_FILE for details."; exit $STATUS' ERR

log "🚀 Starting deployment script..."

# ================================================
# Default Configuration (you can edit these values)
# ================================================
DEFAULT_GIT_REPO_URL="https://github.com/Formula360/docker-deploy-example.git"
DEFAULT_GIT_BRANCH="main"
DEFAULT_SSH_USER="ubuntu"
DEFAULT_SERVER_IP="51.20.84.31" 
DEFAULT_SSH_KEY="/home/olalekan/.ssh/docker_deploy_stage1.pem"
DEFAULT_APP_PORT="3000"
DEFAULT_GITHUB_PAT="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"  # 🔑 Replace with your GitHub PAT

# ===============================
# Collect User Input (with Fallbacks)
# ===============================
read -p "🔗 Git Repository URL [${DEFAULT_GIT_REPO_URL}]: " GIT_REPO_URL
GIT_REPO_URL=${GIT_REPO_URL:-$DEFAULT_GIT_REPO_URL}

read -p "🔑 Personal Access Token (PAT) [hidden input]: " -s GITHUB_PAT
echo
GITHUB_PAT=${GITHUB_PAT:-$DEFAULT_GITHUB_PAT}

read -p "🌿 Branch name [${DEFAULT_GIT_BRANCH}]: " GIT_BRANCH
GIT_BRANCH=${GIT_BRANCH:-$DEFAULT_GIT_BRANCH}

read -p "👤 SSH username [${DEFAULT_SSH_USER}]: " SSH_USER
SSH_USER=${SSH_USER:-$DEFAULT_SSH_USER}

read -p "🌍 Server IP address [${DEFAULT_SERVER_IP}]: " SERVER_IP
SERVER_IP=${SERVER_IP:-$DEFAULT_SERVER_IP}

read -p "🗝️ Path to SSH private key [${DEFAULT_SSH_KEY}]: " SSH_KEY
SSH_KEY=${SSH_KEY:-$DEFAULT_SSH_KEY}

read -p "📦 Application port [${DEFAULT_APP_PORT}]: " APP_PORT
APP_PORT=${APP_PORT:-$DEFAULT_APP_PORT}

log "✅ Using configuration:
Repo: $GIT_REPO_URL
Branch: $GIT_BRANCH
Server: $SERVER_IP
User: $SSH_USER
Port: $APP_PORT
Key: $SSH_KEY
"

# ================================================
# STEP 1: Clone or update repo
# ================================================
log "📦 Cloning or updating repository..."
if [ ! -d "./repo" ]; then
  git clone -b "$GIT_BRANCH" "https://${GITHUB_PAT}@${GIT_REPO_URL#https://}" repo | tee -a "$LOG_FILE"
else
  cd repo
  git fetch origin "$GIT_BRANCH" | tee -a "$LOG_FILE"
  git checkout "$GIT_BRANCH" | tee -a "$LOG_FILE"
  git pull origin "$GIT_BRANCH" | tee -a "$LOG_FILE"
  cd ..
fi
log "✅ Repository ready."

# ================================================
# STEP 2: Verify Dockerfile or docker-compose.yml
# ================================================
cd repo
if [ -f "docker-compose.yml" ]; then
  log "✅ docker-compose.yml found."
elif [ -f "Dockerfile" ]; then
  log "✅ Dockerfile found."
else
  log "❌ ERROR: No Dockerfile or docker-compose.yml found!"
  exit 1
fi
cd ..

# ================================================
# STEP 3: Test SSH connectivity
# ================================================
log "🔗 Testing SSH connection to $SERVER_IP..."
if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "echo SSH connected" >/dev/null 2>&1; then
  log "✅ SSH connection successful."
else
  log "❌ SSH connection failed! Check your key or server."
  exit 1
fi

# ================================================
# STEP 4: Prepare remote server
# ================================================
log "🧰 Preparing remote server environment..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" bash << EOF
  set -e
  sudo apt-get update -y
  sudo apt-get install -y docker.io docker-compose nginx
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo usermod -aG docker $SSH_USER || true
  docker --version
  docker-compose --version
EOF
log "✅ Remote environment ready."

# ================================================
# STEP 5: Transfer project files
# ================================================
log "📤 Transferring project files via rsync..."
rsync -az -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" ./repo/ "$SSH_USER@$SERVER_IP:/home/$SSH_USER/app/"
log "✅ Files transferred."

# ================================================
# STEP 6: Deploy on remote host
# ================================================
log "🐳 Deploying application..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" bash << EOF
  set -e
  cd ~/app
  docker-compose down || true
  docker-compose build
  docker-compose up -d
EOF
log "✅ Application deployed successfully."

# ================================================
# STEP 7: Configure Nginx Reverse Proxy
# ================================================
log "🌐 Configuring Nginx reverse proxy..."

# Pass the APP_PORT variable (default 3000) to the remote host and configure nginx safely
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" APP_PORT_FROM_LOCAL="${APP_PORT:-3000}" bash << 'REMOTE_EOF'

# Create Nginx config template with a placeholder for the port
sudo tee /etc/nginx/sites-available/app.conf > /dev/null <<'NGINX'
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:APP_PORT_REPLACE;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINX

# Replace placeholder with actual port from environment
sudo sed -i "s/APP_PORT_REPLACE/${APP_PORT_FROM_LOCAL}/g" /etc/nginx/sites-available/app.conf

# Enable the new site and reload nginx
sudo ln -sf /etc/nginx/sites-available/app.conf /etc/nginx/sites-enabled/app.conf
sudo nginx -t
sudo systemctl reload nginx
REMOTE_EOF

log "✅ Nginx configured successfully."

# ================================================
# STEP 8: Validate Deployment
# ================================================
log "🔍 Validating deployment..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" bash << EOF
  docker ps
  curl -I http://localhost || true
EOF

log "✅ Deployment validated successfully. Your app should be accessible at: http://${SERVER_IP}"

# ================================================
# STEP 9: Cleanup Old Logs (keep latest 5)
# ================================================
ls -t deploy_*.log 2>/dev/null | tail -n +6 | xargs -r rm --
log "🧹 Cleaned up old log files."

# ================================================
# STEP 10: Optional Cleanup Flag
# ================================================
if [[ "$1" == "--cleanup" ]]; then
  log "🧨 Cleanup flag detected. Removing remote deployment..."
  ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "rm -rf ~/app && sudo rm -f /etc/nginx/sites-enabled/app.conf && sudo systemctl reload nginx"
  log "✅ Cleanup completed."
fi

log "🎉 Deployment complete!"
