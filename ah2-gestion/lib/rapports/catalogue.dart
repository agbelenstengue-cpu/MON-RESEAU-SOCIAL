/// Catalogue de tous les rapports et états : la liste affichée dans l'écran
/// Rapports, avec les filtres que chacun accepte.
library;

import '../noyau/base.dart';
import '../noyau/outils.dart';
import 'etats_comptables.dart';
import 'etats_gestion.dart';
import 'etats_stocks_hospitalisation.dart';
import 'modele.dart';

enum Filtre { periode, date, entite, activite, utilisateur, appareil, subvention, tresorerie, racine, stock, patient }

class Parametres {
  final Filtres filtres;
  final String date;
  final String racine;
  final String? patient;
  const Parametres(this.filtres, {required this.date, this.racine = '', this.patient});
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
    DefRapport('releves_suivi', 'Contrôle', 'Suivi des relevés et des écarts', '', {Filtre.periode}, (b, p) => EtatsGestion.suiviReleves(b, p.periode)),
    DefRapport('anomalies', 'Contrôle', 'Anomalies de synchronisation', '', {Filtre.periode}, (b, p) => EtatsGestion.anomalies(b, p.periode)),
  ];

  static DefRapport parId(String id) => tous.firstWhere((d) => d.id == id);

  static String aujourdhui(Base b) => dateIso(b.maintenant);
}
