/// Caisse et trésorerie : caisses (centrale et mobiles), banque, mobile money.
///
/// Le solde de chaque compte de trésorerie est TOUJOURS la somme de ses
/// mouvements : il n'est jamais stocké, donc toujours juste. Une sortie
/// supérieure au solde est bloquée.
library;

import 'dart:convert';

import '../../noyau/base.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/pieces_jointes.dart';
import '../../noyau/session.dart';
import '../comptabilite/moteur.dart';

/// Modes de paiement reconnus.
class Modes {
  static const especes = 'especes';
  static const mtn = 'mtn';
  static const orange = 'orange';
  static const cheque = 'cheque';
  static const virement = 'virement';
  static const credit = 'credit';
  static const gratuit = 'gratuit';
  static const priseEnCharge = 'pec';

  static const encaissables = [especes, mtn, orange, cheque, virement];
  static const tous = [...encaissables, credit, gratuit, priseEnCharge];

  static const libelles = {
    especes: 'Espèces',
    mtn: 'MTN MoMo',
    orange: 'Orange Money',
    cheque: 'Chèque',
    virement: 'Virement',
    credit: 'À crédit',
    gratuit: 'Gratuit',
    priseEnCharge: 'Prise en charge',
    'carnet': 'Carnet de séances',
  };

  static bool estMomo(String m) => m == mtn || m == orange;
}

class Tresorerie {
  static int solde(Base base, String tresorerie, {String? jusquau}) => base.entier(
      'SELECT COALESCE(SUM(montant),0) FROM mouvements_tresorerie WHERE tresorerie=?${jusquau != null ? ' AND date<=?' : ''}',
      [tresorerie, ?jusquau]);

  static Ligne compte(Base base, String id) =>
      base.ligne('SELECT * FROM tresoreries WHERE id=?', [id]) ??
      (throw RegleMetier('Compte de trésorerie inconnu : $id'));

  /// Caisse utilisée par cet appareil pour une entité : sa caisse mobile, ou
  /// la caisse centrale sur le PC central.
  static String caisseDe(Base base, String entite, {String? appareil}) {
    final app = appareil ?? base.appareil;
    final mobile = base.valeur(
        "SELECT id FROM tresoreries WHERE entite=? AND type='caisse' AND appareil=? AND actif=1 ORDER BY centrale DESC LIMIT 1",
        [entite, app]);
    if (mobile != null) return mobile as String;
    throw RegleMetier("Aucune caisse n'est rattachée à l'appareil $app pour l'entité $entite.");
  }

  /// Compte de trésorerie qui reçoit un paiement selon son mode.
  static String pourMode(Base base, String entite, String mode, {String? appareil}) {
    switch (mode) {
      case Modes.especes:
        return caisseDe(base, entite, appareil: appareil);
      case Modes.mtn:
        return _premier(base, entite, "type='momo' AND operateur='MTN'");
      case Modes.orange:
        return _premier(base, entite, "type='momo' AND operateur='ORANGE'");
      case Modes.cheque:
      case Modes.virement:
        return _premier(base, entite, "type='banque'");
    }
    throw RegleMetier("Le mode « $mode » n'est pas un encaissement.");
  }

  static String _premier(Base base, String entite, String condition) =>
      (base.valeur('SELECT id FROM tresoreries WHERE entite=? AND actif=1 AND $condition ORDER BY id LIMIT 1', [entite])
          as String?) ??
      (throw RegleMetier('Aucun compte de trésorerie configuré ($condition) pour $entite.'));

  /// Variables d'écriture pour un compte de trésorerie.
  static Map<String, String> variables(Base base, String tresorerie, {String prefixe = ''}) {
    final t = compte(base, tresorerie);
    final p = prefixe.isEmpty ? 'tresorerie' : prefixe;
    final j = prefixe.isEmpty ? 'journal_tresorerie' : 'journal_$prefixe';
    return {p: t['compte'] as String, j: t['journal'] as String};
  }

  /// Ajoute un mouvement (appelé par les applicateurs d'opérations).
  static void mouvement(Base base, Operation op, String tresorerie, int montant, String libelle, {String? reference}) {
    base.exec(
        'INSERT INTO mouvements_tresorerie(uuid_op, tresorerie, date, horodatage, montant, libelle, piece, reference) VALUES (?,?,?,?,?,?,?,?)',
        [op.uuid, tresorerie, op.dateOp, op.horodatage, montant, libelle, op.piece, reference]);
    if (montant < 0 && solde(base, tresorerie) < 0) {
      Operations.signalerAnomalie(base, 'solde_negatif', op.uuid,
          'Le solde de « ${compte(base, tresorerie)['libelle']} » est devenu négatif après ${op.piece ?? op.type}.');
    }
  }

  static void verifierDisponible(Base base, String tresorerie, int montant) {
    final s = solde(base, tresorerie);
    if (montant > s) {
      throw RegleMetier('Sortie refusée : ${fcfa(montant)} demandés, solde disponible ${fcfa(s)}.');
    }
  }

  static void verifierReference(String mode, String? reference) {
    if (Modes.estMomo(mode) && (reference == null || reference.trim().length < 4)) {
      throw const RegleMetier('La référence de transaction mobile money est obligatoire.');
    }
  }

  // ------------------------------------------------------------------ dépenses

  /// Décaissement. Au-delà du seuil, il attend la validation de la direction.
  static Operation depense(
    Session s, {
    required String entite,
    required String beneficiaire,
    String motif = '',
    String? compteCharge,
    String? activite,
    String? nature,
    required int montant,
    String? tresorerie,
    String? pieceJointe,
    Map<String, Object?>? fichier,
    String? subvention,
    String? reference,
  }) {
    final base = s.base;
    return base.transaction(() {
      if (montant <= 0) throw const RegleMetier('Le montant doit être positif.');
      // Nature de dépense : le compte et le service sont déduits (aucun numéro à choisir).
      if (nature != null) {
        final n = base.ligne('SELECT * FROM natures_depenses WHERE code=? AND entite=? AND actif=1', [nature, entite]) ??
            (throw const RegleMetier('Nature de dépense inconnue.'));
        compteCharge ??= n['compte'] as String;
        activite ??= (n['activite'] as String?) ?? (entite == 'CS' ? 'ADM_CS' : 'ADM_ONG');
        if (motif.trim().isEmpty) motif = n['libelle'] as String;
      }
      if (compteCharge == null || activite == null) throw const RegleMetier('Choisissez la nature de la dépense.');
      final compteCharge0 = compteCharge!;
      if (beneficiaire.trim().isEmpty || motif.trim().isEmpty) {
        throw const RegleMetier('Le bénéficiaire et le motif sont obligatoires.');
      }
      if (!compteCharge0.startsWith('6') && !compteCharge0.startsWith('2') && !compteCharge0.startsWith('4')) {
        throw const RegleMetier('Imputation invalide : choisissez un compte de charge (classe 6).');
      }
      if (montant > base.paramInt('seuil_piece_jointe') && fichier == null && (pieceJointe == null || pieceJointe.isEmpty)) {
        throw RegleMetier('Pièce jointe obligatoire au-delà de ${fcfa(base.paramInt('seuil_piece_jointe'))}.');
      }
      final treso = tresorerie ?? caisseDe(base, entite);
      if (compte(base, treso)['entite'] != entite) {
        throw const RegleMetier("Le compte de trésorerie n'appartient pas à cette entité.");
      }
      final aValider = montant > base.paramInt('seuil_validation_depense');
      if (!aValider) verifierDisponible(base, treso, montant);
      return Operations.enregistrer(s, type: 'depense', entite: entite, typePiece: 'DEC', donnees: {
        'beneficiaire': beneficiaire.trim(),
        'motif': motif.trim(),
        'compte': compteCharge0,
        'activite': activite,
        'nature': nature,
        'montant': montant,
        'tresorerie': treso,
        'piece_jointe': fichier?['sha256'] ?? pieceJointe,
        'fichier': fichier,
        'subvention': subvention,
        'reference': reference,
        'a_valider': aValider,
      });
    });
  }

  static Operation validerDepense(Session s, String uuidDepense, {bool accepter = true, String? motif}) {
    final base = s.base;
    return base.transaction(() {
      final d = base.ligne('SELECT * FROM depenses WHERE uuid_op=?', [uuidDepense]);
      if (d == null) throw const RegleMetier('Dépense introuvable.');
      if (d['statut'] != 'en_attente') throw const RegleMetier("Cette dépense n'est pas en attente de validation.");
      if (accepter) verifierDisponible(base, d['tresorerie'] as String, d['montant'] as int);
      if (!accepter && (motif == null || motif.trim().isEmpty)) {
        throw const RegleMetier('Le motif du rejet est obligatoire.');
      }
      return Operations.enregistrer(s,
          type: 'validation_depense',
          entite: d['entite'] as String,
          donnees: {'depense': uuidDepense, 'accepte': accepter, 'motif': motif});
    });
  }

  // ------------------------------------------------------------------ virements

  /// Mouvement interne (caisse -> banque, caisse mobile -> caisse centrale…).
  /// Ni recette ni charge : passage par le compte 585.
  static Operation virement(Session s,
      {required String source,
      required String destination,
      required int montant,
      String? reference,
      String? remisPar,
      String? recuPar}) {
    final base = s.base;
    return base.transaction(() {
      if (montant <= 0) throw const RegleMetier('Le montant doit être positif.');
      if (source == destination) throw const RegleMetier('La source et la destination doivent être différentes.');
      final src = compte(base, source);
      final dst = compte(base, destination);
      if (src['entite'] != dst['entite']) {
        throw const RegleMetier('Un virement interne reste dans la même entité (utilisez le compte de liaison sinon).');
      }
      if (src['type'] == 'caisse' && dst['type'] == 'caisse' && (remisPar == null || recuPar == null)) {
        throw const RegleMetier('Versement entre caisses : indiquez qui remet et qui reçoit (pièce signée par les deux).');
      }
      if ((src['type'] != 'caisse' || dst['type'] != 'caisse') && (reference == null || reference.trim().isEmpty)) {
        throw const RegleMetier('La référence (bordereau, transaction) est obligatoire.');
      }
      verifierDisponible(base, source, montant);
      return Operations.enregistrer(s, type: 'virement_interne', entite: src['entite'] as String, typePiece: 'VIR', donnees: {
        'source': source,
        'destination': destination,
        'montant': montant,
        'reference': reference,
        'remis_par': remisPar,
        'recu_par': recuPar,
      });
    });
  }

  // ------------------------------------------------------------------ arrêté

  static List<int> coupures(Base base) => base.param('coupures').split(',').map(int.parse).toList();

  /// Arrêté de caisse quotidien avec billetage. L'écart est enregistré
  /// automatiquement (manquant ou excédent) avec son écriture.
  static Operation arreterCaisse(Session s, {required String caisse, required Map<int, int> billetage, String? motifEcart}) {
    final base = s.base;
    return base.transaction(() {
      final c = compte(base, caisse);
      if (c['type'] != 'caisse') throw const RegleMetier("L'arrêté concerne une caisse.");
      final autorisees = coupures(base).toSet();
      var total = 0;
      billetage.forEach((coupure, nombre) {
        if (!autorisees.contains(coupure)) throw RegleMetier('Coupure inconnue : $coupure');
        if (nombre < 0) throw const RegleMetier('Nombre de billets négatif.');
        total += coupure * nombre;
      });
      final aujourdhui = dateIso(base.maintenant);
      final deja = base.valeur(
          'SELECT a.uuid_op FROM arretes_caisse a WHERE a.tresorerie=? AND a.date=? AND a.uuid_op NOT IN (SELECT uuid_annule FROM annulations)',
          [caisse, aujourdhui]);
      if (deja != null) throw const RegleMetier("L'arrêté de cette caisse est déjà fait aujourd'hui.");
      final theorique = solde(base, caisse);
      final ecart = total - theorique;
      if (ecart != 0 && (motifEcart == null || motifEcart.trim().isEmpty)) {
        throw RegleMetier('Écart de ${fcfa(ecart)} : le motif est obligatoire.');
      }
      return Operations.enregistrer(s, type: 'arrete_caisse', entite: c['entite'] as String, typePiece: 'ARR', donnees: {
        'caisse': caisse,
        'billetage': {for (final e in billetage.entries) '${e.key}': e.value},
        'compte': total,
        'theorique': theorique,
        'ecart': ecart,
        'motif_ecart': motifEcart,
      });
    });
  }

  static void declarer() {
    Operations.declarer(_Depense());
    Operations.declarer(_ValidationDepense());
    Operations.declarer(_Virement());
    Operations.declarer(_Arrete());
  }
}

class _Depense extends TypeOperation {
  @override
  String get type => 'depense';
  @override
  String get module => 'depenses';
  @override
  String get libelle => 'Dépense';

  static void payer(Base base, Operation op, Ligne d, {required Operation paiement}) {
    final treso = d['tresorerie'] as String;
    Moteur.generer(base, paiement, 'depense',
        total: d['montant'] as int,
        entite: d['entite'] as String,
        variables: {...Tresorerie.variables(base, treso), 'charge': d['compte'] as String},
        activite: d['activite'] as String,
        subvention: d['subvention'] as String?,
        libelle: '${d['motif']} : ${d['beneficiaire']}');
    Tresorerie.mouvement(base, paiement, treso, -(d['montant'] as int), 'Dépense : ${d['motif']}',
        reference: d['piece'] as String?);
  }

  @override
  void appliquer(Base base, Operation op) {
    PiecesJointes.enregistrer(base, op, op.donnees['fichier']);
    final aValider = op.d<bool>('a_valider');
    base.exec(
        'INSERT INTO depenses(uuid_op, entite, piece, date, beneficiaire, motif, compte, activite, subvention, tresorerie, montant, piece_jointe, statut, nature) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [op.uuid, op.entite, op.piece, op.dateOp, op.d('beneficiaire'), op.d('motif'), op.d('compte'), op.d('activite'),
          op.d('subvention'), op.d('tresorerie'), op.d('montant'), op.d('piece_jointe'), aValider ? 'en_attente' : 'payee', op.donnees['nature']]);
    if (!aValider) {
      payer(base, op, base.ligne('SELECT * FROM depenses WHERE uuid_op=?', [op.uuid])!, paiement: op);
    }
  }

  @override
  void annuler(Base base, Operation cible, Operation annulation) =>
      base.exec('UPDATE depenses SET annule=1 WHERE uuid_op=?', [cible.uuid]);
}

class _ValidationDepense extends TypeOperation {
  @override
  String get type => 'validation_depense';
  @override
  String get module => 'depenses';
  @override
  String get action => 'valider';
  @override
  String get libelle => 'Validation de dépense';

  @override
  void appliquer(Base base, Operation op) {
    final d = base.ligne('SELECT * FROM depenses WHERE uuid_op=?', [op.d<String>('depense')]);
    if (d == null) {
      Operations.signalerAnomalie(base, 'validation_orpheline', op.uuid, 'Validation d’une dépense inconnue.');
      return;
    }
    if (d['statut'] != 'en_attente') {
      Operations.signalerAnomalie(base, 'double_validation', op.uuid, 'Dépense ${d['piece']} validée deux fois.');
      return;
    }
    if (op.d<bool>('accepte')) {
      base.exec("UPDATE depenses SET statut='payee', valide_par=? WHERE uuid_op=?", [op.utilisateur, d['uuid_op']]);
      _Depense.payer(base, op, d, paiement: op);
    } else {
      base.exec("UPDATE depenses SET statut='rejetee', valide_par=? WHERE uuid_op=?", [op.utilisateur, d['uuid_op']]);
    }
  }

  @override
  void annuler(Base base, Operation cible, Operation annulation) => base.exec(
      "UPDATE depenses SET statut='en_attente', valide_par=NULL WHERE uuid_op=?", [cible.d<String>('depense')]);
}

class _Virement extends TypeOperation {
  @override
  String get type => 'virement_interne';
  @override
  String get module => 'caisse';
  @override
  String get libelle => 'Mouvement interne';

  @override
  void appliquer(Base base, Operation op) {
    final src = op.d<String>('source');
    final dst = op.d<String>('destination');
    final m = op.d<int>('montant');
    final lib = 'Virement ${Tresorerie.compte(base, src)['libelle']} vers ${Tresorerie.compte(base, dst)['libelle']}';
    Moteur.generer(base, op, 'virement_sortie',
        total: m, variables: Tresorerie.variables(base, src, prefixe: 'source'), libelle: lib, activite: null);
    Moteur.generer(base, op, 'virement_entree',
        total: m, variables: Tresorerie.variables(base, dst, prefixe: 'destination'), libelle: lib);
    Tresorerie.mouvement(base, op, src, -m, lib, reference: op.d('reference'));
    Tresorerie.mouvement(base, op, dst, m, lib, reference: op.d('reference'));
  }
}

class _Arrete extends TypeOperation {
  @override
  String get type => 'arrete_caisse';
  @override
  String get module => 'caisse';
  @override
  String get libelle => 'Arrêté de caisse';

  @override
  void appliquer(Base base, Operation op) {
    final caisse = op.d<String>('caisse');
    final ecart = op.d<int>('ecart');
    base.exec(
        'INSERT INTO arretes_caisse(uuid_op, tresorerie, date, billetage, compte, theorique, ecart, motif_ecart, piece) VALUES (?,?,?,?,?,?,?,?,?)',
        [op.uuid, caisse, op.dateOp, jsonEncode(op.d('billetage')), op.d('compte'), op.d('theorique'), ecart,
          op.d('motif_ecart'), op.piece]);
    if (ecart != 0) {
      Moteur.generer(base, op, ecart < 0 ? 'ecart_caisse_manquant' : 'ecart_caisse_excedent',
          total: ecart.abs(),
          variables: Tresorerie.variables(base, caisse),
          activite: op.entite == 'CS' ? 'ADM_CS' : 'ADM_ONG',
          libelle: '${ecart < 0 ? 'Manquant' : 'Excédent'} de caisse : ${op.d('motif_ecart')}');
      Tresorerie.mouvement(base, op, caisse, ecart, 'Écart d’arrêté de caisse');
    }
  }
}
