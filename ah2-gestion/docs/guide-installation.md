# Guide d'installation, AH2 Gestion

## 1. Ce qu'il faut

- **Un PC central** sous Windows 10 ou 11 : le PC du comptable ou un PC dédié. Il contient la base de référence.
- **Un routeur Wi-Fi** pour la structure. Internet n'est **pas** nécessaire.
- Les **autres PC** et les **téléphones Android** (Android 8 ou plus récent).
- **Un disque externe ou une clé USB** pour les sauvegardes quotidiennes.
- Une imprimante A4. En option : une imprimante ticket 80 mm, Bluetooth ou Wi-Fi.

## 2. Réseau Wi-Fi local

1. Branchez le routeur et donnez un nom au réseau (par exemple `AH2-STRUCTURE`) avec un mot de passe WPA2 solide.
2. Dans l'interface du routeur, **réservez une adresse IP fixe** pour le PC central (par exemple `192.168.1.10`). Les téléphones le retrouveront ainsi toujours à la même adresse.
3. Au premier lancement, le pare-feu Windows demande l'autorisation pour AH2 Gestion. Autorisez-la sur les **réseaux privés** : c'est le port local 8765 qui reçoit les synchronisations.

Les échanges sont **chiffrés** (AES-256) avec une clé propre à chaque appareil. Une personne connectée au Wi-Fi sans cette clé ne peut ni lire ni envoyer de données.

## 3. Installer le PC central

1. Lancez l'installateur `AH2-Gestion-Setup.exe` (voir la section 8 pour le produire).
2. Au premier démarrage, choisissez **« Ce PC est le PC central »** et gardez le code `PC1`.
3. Cliquez sur **Installer le PC central**. Aucun mot de passe n'est demandé : le logiciel s'ouvre directement sur le compte du **comptable**, avec tous les menus et les listes de base déjà remplies (examens, natures de dépenses, programmes, remèdes AE et SE).
   - Pour un essai, cochez plutôt « données de démonstration ». On en sort par le menu du compte (en haut à droite) › **Quitter la démonstration** : les données fictives sont effacées et l'installation réelle peut commencer.
   - Pour exiger un identifiant et un mot de passe plus tard : **Paramétrage › Seuils et paramètres › Demander un identifiant et un mot de passe à l'ouverture**.
4. Suivez la carte **Mise en route** de l'accueil, puis dans **Paramétrage** :
   - **Structure** : saisissez nom, adresse, contacts et numéros administratifs de chaque entité. Ils figureront en en-tête de tous les documents.
   - **Utilisateurs** : créez un compte personnel pour chaque personne (comptable, caissiers, agents, direction…), avec un mot de passe et un code court pour le téléphone. **Aucun compte partagé.**
   - **Tarifs**, **Seuils et délais** : remplacez les valeurs de démonstration.
   - **Plan comptable** : le comptable valide les comptes un par un.

## 4. Autoriser et installer un téléphone ou un autre PC

**Sur le PC central**, dans **Paramétrage › Appareils › Autoriser un appareil** :

- saisissez un code (`T01`, `T02`, `PC2`…) et un nom (par exemple « Téléphone laboratoire ») ;
- le logiciel affiche une **clé de synchronisation** : notez-la ou copiez-la. Il crée aussi automatiquement les caisses mobiles de l'appareil.

**Sur le téléphone :**

1. Copiez le fichier `app-release.apk` sur le téléphone, par câble USB ou par Bluetooth.
2. Ouvrez-le et acceptez « Installer des applications inconnues » pour ce fichier. Le Play Store n'est pas nécessaire.
3. Connectez le téléphone au Wi-Fi de la structure.
4. Ouvrez AH2 Gestion et choisissez **« Cet appareil rejoint la structure »**. Saisissez :
   - le code de l'appareil (`T01`) ;
   - l'adresse du PC central (`192.168.1.10`) ;
   - la clé de synchronisation.
5. Le téléphone se synchronise et reçoit le paramétrage. Chacun peut ensuite se connecter avec son identifiant et son code.

Un autre PC s'installe de la même façon, avec l'installateur Windows.

## 5. Synchronisation au quotidien

- Elle est **automatique** toutes les 2 minutes dès que l'appareil est sur le Wi-Fi de la structure.
- Elle peut aussi être **manuelle** : bouton « Synchroniser maintenant » dans l'écran Synchronisation, ou appui sur l'indicateur en haut de l'écran.
- Un **indicateur permanent** affiche l'état : *Synchronisé*, *En attente · N opérations* ou *Hors ligne depuis X h*.
- Au-delà du nombre de jours fixé sans synchronisation (paramètre, 3 par défaut), l'appareil passe en **lecture seule**.
- La **clôture journalière** et les **relevés** ne sont possibles qu'une fois tous les appareils synchronisés. Un appareil hors service peut être déclaré « inactif » dans Paramétrage › Appareils pour ne plus bloquer.

## 6. Appareil perdu ou volé

Sur le PC central, ouvrez **Paramétrage › Appareils** et cliquez sur **Révoquer**.

- À sa prochaine connexion au Wi-Fi de la structure, l'appareil est bloqué et **ses données locales sont effacées**.
- Sans connexion, il reste protégé : base chiffrée, ouverture par code, passage en lecture seule après le délai.

Toutes les opérations déjà synchronisées restent sur le PC central.

## 7. Sauvegardes et restauration

**Sauvegarde quotidienne** (sur le PC central) : ouvrez **Paramétrage › Sauvegardes**, indiquez le dossier du disque externe (par exemple `E:\Sauvegardes AH2`) et un mot de passe de sauvegarde, puis cliquez sur **Sauvegarder maintenant**.

- Le fichier `.ah2s` est **chiffré**.
- Les anciennes sauvegardes sont supprimées après le délai de conservation (paramètre).
- Une **alerte** apparaît sur le tableau de bord si aucune sauvegarde n'a réussi depuis plus de 24 heures.
- La copie distante (cloud) est facultative et se fait hors du logiciel, uniquement si la structure le décide.

**Restauration du PC central :**

1. Sur le PC central (réinstallé au besoin comme « PC central » avec le code `PC1`), ouvrez **Paramétrage › Sauvegardes › Restaurer une sauvegarde**.
2. Indiquez le chemin du fichier `.ah2s` et son mot de passe. Le logiciel déchiffre la sauvegarde et vérifie l'intégrité de la base et du journal d'audit, puis la met en place.
3. Reconnectez-vous : la base est identique à celle du moment de la sauvegarde. Ce point est vérifié par les tests automatiques.

**Reconstruction d'un téléphone** : réinstallez l'application, puis refaites l'étape 4 avec le même code et la même clé. Le téléphone reçoit tout depuis le PC central.

## 8. Produire les fichiers d'installation (développeur)

Sur un PC Windows avec Flutter et Visual Studio (C++) :

```bash
flutter build windows --release
```

Empaquetez ensuite le dossier `build\windows\x64\runner\Release` avec Inno Setup (un modèle de script `.iss` reste à fournir). L'installateur obtenu est `AH2-Gestion-Setup.exe`.

Sur un PC avec Flutter et le SDK Android :

```bash
flutter build apk --release
```

Le fichier produit est `build/app/outputs/flutter-apk/app-release.apk`. Avant la mise en service, signez-le avec la clé de la structure.
