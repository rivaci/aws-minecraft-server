#!/bin/bash
# Raccourcis d'administration du serveur Minecraft. Usage : ./admin.sh <commande>
#   panneau       ouvre un tunnel vers le panneau Crafty : https://localhost:8443
#   identifiants  affiche les identifiants Crafty crees a l'installation
#   demarrer      allume le serveur
#   arreter       eteint le serveur (les mondes sont sauvegardes)
#   page          affiche l'adresse de la page de demarrage/arret
#   journal       affiche la fin du journal d'installation
#   reinstaller   relance l'installation sur le serveur (apres un echec)
#   shell         ouvre un terminal sur le serveur
set -euo pipefail

STACK_NAME=${STACK_NAME:-minecraft}
LOCAL_PORT=${LOCAL_PORT:-8443}
export AWS_PROFILE=${AWS_PROFILE:-default}
export AWS_REGION=${AWS_REGION:-eu-west-3}

output() {
  aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

# Execute une commande sur le serveur via SSM et affiche sa sortie
remote() {
  local command_id
  command_id=$(aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name AWS-RunShellScript \
    --parameters "{\"commands\":[\"$1\"]}" --query Command.CommandId --output text)
  aws ssm wait command-executed --command-id "$command_id" --instance-id "$INSTANCE_ID" || true
  aws ssm get-command-invocation --command-id "$command_id" --instance-id "$INSTANCE_ID" \
    --query StandardOutputContent --output text
}

case "${1:-}" in
  panneau | identifiants | demarrer | arreter | page | journal | reinstaller | shell) ;;
  *)
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac

INSTANCE_ID=$(output InstanceId)

case "$1" in
  panneau)
    echo "Panneau Crafty : https://localhost:$LOCAL_PORT (certificat auto-signe : accepter l'avertissement)"
    echo "Laisser ce terminal ouvert, Ctrl+C pour fermer le tunnel."
    aws ssm start-session --target "$INSTANCE_ID" --document-name AWS-StartPortForwardingSession \
      --parameters "{\"portNumber\":[\"8443\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}"
    ;;
  identifiants) remote "/usr/local/bin/crafty-password" ;;
  demarrer) aws ec2 start-instances --instance-ids "$INSTANCE_ID" --query 'StartingInstances[0].CurrentState.Name' --output text ;;
  arreter) aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --query 'StoppingInstances[0].CurrentState.Name' --output text ;;
  page) output ControlPageUrl ;;
  journal) remote "tail -n 50 /var/log/minecraft-setup.log" ;;
  reinstaller) aws ssm start-associations-once --association-ids "$(output SetupAssociationId)" && echo "Relance ; suivre avec ./admin.sh journal" ;;
  shell) aws ssm start-session --target "$INSTANCE_ID" ;;
esac
