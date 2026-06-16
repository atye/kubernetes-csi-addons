#!/bin/bash

# Cleanup script for VolumeGroupReplication e2e test resources
# This script removes finalizers and deletes all test resources from Kubernetes
# Assumes array resources have already been cleaned up manually

set -e

NAMESPACE="e2e"

echo "=========================================="
echo "Kubernetes Resource Cleanup Script"
echo "=========================================="
echo ""

# Function to patch resources to remove finalizers
patch_finalizers() {
    local resource_type=$1
    local resource_list=$(kubectl get $resource_type -n $NAMESPACE -o name 2>/dev/null || true)
    
    if [ -z "$resource_list" ]; then
        echo "✓ No $resource_type resources found"
        return
    fi
    
    echo "Patching $resource_type resources to remove finalizers..."
    for resource in $resource_list; do
        kubectl patch $resource -n $NAMESPACE -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        echo "  - Patched: $resource"
    done
}

# Function to delete resources
delete_resources() {
    local resource_type=$1
    local count=$(kubectl get $resource_type -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$count" -eq 0 ]; then
        echo "✓ No $resource_type resources to delete"
        return
    fi
    
    echo "Deleting $count $resource_type resource(s)..."
    kubectl delete $resource_type --all -n $NAMESPACE --timeout=10s 2>/dev/null || true
    echo "✓ Deleted $resource_type resources"
}

echo "Step 1: Removing finalizers from VolumeReplication resources..."
patch_finalizers "volumereplication"

echo ""
echo "Step 2: Removing finalizers from VolumeGroupReplication resources..."
patch_finalizers "volumegroupreplication"

echo ""
echo "Step 3: Removing finalizers from VolumeGroupReplicationContent resources..."
patch_finalizers "volumegroupreplicationcontent"

echo ""
echo "Step 4: Removing finalizers from PVCs..."
patch_finalizers "pvc"

echo ""
echo "Step 5: Deleting VolumeReplication resources..."
delete_resources "volumereplication"

echo ""
echo "Step 6: Deleting VolumeGroupReplication resources..."
delete_resources "volumegroupreplication"

echo ""
echo "Step 7: Deleting VolumeGroupReplicationContent resources..."
delete_resources "volumegroupreplicationcontent"

echo ""
echo "Step 8: Deleting PVCs..."
delete_resources "pvc"

echo ""
echo "Step 9: Deleting test VolumeGroupReplicationClass resources (cluster-scoped)..."
vgrc_class_list=$(kubectl get volumegroupreplicationclass --no-headers 2>/dev/null | awk '/^test-/{print $1}' || true)
if [ -z "$vgrc_class_list" ]; then
    echo "✓ No test VolumeGroupReplicationClass resources found"
else
    for vgrc_class in $vgrc_class_list; do
        kubectl delete volumegroupreplicationclass $vgrc_class --timeout=10s 2>/dev/null || true
        echo "  - Deleted: $vgrc_class"
    done
fi

echo ""
echo "Step 10: Deleting test VolumeReplicationClass resources (cluster-scoped)..."
vrc_class_list=$(kubectl get volumereplicationclass --no-headers 2>/dev/null | awk '/^test-/{print $1}' || true)
if [ -z "$vrc_class_list" ]; then
    echo "✓ No test VolumeReplicationClass resources found"
else
    for vrc_class in $vrc_class_list; do
        kubectl delete volumereplicationclass $vrc_class --timeout=10s 2>/dev/null || true
        echo "  - Deleted: $vrc_class"
    done
fi

echo ""
echo "Step 11: Cleaning up Released PVs..."
released_pvs=$(kubectl get pv | grep Released | grep pstore3 | awk '{print $1}' || true)
if [ -z "$released_pvs" ]; then
    echo "✓ No Released PVs found"
else
    echo "Patching and deleting Released PVs..."
    for pv in $released_pvs; do
        kubectl patch pv $pv -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        kubectl delete pv $pv --timeout=10s 2>/dev/null || true
        echo "  - Deleted: $pv"
    done
fi

echo ""
echo "Step 12: Verifying cleanup..."
vr_count=$(kubectl get volumereplication -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
vgr_count=$(kubectl get volumegroupreplication -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
vgrc_count=$(kubectl get volumegroupreplicationcontent -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
pvc_count=$(kubectl get pvc -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")

echo ""
echo "=========================================="
echo "Cleanup Summary:"
echo "=========================================="
echo "VolumeReplication remaining:        $vr_count"
echo "VolumeGroupReplication remaining:   $vgr_count"
echo "VolumeGroupReplicationContent:      $vgrc_count"
echo "PVCs remaining:                     $pvc_count"
echo ""

if [ "$vr_count" -eq 0 ] && [ "$vgr_count" -eq 0 ] && [ "$vgrc_count" -eq 0 ] && [ "$pvc_count" -eq 0 ]; then
    echo "✓ All resources cleaned up successfully!"
    
    # Optional: Delete and recreate namespace for a completely clean state
    if [ "$1" == "--recreate-namespace" ]; then
        echo ""
        echo "Step 13: Recreating namespace for fresh test run..."
        if kubectl get namespace $NAMESPACE &>/dev/null; then
            echo "Deleting namespace $NAMESPACE..."
            kubectl delete namespace $NAMESPACE --timeout=30s 2>/dev/null || true
            echo "Waiting for namespace deletion..."
            sleep 5
        fi
        echo "Creating namespace $NAMESPACE..."
        kubectl create namespace $NAMESPACE 2>/dev/null || echo "Namespace already exists"
        echo "✓ Namespace ready"
    fi
    
    exit 0
else
    echo "⚠ Some resources still remain. You may need to run this script again or check manually."
    exit 1
fi
