/// Outils communs aux tests : horloge simulée, PC central et téléphones en
/// mémoire reliés par un transport simulé (le même code que le Wi-Fi réel,
/// chiffrement compris).
library;

import 'dart:convert';
import 'dart:io';

import 'package:ah2_gestion/demo/demonstration.dart';
import 'package:ah2_gestion/modules/modules.dart';
import 'package:ah2_gestion/noyau/base.dart';
import 'package:ah2_gestion/noyau/session.dart';
import 'package:ah2_gestion/sync/synchronisation.dart';

class Horloge {
  DateTime t;
  Horloge(this.t);
  DateTime call() => t;
  void avancer({int jours = 0, int heures = 0, int minutes = 0}) =>
      t = t.add(Duration(days: jours, hours: heures, minutes: minutes));
  void le(int annee, int mois, int jour, [int h = 9, int m = 0]) => t = DateTime(annee, mois, jour, h, m);
}

class Telephone {
  final Base base;
  final ClientSync client;
  bool efface = false;
  Telephone(this.base, this.client);
  Session session(String identifiant) => Session.pour(base, identifiant);
  Future<ResultatSync> sync() => client.synchroniser();
}

class Environnement {
  final Horloge horloge;
  final Base central;
  final ServeurSync serveur;
  final Map<String, String> cles;
  bool wifi = true;

  Environnement._(this.horloge, this.central, this.serveur, this.cles);

  factory Environnement({DateTime? debut}) {
    initialiserModules();
    final h = Horloge(debut ?? DateTime(2026, 11, 2, 8, 0));
    final c = Base.ouvrir(appareil: 'PC1', horloge: h.call);
    final cles = Demo.installerCentral(c, logo: File('assets/images/logo_ah2.png').readAsBytesSync());
    return Environnement._(h, c, ServeurSync(c), cles);
  }

  Session sessionCentrale(String identifiant) => Session.pour(central, identifiant);

  /// Transport simulé : passage par JSON, comme sur le réseau.
  Future<Map<String, Object?>> _transport(Map<String, Object?> env) async {
    if (!wifi) throw StateError('Pas de Wi-Fi');
    final aller = jsonDecode(jsonEncode(env)) as Map<String, Object?>;
    return jsonDecode(jsonEncode(serveur.traiter(aller))) as Map<String, Object?>;
  }

  /// Crée un téléphone enrôlé et fait sa première synchronisation.
  Future<Telephone> telephone(String code) async {
    final b = Base.ouvrir(appareil: code, horloge: horloge.call);
    ClientSync.enroler(b, cleSync: cles[code]!);
    late Telephone t;
    final client = ClientSync(b, transport: _transport, effacerDonnees: () {
      t.efface = true;
      b.exec('PRAGMA defer_foreign_keys = ON');
    });
    t = Telephone(b, client);
    await t.sync();
    return t;
  }
}
