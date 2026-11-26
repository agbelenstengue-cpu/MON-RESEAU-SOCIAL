import 'dart:io';

import 'package:ah2_gestion/demo/demonstration.dart';
import 'package:ah2_gestion/modules/releves/releves.dart';
import 'package:ah2_gestion/modules/tresorerie/tresorerie.dart';
import 'package:ah2_gestion/noyau/outils.dart';
import 'package:ah2_gestion/noyau/session.dart';
import 'package:ah2_gestion/pdf/documents.dart';
import 'package:test/test.dart';

import 'aide.dart';

void main() {
  test('tous les documents PDF se génèrent (reçus, relevé, rapport de sortie, rapport du jour, arrêté)', () async {
    final env = Environnement(debut: DateTime(2026, 11, 26, 9));
    Demo.donneesFictives(env.central);
    final b = env.central;
    final c = Session.pour(b, 'comptable');
    final hier = ajouterJours(dateIso(env.horloge.t), -1);
    // Les téléphones de démonstration ne servent pas : on les déclare inactifs.
    for (final t in ['T01', 'T02']) {
      b.exec("UPDATE appareils SET statut='inactif' WHERE code=?", [t]);
    }
    Releves.generer(c, activite: 'LAB', date: hier);
    final numero = b.valeur("SELECT numero FROM releves LIMIT 1") as String;
    final releve = await Documents.releve(b, numero);
    expect(releve.length, greaterThan(1000));
    final sortie = await Documents.rapportSortie(b, b.valeur('SELECT id FROM desintox_dossiers LIMIT 1') as String);
    final recu = await Documents.recu(b, b.valeur("SELECT uuid FROM operations WHERE type='desintox_versement' LIMIT 1") as String);
    final dossierPdf = Platform.environment['AH2_PDF'];
    if (dossierPdf != null) {
      File('$dossierPdf/releve.pdf').writeAsBytesSync(releve);
      File('$dossierPdf/sortie.pdf').writeAsBytesSync(sortie);
      File('$dossierPdf/recu.pdf').writeAsBytesSync(recu);
    }
    for (final type in ['acte', 'desintox_versement', 'don']) {
      final uuid = b.valeur('SELECT uuid FROM operations WHERE type=? LIMIT 1', [type]) as String;
      expect((await Documents.recu(b, uuid)).length, greaterThan(500), reason: type);
    }
    final dossier = b.valeur('SELECT id FROM desintox_dossiers LIMIT 1') as String;
    expect((await Documents.rapportSortie(b, dossier)).length, greaterThan(1000));
    expect((await Documents.rapportJour(b, hier)).length, greaterThan(1000));
    final arr = Tresorerie.arreterCaisse(Session.pour(b, 'caisse'),
        caisse: 'CS-CAISSE', billetage: {10000: 1}, motifEcart: 'Comptage de démonstration');
    expect((await Documents.arreteCaisse(b, arr.uuid)).length, greaterThan(1000));
  });
}
