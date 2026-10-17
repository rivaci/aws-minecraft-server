#!/bin/bash
# Deploie (ou met a jour) le serveur Minecraft, puis attend la fin de l'installation sur l'instance.
# Usage : ./deploy.sh [Parametre=Valeur ...]   ex : ./deploy.sh InstanceType=t4g.large
set -euo pipefail

STACK_NAME=${STACK_NAME:-minecraft}
export AWS_PROFILE=${AWS_PROFILE:-default}
export AWS_REGION=${AWS_REGION:-eu-west-3}

cd "$(dirname "$0")"

# Sortie texte de l'AWS CLI, sans les retours chariot qu'ajoute la version Windows
aws_text() {
  aws "$@" --output text | tr -d '\r'
}

output() {
  aws_text cloudformation describe-stacks --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" 2>/dev/null || true
}

# Derniere execution de l'association d'installation : "<id> <statut>"
latest_execution() {
  [ -n "$ASSOCIATION" ] && [ "$ASSOCIATION" != "None" ] || return 0
  aws_text ssm describe-association-executions --association-id "$ASSOCIATION" \
    --query 'AssociationExecutions[].[CreatedTime,ExecutionId,Status]' | sort | tail -n 1 | cut -f2,3
}

# Mot de passe de la page de demarrage/arret : demande une seule fois, CloudFormation le conserve ensuite
PARAMS=(AcceptMinecraftEula=true)
if [[ " $* " != *" ControlPassword="* ]] && ! aws_text cloudformation describe-stacks --stack-name "$STACK_NAME" \
    --query "Stacks[0].Parameters[].ParameterKey" 2>/dev/null | grep -qw ControlPassword; then
  read -rsp "Mot de passe de la page de demarrage/arret (8 caracteres minimum) : " PASSWORD
  echo
  PARAMS+=("ControlPassword=$PASSWORD")
fi

ASSOCIATION=$(output SetupAssociationId)
BEFORE=$(latest_execution | cut -f1)

aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file minecraft.yaml \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides "${PARAMS[@]}" "$@"

# L'installation sur l'instance est faite par une association SSM, apres la mise a jour de la stack.
# On attend la nouvelle execution, ou a defaut (rien a mettre a jour) on rapporte l'etat de la precedente.
ASSOCIATION=$(output SetupAssociationId)
INSTANCE_ID=$(output InstanceId)
echo "Installation sur le serveur en cours (jusqu'a une dizaine de minutes la premiere fois)..."
EXEC=""
STATUS=""
for i in $(seq 1 120); do
  read -r EXEC STATUS < <(latest_execution) || true
  if [ -n "$EXEC" ] && { [ "$EXEC" != "$BEFORE" ] || [ "$i" -ge 6 ]; } \
    && [ "$STATUS" != "Pending" ] && [ "$STATUS" != "InProgress" ]; then
    break
  fi
  sleep 10
done

if [ "$STATUS" != "Success" ]; then
  echo "L'installation a echoue ou n'est pas terminee (statut : ${STATUS:-inconnu})." >&2
  if [ -n "$EXEC" ]; then
    COMMAND_ID=$(aws_text ssm describe-association-execution-targets --association-id "$ASSOCIATION" --execution-id "$EXEC" \
      --query 'AssociationExecutionTargets[0].OutputSource.OutputSourceId' || true)
    aws_text ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
      --query StandardOutputContent 2>/dev/null | tail -n 30 >&2 || true
  fi
  echo "Journal complet : ./admin.sh journal ; pour relancer l'installation : ./admin.sh reinstaller" >&2
  exit 1
fi

echo "Serveur pret."
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' \
  --output table
