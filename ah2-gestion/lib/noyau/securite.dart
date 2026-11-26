/// Mots de passe chiffrés (PBKDF2-HMAC-SHA256), verrouillage après échecs.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'audit.dart';
import 'base.dart';
import 'outils.dart';

class Securite {
  static const iterations = 60000;

  static String nouveauSel() {
    final r = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018), 32 octets.
  static String hacher(String secret, String sel, {int iter = iterations}) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    final s = base64Decode(sel);
    final bloc = Uint8List.fromList([...s, 0, 0, 0, 1]);
    var u = hmac.convert(bloc).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iter; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return base64Encode(t);
  }

  static bool _egal(String a, String b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }

  /// Vérifie identifiant + mot de passe (ou code court sur téléphone).
  /// Verrouille le compte sur CET appareil après N échecs (paramètre).
  /// Le mot de passe ou le code court sont acceptés indifféremment ;
  /// l'identifiant ne tient compte ni des majuscules ni des espaces.
  static Map<String, Object?> connecter(Base base, String identifiantSaisi, String secret,
      {bool parCode = false}) {
    final identifiant = identifiantSaisi.trim().toLowerCase();
    secret = secret.trim();
    final cleEchecs = 'echecs:$identifiant';
    final cleVerrou = 'verrou:$identifiant';
    final verrou = base.valeur('SELECT valeur FROM etat_sync WHERE cle=?', [cleVerrou]) as String?;
    if (verrou != null && DateTime.parse(verrou).isAfter(base.maintenantReel)) {
      throw RegleMetier('Compte verrouillé après plusieurs échecs. Réessayez après ${heureFr(DateTime.parse(verrou))}.');
    }
    final u = base.ligne('SELECT * FROM utilisateurs WHERE LOWER(TRIM(identifiant))=? AND actif=1', [identifiant]);
    bool ok = false;
    if (u != null && secret.isNotEmpty) {
      ok = _egal(hacher(secret, u['sel'] as String), u['empreinte'] as String);
      if (!ok && u['empreinte_code'] != null) {
        ok = _egal(hacher(secret, u['sel_code'] as String), u['empreinte_code'] as String);
      }
    }
    if (!ok) {
      // Les échecs sont enregistrés AVANT de signaler l'erreur.
      base.transaction(() {
        final n = int.parse((base.valeur('SELECT valeur FROM etat_sync WHERE cle=?', [cleEchecs]) as String?) ?? '0') + 1;
        _etat(base, cleEchecs, '$n');
        if (n >= base.paramInt('connexion_echecs_max', 5)) {
          final fin = base.maintenantReel.add(Duration(minutes: base.paramInt('connexion_verrou_minutes', 15)));
          _etat(base, cleVerrou, fin.toIso8601String());
          _etat(base, cleEchecs, '0');
        }
        Audit.tracer(base, utilisateur: identifiant, action: 'connexion_echec', objet: 'utilisateur:$identifiant');
      });
      throw const RegleMetier('Identifiant ou mot de passe incorrect.');
    }
    base.transaction(() {
      _etat(base, cleEchecs, '0');
      Audit.tracer(base, utilisateur: u!['id'] as String, action: 'connexion', objet: 'utilisateur:$identifiant');
    });
    return u!;
  }

  static void _etat(Base base, String cle, String v) => base.exec(
      'INSERT INTO etat_sync(cle, valeur) VALUES (?,?) ON CONFLICT(cle) DO UPDATE SET valeur=excluded.valeur',
      [cle, v]);
}
