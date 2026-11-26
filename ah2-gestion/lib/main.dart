/// AH2 Gestion, logiciel de gestion intégrée de l'ONG A Hand to Humanity.
///
/// Une seule application pour le PC (Windows) et le téléphone (Android),
/// entièrement hors ligne : chaque appareil possède sa base locale, et la
/// synchronisation passe uniquement par le Wi-Fi local de la structure.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'modules/modules.dart';
import 'modules/parametrage/parametrage.dart';
import 'noyau/base.dart';
import 'pdf/documents.dart';
import 'ui/app.dart';
import 'ui/etat_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initialiserModules();
  await chargerPolices();
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
  // Mise à jour du logiciel : le paramétrage est complété, jamais écrasé.
  if (Parametrage.estCentral(base)) Parametrage.completerReferentiels(base);
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

/// Police Arial partout : celle de Windows sur PC ; sur téléphone, son
/// équivalent métrique libre (Liberation Sans, mêmes dimensions qu'Arial),
/// embarqué dans l'application. Les documents PDF utilisent la même.
Future<void> chargerPolices() async {
  Future<Uint8List> fichier(String windows, String asset) async {
    final f = File('C:\\Windows\\Fonts\\$windows');
    if (Platform.isWindows && f.existsSync()) return f.readAsBytesSync();
    final d = await rootBundle.load('assets/polices/$asset');
    return d.buffer.asUint8List();
  }

  final normale = await fichier('arial.ttf', 'LiberationSans-Regular.ttf');
  final gras = await fichier('arialbd.ttf', 'LiberationSans-Bold.ttf');
  final italique = await fichier('ariali.ttf', 'LiberationSans-Italic.ttf');
  final grasItalique = await fichier('arialbi.ttf', 'LiberationSans-BoldItalic.ttf');
  final arial = FontLoader('Arial');
  for (final o in [normale, gras, italique, grasItalique]) {
    arial.addFont(Future.value(ByteData.sublistView(o)));
  }
  await arial.load();
  Documents.configurerPolices(normale: normale, gras: gras, italique: italique, grasItalique: grasItalique);
}

/// Logo livré par défaut (celui de la structure), remplaçable dans le paramétrage.
Future<Uint8List> logoParDefaut() async => (await rootBundle.load('assets/images/logo_ah2.png')).buffer.asUint8List();
