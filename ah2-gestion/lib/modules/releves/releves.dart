/// Relevé journalier des actes / des sorties (§7) : contrôle contradictoire.
///
/// Généré sur le PC central après synchronisation de tous les appareils, il
/// contient exactement les actes du service et de la date, tous appareils
/// confondus. Une fois généré, son contenu est figé.
library;

import 'dart:convert';

import '../../noyau/base.dart';
import '../../noyau/numerotation.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../cloture/cloture.dart';
import '../parametrage/parametrage.dart';
import '../tresorerie/tresorerie.dart';

class Releves {
  static const naturesEcart = ['non realise', 'realise non enregistre', 'montant different', 'autre'];

  /// Contenu calculé (lignes + synthèse) pour un service et une date.
  static Map<String, Object?> calculer(Base base, String activite, String date) {
    final actes = base.lignes(
        'SELECT a.*, p.numero_dossier FROM actes a LEFT JOIN patients p ON p.id=a.patient '
        'WHERE a.activite=? AND a.date=? AND a.annule=0 ORDER BY a.horodatage, a.piece, a.id',
        [activite, date]);
    final lignes = <Map<String, Object?>>[];
    final parMode = <String, int>{};
    var gratuites = 0;
    var encaisse = 0;
    for (final a in actes) {
      final mode = a['mode'] as String;
      final montant = a['montant'] as int;
      lignes.add({
        'n': lignes.length + 1,
        'heure': heureFr(DateTime.parse(a['horodatage'] as String)),
        'piece': a['piece'],
        'dossier': a['numero_dossier'] ?? '—',
        'acte': (a['quantite'] as int) > 1 ? '${a['libelle']} × ${a['quantite']}' : a['libelle'],
        'montant': montant,
        'mode': Modes.libelles[mode] ?? mode,
        'appareil': a['appareil'],
      });
      parMode[mode] = (parMode[mode] ?? 0) + montant;
      if (mode == Modes.gratuit) gratuites++;
      if (Modes.encaissables.contains(mode)) encaisse += montant;
    }
    return {
      'lignes': lignes,
      'synthese': {
        'nombre_actes': lignes.length,
        'par_mode': {for (final e in parMode.entries) Modes.libelles[e.key] ?? e.key: e.value},
        'gratuites': gratuites,
        'total_encaisse': encaisse,
        'total_general': lignes.fold<int>(0, (t, l) => t + (l['montant'] as int)),
      },
    };
  }

  static Operation generer(Session s, {required String activite, required String date}) {
    final base = s.base;
    return base.transaction(() {
      if (!Parametrage.estCentral(base)) throw const RegleMetier('Les relevés se génèrent sur le PC central.');
      s.exiger('releves', 'creer');
      final act = base.ligne('SELECT * FROM activites WHERE code=? AND service=1', [activite]) ??
          (throw RegleMetier("$activite n'est pas un service."));
      // Le relevé est figé : il ne peut porter que sur une journée terminée,
      // sinon des actes saisis ensuite manqueraient.
      if (date.compareTo(dateIso(base.maintenant)) >= 0) {
        throw const RegleMetier('Le relevé porte sur une journée terminée (par exemple, la veille).');
      }
      Cloture.exigerTousSynchronises(base, date);
      if (base.valeur('SELECT numero FROM releves WHERE activite=? AND date_actes=?', [activite, date]) != null) {
        throw const RegleMetier('Le relevé de ce service pour cette date existe déjà (il est figé).');
      }
      final exercice = int.parse(date.substring(0, 4));
      final prefixe = act['type_releve'] == 'sorties' ? 'RJS' : 'RJA';
      final n = Numerotation.suivant(base, entite: '*', typePiece: '$prefixe-$activite', exercice: exercice);
      final numero = '$prefixe-$activite-$exercice-${n.toString().padLeft(4, '0')}';
      return Operations.enregistrer(s, type: 'releve', entite: act['entite'] as String, donnees: {
        'numero': numero,
        'activite': activite,
        'libelle_service': act['libelle'],
        'titre': act['type_releve'] == 'sorties' ? 'RELEVÉ JOURNALIER DES SORTIES' : 'RELEVÉ JOURNALIER DES ACTES',
        'date_actes': date,
        'genere_par': s.nom,
        'contenu': calculer(base, activite, date),
      });
    });
  }

  /// Génère d'un coup les relevés de tous les services pour une date.
  static List<Operation> genererTous(Session s, String date) => [
        for (final a in s.base.lignes('SELECT code FROM activites WHERE service=1 ORDER BY code'))
          if (s.base.valeur('SELECT 1 FROM releves WHERE activite=? AND date_actes=?', [a['code'], date]) == null)
            generer(s, activite: a['code'] as String, date: date),
      ];

  /// Le comptable marque le relevé « Retourné signé » et joint le scan.
  static Operation marquerRetourne(Session s, String numero, {required String scan}) {
    final base = s.base;
    final r = base.ligne('SELECT * FROM releves WHERE numero=?', [numero]) ?? (throw const RegleMetier('Relevé introuvable.'));
    if (r['statut'] == 'retourne_signe') throw const RegleMetier('Ce relevé est déjà marqué retourné signé.');
    if (scan.isEmpty) throw const RegleMetier('Joignez la photo ou le scan du relevé signé.');
    return Operations.enregistrer(s, type: 'releve_retour', entite: 'CS', donnees: {'numero': numero, 'scan': scan});
  }

  static Operation saisirEcart(Session s,
      {required String releve, required String ligne, required String nature, String observation = ''}) {
    final base = s.base;
    return base.transaction(() {
      if (!naturesEcart.contains(nature)) throw RegleMetier("Nature d'écart : ${naturesEcart.join(', ')}.");
      if (base.valeur('SELECT 1 FROM releves WHERE numero=?', [releve]) == null) {
        throw const RegleMetier('Relevé introuvable.');
      }
      final n = Numerotation.suivant(base, entite: '*', typePiece: 'ECA', exercice: base.maintenant.year);
      return Operations.enregistrer(s, type: 'ecart_releve', entite: 'CS', donnees: {
        'numero': 'ECA-${base.appareil}-${base.maintenant.year}-${n.toString().padLeft(4, '0')}',
        'releve': releve,
        'ligne': ligne,
        'nature': nature,
        'observation': observation,
      });
    });
  }

  /// Suivi d'une fiche d'écart : justifié, ou régularisé par une opération corrective.
  static Operation suivreEcart(Session s, String numero, {required String statut, String? regularisation, String? observation}) {
    if (!['justifie', 'regularise'].contains(statut)) throw const RegleMetier('Statut : justifie ou regularise.');
    if (statut == 'regularise' && (regularisation == null || Operations.lire(s.base, regularisation) == null)) {
      throw const RegleMetier("Indiquez l'opération corrective qui régularise l'écart.");
    }
    return Operations.enregistrer(s,
        type: 'ecart_suivi',
        entite: 'CS',
        donnees: {'numero': numero, 'statut': statut, 'regularisation': regularisation, 'observation': observation});
  }

  /// Tableau de suivi : générés, retournés signés, en attente (jours de retard), avec écarts.
  static List<Map<String, Object?>> suivi(Base base) {
    final aujourdhui = dateIso(base.maintenant);
    return [
      for (final r in base.lignes('SELECT * FROM releves ORDER BY date_actes DESC, activite'))
        {
          ...r,
          'retard_jours': r['statut'] == 'genere' ? joursEntre((r['genere_le'] as String).substring(0, 10), aujourdhui) : 0,
          'ecarts_ouverts': base.entier("SELECT COUNT(*) FROM ecarts_releve WHERE releve=? AND statut='ouvert'", [r['numero']]),
          'ecarts': base.entier('SELECT COUNT(*) FROM ecarts_releve WHERE releve=?', [r['numero']]),
        }
    ];
  }

  static Map<String, Object?> contenu(Base base, String numero) =>
      jsonDecode(base.valeur('SELECT contenu FROM releves WHERE numero=?', [numero]) as String) as Map<String, Object?>;

  static void declarer() {
    Operations.declarer(_Releve());
    Operations.declarer(_Retour());
    Operations.declarer(_Ecart());
    Operations.declarer(_SuiviEcart());
  }
}

abstract class _Admin extends TypeOperation {
  @override
  String get module => 'releves';
  @override
  bool get annulable => false;
  @override
  bool get horsJournee => true;
}

class _Releve extends _Admin {
  @override
  String get type => 'releve';
  @override
  String get libelle => 'Relevé journalier';
  @override
  void appliquer(Base base, Operation op) => base.exec(
      'INSERT INTO releves(numero, activite, date_actes, genere_le, genere_par, contenu, uuid_op) VALUES (?,?,?,?,?,?,?)',
      [op.d('numero'), op.d('activite'), op.d('date_actes'), op.horodatage, op.d('genere_par'),
        jsonEncode({...op.d<Map>('contenu'), 'titre': op.d('titre'), 'service': op.d('libelle_service')}), op.uuid]);
}

class _Retour extends _Admin {
  @override
  String get type => 'releve_retour';
  @override
  String get libelle => 'Retour de relevé signé';
  @override
  void appliquer(Base base, Operation op) => base.exec(
      "UPDATE releves SET statut='retourne_signe', scan=? WHERE numero=?", [op.d('scan'), op.d('numero')]);
}

class _Ecart extends _Admin {
  @override
  String get type => 'ecart_releve';
  @override
  String get libelle => "Fiche d'écart";
  @override
  void appliquer(Base base, Operation op) => base.exec(
      'INSERT INTO ecarts_releve(numero, releve, ligne, nature, observation, uuid_op) VALUES (?,?,?,?,?,?)',
      [op.d('numero'), op.d('releve'), op.d('ligne'), op.d('nature'), op.d('observation'), op.uuid]);
}

class _SuiviEcart extends _Admin {
  @override
  String get type => 'ecart_suivi';
  @override
  String get libelle => "Suivi de fiche d'écart";
  @override
  void appliquer(Base base, Operation op) => base.exec(
      'UPDATE ecarts_releve SET statut=?, regularisation=?, observation=COALESCE(?, observation) WHERE numero=?',
      [op.d('statut'), op.d('regularisation'), op.d('observation'), op.d('numero')]);
}
