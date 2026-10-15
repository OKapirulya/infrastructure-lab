# infrastructure-lab

Terraform and Ansible setup that provisions a disposable test environment and uses it to safely develop and verify the configuration management that hardens the production server behind [inventory-api](https://github.com/OKapirulya/inventory-api) and [monitoring-stack](https://github.com/OKapirulya/monitoring-stack).

## How this fits into the bigger picture

inventory-api, monitoring-stack, and log-aggregation all run as Docker containers on a single VPS. Together they form one continuous story: an API, observed by metrics, with its logs collected and searchable, all deployed through a CI/CD pipeline. This project is the layer underneath that story: the operating system the containers actually run on.

Rather than being a separate exercise, it takes the manual steps used when that same server was first set up (creating users, installing fail2ban, enabling automatic security updates) and turns them into versioned, repeatable code. The target of this project's Ansible playbook is the exact machine that serves `api.olegkapy.com` and `monitoring.olegkapy.com` today.

## Why Docker instead of a cloud VM

Terraform normally provisions virtual machines through a cloud provider's API (Hetzner, AWS, DigitalOcean, and so on). The VPS this project targets is hosted with a provider that has no such API available on this plan, so Terraform cannot create or destroy a real server here.

Instead, Terraform talks to the Docker Engine API on the existing VPS over SSH and manages a container. That container is not meant to simulate a production server. It is a disposable target to develop and test Ansible roles against before they ever touch the real machine, the same way application code runs through CI checks before it reaches production.

## Architecture

~~~
Terraform (kreuzwerker/docker provider)
  -> creates a plain ubuntu:24.04 container over SSH

Ansible (hardening role)
  -> test target:        the container above
  -> production target:  the real VPS running inventory-api, monitoring-stack, log-aggregation
~~~

Both targets are defined in one inventory, grouped as `test` and `production`. Every playbook run is pointed explicitly at one group with `--limit`, so a command developed against the container can never accidentally run against the live server.

Some tasks only run against `production`: the test container has no init system and no real network stack to manage, so firewall and SSH daemon configuration are skipped there and only verified once they reach the real server.

## What the hardening role does

- Installs `sudo` and creates a dedicated, limited user for configuration management tasks
- Installs `fail2ban`, `unattended-upgrades`, and `curl`
- Enables automatic security updates
- Installs and enables UFW with a default-deny policy, allowing only SSH, HTTP, and HTTPS (production only)
- Disables SSH root login and password authentication, enforcing key-based access (production only)
- Deploys a fail2ban jail for SSH: bans an IP for one hour after 5 failed login attempts within 10 minutes

## Security decisions worth calling out

- The `deploy` user used by the inventory-api CI/CD pipeline keeps the minimal, docker-only permissions it was created with. Hardening tasks run as a separate user with its own key and sudo access, so the two responsibilities stay cleanly separated.
- Host key checking is left enabled. The server's SSH host key is added to `known_hosts` once, deliberately, with `ssh-keyscan`, rather than disabling the check in Ansible's configuration.
- Sudo on production requires a password, entered interactively per run (`--ask-become-pass`), rather than configuring passwordless sudo for convenience.
- UFW rules are applied before the firewall is enabled, and SSH access is allowed first, so a run can never lock out the only way in.

## Usage

Requirements: Terraform, Ansible, and the `community.docker` and `community.general` collections (`ansible-galaxy collection install community.docker community.general`). Docker must be reachable from your machine over the SSH alias configured for the target server.

Copy the inventory template and fill in your own server details:

~~~
cp ansible/inventory.ini.example ansible/inventory.ini
~~~

Create the test container:

~~~
cd terraform
terraform init
terraform apply
~~~

Run the hardening role against the test container first:

~~~
cd ../ansible
ansible-playbook playbook.yml --limit test
~~~

Once that passes cleanly, run it against production:

~~~
ansible-playbook playbook.yml --limit production --ask-become-pass
~~~

## Roadmap

This is one part of a larger self-study project: inventory-api, monitoring-stack, log-aggregation, this infrastructure project, and eventually a Kubernetes deployment of inventory-api.