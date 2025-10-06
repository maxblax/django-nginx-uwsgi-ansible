#!/bin/bash

# ============================================
# Django-Nginx-uWSGI Ansible - Interactive Setup
# ============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() { echo -e "${BLUE}ℹ ${NC}$1"; }
print_success() { echo -e "${GREEN}✓ ${NC}$1"; }
print_warning() { echo -e "${YELLOW}⚠ ${NC}$1"; }
print_error() { echo -e "${RED}✗ ${NC}$1"; }

# Function to ask yes/no questions
ask_yes_no() {
    local prompt="$1"
    local default="${2:-yes}"
    local response

    if [ "$default" == "yes" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -p "$(echo -e ${BLUE}?${NC}) $prompt" response
    response=${response:-$default}

    if [[ "$response" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to ask for input with default value
ask_input() {
    local prompt="$1"
    local default="$2"
    local response

    if [ -n "$default" ]; then
        read -p "$(echo -e ${BLUE}?${NC}) $prompt [$default]: " response
        echo "${response:-$default}"
    else
        read -p "$(echo -e ${BLUE}?${NC}) $prompt: " response
        echo "$response"
    fi
}

# Function to ask for password (hidden input)
ask_password() {
    local prompt="$1"
    local password

    read -s -p "$(echo -e ${BLUE}?${NC}) $prompt: " password
    echo ""
    echo "$password"
}

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Function to generate Django secret key
generate_django_secret() {
    python3 -c 'import random; import string; print("".join(random.SystemRandom().choice(string.ascii_letters + string.digits + string.punctuation) for _ in range(50)))' 2>/dev/null || \
    openssl rand -base64 50 | tr -d "=+/" | cut -c1-50
}

clear
echo -e "${GREEN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║   Django-Nginx-uWSGI Ansible - Interactive Setup            ║
║   Single Server Deployment with Staging & Production        ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

print_info "This script will help you configure your Django deployment."
print_info "You can press Enter to accept default values shown in brackets."
echo ""

# ============================================
# 1. SERVER CONFIGURATION
# ============================================
echo -e "${GREEN}═══ Server Configuration ═══${NC}"
echo ""

SERVER_IP=$(ask_input "Server IP address" "")
while [ -z "$SERVER_IP" ]; do
    print_error "Server IP is required!"
    SERVER_IP=$(ask_input "Server IP address" "")
done

HOSTNAME=$(ask_input "Server hostname" "django-server")
SSH_PORT=$(ask_input "SSH port" "22")
TIMEZONE=$(ask_input "Timezone" "Europe/Paris")

echo ""

# ============================================
# 2. DOMAIN CONFIGURATION
# ============================================
echo -e "${GREEN}═══ Domain Configuration ═══${NC}"
echo ""

if ask_yes_no "Enable staging environment?" "yes"; then
    STAGING_ENABLED="true"
    STAGING_DOMAIN=$(ask_input "Staging domain" "staging.example.com")
    STAGING_SSL=$(ask_yes_no "Enable SSL for staging?" "yes" && echo "true" || echo "false")
else
    STAGING_ENABLED="false"
    STAGING_DOMAIN="staging.example.com"
    STAGING_SSL="false"
fi

echo ""

PROD_ENABLED="true"
PROD_DOMAIN=$(ask_input "Production domain" "app.example.com")
PROD_SSL=$(ask_yes_no "Enable SSL for production?" "yes" && echo "true" || echo "false")

ADDITIONAL_DOMAINS=""
if ask_yes_no "Add additional domains for production? (e.g., www, apex)" "no"; then
    read -p "$(echo -e ${BLUE}?${NC}) Enter additional domains (comma-separated): " domains_input
    ADDITIONAL_DOMAINS="$domains_input"
fi

echo ""

# ============================================
# 3. SERVICES CONFIGURATION
# ============================================
echo -e "${GREEN}═══ Services Configuration ═══${NC}"
echo ""

# PostgreSQL
POSTGRES_VERSION=$(ask_input "PostgreSQL version" "15")
STAGING_DB=$(ask_input "Staging database name" "db_staging")
STAGING_USER=$(ask_input "Staging database user" "django_staging")
PROD_DB=$(ask_input "Production database name" "db_prod")
PROD_USER=$(ask_input "Production database user" "django_prod")

echo ""

# Redis
if ask_yes_no "Enable Redis for staging?" "yes"; then
    REDIS_STAGING_ENABLED="true"
    REDIS_STAGING_MEMORY=$(ask_input "Redis memory limit for staging" "512mb")
else
    REDIS_STAGING_ENABLED="false"
    REDIS_STAGING_MEMORY="512mb"
fi

if ask_yes_no "Enable Redis for production?" "yes"; then
    REDIS_PROD_ENABLED="true"
    REDIS_PROD_MEMORY=$(ask_input "Redis memory limit for production" "2gb")
else
    REDIS_PROD_ENABLED="false"
    REDIS_PROD_MEMORY="2gb"
fi

echo ""

# Celery
if ask_yes_no "Enable Celery workers?" "yes"; then
    CELERY_STAGING_ENABLED="true"
    CELERY_STAGING_REPLICAS=$(ask_input "Celery replicas for staging" "1")
    CELERY_STAGING_CONCURRENCY=$(ask_input "Celery concurrency for staging" "2")

    CELERY_PROD_ENABLED="true"
    CELERY_PROD_REPLICAS=$(ask_input "Celery replicas for production" "2")
    CELERY_PROD_CONCURRENCY=$(ask_input "Celery concurrency for production" "4")
else
    CELERY_STAGING_ENABLED="false"
    CELERY_PROD_ENABLED="false"
    CELERY_STAGING_REPLICAS="0"
    CELERY_STAGING_CONCURRENCY="1"
    CELERY_PROD_REPLICAS="0"
    CELERY_PROD_CONCURRENCY="1"
fi

echo ""

# Celery Beat
CELERY_BEAT_STAGING_ENABLED="false"
CELERY_BEAT_PROD_ENABLED="false"
if [ "$CELERY_PROD_ENABLED" == "true" ]; then
    if ask_yes_no "Enable Celery Beat (scheduled tasks) for production?" "yes"; then
        CELERY_BEAT_PROD_ENABLED="true"
    fi
    if [ "$STAGING_ENABLED" == "true" ]; then
        if ask_yes_no "Enable Celery Beat for staging?" "no"; then
            CELERY_BEAT_STAGING_ENABLED="true"
        fi
    fi
fi

echo ""

# Flower
FLOWER_STAGING_ENABLED="false"
FLOWER_PROD_ENABLED="false"
if [ "$CELERY_PROD_ENABLED" == "true" ]; then
    if ask_yes_no "Enable Flower (Celery monitoring) for production?" "yes"; then
        FLOWER_PROD_ENABLED="true"
    fi
    if [ "$STAGING_ENABLED" == "true" ]; then
        if ask_yes_no "Enable Flower for staging?" "no"; then
            FLOWER_STAGING_ENABLED="true"
        fi
    fi
fi

echo ""

# ============================================
# 4. DJANGO APP CONFIGURATION
# ============================================
echo -e "${GREEN}═══ Django Application Configuration ═══${NC}"
echo ""

DJANGO_STAGING_IMAGE=$(ask_input "Docker image for staging" "your-registry/your-app:staging")
DJANGO_STAGING_REPLICAS=$(ask_input "Django replicas for staging" "1")
DJANGO_STAGING_WORKERS=$(ask_input "Gunicorn workers for staging" "2")

echo ""

DJANGO_PROD_IMAGE=$(ask_input "Docker image for production" "your-registry/your-app:latest")
DJANGO_PROD_REPLICAS=$(ask_input "Django replicas for production" "2")
DJANGO_PROD_WORKERS=$(ask_input "Gunicorn workers for production" "4")

echo ""

# Nginx
NGINX_MAX_BODY_SIZE=$(ask_input "Nginx max body size" "100M")

echo ""

# ============================================
# 5. SECRETS GENERATION
# ============================================
echo -e "${GREEN}═══ Secrets Configuration ═══${NC}"
echo ""

print_info "Generating secure passwords and secrets..."
echo ""

# PostgreSQL passwords
if ask_yes_no "Auto-generate PostgreSQL passwords?" "yes"; then
    POSTGRES_ROOT_PASSWORD=$(generate_password)
    POSTGRES_STAGING_PASSWORD=$(generate_password)
    POSTGRES_PROD_PASSWORD=$(generate_password)
    print_success "PostgreSQL passwords generated"
else
    POSTGRES_ROOT_PASSWORD=$(ask_password "PostgreSQL root password")
    POSTGRES_STAGING_PASSWORD=$(ask_password "PostgreSQL staging password")
    POSTGRES_PROD_PASSWORD=$(ask_password "PostgreSQL production password")
fi

echo ""

# Django secret keys
if ask_yes_no "Auto-generate Django secret keys?" "yes"; then
    DJANGO_SECRET_STAGING=$(generate_django_secret)
    DJANGO_SECRET_PROD=$(generate_django_secret)
    print_success "Django secret keys generated"
else
    DJANGO_SECRET_STAGING=$(ask_password "Django secret key for staging")
    DJANGO_SECRET_PROD=$(ask_password "Django secret key for production")
fi

echo ""

# JWT secret keys
if ask_yes_no "Auto-generate JWT secret keys?" "yes"; then
    JWT_SECRET_STAGING=$(generate_password)
    JWT_SECRET_PROD=$(generate_password)
    print_success "JWT secret keys generated"
else
    JWT_SECRET_STAGING=$(ask_password "JWT secret key for staging")
    JWT_SECRET_PROD=$(ask_password "JWT secret key for production")
fi

echo ""

# Flower password
FLOWER_USERNAME="admin"
if [ "$FLOWER_PROD_ENABLED" == "true" ] || [ "$FLOWER_STAGING_ENABLED" == "true" ]; then
    if ask_yes_no "Auto-generate Flower password?" "yes"; then
        FLOWER_PASSWORD=$(generate_password)
        print_success "Flower password generated"
    else
        FLOWER_PASSWORD=$(ask_password "Flower password")
    fi
else
    FLOWER_PASSWORD=$(generate_password)
fi

echo ""

# Optional API keys
print_info "Optional API Keys (leave empty if not needed)"
echo ""

OPENAI_API_KEY=$(ask_input "OpenAI API Key" "")
STRIPE_SECRET_KEY=$(ask_input "Stripe Secret Key" "")
STRIPE_WEBHOOK_SECRET=$(ask_input "Stripe Webhook Secret" "")
GROQ_API_KEY=$(ask_input "Groq API Key" "")
GOOGLE_CLIENT_ID=$(ask_input "Google Client ID" "")
GOOGLE_CLIENT_SECRET=$(ask_input "Google Client Secret" "")
EMAIL_HOST_USER=$(ask_input "Email Host User" "")
EMAIL_HOST_PASSWORD=$(ask_password "Email Host Password")

echo ""

# ============================================
# 6. GENERATE CONFIGURATION FILES
# ============================================
echo -e "${GREEN}═══ Generating Configuration Files ═══${NC}"
echo ""

# Create project_config.yml
print_info "Creating project_config.yml..."
cat > project_config.yml << EOF
# Django-Nginx-uWSGI Ansible - Project Configuration
# Generated by setup.sh on $(date)

server:
  hostname: "$HOSTNAME"
  ip_address: "$SERVER_IP"
  ssh_port: $SSH_PORT
  timezone: "$TIMEZONE"

domains:
  staging:
    enabled: $STAGING_ENABLED
    domain: "$STAGING_DOMAIN"
    ssl: $STAGING_SSL
  production:
    enabled: $PROD_ENABLED
    domain: "$PROD_DOMAIN"
    additional_domains:
EOF

if [ -n "$ADDITIONAL_DOMAINS" ]; then
    IFS=',' read -ra DOMAINS <<< "$ADDITIONAL_DOMAINS"
    for domain in "${DOMAINS[@]}"; do
        echo "      - \"$(echo $domain | xargs)\"" >> project_config.yml
    done
fi

cat >> project_config.yml << EOF
    ssl: $PROD_SSL

services:
  postgresql:
    version: "$POSTGRES_VERSION"
    staging_db: "$STAGING_DB"
    staging_user: "$STAGING_USER"
    production_db: "$PROD_DB"
    production_user: "$PROD_USER"

  docker:
    data_root: "/data/docker"

  redis:
    staging:
      enabled: $REDIS_STAGING_ENABLED
      memory_limit: "$REDIS_STAGING_MEMORY"
    production:
      enabled: $REDIS_PROD_ENABLED
      memory_limit: "$REDIS_PROD_MEMORY"

  celery_worker:
    staging:
      enabled: $CELERY_STAGING_ENABLED
      replicas: $CELERY_STAGING_REPLICAS
      concurrency: $CELERY_STAGING_CONCURRENCY
    production:
      enabled: $CELERY_PROD_ENABLED
      replicas: $CELERY_PROD_REPLICAS
      concurrency: $CELERY_PROD_CONCURRENCY

  celery_beat:
    staging:
      enabled: $CELERY_BEAT_STAGING_ENABLED
    production:
      enabled: $CELERY_BEAT_PROD_ENABLED

  flower:
    staging:
      enabled: $FLOWER_STAGING_ENABLED
    production:
      enabled: $FLOWER_PROD_ENABLED

django:
  staging:
    docker_image: "$DJANGO_STAGING_IMAGE"
    replicas: $DJANGO_STAGING_REPLICAS
    port: 8001
    workers: $DJANGO_STAGING_WORKERS
    threads: 2
    timeout: 120
  production:
    docker_image: "$DJANGO_PROD_IMAGE"
    replicas: $DJANGO_PROD_REPLICAS
    port: 8000
    workers: $DJANGO_PROD_WORKERS
    threads: 2
    timeout: 300

nginx:
  client_max_body_size: "$NGINX_MAX_BODY_SIZE"
  worker_processes: "auto"
  worker_connections: 1024

security:
  fail2ban:
    enabled: true
    ssh_maxretry: 3
    ssh_bantime: 3600
    nginx_maxretry: 5
    nginx_bantime: 600

  firewall:
    enabled: true
    allowed_ports:
      - 22
      - 80
      - 443
    allowed_ips: []

monitoring:
  log_retention_days: 30

backup:
  enabled: false
  schedule: "0 2 * * *"
  retention_days: 7
EOF

print_success "project_config.yml created"

# Create inventory/hosts
print_info "Creating inventory/hosts..."
mkdir -p inventory
cat > inventory/hosts << EOF
[all:vars]
ansible_user=ansible
ansible_ssh_private_key_file=~/.ssh/ansible_rsa
ansible_python_interpreter=/usr/bin/python3

[django_server]
production ansible_host=$SERVER_IP
EOF

print_success "inventory/hosts created"

# Create group_vars/all/vars.yml
print_info "Creating group_vars/all/vars.yml..."
mkdir -p group_vars/all
cat > group_vars/all/vars.yml << EOF
# Django-Nginx-uWSGI Ansible - Variables
# Generated by setup.sh on $(date)

# Load project configuration
project_config: "{{ lookup('file', playbook_dir + '/../project_config.yml') | from_yaml }}"

# Server configuration
server_hostname: "{{ project_config.server.hostname }}"
server_ip: "{{ project_config.server.ip_address }}"
server_timezone: "{{ project_config.server.timezone }}"

# Domains
staging_domain: "{{ project_config.domains.staging.domain }}"
production_domain: "{{ project_config.domains.production.domain }}"

# PostgreSQL
postgres_version: "{{ project_config.services.postgresql.version }}"
postgres_staging_db: "{{ project_config.services.postgresql.staging_db }}"
postgres_staging_user: "{{ project_config.services.postgresql.staging_user }}"
postgres_production_db: "{{ project_config.services.postgresql.production_db }}"
postgres_production_user: "{{ project_config.services.postgresql.production_user }}"

# Django
django_staging_image: "{{ project_config.django.staging.docker_image }}"
django_production_image: "{{ project_config.django.production.docker_image }}"
EOF

print_success "group_vars/all/vars.yml created"

# Create vault.yml
print_info "Creating group_vars/all/vault.yml..."
cat > group_vars/all/vault.yml << EOF
# Ansible Vault - Secrets
# Generated by setup.sh on $(date)

# PostgreSQL Passwords
postgres_root_password: "$POSTGRES_ROOT_PASSWORD"
postgres_staging_password: "$POSTGRES_STAGING_PASSWORD"
postgres_production_password: "$POSTGRES_PROD_PASSWORD"

# Django Secret Keys
django_secret_key_staging: "$DJANGO_SECRET_STAGING"
django_secret_key_production: "$DJANGO_SECRET_PROD"

# JWT Secret Keys
jwt_secret_key_staging: "$JWT_SECRET_STAGING"
jwt_secret_key_production: "$JWT_SECRET_PROD"

# Flower (Celery monitoring)
flower_username: "$FLOWER_USERNAME"
flower_password: "$FLOWER_PASSWORD"

# API Keys
openai_api_key: "$OPENAI_API_KEY"
stripe_secret_key: "$STRIPE_SECRET_KEY"
stripe_webhook_secret: "$STRIPE_WEBHOOK_SECRET"
groq_api_key: "$GROQ_API_KEY"
google_client_id: "$GOOGLE_CLIENT_ID"
google_client_secret: "$GOOGLE_CLIENT_SECRET"

# Email Configuration
email_host_user: "$EMAIL_HOST_USER"
email_host_password: "$EMAIL_HOST_PASSWORD"

# Docker Registry
docker_registry_username: ""
docker_registry_password: ""
EOF

print_success "group_vars/all/vault.yml created (UNENCRYPTED)"

echo ""

# ============================================
# 7. ENCRYPT VAULT
# ============================================
echo -e "${GREEN}═══ Vault Encryption ═══${NC}"
echo ""

if ask_yes_no "Encrypt vault.yml with ansible-vault?" "yes"; then
    print_info "You will need to create a vault password..."
    echo ""

    # Create vault password file
    VAULT_PASSWORD=$(ask_password "Enter vault password")
    echo "$VAULT_PASSWORD" > .vault_pass
    chmod 600 .vault_pass

    # Encrypt the vault
    ansible-vault encrypt group_vars/all/vault.yml --vault-password-file .vault_pass

    print_success "vault.yml encrypted successfully"
    print_warning "Vault password saved to .vault_pass (kept in .gitignore)"
else
    print_warning "vault.yml left UNENCRYPTED - remember to encrypt it before committing!"
fi

echo ""

# ============================================
# 8. SUMMARY
# ============================================
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}    Setup Complete! 🎉${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""

print_success "Configuration files created:"
echo "  • project_config.yml"
echo "  • inventory/hosts"
echo "  • group_vars/all/vars.yml"
echo "  • group_vars/all/vault.yml"
echo ""

print_info "Next steps:"
echo "  1. Review the generated configuration files"
echo "  2. Ensure your SSH key (~/.ssh/ansible_rsa) is set up"
echo "  3. Run the setup playbook:"
echo "     ${BLUE}ansible-playbook playbooks/setup_server.yml${NC}"
echo ""
echo "  4. Deploy your application:"
echo "     ${BLUE}ansible-playbook playbooks/deploy_staging.yml${NC}"
echo "     ${BLUE}ansible-playbook playbooks/deploy_production.yml${NC}"
echo ""

print_warning "Important:"
echo "  • Never commit vault.yml unencrypted!"
echo "  • Keep .vault_pass secure and never commit it"
echo "  • Update your Django app Docker images in project_config.yml"
echo ""

print_info "Configuration summary:"
echo "  Server: $SERVER_IP ($HOSTNAME)"
echo "  Staging: $STAGING_DOMAIN (enabled: $STAGING_ENABLED)"
echo "  Production: $PROD_DOMAIN (enabled: $PROD_ENABLED)"
echo "  Celery: enabled=$CELERY_PROD_ENABLED, Beat: enabled=$CELERY_BEAT_PROD_ENABLED"
echo "  Flower: enabled=$FLOWER_PROD_ENABLED"
echo ""

print_success "Happy deploying! 🚀"
