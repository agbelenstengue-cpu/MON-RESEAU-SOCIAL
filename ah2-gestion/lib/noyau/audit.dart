/// Journal d'audit : qui, quand, sur quel appareil, ancienne et nouvelle valeur.
///
/// Les lignes sont chaînées (chaque empreinte inclut la précédente) : toute
/// altération du fichier, même hors du logiciel, est détectée par [verifier].
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'base.dart';

class Audit {
  static const _origine = 'AH2-GENESE';

  static String _empreinte(String prec, List<Object?> champs) {
    final txt = [prec, ...champs.map((c) => c?.toString() ?? '')].join('\u001f');
    return sha256.convert(utf8.encode(txt)).toString();
  }

  /// Ajoute une ligne au journal (doit être appelé dans la transaction de l'action).
  static void tracer(
    Base base, {
    required String utilisateur,
    required String action,
    required String objet,
    Object? ancien,
    Object? nouveau,
    String? appareil,
  }) {
    final prec = base.valeur('SELECT empreinte FROM audit ORDER BY id DESC LIMIT 1')
            as String? ??
        _origine;
    final h = base.maintenantReel.toIso8601String();
    final app = appareil ?? base.appareil;
    final a = ancien == null ? null : (ancien is String ? ancien : jsonEncode(ancien));
    final n = nouveau == null ? null : (nouveau is String ? nouveau : jsonEncode(nouveau));
    final e = _empreinte(prec, [h, utilisateur, app, action, objet, a, n]);
    base.exec(
        'INSERT INTO audit(horodatage, utilisateur, appareil, action, objet, '
        'ancienne_valeur, nouvelle_valeur, empreinte_prec, empreinte) '
        'VALUES (?,?,?,?,?,?,?,?,?)',
        [h, utilisateur, app, action, objet, a, n, prec, e]);
  }

  /// Vérifie l'intégrité de toute la chaîne. Renvoie l'id de la première ligne
  /// altérée, ou null si tout est intact.
  static int? verifier(Base base) {
    var prec = _origine;
    for (final l in base.lignes('SELECT * FROM audit ORDER BY id')) {
      final e = _empreinte(prec, [
        l['horodatage'],
        l['utilisateur'],
        l['appareil'],
        l['action'],
        l['objet'],
        l['ancienne_valeur'],
        l['nouvelle_valeur'],
      ]);
      if (l['empreinte_prec'] != prec || l['empreinte'] != e) return l['id'] as int;
      prec = e;
    }
    return null;
  }
}
