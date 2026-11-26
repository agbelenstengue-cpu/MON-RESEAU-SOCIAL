/// Phase 3 : paie, immobilisations, notes annexes, prévisions, export Sage.
library;

import 'dart:convert';

import 'package:ah2_gestion/demo/demonstration.dart';
import 'package:ah2_gestion/modules/comptabilite/moteur.dart';
import 'package:ah2_gestion/modules/immobilisations/immobilisations.dart';
import 'package:ah2_gestion/modules/paie/paie.dart';
import 'package:ah2_gestion/modules/tresorerie/tresorerie.dart';
import 'package:ah2_gestion/noyau/outils.dart';
import 'package:ah2_gestion/rapports/etats_comptables.dart';
import 'package:ah2_gestion/rapports/etats_phase3.dart';
import 'package:ah2_gestion/rapports/modele.dart';
import 'package:test/test.dart';

import 'aide.dart';

void main() {
  test('paie complète', () {
    final env = Environnement(debut: DateTime(2026, 6, 25, 9));
    final c = env.sessionCentrale('comptable');
    final b = env.central;
    final inf = Paie.enregistrerEmploye(c, nom: 'NGO Marie', entite: 'CS', poste: 'Infirmière', salaireBase: 200000, primes: 25000, cnps: '123456').d<String>('id');
    final med = Paie.enregistrerEmploye(c, nom: 'ABENA Paul', entite: 'CS', poste: 'Médecin', salaireBase: 900000).d<String>('id');
    final ben = Paie.enregistrerEmploye(c, nom: 'TCHOUPO', entite: 'CS', statut: 'benevole', salaireBase: 30000).d<String>('id');
    // Fonds de départ en caisse (soldes d'ouverture) pour payer l'avance.
    b.transaction(() => b.exec("INSERT INTO mouvements_tresorerie(uuid_op, tresorerie, date, horodatage, montant, libelle) VALUES ('init','CS-CAISSE','2026-06-01','2026-06-01T08:00:00',2000000,'Fonds')"));
    Paie.avance(c, employe: inf, montant: 50000);
    expect(Paie.avancesEnCours(b, inf), 50000);
    final op = Paie.calculer(c, entite: 'CS', periode: '2026-06', variables: {inf: (10000, 0)});
    final bulletins = {for (final x in op.d<List>('bulletins').cast<Map>()) x['employe']: x};
    final bi = bulletins[inf]!;
    // Brut = 200 000 + 25 000 + 10 000 ; CNPS salariale 4,20 % ; crédit foncier 1 %.
    expect(bi['brut'], 235000);
    expect(bi['cnps_salarial'], (235000 * 420 / 10000).round());
    expect(bi['etat_salarial'], (235000 * 100 / 10000).round());
    expect(bi['avances'], 50000);
    expect(bi['net'], 235000 - bi['cnps_salarial'] - bi['etat_salarial'] - 50000);
    // Plafond CNPS (750 000) appliqué au médecin.
    expect(bulletins[med]!['cnps_salarial'], (750000 * 420 / 10000).round());
    // Bénévole indemnisé : pas de cotisations.
    expect(bulletins[ben]!['retenues'], 0);
    expect(bulletins[ben]!['net'], 30000);
    expect(Paie.avancesEnCours(b, inf), 0);
    expect(() => Paie.calculer(c, entite: 'CS', periode: '2026-06'), throwsA(isA<RegleMetier>()));
    // Comptabilité : 661 = total brut ; 4221 = total net dû.
    final totalBrut = bulletins.values.fold<int>(0, (t, x) => t + (x['brut'] as int));
    final totalNet = bulletins.values.fold<int>(0, (t, x) => t + (x['net'] as int));
    expect(Moteur.solde(b, 'CS', '6611'), totalBrut);
    expect(-Moteur.solde(b, 'CS', '4221'), totalNet);
    expect(Moteur.ecrituresDesequilibrees(b), isEmpty);
    // Paiement des salaires.
    Paie.payer(c, entite: 'CS', periode: '2026-06', mode: Modes.especes);
    expect(Moteur.solde(b, 'CS', '4221'), 0);
    expect(totauxPaie(b, 'CS', '2026-06')['reste_a_payer'], 0);
    // Bulletin et livre de paie.
    final bu = EtatsPaie.bulletin(b, inf, '2026-06');
    expect(bu.synthese.last.$2, fcfa(bi['net'] as int));
    final livre = EtatsPaie.livre(b, 'CS', const Periode('2026-06-01', '2026-06-30'));
    expect(livre.sections.first.ligneTotal![6], totalNet);
    final cnps = EtatsPaie.declaration(b, 'CS', '2026-06', organisme: 'CNPS');
    expect(cnps.sections.first.lignes.length, 3);
    // Taux modifié et daté : s'applique aux périodes suivantes seulement.
    Paie.enregistrerRubrique(c, code: 'CFC_SAL', libelle: 'Crédit foncier (part salariale)', nature: 'retenue_salariale', organisme: 'ETAT', taux: 150, depuis: '2026-07-01');
    expect(Paie.rubriques(b, '2026-06').firstWhere((r) => r['code'] == 'CFC_SAL')['taux'], 100);
    expect(Paie.rubriques(b, '2026-07').firstWhere((r) => r['code'] == 'CFC_SAL')['taux'], 150);
  });

  test('immobilisations : acquisition, amortissements mensuels, sortie, registre', () {
    final env = Environnement(debut: DateTime(2026, 1, 15, 9));
    final c = env.sessionCentrale('comptable');
    final b = env.central;
    final op = Immobilisations.acquerir(c, entite: 'CS', designation: 'Microscope', categorie: 'MED', valeur: 1200000, origine: 'achat', localisation: 'Laboratoire', activite: 'LAB');
    final id = op.d<String>('id');
    expect(Moteur.solde(b, 'CS', '2411'), 1200000);
    expect(-Moteur.solde(b, 'CS', '4011'), 1200000);
    env.horloge.le(2026, 3, 31);
    Immobilisations.amortir(c, entite: 'CS', periode: '2026-03');
    // 3 mois sur 60 : 60 000.
    expect(Moteur.solde(b, 'CS', '6813'), 60000);
    expect(Immobilisations.amortir(c, entite: 'CS', periode: '2026-03'), isNull, reason: 'pas de double dotation');
    final reg = EtatsImmobilisations.registre(b, 'CS', '2026-03-31');
    expect(reg.sections.first.lignes.single[8], 1140000);
    // Don d'un ordinateur à l'ONG.
    Immobilisations.acquerir(c, entite: 'ONG', designation: 'Ordinateur', categorie: 'INFO', valeur: 360000, origine: 'don');
    expect(-Moteur.solde(b, 'ONG', '1411'), 360000);
    // Cession du microscope.
    Immobilisations.sortir(c, id, motif: 'cession', prixCession: 1000000);
    expect(Moteur.solde(b, 'CS', '2411'), 0);
    expect(Moteur.solde(b, 'CS', '2841'), 0);
    expect(Moteur.solde(b, 'CS', '8121'), 1140000);
    expect(-Moteur.solde(b, 'CS', '8221'), 1000000);
    expect(EtatsComptables.bilan(b, 'CS', '2026-12-31').synthese.last.$2, fcfa(0));
    final t = EtatsImmobilisations.tableauAmortissements(b, 'ONG', 2026);
    expect(t.sections.first.lignes.single[5], 360000 * 10 ~/ 36, reason: 'acquis en mars : 10 mois en 2026');
  });

  test('notes annexes, prévisions, courbes 12 mois, export Sage', () {
    final env = Environnement(debut: DateTime(2026, 11, 26, 9));
    Demo.donneesFictives(env.central);
    final b = env.central;
    final notes = EtatsFinanciersAnnexes.notes(b, 'CS', 2026);
    expect(notes.sections, isNotEmpty);
    final p = Previsions.tresorerie(b, 'CS', 30);
    expect(p['solde_previsionnel'],
        (p['solde_actuel'] as int) + (p['flux_courants'] as int) + (p['salaires'] as int) + (p['echeances_desintox'] as int) + (p['tranches_subventions'] as int) + (p['dettes_fournisseurs'] as int));
    final courbes = Previsions.douzeMois(b);
    expect(courbes.length, 12);
    expect(courbes.last['recettes'] as int, greaterThan(0));
    final sage = ExportSage.generer(b, 'CS', const Periode('2026-11-01', '2026-11-30'));
    final lignes = latin1.decode(sage).split('\r\n').where((l) => l.isNotEmpty).toList();
    expect(lignes.first, 'Journal;Date;Compte;Tiers;Piece;Libelle;Debit;Credit');
    var d = 0, cr = 0;
    for (final l in lignes.skip(1)) {
      final c = l.split(';');
      expect(c.length, 8);
      d += int.parse(c[6]);
      cr += int.parse(c[7]);
    }
    expect(d, cr, reason: 'export équilibré');
  });
}

