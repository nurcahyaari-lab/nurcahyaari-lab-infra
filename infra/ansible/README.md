# Ansible

Configures the VMs that Terraform (`infra/`) creates. Terraform makes the machines;
Ansible decides what is set up on them.

## Layout

| Path | What goes there |
| --- | --- |
| `inventory/hosts.ini` | **Which** machines exist and their groups. Only names, IPs, groups. |
| `inventory/group_vars/<group>.yaml` | Settings for every machine in that group (`all.yaml` = everyone). |
| `roles/<role>/` | **How** to do one job. Reusable building block. |
| `playbooks/<name>.yaml` | **What** to apply **where**: maps inventory groups to roles. |
| `playbooks/site.yaml` | Runs every playbook in order. |
| `ansible.cfg` | Defaults so commands work without flags. Run everything from this folder. |

Roles:

| Role | Runs on | Does |
| --- | --- | --- |
| `common` | all | hostname, `/etc/hosts` listing every machine |

## Usage

```sh
brew install ansible
cd ansible

ansible all -m ping                           # can Ansible reach every machine?
ansible-playbook playbooks/site.yaml --check --diff  # preview changes
ansible-playbook playbooks/site.yaml          # apply
ansible-playbook playbooks/site.yaml --limit k8s-cp  # only one machine
```

## Adding things

- **A machine:** add it to `infra/terraform/terraform.tfvars`, `terraform apply`, then add it to
  `inventory/hosts.ini` under the right group and run `playbooks/site.yaml`.
- **A new job** (e.g. Kubernetes):
  1. `roles/<name>/tasks/main.yaml` with the steps (plus `handlers/`, `templates/`, `defaults/` if needed).
  2. `playbooks/<name>.yaml` mapping a group to the role, e.g. `hosts: k8s`.
  3. `inventory/group_vars/<group>.yaml` for its settings, e.g. the Kubernetes version.
  4. Import the playbook in `playbooks/site.yaml`.
