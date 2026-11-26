/// Synchronisation appareil ↔ PC central, par le Wi-Fi local uniquement.
///
/// Couche isolée et testée séparément. Principe :
///  * l'appareil envoie ses opérations locales pas encore acquittées ;
///  * le PC central les intègre (idempotent : UUID unique) et renvoie les
///    opérations des autres appareils ainsi que le paramétrage s'il a changé ;
///  * tout est chiffré en AES-256-GCM avec la clé propre à l'appareil
///    (remise lors de son enregistrement) : seuls les appareils autorisés
///    peuvent se synchroniser, et personne sur le Wi-Fi ne peut lire les données.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../noyau/audit.dart';
import '../noyau/base.dart';
import '../noyau/chiffrement.dart';
import '../noyau/operations.dart';
import '../noyau/outils.dart';
import '../modules/parametrage/parametrage.dart';

/// Taille maximale d'un lot d'opérations par échange.
const tailleLot = 500;

class AppareilRevoque extends RegleMetier {
  const AppareilRevoque() : super('Cet appareil a été révoqué : ses données locales sont effacées.');
}

class Enveloppe {
  static Uint8List _aad(String appareil) => Uint8List.fromList(utf8.encode('AH2SYNC|$appareil'));

  static Map<String, Object?> fermer(String appareil, String cleBase64, Map<String, Object?> contenu) => {
        'appareil': appareil,
        'paquet': base64Encode(Chiffrement.chiffrer(
            base64Decode(cleBase64), Uint8List.fromList(utf8.encode(jsonEncode(contenu))),
            associees: _aad(appareil))),
      };

  static Map<String, Object?> ouvrir(String appareil, String cleBase64, Map<String, Object?> enveloppe) {
    final clair = Chiffrement.dechiffrer(base64Decode(cleBase64), base64Decode(enveloppe['paquet'] as String),
        associees: _aad(appareil));
    return Map<String, Object?>.from(jsonDecode(utf8.decode(clair)) as Map);
  }
}

// =============================================================== PC CENTRAL

class ServeurSync {
  final Base base;
  ServeurSync(this.base);

  String _etat(String cle) => (base.valeur('SELECT valeur FROM etat_sync WHERE cle=?', [cle]) as String?) ?? '0';
  void _definir(String cle, String v) => base.exec(
      'INSERT INTO etat_sync(cle, valeur) VALUES (?,?) ON CONFLICT(cle) DO UPDATE SET valeur=excluded.valeur', [cle, v]);

  /// Traite une enveloppe reçue d'un appareil et renvoie l'enveloppe de réponse.
  Map<String, Object?> traiter(Map<String, Object?> enveloppe) {
    final code = enveloppe['appareil'] as String?;
    final app = code == null ? null : base.ligne('SELECT * FROM appareils WHERE code=? AND central=0', [code]);
    if (app == null) return {'erreur': 'appareil_inconnu'};
    final cle = app['cle_sync'] as String;
    Map<String, Object?> req;
    try {
      req = Enveloppe.ouvrir(code!, cle, enveloppe);
    } catch (_) {
      base.transaction(() => Audit.tracer(base,
          utilisateur: 'synchronisation', appareil: code!, action: 'synchronisation_refusee', objet: 'appareil:$code', nouveau: 'clé invalide'));
      return {'erreur': 'authentification'};
    }
    // Protection contre le rejeu : compteur strictement croissant.
    final compteur = req['compteur'] as int;
    if (compteur <= int.parse(_etat('compteur:$code'))) {
      return {'erreur': 'rejeu'};
    }
    if (app['statut'] == 'revoque') {
      base.transaction(() {
        _definir('compteur:$code', '$compteur');
        Audit.tracer(base,
            utilisateur: 'synchronisation', appareil: code, action: 'synchronisation_refusee', objet: 'appareil:$code', nouveau: 'appareil révoqué');
      });
      return Enveloppe.fermer(code, cle, {'revoque': true});
    }
    final reponse = base.transaction(() {
      _definir('compteur:$code', '$compteur');
      var recues = 0;
      for (final j in (req['operations'] as List).cast<Map>()) {
        final op = Operation.depuisJson(Map<String, Object?>.from(j));
        if (op.appareil != code) {
          Operations.signalerAnomalie(base, 'origine_invalide', op.uuid, "L'appareil $code a transmis une opération de ${op.appareil}.");
          continue;
        }
        if (Operations.importer(base, op, parUtilisateur: op.utilisateur)) recues++;
      }
      final depuis = req['recu_jusqua'] as int;
      final aEnvoyer = base.lignes(
          'SELECT * FROM operations WHERE seq > ? AND appareil <> ? ORDER BY seq LIMIT ?', [depuis, code, tailleLot + 1]);
      final reste = aEnvoyer.length > tailleLot;
      final lot = aEnvoyer.take(tailleLot).toList();
      final curseur = lot.isEmpty ? base.entier('SELECT COALESCE(MAX(seq),0) FROM operations') : lot.last['seq'] as int;
      final versionCentrale = base.paramInt('version_parametrage');
      final complet = req['complet'] == true && !reste;
      if (complet) {
        base.exec('UPDATE appareils SET derniere_sync=? WHERE code=?', [base.maintenantReel.toIso8601String(), code]);
      }
      Audit.tracer(base,
          utilisateur: 'synchronisation',
          appareil: code,
          action: 'synchronisation',
          objet: 'appareil:$code',
          nouveau: {'recues': recues, 'envoyees': lot.length, 'complete': complet});
      return {
        'operations': [for (final l in lot) Operation.depuisLigne(l).versJson()],
        'curseur': curseur,
        'reste': reste,
        'parametrage': req['version_parametrage'] == versionCentrale ? null : Parametrage.exporter(base, pourAppareil: code),
        'heure_centrale': base.maintenantReel.toIso8601String(),
      };
    });
    return Enveloppe.fermer(code, cle, reponse);
  }
}

// =============================================================== APPAREIL

/// Transport : envoie une enveloppe au PC central et renvoie sa réponse.
typedef Transport = Future<Map<String, Object?>> Function(Map<String, Object?> enveloppe);

class ResultatSync {
  final int envoyees;
  final int recues;
  final bool parametrageMisAJour;
  const ResultatSync(this.envoyees, this.recues, this.parametrageMisAJour);
}

class EtatSync {
  final int enAttente;
  final DateTime? derniere;
  const EtatSync(this.enAttente, this.derniere);

  /// Libellé de l'indicateur permanent.
  String libelle(DateTime maintenant) {
    if (derniere == null) return 'Jamais synchronisé';
    if (enAttente > 0) return 'En attente · $enAttente opération${enAttente > 1 ? 's' : ''}';
    final h = maintenant.difference(derniere!).inHours;
    return h >= 1 ? 'Hors ligne depuis $h h' : 'Synchronisé';
  }
}

class ClientSync {
  final Base base;
  final Transport transport;

  /// Efface les données locales (appareil révoqué).
  final void Function() effacerDonnees;

  ClientSync(this.base, {required this.transport, required this.effacerDonnees});

  /// Enregistre sur un appareil neuf la clé remise par le PC central.
  static void enroler(Base base, {required String cleSync}) => base.transaction(() {
        for (final e in {
          'cle_sync': cleSync,
          'installe_le': base.maintenantReel.toIso8601String(),
        }.entries) {
          base.exec('INSERT INTO etat_sync(cle, valeur) VALUES (?,?) ON CONFLICT(cle) DO UPDATE SET valeur=excluded.valeur',
              [e.key, e.value]);
        }
      });

  String? _etat(String cle) => base.valeur('SELECT valeur FROM etat_sync WHERE cle=?', [cle]) as String?;
  void _definir(String cle, String v) => base.exec(
      'INSERT INTO etat_sync(cle, valeur) VALUES (?,?) ON CONFLICT(cle) DO UPDATE SET valeur=excluded.valeur', [cle, v]);

  static EtatSync etat(Base base) {
    final envoye = int.parse((base.valeur("SELECT valeur FROM etat_sync WHERE cle='envoye_jusqua'") as String?) ?? '0');
    final d = base.valeur("SELECT valeur FROM etat_sync WHERE cle='derniere_sync'") as String?;
    return EtatSync(base.entier("SELECT COUNT(*) FROM operations WHERE origine='locale' AND seq > ?", [envoye]),
        d == null ? null : DateTime.parse(d));
  }

  Future<ResultatSync> synchroniser() async {
    if (_etat('revoque') == '1') throw const AppareilRevoque();
    final cle = _etat('cle_sync') ?? (throw const RegleMetier("Appareil non enrôlé : saisissez la clé remise par l'administrateur."));
    var envoyees = 0, recues = 0;
    var params = false;
    var initial = _etat('recu_jusqua') == null;
    while (true) {
      final envoye = int.parse(_etat('envoye_jusqua') ?? '0');
      final enAttente = base.lignes(
          "SELECT * FROM operations WHERE origine='locale' AND seq > ? ORDER BY seq LIMIT ?", [envoye, tailleLot + 1]);
      final lot = enAttente.take(tailleLot).toList();
      final compteur = int.parse(_etat('compteur') ?? '0') + 1;
      base.transaction(() => _definir('compteur', '$compteur'));
      final requete = {
        'compteur': compteur,
        'horodatage': base.maintenantReel.toIso8601String(),
        'operations': [for (final l in lot) Operation.depuisLigne(l).versJson()],
        'recu_jusqua': int.parse(_etat('recu_jusqua') ?? '0'),
        'version_parametrage': initial ? -1 : base.paramInt('version_parametrage', 0),
        'complet': enAttente.length <= tailleLot,
        'initial': initial,
      };
      final reponseEnv = await transport(Enveloppe.fermer(base.appareil, cle, requete));
      if (reponseEnv['erreur'] != null) {
        throw RegleMetier('Synchronisation refusée par le PC central (${reponseEnv['erreur']}).');
      }
      final rep = Enveloppe.ouvrir(base.appareil, cle, reponseEnv);
      if (rep['revoque'] == true) {
        base.transaction(() => _definir('revoque', '1'));
        effacerDonnees();
        throw const AppareilRevoque();
      }
      base.transaction(() {
        if (lot.isNotEmpty) _definir('envoye_jusqua', '${lot.last['seq']}');
        final p = rep['parametrage'];
        if (p != null) {
          Parametrage.importer(base, Map<String, Object?>.from(p as Map));
          params = true;
        }
        for (final j in (rep['operations'] as List).cast<Map>()) {
          if (Operations.importer(base, Operation.depuisJson(Map<String, Object?>.from(j)))) recues++;
        }
        _definir('recu_jusqua', '${rep['curseur']}');
      });
      envoyees += lot.length;
      initial = false;
      if (enAttente.length <= tailleLot && rep['reste'] != true) break;
    }
    base.transaction(() {
      _definir('derniere_sync', base.maintenantReel.toIso8601String());
      Audit.tracer(base,
          utilisateur: 'synchronisation', action: 'synchronisation', objet: 'PC central', nouveau: {'envoyees': envoyees, 'recues': recues});
    });
    return ResultatSync(envoyees, recues, params);
  }
}
