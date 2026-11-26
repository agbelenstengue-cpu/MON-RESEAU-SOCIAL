/// Personnel et paie (§6.12) : dossiers des employés (salariés et bénévoles
/// indemnisés), rubriques de cotisations datées et paramétrables (aucun taux
/// codé en dur), avances déduites automatiquement, bulletins, livre de paie,
/// écritures, paiement des salaires, congés.
library;

import 'dart:convert';

import '../../noyau/base.dart';
import '../../noyau/numerotation.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../comptabilite/moteur.dart';
import '../parametrage/parametrage.dart';
import '../tresorerie/tresorerie.dart';

class Paie {
  // ------------------------------------------------------------ rubriques (paramétrage)
  static void enregistrerRubrique(Session s,
          {required String code,
          required String libelle,
          required String nature,
          required String organisme,
          required int taux,
          int plafond = 0,
          String? depuis}) =>
      Parametrage.modifier(s, 'paie', 'rubrique:$code', () {
        if (!['retenue_salariale', 'charge_patronale'].contains(nature)) throw const RegleMetier('Nature : retenue_salariale ou charge_patronale.');
        if (!['CNPS', 'ETAT'].contains(organisme)) throw const RegleMetier('Organisme : CNPS ou ETAT.');
        if (taux < 0 || plafond < 0) throw const RegleMetier('Taux et plafond positifs.');
        final d = depuis ?? '${dateIso(s.base.maintenant).substring(0, 7)}-01';
        s.base.exec(
            'INSERT INTO rubriques_paie(code, depuis, libelle, nature, organisme, taux, plafond) VALUES (?,?,?,?,?,?,?) '
            'ON CONFLICT(code, depuis) DO UPDATE SET libelle=excluded.libelle, nature=excluded.nature, organisme=excluded.organisme, '
            'taux=excluded.taux, plafond=excluded.plafond, actif=1',
            [code.trim().toUpperCase(), d, libelle.trim(), nature, organisme, taux, plafond]);
      }, nouveau: {'libelle': libelle, 'taux': taux, 'plafond': plafond});

  /// Rubriques en vigueur pour une période (la plus récente version de chaque code).
  static List<Ligne> rubriques(Base b, String periode) => b.lignes(
      "SELECT r.* FROM rubriques_paie r WHERE r.actif=1 AND r.depuis = (SELECT MAX(depuis) FROM rubriques_paie x WHERE x.code=r.code AND x.depuis <= ?) "
      "ORDER BY r.nature DESC, r.code",
      ['$periode-31']);

  // ------------------------------------------------------------ employés
  static Operation enregistrerEmploye(Session s,
      {String? id,
      required String nom,
      required String entite,
      String poste = '',
      String? activite,
      String? embauche,
      String contrat = '',
      String statut = 'salarie',
      required int salaireBase,
      int primes = 0,
      String cnps = '',
      String paiement = '',
      bool actif = true}) {
    final b = s.base;
    return b.transaction(() {
      if (nom.trim().isEmpty) throw const RegleMetier("Le nom de l'employé est obligatoire.");
      if (!['salarie', 'benevole'].contains(statut)) throw const RegleMetier('Statut : salarié ou bénévole indemnisé.');
      if (salaireBase < 0 || primes < 0) throw const RegleMetier('Montants invalides.');
      final existant = id == null ? null : b.ligne('SELECT * FROM employes WHERE id=?', [id]);
      final matricule = existant?['matricule'] as String? ?? Numerotation.dossier(b, prefixe: 'EMP', exercice: b.maintenant.year);
      return Operations.enregistrer(s, type: 'employe', entite: entite, donnees: {
        'id': id ?? b.nouvelUuid(),
        'matricule': matricule,
        'nom': nom.trim(),
        'poste': poste,
        'activite': activite,
        'entite': entite,
        'embauche': embauche,
        'contrat': contrat,
        'statut': statut,
        'salaire_base': salaireBase,
        'primes': primes,
        'cnps': cnps,
        'paiement': paiement,
        'actif': actif ? 1 : 0,
      });
    });
  }

  static int avancesEnCours(Base b, String employe) => Moteur.solde(b, b.valeur('SELECT entite FROM employes WHERE id=?', [employe]) as String? ?? 'CS', '4211', tiers: employe);

  static Operation avance(Session s, {required String employe, required int montant, String mode = Modes.especes, String? reference}) {
    final b = s.base;
    return b.transaction(() {
      final e = b.ligne('SELECT * FROM employes WHERE id=? AND actif=1', [employe]) ?? (throw const RegleMetier('Employé introuvable.'));
      if (montant <= 0) throw const RegleMetier('Montant invalide.');
      final treso = Tresorerie.pourMode(b, e['entite'] as String, mode);
      Tresorerie.verifierReference(mode, reference);
      Tresorerie.verifierDisponible(b, treso, montant);
      return Operations.enregistrer(s, type: 'avance_salaire', entite: e['entite'] as String, typePiece: 'AVS', donnees: {
        'employe': employe,
        'montant': montant,
        'tresorerie': treso,
        'reference': reference,
      });
    });
  }

  /// Calcule la paie d'un mois pour une entité. [variables] : éléments du
  /// mois par employé (primes exceptionnelles, retenues diverses).
  static Operation calculer(Session s, {required String entite, required String periode, Map<String, (int, int)> variables = const {}}) {
    final b = s.base;
    return b.transaction(() {
      if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(periode)) throw const RegleMetier('Période : AAAA-MM.');
      if (b.valeur('SELECT 1 FROM bulletins WHERE periode=? AND annule=0 AND employe IN (SELECT id FROM employes WHERE entite=?)', [periode, entite]) != null) {
        throw RegleMetier('La paie de $periode est déjà calculée pour cette entité (annulez-la pour la refaire).');
      }
      final employes = b.lignes('SELECT * FROM employes WHERE entite=? AND actif=1 ORDER BY nom', [entite]);
      if (employes.isEmpty) throw const RegleMetier('Aucun employé actif.');
      final rubs = rubriques(b, periode);
      final bulletins = <Map<String, Object?>>[];
      for (final e in employes) {
        final (primesVar, retenuesDiv) = variables[e['id']] ?? (0, 0);
        final brut = (e['salaire_base'] as int) + (e['primes'] as int) + primesVar;
        final lignes = <Map<String, Object?>>[];
        var retenues = 0, patronales = 0, cnpsSal = 0, etatSal = 0, cnpsPat = 0, etatPat = 0;
        if (e['statut'] == 'salarie') {
          for (final r in rubs) {
            final plafond = r['plafond'] as int;
            final base = plafond > 0 && brut > plafond ? plafond : brut;
            final montant = (base * (r['taux'] as int) / 10000).round();
            if (montant == 0) continue;
            lignes.add({'code': r['code'], 'libelle': r['libelle'], 'nature': r['nature'], 'organisme': r['organisme'], 'base': base, 'taux': r['taux'], 'montant': montant});
            if (r['nature'] == 'retenue_salariale') {
              retenues += montant;
              r['organisme'] == 'CNPS' ? cnpsSal += montant : etatSal += montant;
            } else {
              patronales += montant;
              r['organisme'] == 'CNPS' ? cnpsPat += montant : etatPat += montant;
            }
          }
        }
        retenues += retenuesDiv;
        final avances = avancesEnCours(b, e['id'] as String);
        final netAvant = brut - retenues;
        final deduit = avances > netAvant ? (netAvant > 0 ? netAvant : 0) : avances;
        bulletins.add({
          'employe': e['id'],
          'nom': e['nom'],
          'base': e['salaire_base'],
          'primes': (e['primes'] as int) + primesVar,
          'brut': brut,
          'lignes': lignes,
          'retenues_diverses': retenuesDiv,
          'retenues': retenues,
          'cnps_salarial': cnpsSal,
          'etat_salarial': etatSal,
          'cnps_patronal': cnpsPat,
          'etat_patronal': etatPat,
          'patronales': patronales,
          'avances': deduit,
          'net': netAvant - deduit,
        });
      }
      return Operations.enregistrer(s, type: 'paie_mois', entite: entite, typePiece: 'PAIE', donnees: {'periode': periode, 'bulletins': bulletins});
    });
  }

  /// Net restant à payer à un employé (compte 4221).
  static int netAPayer(Base b, String entite, String employe) => -Moteur.solde(b, entite, '4221', tiers: employe);

  /// Paiement des salaires nets d'un mois.
  static Operation payer(Session s, {required String entite, required String periode, String mode = Modes.virement, String? reference}) {
    final b = s.base;
    return b.transaction(() {
      final dus = <Map<String, Object?>>[];
      for (final bu in b.lignes('SELECT b.employe FROM bulletins b JOIN employes e ON e.id=b.employe WHERE b.periode=? AND b.annule=0 AND e.entite=?', [periode, entite])) {
        final n = netAPayer(b, entite, bu['employe'] as String);
        if (n > 0) dus.add({'employe': bu['employe'], 'montant': n});
      }
      if (dus.isEmpty) throw const RegleMetier('Aucun salaire restant à payer pour cette période.');
      final total = dus.fold<int>(0, (t, d) => t + (d['montant'] as int));
      final treso = Tresorerie.pourMode(b, entite, mode);
      Tresorerie.verifierReference(mode, reference);
      Tresorerie.verifierDisponible(b, treso, total);
      return Operations.enregistrer(s, type: 'paiement_salaires', entite: entite, typePiece: 'DEC', donnees: {
        'periode': periode,
        'paiements': dus,
        'total': total,
        'tresorerie': treso,
        'reference': reference,
      });
    });
  }

  static Operation conge(Session s, {required String employe, required String debut, required String fin, String motif = ''}) {
    final e = s.base.ligne('SELECT * FROM employes WHERE id=?', [employe]) ?? (throw const RegleMetier('Employé introuvable.'));
    if (fin.compareTo(debut) < 0) throw const RegleMetier('La fin du congé précède son début.');
    return Operations.enregistrer(s, type: 'conge', entite: e['entite'] as String, donnees: {'employe': employe, 'debut': debut, 'fin': fin, 'motif': motif});
  }

  static void declarer() {
    Operations.declarer(_Employe());
    Operations.declarer(_Avance());
    Operations.declarer(_PaieMois());
    Operations.declarer(_Paiement());
    Operations.declarer(_Conge());
  }
}

class _Employe extends TypeOperation {
  @override
  String get type => 'employe';
  @override
  String get module => 'paie';
  @override
  String get libelle => 'Dossier employé';
  @override
  bool get annulable => false;
  @override
  void appliquer(Base base, Operation op) {
    final d = op.donnees;
    base.exec(
        'INSERT INTO employes(id, matricule, nom, poste, activite, entite, embauche, contrat, statut, salaire_base, primes, cnps, paiement, actif, uuid_op) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET nom=excluded.nom, poste=excluded.poste, activite=excluded.activite, '
        'embauche=excluded.embauche, contrat=excluded.contrat, statut=excluded.statut, salaire_base=excluded.salaire_base, primes=excluded.primes, '
        'cnps=excluded.cnps, paiement=excluded.paiement, actif=excluded.actif, uuid_op=excluded.uuid_op',
        [d['id'], d['matricule'], d['nom'], d['poste'], d['activite'], d['entite'], d['embauche'], d['contrat'], d['statut'], d['salaire_base'],
          d['primes'], d['cnps'], d['paiement'], d['actif'], op.uuid]);
  }
}

class _Avance extends TypeOperation {
  @override
  String get type => 'avance_salaire';
  @override
  String get module => 'paie';
  @override
  String get libelle => 'Avance sur salaire';
  @override
  void appliquer(Base base, Operation op) {
    final m = op.d<int>('montant');
    final treso = op.d<String>('tresorerie');
    final nom = base.valeur('SELECT nom FROM employes WHERE id=?', [op.d('employe')]) ?? '';
    Moteur.generer(base, op, 'avance_salaire', total: m, variables: Tresorerie.variables(base, treso), tiers: op.d('employe'), libelle: 'Avance sur salaire $nom');
    Tresorerie.mouvement(base, op, treso, -m, 'Avance sur salaire $nom', reference: op.d('reference'));
  }
}

class _PaieMois extends TypeOperation {
  @override
  String get type => 'paie_mois';
  @override
  String get module => 'paie';
  @override
  String get libelle => 'Paie du mois';

  @override
  void appliquer(Base base, Operation op) {
    final periode = op.d<String>('periode');
    final fin = Periode0.fin(periode);
    for (final bu in op.d<List>('bulletins').cast<Map>()) {
      final e = bu['employe'] as String;
      base.exec(
          'INSERT INTO bulletins(id, uuid_op, employe, periode, brut, retenues, avances, net, patronales, detail) VALUES (?,?,?,?,?,?,?,?,?,?) '
          'ON CONFLICT(id) DO UPDATE SET uuid_op=excluded.uuid_op, brut=excluded.brut, retenues=excluded.retenues, avances=excluded.avances, '
          'net=excluded.net, patronales=excluded.patronales, detail=excluded.detail, annule=0',
          ['$e#$periode', op.uuid, e, periode, bu['brut'], bu['retenues'], bu['avances'], bu['net'], bu['patronales'], jsonEncode(bu)]);
      final lib = 'Paie $periode : ${bu['nom']}';
      void ecr(String type, Object? m) {
        if ((m as int) > 0) Moteur.generer(base, op, type, total: m, tiers: e, libelle: lib, date: fin);
      }

      ecr('paie_brut', bu['brut']);
      ecr('paie_retenues_cnps', bu['cnps_salarial']);
      ecr('paie_retenues_etat', (bu['etat_salarial'] as int) + (bu['retenues_diverses'] as int));
      ecr('paie_patronales_cnps', bu['cnps_patronal']);
      ecr('paie_patronales_etat', bu['etat_patronal']);
      ecr('paie_avances', bu['avances']);
    }
  }

  @override
  void annuler(Base base, Operation cible, Operation annulation) => base.exec('UPDATE bulletins SET annule=1 WHERE uuid_op=?', [cible.uuid]);
}

class _Paiement extends TypeOperation {
  @override
  String get type => 'paiement_salaires';
  @override
  String get module => 'paie';
  @override
  String get libelle => 'Paiement des salaires';
  @override
  void appliquer(Base base, Operation op) {
    final treso = op.d<String>('tresorerie');
    for (final p in op.d<List>('paiements').cast<Map>()) {
      final nom = base.valeur('SELECT nom FROM employes WHERE id=?', [p['employe']]) ?? '';
      Moteur.generer(base, op, 'paiement_salaire',
          total: p['montant'] as int, variables: Tresorerie.variables(base, treso), tiers: p['employe'] as String, libelle: 'Salaire ${op.d('periode')} : $nom');
    }
    Tresorerie.mouvement(base, op, treso, -op.d<int>('total'), 'Salaires ${op.d('periode')}', reference: op.d('reference'));
  }
}

class _Conge extends TypeOperation {
  @override
  String get type => 'conge';
  @override
  String get module => 'paie';
  @override
  String get libelle => 'Congé';
  @override
  bool get horsJournee => true;
  @override
  void appliquer(Base base, Operation op) => base.exec('INSERT INTO conges(uuid_op, employe, debut, fin, motif) VALUES (?,?,?,?,?)',
      [op.uuid, op.d('employe'), op.d('debut'), op.d('fin'), op.d('motif')]);
  @override
  void annuler(Base base, Operation cible, Operation annulation) => base.exec('DELETE FROM conges WHERE uuid_op=?', [cible.uuid]);
}

class Periode0 {
  /// Dernier jour d'un mois AAAA-MM.
  static String fin(String periode) {
    final a = int.parse(periode.substring(0, 4)), m = int.parse(periode.substring(5, 7));
    return dateIso(DateTime.utc(a, m + 1, 0));
  }
}
