/// Journal des opérations : le cœur de la saisie unique et de la synchronisation.
///
/// Toute action de gestion (encaissement, versement, dépense, don…) est une
/// [Operation] immuable, identifiée par un UUID. L'enregistrer :
///   1. vérifie les droits, la date (non clôturée) et l'état de l'appareil ;
///   2. attribue le numéro de pièce (sans trou) ;
///   3. applique l'opération : écriture comptable, caisse, créances… ;
///   4. trace l'action dans le journal d'audit.
/// Le tout dans UNE transaction. La synchronisation recopie les opérations
/// (jamais les résultats) : chaque base les applique de la même manière, ce
/// qui garantit l'absence de perte et de doublon (UUID unique).
library;

import 'dart:convert';

import '../modules/comptabilite/moteur.dart';
import 'audit.dart';
import 'base.dart';
import 'numerotation.dart';
import 'outils.dart';
import 'session.dart';

class Operation {
  final String uuid;
  final String type;
  final String entite;
  final String appareil;
  final String utilisateur;
  final String horodatage;
  final String dateOp;
  final String? piece;
  final Map<String, Object?> donnees;
  final String origine;

  Operation({
    required this.uuid,
    required this.type,
    required this.entite,
    required this.appareil,
    required this.utilisateur,
    required this.horodatage,
    required this.dateOp,
    required this.piece,
    required this.donnees,
    this.origine = 'locale',
  });

  int get exercice => int.parse(dateOp.substring(0, 4));
  DateTime get instant => DateTime.parse(horodatage);

  T d<T>(String cle) => donnees[cle] as T;

  Map<String, Object?> versJson() => {
        'uuid': uuid,
        'type': type,
        'entite': entite,
        'appareil': appareil,
        'utilisateur': utilisateur,
        'horodatage': horodatage,
        'date_op': dateOp,
        'piece': piece,
        'donnees': donnees,
      };

  factory Operation.depuisJson(Map<String, Object?> j, {String origine = 'synchronisee'}) => Operation(
        uuid: j['uuid'] as String,
        type: j['type'] as String,
        entite: j['entite'] as String,
        appareil: j['appareil'] as String,
        utilisateur: j['utilisateur'] as String,
        horodatage: j['horodatage'] as String,
        dateOp: j['date_op'] as String,
        piece: j['piece'] as String?,
        donnees: Map<String, Object?>.from(j['donnees'] as Map),
        origine: origine,
      );

  factory Operation.depuisLigne(Ligne l) => Operation(
        uuid: l['uuid'] as String,
        type: l['type'] as String,
        entite: l['entite'] as String,
        appareil: l['appareil'] as String,
        utilisateur: l['utilisateur'] as String,
        horodatage: l['horodatage'] as String,
        dateOp: l['date_op'] as String,
        piece: l['piece'] as String?,
        donnees: Map<String, Object?>.from(jsonDecode(l['donnees'] as String) as Map),
        origine: l['origine'] as String,
      );
}

/// Définition d'un type d'opération : comment l'appliquer et comment
/// l'annuler (marquage des vues dérivées ; la contre-passation comptable et
/// l'inversion des mouvements de trésorerie sont automatiques).
abstract class TypeOperation {
  String get type;

  /// Module de droits (caisse, desintox, dons…).
  String get module;

  /// Action requise pour la saisir (creer en général).
  String get action => 'creer';

  /// Libellé lisible (journal d'audit, listes).
  String get libelle;

  bool get annulable => true;

  /// Opération purement administrative : autorisée même sur une journée clôturée
  /// (clôture, réouverture, retour de relevé signé…).
  bool get horsJournee => false;

  void appliquer(Base base, Operation op);

  void annuler(Base base, Operation cible, Operation annulation) {}
}

class Operations {
  static final Map<String, TypeOperation> _registre = {};

  static void declarer(TypeOperation t) => _registre[t.type] = t;

  static TypeOperation typeDe(String type) =>
      _registre[type] ?? (throw StateError("Type d'opération inconnu : $type"));

  static bool _initialise = false;

  /// Déclare l'opération d'annulation (les modules déclarent les leurs).
  static void initialiser() {
    if (_initialise) return;
    _initialise = true;
    declarer(_Annulation());
  }

  /// Vérifie qu'on peut saisir sur cet appareil, pour cette entité, à cette date.
  static void verifierSaisie(Base base, String entite, String dateOp) {
    final app = base.ligne('SELECT * FROM appareils WHERE code=?', [base.appareil]);
    if (app == null || app['statut'] != 'autorise') {
      throw const RegleMetier("Cet appareil n'est pas autorisé. Contactez l'administrateur.");
    }
    if (app['central'] != 1) {
      final derniere = base.valeur("SELECT valeur FROM etat_sync WHERE cle='derniere_sync'") as String?;
      final reference = derniere ?? base.valeur("SELECT valeur FROM etat_sync WHERE cle='installe_le'") as String?;
      if (reference != null) {
        final jours = base.maintenantReel.difference(DateTime.parse(reference)).inHours / 24;
        if (jours > base.paramInt('sync_jours_max')) {
          throw RegleMetier(
              "Lecture seule : aucune synchronisation depuis plus de ${base.paramInt('sync_jours_max')} jours. "
              'Connectez-vous au Wi-Fi de la structure et synchronisez.');
        }
      }
    }
    if (estCloturee(base, entite, dateOp)) {
      throw RegleMetier('La journée du ${dateFr(depuisIso(dateOp))} est clôturée : aucune saisie possible.');
    }
    final mois = dateOp.substring(0, 7);
    final annee = dateOp.substring(0, 4);
    if (base.valeur('SELECT 1 FROM periodes_verrouillees WHERE entite=? AND periode IN (?,?)',
            [entite, mois, annee]) !=
        null) {
      throw RegleMetier('La période $mois est verrouillée.');
    }
  }

  static bool estCloturee(Base base, String entite, String dateOp) =>
      base.valeur('SELECT cloture FROM clotures WHERE entite=? AND date=?', [entite, dateOp]) == 1;

  /// Enregistre une nouvelle opération saisie sur cet appareil.
  static Operation enregistrer(
    Session s, {
    required String type,
    required String entite,
    required Map<String, Object?> donnees,
    String? typePiece,
  }) {
    initialiser();
    // (les données peuvent être complétées : saisie rétroactive)
    final t = typeDe(type);
    final base = s.base;
    return base.transaction(() {
      if (type == 'annulation') {
        final cible = lire(base, donnees['cible'] as String);
        if (cible == null) throw const RegleMetier('Opération introuvable.');
        s.exiger(typeDe(cible.type).module, 'annuler');
      } else {
        s.exiger(t.module, t.action);
      }
      final maintenant = base.maintenant;
      final dateOp = dateIso(maintenant);
      final retroactif = base.dateSaisie != null && base.dateSaisie != dateIso(base.maintenantReel);
      if (retroactif) {
        // Saisie à une date passée : droit dédié, jamais dans le futur.
        if (!s.peut('retroactif', 'creer')) {
          throw const DroitRefuse("Vous n'avez pas le droit de saisir à une date passée.");
        }
        if (dateOp.compareTo(dateIso(base.maintenantReel)) > 0) {
          throw const RegleMetier('On ne peut pas saisir une opération à une date future.');
        }
        donnees = {...donnees, '_saisi_le': base.maintenantReel.toIso8601String()};
      }
      if (!t.horsJournee) {
        verifierSaisie(base, entite, dateOp);
      } else {
        final app = base.ligne('SELECT statut FROM appareils WHERE code=?', [base.appareil]);
        if (app == null || app['statut'] != 'autorise') {
          throw const RegleMetier("Cet appareil n'est pas autorisé.");
        }
      }
      final piece = typePiece == null
          ? null
          : Numerotation.piece(base, entite: entite, typePiece: typePiece, exercice: maintenant.year);
      final op = Operation(
        uuid: base.nouvelUuid(),
        type: type,
        entite: entite,
        appareil: base.appareil,
        utilisateur: s.utilisateur,
        horodatage: maintenant.toIso8601String(),
        dateOp: dateOp,
        piece: piece,
        donnees: donnees,
      );
      _inserer(base, op);
      t.appliquer(base, op);
      Audit.tracer(base,
          utilisateur: s.utilisateur,
          action: type == 'annulation' ? 'annulation' : 'creation',
          objet: '${t.libelle}${piece != null ? ' $piece' : ''} [${op.uuid}]',
          nouveau: _sansContenu(donnees));
      return op;
    });
  }

  static void _inserer(Base base, Operation op) => base.exec(
      'INSERT INTO operations(uuid, type, entite, appareil, utilisateur, horodatage, date_op, piece, donnees, origine, recu_le) '
      'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
      [
        op.uuid,
        op.type,
        op.entite,
        op.appareil,
        op.utilisateur,
        op.horodatage,
        op.dateOp,
        op.piece,
        jsonEncode(op.donnees),
        op.origine,
        base.maintenantReel.toIso8601String(),
      ]);

  /// Intègre une opération reçue par synchronisation. Idempotent : une
  /// opération déjà connue (même UUID) est ignorée. Renvoie true si nouvelle.
  /// Une opération reçue n'est JAMAIS rejetée (rien ne se perd) : les
  /// incohérences deviennent des anomalies à traiter par le comptable.
  static bool importer(Base base, Operation op, {String parUtilisateur = 'synchronisation'}) {
    initialiser();
    if (base.valeur('SELECT 1 FROM operations WHERE uuid=?', [op.uuid]) != null) return false;
    final t = typeDe(op.type);
    base.transaction(() {
      final recu = Operation.depuisJson(op.versJson());
      _inserer(base, recu);
      if (!t.horsJournee && estCloturee(base, op.entite, op.dateOp)) {
        signalerAnomalie(base, 'date_cloturee', op.uuid,
            'Opération ${op.piece ?? op.type} de ${op.appareil} reçue pour la journée clôturée du ${dateFr(depuisIso(op.dateOp))}.');
      }
      t.appliquer(base, recu);
      Audit.tracer(base,
          utilisateur: parUtilisateur,
          appareil: op.appareil,
          action: 'synchronisation',
          objet: '${t.libelle}${op.piece != null ? ' ${op.piece}' : ''} [${op.uuid}]',
          nouveau: _sansContenu(op.donnees));
    });
    return true;
  }

  /// Le journal d'audit garde l'empreinte des pièces jointes, pas leur contenu.
  static Map<String, Object?> _sansContenu(Map<String, Object?> d) => d['fichier'] is Map
      ? {...d, 'fichier': {'nom': (d['fichier'] as Map)['nom'], 'sha256': (d['fichier'] as Map)['sha256']}}
      : d;

  static void signalerAnomalie(Base base, String type, String? uuidOp, String detail) => base.exec(
      'INSERT INTO anomalies_sync(horodatage, type, uuid_op, detail) VALUES (?,?,?,?)',
      [base.maintenantReel.toIso8601String(), type, uuidOp, detail]);

  static Operation? lire(Base base, String uuid) {
    final l = base.ligne('SELECT * FROM operations WHERE uuid=?', [uuid]);
    return l == null ? null : Operation.depuisLigne(l);
  }

  static bool estAnnulee(Base base, String uuid) =>
      base.valeur('SELECT 1 FROM annulations WHERE uuid_annule=?', [uuid]) != null;

  /// Annule une opération validée par une contre-opération (motif obligatoire).
  static Operation annuler(Session s, String uuid, String motif) {
    initialiser();
    final base = s.base;
    return base.transaction(() {
      final cible = lire(base, uuid);
      if (cible == null) throw const RegleMetier('Opération introuvable.');
      final t = typeDe(cible.type);
      if (!t.annulable) throw RegleMetier('Une opération « ${t.libelle} » ne peut pas être annulée.');
      if (motif.trim().length < 3) throw const RegleMetier("Le motif d'annulation est obligatoire.");
      if (estAnnulee(base, uuid)) throw const RegleMetier('Cette opération est déjà annulée.');
      return enregistrer(s,
          type: 'annulation',
          entite: cible.entite,
          donnees: {'cible': uuid, 'motif': motif.trim(), 'piece_cible': cible.piece},
          typePiece: 'ANN');
    });
  }
}

class _Annulation extends TypeOperation {
  @override
  String get type => 'annulation';
  @override
  String get module => 'annulation';
  @override
  String get action => 'creer';
  @override
  String get libelle => 'Annulation';
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    final uuidCible = op.d<String>('cible');
    final cible = Operations.lire(base, uuidCible);
    if (cible == null) {
      Operations.signalerAnomalie(base, 'annulation_orpheline', op.uuid, "Annulation d'une opération inconnue : $uuidCible");
      return;
    }
    if (Operations.estAnnulee(base, uuidCible)) {
      Operations.signalerAnomalie(base, 'double_annulation', op.uuid,
          'Opération ${cible.piece ?? uuidCible} annulée deux fois (deux appareils hors ligne).');
      return;
    }
    base.exec('INSERT INTO annulations(uuid_annule, uuid_op, motif) VALUES (?,?,?)',
        [uuidCible, op.uuid, op.d<String>('motif')]);
    Moteur.contrePasser(base, cible, op);
    // Inversion des mouvements de trésorerie.
    for (final m in base.lignes('SELECT * FROM mouvements_tresorerie WHERE uuid_op=?', [uuidCible])) {
      base.exec(
          'INSERT INTO mouvements_tresorerie(uuid_op, tresorerie, date, horodatage, montant, libelle, piece, reference) VALUES (?,?,?,?,?,?,?,?)',
          [op.uuid, m['tresorerie'], op.dateOp, op.horodatage, -(m['montant'] as int), 'Annulation ${m['piece'] ?? ''}', op.piece, m['reference']]);
    }
    Operations.typeDe(cible.type).annuler(base, cible, op);
  }
}
