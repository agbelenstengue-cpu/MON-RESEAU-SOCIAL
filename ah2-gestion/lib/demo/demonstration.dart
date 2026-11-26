/// Données de démonstration FICTIVES (§14) : utilisateurs, appareils,
/// patients, actes, versements de désintoxication, dons, dépenses.
library;

import 'dart:math';

import '../modules/actes/actes.dart';
import '../modules/desintox/desintox.dart';
import '../modules/dons/dons.dart';
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
  static Map<String, String> installerCentral(Base b) {
    initialiserModules();
    Parametrage.installerPcCentral(b, motDePasseAdmin: motDePasse);
    final admin = Session.pour(b, 'admin');
    for (final u in [
      ['comptable', 'M. Ekotto', 'comptable', null],
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
