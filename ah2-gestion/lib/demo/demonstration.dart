/// Données de démonstration FICTIVES (§14) : utilisateurs, appareils,
/// patients, actes, versements de désintoxication, dons, dépenses.
library;

import 'dart:math';
import 'dart:typed_data';

import '../modules/actes/actes.dart';
import '../modules/desintox/desintox.dart';
import '../modules/dons/dons.dart';
import '../modules/hospitalisation/hospitalisation.dart';
import '../modules/immobilisations/immobilisations.dart';
import '../modules/paie/paie.dart';
import '../modules/stocks/stocks.dart';
import '../modules/modules.dart';
import '../modules/parametrage/parametrage.dart';
import '../modules/patients/patients.dart';
import '../modules/tresorerie/tresorerie.dart';
import '../noyau/base.dart';
import '../noyau/session.dart';

class Demo {
  /// Mot de passe de tous les comptes de démonstration.
  static const motDePasse = 'demo1234';

  /// Installe un PC central avec des utilisateurs et deux téléphones.
  /// Renvoie les clés de synchronisation des téléphones.
  static Map<String, String> installerCentral(Base b, {Uint8List? logo}) {
    initialiserModules();
    Parametrage.installerPcCentral(b, motDePasseAdmin: motDePasse, logo: logo);
    b.transaction(() {
      b.definirParam('demonstration', '1');
      b.exec("UPDATE utilisateurs SET nom='M. Ekotto' WHERE identifiant='comptable'");
    });
    final admin = Session.pour(b, 'admin');
    for (final u in [
      ['caisse', 'Mme Ngo Bassa', 'caissier', null],
      ['labo', 'M. Fouda (laboratoire)', 'agent', 'LAB'],
      ['consult', 'Dr Abena (consultations)', 'agent', 'CONS'],
      ['desintox', 'Mme Essomba (désintoxication)', 'agent', 'DESINTOX'],
      ['resp_labo', 'Dr Manga (resp. laboratoire)', 'responsable', 'LAB'],
      ['direction', 'Mme la Présidente', 'direction', null],
      ['auditeur', 'Cabinet d’audit', 'auditeur', null],
    ]) {
      Parametrage.ajouterUtilisateur(admin,
          identifiant: u[0]!, nom: u[1]!, role: u[2]!, motDePasse: motDePasse, activite: u[3], code: '1234');
    }
    return {
      'T01': Parametrage.ajouterAppareil(admin, code: 'T01', nom: 'Téléphone laboratoire', type: 'telephone'),
      'T02': Parametrage.ajouterAppareil(admin, code: 'T02', nom: 'Téléphone désintoxication', type: 'telephone'),
    };
  }

  static const _noms = [
    ['NKOULOU', 'Brigitte', 'F'], ['MBARGA', 'Jean-Paul', 'M'], ['ATANGANA', 'Rose', 'F'], ['FOUDA', 'Éric', 'M'],
    ['NGONO', 'Marie', 'F'], ['ESSOMBA', 'Patrick', 'M'], ['BELLA', 'Christine', 'F'], ['OWONA', 'Serge', 'M'],
    ['MVONDO', 'Alice', 'F'], ['ABENA', 'Thierry', 'M'], ['ONANA', 'Solange', 'F'], ['NDZANA', 'Hervé', 'M'],
  ];

  /// Génère [jours] jours d'activité fictive sur le PC central (horloge simulée).
  static void donneesFictives(Base b, {int jours = 28}) {
    initialiserModules();
    final horlogeReelle = b.horloge;
    final aujourdhui = horlogeReelle();
    final r = Random(42);
    final comptable = Session.pour(b, 'comptable');
    final caisse = Session.pour(b, 'caisse');
    DateTime jour(int decalage, int heure, int minute) =>
        DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day, heure, minute).subtract(Duration(days: decalage));
    try {
      b.horloge = () => jour(jours, 8, 0);
      final patients = [
        for (final n in _noms)
          Patients.creer(caisse, nom: n[0], prenoms: n[1], sexe: n[2], contact: '6 9${r.nextInt(9)} ${r.nextInt(90) + 10} ${r.nextInt(90) + 10} ${r.nextInt(90) + 10}')
              .d<String>('id')
      ];
      // Stocks, lits et fournisseur de démonstration.
      for (final pr in [
        ['AMOX500', 'Amoxicilline 500 mg', 'PHM', 'gélule', 150, 50, 80],
        ['PARA500', 'Paracétamol 500 mg', 'PHM', 'comprimé', 50, 100, 20],
        ['ARTE', 'Artéméther-luméfantrine', 'PHM', 'boîte', 2500, 10, 1600],
        ['DIAZ', 'Diazépam 5 mg', 'PHM', 'comprimé', 100, 30, 45],
        ['TISANE', 'Tisane digestive', 'PHT', 'sachet', 1000, 10, 400],
        ['BANDE', 'Bandelettes glycémie', 'LAB', 'boîte', 0, 5, 6000],
      ]) {
        Stocks.enregistrerProduit(comptable,
            code: pr[0] as String, designation: pr[1] as String, stock: pr[2] as String, forme: pr[3] as String,
            prixVente: pr[4] as int, stockMinimum: pr[5] as int);
      }
      for (final l in ['C1-L1', 'C1-L2', 'C2-L1', 'C2-L2']) {
        Hospitalisation.enregistrerLit(comptable, code: l, chambre: 'Chambre ${l.substring(1, 2)}', categorie: 'Standard', tarif: 5000);
      }
      final fournisseur = Stocks.creerFournisseur(comptable, nom: 'Grossiste pharmaceutique de Yaoundé', contact: '6 90 00 00 00').d<String>('id');
      Stocks.entrer(comptable, stock: 'PHM', origine: 'achat', fournisseur: fournisseur, facture: 'F-2026-118', lignes: [
        LigneStock('AMOX500', 300, lot: 'AM-24-11', peremption: _iso(aujourdhui.add(const Duration(days: 300))), coutUnitaire: 80),
        LigneStock('PARA500', 1000, lot: 'PA-25-02', peremption: _iso(aujourdhui.add(const Duration(days: 500))), coutUnitaire: 20),
        LigneStock('ARTE', 40, lot: 'AR-25-01', peremption: _iso(aujourdhui.add(const Duration(days: 45))), coutUnitaire: 1600),
        LigneStock('DIAZ', 200, lot: 'DZ-25-03', peremption: _iso(aujourdhui.add(const Duration(days: 400))), coutUnitaire: 45),
      ]);
      Stocks.entrer(comptable, stock: 'PHT', origine: 'achat', fournisseur: fournisseur, lignes: [
        LigneStock('TISANE', 60, lot: 'TI-01', peremption: _iso(aujourdhui.add(const Duration(days: 200))), coutUnitaire: 400),
      ]);
      Stocks.entrer(comptable, stock: 'LAB', origine: 'achat', fournisseur: fournisseur, lignes: const [
        LigneStock('BANDE', 8, lot: 'BG-7', coutUnitaire: 6000),
      ]);
      // Personnel et immobilisations de démonstration.
      for (final e in [
        ['ABENA Paul', 'Médecin', 'CONS', 450000, 50000],
        ['NGO BASSA Marie', 'Caissière', 'ADM_CS', 120000, 15000],
        ['FOUDA Éric', 'Technicien de laboratoire', 'LAB', 150000, 20000],
      ]) {
        Paie.enregistrerEmploye(comptable,
            nom: e[0] as String, entite: 'CS', poste: e[1] as String, activite: e[2] as String, salaireBase: e[3] as int, primes: e[4] as int,
            embauche: '2024-01-02', contrat: 'CDI');
      }
      Paie.enregistrerEmploye(comptable, nom: 'TCHOUPO Alain', entite: 'ONG', poste: 'Animateur social', statut: 'benevole', salaireBase: 40000);
      Paie.calculer(comptable, entite: 'CS', periode: _iso(b.maintenant).substring(0, 7));
      Immobilisations.acquerir(comptable, entite: 'CS', designation: 'Microscope binoculaire', categorie: 'MED', valeur: 1200000, origine: 'achat',
          localisation: 'Laboratoire', activite: 'LAB', dateAcquisition: '2025-06-15');
      Immobilisations.acquerir(comptable, entite: 'CS', designation: 'Ordinateur de la caisse', categorie: 'INFO', valeur: 450000, origine: 'achat',
          localisation: 'Accueil', activite: 'ADM_CS', dateAcquisition: '2026-02-01');
      final donateur = Dons.creerDonateur(comptable, nom: 'Fondation Espoir Solidaire', type: 'fondation', pays: 'France').d<String>('id');
      final membre = Dons.creerDonateur(comptable, nom: 'M. Tchoupo (membre)', type: 'membre').d<String>('id');
      // Dossier de désintoxication de la maquette : 450 000 FCFA, 225 000 versés.
      final dossier = Desintox.inscrire(caisse,
          patient: patients[1],
          programme: 'RES-90',
          responsables: const [Responsable('MBARGA Thérèse', 'mère', '6 77 00 00 01'), Responsable('MBARGA Paul', 'oncle', '6 99 00 00 02')],
          echeancier: [
            for (var i = 0; i < 6; i++) Echeance(_iso(jour(jours - 4 - i * 5, 0, 0)), 75000),
          ]).d<String>('id');
      for (var d = jours; d >= 0; d--) {
        var minute = 0;
        void a(String act, List<String> codes, String mode, int p) {
          minute += 7 + r.nextInt(20);
          b.horloge = () => jour(d, 7 + minute ~/ 60, minute % 60);
          Actes.enregistrer(caisse,
              activite: act,
              actes: [for (final c in codes) DemandeActe(c)],
              mode: mode,
              patient: patients[p],
              reference: Modes.estMomo(mode) ? '${1000000000 + r.nextInt(899999999)}' : null,
              motifGratuite: mode == Modes.gratuit ? 'indigent' : null);
        }

        final n = 4 + r.nextInt(5);
        for (var i = 0; i < n; i++) {
          final mode = [Modes.especes, Modes.especes, Modes.especes, Modes.mtn, Modes.orange, Modes.credit, Modes.gratuit][r.nextInt(7)];
          switch (r.nextInt(3)) {
            case 0:
              a('LAB', [['LAB-GLY', 'LAB-NFS', 'LAB-GE', 'LAB-WID'][r.nextInt(4)]], mode, r.nextInt(patients.length));
            case 1:
              a('CONS', ['CONS-GEN'], mode, r.nextInt(patients.length));
            default:
              if (d % 3 == 0) a('MASS', ['MASS-30'], mode == Modes.credit ? Modes.especes : mode, r.nextInt(patients.length));
          }
        }
        if (d == jours - 1 || d == jours - 10 || d == jours - 20) {
          b.horloge = () => jour(d, 15, 30);
          final m = d == jours - 1 ? 50000 : (d == jours - 10 ? 100000 : 75000);
          Desintox.verser(caisse,
              dossierId: dossier, montant: m, payeur: d == jours - 20 ? 'MBARGA Paul' : 'MBARGA Thérèse', mode: d == jours - 20 ? Modes.mtn : Modes.especes,
              reference: d == jours - 20 ? '7654321098' : null);
        }
        if (d % 2 == 0) {
          b.horloge = () => jour(d, 14, 10);
          Stocks.sortir(comptable, stock: 'PHM', type: 'vente', lignes: [LigneStock(['AMOX500', 'PARA500', 'ARTE'][d % 3], 1 + r.nextInt(6))]);
        }
        if (d == 6) {
          b.horloge = () => jour(d, 10, 0);
          final sejour = Hospitalisation.admettre(caisse, patient: patients[4], lit: 'C1-L1', caution: 20000).d<String>('id');
          Actes.enregistrer(caisse, activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.credit, sejour: sejour);
          Stocks.sortir(comptable, stock: 'PHM', type: 'delivrance_sejour', sejour: sejour, lignes: const [LigneStock('PARA500', 12)]);
          Stocks.sortir(comptable, stock: 'PHM', type: 'delivrance_desintox', dossierDesintox: dossier, facturer: false, lignes: const [LigneStock('DIAZ', 20)]);
        }
        if (d % 7 == 0 && Tresorerie.solde(b, 'CS-CAISSE') > 18500) {
          b.horloge = () => jour(d, 16, 0);
          Tresorerie.depense(caisse,
              entite: 'CS', beneficiaire: 'ENEO', motif: 'Facture électricité', compteCharge: '6052', activite: 'ADM_CS', montant: 18500,
              pieceJointe: 'facture-eneo.jpg');
        }
        if (d == 12) {
          b.horloge = () => jour(d, 11, 0);
          Dons.recevoir(comptable, donateur: donateur, montant: 1500000, nature: 'virement', affectation: 'PROG', reference: 'VIR-FES-2026-11');
          Dons.recevoir(comptable, donateur: membre, montant: 50000, nature: 'especes');
        }
      }
    } finally {
      b.horloge = horlogeReelle;
    }
  }

  static String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
