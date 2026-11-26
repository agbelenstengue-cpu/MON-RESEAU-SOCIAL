/// Hospitalisation (§6.5) : lits, admissions avec caution, journées,
/// actes et produits rattachés au séjour, sortie avec facture récapitulative,
/// déduction de la caution, solde à payer ou à rembourser.
library;

import '../../noyau/base.dart';
import '../../noyau/numerotation.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../comptabilite/moteur.dart';
import '../parametrage/parametrage.dart';
import '../tresorerie/tresorerie.dart';

class Hospitalisation {
  // ------------------------------------------------------------ lits (paramétrage)
  static void enregistrerLit(Session s, {required String code, required String chambre, required String categorie, required int tarif}) =>
      Parametrage.modifier(s, 'parametrage', 'lit:$code', () {
        final c = code.trim().toUpperCase();
        if (c.isEmpty || chambre.trim().isEmpty) throw const RegleMetier('Code du lit et chambre obligatoires.');
        if (tarif < 0) throw const RegleMetier('Tarif invalide.');
        s.base.exec(
            'INSERT INTO lits(code, chambre, categorie, tarif_journalier) VALUES (?,?,?,?) ON CONFLICT(code) DO UPDATE SET '
            'chambre=excluded.chambre, categorie=excluded.categorie, tarif_journalier=excluded.tarif_journalier, actif=1',
            [c, chambre.trim(), categorie.trim(), tarif]);
      }, nouveau: {'chambre': chambre, 'tarif': tarif});

  static String retirerLit(Session s, String code) => Parametrage.modifier(s, 'parametrage', 'lit:$code', () {
        final b = s.base;
        if (b.valeur('SELECT 1 FROM sejours WHERE lit=? AND date_sortie IS NULL', [code]) != null) {
          throw const RegleMetier('Le lit est occupé.');
        }
        if (b.valeur('SELECT 1 FROM sejours WHERE lit=?', [code]) != null) {
          b.exec('UPDATE lits SET actif=0 WHERE code=?', [code]);
          return 'désactivé';
        }
        b.exec('DELETE FROM lits WHERE code=?', [code]);
        return 'supprimé';
      }, nouveau: 'retiré');

  static bool litLibre(Base b, String lit) => b.valeur('SELECT 1 FROM sejours WHERE lit=? AND date_sortie IS NULL', [lit]) == null;

  // ------------------------------------------------------------ séjours
  static Operation admettre(Session s, {required String patient, required String lit, int caution = 0, String mode = Modes.especes, String? reference}) {
    final b = s.base;
    return b.transaction(() {
      if (b.valeur('SELECT 1 FROM patients WHERE id=?', [patient]) == null) throw const RegleMetier('Patient introuvable.');
      final l = b.ligne('SELECT * FROM lits WHERE code=? AND actif=1', [lit]) ?? (throw const RegleMetier('Lit inconnu.'));
      if (!litLibre(b, lit)) throw RegleMetier('Le lit $lit est occupé.');
      if (b.valeur('SELECT numero FROM sejours WHERE patient=? AND date_sortie IS NULL', [patient]) != null) {
        throw const RegleMetier('Ce patient est déjà hospitalisé.');
      }
      if (caution < 0) throw const RegleMetier('Caution invalide.');
      if (caution > 0) Tresorerie.verifierReference(mode, reference);
      final numero = Numerotation.dossier(b, prefixe: 'H', exercice: b.maintenant.year);
      return Operations.enregistrer(s, type: 'admission', entite: 'CS', typePiece: caution > 0 ? 'REC' : null, donnees: {
        'id': b.nouvelUuid(),
        'numero': numero,
        'patient': patient,
        'lit': lit,
        'tarif': l['tarif_journalier'],
        'caution': caution,
        'mode': mode,
        'reference': reference,
        'tresorerie': caution > 0 ? Tresorerie.pourMode(b, 'CS', mode) : null,
      });
    });
  }

  static Ligne sejour(Base b, String id) => b.ligne('SELECT * FROM sejours WHERE id=?', [id]) ?? (throw const RegleMetier('Séjour introuvable.'));

  /// Journées comptées : jours entamés depuis l'entrée (au moins une).
  static int journees(Base b, Ligne s, {String? jusquau}) {
    final fin = (s['date_sortie'] as String?) ?? jusquau ?? dateIso(b.maintenant);
    final j = joursEntre(s['date_entree'] as String, fin);
    return j < 1 ? 1 : j;
  }

  /// Situation d'un séjour : journées, actes, produits, caution, reste.
  static Map<String, Object?> situation(Base b, String id) {
    final s = sejour(b, id);
    final j = journees(b, s);
    final montantJournees = j * (s['tarif_journalier'] as int);
    final actes = b.lignes('SELECT * FROM actes WHERE sejour=? AND annule=0 ORDER BY horodatage', [id]);
    final produits = b.lignes(
        "SELECT m.*, p.designation FROM mouvements_stock m JOIN produits p ON p.code=m.produit WHERE m.reference=? AND m.annule=0 AND m.quantite<0 ORDER BY m.horodatage",
        [id]);
    final ventes = b.lignes("SELECT donnees FROM operations WHERE type='stock_sortie' AND donnees LIKE ? AND uuid NOT IN (SELECT uuid_annule FROM annulations)",
        ['%"sejour":"$id"%']);
    var totalProduits = 0;
    for (final v in ventes) {
      totalProduits += Operation0.total(v['donnees'] as String);
    }
    final totalActes = actes.fold<int>(0, (t, a) => t + (a['montant'] as int));
    final total = montantJournees + totalActes + totalProduits;
    return {
      'sejour': s,
      'journees': j,
      'montant_journees': montantJournees,
      'actes': actes,
      'total_actes': totalActes,
      'produits': produits,
      'total_produits': totalProduits,
      'total': total,
      'caution': s['caution'],
      'reste': total - (s['caution'] as int),
    };
  }

  static Operation sortir(Session s, String id, {bool rembourserExcedent = true, String modeRemboursement = Modes.especes}) {
    final b = s.base;
    return b.transaction(() {
      final se = sejour(b, id);
      if (se['date_sortie'] != null) throw const RegleMetier('La sortie est déjà enregistrée.');
      final sit = situation(b, id);
      final caution = se['caution'] as int;
      final total = sit['total'] as int;
      final aRembourser = rembourserExcedent && caution > total ? caution - total : 0;
      String? treso;
      if (aRembourser > 0) {
        treso = Tresorerie.pourMode(b, 'CS', modeRemboursement);
        Tresorerie.verifierDisponible(b, treso, aRembourser);
      }
      return Operations.enregistrer(s, type: 'sortie_hospitalisation', entite: 'CS', typePiece: 'FAC', donnees: {
        'sejour': id,
        'patient': se['patient'],
        'journees': sit['journees'],
        'montant_journees': sit['montant_journees'],
        'imputation_caution': caution < total ? caution : total,
        'remboursement': aRembourser,
        'tresorerie': treso,
      });
    });
  }

  static List<Ligne> occupation(Base b) => b.lignes(
      "SELECT l.*, s.id AS sejour, s.numero, s.date_entree, p.nom, p.prenoms, p.numero_dossier FROM lits l "
      "LEFT JOIN sejours s ON s.lit=l.code AND s.date_sortie IS NULL LEFT JOIN patients p ON p.id=s.patient WHERE l.actif=1 ORDER BY l.chambre, l.code");

  static double tauxOccupation(Base b) {
    final o = occupation(b);
    return o.isEmpty ? 0 : o.where((l) => l['sejour'] != null).length / o.length;
  }

  static void declarer() {
    Operations.declarer(_Admission());
    Operations.declarer(_Sortie());
  }
}

/// Lecture du total d'une opération enregistrée (JSON).
class Operation0 {
  static int total(String donnees) {
    final m = RegExp(r'"total":(\d+)').firstMatch(donnees);
    return m == null ? 0 : int.parse(m.group(1)!);
  }
}

class _Admission extends TypeOperation {
  @override
  String get type => 'admission';
  @override
  String get module => 'hospitalisation';
  @override
  String get libelle => "Admission en hospitalisation";
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    base.exec(
        'INSERT INTO sejours(id, numero, patient, lit, date_entree, tarif_journalier, caution, uuid_op) VALUES (?,?,?,?,?,?,?,?)',
        [op.d('id'), op.d('numero'), op.d('patient'), op.d('lit'), op.dateOp, op.d('tarif'), op.d('caution'), op.uuid]);
    final c = op.d<int>('caution');
    if (c > 0) {
      final treso = op.d<String>('tresorerie');
      Moteur.generer(base, op, 'caution_hospitalisation',
          total: c, variables: Tresorerie.variables(base, treso), tiers: op.d('patient'), activite: 'HOSP', libelle: 'Caution ${op.d('numero')}');
      Tresorerie.mouvement(base, op, treso, c, 'Caution d’hospitalisation ${op.d('numero')}', reference: op.d('reference'));
    }
    if (!Hospitalisation.litLibre(base, op.d('lit')) &&
        base.entier('SELECT COUNT(*) FROM sejours WHERE lit=? AND date_sortie IS NULL', [op.d('lit')]) > 1) {
      Operations.signalerAnomalie(base, 'conflit_lit', op.uuid, 'Le lit ${op.d('lit')} a été attribué deux fois (admissions hors ligne).');
    }
  }
}

class _Sortie extends TypeOperation {
  @override
  String get type => 'sortie_hospitalisation';
  @override
  String get module => 'hospitalisation';
  @override
  String get libelle => "Sortie d'hospitalisation";
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    final id = op.d<String>('sejour');
    base.exec('UPDATE sejours SET date_sortie=?, journees=? WHERE id=?', [op.dateOp, op.d('journees'), id]);
    final numero = base.valeur('SELECT numero FROM sejours WHERE id=?', [id]);
    final mj = op.d<int>('montant_journees');
    if (mj > 0) {
      Moteur.generer(base, op, 'prestation_credit',
          total: mj,
          lignes: [LigneMontant(mj, variables: {'produit': '7063'}, activite: 'HOSP')],
          tiers: op.d('patient'),
          activite: 'HOSP',
          libelle: 'Hospitalisation $numero : ${op.d('journees')} journée(s)');
    }
    final imp = op.d<int>('imputation_caution');
    if (imp > 0) {
      Moteur.generer(base, op, 'imputation_caution', total: imp, tiers: op.d('patient'), activite: 'HOSP', libelle: 'Caution déduite $numero');
    }
    final remb = op.d<int>('remboursement');
    if (remb > 0) {
      final treso = op.d<String>('tresorerie');
      Moteur.generer(base, op, 'remboursement_caution',
          total: remb, variables: Tresorerie.variables(base, treso), tiers: op.d('patient'), activite: 'HOSP', libelle: 'Remboursement caution $numero');
      Tresorerie.mouvement(base, op, treso, -remb, 'Remboursement de caution $numero');
    }
  }
}
