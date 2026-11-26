/// Rend chaque écran avec les données de démonstration (vraies polices) :
/// vérifie l'absence d'erreur de mise en page et produit des captures.
library;

import 'dart:io';

import 'package:ah2_gestion/demo/demonstration.dart';
import 'package:ah2_gestion/noyau/base.dart';
import 'package:ah2_gestion/noyau/session.dart';
import 'package:ah2_gestion/ui/app.dart';
import 'package:ah2_gestion/ui/ecrans/coquille.dart';
import 'package:ah2_gestion/ui/etat_app.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _polices() async {
  final dossier = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final arial = FontLoader('Arial');
  for (final f in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
    arial.addFont(Future.value(ByteData.sublistView(File('assets/polices/LiberationSans-$f.ttf').readAsBytesSync())));
  }
  await arial.load();
  final icones = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$dossier/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icones.load();
}

late EtatApp etat;

void main() {
  setUpAll(() async {
    await _polices();
    final b = Base.ouvrir(appareil: 'PC1');
    Demo.installerCentral(b, logo: File('assets/images/logo_ah2.png').readAsBytesSync());
    Demo.donneesFictives(b);
    etat = EtatApp()..ouvrir(b, null);
  });

  Future<void> afficher(WidgetTester t, Size taille, String identifiant) async {
    t.view.physicalSize = taille * 2;
    t.view.devicePixelRatio = 2;
    etat.connecter(Session.pour(etat.base!, identifiant));
    await t.pumpWidget(Ah2App(etat: etat));
    await t.pumpAndSettle();
  }

  for (final (nom, taille) in [('pc', const Size(1440, 900)), ('telephone', const Size(390, 844))]) {
    testWidgets('écrans $nom', (t) async {
      await afficher(t, taille, 'comptable');
      for (final d in destinations) {
        if (!d.visible(etat)) continue;
        if (nom == 'pc') {
          await t.tap(find.text(d.libelle).last);
        } else {
          final court = d.court;
          final bas = find.descendant(of: find.byType(NavigationBar), matching: find.text(court));
          if (bas.evaluate().isEmpty) {
            await t.tap(find.text('Plus'));
            await t.pumpAndSettle();
            await t.tap(find.text(d.libelle).last);
          } else {
            await t.tap(bas.first);
          }
        }
        await t.pumpAndSettle();
        // Les images (logo, filigrane) se décodent de façon asynchrone.
        await t.runAsync(() async {
          for (final e in find.byType(Image).evaluate()) {
            await precacheImage((e.widget as Image).image, e);
          }
        });
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: d.libelle);
        // Captures produites seulement à la demande : AH2_CAPTURES=1 flutter test --update-goldens
        if (Platform.environment['AH2_CAPTURES'] == '1') {
          await expectLater(find.byType(Ah2App), matchesGoldenFile('captures/${nom}_${d.id}.png'));
        }
      }
      etat.deconnecter();
      await t.pumpAndSettle();
    });
  }
}

