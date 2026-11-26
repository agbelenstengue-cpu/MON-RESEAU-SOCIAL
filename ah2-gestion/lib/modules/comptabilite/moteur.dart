/// Moteur d'écritures automatiques.
///
/// Chaque type d'opération est associé à un schéma d'écriture paramétrable
/// (table `schemas_ecritures`), propre à chaque entité : SYSCOHADA pour le
/// centre de santé, SYCEBNL pour l'ONG. Les comptes peuvent être des
/// variables ({tresorerie}, {produit}, {charge}…) résolues à partir de
/// l'opération. Toute écriture est contrôlée : débit = crédit.
library;

import '../../noyau/base.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';

/// Une ligne de détail (un acte, un produit…) pour les schémas « par_ligne ».
class LigneMontant {
  final int montant;
  final Map<String, String> variables;
  final String? activite;
  final String? subvention;
  const LigneMontant(this.montant, {this.variables = const {}, this.activite, this.subvention});
}

class Moteur {
  static final _variable = RegExp(r'\{([a-z_]+)\}');

  static String _resoudre(String modele, Map<String, String> vars) =>
      modele.replaceAllMapped(_variable, (m) {
        final v = vars[m[1]];
        if (v == null) throw StateError("Variable d'écriture non fournie : {${m[1]}}");
        return v;
      });

  /// Génère l'écriture de [typeEcriture] pour [op]. Renvoie l'id de
  /// l'écriture, ou null si le montant est nul (gratuité).
  static int? generer(
    Base base,
    Operation op,
    String typeEcriture, {
    required int total,
    List<LigneMontant> lignes = const [],
    Map<String, String> variables = const {},
    String? activite,
    String? subvention,
    String? tiers,
    required String libelle,
    String? entite,
    String? date,
  }) {
    final ent = entite ?? op.entite;
    final schema = base.lignes(
        'SELECT * FROM schemas_ecritures WHERE entite=? AND type_ecriture=? ORDER BY ordre', [ent, typeEcriture]);
    if (schema.isEmpty) {
      throw RegleMetier("Aucun schéma d'écriture « $typeEcriture » pour l'entité $ent (voir Paramétrage).");
    }
    if (total == 0 && lignes.every((l) => l.montant == 0)) return null;

    final produites = <Map<String, Object?>>[];
    String? journal;
    for (final s in schema) {
      final repete = s['repetition'] == 'par_ligne';
      final items = repete ? lignes : [LigneMontant(total, activite: activite, subvention: subvention)];
      for (final it in items) {
        final montant = s['montant'] == 'ligne' ? it.montant : total;
        if (montant == 0) continue;
        if (montant < 0) throw const RegleMetier('Montant négatif interdit dans une écriture.');
        final vars = {...variables, ...it.variables};
        final compte = _resoudre(s['compte'] as String, vars);
        journal ??= _resoudre(s['journal'] as String, vars);
        produites.add({
          'compte': compte,
          'debit': s['sens'] == 'D' ? montant : 0,
          'credit': s['sens'] == 'C' ? montant : 0,
          'activite': it.activite ?? activite,
          'subvention': it.subvention ?? subvention,
        });
      }
    }
    final d = produites.fold<int>(0, (a, l) => a + (l['debit'] as int));
    final c = produites.fold<int>(0, (a, l) => a + (l['credit'] as int));
    if (d != c) {
      throw RegleMetier('Écriture déséquilibrée ($typeEcriture) : débit ${fcfa(d)}, crédit ${fcfa(c)}.');
    }
    for (final l in produites) {
      if (base.valeur('SELECT 1 FROM comptes WHERE entite=? AND numero=? AND actif=1', [ent, l['compte']]) == null) {
        throw RegleMetier("Le compte ${l['compte']} n'existe pas (ou est inactif) dans le plan comptable de l'entité $ent.");
      }
    }
    if (base.valeur('SELECT 1 FROM journaux WHERE entite=? AND code=?', [ent, journal]) == null) {
      throw RegleMetier("Le journal $journal n'existe pas pour l'entité $ent.");
    }
    base.exec(
        'INSERT INTO ecritures(uuid_op, entite, journal, date, libelle, piece, utilisateur, appareil) VALUES (?,?,?,?,?,?,?,?)',
        [op.uuid, ent, journal, date ?? op.dateOp, libelle, op.piece, op.utilisateur, op.appareil]);
    final id = base.db.lastInsertRowId;
    for (final l in produites) {
      final compte = l['compte'] as String;
      final estTiers = compte.startsWith('40') || compte.startsWith('41') || compte.startsWith('46');
      base.exec(
          'INSERT INTO lignes_ecriture(ecriture, compte, debit, credit, activite, subvention, tiers) VALUES (?,?,?,?,?,?,?)',
          [id, compte, l['debit'], l['credit'], l['activite'], l['subvention'], estTiers ? tiers : null]);
    }
    return id;
  }

  /// Contre-passe (inverse) toutes les écritures produites par [cible].
  static void contrePasser(Base base, Operation cible, Operation annulation) {
    final ecr = base.lignes('SELECT * FROM ecritures WHERE uuid_op=? AND contre_passation=0', [cible.uuid]);
    for (final e in ecr) {
      base.exec(
          'INSERT INTO ecritures(uuid_op, entite, journal, date, libelle, piece, utilisateur, appareil, contre_passation) VALUES (?,?,?,?,?,?,?,?,1)',
          [annulation.uuid, e['entite'], e['journal'], annulation.dateOp, 'Annulation : ${e['libelle']}', annulation.piece,
            annulation.utilisateur, annulation.appareil]);
      final id = base.db.lastInsertRowId;
      for (final l in base.lignes('SELECT * FROM lignes_ecriture WHERE ecriture=?', [e['id']])) {
        base.exec(
            'INSERT INTO lignes_ecriture(ecriture, compte, debit, credit, activite, subvention, tiers) VALUES (?,?,?,?,?,?,?)',
            [id, l['compte'], l['credit'], l['debit'], l['activite'], l['subvention'], l['tiers']]);
      }
    }
  }

  /// Solde (débit - crédit) d'un compte ou d'une racine de comptes.
  static int solde(Base base, String entite, String racine, {String? tiers, String? jusquau}) {
    final p = <Object?>[entite, '$racine%'];
    var sql = 'SELECT COALESCE(SUM(l.debit - l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture '
        'WHERE e.entite=? AND l.compte LIKE ?';
    if (tiers != null) {
      sql += ' AND l.tiers=?';
      p.add(tiers);
    }
    if (jusquau != null) {
      sql += ' AND e.date<=?';
      p.add(jusquau);
    }
    return base.entier(sql, p);
  }

  /// Liste des écritures déséquilibrées (doit toujours être vide).
  static List<int> ecrituresDesequilibrees(Base base) => base
      .lignes('SELECT e.id FROM ecritures e JOIN lignes_ecriture l ON l.ecriture=e.id '
          'GROUP BY e.id HAVING SUM(l.debit) <> SUM(l.credit)')
      .map((l) => l['id'] as int)
      .toList();

  /// Balance générale d'une entité sur une période.
  static List<Ligne> balance(Base base, String entite, {required String du, required String au}) => base.lignes(
      'SELECT l.compte, c.libelle, SUM(l.debit) AS debit, SUM(l.credit) AS credit, SUM(l.debit-l.credit) AS solde '
      'FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture '
      'LEFT JOIN comptes c ON c.entite=e.entite AND c.numero=l.compte '
      'WHERE e.entite=? AND e.date BETWEEN ? AND ? GROUP BY l.compte ORDER BY l.compte',
      [entite, du, au]);
}
