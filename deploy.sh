#!/bin/bash
# Deploie (ou met a jour) le serveur Minecraft.
# Usage : ./deploy.sh [Parametre=Valeur ...]   ex : ./deploy.sh InstanceType=t4g.large
set -euo pipefail

STACK_NAME=${STACK_NAME:-minecraft}
export AWS_PROFILE=${AWS_PROFILE:-default}
export AWS_REGION=${AWS_REGION:-eu-west-3}

cd "$(dirname "$0")"

aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file minecraft.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides AcceptMinecraftEula=true "$@"

aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' \
  --output table
