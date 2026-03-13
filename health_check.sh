#!/bin/bash
# scripts/health-check.sh — validates your lab environment is ready
#
# Checks:
#   1. Required CLI tools are installed and working
#   2. AWS credentials are valid
#   3. State bucket is reachable
#   4. Terraform can initialise (if environments/dev exists)
#   5. EKS cluster reachable (if kubeconfig is configured)

set -euo pipefail

PASS="[PASS]"
FAIL="[FAIL]"
SKIP="[SKIP]"
WARN="[WARN]"

AWS_REGION="us-east-1"
ERRORS=0

echo "══════════════════════════════════════════════"
echo "  EKS Lab — Environment Health Check"
echo "══════════════════════════════════════════════"
echo ""

# ── Helper ────────────────────────────────────────────────────────────────────
check() {
  local label="$1"
  local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo "$PASS $label"
  else
    echo "$FAIL $label"
    ERRORS=$((ERRORS + 1))
  fi
}

# ── 1. Tool versions ──────────────────────────────────────────────────────────
echo "── Tools ─────────────────────────────────────"
check "aws CLI installed"       "aws --version"
check "terraform installed"     "terraform version"
check "kubectl installed"       "kubectl version --client"
check "helm installed"          "helm version"

# Print actual versions for the record
echo ""
echo "  aws       : $(aws --version 2>&1 | head -1)"
echo "  terraform : $(terraform version -json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)[\"terraform_version\"])' 2>/dev/null || terraform version | head -1)"
echo "  kubectl   : $(kubectl version --client --short 2>/dev/null || kubectl version --client | head -1)"
echo "  helm      : $(helm version --short 2>/dev/null)"
echo ""

# ── 2. AWS credentials ────────────────────────────────────────────────────────
echo "── AWS credentials ───────────────────────────"
if IDENTITY=$(aws sts get-caller-identity 2>/dev/null); then
  ACCOUNT_ID=$(echo "$IDENTITY" | python3 -c 'import sys,json; print(json.load(sys.stdin)["Account"])')
  ARN=$(echo "$IDENTITY"        | python3 -c 'import sys,json; print(json.load(sys.stdin)["Arn"])')
  echo "$PASS Credentials valid"
  echo "  Account : $ACCOUNT_ID"
  echo "  Identity: $ARN"
else
  echo "$FAIL AWS credentials not configured or expired"
  echo "  Run: aws configure  OR  export AWS_PROFILE=<your-profile>"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# ── 3. State bucket reachable ─────────────────────────────────────────────────
echo "── State backend ─────────────────────────────"
if [ -n "${ACCOUNT_ID:-}" ]; then
  BUCKET_NAME="terraform-state-${ACCOUNT_ID}-${AWS_REGION}"
  if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "$PASS S3 state bucket exists: $BUCKET_NAME"
    # Check versioning is on
    VERSIONING=$(aws s3api get-bucket-versioning --bucket "$BUCKET_NAME" --query Status --output text 2>/dev/null)
    if [ "$VERSIONING" = "Enabled" ]; then
      echo "$PASS Versioning enabled"
    else
      echo "$WARN Versioning is NOT enabled on state bucket — run initialize_aws.sh"
    fi
  else
    echo "$FAIL State bucket not found: $BUCKET_NAME"
    echo "  Run: cd bootstrap && bash initialize_aws.sh"
    ERRORS=$((ERRORS + 1))
  fi

  TABLE_NAME="terraform-state-lock"
  if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$AWS_REGION" 2>/dev/null | grep -q ACTIVE; then
    echo "$PASS DynamoDB lock table exists: $TABLE_NAME"
  else
    echo "$FAIL DynamoDB lock table not found"
    echo "  Run: cd bootstrap && bash initialize_aws.sh"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "$SKIP Cannot check bucket — AWS credentials failed above"
fi
echo ""

# ── 4. Terraform init ─────────────────────────────────────────────────────────
echo "── Terraform ─────────────────────────────────"
DEV_DIR="$(dirname "$0")/../environments/dev"
if [ -d "$DEV_DIR" ] && [ -f "$DEV_DIR/backend.tf" ]; then
  # Run terraform validate from the dev dir without printing noisy output
  if (cd "$DEV_DIR" && terraform init -backend=false -no-color 2>&1 | grep -q "Terraform initialized"); then
    echo "$PASS Terraform initialises cleanly"
  else
    echo "$WARN Terraform init needs running: cd environments/dev && terraform init"
  fi
else
  echo "$SKIP No environments/dev found yet — run initialize_aws.sh first"
fi
echo ""

# ── 5. EKS / kubectl ─────────────────────────────────────────────────────────
echo "── EKS cluster ───────────────────────────────"
if kubectl cluster-info 2>/dev/null | grep -q "is running"; then
  echo "$PASS kubectl can reach cluster"
  echo "  $(kubectl cluster-info 2>/dev/null | head -1)"
  NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  echo "$PASS Nodes visible: $NODE_COUNT"
else
  echo "$SKIP No kubeconfig / cluster not yet deployed (expected at this stage)"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════"
if [ "$ERRORS" -eq 0 ]; then
  echo "  All checks passed — lab is ready"
else
  echo "  $ERRORS check(s) failed — see above"
fi
echo "══════════════════════════════════════════════"
exit "$ERRORS"
