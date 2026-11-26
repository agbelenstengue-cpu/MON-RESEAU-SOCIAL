/// Mises à jour sans perte, états comptables et de gestion, exports.
library;

import 'dart:io';

import 'package:ah2_gestion/demo/demonstration.dart';
import 'package:ah2_gestion/modules/actes/actes.dart';
import 'package:ah2_gestion/modules/comptabilite/comptabilite.dart';
import 'package:ah2_gestion/modules/comptabilite/moteur.dart';
import 'package:ah2_gestion/modules/patients/patients.dart';
import 'package:ah2_gestion/modules/rapports/rapports.dart';
import 'package:ah2_gestion/modules/tresorerie/tresorerie.dart';
import 'package:ah2_gestion/noyau/base.dart';
import 'package:ah2_gestion/noyau/outils.dart';
import 'package:ah2_gestion/noyau/schema.dart';
import 'package:ah2_gestion/pdf/documents.dart';
import 'package:ah2_gestion/rapports/etats_comptables.dart';
import 'package:ah2_gestion/rapports/etats_gestion.dart';
import 'package:ah2_gestion/rapports/export_xlsx.dart';
import 'package:ah2_gestion/rapports/modele.dart';
import 'package:archive/archive.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'aide.dart';

void main() {
  test('une mise à jour du logiciel ne perd aucune donnée (schéma 1 vers 2)', () {
    final d = Directory.systemTemp.createTempSync('ah2-migration');
    final chemin = '${d.path}/ancienne.db';
    // Base créée par la version 1 du logiciel, avec des données.
    final ancienne = sqlite3.open(chemin);
    ancienne.execute(schemaSql);
    ancienne.execute('PRAGMA user_version = 1');
    ancienne.execute("INSERT INTO parametres(cle, valeur) VALUES ('test', 'conservé')");
    ancienne.execute(
        "INSERT INTO patients(id, numero_dossier, nom, version_op, horodatage_version) VALUES ('p1', 'P-PC1-2026-00001', 'ANCIEN', 'x', '2026-01-01')");
    ancienne.execute(
        "INSERT INTO desintox_dossiers(id, numero, patient, programme, date_entree, duree_prevue, montant_total, responsables, echeancier, reconnaissance, uuid_op) "
        "VALUES ('d1', 'D-1', 'p1', 'RES-90', '2026-01-01', 90, 450000, '[]', '[]', 'inscription', 'x')");
    ancienne.close();
    final b = Base.ouvrir(chemin: chemin, appareil: 'PC1');
    expect(b.valeur('PRAGMA user_version'), versionSchema);
    expect(b.param('test'), 'conservé');
    expect(b.valeur("SELECT nom FROM patients WHERE id='p1'"), 'ANCIEN');
    expect(b.valeur("SELECT montant_total FROM desintox_dossiers WHERE id='d1'"), 450000);
    expect(b.valeur("SELECT medicaments_factures FROM desintox_dossiers WHERE id='d1'"), 0);
    expect(b.entier("SELECT COUNT(*) FROM sqlite_master WHERE name IN ('produits','sejours','employes','immobilisations')"), 4);
    b.fermer();
    d.deleteSync(recursive: true);
  });

  group('états comptables', () {
    late Environnement env;
    setUpAll(() {
      env = Environnement(debut: DateTime(2026, 11, 26, 9));
      Demo.donneesFictives(env.central);
    });

    test('balance : débits = crédits ; bilan : actif = passif ; compte de résultat cohérent', () {
      final b = env.central;
      final annee = const Periode('2026-01-01', '2026-12-31');
      for (final ent in ['CS', 'ONG']) {
        final bal = EtatsComptables.balance(b, ent, annee);
        final t = bal.sections.first.ligneTotal!;
        expect(t[4], t[5], reason: 'mouvements débit = crédit ($ent)');
        expect((t[6] as int) - (t[7] as int), (t[2] as int) - (t[3] as int) + (t[4] as int) - (t[5] as int));
        final bilan = EtatsComptables.bilan(b, ent, '2026-12-31');
        expect(bilan.synthese.last.$2, fcfa(0), reason: 'bilan équilibré ($ent)');
        final cr = EtatsComptables.compteResultat(b, ent, annee);
        final produits = cr.sections[0].ligneTotal![2] as int;
        final charges = cr.sections[1].ligneTotal![2] as int;
        expect(produits, -Moteur.solde(b, ent, '7'));
        expect(charges, Moteur.solde(b, ent, '6'));
      }
    });

    test('analytique : charges communes réparties au franc près ; parts = 100 %', () {
      final r = EtatsComptables.resultatAnalytique(env.central, 'CS', const Periode('2026-10-01', '2026-11-30'));
      final lignes = r.sections.first.lignes;
      final total = r.sections.first.ligneTotal!;
      expect(lignes.fold<int>(0, (t, l) => t + (l[2] as int)), 100);
      expect(lignes.fold<int>(0, (t, l) => t + (l[4] as int)), total[4]);
      expect(total[4], Moteur.solde(env.central, 'CS', '6') - lignes.fold<int>(0, (t, l) => t + (l[3] as int)));
    });

    test('grand livre : solde final = solde du compte ; journaux équilibrés', () {
      final gl = EtatsComptables.grandLivre(env.central, 'CS', const Periode('2026-11-01', '2026-11-30'), racine: '5711');
      expect(gl.sections.single.ligneTotal!.last, Tresorerie.solde(env.central, 'CS-CAISSE', jusquau: '2026-11-30'));
      final j = EtatsComptables.journal(env.central, 'CS', const Periode('2026-11-01', '2026-11-30'));
      for (final s in j.sections) {
        expect(s.ligneTotal![4], s.ligneTotal![5], reason: s.titre);
      }
    });

    test('rapports de gestion par période et par service, comparaisons, totaux = somme des lignes', () {
      final b = env.central;
      final mois = Periode.mois('2026-11-26');
      final f = EtatsGestion.financier(b, Filtres(mois, entite: 'CS'));
      final s = f.sections.first;
      expect(s.lignes.fold<int>(0, (t, l) => t + (l[1] as int)), s.ligneTotal![1]);
      expect(s.lignes.fold<int>(0, (t, l) => t + (l[2] as int)), 100);
      final a = EtatsGestion.activite(b, Filtres(mois, activite: 'LAB'));
      expect(a.sections.first.lignes, isNotEmpty);
      final liste = EtatsGestion.listeActes(b, Filtres(Periode.semaine('2026-11-20'), activite: 'MASS'));
      expect(liste.sections.first.lignes.every((l) => l.last == '[  ]'), isTrue);
      expect(Periode.trimestre('2026-11-26').du, '2026-10-01');
      expect(Periode.mois('2026-02-10').au, '2026-02-28');
      expect(Periode.semaine('2026-11-26').du, '2026-11-23');
    });

    test('état des patients en désintoxication et balance âgée', () {
      final e = EtatsGestion.desintoxEnCours(env.central, '2026-11-26');
      expect(e.sections.first.lignes.single[9], 225000);
      final ba = EtatsComptables.balanceAgee(env.central, 'CS', '2026-11-26');
      final t = ba.sections.first.ligneTotal!;
      expect((t[2] as int) + (t[3] as int) + (t[4] as int) + (t[5] as int), t[6]);
      expect(t[6], Moteur.solde(env.central, 'CS', '411'));
    });

    test('exports : PDF et Excel (classeur valide) pour chaque état', () async {
      final b = env.central;
      final mois = Periode.mois('2026-11-26');
      for (final r in [
        EtatsComptables.balance(b, 'CS', mois),
        EtatsComptables.bilan(b, 'ONG', '2026-11-26'),
        EtatsGestion.financier(b, Filtres(mois)),
        EtatsGestion.dons(b, Filtres(mois)),
        EtatsGestion.brouillard(b, 'CS-CAISSE', mois),
      ]) {
        expect((await Documents.rapport(b, r)).length, greaterThan(2000), reason: r.titre);
        final x = ExportXlsx.generer(r, structure: 'AH2');
        final z = ZipDecoder().decodeBytes(x);
        expect(z.findFile('xl/worksheets/sheet1.xml'), isNotNull);
        expect(String.fromCharCodes(z.findFile('xl/worksheets/sheet1.xml')!.content), contains('<sheetData>'));
      }
    });
  });

  test('saisie manuelle, soldes d’ouverture, clôture d’exercice, rapprochement, lettrage', () {
    final env = Environnement(debut: DateTime(2025, 12, 10, 9));
    final c = env.sessionCentrale('comptable');
    final b = env.central;
    expect(() => Comptabilite.saisir(env.sessionCentrale('caisse'), entite: 'CS', journal: 'OD', libelle: 'x', lignes: const []),
        throwsA(isA<DroitRefuse>()));
    expect(
        () => Comptabilite.saisir(c, entite: 'CS', journal: 'AN', libelle: 'Ouverture', lignes: const [
              LigneSaisie('5211', debit: 1000000),
              LigneSaisie('1011', credit: 900000),
            ]),
        throwsA(isA<RegleMetier>()));
    Comptabilite.saisir(c, entite: 'CS', journal: 'AN', libelle: "Soldes d'ouverture", lignes: const [
      LigneSaisie('5211', debit: 1000000),
      LigneSaisie('1011', credit: 1000000),
    ]);
    expect(Tresorerie.solde(b, 'CS-BQ'), 0, reason: 'la saisie comptable ne crée pas de mouvement de trésorerie');
    expect(Moteur.solde(b, 'CS', '5211'), 1000000);
    // Une recette en 2025, puis clôture de l'exercice 2025.
    Actes.enregistrer(c, activite: 'LAB', actes: const [DemandeActe('LAB-NFS')], mode: Modes.especes);
    env.horloge.le(2026, 1, 5);
    Comptabilite.cloturerExercice(c, entite: 'CS', annee: 2025);
    expect(Moteur.solde(b, 'CS', '7'), 0);
    expect(Moteur.solde(b, 'CS', '1311'), -3500);
    expect(EtatsComptables.bilan(b, 'CS', '2026-01-05').synthese.last.$2, fcfa(0));
    expect(EtatsComptables.compteResultat(b, 'CS', const Periode('2025-01-01', '2025-12-31')).synthese.last.$2, fcfa(3500));
    expect(() => Comptabilite.cloturerExercice(c, entite: 'CS', annee: 2025), throwsA(isA<RegleMetier>()));
    // Rapprochement bancaire.
    Tresorerie.virement(c, source: 'CS-CAISSE', destination: 'CS-BQ', montant: 3000, reference: 'BORD-1');
    Comptabilite.saisirReleveBancaire(c, tresorerie: 'CS-BQ', date: '2026-01-05', solde: 0);
    var r = EtatsComptables.rapprochement(b, 'CS-BQ', '2026-01-05');
    expect(r.sections.first.lignes.length, 1);
    final m = Comptabilite.mouvementsAvecCle(b, 'CS-BQ').single;
    Comptabilite.pointer(c, entite: 'CS', mouvements: [m['cle'] as String]);
    r = EtatsComptables.rapprochement(b, 'CS-BQ', '2026-01-05');
    expect(r.sections.first.lignes, isEmpty);
    // Lettrage d'une créance réglée.
    final pat = Patients.creer(c, nom: 'LETTRE').d<String>('id');
    Actes.enregistrer(c, activite: 'CONS', actes: const [DemandeActe('CONS-GEN')], mode: Modes.credit, patient: pat);
    Actes.reglerCreance(c, tiers: pat, montant: 2000, mode: Modes.especes);
    final lignes = Comptabilite.lignesTiers(b, 'CS', '4111', pat);
    expect(lignes.length, 2);
    expect(() => Comptabilite.lettrer(c, entite: 'CS', compte: '4111', tiers: pat, lignes: [lignes.first['cle'] as String]), throwsA(isA<RegleMetier>()));
    Comptabilite.lettrer(c, entite: 'CS', compte: '4111', tiers: pat, lignes: [for (final l in lignes) l['cle'] as String]);
    expect(Comptabilite.lignesTiers(b, 'CS', '4111', pat).every((l) => l['code'] == 'A'), isTrue);
  });

  test('alerte de déficit et de trésorerie insuffisante', () {
    final env = Environnement(debut: DateTime(2026, 11, 10, 9));
    final c = env.sessionCentrale('comptable');
    Actes.enregistrer(c, activite: 'LAB', actes: const [DemandeActe('LAB-NFS')], mode: Modes.especes);
    Tresorerie.depense(c, entite: 'CS', beneficiaire: 'ENEO', motif: 'Électricité', compteCharge: '6052', activite: 'LAB', montant: 3000);
    expect(Rapports.alertes(env.central).where((a) => a['titre']!.startsWith('Déficit')), isEmpty);
    Comptabilite.saisir(c, entite: 'CS', journal: 'OD', libelle: 'Loyer', lignes: const [
      LigneSaisie('6221', debit: 50000, activite: 'ADM_CS'),
      LigneSaisie('4011', credit: 50000),
    ]);
    final al = Rapports.alertes(env.central);
    expect(al.any((a) => a['titre'] == 'Déficit du mois : Centre de santé'), isTrue);
    expect(al.any((a) => a['titre'] == 'Activité déficitaire ce mois'), isFalse);
  });
}
