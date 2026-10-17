# Serveur Minecraft sur AWS

Template CloudFormation (`minecraft.yaml`) qui déploie un serveur Minecraft Java dans son propre VPC,
par défaut en `eu-west-3` (Paris) avec le profil AWS `default`. Il comprend :

- un **panneau d'administration [Crafty Controller](https://craftycontrol.com)** pour gérer les mondes,
  les joueurs, la console, les fichiers et les sauvegardes depuis le navigateur ;
- une **page web de démarrage/arrêt**, protégée par mot de passe, à partager avec les joueurs pour
  qu'ils allument le serveur eux-mêmes.

## Ce qui est créé

- **Réseau** : un VPC dédié, un sous-réseau public, et un security group qui n'ouvre que les ports
  Minecraft `25565-25570/tcp` (un par monde lancé en même temps). Une **Elastic IP** donne une adresse fixe.
- **Serveur** : une instance EC2 Graviton `t4g.medium` (2 vCPU, 4 Go) sous Amazon Linux 2023.
  Crafty y tourne dans un conteneur Docker qui contient Java 8, 11, 17, 21 et 25.
- **Mondes** : un volume EBS gp3 chiffré séparé (`/opt/minecraft`), qui survit au remplacement de l'instance,
  avec un **snapshot quotidien** (04:00 UTC, 7 conservés) et un snapshot final si la stack est supprimée.
- **Page de démarrage/arrêt** : une fonction Lambda avec une URL publique. Elle affiche l'état du serveur
  et le nombre de joueurs connectés.
- **Administration** : pas de SSH ni de port d'administration ouvert. Le panneau Crafty et le terminal
  passent par **SSM Session Manager**.

L'installation sur l'instance n'est pas dans le UserData : c'est un document SSM, appliqué à la création
et à chaque mise à jour de la stack. Le script (`/usr/local/sbin/minecraft-setup`) peut être relancé
sans risque, et son journal est dans `/var/log/minecraft-setup.log`.

## Prérequis

- AWS CLI v2 configurée avec le profil `default`.
- Le [plugin Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
  pour le panneau Crafty et le terminal.
- Un terminal bash (sous Windows : WSL ou Git Bash).

## Déployer ou mettre à jour

```bash
./deploy.sh
```

Au premier lancement, le script demande le mot de passe de la page de démarrage/arrêt ; CloudFormation
le conserve ensuite. Il passe aussi `AcceptMinecraftEula=true` : en l'exécutant, vous acceptez le
[CLUF Minecraft](https://aka.ms/MinecraftEULA). Il attend la fin de l'installation sur le serveur
(jusqu'à une dizaine de minutes la première fois), puis affiche les adresses utiles.

**Depuis la version sans Crafty**, la mise à jour redémarre l'instance, arrête l'ancien service, puis importe
le monde existant dans Crafty sous le nom « Monde principal ». Le monde, les ops, la whitelist et
`server.properties` sont repris. Une copie des anciens fichiers reste dans `/opt/minecraft/serveur-avant-crafty`,
à supprimer quand tout va bien.

Paramètres utiles :

```bash
./deploy.sh InstanceType=t4g.large AllowedCidr=203.0.113.0/24
./deploy.sh ControlPassword=nouveau-mot-de-passe
```

| Paramètre | Défaut | Rôle |
|---|---|---|
| `ControlPassword` | (demandé) | Mot de passe de la page de démarrage/arrêt |
| `InstanceType` | `t4g.medium` | Type d'instance Graviton (arm64) |
| `DataVolumeSize` | `10` | Taille du volume des mondes et des sauvegardes Crafty (Go, augmentable) |
| `BackupRetentionDays` | `7` | Nombre de snapshots quotidiens conservés |
| `AllowedCidr` | `0.0.0.0/0` | IP autorisées sur les ports Minecraft |
| `CraftyVersion` | `4.11.0` | Version de Crafty Controller |
| `MinecraftVersion`, `ServerMotd`, `GameMode`, `Difficulty`, `MaxPlayers` | | Réglages du premier monde, à la toute première installation |

## Page de démarrage/arrêt

```bash
./admin.sh page
```

Affiche l'adresse de la page (`https://….lambda-url.eu-west-3.on.aws/`). Les joueurs y voient l'état du serveur
et le nombre de connectés ; avec le mot de passe, ils peuvent l'allumer ou l'éteindre. Après un démarrage,
Minecraft met 1 à 2 minutes à être prêt. Les mondes sont sauvegardés proprement à l'arrêt.

## Panneau Crafty

```bash
./admin.sh identifiants   # identifiants créés à l'installation (à changer dès la première connexion)
./admin.sh recuperer      # mot de passe perdu : compte de secours Crafty valable 1 heure
./admin.sh panneau        # ouvre le tunnel, laisser le terminal ouvert
```

Puis ouvrir **https://localhost:8443** et accepter l'avertissement de certificat (il est auto-signé, et le
trafic passe de toute façon dans le tunnel chiffré SSM).

Dans Crafty :

- **Joueurs** : onglet *Players* du serveur (whitelist, op, ban), ou commandes dans l'onglet *Terminal*
  (`whitelist add Pseudo`, `op Pseudo`).
- **Réglages** : onglet *Files* pour modifier `server.properties`, puis redémarrer le serveur.
- **Sauvegardes** : onglet *Backups*, avec planification possible. Elles sont stockées sur le volume des mondes,
  donc à limiter en nombre (le volume peut être agrandi avec `DataVolumeSize`).
- **Nouveaux mondes** : *Create New Server*. Choisir un port libre entre 25565 et 25570, puis dans l'onglet
  *Config*, choisir la version de Java demandée par la version de Minecraft (*Override current Java Version* :
  Java 25 pour les versions 26.x, Java 21 pour 1.20.5 à 1.21.x). Avec 4 Go de RAM, mieux vaut ne lancer
  qu'un monde à la fois (arrêter l'un, démarrer l'autre).

La mémoire du « Monde principal » est réglée à 60 % de la RAM de l'instance. Après un changement de type
d'instance, ajuster `-Xms`/`-Xmx` dans *Config > Server Execution Command*.

## Icône et message du serveur

`assets/server-icon.png` est l'icône du serveur (PNG 64×64) et `assets/motd.txt` contient la ligne `motd=`
correspondante, avec les codes couleur Minecraft. Pour les appliquer à un monde, dans Crafty :

1. onglet *Files* du monde : téléverser `server-icon.png` à la racine (à côté de `server.properties`) ;
2. ouvrir `server.properties` et remplacer la ligne `motd=` par celle de `assets/motd.txt` ;
3. redémarrer le monde.

## Autres commandes

```bash
./admin.sh demarrer   # allumer le serveur
./admin.sh arreter    # éteindre le serveur
./admin.sh shell      # terminal sur le serveur
./admin.sh journal    # fin du journal d'installation
./admin.sh reinstaller  # relancer l'installation sur le serveur (après un échec)
```

## Coûts

En 24 h/24, compter environ 30 $ par mois en `eu-west-3` : l'instance, plus l'Elastic IP (~3,6 $/mois)
et quelques centimes de stockage EBS et de snapshots. La fonction Lambda reste dans l'offre gratuite.
Éteindre le serveur quand personne ne joue réduit la facture à l'IP et au stockage.

## Supprimer

```bash
aws cloudformation delete-stack --stack-name minecraft --region eu-west-3 --profile default
```

Un snapshot final du volume des mondes est conservé, ainsi que les derniers snapshots quotidiens
(supprimez-les à la main dans EC2 > Snapshots s'ils ne sont plus utiles).
