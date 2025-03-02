# Homelab Deployment System

This repository contains the infrastructure as code for deploying and managing a homelab environment using Ansible, Docker, and GitHub Actions. The system automates the deployment of various services to my homelab server(s) whenever changes are pushed to the repository.

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Ansible Setup](#ansible-setup)
- [Service Configuration](#service-configuration)
- [Deployment Process](#deployment-process)
- [GitHub Actions Workflow](#github-actions-workflow)
- [Managing Multiple Services](#managing-multiple-services)
- [Troubleshooting](#troubleshooting)

## Overview

This system provides an automated way to deploy and manage Docker-based services on my homelab server(s). It uses:

- **Ansible** for configuration management and service deployment
- **Docker Compose** for defining and running multi-container Docker applications
- **GitHub Actions** for continuous integration and deployment
- **WireGuard VPN** for secure remote access to my homelab

The workflow automatically detects changes to service definitions and deploys only the affected services, making updates efficient and targeted.

## Repository Structure

```
.
├── ansible/                  # Ansible configuration files
│   ├── group_vars/           # Variables for groups of hosts
│   │   ├── all.yml           # Common variables (encrypted)
│   │   └── targets.yml       # Service to host mapping (not encrypted)
│   ├── inventory.ini         # Host inventory file
│   ├── pass                  # Vault password file (encrypted)
│   ├── playbook.yml          # Main Ansible playbook
│   └── process_service.yml   # Tasks for processing each service
├── docker/                   # Docker service definitions
│   ├── service1/             # Each service has its own directory
│   │   ├── docker-compose.yml # Docker Compose configuration
│   │   └── .env.j2           # Environment variables template
│   └── service2/
│       └── ...
└── .github/
    ├── workflows/
    │   └── deploy.yml        # GitHub Actions workflow
    └── deployment-marker.txt # Tracks last successful deployment
```

## Ansible Setup

### Inventory Configuration

The `ansible/inventory.ini` file defines the hosts where services will be deployed:

```ini
[all]

[servers]
helios ansible_host=192.168.1.105
```

Each host entry includes:

- Hostname (e.g., `helios`)
- IP address (`ansible_host=192.168.1.105`)

### Playbook Structure

The main playbook (`ansible/playbook.yml`) orchestrates the deployment process:

1. Determines which hosts to run on (runs on all hosts initially)
2. Loads variables from `group_vars/all.yml` and `group_vars/targets.yml`
3. Gets the list of changed services from the environment variable
4. Converts the comma-separated string of services into a proper list
5. Processes each changed service using `process_service.yml`, but only on hosts that are configured to run that service

### Service to Host Mapping

The `ansible/group_vars/targets.yml` file defines which services should be deployed to which hosts:

```yaml
deploy_targets:
  server1:
    - authentik
    - beszel
    - open-webui
    # ... other services
  server2:
    - service1
    - service2
```

This mapping is used to determine which host to deploy each service to. When a service is being deployed, the playbook looks up the service name in this mapping and selects the appropriate host.

### Service Processing

For each service, the system:

1. Defines service paths (apps and appdata directories)
2. Verifies required variables
3. Stops any existing Docker containers
4. Creates required directories
5. Processes volume files (if present):
   - Processes any .j2 template files found in the volume directory
   - Copies all non-template files from the volume directory to the appdata directory
6. Generates Docker Compose configuration from templates
7. Generates environment files from templates
8. Starts the Docker Compose stack

### Volume Files

If a service has a `volume` directory (e.g., `docker/traefik/volume/`), the system will:

1. Process any `.j2` template files found in the volume directory, applying Ansible variables
2. Copy all non-template files to the service's appdata directory (e.g., `/home/user/appdata/traefik/`)

This allows you to include configuration files, certificates, and other static files that should be placed in the service's data directory.

You can control the file copying behavior with the following variables:

- `overwrite_volume_files`: Controls whether existing files should be overwritten (defaults to `true`)

Example volume directory structure:

```
docker/
  traefik/
    volume/
      config.yml          # Regular file, will be copied as-is
      certificates/       # Directory with files, will be copied recursively
        cert.pem
      dynamic_conf.yml.j2 # Template file, will be processed with Ansible variables
```

## Service Configuration

Each service is defined in its own directory under `docker/`:

### Docker Compose Configuration

The `docker-compose.yml` file defines the containers, networks, volumes, and other settings for the service:

```yaml
services:
  service_name:
    container_name: service_name
    image: image:tag
    restart: unless-stopped
    networks:
      - traefik-proxy
    volumes:
      - ${APPDATA_PATH}/data:/data
    environment:
      - ENV_VAR1=${ENV_VAR1}
    labels:
      - traefik.enable=true
      - traefik.http.routers.service.rule=Host(`${DOMAIN_NAME}`)
```

### Environment Variables

The `.env.j2` file is a Jinja2 template for generating the service's environment variables:

```
DOMAIN_NAME={{ domain_name }}
LOCAL_DOMAIN_NAME={{ local_domain_name }}
APPDATA_PATH={{ appdata_path }}
```

These variables are populated from Ansible variables during deployment.

## Deployment Process

The deployment process follows these steps:

1. **Change Detection**: The system identifies which services have changed since the last successful deployment
2. **Environment Setup**: The list of changed services is passed to Ansible via an environment variable
3. **Service List Processing**: The playbook converts the comma-separated string of services into a proper list
4. **Target Selection**: For each service in the list, it determines which host(s) to deploy to based on the mapping in `targets.yml`
5. **Service Deployment**: It processes each service using the steps defined in `process_service.yml`, but only on the appropriate hosts
6. **Deployment Tracking**: After successful deployment, it updates the deployment marker

## GitHub Actions Workflow

The GitHub Actions workflow (`.github/workflows/deploy.yml`) automates the deployment process whenever changes are pushed to the `master` branch.

### Workflow Steps

1. **Checkout**: Retrieves the repository code
2. **Setup**: Installs required packages (Ansible, WireGuard)
3. **Change Detection**: Identifies which services have changed
4. **VPN Connection**: Establishes a secure WireGuard connection to the homelab
5. **SSH Setup**: Configures SSH for connecting to the hosts
6. **Ansible Deployment**: Runs the Ansible playbook for each changed service
7. **Deployment Tracking**: Updates the deployment marker file

### Concurrency Control

The workflow uses concurrency settings to ensure only one deployment runs at a time:

```yaml
concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: true
```

This prevents conflicts when multiple PRs are merged in quick succession.

### Deployment Marker

The system tracks successful deployments using a marker file (`.github/deployment-marker.txt`), which contains the commit hash of the last successful deployment. This enables the system to:

1. Detect changes since the last successful deployment
2. Skip unnecessary deployments when no services have changed
3. Handle multiple PR merges efficiently

## Managing Multiple Services

### Adding a New Service

To add a new service:

1. Create a new directory under `docker/` with the service name
2. Add a `docker-compose.yml` file defining the service
3. Add an `.env.j2` template for environment variables
4. Commit and push the changes

The GitHub Actions workflow will automatically deploy the new service.

### Updating a Service

To update an existing service:

1. Modify the service's `docker-compose.yml` or `.env.j2` files
2. Commit and push the changes

The workflow will detect the changes and deploy only the affected service.

### Multiple PR Handling

When multiple PRs are merged simultaneously:

1. Only one workflow run will execute (due to concurrency settings)
2. All changes from all merged PRs will be detected
3. All affected services will be deployed in a single run
4. The deployment marker will be updated to the latest commit

By default, if no deployment marker exists (first run), the system will limit deployments to the 5 most recently modified services to prevent overwhelming the system. This limit can be adjusted using the `MAX_DEPLOY_SERVICES` environment variable.

## Troubleshooting

### Common Issues

- **SSH Connection Failures**: Ensure SSH keys are properly configured in GitHub Secrets
- **WireGuard Connection Issues**: Verify WireGuard configuration in GitHub Secrets
- **Ansible Errors**: Check the Ansible logs for detailed error messages
- **Deployment Marker Issues**: If the marker file is missing, the system will fall back to a limited deployment

### Logs and Debugging

GitHub Actions provides detailed logs for each workflow run. Check these logs to diagnose issues with the deployment process.
