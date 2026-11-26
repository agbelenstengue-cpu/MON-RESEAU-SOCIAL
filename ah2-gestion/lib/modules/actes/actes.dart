/// Actes des services (consultations, laboratoire, massages…) et encaissement.
///
/// Saisie unique : enregistrer un acte crée le reçu numéroté, l'écriture
/// comptable, le mouvement de caisse ou la créance patient. Un acte gratuit
/// est enregistré à 0 avec son motif et figure dans les relevés.
library;

import '../../noyau/base.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../comptabilite/moteur.dart';
import '../parametrage/parametrage.dart';
import '../tresorerie/tresorerie.dart';

/// Une ligne demandée : code d'acte, quantité, remise éventuelle.
class DemandeActe {
  final String code;
  final int quantite;
  final int remise;
  const DemandeActe(this.code, {this.quantite = 1, this.remise = 0});
}

class Actes {
  static const motifsGratuite = ['programme social', 'indigent', 'personnel', 'campagne'];

  /// Enregistre un ou plusieurs actes d'un même service pour un patient.
  static Operation enregistrer(
    Session s, {
    required String activite,
    required List<DemandeActe> actes,
    required String mode,
    String? patient,
    String? reference,
    String? motifGratuite,
    String? motifRemise,
    String? praticien,
    String? organismePec,
    String? prescripteur,
    String statut = 'realise',
  }) {
    final base = s.base;
    return base.transaction(() {
      if (actes.isEmpty) throw const RegleMetier('Sélectionnez au moins un acte.');
      if (!Modes.tous.contains(mode)) throw RegleMetier('Mode de paiement inconnu : $mode');
      final act = base.ligne('SELECT * FROM activites WHERE code=? AND actif=1', [activite]) ??
          (throw RegleMetier('Service inconnu : $activite'));
      if (s.activite != null && s.role == 'agent' && s.activite != activite) {
        throw const DroitRefuse('Vous ne pouvez enregistrer que les actes de votre service.');
      }
      if (patient != null) {
        if (base.valeur('SELECT 1 FROM patients WHERE id=?', [patient]) == null) {
          throw const RegleMetier('Patient introuvable.');
        }
      }
      if ((mode == Modes.credit || mode == Modes.priseEnCharge) && patient == null) {
        throw const RegleMetier('Un acte à crédit ou pris en charge doit être rattaché à un patient.');
      }
      if (mode == Modes.priseEnCharge && (organismePec == null || organismePec.trim().isEmpty)) {
        throw const RegleMetier("Indiquez l'organisme ou le programme qui prend en charge.");
      }
      if (mode == Modes.gratuit && !motifsGratuite.contains(motifGratuite)) {
        throw RegleMetier('Motif de gratuité obligatoire : ${motifsGratuite.join(', ')}.');
      }
      Tresorerie.verifierReference(mode, reference);
      final aujourdhui = dateIso(base.maintenant);
      final lignes = <Map<String, Object?>>[];
      for (final a in actes) {
        final cat = base.ligne('SELECT * FROM actes_catalogue WHERE code=? AND actif=1', [a.code]) ??
            (throw RegleMetier('Acte inconnu : ${a.code}'));
        if (cat['activite'] != activite) {
          throw RegleMetier('L’acte ${cat['libelle']} n’appartient pas au service ${act['libelle']}.');
        }
        if (a.quantite <= 0) throw const RegleMetier('Quantité invalide.');
        final prix = Parametrage.tarif(base, a.code, aujourdhui);
        final brut = prix * a.quantite;
        if (a.remise < 0 || a.remise > brut) throw const RegleMetier('Remise invalide.');
        if (a.remise > 0) {
          s.exiger('remises', 'creer');
          final plafond = brut * base.paramInt('remise_plafond_pourcent') ~/ 100;
          if (a.remise > plafond) {
            throw RegleMetier('Remise supérieure au plafond autorisé (${base.paramInt('remise_plafond_pourcent')} %).');
          }
          if (motifRemise == null || motifRemise.trim().isEmpty) {
            throw const RegleMetier('Le motif de la remise est obligatoire.');
          }
        }
        lignes.add({
          'code': a.code,
          'libelle': cat['libelle'],
          'quantite': a.quantite,
          'prix_unitaire': prix,
          'remise': mode == Modes.gratuit ? 0 : a.remise,
          'montant': mode == Modes.gratuit ? 0 : brut - a.remise,
          'compte_produit': cat['compte_produit'],
        });
      }
      final entite = act['entite'] as String;
      final total = lignes.fold<int>(0, (t, l) => t + (l['montant'] as int));
      String? treso;
      if (Modes.encaissables.contains(mode)) treso = Tresorerie.pourMode(base, entite, mode);
      final typePiece = switch (mode) {
        Modes.credit => 'FAC',
        Modes.priseEnCharge => 'PEC',
        _ => 'REC',
      };
      return Operations.enregistrer(s, type: 'acte', entite: entite, typePiece: typePiece, donnees: {
        'activite': activite,
        'patient': patient,
        'mode': mode,
        'reference': reference,
        'motif_gratuite': mode == Modes.gratuit ? motifGratuite : null,
        'motif_remise': motifRemise,
        'praticien': praticien,
        'prescripteur': prescripteur,
        'organisme_pec': organismePec,
        'tresorerie': treso,
        'statut': statut,
        'lignes': lignes,
        'total': total,
      });
    });
  }

  /// Laboratoire : passe un examen de « demandé » à « réalisé ».
  static Operation marquerRealise(Session s, String uuidActe) {
    final base = s.base;
    final op = Operations.lire(base, uuidActe) ?? (throw const RegleMetier('Acte introuvable.'));
    return Operations.enregistrer(s, type: 'acte_statut', entite: op.entite, donnees: {'acte': uuidActe, 'statut': 'realise'});
  }

  /// Créance d'un patient (ou organisme) : calculée depuis la comptabilité.
  static int creance(Base base, String tiers, {String compte = '4111'}) =>
      Moteur.solde(base, 'CS', compte, tiers: tiers);

  /// Règlement (total ou partiel) d'une créance patient.
  static Operation reglerCreance(Session s,
      {required String tiers, required int montant, required String mode, String? reference, String compte = '4111'}) {
    final base = s.base;
    return base.transaction(() {
      if (!Modes.encaissables.contains(mode)) throw const RegleMetier('Mode de règlement invalide.');
      Tresorerie.verifierReference(mode, reference);
      final du = creance(base, tiers, compte: compte);
      if (montant <= 0) throw const RegleMetier('Le montant doit être positif.');
      if (montant > du) throw RegleMetier('Le montant dépasse la créance (${fcfa(du)}).');
      return Operations.enregistrer(s, type: 'reglement_creance', entite: 'CS', typePiece: 'REC', donnees: {
        'tiers': tiers,
        'compte_tiers': compte,
        'montant': montant,
        'mode': mode,
        'reference': reference,
        'tresorerie': Tresorerie.pourMode(base, 'CS', mode),
      });
    });
  }

  static void declarer() {
    Operations.declarer(_Acte());
    Operations.declarer(_Statut());
    Operations.declarer(_Reglement());
  }
}

class _Acte extends TypeOperation {
  @override
  String get type => 'acte';
  @override
  String get module => 'actes';
  @override
  String get libelle => 'Acte';

  @override
  void appliquer(Base base, Operation op) {
    final lignes = (op.d<List>('lignes')).cast<Map>();
    final mode = op.d<String>('mode');
    final activite = op.d<String>('activite');
    final patient = op.d<String?>('patient');
    for (final l in lignes) {
      base.exec(
          'INSERT INTO actes(uuid_op, piece, patient, activite, code_acte, libelle, quantite, prix_unitaire, remise, montant, mode, '
          'motif_gratuite, praticien, date, horodatage, appareil, utilisateur, statut) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [op.uuid, op.piece, patient, activite, l['code'], l['libelle'], l['quantite'], l['prix_unitaire'], l['remise'],
            l['montant'], mode, op.d('motif_gratuite'), op.d('praticien'), op.dateOp, op.horodatage, op.appareil, op.utilisateur,
            op.d('statut')]);
    }
    final total = op.d<int>('total');
    if (mode == Modes.gratuit || total == 0) return;
    final detail = [
      for (final l in lignes)
        LigneMontant(l['montant'] as int, variables: {'produit': l['compte_produit'] as String}, activite: activite)
    ];
    final libelle = '${lignes.map((l) => l['libelle']).join(', ')}${op.piece != null ? ' : ${op.piece}' : ''}';
    switch (mode) {
      case Modes.credit:
        Moteur.generer(base, op, 'prestation_credit', total: total, lignes: detail, tiers: patient, activite: activite, libelle: libelle);
      case Modes.priseEnCharge:
        Moteur.generer(base, op, 'prestation_pec',
            total: total, lignes: detail, tiers: op.d<String>('organisme_pec'), activite: activite, libelle: libelle);
      default:
        final treso = op.d<String>('tresorerie');
        Moteur.generer(base, op, 'prestation_payee',
            total: total, lignes: detail, variables: Tresorerie.variables(base, treso), activite: activite, libelle: libelle);
        Tresorerie.mouvement(base, op, treso, total, libelle, reference: op.d('reference'));
    }
  }

  @override
  void annuler(Base base, Operation cible, Operation annulation) =>
      base.exec('UPDATE actes SET annule=1 WHERE uuid_op=?', [cible.uuid]);
}

class _Statut extends TypeOperation {
  @override
  String get type => 'acte_statut';
  @override
  String get module => 'actes';
  @override
  String get libelle => "Statut d'examen";
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) =>
      base.exec('UPDATE actes SET statut=? WHERE uuid_op=?', [op.d('statut'), op.d('acte')]);
}

class _Reglement extends TypeOperation {
  @override
  String get type => 'reglement_creance';
  @override
  String get module => 'caisse';
  @override
  String get libelle => 'Règlement de créance';

  @override
  void appliquer(Base base, Operation op) {
    final treso = op.d<String>('tresorerie');
    final m = op.d<int>('montant');
    Moteur.generer(base, op, 'reglement_creance',
        total: m,
        variables: {...Tresorerie.variables(base, treso), 'compte_tiers': op.d<String>('compte_tiers')},
        tiers: op.d('tiers'),
        libelle: 'Règlement de créance : ${op.piece}');
    Tresorerie.mouvement(base, op, treso, m, 'Règlement de créance', reference: op.d('reference'));
  }
}
