#!/usr/bin/env bash
# ci/infra.sh plan|apply — OpenTofu against the R2 state backend.
# Needs CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, AWS_ACCESS_KEY_ID,
# AWS_SECRET_ACCESS_KEY (R2 state token), TF_VAR_account_id,
# TF_VAR_state_passphrase. Fails loudly when any is missing: a skipped plan
# must never look like a passing one.
set -euo pipefail
mode="${1:?usage: ci/infra.sh plan|apply}"
for v in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TF_VAR_account_id TF_VAR_state_passphrase; do
  [ -n "${!v:-}" ] || { echo "::error::$v is not set (infra/README.md \"Bootstrap\")"; exit 1; }
done
cd "$(dirname "$0")/../infra"
rm -rf .terraform
tofu init -input=false -backend-config="endpoints={s3=\"https://${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com\"}"
tofu plan -input=false -lock-timeout=5m -out=tfplan
case "$mode" in
  plan) ;;
  apply) tofu apply -input=false -lock-timeout=5m tfplan ;;
  *) echo "unknown mode $mode" >&2; exit 2 ;;
esac
