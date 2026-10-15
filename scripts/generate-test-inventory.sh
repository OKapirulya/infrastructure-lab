#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
INVENTORY_FILE="${SCRIPT_DIR}/../ansible/inventory/test"

CONTAINER_NAME=$(terraform -chdir="${TERRAFORM_DIR}" output -raw container_name)

cat > "${INVENTORY_FILE}" <<EOF
[test]
${CONTAINER_NAME} ansible_connection=community.docker.docker
EOF

echo "Wrote ${INVENTORY_FILE} (container: ${CONTAINER_NAME})"
