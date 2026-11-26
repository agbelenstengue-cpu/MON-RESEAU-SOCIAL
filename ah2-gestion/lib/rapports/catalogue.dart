/// Catalogue de tous les rapports et états : la liste affichée dans l'écran
/// Rapports, avec les filtres que chacun accepte.
library;

import '../noyau/base.dart';
import '../noyau/outils.dart';
import 'etats_comptables.dart';
import 'etats_gestion.dart';
import 'etats_phase3.dart';
import 'etats_stocks_hospitalisation.dart';
import 'etats_suivi_audit.dart';
import 'statistiques.dart';
import 'modele.dart';

enum Filtre { periode, date, entite, activite, utilisateur, appareil, subvention, tresorerie, racine, stock, patient, employe }

class Parametres {
  final Filtres filtres;
  final String date;
  final String racine;
  final String? patient;
  final String? employe;
  const Parametres(this.filtres, {required this.date, this.racine = '', this.patient, this.employe});
  Periode get periode => filtres.periode;
  String get entite => filtres.entite ?? 'CS';
}

class DefRapport {
  final String id;
  final String categorie;
  final String titre;
  final String description;
  final Set<Filtre> filtres;
  final Rapport Function(Base b, Parametres p) produire;
  const DefRapport(this.id, this.categorie, this.titre, this.description, this.filtres, this.produire);
}

class Catalogue {
  static final List<DefRapport> _extensions = [];

  /// Les modules des phases 2 et 3 ajoutent leurs états ici.
  static void ajouter(List<DefRapport> d) {
    for (final x in d) {
      if (!_extensions.any((e) => e.id == x.id)) _extensions.add(x);
    }
  }

  static List<DefRapport> get tous => [..._base, ..._extensions];

  static final _base = <DefRapport>[
    DefRapport('financier', 'Gestion', 'Rapport financier', 'Recettes par activité, charges, résultat, comparaisons.',
        {Filtre.periode, Filtre.entite, Filtre.activite, Filtre.utilisateur, Filtre.appareil, Filtre.subvention}, (b, p) => EtatsGestion.financier(b, p.filtres)),
    DefRapport('activite', 'Gestion', "Activité d'un service", "Actes par type, par praticien, par utilisateur, gratuités.",
        {Filtre.periode, Filtre.entite, Filtre.activite, Filtre.utilisateur, Filtre.appareil}, (b, p) => EtatsGestion.activite(b, p.filtres)),
    DefRapport('liste_actes', 'Gestion', 'Liste des actes à contrôler sur place', 'Chaque acte, avec une case « Constaté ».',
        {Filtre.periode, Filtre.activite, Filtre.utilisateur, Filtre.appareil}, (b, p) => EtatsGestion.listeActes(b, p.filtres)),
    DefRapport('recus', 'Gestion', 'Reçus émis et annulés', 'Toutes les pièces, avec les annulations et leur motif.',
        {Filtre.periode, Filtre.entite, Filtre.utilisateur, Filtre.appareil}, (b, p) => EtatsGestion.recus(b, p.filtres)),
    DefRapport('brouillard', 'Gestion', 'Brouillard de caisse ou de banque', 'Entrées, sorties et solde progressif.', {Filtre.periode, Filtre.tresorerie},
        (b, p) => EtatsGestion.brouillard(b, p.filtres.tresorerie ?? 'CS-CAISSE', p.periode)),
    DefRapport('desintox_etat', 'Gestion', 'État des patients en désintoxication', 'Patients en cours et sortis avec solde dû.', {Filtre.date},
        (b, p) => EtatsGestion.desintoxEnCours(b, p.date)),
    DefRapport('desintox_versements', 'Gestion', 'Versements reçus en désintoxication', '', {Filtre.periode},
        (b, p) => EtatsGestion.versementsDesintox(b, p.periode)),
    DefRapport('balance_agee', 'Gestion', 'Créances : balance âgée', 'Créances patients et organismes par ancienneté.', {Filtre.date, Filtre.entite},
        (b, p) => EtatsComptables.balanceAgee(b, p.entite, p.date)),
    DefRapport('journaux', 'Comptabilité', 'Journaux comptables', 'Toutes les écritures, journal par journal.', {Filtre.periode, Filtre.entite},
        (b, p) => EtatsComptables.journal(b, p.entite, p.periode)),
    DefRapport('grand_livre', 'Comptabilité', 'Grand livre', 'Mouvements et solde progressif par compte.', {Filtre.periode, Filtre.entite, Filtre.racine},
        (b, p) => EtatsComptables.grandLivre(b, p.entite, p.periode, racine: p.racine)),
    DefRapport('balance', 'Comptabilité', 'Balance générale', 'Soldes d’ouverture, mouvements et soldes de clôture.', {Filtre.periode, Filtre.entite},
        (b, p) => EtatsComptables.balance(b, p.entite, p.periode)),
    DefRapport('balance_tiers', 'Comptabilité', 'Balance des tiers', 'Patients et organismes (411) ou fournisseurs (401).',
        {Filtre.periode, Filtre.entite, Filtre.racine}, (b, p) => EtatsComptables.balanceTiers(b, p.entite, p.periode, racine: p.racine.isEmpty ? '411' : p.racine)),
    DefRapport('compte_resultat', 'États financiers', 'Compte de résultat', 'Produits, charges, résultat ; comparaison N-1.', {Filtre.periode, Filtre.entite},
        (b, p) => EtatsComptables.compteResultat(b, p.entite, p.periode)),
    DefRapport('bilan', 'États financiers', 'Bilan', 'Actif et passif à une date.', {Filtre.date, Filtre.entite}, (b, p) => EtatsComptables.bilan(b, p.entite, p.date)),
    DefRapport('analytique', 'États financiers', 'Résultat par activité', 'Comptabilité analytique avec répartition des charges communes.',
        {Filtre.periode, Filtre.entite}, (b, p) => EtatsComptables.resultatAnalytique(b, p.entite, p.periode)),
    DefRapport('rapprochement', 'Comptabilité', 'État de rapprochement bancaire', '', {Filtre.date, Filtre.tresorerie},
        (b, p) => EtatsComptables.rapprochement(b, p.filtres.tresorerie ?? 'CS-BQ', p.date)),
    DefRapport('dons', 'Dons et subventions', 'État des dons', 'Par donateur, par nature ; dons au-delà du seuil.', {Filtre.periode, Filtre.subvention},
        (b, p) => EtatsGestion.dons(b, p.filtres)),
    DefRapport('subventions', 'Dons et subventions', 'Suivi des subventions', 'Budget, réalisé et solde par ligne.', {}, (b, p) => EtatsGestion.subventions(b)),
    DefRapport('stocks_etat', 'Stocks', 'État des stocks et valorisation', 'Quantités par lot et valeur au CUMP.', {Filtre.date, Filtre.stock},
        (b, p) => EtatsStocks.etat(b, p.filtres.stock, p.date)),
    DefRapport('stocks_mouvements', 'Stocks', 'Mouvements de stock', 'Entrées et sorties détaillées.', {Filtre.periode, Filtre.stock},
        (b, p) => EtatsStocks.mouvements(b, p.filtres.stock, p.periode)),
    DefRapport('stocks_consommations', 'Stocks', 'Consommations, pertes et péremptions', '', {Filtre.periode, Filtre.stock},
        (b, p) => EtatsStocks.mouvements(b, p.filtres.stock, p.periode, types: const ['consommation', 'distribution', 'peremption', 'casse', 'perte'])),
    DefRapport('stocks_inventaire', 'Stocks', "Dernier inventaire : écarts", '', {Filtre.stock}, (b, p) => EtatsStocks.inventaire(b, p.filtres.stock ?? 'PHM')),
    DefRapport('stocks_comptage', 'Stocks', 'Fiche de comptage pour inventaire', '', {Filtre.date, Filtre.stock},
        (b, p) => EtatsStocks.ficheComptage(b, p.filtres.stock ?? 'PHM', p.date)),
    DefRapport('dettes_fournisseurs', 'Stocks', 'Dettes fournisseurs', 'Balance des fournisseurs (401).', {Filtre.periode},
        (b, p) => EtatsComptables.balanceTiers(b, 'CS', p.periode, racine: '401')),
    DefRapport('occupation', 'Hospitalisation', 'Occupation des lits', 'Lits, patients présents, journées, montant cumulé.', {Filtre.date},
        (b, p) => EtatsHospitalisation.occupation(b, p.date)),
    DefRapport('releve_compte', 'Gestion', 'Relevé de compte patient', 'Actes, paiements et solde.', {Filtre.periode, Filtre.patient},
        (b, p) => EtatsTiers.releveCompte(b, p.patient ?? '', p.periode)),
    DefRapport('relances', 'Gestion', 'Créances à relancer', 'Patients et organismes qui doivent depuis plus de 30 jours.', {Filtre.date},
        (b, p) => EtatsTiers.relances(b, p.date)),
    DefRapport('notes_annexes', 'États financiers', 'Notes annexes', 'Règles comptables, immobilisations, stocks, créances et dettes.',
        {Filtre.date, Filtre.entite}, (b, p) => EtatsFinanciersAnnexes.notes(b, p.entite, int.parse(p.date.substring(0, 4)))),
    DefRapport('previsions', 'États financiers', 'Prévisions de trésorerie et de résultat', 'À 30 et 90 jours ; résultat projeté de fin d’exercice.',
        {Filtre.entite}, (b, p) => Previsions.rapport(b, p.entite)),
    DefRapport('bulletin', 'Personnel et paie', 'Bulletin de paie', '', {Filtre.date, Filtre.employe},
        (b, p) => EtatsPaie.bulletin(b, p.employe ?? '', p.date.substring(0, 7))),
    DefRapport('livre_paie', 'Personnel et paie', 'Livre de paie', '', {Filtre.periode, Filtre.entite}, (b, p) => EtatsPaie.livre(b, p.entite, p.periode)),
    DefRapport('declaration_cnps', 'Personnel et paie', 'Déclaration CNPS du mois', '', {Filtre.date, Filtre.entite},
        (b, p) => EtatsPaie.declaration(b, p.entite, p.date.substring(0, 7), organisme: 'CNPS')),
    DefRapport('declaration_fiscale', 'Personnel et paie', 'État des retenues fiscales du mois', '', {Filtre.date, Filtre.entite},
        (b, p) => EtatsPaie.declaration(b, p.entite, p.date.substring(0, 7), organisme: 'ETAT')),
    DefRapport('registre_immo', 'Immobilisations', 'Registre des immobilisations', '', {Filtre.date, Filtre.entite},
        (b, p) => EtatsImmobilisations.registre(b, p.entite, p.date)),
    DefRapport('amortissements', 'Immobilisations', 'Tableau des amortissements', '', {Filtre.date, Filtre.entite},
        (b, p) => EtatsImmobilisations.tableauAmortissements(b, p.entite, int.parse(p.date.substring(0, 4)))),
    DefRapport('inventaire_immo', 'Immobilisations', "Fiche d'inventaire physique des biens", '', {Filtre.entite},
        (b, p) => EtatsImmobilisations.ficheInventaire(b, p.entite)),
    DefRapport('compte_rendu', 'Gestion', 'Compte rendu de la journée aux dirigeants',
        'Activité par service, dépenses, caisses, désintoxication, alertes et observations du comptable.', {Filtre.date},
        (b, p) => EtatsSuivi.compteRendu(b, p.date)),
    DefRapport('statistiques', 'Gestion', 'Statistiques', 'Évolution des recettes et des charges, répartitions par service et par nature.',
        {Filtre.periode}, (b, p) => Statistiques.calculer(b, p.periode, entite: p.filtres.entite).rapport()),
    DefRapport('audit_annulations', 'Contrôle', 'Annulations et motifs', '', {Filtre.periode}, (b, p) => EtatsAudit.annulations(b, p.periode)),
    DefRapport('audit_gratuites', 'Contrôle', 'Gratuités et remises', '', {Filtre.periode}, (b, p) => EtatsAudit.gratuitesRemises(b, p.periode)),
    DefRapport('audit_ecarts', 'Contrôle', 'Écarts de caisse', '', {Filtre.periode}, (b, p) => EtatsAudit.ecartsCaisse(b, p.periode)),
    DefRapport('audit_modifications', 'Contrôle', 'Changements de prix, de montants et de paramètres', '', {Filtre.periode},
        (b, p) => EtatsAudit.modifications(b, p.periode)),
    DefRapport('audit_retroactif', 'Contrôle', 'Saisies à une date passée', 'Date de l’opération et date réelle de saisie.', {Filtre.periode},
        (b, p) => EtatsAudit.saisiesRetroactives(b, p.periode)),
    DefRapport('audit_journal', 'Contrôle', "Journal d'audit (historique complet)", 'Toutes les actions, filtrables par appareil et utilisateur.',
        {Filtre.periode, Filtre.appareil, Filtre.utilisateur},
        (b, p) => EtatsAudit.journal(b, p.periode, appareil: p.filtres.appareil, utilisateur: p.filtres.utilisateur)),
    DefRapport('releves_suivi', 'Contrôle', 'Suivi des relevés et des écarts', '', {Filtre.periode}, (b, p) => EtatsGestion.suiviReleves(b, p.periode)),
    DefRapport('anomalies', 'Contrôle', 'Anomalies de synchronisation', '', {Filtre.periode}, (b, p) => EtatsGestion.anomalies(b, p.periode)),
  ];

  static DefRapport parId(String id) => tous.firstWhere((d) => d.id == id);

  static String aujourdhui(Base b) => dateIso(b.maintenant);
}
