/// Comptabilité générale : saisie d'opérations diverses et d'à-nouveaux,
/// clôture d'exercice, rapprochement bancaire, lettrage des tiers.
library;

import '../../noyau/base.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../tresorerie/tresorerie.dart';
import 'moteur.dart';

/// Une ligne saisie : compte, débit ou crédit, activité et tiers éventuels.
class LigneSaisie {
  final String compte;
  final int debit;
  final int credit;
  final String? activite;
  final String? tiers;
  const LigneSaisie(this.compte, {this.debit = 0, this.credit = 0, this.activite, this.tiers});
  Map<String, Object?> versJson() => {'compte': compte, 'debit': debit, 'credit': credit, 'activite': activite, 'tiers': tiers};
}

class Comptabilite {
  /// Opération diverse saisie par le comptable (contrôle débit = crédit).
  /// Avec [journal] = 'AN', elle sert à saisir les soldes d'ouverture.
  static Operation saisir(Session s,
      {required String entite, required String journal, required String libelle, required List<LigneSaisie> lignes}) {
    if (s.role != 'comptable') throw const DroitRefuse('La saisie manuelle est réservée au comptable.');
    if (libelle.trim().isEmpty) throw const RegleMetier('Le libellé est obligatoire.');
    return Operations.enregistrer(s,
        type: 'ecriture_manuelle',
        entite: entite,
        typePiece: journal == 'AN' ? 'AN' : 'OD',
        donnees: {'journal': journal, 'libelle': libelle.trim(), 'lignes': [for (final l in lignes) l.versJson()]});
  }

  /// Clôture de l'exercice : solde les comptes de charges et de produits
  /// vers le résultat (bénéfice/excédent ou perte/déficit) et verrouille l'année.
  static Operation cloturerExercice(Session s, {required String entite, required int annee}) {
    final base = s.base;
    if (s.role != 'comptable') throw const DroitRefuse("La clôture de l'exercice est réservée au comptable.");
    if ('$annee-12-31'.compareTo(dateIso(base.maintenant)) >= 0) throw const RegleMetier("L'exercice n'est pas terminé.");
    if (base.valeur("SELECT 1 FROM periodes_verrouillees WHERE entite=? AND periode=?", [entite, '$annee']) != null) {
      throw const RegleMetier('Cet exercice est déjà clôturé.');
    }
    return Operations.enregistrer(s, type: 'cloture_exercice', entite: entite, typePiece: 'CL', donnees: {'annee': annee});
  }

  /// Relevé bancaire (solde à une date) pour le rapprochement.
  static Operation saisirReleveBancaire(Session s, {required String tresorerie, required String date, required int solde, String reference = ''}) {
    final t = Tresorerie.compte(s.base, tresorerie);
    if (t['type'] == 'caisse') throw const RegleMetier('Le rapprochement concerne une banque ou un compte mobile money.');
    return Operations.enregistrer(s,
        type: 'releve_bancaire', entite: t['entite'] as String, donnees: {'tresorerie': tresorerie, 'date': date, 'solde': solde, 'reference': reference});
  }

  /// Pointe des mouvements (clé « uuid:rang ») comme présents sur le relevé.
  static Operation pointer(Session s, {required String entite, required List<String> mouvements, String? releve}) {
    if (mouvements.isEmpty) throw const RegleMetier('Sélectionnez au moins un mouvement.');
    return Operations.enregistrer(s, type: 'pointage', entite: entite, donnees: {'mouvements': mouvements, 'releve': releve});
  }

  /// Mouvements d'un compte de trésorerie avec leur clé stable et leur pointage.
  static List<Ligne> mouvementsAvecCle(Base base, String tresorerie, {String? jusquau}) {
    final pointes = {for (final p in base.lignes('SELECT mouvement FROM pointages')) p['mouvement'] as String};
    return [
      for (final m in base.lignes(
          "SELECT m.*, m.uuid_op || ':' || (SELECT COUNT(*) FROM mouvements_tresorerie m2 "
          "WHERE m2.uuid_op=m.uuid_op AND m2.tresorerie=m.tresorerie AND m2.id<=m.id) AS cle "
          "FROM mouvements_tresorerie m WHERE m.tresorerie=? ${jusquau != null ? 'AND m.date<=?' : ''} ORDER BY m.date, m.id",
          [tresorerie, ?jusquau]))
        {...m, 'pointe': pointes.contains(m['cle'])}
    ];
  }

  /// Lignes d'un compte de tiers avec leur clé stable et leur lettrage.
  static List<Ligne> lignesTiers(Base base, String entite, String compte, String tiers) => base.lignes(
      "SELECT * FROM (SELECT l.*, e.date, e.libelle, e.piece, e.uuid_op || ':' || "
      "ROW_NUMBER() OVER (PARTITION BY e.uuid_op ORDER BY l.id) AS cle "
      "FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE e.entite=?) x "
      "LEFT JOIN lettrages t ON t.ligne=x.cle WHERE x.compte=? AND x.tiers=? ORDER BY x.date, x.id",
      [entite, compte, tiers]);

  /// Lettrage : rapproche des lignes d'un même tiers dont le solde est nul.
  static Operation lettrer(Session s, {required String entite, required String compte, required String tiers, required List<String> lignes}) {
    final base = s.base;
    final toutes = {for (final l in lignesTiers(base, entite, compte, tiers)) l['cle'] as String: l};
    var solde = 0;
    for (final c in lignes) {
      final l = toutes[c] ?? (throw const RegleMetier('Ligne inconnue pour ce tiers.'));
      if (l['code'] != null) throw const RegleMetier('Une des lignes est déjà lettrée.');
      solde += (l['debit'] as int) - (l['credit'] as int);
    }
    if (lignes.length < 2 || solde != 0) throw const RegleMetier('Les lignes à lettrer doivent avoir un solde nul (débits = crédits).');
    final n = base.entier('SELECT COUNT(DISTINCT code) FROM lettrages') + 1;
    return Operations.enregistrer(s, type: 'lettrage', entite: entite, donnees: {'lignes': lignes, 'code': _code(n)});
  }

  static String _code(int n) {
    var s = '';
    while (n > 0) {
      s = String.fromCharCode(65 + (n - 1) % 26) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static void declarer() {
    Operations.declarer(_Manuelle());
    Operations.declarer(_ClotureExercice());
    Operations.declarer(_Releve());
    Operations.declarer(_Pointage());
    Operations.declarer(_Lettrage());
  }
}

class _Manuelle extends TypeOperation {
  @override
  String get type => 'ecriture_manuelle';
  @override
  String get module => 'comptabilite';
  @override
  String get libelle => 'Écriture manuelle';
  @override
  void appliquer(Base base, Operation op) => Moteur.ecrireLibre(base, op,
      entite: op.entite, journal: op.d('journal'), libelle: op.d('libelle'), lignes: op.d<List>('lignes').cast<Map>());
}

class _ClotureExercice extends TypeOperation {
  @override
  String get type => 'cloture_exercice';
  @override
  String get module => 'comptabilite';
  @override
  String get libelle => "Clôture de l'exercice";
  @override
  bool get annulable => false;
  @override
  bool get horsJournee => true;

  @override
  void appliquer(Base base, Operation op) {
    final annee = op.d<int>('annee');
    final soldes = base.lignes(
        "SELECT l.compte, SUM(l.debit - l.credit) AS solde FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture "
        "WHERE e.entite=? AND e.date BETWEEN ? AND ? AND e.journal <> 'CL' "
        "AND (l.compte LIKE '6%' OR l.compte LIKE '7%' OR l.compte LIKE '8%') GROUP BY l.compte HAVING solde <> 0",
        [op.entite, '$annee-01-01', '$annee-12-31']);
    final lignes = <Map>[];
    var resultat = 0; // positif = bénéfice
    for (final s in soldes) {
      final v = s['solde'] as int;
      resultat -= v;
      lignes.add({'compte': s['compte'], 'debit': v < 0 ? -v : 0, 'credit': v > 0 ? v : 0});
    }
    if (resultat > 0) lignes.add({'compte': '1311', 'debit': 0, 'credit': resultat});
    if (resultat < 0) lignes.add({'compte': '1391', 'debit': -resultat, 'credit': 0});
    if (lignes.length >= 2) {
      Moteur.ecrireLibre(base, op, entite: op.entite, journal: 'CL', libelle: "Détermination du résultat de l'exercice $annee", lignes: lignes, date: '$annee-12-31');
    }
    base.exec('INSERT OR IGNORE INTO periodes_verrouillees(entite, periode, uuid_op) VALUES (?,?,?)', [op.entite, '$annee', op.uuid]);
  }
}

class _Releve extends TypeOperation {
  @override
  String get type => 'releve_bancaire';
  @override
  String get module => 'comptabilite';
  @override
  String get libelle => 'Relevé bancaire';
  @override
  bool get horsJournee => true;
  @override
  void appliquer(Base base, Operation op) => base.exec(
      'INSERT INTO releves_bancaires(uuid_op, tresorerie, date, solde, reference) VALUES (?,?,?,?,?)',
      [op.uuid, op.d('tresorerie'), op.d('date'), op.d('solde'), op.d('reference')]);
}

class _Pointage extends TypeOperation {
  @override
  String get type => 'pointage';
  @override
  String get module => 'comptabilite';
  @override
  String get libelle => 'Pointage bancaire';
  @override
  bool get horsJournee => true;
  @override
  void appliquer(Base base, Operation op) {
    for (final m in op.d<List>('mouvements').cast<String>()) {
      base.exec('INSERT OR IGNORE INTO pointages(mouvement, uuid_op, releve) VALUES (?,?,?)', [m, op.uuid, op.d('releve')]);
    }
  }

  @override
  void annuler(Base base, Operation cible, Operation annulation) => base.exec('DELETE FROM pointages WHERE uuid_op=?', [cible.uuid]);
}

class _Lettrage extends TypeOperation {
  @override
  String get type => 'lettrage';
  @override
  String get module => 'comptabilite';
  @override
  String get libelle => 'Lettrage';
  @override
  bool get horsJournee => true;
  @override
  void appliquer(Base base, Operation op) {
    for (final l in op.d<List>('lignes').cast<String>()) {
      base.exec('INSERT OR IGNORE INTO lettrages(ligne, code, uuid_op) VALUES (?,?,?)', [l, op.d('code'), op.uuid]);
    }
  }

  @override
  void annuler(Base base, Operation cible, Operation annulation) => base.exec('DELETE FROM lettrages WHERE uuid_op=?', [cible.uuid]);
}
