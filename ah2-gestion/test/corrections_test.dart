/// Corrections demandées après le premier essai : laboratoire (client divers,
/// statuts), dépenses par nature, remèdes au litre, fiche de suivi, compte
/// rendu du soir, saisie à une date passée, audit, statistiques.
library;

import 'package:ah2_gestion/demo/demonstration.dart';
import 'package:ah2_gestion/modules/actes/actes.dart';
import 'package:ah2_gestion/modules/comptabilite/moteur.dart';
import 'package:ah2_gestion/modules/depenses/depenses.dart';
import 'package:ah2_gestion/modules/desintox/desintox.dart';
import 'package:ah2_gestion/modules/patients/patients.dart';
import 'package:ah2_gestion/modules/stocks/stocks.dart';
import 'package:ah2_gestion/modules/tresorerie/tresorerie.dart';
import 'package:ah2_gestion/noyau/outils.dart';
import 'package:ah2_gestion/noyau/session.dart';
import 'package:ah2_gestion/rapports/catalogue.dart';
import 'package:ah2_gestion/rapports/etats_suivi_audit.dart';
import 'package:ah2_gestion/rapports/modele.dart';
import 'package:ah2_gestion/rapports/statistiques.dart';
import 'package:test/test.dart';

import 'aide.dart';

void main() {
  test('laboratoire : client divers nommé, statuts demandé, réalisé, remis', () {
    final env = Environnement(debut: DateTime(2026, 11, 2, 9));
    final c = env.sessionCentrale('comptable');
    final b = env.central;
    final op = Actes.enregistrer(c, activite: 'LAB', actes: const [DemandeActe('LAB-GS'), DemandeActe('LAB-TDR')], mode: Modes.especes,
        client: 'Mme Atangana', statut: 'demande');
    expect(b.valeur('SELECT client FROM actes WHERE uuid_op=? LIMIT 1', [op.uuid]), 'Mme Atangana');
    expect(b.valeur('SELECT statut FROM actes WHERE uuid_op=? LIMIT 1', [op.uuid]), 'demande');
    Actes.changerStatut(c, op.uuid, 'realise');
    Actes.changerStatut(c, op.uuid, 'remis');
    expect(b.valeur('SELECT statut FROM actes WHERE uuid_op=? LIMIT 1', [op.uuid]), 'remis');
    final anonyme = Actes.enregistrer(c, activite: 'LAB', actes: const [DemandeActe('LAB-VIH')], mode: Modes.especes);
    expect(anonyme.d('client'), 'Client divers');
  });

  test('dépense par nature : le compte est trouvé sans le choisir ; dépenses répétitives', () {
    final env = Environnement(debut: DateTime(2026, 11, 2, 9));
    final c = env.sessionCentrale('comptable');
    final b = env.central;
    b.transaction(() => b.exec(
        "INSERT INTO mouvements_tresorerie(uuid_op, tresorerie, date, horodatage, montant, libelle) VALUES ('init','CS-CAISSE','2026-11-01','2026-11-01T08:00:00',500000,'Fonds')"));
    final natures = Depenses.natures(b, 'CS');
    expect(natures.map((n) => n['code']), containsAll(['ELEC', 'EAU', 'CARB']));
    final compteElec = natures.firstWhere((n) => n['code'] == 'ELEC')['compte'] as String;
    final avant = Moteur.solde(b, 'CS', compteElec);
    Tresorerie.depense(c, entite: 'CS', beneficiaire: 'ENEO', nature: 'ELEC', montant: 20000, tresorerie: 'CS-CAISSE');
    expect(Moteur.solde(b, 'CS', compteElec) - avant, 20000);
    expect(b.valeur("SELECT nature FROM depenses WHERE beneficiaire='ENEO'"), 'ELEC');
    Depenses.enregistrerModele(c, entite: 'CS', nature: 'LOYER', beneficiaire: 'Bailleur', montant: 20000, jour: 5);
    var aPayer = Depenses.aPayerCeMois(b);
    expect(aPayer.single['payee'], false);
    Tresorerie.depense(c, entite: 'CS', beneficiaire: 'Bailleur', nature: 'LOYER', montant: 20000, tresorerie: 'CS-CAISSE');
    aPayer = Depenses.aPayerCeMois(b);
    expect(aPayer.single['payee'], true);
    expect(Moteur.ecrituresDesequilibrees(b), isEmpty);
  });

  test('remèdes au litre : prix réservé au comptable, distribution du jour, fiche de suivi', () {
    final env = Environnement(debut: DateTime(2026, 11, 2, 9));
    final c = env.sessionCentrale('comptable');
    final b = env.central;
    expect(() => Stocks.prixLitre(Session.pour(b, 'caisse'), 'AE', 1500), throwsA(isA<DroitRefuse>()));
    Stocks.prixLitre(c, 'AE', 1500);
    final fournisseur = Stocks.creerFournisseur(c, nom: 'Tradipraticien').d<String>('id');
    // Un bidon de 25 litres (la taille varie).
    Stocks.entrer(c, stock: 'PHT', origine: 'achat', fournisseur: fournisseur, lignes: const [LigneStock('AE', 25)]);
    expect(Stocks.quantite(b, 'AE'), 25);
    final dossiers = [
      for (final n in ['UN', 'DEUX', 'TROIS'])
        Desintox.inscrire(c, patient: Patients.creer(c, nom: n).d<String>('id'), programme: 'RES-30', responsables: const [Responsable('A', 'b', '1')])
            .d<String>('id')
    ];
    // Un geste : 1 litre par patient présent.
    Stocks.servirRemede(c, produit: 'AE', parDossier: {for (final d in dossiers) d: 1});
    env.horloge.avancer(jours: 1);
    Stocks.servirRemede(c, produit: 'AE', parDossier: {for (final d in dossiers) d: 1});
    expect(Stocks.quantite(b, 'AE'), 19);
    // Le prix change : le passé ne bouge pas (coût du litre reçu).
    Stocks.prixLitre(c, 'AE', 2000);
    expect(b.valeur('SELECT medicaments_compris FROM desintox_dossiers WHERE id=?', [dossiers.first]), 3000);
    final fiche = EtatsSuivi.desintox(b, dossiers.first);
    expect(fiche.sections.first.lignes.length, 2);
    expect(fiche.sections.first.ligneTotal![4], 3000);
    expect(fiche.synthese.any((s) => s.$1.startsWith('Coût des produits compris') && s.$2 == fcfa(3000)), isTrue);
    expect(Moteur.ecrituresDesequilibrees(b), isEmpty);
    // Le changement de prix figure dans l'état des modifications.
    final modifs = EtatsAudit.modifications(b, const Periode('2026-11-01', '2026-11-30'));
    expect(modifs.sections.first.lignes.where((l) => '${l[1]}'.contains('prix_litre:AE')).length, 2);
  });

  test('compte rendu du soir avec observations du comptable', () {
    final env = Environnement(debut: DateTime(2026, 11, 2, 9));
    final c = env.sessionCentrale('comptable');
    final b = env.central;
    Actes.enregistrer(c, activite: 'LAB', actes: const [DemandeActe('LAB-GS')], mode: Modes.especes, client: 'Client divers');
    Depenses.observer(c, date: '2026-11-02', observations: 'Coupure de courant de 2 heures.');
    final cr = EtatsSuivi.compteRendu(b, '2026-11-02');
    expect(cr.sections.first.lignes, isNotEmpty);
    expect(cr.sections.last.lignes.single.single, 'Coupure de courant de 2 heures.');
    // Modifiable le soir même.
    Depenses.observer(c, date: '2026-11-02', observations: 'RAS.');
    expect(Depenses.observations(b, '2026-11-02'), 'RAS.');
  });

  test('saisie à une date passée : réservée, double date, jamais dans le futur', () {
    final env = Environnement(debut: DateTime(2026, 11, 2, 9));
    final b = env.central;
    final c = env.sessionCentrale('comptable');
    b.dateSaisie = '2026-02-10';
    final op = Actes.enregistrer(c, activite: 'LAB', actes: const [DemandeActe('LAB-GS')], mode: Modes.especes);
    expect(op.dateOp, '2026-02-10');
    expect(op.donnees['_saisi_le'], startsWith('2026-11-02'));
    expect(() => Actes.enregistrer(Session.pour(b, 'caisse'), activite: 'LAB', actes: const [DemandeActe('LAB-GS')], mode: Modes.especes),
        throwsA(isA<DroitRefuse>()));
    b.dateSaisie = '2026-12-01';
    expect(() => Actes.enregistrer(c, activite: 'LAB', actes: const [DemandeActe('LAB-GS')], mode: Modes.especes), throwsA(anything));
    b.dateSaisie = null;
    final r = EtatsAudit.saisiesRetroactives(b, const Periode('2026-01-01', '2026-12-31'));
    expect(r.sections.first.lignes.length, 1);
  });

  test('statistiques et tous les états du catalogue sur la démonstration', () {
    final env = Environnement(debut: DateTime(2026, 11, 2, 9));
    final b = env.central;
    Demo.donneesFictives(b);
    final st = Statistiques.calculer(b, const Periode('2026-10-01', '2026-11-02'));
    expect(st.recettes.points.length, 33);
    expect(st.recettes.total, greaterThan(0));
    final annuel = Statistiques.calculer(b, const Periode('2026-01-01', '2026-12-31'));
    expect(annuel.parMois, isTrue);
    expect(annuel.recettes.points.length, 12);
    expect(annuel.recettes.total, st.recettes.total);
    // Chaque état du catalogue se produit sans erreur.
    final p = Parametres(const Filtres(Periode('2026-10-01', '2026-11-02')), date: '2026-11-02');
    for (final d in Catalogue.tous) {
      if (d.filtres.contains(Filtre.patient) || d.filtres.contains(Filtre.employe)) continue;
      expect(() => d.produire(b, p), returnsNormally, reason: d.id);
    }
  });
}
