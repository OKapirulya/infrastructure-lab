# infrastructure-lab

This is the part of my portfolio that nobody sees running, but everything else depends on. [inventory-api](https://github.com/OKapirulya/inventory-api) and [monitoring-stack](https://github.com/OKapirulya/monitoring-stack) both live on a single VPS, and this project is what sets that server up and keeps it in shape: users, a firewall, SSH hardening, fail2ban, the works. All of it as code, instead of a list of commands I half remember typing once.

## Stack

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=flat&logo=ansible&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-009639?style=flat&logo=nginx&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=githubactions&logoColor=white)

## The short version

Terraform spins up a disposable test container on the same VPS. Ansible hardens it first, to catch mistakes somewhere that doesn't matter. Once a change behaves on the container, the exact same playbook runs against the real server. A small script connects the two tools, so the test target is always read from Terraform directly, never typed in twice by hand.

## Why a container instead of a cloud VM

Terraform usually spins up real virtual machines through a cloud provider's API. My VPS is hosted with a provider that doesn't expose one on this plan, so Terraform has no way to create or destroy a server here.

What it can do is talk to the Docker Engine already running on that VPS, over SSH, and manage a container there. That container was never meant to look like a production server. It exists so Ansible roles can be tried out somewhere safe, before they ever get near the machine that actually matters.

## How Terraform and Ansible are actually connected

This part took a few tries to get right, so it's worth spelling out.

~~~
terraform apply
  -> creates (or updates) the test container, its name tracked in Terraform's state

scripts/generate-test-inventory.sh
  -> reads that name straight from Terraform's output
  -> writes ansible/inventory/test

ansible-playbook playbook.yml --limit test
  -> uses that file, always current, never hand maintained
~~~

Production lives in its own file, `ansible/inventory/production`, which I keep and edit myself since Terraform has no business touching the real server's identity.

## Getting a fresh server ready

Hardening and the app-server role both connect as `oleg`, over SSH, with a key. On a server that was just wiped, that user doesn't exist yet, nothing does except root. `bootstrap.yml` is what gets from a bare server to a usable one: it creates `oleg` (sudo, used for everything else from here on) and `deploy` (no sudo, used only by CI), and drops both their public keys into place.

It's meant to run exactly once, right after a reinstall, connected as root with whatever access the provider still gives you at that point:

~~~
ansible-playbook -i inventory/production bootstrap.yml -u root --ask-pass
~~~

Everything else in this repo assumes that step already happened.

## What the hardening role does

- Installs `sudo` and makes sure `oleg`, the user `bootstrap.yml` already created, is in the sudo group. On production this is a no-op by the time it runs, it's just a safety net in case this role is ever pointed at a box that skipped bootstrap
- Installs `fail2ban`, `unattended-upgrades`, and `curl`
- Turns on automatic security updates
- Installs UFW and enables it with a default deny policy, only SSH, HTTP, and HTTPS allowed through (production only)
- Turns off SSH root login and password authentication, so only keys get you in (production only)
- Writes a fail2ban jail for SSH: five failed logins within ten minutes earns an IP a one hour ban

The two "production only" items are skipped on the test container on purpose. It has no init system and no real network stack to speak of, so there's nothing there for a firewall or an SSH daemon to actually manage.

## What the app-server role does

Hardening makes the server safe to use. This role makes it useful.

It installs Docker and adds `oleg` to the `docker` group, installs Nginx, and sets up a reverse proxy and TLS certificate for each app subdomain (`api.olegkapy.com`, `monitoring.olegkapy.com`) via Certbot.

The vhost config is only written the first time. Once Certbot has added its own `listen 443 ssl` block to a config file, re-running the role checks for an existing certificate first and leaves that file alone, so a routine playbook run can never silently strip HTTPS back out again.

## Locking down the deploy key

`deploy`'s SSH key is the one GitHub Actions holds, used to redeploy inventory-api after every push to `main`. That makes it a different kind of credential than `oleg`'s: it lives in GitHub Secrets, gets read by a third-party Action on every run, and nothing I do locally protects it.

So it doesn't get a shell at all. Its entry in `authorized_keys` forces one fixed command, a script that does exactly what the CI step always asked for (`git pull`, `docker compose up --build -d`, prune old images), no matter what command actually gets sent over the connection. `deploy` runs that script through a narrow, passwordless sudo rule rather than through `docker` group membership, so there's no group left to escalate through even if the key ever leaked.

This doesn't touch the separate `terraform-deploy` key, also authenticating as `deploy`, which never leaves my own machine. That one keeps full access, since it's never handled by anything but me.

## Before running anything against the real server

Terraform has `plan`, which shows what would happen without doing it. Ansible has the same thing, it's just easy to forget:

~~~
ansible-playbook playbook.yml --limit production --ask-become-pass --check --diff
~~~

`--check` simulates the run, `--diff` shows exactly which lines in which files would change. I run this before every production apply, the same way I'd never skip `terraform plan`.

## Security decisions worth knowing about

- `oleg` and `deploy` never share a job. `oleg` has sudo and is the only user hardening or app-server ever connect as; `deploy` can't get a shell at all, only trigger the one fixed redeploy script described above
- Host key checking stays on. The server's key gets added to `known_hosts` once, on purpose, with `ssh-keyscan`, rather than switching the check off in Ansible's config
- Sudo on production asks for a password every time, typed in by hand, instead of being configured away for convenience
- UFW rules go in before the firewall turns on, and SSH is allowed first of all, so a run can never lock out the only way back in

## Running it yourself

You'll need Terraform, Ansible, and the collections pinned in `ansible/requirements.yml`:

~~~
ansible-galaxy collection install -r ansible/requirements.yml
~~~

Copy the production inventory and variables templates, and fill in your own server:

~~~
cp ansible/inventory.example ansible/inventory/production
cp ansible/group_vars/production/vars.yml.example ansible/group_vars/production/vars.yml
~~~

On a freshly provisioned server, run bootstrap first (see above). Then bring up the test container:

~~~
cd terraform
terraform init
terraform apply
~~~

Generate its inventory entry and run the roles against it:

~~~
cd ..
./scripts/generate-test-inventory.sh
cd ansible
ansible-playbook playbook.yml --limit test
~~~

Once that's clean, do the same against production, dry run first:

~~~
ansible-playbook playbook.yml --limit production --ask-become-pass --check --diff
ansible-playbook playbook.yml --limit production --ask-become-pass
~~~

## What else is in here

A GitHub Actions pipeline runs on every push: `terraform fmt` and `terraform validate` on one side, `ansible-lint` (at the `production` profile, the strictest one) and `yamllint` on the other. Neither job ever touches real infrastructure. They just make sure the code itself is sound before anything gets applied by hand.

## Roadmap

One piece of a bigger self-study project, alongside [inventory-api](https://github.com/OKapirulya/inventory-api), [monitoring-stack](https://github.com/OKapirulya/monitoring-stack), and log aggregation.