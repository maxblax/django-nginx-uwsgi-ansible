# Django-Nginx-uWSGI Ansible

**Production-ready Django deployment automation for single-server setups**

Deploy Django applications with Nginx, PostgreSQL, Redis, and Celery on a single bare-metal server. Supports **staging** and **production** environments on the same machine using Docker Swarm for zero-downtime deployments.

## ✨ Features

- 🚀 **One-command setup** - Interactive script configures everything
- 🔒 **Security hardened** - UFW firewall, Fail2ban, SSH key auth
- 🐘 **PostgreSQL on bare metal** - Separate databases for staging/prod  
- 🐳 **Docker Swarm** - Single-node Swarm for rolling updates
- 🔄 **Zero-downtime deployments** - Blue-green style updates
- 🔐 **Automatic SSL** - Let's Encrypt with auto-renewal
- 📊 **Optional monitoring** - Flower for Celery
- ⚙️ **Highly modular** - Enable/disable any service per environment
- 🎯 **Simple & focused** - Perfect for small to medium Django projects

## 🏗️ Architecture

### Infrastructure
- **1 bare-metal server** (Debian/Ubuntu)
- **Nginx** on host as reverse proxy
- **PostgreSQL** on host with 2 databases
- **Docker Swarm** single-node mode

### Modular Services (per environment)
- **Django app** (Gunicorn) - Required
- **Redis** - Optional cache/broker
- **Celery workers** - Optional, configurable queues
  - Default queue workers
  - Orchestrator queue workers (optional)
- **Celery Beat** - Optional scheduled tasks
- **Flower** - Optional Celery monitoring

### Network Flow
```
Internet → Nginx :80/:443
    ├─ staging.example.com → :8001 → Staging Stack
    └─ app.example.com     → :8000 → Production Stack
```

## 📋 Prerequisites

### Local machine
- Ansible 2.10+
- Python 3.8+
- SSH key pair (`~/.ssh/ansible_rsa`)

### Target server
- Debian 11+ or Ubuntu 20.04+
- Fresh server with root access
- 2GB RAM minimum (4GB+ recommended)
- Public IP address
- Domain names pointing to server

## 🚀 Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/yourusername/django-nginx-uwsgi-ansible.git
cd django-nginx-uwsgi-ansible
./setup.sh
```

The interactive script will ask about:
- Server details (IP, hostname)
- Domains (staging & production)
- Services to enable (Redis, Celery workers, Orchestrator, Beat, Flower)
- Auto-generate secure passwords

**Creates:**
- `project_config.yml` - Your configuration
- `inventory/hosts` - Ansible inventory  
- `group_vars/all/vars.yml` - Public variables
- `group_vars/all/vault.yml` - Encrypted secrets

### 2. Setup server

```bash
ansible-playbook playbooks/setup_server.yml
```

Installs and configures:
- User management & SSH hardening
- Docker & Swarm
- PostgreSQL (2 databases)
- Nginx reverse proxy
- Firewall (UFW)
- Fail2ban

### 3. Deploy applications

```bash
# Deploy staging
ansible-playbook playbooks/deploy_staging.yml

# Deploy production  
ansible-playbook playbooks/deploy_production.yml
```

### 4. Setup SSL (after deployment)

```bash
ansible-playbook playbooks/setup_ssl.yml
```

This:
- Obtains Let's Encrypt certificates
- Configures HTTPS redirect
- Sets up automatic renewal (twice daily)
- Tests certificate renewal

## ⚙️ Configuration

### Modular Services

Edit `project_config.yml` to enable/disable services:

```yaml
services:
  # Redis - Optional
  redis:
    staging:
      enabled: true
      memory_limit: "512mb"
    production:
      enabled: true  
      memory_limit: "2gb"

  # Celery Workers - Optional, default queue
  celery_worker:
    staging:
      enabled: true
      replicas: 1
      concurrency: 2
    production:
      enabled: true
      replicas: 2
      concurrency: 4

  # Celery Orchestrator - Optional, separate queue
  celery_orchestrator:
    staging:
      enabled: false
      replicas: 0
    production:
      enabled: false  # Enable for orchestration pattern
      replicas: 1
      concurrency: 1

  # Celery Beat - Optional
  celery_beat:
    staging:
      enabled: false
    production:
      enabled: true

  # Flower - Optional
  flower:
    staging:
      enabled: false
    production:
      enabled: true
```

### SSL Configuration

```yaml
ssl:
  enabled: true
  email: "admin@example.com"
  staging_cert: false  # Use Let's Encrypt staging (for testing)
```

### Complete Config Structure

```yaml
server:
  hostname: "django-server"
  ip_address: "1.2.3.4"
  ssh_port: 22
  timezone: "Europe/Paris"

domains:
  staging:
    enabled: true
    domain: "staging.example.com"
    ssl: true
  production:
    enabled: true
    domain: "app.example.com"
    additional_domains:
      - "example.com"
      - "www.example.com"
    ssl: true

django:
  staging:
    docker_image: "registry.example.com/app:staging"
    replicas: 1
    workers: 2
  production:
    docker_image: "registry.example.com/app:latest"
    replicas: 2
    workers: 4
```

## 🔒 SSL/TLS Auto-Renewal

SSL certificates auto-renew using systemd timers:

- **Schedule**: Twice daily (00:00 and 12:00)
- **Renewal**: 30 days before expiry
- **Post-renewal**: Nginx auto-reloads

**Manual operations:**
```bash
# Test renewal
sudo certbot renew --dry-run

# Force renewal
sudo certbot renew --force-renewal

# Check timer status
sudo systemctl status certbot-renewal.timer

# View renewal logs
sudo journalctl -u certbot-renewal.service
```

**How it works:**
1. Systemd timer (`certbot-renewal.timer`) triggers twice daily
2. Certbot checks all certificates
3. Renews any expiring within 30 days
4. Runs post-hook to reload Nginx
5. No manual intervention needed!

## 🔧 Common Tasks

### Update Django app

```bash
ansible-playbook playbooks/deploy_staging.yml
# or
ansible-playbook playbooks/deploy_production.yml
```

Docker Swarm performs rolling updates with zero downtime.

### Scale services

Edit `project_config.yml`:
```yaml
django:
  production:
    replicas: 4  # Increase from 2
```

Then redeploy:
```bash
ansible-playbook playbooks/deploy_production.yml
```

### View logs

```bash
# Django app logs
docker service logs production_django_app -f

# Celery logs
docker service logs production_django_celery_worker -f

# All services
docker stack ps production_django
```

### Run Django commands

```bash
# Find container
docker ps | grep production_django_app

# Exec into container
docker exec -it <container_id> bash

# Run commands
python manage.py createsuperuser
python manage.py migrate
```

### Rollback deployment

```bash
docker service rollback production_django_app
```

### Database operations

PostgreSQL is on the host:
```bash
# Connect
sudo -u postgres psql

# Backup production
sudo -u postgres pg_dump db_prod > backup.sql

# Restore
sudo -u postgres psql db_prod < backup.sql
```

## 📁 Project Structure

```
django-nginx-uwsgi-ansible/
├── setup.sh                    # Interactive setup
├── ansible.cfg                 
├── project_config.yml          # Generated config
├── inventory/
│   └── hosts                   # Generated inventory
├── group_vars/all/
│   ├── vars.yml                # Generated variables
│   └── vault.yml               # Encrypted secrets
├── playbooks/
│   ├── setup_server.yml        # Complete server setup
│   ├── deploy_staging.yml      # Deploy staging
│   ├── deploy_production.yml   # Deploy production
│   └── setup_ssl.yml           # SSL certificate setup
├── roles/
│   ├── 01_user_management/     # User & SSH
│   ├── 02_packages/            # System packages
│   ├── 03_hostname/            # Hostname & timezone
│   ├── 04_firewall/            # UFW
│   ├── 05_fail2ban/            # Fail2ban
│   ├── 06_postgresql/          # PostgreSQL + DBs
│   ├── 07_docker_swarm/        # Docker & Swarm
│   ├── 08_nginx_revproxy/      # Nginx reverse proxy
│   ├── 09_django_app/          # Django deployment
│   └── 10_ssl_certbot/         # SSL/TLS setup
└── templates/
    ├── project_config.yml.example
    └── vault.yml.example
```

## 🔐 Security

**Implemented:**
- ✅ SSH key-only auth (password disabled)
- ✅ Root SSH disabled
- ✅ UFW firewall (ports 22, 80, 443)
- ✅ Fail2ban (SSH + Nginx)
- ✅ PostgreSQL localhost-only
- ✅ Ansible Vault encryption
- ✅ Nginx rate limiting
- ✅ SSL/TLS with auto-renewal

**Recommendations:**
1. Change SSH port in `project_config.yml`
2. Restrict SSH by IP (`firewall.allowed_ips`)
3. Enable automatic security updates
4. Regular database backups
5. Monitor auth logs

## 🐛 Troubleshooting

### Services not starting

```bash
docker stack ps production_django
docker service ps production_django_app --no-trunc
```

### Database connection errors

```bash
sudo systemctl status postgresql
sudo -u postgres psql -l
```

Django connects to PostgreSQL via `172.17.0.1` (Docker bridge).

### Nginx errors

```bash
sudo nginx -t
sudo tail -f /var/log/nginx/error.log
```

### SSL certificate issues

```bash
# Test renewal
sudo certbot renew --dry-run

# Check certificates
sudo certbot certificates

# View logs
sudo journalctl -u certbot-renewal.service -f
```

### Firewall blocking

```bash
sudo ufw status
```

## 🎯 Workflow Summary

**Initial Setup:**
```bash
./setup.sh                                    # Configure project
ansible-playbook playbooks/setup_server.yml   # Setup server
ansible-playbook playbooks/deploy_staging.yml # Deploy staging
ansible-playbook playbooks/setup_ssl.yml      # Setup SSL
```

**Regular Deployments:**
```bash
ansible-playbook playbooks/deploy_production.yml
```

**SSL manages itself!** ✨

## 🤝 Contributing

Contributions welcome!
1. Fork repository
2. Create feature branch
3. Submit pull request

## 📄 License

MIT License

## 🙏 Credits

Inspired by production Django patterns and the need for simple, reproducible deployments.

---

**Happy deploying! 🚀**
