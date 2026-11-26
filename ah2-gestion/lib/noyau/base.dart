/// Accès à la base locale SQLite.
///
/// Chaque appareil (PC central compris) possède sa propre base. Toutes les
/// écritures passent par [Base.transaction] : en cas de coupure de courant ou de
/// batterie vide, une opération est soit entièrement enregistrée, soit pas du
/// tout (journal WAL + synchronous=FULL).
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'schema.dart';

typedef Ligne = Map<String, Object?>;

class Base {
  final Database db;

  /// Code de l'appareil qui détient cette base (PC1, T01…).
  final String appareil;

  /// Horloge injectable (les tests simulent des journées entières).
  DateTime Function() horloge;

  final String? chemin;
  int _profondeur = 0;
  static const _uuid = Uuid();

  Base._(this.db, this.appareil, this.horloge, this.chemin);

  /// Ouvre (ou crée) une base. [cle] active le chiffrement (SQLite3MultipleCiphers),
  /// utilisé sur les téléphones. Sans [chemin], la base est en mémoire (tests).
  factory Base.ouvrir({
    String? chemin,
    required String appareil,
    String? cle,
    DateTime Function()? horloge,
  }) {
    final db = chemin == null ? sqlite3.openInMemory() : sqlite3.open(chemin);
    if (cle != null) {
      // Doit être la toute première instruction sur une base chiffrée.
      db.execute("PRAGMA key = '${cle.replaceAll("'", "''")}'");
    }
    db.execute('PRAGMA foreign_keys = ON');
    if (chemin != null) {
      db.execute('PRAGMA journal_mode = WAL');
    }
    db.execute('PRAGMA synchronous = FULL');
    final base = Base._(db, appareil, horloge ?? DateTime.now, chemin);
    base._migrer();
    return base;
  }

  void _migrer() {
    var v = db.select('PRAGMA user_version').first.values.first as int;
    if (v == 0) {
      transaction(() {
        db.execute(schemaSql);
        db.execute('PRAGMA user_version = 1');
      });
      v = 1;
    }
    // Mises à jour : uniquement des ajouts, aucune donnée n'est perdue.
    for (var cible = v + 1; cible <= versionSchema; cible++) {
      transaction(() {
        db.execute(migrations[cible]!);
        db.execute('PRAGMA user_version = $cible');
      });
    }
  }

  /// Exécute [action] de façon atomique. Les appels imbriqués utilisent des
  /// points de sauvegarde : une erreur annule uniquement le bloc concerné,
  /// et l'exception remonte.
  T transaction<T>(T Function() action) {
    final point = 'p$_profondeur';
    if (_profondeur == 0) {
      db.execute('BEGIN IMMEDIATE');
    } else {
      db.execute('SAVEPOINT $point');
    }
    _profondeur++;
    try {
      final r = action();
      _profondeur--;
      if (_profondeur == 0) {
        db.execute('COMMIT');
      } else {
        db.execute('RELEASE $point');
      }
      return r;
    } catch (_) {
      _profondeur--;
      if (_profondeur == 0) {
        db.execute('ROLLBACK');
      } else {
        db.execute('ROLLBACK TO $point');
        db.execute('RELEASE $point');
      }
      rethrow;
    }
  }

  bool get enTransaction => !db.autocommit;

  void exec(String sql, [List<Object?> p = const []]) => db.execute(sql, p);

  List<Ligne> lignes(String sql, [List<Object?> p = const []]) =>
      db.select(sql, p).map((r) => Map<String, Object?>.from(r)).toList();

  Ligne? ligne(String sql, [List<Object?> p = const []]) {
    final r = db.select(sql, p);
    return r.isEmpty ? null : Map<String, Object?>.from(r.first);
  }

  Object? valeur(String sql, [List<Object?> p = const []]) {
    final r = db.select(sql, p);
    return r.isEmpty ? null : r.first.values.first;
  }

  int entier(String sql, [List<Object?> p = const []]) =>
      (valeur(sql, p) as int?) ?? 0;

  /// Paramètre (seuil, délai…) : jamais codé en dur, toujours lu ici.
  String param(String cle, [String? defaut]) {
    final v = valeur('SELECT valeur FROM parametres WHERE cle = ?', [cle]);
    if (v == null) {
      if (defaut != null) return defaut;
      throw StateError('Paramètre manquant : $cle');
    }
    return v as String;
  }

  int paramInt(String cle, [int? defaut]) =>
      int.parse(param(cle, defaut?.toString()));

  void definirParam(String cle, String valeur) => exec(
      'INSERT INTO parametres(cle, valeur) VALUES (?, ?) '
      'ON CONFLICT(cle) DO UPDATE SET valeur = excluded.valeur',
      [cle, valeur]);

  String nouvelUuid() => _uuid.v4();

  /// Date de saisie choisie (reprise de l'historique). Quand elle est
  /// définie, les opérations sont datées de ce jour (à l'heure actuelle),
  /// tandis que la date et l'heure réelles restent tracées (audit).
  String? dateSaisie;

  /// Instant « métier » : la date de saisie choisie, sinon maintenant.
  DateTime get maintenant {
    final r = horloge();
    final d = dateSaisie;
    if (d == null) return r;
    final p = d.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2], r.hour, r.minute, r.second);
  }

  /// Exécute [action] à la date réelle (clôtures, relevés, synchronisation).
  T aDateReelle<T>(T Function() action) {
    final d = dateSaisie;
    dateSaisie = null;
    try {
      return action();
    } finally {
      dateSaisie = d;
    }
  }

  /// Instant réel (horloge de l'appareil), pour la traçabilité.
  DateTime get maintenantReel => horloge();

  /// Copie cohérente de la base dans un fichier (sauvegarde à chaud).
  void copierVers(String cheminCible) {
    final f = File(cheminCible);
    if (f.existsSync()) f.deleteSync();
    db.execute('VACUUM INTO ?', [cheminCible]);
  }

  void fermer() => db.close();
}
