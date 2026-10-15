# infrastructure-lab

This is the part of my portfolio that nobody sees running, but everything else depends on. [inventory-api](https://github.com/OKapirulya/inventory-api) and [monitoring-stack](https://github.com/OKapirulya/monitoring-stack) both live on a single VPS, and this project is what sets that server up and keeps it in shape: users, a firewall, SSH hardening, fail2ban, the works. All of it as code, instead of a list of commands I half remember typing once.

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

## What the hardening role does

- Installs `sudo` and creates a dedicated, limited user for configuration tasks
- Installs `fail2ban`, `unattended-upgrades`, and `curl`
- Turns on automatic security updates
- Installs UFW and enables it with a default deny policy, only SSH, HTTP, and HTTPS allowed through (production only)
- Turns off SSH root login and password authentication, so only keys get you in (production only)
- Writes a fail2ban jail for SSH: five failed logins within ten minutes earns an IP a one hour ban

The two "production only" items are skipped on the test container on purpose. It has no init system and no real network stack to speak of, so there's nothing there for a firewall or an SSH daemon to actually manage.

## Before running anything against the real server

Terraform has `plan`, which shows what would happen without doing it. Ansible has the same thing, it's just easy to forget:

~~~
ansible-playbook playbook.yml --limit production --ask-become-pass --check --diff
~~~

`--check` simulates the run, `--diff` shows exactly which lines in which files would change. I run this before every production apply, the same way I'd never skip `terraform plan`.

## Security decisions worth knowing about

- The `deploy` user from inventory-api's CI/CD pipeline keeps the narrow, docker only permissions it was given. Hardening runs as a separate user with its own key and sudo access, so the two jobs never overlap.
- Host key checking stays on. The server's key gets added to `known_hosts` once, on purpose, with `ssh-keyscan`, rather than switching the check off in Ansible's config.
- Sudo on production asks for a password every time, typed in by hand, instead of being configured away for convenience.
- UFW rules go in before the firewall turns on, and SSH is allowed first of all, so a run can never lock out the only way back in.

## Running it yourself

You'll need Terraform, Ansible, and the collections pinned in `ansible/requirements.yml`:

~~~
ansible-galaxy collection install -r ansible/requirements.yml
~~~

Copy the production inventory template and fill in your own server:

~~~
cp ansible/inventory.example ansible/inventory/production
~~~

Bring up the test container:

~~~
cd terraform
terraform init
terraform apply
~~~

Generate its inventory entry and run the role against it:

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

One piece of a bigger self study project: inventory-api, monitoring-stack, log-aggregation, this one, and eventually a Kubernetes deployment of inventory-api on top of all of it.