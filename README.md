# MIC — Monde Interconnecté

> *Connect to the world. Stay close to those who matter.*
> *Connectez-vous au monde. Restez proche de ceux qui comptent.*

Prototype web fonctionnel du réseau social **MIC**, construit à partir du
*Cahier de conception fonctionnelle* (v1.0). Une seule identité, deux univers
étanches :

- **Me** (privé, marron) : discussions, groupes, stories pour les amis et les proches.
- **World** (public, vert) : publications, fils *For You* / *Following*, hashtags, tendances, abonnés.

Rien ne passe de Me à World sans une action explicite, grâce au **sélecteur
d'audience** « Share with… » (section 4.5 du cahier).

## Démarrer

Prérequis : **Node.js 22.5 ou plus récent** (la base SQLite intégrée `node:sqlite` est utilisée).

```bash
npm install
npm run seed     # facultatif : crée 5 comptes de démonstration
npm start        # http://localhost:3000
```

Comptes de démonstration (après `npm run seed`) — choisissez « Se connecter » :

| Numéro | Compte |
| --- | --- |
| +237 670000001 | @angele — Angèle Nkoa (World actif, **modératrice**) |
| +237 670000002 | @paul — Paul Mbarga |
| +237 670000003 | @sophie — Sophie Ekane (Me uniquement) |
| +237 670000004 | @kofi — Kofi Mensah (créateur) |
| +33 600000005 | @lea — Léa Martin (choisir la France comme pays) |

La démo contient aussi un canal (« MIC Officiel »), une communauté (« Cuisine
camerounaise ») avec un événement, des discussions, des stories et des publications.

Aucun SMS n'est envoyé : en développement, **le code de vérification s'affiche
à l'écran** (et dans le terminal). Ouvrez deux navigateurs (ou une fenêtre
privée) pour voir la messagerie en temps réel entre deux comptes.

Autres commandes :

```bash
npm test         # tests d'intégration de l'API (node:test)
npm run dev      # redémarrage automatique pendant le développement
```

### Application de bureau (Windows .exe)

L'application de bureau (Electron) embarque le serveur MIC et s'ouvre dans sa
propre fenêtre, sans navigateur ni Node.js à installer. À chaque envoi sur
GitHub, le workflow « Applications MIC » construit le `.exe` et le publie dans
l'onglet **Releases** du dépôt :

- `MIC-Setup-<version>.exe` : installateur (raccourcis Bureau et menu Démarrer) ;
- `MIC-<version>-portable.exe` : se lance directement, sans installation.

Au premier lancement, les comptes de démonstration ci-dessus sont créés. Les
données (base, photos, vocaux) restent sur l'ordinateur, dans
`%APPDATA%\MIC\data`. Par défaut, le serveur n'écoute que sur cet ordinateur
(127.0.0.1) ; le menu **Partage → Partager sur le réseau local** l'ouvre aux
navigateurs des appareils du même Wi-Fi (adresse affichée, par exemple
`http://192.168.1.10:37238`, aussi dans le titre de la fenêtre) : tout le monde
s'écrit alors en temps réel sur le MIC de ce PC. Partagez seulement sur un
réseau de confiance (le code de connexion s'affiche sur l'appareil qui le
demande). L'application n'est pas signée :
Windows SmartScreen demande une confirmation (« Informations complémentaires »
→ « Exécuter quand même »).

```bash
npm run desktop       # lancer l'application de bureau depuis les sources
npm run desktop:win   # construire le .exe (sous Windows)
```

### Application Android (.apk)

Le workflow « Applications MIC » construit aussi `MIC-<version>.apk` (Android 7.0
et plus récent) et le publie dans la même version des **Releases**.

Comme l'application Windows, l'APK fonctionne **seul dans le téléphone**, sans
serveur ni adresse à saisir. Le code du serveur MIC (`server/`, le même que sur
PC) est regroupé avec l'interface et tourne dans l'application (Capacitor,
dossier `mobile/`) :

- `mobile/src/backend.js` reçoit les appels `/api` et la connexion temps réel
  `/ws` de l'interface, sans réseau ;
- `mobile/src/shims/` remplace les modules Node : `node:sqlite` par SQLite en
  WebAssembly (sql.js), Express, `ws`, `node:crypto`, les fichiers ;
- la base est enregistrée sur le téléphone après chaque écriture (IndexedDB) ;
  photos, vocaux et vidéos sont rangés dans le stockage de l'application et
  servis par un service worker (`mobile/src/sw.js`) ;
- les téléchargements (mes données, événement, clip) ouvrent le partage Android.

Au premier lancement, les comptes de démonstration sont créés. Le micro et la
caméra fonctionnent (vocaux, Clips, photos). Comme sur PC, chaque appareil a son
propre MIC : pour essayer une discussion, déconnectez-vous puis connectez-vous
avec un autre compte de démonstration. Les appels demandent que les deux
personnes soient connectées en même temps au même MIC.

La clé de signature `mobile/keystore/mic-sideload.jks` est publique : elle sert
seulement à installer les nouvelles versions par-dessus les anciennes. Pour le
Play Store, il faudra une clé secrète (variables `MIC_KEYSTORE`,
`MIC_KEYSTORE_PASSWORD`, `MIC_KEY_ALIAS`, `MIC_KEY_PASSWORD`).

```bash
cd mobile
npm install
npm run build:www     # regroupe public/ et server/ dans www/
npm run build:apk     # APK : nécessite en plus le SDK Android et Java 21
```

Variables d'environnement : `PORT` (3000), `HOST`, `MIC_DB` (chemin de la base,
par défaut `data/mic.db`), `NODE_ENV=production` (masque les codes OTP),
`MIC_ICE_SERVERS` (serveurs STUN/TURN pour les appels, en JSON, par exemple
`[{"urls":"turn:turn.example.com:3478","username":"mic","credential":"…"}]`).

Le micro et la caméra ne fonctionnent dans le navigateur qu'en **HTTPS** ou sur
`localhost`. Pour essayer les appels entre deux téléphones, servez l'application en HTTPS.

## Ce que couvre le prototype

| Section du cahier | Implémenté |
| --- | --- |
| 2. Identité « luxe » | Palette Espresso / Cognac / Émeraude / Sauge / Laiton / Ivoire / Ébène, serif pour les titres, logo « sourire » en une ligne, liseré d'univers, mode sombre, animations courtes, squelettes de chargement, états vides |
| 3. Langues | Les six langues de lancement : anglais (par défaut), français, espagnol, portugais, arabe (interface en miroir, de droite à gauche) et swahili ; langue du navigateur détectée, bascule instantanée, fichiers de langue téléchargés à la demande ; dates, heures et compteurs localisés (1,2 k), fuseau horaire des événements |
| 4. Me / World | Deux visages (nom et photo privés pour les amis, publics pour les autres), présence World facultative, sélecteur d'audience avec blocs Privé / Public, bouton *Send* (marron) ou *Publish* (vert), confirmation de la première publication publique, dernier choix privé mémorisé (jamais le public) |
| 5. Compte | Inscription par numéro + code à 6 chiffres (expiration 10 min, 5 codes/heure, 5 essais), date de naissance (âge minimum 13 ans, mineurs en privé), @username avec suggestions, choix « Rester en privé » / « Rejoindre World », déconnexion, suppression du compte |
| 6. Graphe social | Amis (demandes, acceptation, refus silencieux), proches (liste privée), abonnés (compte World public ou privé avec approbation), personnes que vous pourriez connaître |
| 7. Navigation | 5 onglets : Chats · Stories · Caméra · World · Me ; bandeau hors ligne ; menu Nouveau (discussion, groupe, liste de diffusion, canal) |
| 8. Messagerie | Discussions individuelles et groupes, temps réel (WebSocket), statuts envoyé / distribué / lu, « écrit… », en ligne / vu à (amis seulement), réponses citées, réactions (une par personne), modification 15 min, suppression pour tous 48 h, photos, demandes de message pour les inconnus (sans accusé de lecture), mineurs non joignables par des inconnus |
| 9. Messages vocaux | Maintenir le micro pour enregistrer, glisser à gauche pour annuler, glisser vers le haut ou simple appui pour verrouiller (« Tap to record »), pause / reprise, écoute avant envoi, onde sonore, lecture 1× · 1,5× · 2×, avance en touchant l'onde, lecture continue des vocaux non écoutés, mini-lecteur flottant, statut « écouté » (point vert / micro vert), indicateur « enregistre un vocal… », Opus ~32 kbit/s, 60 min max. |
| 10. Appels | Appels vocaux et vidéo individuels et de groupe (32 max.) en WebRTC pair-à-pair, sonnerie, Accepter / Refuser / Répondre par message, occupé, sans réponse après 40 s, bandeau « Rejoindre » pour un appel de groupe en cours, micro / caméra / changer de caméra / passer de l'audio à la vidéo, réactions qui flottent, réduction en pastille pour continuer à naviguer, message « Appel manqué · Rappeler » dans la discussion, historique (Toutes / Manqués, suppression), appels réservés aux amis (10.8) et impossibles avec un compte bloqué |
| 8.8 / 8.9 Éphémères et vue unique | Minuteur par discussion (désactivé, 24 h, 7 j, 90 j) avec message système, minuteur par défaut, effacement automatique côté serveur ; photo ou vocal en vue unique ouvert une seule fois en plein écran, fichier supprimé ensuite, statut « Ouvert » |
| 11. Groupes, canaux, diffusion | Groupes (admins, mode annonce, ajout / retrait) ; **canaux** World publics ou privés sur invitation, 16 admins, réactions, vues, abonnés invisibles entre eux ; **listes de diffusion** (256 amis, réponses en privé) |
| 12. Stories | Audiences Amis / Proches / Moi uniquement / World, 24 h, lecteur plein écran (appui = pause), liste des vues, archives |
| 13. Caméra | Prise de vue (getUserMedia) ou galerie, 6 filtres MIC, stories texte sur fonds de la marque |
| 14. World | Publications texte + photo, réglages par publication (qui peut voir, qui peut commenter, masquer les j'aime), modification, suppression, partage vers une discussion (passerelle World → Me) |
| 14.2 Clips | Enregistrement vidéo depuis la caméra MIC (3 min) ou import (10 min, 50 Mo), couverture automatique, publication avec réglages (dont « Autoriser le téléchargement », désactivé par défaut pour les mineurs), fil vertical plein écran (appui = pause, double appui = j'aime, son activable), lecture automatique silencieuse dans les fils, compteur de vues |
| 16. Interactions | J'aime (double-clic avec l'animation du sourire), commentaires, mentions, enregistrements, « Pas intéressé » |
| 17. Découverte | Recherche (personnes, hashtags, publications), pages hashtag, tendances, fil *For You* explicable (« Pourquoi je vois ce contenu ? ») |
| 18. Communautés et événements | Communautés publiques, privées (sur demande) ou cachées (sur invitation), rôles propriétaire / admin / modérateur / membre, règles, épinglage, retrait de publications, journal de modération, fil « Communautés » ; événements (visibilité, J'y vais / Intéressé / Je ne peux pas, adresse réservée aux participants confirmés, rappels 1 jour et 1 heure avant, annulation notifiée, export vers l'agenda) |
| 19. Notifications | J'aime, commentaires, mentions, demandes, communautés, événements, modération |
| 20.2 Confidentialité | Vu à et en ligne, photo de profil privée, statut, qui peut m'écrire / m'appeler / me mentionner, minuteur par défaut, accusés de lecture et indicateur d'écriture (réciproques), suggestion du compte ; valeurs plus strictes et verrouillées pour les mineurs |
| 22. Modération | Blocage (22.4) ; signalement limité à ce que l'on voit (message transmis avec 5 précédents) ; **console de modération** triée par gravité, images floutées ; décisions et **avertissements** (restriction 24 h / 7 j, suspension 30 j, bannissement) ; **appels** revus par un autre modérateur ; pages « Statut du compte » et « Mes signalements » ; modérateurs désignés par `MIC_MODERATORS` |
| 24.2 Données personnelles | « Télécharger mes données » en JSON ou en page HTML lisible |
| 26. Économie de données et hors ligne | Mode MIC Lite (photos légères, pas de lecture automatique, pas de polices web), consommation réseau de la session ; application installable (manifeste, icônes) ; service worker : application et discussions déjà vues disponibles hors ligne, messages écrits hors ligne envoyés au retour du réseau |

## Ce qui reste à faire (et pourquoi)

Le cahier décrit une application native destinée à une équipe d'environ 40
personnes (section 28.3). Ce prototype valide le produit ; il ne remplace pas :

- **Chiffrement de bout en bout** (Signal / MLS, section 21) : ici les messages sont
  stockés côté serveur et l'interface le dit honnêtement dans chaque discussion.
- **Envoi réel des SMS** (fournisseur OTP à choisir, annexe D), vérification en deux
  étapes, passkeys, appareils liés, sauvegarde chiffrée.
- **Applications mobiles natives** et architecture distribuée (section 27) ; serveur
  TURN et SFU pour les appels à grande échelle ; transcodage et diffusion adaptative
  des vidéos.
- Live, MIC Effects Studio, MIC Privé, publicité, monétisation (phases 2 et 3).
- Family Center (phase 1.5), vérification de l'âge, conformité par pays, rapports de
  transparence publiés (sections 22 à 24).
- Alerte de capture d'écran (impossible à détecter dans un navigateur).
- Traductions relues par des locuteurs natifs (règle des 98 % de la section 3.2).

## Architecture

```
server/
  index.js         démarrage HTTP + WebSocket
  app.js           Express, authentification, médias, erreurs
  db.js            schéma SQLite (modèle de données de la section 27.3)
  social.js        règles de visibilité (amis, proches, abonnés, blocages)
  views.js         mise en forme des réponses (« une personne, deux visages »)
  realtime.js      hub WebSocket : messages, accusés, présence, « écrit… »
  privacy.js       réglages de confidentialité (20.2) et valeurs pour les mineurs
  routes/          account · people · chats · stories · world · calls (signalisation WebRTC)
                   · moderation · channels (canaux, listes de diffusion)
                   · communities (communautés, événements) · export
  seed.js          données de démonstration
public/
  index.html, css/styles.css (MIC Design System), img/logo.svg
  js/app.js        routeur et coquille ; js/i18n.js (EN/FR) ; js/ui.js (composants)
  js/voice.js      enregistreur et lecteur de vocaux ; js/calls.js (appels WebRTC)
  js/outbox.js     file d'envoi hors ligne ; js/datasaver.js (mode Lite)
  js/locales/      es · pt · ar · sw (chargées à la demande)
  sw.js            service worker ; manifest.webmanifest et icônes
  js/screens/      auth · chats · stories · create (caméra + sélecteur d'audience) · world · me
                   · safety (modération) · channels · communities
test/              tests d'intégration (API, vocaux, signalisation des appels)
```

Aucune étape de compilation : le client est en JavaScript natif (modules ES).
