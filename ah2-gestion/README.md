# AH2 Gestion

Logiciel de gestion intégrée de l'ONG **A Hand to Humanity (AH2)** et de son centre de santé.

Il tient en **une seule application** pour le PC (Windows) et le téléphone (Android). La version iPhone pourra être ajoutée sans réécriture. Il fonctionne **entièrement hors ligne** : aucun hébergement web, aucun lien Internet. Les appareils se synchronisent avec le PC central **uniquement par le Wi-Fi local** de la structure.

![Accueil sur PC](docs/captures/pc_accueil.png)

## État : les trois phases du cahier des charges (§12)

| Domaine | Contenu |
|---|---|
| Socle | Hors ligne, base locale chiffrée par appareil, synchronisation Wi-Fi chiffrée, mises à jour sans perte de données |
| Paramétrage | Tout est modifiable par le comptable : services, actes et prix, programmes, comptes, schémas d'écritures, trésorerie, lits, produits, taux de paie, catégories d'immobilisations, seuils |
| Patients, caisse, actes | Encaissement, gratuités, remises, crédit, prise en charge, caisses mobiles, arrêté avec billetage, carnets de séances, avoirs |
| Désintoxication | Inscription, versements, échéancier, sortie, archivage, réadmission, médicaments compris ou facturés |
| Pharmacies et stocks | Lots, FEFO, CUMP, inventaire, alertes, conflits hors ligne, fournisseurs, commandes, réceptions, règlements |
| Hospitalisation | Lits, admission avec caution, journées, actes et produits du séjour, facture, sortie |
| Dons et subventions | ONG (SYCEBNL), dons en nature transférés au centre, suivi budgétaire des subventions |
| Personnel et paie | Salariés et bénévoles, rubriques datées, avances, bulletins, livre de paie, déclarations, paiement, congés |
| Immobilisations | Registre, amortissements mensuels, cessions, inventaire |
| Comptabilité | Journaux, grand livre, balances, balance âgée, lettrage, rapprochement, saisie, soldes d'ouverture, clôture d'exercice, analytique |
| États financiers | Bilan, compte de résultat (SYSCOHADA et SYCEBNL), notes annexes, prévisions de trésorerie et de résultat |
| Rapports | Plus de 35 états, par période (jour, semaine, mois, trimestre, année, dates libres) et par filtres, en PDF et Excel ; export Sage |
| Tableau de bord | Indicateurs, tendances sur 12 mois, perspectives, alertes (dont déficit) |

## Présentation

- Police **Arial** partout. Sur PC, c'est l'Arial de Windows. Sur téléphone, c'est son équivalent libre de mêmes dimensions, Liberation Sans, embarqué dans l'application.
- Les documents PDF utilisent la même police.
- Charte sobre ; logo de la structure dans l'entête et **en filigrane**. On peut aussi importer une entête toute faite (Paramétrage › Structure et documents).

## Deux comptabilités

Le centre de santé et l'ONG sont deux entités distinctes :

| | Centre de santé (`CS`) | ONG AH2 (`ONG`) |
|---|---|---|
| Référentiel | SYSCOHADA révisé | SYCEBNL |
| Activités | Consultations, laboratoire, hospitalisation, désintoxication, massages, pharmacies | Programmes sociaux, dons, subventions |
| Pièces | `REC-CS-T01-2026-000451` | `DON-ONG-PC1-2026-000012` |

L'entité est choisie **automatiquement** selon l'activité : personne ne la choisit à la main. Les plans comptables sont livrés pré-remplis, avec la mention « à valider par le comptable ». Comptes, schémas d'écritures, tarifs, seuils et délais se modifient tous dans le paramétrage. **Rien n'est codé en dur.**

## Architecture

```
lib/
  noyau/        base SQLite, opérations immuables, audit chaîné, numérotation,
                sécurité (mots de passe), chiffrement, pièces jointes
  modules/      un module par domaine du §6 : parametrage, patients, tresorerie,
                actes, desintox, dons, cloture, releves, rapports, sauvegarde,
                comptabilite (moteur d'écritures)
  sync/         couche de synchronisation isolée (protocole + transport HTTP local)
  pdf/          documents : reçu 80 mm, relevé A4, rapport de sortie, rapport du jour,
                arrêté de caisse
  ui/           écrans Flutter (conformes aux maquettes validées)
  demo/         données de démonstration fictives
test/           tests automatisés des règles du §13
```

**Principe central : la saisie unique par opérations immuables.** Chaque action (encaissement, versement, dépense, don…) est une *opération* identifiée par un UUID. Enregistrer une opération se fait en **une seule transaction**, qui comprend :

1. la vérification des droits, de la date (journée non clôturée) et de l'état de l'appareil ;
2. l'attribution du numéro de pièce, sans trou ;
3. la génération de l'écriture comptable (contrôle débit = crédit), du mouvement de caisse et de la créance ;
4. la trace dans le journal d'audit.

La synchronisation recopie les **opérations**, jamais les résultats : chaque base les applique de la même façon. Il n'y a donc ni perte ni doublon. Une opération reçue n'est jamais rejetée : une incohérence devient une **anomalie** à traiter par le comptable.

Le schéma de la base est dans `lib/noyau/schema.dart`. Des déclencheurs SQL interdisent toute modification ou suppression des opérations, des écritures et du journal d'audit.

## Développement

```bash
flutter pub get
flutter test                      # règles du §13, synchronisation, chiffrement, écrans
flutter run -d windows            # PC
flutter build apk --release       # téléphone Android (APK installé directement)
flutter build windows --release   # puis installateur (voir docs/guide-installation.md)
```

Pour produire les captures d'écran des tests : `AH2_CAPTURES=1 flutter test test/ecrans --update-goldens`.

## Documentation

- [Guide d'installation](docs/guide-installation.md) : PC central, autres PC, téléphones, réseau Wi-Fi local, sauvegardes et restauration.
- [Guides utilisateurs par rôle](docs/guide-utilisateurs.md).
- [Points à valider par la structure](docs/points-a-valider.md).
