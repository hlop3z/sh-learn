#!/bin/bash
# =====================================================
# Debian Server Setup Script (Non-Interactive & Robust)
# =====================================================
# USAGE: sudo ./setup.sh --all
# =====================================================

set -euo pipefail
IFS=$'\n\t'

# ---------------------------
# Configurable Options
# ---------------------------
INSTALL_UFW=false
INSTALL_UTILS=false
INSTALL_DOCKER=false
INSTALL_NGINX=false
INSTALL_CADDY=false
LOG_FILE="/var/log/debian_setup.log"

# ---------------------------
# Logging Functions
# ---------------------------
log() {
    echo -e "\e[32m[INFO]\e[0m $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "\e[31m[ERROR]\e[0m $1" | tee -a "$LOG_FILE" >&2
}

die() {
    error "$1"
    exit 1
}

# ---------------------------
# Usage
# ---------------------------
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --ufw        Install and configure UFW firewall
  --utils      Install essential utilities
  --docker     Install Docker and Docker Compose
  --nginx      Install and start Nginx
  --caddy      Install and start Caddy web server
  --all        Install everything with Nginx as default web server
  -h, --help   Show this help message
EOF
    exit 1
}

# ---------------------------
# System Functions
# ---------------------------
update_system() {
    log "Updating and upgrading system packages..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt update -y
    sudo apt full-upgrade -y
    sudo apt autoremove -y
    log "System update complete."
}

install_ufw() {
    log "Installing UFW firewall..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt install -y ufw || die "Failed to install UFW"
    log "UFW installed successfully."
}

setup_ufw() {
    install_ufw
    log "Configuring UFW firewall..."
    sudo ufw allow 22/tcp || die "Failed to allow SSH"
    sudo ufw allow 80/tcp || die "Failed to allow HTTP"
    sudo ufw allow 443/tcp || die "Failed to allow HTTPS"
    sudo ufw --force enable || die "Failed to enable UFW"
    sudo ufw status verbose | tee -a "$LOG_FILE"
    log "UFW setup complete."
}

install_utils() {
    log "Installing essential utilities..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt install -y curl wget unzip zip build-essential ca-certificates software-properties-common || die "Failed to install utilities"
    log "Essential utilities installed."
}

install_docker() {
    log "Installing Docker..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt install -y ca-certificates curl gnupg lsb-release || die "Failed to install dependencies"
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || die "Failed to download Docker GPG key"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update -y
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || die "Failed to install Docker"
    sudo usermod -aG docker $USER || die "Failed to add user to Docker group"
    log "Docker installation complete. You may need to log out and back in for Docker group changes to take effect."
}

# ---------------------------
# Web Server Functions
# ---------------------------
check_web_server_conflicts() {
    if $INSTALL_NGINX && $INSTALL_CADDY; then
        die "You cannot install both Nginx and Caddy at the same time. Please choose only one."
    fi
}

install_nginx() {
    log "Installing and starting Nginx..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt install -y nginx || die "Failed to install Nginx"
    sudo systemctl enable nginx || die "Failed to enable Nginx"
    sudo systemctl start nginx || die "Failed to start Nginx"
    log "Nginx installation complete."
}

install_caddy() {
    log "Installing and starting Caddy..."
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https || die "Failed to install prerequisites"
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt update -y
    sudo apt install -y caddy || die "Failed to install Caddy"
    sudo systemctl enable caddy || die "Failed to enable Caddy"
    sudo systemctl start caddy || die "Failed to start Caddy"
    log "Caddy installation complete."
}

# ---------------------------
# System Verification
# ---------------------------
verify_system() {
    log "Verifying system health..."
    echo -e "\nDisk Usage:" | tee -a "$LOG_FILE"
    df -h | tee -a "$LOG_FILE"
    echo -e "\nMemory Usage:" | tee -a "$LOG_FILE"
    free -h | tee -a "$LOG_FILE"
    echo -e "\nFailed Systemd Units:" | tee -a "$LOG_FILE"
    systemctl list-units --failed | tee -a "$LOG_FILE"
}

# ---------------------------
# CLI Argument Parsing
# ---------------------------
if [ $# -eq 0 ]; then
    usage
fi

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --ufw) INSTALL_UFW=true ;;
        --utils) INSTALL_UTILS=true ;;
        --docker) INSTALL_DOCKER=true ;;
        --nginx) INSTALL_NGINX=true ;;
        --caddy) INSTALL_CADDY=true ;;
        --all)
            INSTALL_UFW=true
            INSTALL_UTILS=true
            INSTALL_DOCKER=true
            INSTALL_NGINX=false   
            INSTALL_CADDY=true  # Default web server for --all
            ;;
        -h|--help) usage ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

# ---------------------------
# Main Execution
# ---------------------------
main() {
    update_system

    $INSTALL_UFW && setup_ufw
    $INSTALL_UTILS && install_utils
    $INSTALL_DOCKER && install_docker

    # Ensure only one web server is selected
    check_web_server_conflicts

    $INSTALL_NGINX && install_nginx
    $INSTALL_CADDY && install_caddy

    verify_system

    log "Server setup complete! Logs saved at $LOG_FILE"
}

main
