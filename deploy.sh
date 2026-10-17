#!/bin/bash
# Deploie (ou met a jour) le serveur Minecraft, puis attend la fin de l'installation sur l'instance.
# Usage : ./deploy.sh [Parametre=Valeur ...]   ex : ./deploy.sh InstanceType=t4g.large
set -euo pipefail

STACK_NAME=${STACK_NAME:-minecraft}
export AWS_PROFILE=${AWS_PROFILE:-default}
export AWS_REGION=${AWS_REGION:-eu-west-3}

cd "$(dirname "$0")"

output() {
  aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text 2>/dev/null || true
}

executions() {
  [ -n "$1" ] && [ "$1" != "None" ] || return 0
  aws ssm describe-association-executions --association-id "$1" \
    --query 'AssociationExecutions[].[ExecutionId,Status]' --output text
}

# Mot de passe de la page de demarrage/arret : demande une seule fois, CloudFormation le conserve ensuite
PARAMS=(AcceptMinecraftEula=true)
if [[ " $* " != *" ControlPassword="* ]] && ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
    --query "Stacks[0].Parameters[].ParameterKey" --output text 2>/dev/null | grep -qw ControlPassword; then
  read -rsp "Mot de passe de la page de demarrage/arret (8 caracteres minimum) : " PASSWORD
  echo
  PARAMS+=("ControlPassword=$PASSWORD")
fi

ASSOCIATION=$(output SetupAssociationId)
BEFORE=$(executions "$ASSOCIATION" | cut -f1)

aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file minecraft.yaml \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides "${PARAMS[@]}" "$@"

# L'installation sur l'instance est faite par une association SSM, apres la mise a jour de la stack
ASSOCIATION=$(output SetupAssociationId)
INSTANCE_ID=$(output InstanceId)
echo "Installation sur le serveur en cours (jusqu'a une dizaine de minutes la premiere fois)..."
STATUS=""
for i in $(seq 1 120); do
  while read -r EXEC STATUS; do
    grep -qx "$EXEC" <<<"$BEFORE" || break
    EXEC=""
  done < <(executions "$ASSOCIATION")
  if [ -z "$EXEC" ] && [ "$i" -ge 6 ]; then
    echo "Rien a installer : le serveur etait deja a jour."
    STATUS=Success
    break
  fi
  [ -n "$EXEC" ] && [ "$STATUS" != "Pending" ] && [ "$STATUS" != "InProgress" ] && break
  sleep 10
done

if [ "$STATUS" != "Success" ]; then
  echo "L'installation a echoue ou n'est pas terminee (statut : ${STATUS:-inconnu})." >&2
  if [ -n "${EXEC:-}" ]; then
    COMMAND_ID=$(aws ssm describe-association-execution-targets --association-id "$ASSOCIATION" --execution-id "$EXEC" \
      --query 'AssociationExecutionTargets[0].OutputSource.OutputSourceId' --output text)
    aws ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
      --query StandardOutputContent --output text | tail -n 30 >&2 || true
  fi
  echo "Journal complet : ./admin.sh journal ; pour relancer l'installation : ./admin.sh reinstaller" >&2
  exit 1
fi

echo "Serveur pret."
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' \
  --output table
