#!/bin/bash
# Libère de l'espace disque sur un nœud k3s (ephemeral-storage pressure)
# À exécuter sur chaque VM : ssh user@node 'sudo bash -s' < clean-node-disk.sh

set -e

echo "=== Avant ==="
df -h /var/lib/rancher
echo ""

echo "Suppression des images containerd non utilisées (k3s)..."
k3s crictl rmi --prune 2>/dev/null || crictl rmi --prune 2>/dev/null || true

echo "Purge des logs journal..."
journalctl --vacuum-size=50M 2>/dev/null || true

echo ""
echo "=== Après ==="
df -h /var/lib/rancher
