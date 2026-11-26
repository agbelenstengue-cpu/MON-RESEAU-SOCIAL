# Guides utilisateurs par rôle, AH2 Gestion

Chaque personne a **son propre identifiant**. Sur PC, on se connecte avec un mot de passe. Sur téléphone, on se connecte avec un code court. Toute action est tracée : qui, quand, sur quel appareil.

La session se ferme seule après quelques minutes d'inactivité. Le compte se verrouille après 5 mots de passe erronés.

Sur tous les écrans :

- le **bouton (+)** donne accès aux actions rapides : encaissement, patient, versement, dépense ;
- la **loupe** cherche un patient, un reçu ou un donateur ;
- le **menu du compte** permet de passer en mode clair ou sombre, de régler la taille du texte et de se déconnecter.

---

## Caissier

**Encaisser un acte**

1. Ouvrez **Caisse** (ou le bouton (+) puis *Nouvel encaissement*).
2. Choisissez le patient. C'est facultatif si l'acte est payé comptant.
3. Choisissez le service, puis cochez les actes. Le total se calcule tout seul.
4. Choisissez le mode de paiement :
   - **Mobile money** : la référence de transaction est obligatoire ;
   - **Gratuit** : choisissez le motif (programme social, indigent, personnel, campagne) ;
   - **À crédit** : une créance patient est créée ;
   - **Prise en charge** : indiquez l'organisme.
5. Appuyez sur **Encaisser et émettre le reçu**, puis imprimez le ticket ou partagez-le (WhatsApp).

**Autres tâches**

- **Régler une créance** : ouvrez *Patients*, puis la fiche du patient, puis *Régler la créance*.
- **Dépense** : ouvrez *Trésorerie* puis *Nouvelle dépense*. Indiquez le bénéficiaire, le motif, le compte et la photo du justificatif. Au-delà du seuil, la dépense attend la validation de la direction. Une sortie supérieure au solde est refusée.
- **Reverser la caisse mobile** à la caisse centrale : *Trésorerie*, puis *Mouvement interne*. Indiquez qui remet et qui reçoit ; la pièce est signée par les deux.
- **Arrêté de caisse** (chaque soir) : *Trésorerie*, puis *Arrêté de caisse*. Saisissez le nombre de billets et de pièces de chaque coupure. L'écart est calculé ; le motif est obligatoire s'il y en a un. Imprimez le PDF et signez-le.

**Annulation** : un caissier ne peut pas annuler. Signalez l'erreur au comptable, qui annule avec un motif.

## Agent de service (laboratoire, consultation, désintoxication, massages)

- Vous enregistrez **les actes de votre service uniquement**, sur le téléphone du service, même hors ligne.
- Le lendemain, vous recevez le **relevé journalier des actes**. Vérifiez chaque ligne, cochez « Confirmé » et notez les écarts. Le responsable signe.

**Agent de désintoxication :**

- **Inscrire un patient** : *Désintox*, puis *Inscrire*. Choisissez le patient, le programme, puis les responsables du paiement (nom, lien, téléphone).
- **Versement** : ouvrez la fiche du patient, puis *Nouveau versement*. Indiquez le montant, qui paie et le mode. Le reçu indique le montant versé ce jour, le total déjà versé et le reste à payer.
- **Sortie** : ouvrez la fiche, puis *Enregistrer la sortie* et choisissez le motif. Le *Rapport de sortie du patient* (PDF) s'imprime ou se partage.

La liste de travail a trois onglets : *En cours*, *Sortis avec solde dû* et *Archives*.

- Un patient soldé disparaît de la liste 30 jours après sa sortie.
- Un patient qui doit encore de l'argent reste dans l'onglet *Sortis avec solde dû* jusqu'au paiement complet.
- Rien n'est jamais effacé : les dossiers archivés restent consultables.

## Responsable de service

- Consulte les relevés de son service et les confirme : **signature et cachet** sur le relevé papier.
- Signale tout écart au comptable : acte non réalisé, acte réalisé mais non enregistré, montant différent.

## Comptable

**Le matin, sur le PC central :**

1. Vérifiez que tous les appareils sont synchronisés (écran *Synchronisation*).
2. Dans *Relevés journaliers*, cliquez sur **Générer tous les services** pour la veille. Imprimez les relevés et remettez-les aux services.
3. Au retour des relevés signés, marquez-les *retournés signés* en joignant la photo. Saisissez les écarts éventuels : chacun crée une **fiche d'écart**, à justifier ou à régulariser.
4. Dans *Comptabilité*, onglet *Clôtures*, **clôturez la veille** pour chaque entité. Plus aucune saisie n'est ensuite possible sur cette date.

**En continu :**

- **Annuler** une opération : par contre-opération, avec un motif obligatoire. Rien ne se supprime.
- Traiter les **anomalies de synchronisation** (*Comptabilité*, onglet *Anomalies*) : versements simultanés hors ligne, conflits sur un dossier patient, etc.
- **Rouvrir une journée** : faites la demande, avec motif, dans *Comptabilité › Clôtures*. La direction doit l'approuver.
- **Dons et subventions** : enregistrez chaque don et remettez le reçu au donateur. Les conventions de subvention se suivent ligne par ligne (budget, réalisé, solde).
- Valider le **plan comptable** dans *Paramétrage › Plan comptable*. Le centre de santé est en SYSCOHADA, l'ONG en SYCEBNL.

**Paramétrage (sur le PC central) :** tout s'ajoute, se modifie et se retire, sans toucher au code.

- **Structure et documents** : vous pouvez importer le logo, ou importer une entête toute faite (l'image de votre papier à en-tête, qui remplace alors l'entête générée). Vous pouvez aussi modifier les textes de l'entête et activer ou non le logo en filigrane (documents et écran).
- **Services, actes et prix** : ajouter un service ou un acte, changer un prix (il s'applique à partir d'aujourd'hui, le passé ne change pas), renommer, retirer.
- **Programmes de désintoxication**, **comptes de trésorerie** (banques, mobile money, caisses), **plan comptable**, **schémas d'écritures**, **seuils et délais**, **utilisateurs**.
- Retirer un élément qui n'a jamais servi le supprime. Retirer un élément qui a déjà servi le **désactive** : il disparaît des listes de saisie, mais l'historique et la comptabilité restent intacts. On peut le réactiver.

## Direction, présidence, trésorerie

- **Tableau de bord** : recettes, charges, soldes de chaque caisse, banque et mobile money, santé de chaque activité (en hausse, stable ou en baisse), alertes.
- **Valider les dépenses** au-delà du seuil : *Trésorerie*, section *Dépenses en attente de validation*.
- **Approuver les réouvertures** de journée demandées par le comptable.
- **Rapports** : rapport financier du jour avec note de synthèse, brouillards, reçus émis et annulés, au format PDF.

## Administrateur

- Gère le **paramétrage** : structure, utilisateurs, appareils, tarifs, seuils, sauvegardes.
- **Ne saisit aucune opération** : le logiciel le lui interdit.
- Autorise les nouveaux appareils et **révoque** un appareil perdu.
- Fait la **sauvegarde quotidienne** sur le disque externe (voir le guide d'installation).

## Auditeur

- **Lecture seule complète**, y compris le **journal d'audit** (*Comptabilité*, onglet *Audit*).
- Le logiciel vérifie en continu l'intégrité de la chaîne d'audit. Toute altération du fichier, même faite en dehors du logiciel, est signalée.
