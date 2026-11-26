/// Facturation et créances (§6.10) et carnets de séances de massage (§6.7).
library;

import '../../noyau/base.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../comptabilite/moteur.dart';
import '../tresorerie/tresorerie.dart';

class Facturation {
  /// Avoir : réduit la créance d'un patient ou d'un organisme (rôle
  /// autorisé, motif obligatoire). [compteProduit] : prestation concernée.
  static Operation avoir(Session s,
      {required String tiers, required int montant, required String motif, required String compteProduit, String compteTiers = '4111', String? activite}) {
    final b = s.base;
    return b.transaction(() {
      s.exiger('facturation', 'valider');
      if (motif.trim().isEmpty) throw const RegleMetier("Le motif de l'avoir est obligatoire.");
      final du = Moteur.solde(b, 'CS', compteTiers, tiers: tiers);
      if (montant <= 0 || montant > du) throw RegleMetier('Montant invalide : créance de ${fcfa(du)}.');
      return Operations.enregistrer(s, type: 'avoir', entite: 'CS', typePiece: 'AV', donnees: {
        'tiers': tiers,
        'montant': montant,
        'motif': motif.trim(),
        'compte_produit': compteProduit,
        'compte_tiers': compteTiers,
        'activite': activite,
      });
    });
  }

  // ------------------------------------------------------------ carnets de séances
  static Operation vendreCarnet(Session s,
      {required String acte, required int seances, required int montant, String? patient, String mode = Modes.especes, String? reference}) {
    final b = s.base;
    return b.transaction(() {
      final cat = b.ligne('SELECT * FROM actes_catalogue WHERE code=? AND actif=1', [acte]) ?? (throw const RegleMetier('Prestation inconnue.'));
      if (seances < 2) throw const RegleMetier('Un carnet compte au moins 2 séances.');
      if (montant <= 0) throw const RegleMetier('Montant invalide.');
      if (!Modes.encaissables.contains(mode)) throw const RegleMetier('Mode de paiement invalide.');
      Tresorerie.verifierReference(mode, reference);
      return Operations.enregistrer(s, type: 'carnet_vente', entite: 'CS', typePiece: 'REC', donnees: {
        'id': b.nouvelUuid(),
        'patient': patient,
        'acte': acte,
        'libelle': cat['libelle'],
        'activite': cat['activite'],
        'compte_produit': cat['compte_produit'],
        'seances': seances,
        'montant': montant,
        'mode': mode,
        'reference': reference,
        'tresorerie': Tresorerie.pourMode(b, 'CS', mode),
      });
    });
  }

  static Operation consommerSeance(Session s, String carnet, {String? praticien}) {
    final b = s.base;
    return b.transaction(() {
      final c = b.ligne('SELECT * FROM carnets WHERE id=?', [carnet]) ?? (throw const RegleMetier('Carnet introuvable.'));
      if ((c['consommees'] as int) >= (c['seances'] as int)) throw const RegleMetier('Toutes les séances de ce carnet ont été consommées.');
      return Operations.enregistrer(s, type: 'carnet_seance', entite: 'CS', typePiece: 'SEA', donnees: {'carnet': carnet, 'praticien': praticien});
    });
  }

  static void declarer() {
    Operations.declarer(_Avoir());
    Operations.declarer(_CarnetVente());
    Operations.declarer(_CarnetSeance());
  }
}

class _Avoir extends TypeOperation {
  @override
  String get type => 'avoir';
  @override
  String get module => 'facturation';
  @override
  String get action => 'valider';
  @override
  String get libelle => 'Avoir';
  @override
  void appliquer(Base base, Operation op) => Moteur.generer(base, op, 'avoir',
      total: op.d<int>('montant'),
      variables: {'produit': op.d<String>('compte_produit'), 'compte_tiers': op.d<String>('compte_tiers')},
      tiers: op.d('tiers'),
      activite: op.d('activite'),
      libelle: 'Avoir ${op.piece} : ${op.d('motif')}');
}

class _CarnetVente extends TypeOperation {
  @override
  String get type => 'carnet_vente';
  @override
  String get module => 'actes';
  @override
  String get libelle => 'Vente de carnet de séances';

  @override
  void appliquer(Base base, Operation op) {
    base.exec('INSERT INTO carnets(id, patient, acte, seances, montant, date, uuid_op) VALUES (?,?,?,?,?,?,?)',
        [op.d('id'), op.d('patient'), op.d('acte'), op.d('seances'), op.d('montant'), op.dateOp, op.uuid]);
    final treso = op.d<String>('tresorerie');
    final m = op.d<int>('montant');
    final lib = 'Carnet de ${op.d('seances')} séances : ${op.d('libelle')}';
    Moteur.generer(base, op, 'prestation_payee',
        total: m,
        lignes: [LigneMontant(m, variables: {'produit': op.d<String>('compte_produit')}, activite: op.d('activite'))],
        variables: Tresorerie.variables(base, treso),
        activite: op.d('activite'),
        libelle: lib);
    Tresorerie.mouvement(base, op, treso, m, lib, reference: op.d('reference'));
  }

  @override
  void annuler(Base base, Operation cible, Operation annulation) =>
      base.exec('UPDATE carnets SET seances=consommees WHERE id=?', [cible.d('id')]);
}

class _CarnetSeance extends TypeOperation {
  @override
  String get type => 'carnet_seance';
  @override
  String get module => 'actes';
  @override
  String get libelle => 'Séance de carnet';

  @override
  void appliquer(Base base, Operation op) {
    final c = base.ligne('SELECT * FROM carnets WHERE id=?', [op.d('carnet')]);
    if (c == null) return;
    base.exec('UPDATE carnets SET consommees=consommees+1 WHERE id=?', [c['id']]);
    if ((c['consommees'] as int) + 1 > (c['seances'] as int)) {
      Operations.signalerAnomalie(base, 'carnet_depasse', op.uuid, 'Plus de séances consommées que payées sur un carnet (saisies hors ligne).');
    }
    final cat = base.ligne('SELECT * FROM actes_catalogue WHERE code=?', [c['acte']]);
    // La séance figure au relevé journalier du service (déjà payée par le carnet).
    base.exec(
        "INSERT INTO actes(uuid_op, piece, patient, activite, code_acte, libelle, quantite, prix_unitaire, montant, mode, praticien, date, horodatage, appareil, utilisateur) "
        "VALUES (?,?,?,?,?,?,1,0,0,'carnet',?,?,?,?,?)",
        [op.uuid, op.piece, c['patient'], cat?['activite'] ?? 'MASS', c['acte'], 'Séance de carnet : ${cat?['libelle'] ?? ''}', op.d('praticien'),
          op.dateOp, op.horodatage, op.appareil, op.utilisateur]);
  }

  @override
  void annuler(Base base, Operation cible, Operation annulation) {
    base.exec('UPDATE carnets SET consommees=consommees-1 WHERE id=?', [cible.d('carnet')]);
    base.exec('UPDATE actes SET annule=1 WHERE uuid_op=?', [cible.uuid]);
  }
}

