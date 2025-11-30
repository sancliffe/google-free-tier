#!/bin/bash
# scripts/integration-test.sh
set -euo pipefail

VM_IP=$(terraform output -raw instance_public_ip)
DOMAIN=$(terraform output -raw domain_name)

# Test VM health
if ! curl -f -s "http://${VM_IP}" > /dev/null; then
    echo "ERROR: VM health check failed"
    exit 1
fi

# Test SSL
if ! curl -f -s "https://${DOMAIN}" > /dev/null; then
    echo "ERROR: SSL health check failed"
    exit 1
fi

# Test Firestore connectivity
COUNTER=$(curl -s "https://${DOMAIN}" | grep -oP 'Visitor Count: <strong>\K[0-9]+')
if [[ -z "${COUNTER}" ]]; then
    echo "ERROR: Firestore integration failed"
    exit 1
fi

echo "✓ All integration tests passed"
