# Serveur Minecraft sur AWS

Template CloudFormation (`minecraft.yaml`) qui déploie un petit serveur Minecraft Java (vanilla)
dans son propre VPC, par défaut en `eu-west-3` (Paris) avec le profil AWS `default`.

## Ce qui est créé

- **Réseau** : un VPC dédié (`10.42.0.0/16`), un sous-réseau public, une Internet Gateway,
  un security group qui n'ouvre que le port `25565/tcp`, et une **Elastic IP** (adresse fixe).
- **Serveur** : une instance EC2 Graviton `t4g.medium` (2 vCPU, 4 Go) sous Amazon Linux 2023,
  avec la dernière version de Minecraft et la version de Java qu'elle exige (lue dans les métadonnées Mojang).
  Le heap Java est réglé automatiquement à 75 % de la RAM.
- **Monde** : un volume EBS gp3 chiffré séparé (`/opt/minecraft`), qui survit au remplacement de l'instance,
  avec un **snapshot quotidien** (04:00 UTC, 7 conservés) et un snapshot final si la stack est supprimée.
- **Administration** : pas de SSH ; accès shell via **SSM Session Manager**.

## Déployer

Prérequis : AWS CLI v2 configurée avec le profil `default`.

```bash
./deploy.sh
```

Le script passe `AcceptMinecraftEula=true` : en l'exécutant, vous acceptez le
[CLUF Minecraft](https://aka.ms/MinecraftEULA). D'autres paramètres peuvent être ajoutés :

```bash
./deploy.sh InstanceType=t4g.large Difficulty=hard MaxPlayers=20 AllowedCidr=203.0.113.0/24
```

| Paramètre | Défaut | Rôle |
|---|---|---|
| `InstanceType` | `t4g.medium` | Type d'instance Graviton (arm64) |
| `DataVolumeSize` | `10` | Taille du volume du monde (Go) |
| `BackupRetentionDays` | `7` | Nombre de snapshots quotidiens conservés |
| `AllowedCidr` | `0.0.0.0/0` | IP autorisées sur le port Minecraft |
| `MinecraftVersion` | `latest` | Version du serveur (ex. `1.21.11`) |
| `ServerMotd`, `GameMode`, `Difficulty`, `MaxPlayers` | | Réglages du jeu, appliqués à la première installation uniquement (ensuite : éditer `server.properties`) |

L'installation prend 2 à 3 minutes après la fin du déploiement. L'adresse du serveur est affichée
dans la sortie `ServerAddress`.

## Administrer le serveur

Ouvrir un shell (nécessite le [plugin Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)) :

```bash
aws ssm start-session --target <InstanceId> --region eu-west-3 --profile default
```

Puis, sur le serveur :

```bash
sudo mc-cmd whitelist add MonPseudo   # autoriser un joueur
sudo mc-cmd op MonPseudo              # le passer administrateur
sudo journalctl -u minecraft -f       # suivre la console
sudo systemctl restart minecraft      # redémarrer (le monde est sauvegardé à l'arrêt)
sudo vi /opt/minecraft/server.properties     # puis redémarrer pour appliquer
```

Si un joueur est refusé (« not white-listed »), ajoutez-le avec `whitelist add`, ou désactivez la
whitelist avec `sudo mc-cmd whitelist off`.

Le journal d'installation se trouve dans `/var/log/cloud-init-output.log`.

## Réduire les coûts

En 24 h/24, compter environ 30 $ par mois en `eu-west-3` : l'instance, plus l'Elastic IP
(~3,6 $/mois) et quelques centimes de stockage EBS et de snapshots. Arrêter l'instance quand
personne ne joue réduit la facture à l'IP et au stockage :

```bash
aws ec2 stop-instances  --instance-ids <InstanceId> --region eu-west-3 --profile default
aws ec2 start-instances --instance-ids <InstanceId> --region eu-west-3 --profile default
```

L'adresse IP reste la même et le serveur redémarre tout seul.

## Supprimer

```bash
aws cloudformation delete-stack --stack-name minecraft --region eu-west-3 --profile default
```

Un snapshot final du monde est conservé, ainsi que les derniers snapshots quotidiens
(supprimez-les à la main dans EC2 > Snapshots s'ils ne sont plus utiles).
