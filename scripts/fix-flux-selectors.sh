#!/bin/bash
set -euo pipefail

echo "🔧 Fixing Flux deployment selector issues..."

# List of Flux deployments that need to be recreated
DEPLOYMENTS=(
    "helm-controller"
    "image-automation-controller"
    "image-reflector-controller"
    "kustomize-controller"
    "notification-controller"
    "source-controller"
)

echo "⚠️  This script will delete and recreate Flux deployments to fix selector issues."
echo "   Flux will be temporarily unavailable during this process."
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Delete the deployments
echo "🗑️  Deleting Flux deployments..."
for deployment in "${DEPLOYMENTS[@]}"; do
    echo "   Deleting $deployment..."
    kubectl delete deployment "$deployment" -n flux-system --ignore-not-found=true
done

echo "⏳ Waiting for deployments to be deleted..."
sleep 5

echo "🔄 Triggering Flux reconciliation..."
flux reconcile source git flux-system
flux reconcile kustomization flux-system --timeout=5m

echo "⏳ Waiting for Flux controllers to be ready..."
kubectl -n flux-system wait --for=condition=ready pod --all --timeout=3m

echo "✅ Fix completed! Checking Flux status..."
flux check