/// Dons et subventions (§6.14), comptabilité de l'ONG (SYCEBNL).
library;

import 'dart:convert';

import '../../noyau/base.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../comptabilite/moteur.dart';
import '../tresorerie/tresorerie.dart';

class Dons {
  static const typesDonateur = ['particulier', 'membre', 'entreprise', 'fondation', 'organisme public'];
  static const natures = ['especes', 'virement', 'mtn', 'orange', 'cheque', 'nature'];

  static Operation creerDonateur(Session s,
      {required String nom,
      required String type,
      String responsable = '',
      String adresse = '',
      String telephone = '',
      String pays = 'Cameroun'}) {
    if (nom.trim().isEmpty) throw const RegleMetier('Le nom du donateur est obligatoire.');
    if (!typesDonateur.contains(type)) throw RegleMetier('Type de donateur : ${typesDonateur.join(', ')}.');
    return Operations.enregistrer(s, type: 'donateur', entite: 'ONG', donnees: {
      'id': s.base.nouvelUuid(),
      'nom': nom.trim(),
      'type': type,
      'responsable': responsable,
      'adresse': adresse,
      'telephone': telephone,
      'pays': pays,
    });
  }

  /// Enregistre un don ; un reçu numéroté est remis au donateur.
  static Operation recevoir(Session s,
      {required String donateur,
      required int montant,
      required String nature,
      String description = '',
      String? affectation,
      String? subvention,
      String? reference,
      String compteActif = '3111'}) {
    final base = s.base;
    return base.transaction(() {
      if (base.valeur('SELECT 1 FROM donateurs WHERE id=?', [donateur]) == null) {
        throw const RegleMetier('Donateur introuvable.');
      }
      if (!natures.contains(nature)) throw RegleMetier('Nature du don : ${natures.join(', ')}.');
      if (montant <= 0) throw const RegleMetier('Le montant (ou la valeur estimée) doit être positif.');
      if (nature == 'nature' && description.trim().isEmpty) {
        throw const RegleMetier('Décrivez le don en nature (biens reçus).');
      }
      final mode = nature == 'nature' ? null : (nature == 'especes' ? Modes.especes : nature);
      if (mode != null) Tresorerie.verifierReference(mode, reference);
      return Operations.enregistrer(s, type: 'don', entite: 'ONG', typePiece: 'DON', donnees: {
        'donateur': donateur,
        'montant': montant,
        'nature': nature,
        'description': description,
        'affectation': affectation,
        'subvention': subvention,
        'reference': reference,
        'tresorerie': mode == null ? null : Tresorerie.pourMode(base, 'ONG', mode),
        'compte_actif': nature == 'nature' ? compteActif : null,
      });
    });
  }

  static Operation creerSubvention(Session s,
      {required String reference,
      required String bailleur,
      required int montant,
      required String debut,
      required String fin,
      String? programme,
      String conditions = '',
      required List<Map<String, Object>> budget,
      required List<Map<String, Object>> tranches}) {
    final base = s.base;
    if (base.valeur('SELECT 1 FROM subventions WHERE reference=?', [reference]) != null) {
      throw RegleMetier('La convention $reference existe déjà.');
    }
    final b = budget.fold<int>(0, (t, l) => t + (l['montant'] as int));
    final tr = tranches.fold<int>(0, (t, l) => t + (l['montant'] as int));
    if (b != montant) throw RegleMetier('Le budget (${fcfa(b)}) doit être égal au montant accordé (${fcfa(montant)}).');
    if (tr != montant) throw RegleMetier('Les tranches (${fcfa(tr)}) doivent totaliser le montant accordé.');
    return Operations.enregistrer(s, type: 'subvention', entite: 'ONG', donnees: {
      'id': base.nouvelUuid(),
      'reference': reference,
      'bailleur': bailleur,
      'montant': montant,
      'debut': debut,
      'fin': fin,
      'programme': programme,
      'conditions': conditions,
      'budget': budget,
      'tranches': tranches,
    });
  }

  static Operation recevoirTranche(Session s,
      {required String subvention, required int montant, required String mode, String? reference}) {
    final base = s.base;
    return base.transaction(() {
      final sub = base.ligne('SELECT * FROM subventions WHERE id=?', [subvention]) ??
          (throw const RegleMetier('Subvention introuvable.'));
      final recu = base.entier(
          'SELECT COALESCE(SUM(montant),0) FROM subventions_tranches_recues WHERE subvention=? AND annule=0', [subvention]);
      if (recu + montant > (sub['montant_accorde'] as int)) {
        throw const RegleMetier('Le total reçu dépasserait le montant accordé.');
      }
      Tresorerie.verifierReference(mode, reference);
      return Operations.enregistrer(s, type: 'subvention_tranche', entite: 'ONG', typePiece: 'SUB', donnees: {
        'subvention': subvention,
        'montant': montant,
        'mode': mode,
        'reference': reference,
        'tresorerie': Tresorerie.pourMode(base, 'ONG', mode),
      });
    });
  }

  /// Suivi budget / réalisé / solde par ligne. Les dépenses sont rattachées
  /// avec le code « idSubvention#ligne ».
  static List<Map<String, Object?>> suiviSubvention(Base base, String subvention) {
    final sub = base.ligne('SELECT * FROM subventions WHERE id=?', [subvention])!;
    final budget = (jsonDecode(sub['budget'] as String) as List).cast<Map>();
    return [
      for (final l in budget)
        () {
          final realise = base.entier(
              "SELECT COALESCE(SUM(l.debit - l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture "
              "WHERE e.entite='ONG' AND l.subvention=? AND l.compte LIKE '6%'",
              ['$subvention#${l['ligne']}']);
          return {
            'ligne': l['ligne'],
            'libelle': l['libelle'],
            'budget': l['montant'],
            'realise': realise,
            'solde': (l['montant'] as int) - realise,
          };
        }(),
    ];
  }

  static void declarer() {
    Operations.declarer(_Donateur());
    Operations.declarer(_Don());
    Operations.declarer(_Subvention());
    Operations.declarer(_Tranche());
  }
}

class _Donateur extends TypeOperation {
  @override
  String get type => 'donateur';
  @override
  String get module => 'dons';
  @override
  String get libelle => 'Fiche donateur';
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    final d = op.donnees;
    base.exec(
        'INSERT INTO donateurs(id, nom, responsable, adresse, telephone, pays, type, uuid_op) VALUES (?,?,?,?,?,?,?,?)',
        [d['id'], d['nom'], d['responsable'], d['adresse'], d['telephone'], d['pays'], d['type'], op.uuid]);
  }
}

class _Don extends TypeOperation {
  @override
  String get type => 'don';
  @override
  String get module => 'dons';
  @override
  String get libelle => 'Don';

  @override
  void appliquer(Base base, Operation op) {
    final m = op.d<int>('montant');
    base.exec(
        'INSERT INTO dons(uuid_op, piece, donateur, date, montant, nature, description, affectation, subvention) VALUES (?,?,?,?,?,?,?,?,?)',
        [op.uuid, op.piece, op.d('donateur'), op.dateOp, m, op.d('nature'), op.d('description'), op.d('affectation'), op.d('subvention')]);
    final nom = base.valeur('SELECT nom FROM donateurs WHERE id=?', [op.d('donateur')]) ?? '';
    final activite = op.d<String?>('affectation') ?? 'PROG';
    if (op.d('nature') == 'nature') {
      Moteur.generer(base, op, 'don_nature',
          total: m, variables: {'compte_actif': op.d<String>('compte_actif')}, activite: activite, libelle: 'Don en nature : $nom');
    } else {
      final treso = op.d<String>('tresorerie');
      Moteur.generer(base, op, 'don_numeraire',
          total: m, variables: Tresorerie.variables(base, treso), activite: activite, libelle: 'Don : $nom');
      Tresorerie.mouvement(base, op, treso, m, 'Don : $nom', reference: op.d('reference'));
    }
  }

  @override
  void annuler(Base base, Operation cible, Operation annulation) =>
      base.exec('UPDATE dons SET annule=1 WHERE uuid_op=?', [cible.uuid]);
}

class _Subvention extends TypeOperation {
  @override
  String get type => 'subvention';
  @override
  String get module => 'dons';
  @override
  String get libelle => 'Convention de subvention';
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    final d = op.donnees;
    base.exec(
        'INSERT INTO subventions(id, reference, bailleur, montant_accorde, debut, fin, programme, conditions, budget, tranches, uuid_op) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        [d['id'], d['reference'], d['bailleur'], d['montant'], d['debut'], d['fin'], d['programme'], d['conditions'],
          jsonEncode(d['budget']), jsonEncode(d['tranches']), op.uuid]);
  }
}

class _Tranche extends TypeOperation {
  @override
  String get type => 'subvention_tranche';
  @override
  String get module => 'dons';
  @override
  String get libelle => 'Tranche de subvention';

  @override
  void appliquer(Base base, Operation op) {
    final m = op.d<int>('montant');
    final treso = op.d<String>('tresorerie');
    final ref = base.valeur('SELECT reference FROM subventions WHERE id=?', [op.d('subvention')]) ?? '';
    base.exec('INSERT INTO subventions_tranches_recues(uuid_op, subvention, date, montant, piece) VALUES (?,?,?,?,?)',
        [op.uuid, op.d('subvention'), op.dateOp, m, op.piece]);
    Moteur.generer(base, op, 'subvention_tranche',
        total: m, variables: Tresorerie.variables(base, treso), subvention: op.d('subvention'), activite: 'PROG',
        libelle: 'Tranche subvention $ref');
    Tresorerie.mouvement(base, op, treso, m, 'Tranche subvention $ref', reference: op.d('reference'));
  }

  @override
  void annuler(Base base, Operation cible, Operation annulation) =>
      base.exec('UPDATE subventions_tranches_recues SET annule=1 WHERE uuid_op=?', [cible.uuid]);
}
