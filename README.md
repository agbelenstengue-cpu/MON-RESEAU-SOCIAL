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
| +237 670000001 | @angele — Angèle Nkoa (World actif) |
| +237 670000002 | @paul — Paul Mbarga |
| +237 670000003 | @sophie — Sophie Ekane (Me uniquement) |
| +237 670000004 | @kofi — Kofi Mensah (créateur) |
| +33 600000005 | @lea — Léa Martin |

Aucun SMS n'est envoyé : en développement, **le code de vérification s'affiche
à l'écran** (et dans le terminal). Ouvrez deux navigateurs (ou une fenêtre
privée) pour voir la messagerie en temps réel entre deux comptes.

Autres commandes :

```bash
npm test         # tests d'intégration de l'API (node:test)
npm run dev      # redémarrage automatique pendant le développement
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
| 3. Langues | Anglais par défaut, français ; bascule instantanée ; dates et compteurs localisés (1,2 k) |
| 4. Me / World | Deux visages (nom et photo privés pour les amis, publics pour les autres), présence World facultative, sélecteur d'audience avec blocs Privé / Public, bouton *Send* (marron) ou *Publish* (vert), confirmation de la première publication publique, dernier choix privé mémorisé (jamais le public) |
| 5. Compte | Inscription par numéro + code à 6 chiffres (expiration 10 min, 5 codes/heure, 5 essais), date de naissance (âge minimum 13 ans, mineurs en privé), @username avec suggestions, choix « Rester en privé » / « Rejoindre World », déconnexion, suppression du compte |
| 6. Graphe social | Amis (demandes, acceptation, refus silencieux), proches (liste privée), abonnés (compte World public ou privé avec approbation), personnes que vous pourriez connaître |
| 7. Navigation | 5 onglets : Chats · Stories · Caméra · World · Me ; bandeau hors ligne |
| 8. Messagerie | Discussions individuelles et groupes, temps réel (WebSocket), statuts envoyé / distribué / lu, « écrit… », en ligne / vu à (amis seulement), réponses citées, réactions (une par personne), modification 15 min, suppression pour tous 48 h, photos, demandes de message pour les inconnus (sans accusé de lecture), mineurs non joignables par des inconnus |
| 9. Messages vocaux | Maintenir le micro pour enregistrer, glisser à gauche pour annuler, glisser vers le haut ou simple appui pour verrouiller (« Tap to record »), pause / reprise, écoute avant envoi, onde sonore, lecture 1× · 1,5× · 2×, avance en touchant l'onde, lecture continue des vocaux non écoutés, mini-lecteur flottant, statut « écouté » (point vert / micro vert), indicateur « enregistre un vocal… », Opus ~32 kbit/s, 60 min max. |
| 10. Appels | Appels vocaux et vidéo individuels et de groupe (32 max.) en WebRTC pair-à-pair, sonnerie, Accepter / Refuser / Répondre par message, occupé, sans réponse après 40 s, bandeau « Rejoindre » pour un appel de groupe en cours, micro / caméra / changer de caméra / passer de l'audio à la vidéo, réactions qui flottent, réduction en pastille pour continuer à naviguer, message « Appel manqué · Rappeler » dans la discussion, historique (Toutes / Manqués, suppression), appels réservés aux amis (10.8) et impossibles avec un compte bloqué |
| 8.8 / 8.9 Éphémères et vue unique | Minuteur par discussion (désactivé, 24 h, 7 j, 90 j) avec message système, minuteur par défaut, effacement automatique côté serveur ; photo ou vocal en vue unique ouvert une seule fois en plein écran, fichier supprimé ensuite, statut « Ouvert » |
| 11. Groupes | Création avec ses amis, admins, mode annonce, ajout / retrait, quitter |
| 12. Stories | Audiences Amis / Proches / Moi uniquement / World, 24 h, lecteur plein écran (appui = pause), liste des vues, archives |
| 13. Caméra | Prise de vue (getUserMedia) ou galerie, 6 filtres MIC, stories texte sur fonds de la marque |
| 14. World | Publications texte + photo, réglages par publication (qui peut voir, qui peut commenter, masquer les j'aime), modification, suppression, partage vers une discussion (passerelle World → Me) |
| 14.2 Clips | Enregistrement vidéo depuis la caméra MIC (3 min) ou import (10 min, 50 Mo), couverture automatique, publication avec réglages (dont « Autoriser le téléchargement », désactivé par défaut pour les mineurs), fil vertical plein écran (appui = pause, double appui = j'aime, son activable), lecture automatique silencieuse dans les fils, compteur de vues |
| 16. Interactions | J'aime (double-clic avec l'animation du sourire), commentaires, mentions, enregistrements, « Pas intéressé » |
| 17. Découverte | Recherche (personnes, hashtags, publications), pages hashtag, tendances, fil *For You* explicable (« Pourquoi je vois ce contenu ? ») |
| 19. Notifications | J'aime, commentaires, mentions, demandes d'ami et d'abonnement |
| 20.2 Confidentialité | Vu à et en ligne, photo de profil privée, statut, qui peut m'écrire / m'appeler / me mentionner, minuteur par défaut, accusés de lecture et indicateur d'écriture (réciproques), suggestion du compte ; valeurs plus strictes et verrouillées pour les mineurs |
| 22. Sécurité | Blocage (effets de la section 22.4), signalement avec motifs |

## Ce qui reste à faire (et pourquoi)

Le cahier décrit une application native destinée à une équipe d'environ 40
personnes (section 28.3). Ce prototype valide le produit ; il ne remplace pas :

- **Chiffrement de bout en bout** (Signal / MLS, section 21) : ici les messages
  sont stockés en clair côté serveur et l'interface le dit honnêtement.
- **Envoi réel des SMS** (fournisseur OTP à choisir, annexe D), vérification en deux étapes, passkeys.
- Pour les appels : un serveur **TURN** (à définir avec `MIC_ICE_SERVERS`, sinon certains réseaux
  d'entreprise ou mobiles bloquent la connexion), un **SFU** pour les grands appels de groupe (ici
  chaque participant se connecte à chacun, adapté jusqu'à environ 6 personnes), les liens d'appel,
  le partage d'écran et les effets en direct.
- Pour les vocaux : transcription, coupe du début / de la fin avant envoi, vocaux en vue unique,
  brouillon vocal conservé quand on quitte la discussion.
- Live, MIC Effects Studio, communautés, événements, canaux ; pour les Clips : montage, sons,
  duo / remix, transcodage serveur (les vidéos sont servies telles qu'envoyées).
- Alerte de capture d'écran (impossible à détecter dans un navigateur), sauvegarde chiffrée,
  appareils liés, verrouillage de discussion.
- Modération outillée, Family Center, vérification de l'âge, conformité par pays (sections 22 à 24).
- Applications mobiles natives et architecture distribuée (section 27).

## Architecture

```
server/
  index.js         démarrage HTTP + WebSocket
  app.js           Express, authentification, médias, erreurs
  db.js            schéma SQLite (modèle de données de la section 27.3)
  social.js        règles de visibilité (amis, proches, abonnés, blocages)
  views.js         mise en forme des réponses (« une personne, deux visages »)
  realtime.js      hub WebSocket : messages, accusés, présence, « écrit… »
  routes/          account · people · chats · stories · world · calls (signalisation WebRTC)
  seed.js          données de démonstration
public/
  index.html, css/styles.css (MIC Design System), img/logo.svg
  js/app.js        routeur et coquille ; js/i18n.js (EN/FR) ; js/ui.js (composants)
  js/voice.js      enregistreur et lecteur de vocaux ; js/calls.js (appels WebRTC)
  js/screens/      auth · chats · stories · create (caméra + sélecteur d'audience) · world · me
test/              tests d'intégration (API, vocaux, signalisation des appels)
```

Aucune étape de compilation : le client est en JavaScript natif (modules ES).
