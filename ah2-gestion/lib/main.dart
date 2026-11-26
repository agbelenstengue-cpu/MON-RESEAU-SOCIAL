/// AH2 Gestion — logiciel de gestion intégrée de l'ONG A Hand to Humanity.
///
/// Une seule application pour le PC (Windows) et le téléphone (Android),
/// entièrement hors ligne : chaque appareil possède sa base locale, et la
/// synchronisation passe uniquement par le Wi-Fi local de la structure.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'modules/modules.dart';
import 'noyau/base.dart';
import 'ui/app.dart';
import 'ui/etat_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initialiserModules();
  final etat = EtatApp();
  await ouvrirBaseLocale(etat);
  runApp(Ah2App(etat: etat));
}

/// Ouvre (ou crée) la base locale chiffrée. La clé est générée au premier
/// lancement et conservée dans le coffre sécurisé du système (Android
/// Keystore, Windows DPAPI).
Future<void> ouvrirBaseLocale(EtatApp etat) async {
  final dossier = await getApplicationSupportDirectory();
  dossier.createSync(recursive: true);
  final chemin = p.join(dossier.path, 'ah2_gestion.db');
  String? cle;
  try {
    const coffre = FlutterSecureStorage();
    cle = await coffre.read(key: 'cle_base');
    if (cle == null) {
      final r = Random.secure();
      cle = base64Encode(List<int>.generate(32, (_) => r.nextInt(256)));
      await coffre.write(key: 'cle_base', value: cle);
    }
  } catch (_) {
    cle = null; // plateforme sans coffre : base non chiffrée
  }
  final appareil = await _codeAppareil(dossier.path);
  final base = Base.ouvrir(chemin: chemin, appareil: appareil ?? 'NOUVEAU', cle: cle);
  etat.ouvrir(base, chemin, cle: cle);
  await etat.demarrerServices();
}

/// Le code de l'appareil (PC1, T01…) est choisi à l'installation et conservé
/// dans un petit fichier à côté de la base.
Future<String?> _codeAppareil(String dossier) async {
  final f = File(p.join(dossier, 'appareil.txt'));
  return f.existsSync() ? f.readAsStringSync().trim() : null;
}

Future<void> enregistrerCodeAppareil(String code) async {
  final dossier = await getApplicationSupportDirectory();
  File(p.join(dossier.path, 'appareil.txt')).writeAsStringSync(code);
}
