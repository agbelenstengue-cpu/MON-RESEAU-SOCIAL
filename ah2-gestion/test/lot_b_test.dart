/// Phase 2 : stocks (CUMP, FEFO, inventaire, conflits), achats,
/// hospitalisation, médicaments en désintoxication, carnets, avoirs.
library;

import 'package:ah2_gestion/modules/actes/actes.dart';
import 'package:ah2_gestion/modules/comptabilite/moteur.dart';
import 'package:ah2_gestion/modules/desintox/desintox.dart';
import 'package:ah2_gestion/modules/dons/dons.dart';
import 'package:ah2_gestion/modules/facturation/facturation.dart';
import 'package:ah2_gestion/modules/hospitalisation/hospitalisation.dart';
import 'package:ah2_gestion/modules/patients/patients.dart';
import 'package:ah2_gestion/modules/releves/releves.dart';
import 'package:ah2_gestion/modules/stocks/stocks.dart';
import 'package:ah2_gestion/modules/tresorerie/tresorerie.dart';
import 'package:ah2_gestion/noyau/outils.dart';
import 'package:ah2_gestion/noyau/session.dart';
import 'package:ah2_gestion/rapports/etats_comptables.dart';
import 'package:ah2_gestion/rapports/etats_stocks_hospitalisation.dart';
import 'package:ah2_gestion/rapports/modele.dart';
import 'package:test/test.dart';

import 'aide.dart';

String fournisseur(Session s) => Stocks.creerFournisseur(s, nom: 'LABOREX').d<String>('id');

void preparer(Environnement env) {
  final c = env.sessionCentrale('comptable');
  Stocks.enregistrerProduit(c, code: 'AMOX', designation: 'Amoxicilline 500 mg', stock: 'PHM', forme: 'gélule', prixVente: 150, stockMinimum: 20);
  Stocks.enregistrerProduit(c, code: 'PARA', designation: 'Paracétamol 500 mg', stock: 'PHM', prixVente: 50);
}

void main() {
  test('§13.9 stock calculé = entrées - sorties ; valorisation CUMP correcte ; FEFO', () {
    final env = Environnement(debut: DateTime(2026, 3, 1, 9));
    preparer(env);
    final c = env.sessionCentrale('comptable');
    final b = env.central;
    final f = fournisseur(c);
    Stocks.entrer(c, stock: 'PHM', origine: 'achat', fournisseur: f, lignes: const [
      LigneStock('AMOX', 100, lot: 'A1', peremption: '2026-12-31', coutUnitaire: 80),
    ]);
    env.horloge.avancer(heures: 1);
    Stocks.entrer(c, stock: 'PHM', origine: 'achat', fournisseur: f, lignes: const [
      LigneStock('AMOX', 50, lot: 'A0', peremption: '2026-06-30', coutUnitaire: 110),
    ]);
    // CUMP = (100 x 80 + 50 x 110) / 150 = 90.
    expect(Stocks.cump(b, 'AMOX'), 90);
    env.horloge.avancer(heures: 1);
    final v = Stocks.sortir(c, stock: 'PHM', type: 'vente', lignes: const [LigneStock('AMOX', 60)]);
    // FEFO : d'abord les 50 du lot A0 (périmé plus tôt), puis 10 du lot A1.
    final lots = v.d<List>('lignes').cast<Map>().map((l) => '${l['lot']}:${l['quantite']}').toList();
    expect(lots, ['A0:50', 'A1:10']);
    expect(Stocks.quantite(b, 'AMOX'), 150 - 60);
    expect(Stocks.cump(b, 'AMOX'), 90, reason: 'une sortie ne change pas le CUMP');
    env.horloge.avancer(heures: 1);
    Stocks.entrer(c, stock: 'PHM', origine: 'achat', fournisseur: f, lignes: const [
      LigneStock('AMOX', 90, lot: 'A2', peremption: '2027-03-31', coutUnitaire: 100),
    ]);
    expect(Stocks.cump(b, 'AMOX'), 95); // (90 x 90 + 90 x 100) / 180
    expect(Stocks.valeur(b, 'AMOX'), 180 * 95);
    // Comptabilité : stock 3111 = valeur ; dette fournisseur ; vente 7011 ; coût 6031.
    expect(Moteur.solde(b, 'CS', '3111'), 100 * 80 + 50 * 110 - 60 * 90 + 90 * 100);
    expect(-Moteur.solde(b, 'CS', '4011', tiers: f), 100 * 80 + 50 * 110 + 90 * 100);
    expect(-Moteur.solde(b, 'CS', '7011'), 60 * 150);
    expect(Tresorerie.solde(b, 'CS-CAISSE'), 60 * 150);
    expect(Moteur.ecrituresDesequilibrees(b), isEmpty);
    // Sortie supérieure au stock : refusée ; perte : motif et droit exigés.
    expect(() => Stocks.sortir(c, stock: 'PHM', type: 'vente', lignes: const [LigneStock('AMOX', 1000)]), throwsA(isA<RegleMetier>()));
    expect(() => Stocks.sortir(env.sessionCentrale('caisse'), stock: 'PHM', type: 'casse', motif: 'x', lignes: const [LigneStock('AMOX', 1)]),
        throwsA(anything));
    // Inventaire : 175 comptés pour 180 → manquant de 5, ajusté au CUMP.
    final lotsAvant = {for (final l in Stocks.lots(b, 'AMOX')) l['lot'] as String: l['quantite'] as int};
    Stocks.inventorier(c, stock: 'PHM', comptes: {
      for (final e in lotsAvant.entries) ('AMOX', e.key): e.key == 'A2' ? e.value - 5 : e.value,
    });
    expect(Stocks.quantite(b, 'AMOX'), 175);
    expect(EtatsStocks.inventaire(b, 'PHM').sections.first.ligneTotal![4], -5);
    // Règlement du fournisseur.
    Comptes.versement(env);
    Stocks.reglerFournisseur(c, fournisseur: f, montant: 5000, mode: Modes.especes);
    expect(-Moteur.solde(b, 'CS', '4011', tiers: f), 100 * 80 + 50 * 110 + 90 * 100 - 5000);
    // État des stocks : total = valeur calculée.
    final etat = EtatsStocks.etat(b, 'PHM', '2026-03-01');
    expect(etat.sections.first.ligneTotal![6], Stocks.valeur(b, 'AMOX') + Stocks.valeur(b, 'PARA'));
  });

  test('don en nature à la pharmacie : reçu par l’ONG (SYCEBNL) et transféré au centre', () {
    final env = Environnement();
    preparer(env);
    final c = env.sessionCentrale('comptable');
    final d = Dons.creerDonateur(c, nom: 'Fondation', type: 'fondation').d<String>('id');
    Stocks.entrer(c, stock: 'PHM', origine: 'don', donateur: d, lignes: const [
      LigneStock('PARA', 1000, lot: 'P1', peremption: '2027-01-31', coutUnitaire: 20),
    ]);
    final b = env.central;
    expect(-Moteur.solde(b, 'ONG', '7582'), 20000);
    expect(Moteur.solde(b, 'ONG', '4671'), 20000);
    expect(Moteur.solde(b, 'CS', '3111'), 20000);
    expect(-Moteur.solde(b, 'CS', '4671'), 20000);
    expect(b.entier("SELECT COUNT(*) FROM dons WHERE nature='nature'"), 1);
  });

  test('conflit de stock : deux téléphones vendent hors ligne le même stock ; signalé au comptable', () async {
    final env = Environnement();
    preparer(env);
    final c = env.sessionCentrale('comptable');
    Stocks.entrer(c, stock: 'PHM', origine: 'achat', fournisseur: fournisseur(c), lignes: const [
      LigneStock('PARA', 10, lot: 'P1', peremption: '2027-01-31', coutUnitaire: 20),
    ]);
    final t1 = await env.telephone('T01');
    final t2 = await env.telephone('T02');
    expect(Stocks.quantite(t1.base, 'PARA'), 10);
    env.wifi = false;
    // Le pharmacien n'a pas de compte ici : l'agent de laboratoire a le droit stocks.
    Stocks.sortir(t1.session('labo'), stock: 'PHM', type: 'vente', lignes: const [LigneStock('PARA', 8)]);
    Stocks.sortir(t2.session('labo'), stock: 'PHM', type: 'vente', lignes: const [LigneStock('PARA', 6)]);
    env.wifi = true;
    await t1.sync();
    await t2.sync();
    expect(Stocks.quantite(env.central, 'PARA'), -4);
    expect(env.central.entier("SELECT COUNT(*) FROM anomalies_sync WHERE type='conflit_stock'"), 1);
  });

  test('hospitalisation : caution, journées, actes et produits du séjour, sortie, facture', () {
    final env = Environnement(debut: DateTime(2026, 5, 1, 9));
    preparer(env);
    final c = env.sessionCentrale('comptable');
    final b = env.central;
    Hospitalisation.enregistrerLit(c, code: 'L1', chambre: 'Chambre 1', categorie: 'Standard', tarif: 5000);
    Stocks.entrer(c, stock: 'PHM', origine: 'achat', fournisseur: fournisseur(c), lignes: const [
      LigneStock('PARA', 100, lot: 'P1', peremption: '2027-01-31', coutUnitaire: 20),
    ]);
    final p = Patients.creer(c, nom: 'HOSPI').d<String>('id');
    final s = Hospitalisation.admettre(c, patient: p, lit: 'L1', caution: 20000).d<String>('id');
    expect(() => Hospitalisation.admettre(c, patient: Patients.creer(c, nom: 'AUTRE').d<String>('id'), lit: 'L1'), throwsA(isA<RegleMetier>()));
    expect(Hospitalisation.tauxOccupation(b), 1.0);
    Actes.enregistrer(c, activite: 'LAB', actes: const [DemandeActe('LAB-NFS')], mode: Modes.especes, sejour: s);
    Stocks.sortir(c, stock: 'PHM', type: 'delivrance_sejour', sejour: s, lignes: const [LigneStock('PARA', 10)]);
    env.horloge.avancer(jours: 3);
    final sit = Hospitalisation.situation(b, s);
    expect(sit['journees'], 3);
    expect(sit['total'], 3 * 5000 + 3500 + 10 * 50);
    final facture = EtatsHospitalisation.facture(b, s);
    expect(facture.sections.first.ligneTotal!.last, sit['total']);
    Hospitalisation.sortir(c, s);
    // Total 19 000 < caution 20 000 : l'excédent de 1 000 est remboursé, plus rien n'est dû.
    expect(Actes.creance(b, p), 0);
    expect(b.entier("SELECT SUM(montant) FROM mouvements_tresorerie WHERE libelle LIKE 'Remboursement de caution%'"), -1000);
    expect(Moteur.solde(b, 'CS', '4191'), 0);
    expect(Hospitalisation.litLibre(b, 'L1'), isTrue);
    expect(Moteur.ecrituresDesequilibrees(b), isEmpty);
  });

  test('désintoxication : médicaments compris dans le forfait ou facturés en plus ; rapport', () {
    final env = Environnement();
    preparer(env);
    final c = env.sessionCentrale('comptable');
    final b = env.central;
    Stocks.entrer(c, stock: 'PHM', origine: 'achat', fournisseur: fournisseur(c), lignes: const [
      LigneStock('PARA', 100, lot: 'P1', peremption: '2027-01-31', coutUnitaire: 20),
    ]);
    final p = Patients.creer(c, nom: 'DETOX').d<String>('id');
    final d = Desintox.inscrire(c, patient: p, programme: 'RES-30', responsables: const [Responsable('A', 'b', '1')]).d<String>('id');
    Stocks.sortir(c, stock: 'PHM', type: 'delivrance_desintox', dossierDesintox: d, facturer: false, lignes: const [LigneStock('PARA', 10)]);
    expect(Desintox.situation(b, d).total, 180000, reason: 'compris : le reste à payer ne change pas');
    Stocks.sortir(c, stock: 'PHM', type: 'delivrance_desintox', dossierDesintox: d, facturer: true, lignes: const [LigneStock('PARA', 20)]);
    final sit = Desintox.situation(b, d);
    expect(sit.total, 180000 + 20 * 50);
    expect(Actes.creance(b, p), sit.reste);
    expect(b.valeur('SELECT medicaments_compris FROM desintox_dossiers WHERE id=?', [d]), 10 * 20);
    final r = Desintox.rapportSortie(b, d);
    expect((r['medicaments'] as List).length, 2);
  });

  test('relevé journalier des sorties de la pharmacie ; carnets de massage ; avoir', () {
    final env = Environnement(debut: DateTime(2026, 5, 1, 9));
    preparer(env);
    final c = env.sessionCentrale('comptable');
    final b = env.central;
    Stocks.entrer(c, stock: 'PHM', origine: 'achat', fournisseur: fournisseur(c), lignes: const [
      LigneStock('PARA', 100, lot: 'P1', peremption: '2027-01-31', coutUnitaire: 20),
    ]);
    Stocks.sortir(c, stock: 'PHM', type: 'vente', lignes: const [LigneStock('PARA', 4)]);
    final carnet = Facturation.vendreCarnet(c, acte: 'MASS-30', seances: 5, montant: 20000).d<String>('id');
    Facturation.consommerSeance(c, carnet, praticien: 'M. Ondoa');
    for (var i = 0; i < 4; i++) {
      Facturation.consommerSeance(c, carnet);
    }
    expect(() => Facturation.consommerSeance(c, carnet), throwsA(isA<RegleMetier>()));
    env.horloge.avancer(jours: 1);
    for (final t in ['T01', 'T02']) {
      b.exec("UPDATE appareils SET statut='inactif' WHERE code=?", [t]);
    }
    Releves.generer(c, activite: 'PHM', date: '2026-05-01');
    final contenu = Releves.contenu(b, 'RJS-PHM-2026-0001');
    expect((contenu['lignes'] as List).single['acte'], contains('Paracétamol'));
    Releves.generer(c, activite: 'MASS', date: '2026-05-01');
    expect((Releves.contenu(b, 'RJA-MASS-2026-0001')['synthese'] as Map)['nombre_actes'], 5);
    // Avoir sur une créance.
    final p = Patients.creer(c, nom: 'AVOIR').d<String>('id');
    Actes.enregistrer(c, activite: 'CONS', actes: const [DemandeActe('CONS-SPE')], mode: Modes.credit, patient: p);
    expect(() => Facturation.avoir(env.sessionCentrale('caisse'), tiers: p, montant: 1000, motif: 'x', compteProduit: '7061'), throwsA(isA<DroitRefuse>()));
    Facturation.avoir(c, tiers: p, montant: 1000, motif: 'Erreur de tarif', compteProduit: '7061', activite: 'CONS');
    expect(Actes.creance(b, p), 4000);
    expect(EtatsComptables.balanceTiers(b, 'CS', const Periode('2026-01-01', '2026-12-31')).sections.first.lignes, isNotEmpty);
  });
}

class Comptes {
  /// Alimente la caisse pour pouvoir payer un fournisseur.
  static void versement(Environnement env) =>
      Actes.enregistrer(env.sessionCentrale('caisse'), activite: 'CONS', actes: const [DemandeActe('CONS-SPE', quantite: 2)], mode: Modes.especes);
}

