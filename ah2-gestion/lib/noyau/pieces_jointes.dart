/// Pièces jointes (photo prise avec le téléphone, scan) rattachées à une
/// opération. Le contenu voyage avec l'opération : le PC central reçoit
/// donc la photo de chaque dépense et de chaque relevé signé.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'base.dart';
import 'operations.dart';
import 'outils.dart';

class PiecesJointes {
  static const tailleMax = 3 * 1024 * 1024;

  /// Prépare un fichier pour l'inclure dans les données d'une opération.
  static Map<String, Object?> preparer(String nom, Uint8List octets) {
    if (octets.isEmpty) throw const RegleMetier('Fichier vide.');
    if (octets.length > tailleMax) throw const RegleMetier('Pièce jointe trop lourde (3 Mo maximum).');
    return {'nom': nom, 'sha256': sha256.convert(octets).toString(), 'contenu': base64Encode(octets)};
  }

  /// Enregistre la pièce jointe d'une opération (appelé par les applicateurs).
  static String? enregistrer(Base base, Operation op, Object? fichier) {
    if (fichier == null) return null;
    final f = Map<String, Object?>.from(fichier as Map);
    base.exec('INSERT OR IGNORE INTO pieces_jointes(sha256, uuid_op, nom, contenu, ajoute_le) VALUES (?,?,?,?,?)',
        [f['sha256'], op.uuid, f['nom'], base64Decode(f['contenu'] as String), op.horodatage]);
    return f['sha256'] as String;
  }

  static Uint8List? lire(Base base, String sha) => base.valeur('SELECT contenu FROM pieces_jointes WHERE sha256=?', [sha]) as Uint8List?;
}
