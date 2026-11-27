#!/usr/bin/env bash
# Prints the playbooks affected by the changes between two commits, one per line,
# in the same order as playbooks/site.yaml. Run it from the ansible/ directory:
#
#   ../.github/scripts/ansible-changed-playbooks.sh <base-sha> <head-sha>
#
# How a changed file maps to playbooks:
#   playbooks/<name>.yaml        -> that playbook (site.yaml -> everything)
#   roles/<role>/...             -> every playbook that lists the role
#   inventory/group_vars/<group> -> every playbook whose hosts include that group (or all)
#   *.md                         -> nothing
#   anything else                -> site.yaml (inventory, ansible.cfg, requirements, ...)
#
# Prints site.yaml if the commits can't be compared (first push, force-push).
# Prints nothing if no ansible files changed.
set -euo pipefail

base=$1
head=$2

everything() {
  echo site.yaml
  exit 0
}

if [[ $base =~ ^0+$ ]] || ! changed=$(git diff --name-only --relative "$base" "$head" 2>/dev/null); then
  everything
fi

want=""
add() {
  local p
  for p in "$@"; do
    p=${p#playbooks/}
    [[ $p == site.yaml ]] && continue
    want+="$p"$'\n'
  done
}

# Word boundary that works in both GNU and BSD grep -E.
b_start='(^|[^[:alnum:]_-])'
b_end='([^[:alnum:]_-]|$)'

while IFS= read -r f; do
  [[ -z $f ]] && continue
  case $f in
    playbooks/site.yaml)
      everything
      ;;
    playbooks/*.yaml)
      add "$f"
      ;;
    roles/*)
      role=${f#roles/}
      role=${role%%/*}
      # shellcheck disable=SC2046
      add $(grep -lE "^[[:space:]]*-[[:space:]]*${role}[[:space:]]*$" playbooks/*.yaml || true)
      ;;
    inventory/group_vars/*)
      group=${f#inventory/group_vars/}
      group=${group%%/*}
      group=${group%.yaml}
      group=${group%.yml}
      [[ $group == all ]] && everything
      # shellcheck disable=SC2046
      add $(grep -lE "^[[:space:]]*hosts:.*${b_start}(${group}|all)${b_end}" playbooks/*.yaml || true)
      ;;
    *.md)
      ;;
    *)
      everything
      ;;
  esac
done <<<"$changed"

[[ -z $want ]] && exit 0

# Print in site.yaml order, then any playbook that isn't imported by site.yaml.
ordered=$(sed -nE 's/.*import_playbook:[[:space:]]*([^[:space:]]+).*/\1/p' playbooks/site.yaml)
{
  printf '%s\n' "$ordered" | grep -xF -f <(printf '%s' "$want") || true
  printf '%s' "$want" | grep -vxF -f <(printf '%s\n' "$ordered") || true
} | awk 'NF && !seen[$0]++'
