#!/bin/bash
# scripts/teardown.sh: v3
# Run from: ../crystal-node/environments/dev
#
# Why this script exists:
# The AWS Load Balancer Controller creates NLBs, ENIs, and security groups
# outside of Terraform state. Terraform can't see or delete them. If they
# exist when terraform destroy runs, the VPC deletion fails with
# DependencyViolation. This script cleans them up first in the correct order.

set -euo pipefail

AWS_REGION="us-east-1"
MAX_WAIT=300  # 5 minutes max wait for any single condition
POLL_INTERVAL=15

# Timeout-aware wait function
# Usage: wait_for "description" "command that returns empty when done"
wait_for() {
  local description=$1
  local check_cmd=$2
  local elapsed=0

  echo "  Waiting for: $description (max ${MAX_WAIT}s)"

  while true; do
    local result
    result=$(eval "$check_cmd" 2>/dev/null || echo "")

    if [ -z "$result" ]; then
      echo "  Done: $description"
      return 0
    fi

    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
      echo "  TIMEOUT: $description still not complete after ${MAX_WAIT}s"
      echo "  Last result: $result"
      echo "  Continuing anyway... terraform destroy may fail"
      return 1
    fi

    echo "  Still waiting ($elapsed s): $result"
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done
}

echo "--- crystal-node teardown ---"

# Step 1: Remove ArgoCD application finalizers
# ArgoCD adds finalizers to apps and namespaces. If ArgoCD is destroyed
# before finalizers are removed, Kubernetes waits forever for cleanup
# that will never happen... causing context deadline exceeded errors.
echo "[1/7] Removing ArgoCD application finalizers..."
for app in crystal-app fit-link; do
  kubectl patch application "$app" -n argocd \
    -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
done
kubectl delete application crystal-app fit-link \
  -n argocd --ignore-not-found 2>/dev/null || true
sleep 5

# Step 2: Remove namespace finalizers
# ArgoCD also adds finalizers to namespaces it manages.
echo "[2/7] Removing namespace finalizers..."
for ns in crystal-app fit-link monitoring amazon-cloudwatch argocd; do
  kubectl patch namespace "$ns" \
    -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
done

# Step 3: Delete Kubernetes services
# Deleting the Service with type LoadBalancer triggers the LB Controller
# to start deprovisioning the NLB in AWS. Must happen before we wait
# for NLBs to be gone, otherwise they never start deprovisioning.
echo "[3/7] Deleting Kubernetes services..."
kubectl delete svc crystal-app -n crystal-app 2>/dev/null || true
kubectl delete svc fit-link -n fit-link 2>/dev/null || true

# Step 4: Empty ECR repositories
# Even with force_delete = true in Terraform, emptying manually avoids
# the RepositoryNotEmptyException if force_delete wasn't in the deployed state.
echo "[4/7] Emptying ECR repositories..."
for repo in crystal-app fit-link; do
  IMAGES=$(aws ecr list-images \
    --repository-name "$repo" \
    --region "$AWS_REGION" \
    --query 'imageIds' \
    --output json 2>/dev/null || echo "[]")
  if [ "$IMAGES" != "[]" ] && [ -n "$IMAGES" ]; then
    aws ecr batch-delete-image \
      --repository-name "$repo" \
      --image-ids "$IMAGES" \
      --region "$AWS_REGION" 2>/dev/null && echo "  Emptied: $repo" || true
  fi
done

# Step 5: Wait for NLBs to be fully deleted
# The LB Controller deletes NLBs asynchronously after the Service is deleted.
# We must wait until AWS confirms they are gone before proceeding.
# Leftover NLBs leave ENIs attached to subnets which block VPC deletion.
echo "[5/7] Waiting for NLBs to deprovision..."
wait_for "NLBs to be deleted" \
  "aws elbv2 describe-load-balancers \
    --region $AWS_REGION \
    --query 'LoadBalancers[?contains(LoadBalancerName,\`crystal-app-nlb\`) || contains(LoadBalancerName,\`fit-link-nlb\`)].LoadBalancerName' \
    --output text" || true

# Step 6: Delete leftover k8s security groups
# The LB Controller creates security groups for NLBs that are not tracked
# by Terraform. They must be deleted before the VPC can be destroyed.
# We identify them by the k8s- prefix in their name.
echo "[6/7] Cleaning up leftover security groups..."
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")

if [ -n "$VPC_ID" ]; then
  SGS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region "$AWS_REGION" \
    --query 'SecurityGroups[?starts_with(GroupName,`k8s-`)].GroupId' \
    --output text 2>/dev/null || echo "")

  if [ -n "$SGS" ]; then
    for sg in $SGS; do
      # Retry deletion, sometimes ENIs take a moment to detach after NLB deletion
      for attempt in 1 2 3; do
        if aws ec2 delete-security-group \
          --group-id "$sg" \
          --region "$AWS_REGION" 2>/dev/null; then
          echo "  Deleted: $sg"
          break
        else
          if [ "$attempt" -lt 3 ]; then
            echo "  Retry $attempt for $sg, waiting 10s..."
            sleep 10
          else
            echo "  Could not delete $sg after 3 attempts... terraform may fail on VPC deletion"
          fi
        fi
      done
    done
  else
    echo "  No leftover security groups found"
  fi
else
  echo "  Could not get VPC ID... skipping security group cleanup"
fi

# Step 7: Terraform destroy
echo "[7/7] Running terraform destroy..."
terraform destroy

echo ""
echo "--- teardown complete ---"