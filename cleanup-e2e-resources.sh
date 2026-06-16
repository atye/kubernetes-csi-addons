#!/bin/bash
# Cleanup script for E2E test resources
# This script deletes resources in the correct order to allow proper cleanup on the PowerStore array
# WITHOUT removing finalizers, so controllers can properly clean up backend resources

set -e

TIMEOUT_OPERATION="10m"
TIMEOUT_DELETE="15m"

echo "=== Cleaning up E2E test resources (with proper array cleanup) ==="
echo "Operation timeout: $TIMEOUT_OPERATION"
echo "Delete timeout: $TIMEOUT_DELETE"
echo ""

# Helper function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local namespace=$2
    local timeout=$3
    
    echo "  Waiting for $resource_type to be deleted (timeout: $timeout)..."
    local end_time=$((SECONDS + $(echo $timeout | sed 's/m/*60/;s/s//;s/h/*3600/' | bc)))
    
    while [ $SECONDS -lt $end_time ]; do
        if [ -n "$namespace" ]; then
            count=$(kubectl get $resource_type -n $namespace --no-headers 2>/dev/null | wc -l)
        else
            count=$(kubectl get $resource_type --no-headers 2>/dev/null | wc -l)
        fi
        
        if [ "$count" -eq 0 ]; then
            echo "  ✓ All $resource_type deleted"
            return 0
        fi
        
        echo "  Still waiting for $count $resource_type to be deleted..."
        sleep 10
    done
    
    echo "  ⚠ Timeout waiting for $resource_type deletion"
    return 1
}

# 1. Delete VolumeGroupReplications first (this will trigger VR deletion via owner references)
echo "Step 1: Deleting VolumeGroupReplications in e2e namespace..."
if kubectl get volumegroupreplication -n e2e --no-headers 2>/dev/null | grep -q .; then
    kubectl delete volumegroupreplication -n e2e --all --timeout=$TIMEOUT_DELETE 2>&1 || {
        echo "  ⚠ VGR deletion timed out or failed"
        echo "  Checking for stuck VGRs..."
        kubectl get volumegroupreplication -n e2e -o wide 2>/dev/null || true
    }
    wait_for_deletion "volumegroupreplication" "e2e" "$TIMEOUT_DELETE" || {
        echo "  ⚠ Some VGRs still remain, checking status..."
        kubectl get volumegroupreplication -n e2e -o yaml 2>/dev/null | grep -A 5 "status:" || true
    }
else
    echo "  No VolumeGroupReplications found"
fi
echo ""

# 2. Delete any remaining VolumeReplications (should be auto-deleted by VGR, but check)
echo "Step 2: Deleting any remaining VolumeReplications in e2e namespace..."
if kubectl get volumereplication -n e2e --no-headers 2>/dev/null | grep -q .; then
    kubectl delete volumereplication -n e2e --all --timeout=$TIMEOUT_DELETE 2>&1 || {
        echo "  ⚠ VR deletion timed out or failed"
    }
    wait_for_deletion "volumereplication" "e2e" "$TIMEOUT_DELETE" || true
else
    echo "  No VolumeReplications found"
fi
echo ""

# 3. Delete PVCs (this will trigger PV deletion)
echo "Step 3: Deleting PVCs in e2e namespace..."
if kubectl get pvc -n e2e --no-headers 2>/dev/null | grep -q .; then
    kubectl delete pvc -n e2e --all --timeout=$TIMEOUT_DELETE 2>&1 || {
        echo "  ⚠ PVC deletion timed out or failed"
    }
    wait_for_deletion "pvc" "e2e" "$TIMEOUT_DELETE" || true
else
    echo "  No PVCs found"
fi
echo ""

# 4. Delete VolumeGroupReplicationContents (cluster-scoped)
echo "Step 4: Deleting VolumeGroupReplicationContents..."
if kubectl get volumegroupreplicationcontent --no-headers 2>/dev/null | grep -q .; then
    kubectl delete volumegroupreplicationcontent --all --timeout=$TIMEOUT_DELETE 2>&1 || {
        echo "  ⚠ VGRContent deletion timed out or failed"
    }
    wait_for_deletion "volumegroupreplicationcontent" "" "$TIMEOUT_DELETE" || true
else
    echo "  No VolumeGroupReplicationContents found"
fi
echo ""

# 5. Delete VolumeGroupReplicationClasses
echo "Step 5: Deleting VolumeGroupReplicationClasses..."
kubectl delete volumegroupreplicationclass --all --timeout=30s 2>&1 || true
echo ""

# 6. Delete VolumeReplicationClasses
echo "Step 6: Deleting VolumeReplicationClasses..."
kubectl delete volumereplicationclass --all --timeout=30s 2>&1 || true
echo ""

# 7. Delete the e2e namespace (should be clean now)
echo "Step 7: Deleting e2e namespace..."
if kubectl get ns e2e 2>/dev/null; then
    kubectl delete ns e2e --timeout=2m 2>&1 || {
        echo "  ⚠ Namespace deletion timed out"
        echo "  Checking for remaining resources..."
        kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n e2e 2>/dev/null || true
    }
    
    # Wait for namespace deletion
    echo "  Waiting for namespace deletion..."
    for i in {1..60}; do
        if ! kubectl get ns e2e 2>/dev/null; then
            echo "  ✓ e2e namespace successfully deleted"
            break
        fi
        if [ $i -eq 60 ]; then
            echo "  ⚠ Namespace still exists after 2 minutes"
            echo "  You may need to manually investigate stuck resources"
        fi
        sleep 2
    done
else
    echo "  e2e namespace does not exist"
fi
echo ""

echo "=== Cleanup Summary ==="
echo "VolumeGroupReplicationClasses:"
kubectl get volumegroupreplicationclass 2>&1 || echo "  None found ✓"
echo ""
echo "VolumeReplicationClasses:"
kubectl get volumereplicationclass 2>&1 || echo "  None found ✓"
echo ""
echo "VolumeGroupReplicationContents:"
kubectl get volumegroupreplicationcontent 2>&1 || echo "  None found ✓"
echo ""
echo "e2e namespace:"
kubectl get ns e2e 2>&1 || echo "  Not found ✓"
echo ""

# Check for any remaining PVs that might be stuck
echo "Checking for stuck PVs from e2e tests..."
kubectl get pv | grep -E "e2e|test-" || echo "  No test PVs found ✓"
echo ""

echo "=== Cleanup complete! ==="
echo ""
echo "Note: If resources are still stuck, check the controller logs:"
echo "  kubectl logs -n csi-addons-system -l app.kubernetes.io/name=csi-addons --tail=100"
echo "  kubectl logs -n powerstore -l app=csi-powerstore-controller --tail=100"
