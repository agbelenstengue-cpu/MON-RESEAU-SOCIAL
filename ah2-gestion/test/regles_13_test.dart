/// Critères de recette du cahier des charges (§13), un groupe par règle.
library;

import 'dart:io';
import 'dart:math';

import 'package:ah2_gestion/demo/demonstration.dart';
import 'package:ah2_gestion/modules/actes/actes.dart';
import 'package:ah2_gestion/modules/cloture/cloture.dart';
import 'package:ah2_gestion/modules/comptabilite/moteur.dart';
import 'package:ah2_gestion/modules/desintox/desintox.dart';
import 'package:ah2_gestion/modules/dons/dons.dart';
import 'package:ah2_gestion/modules/parametrage/parametrage.dart';
import 'package:ah2_gestion/modules/patients/patients.dart';
import 'package:ah2_gestion/modules/rapports/rapports.dart';
import 'package:ah2_gestion/modules/releves/releves.dart';
import 'package:ah2_gestion/modules/sauvegarde/sauvegarde.dart';
import 'package:ah2_gestion/modules/tresorerie/tresorerie.dart';
import 'package:ah2_gestion/noyau/audit.dart';
import 'package:ah2_gestion/noyau/base.dart';
import 'package:ah2_gestion/noyau/numerotation.dart';
import 'package:ah2_gestion/noyau/operations.dart';
import 'package:ah2_gestion/noyau/outils.dart';
import 'package:ah2_gestion/noyau/securite.dart';
import 'package:ah2_gestion/noyau/session.dart';
import 'package:ah2_gestion/sync/synchronisation.dart';
import 'package:test/test.dart';

import 'aide.dart';

String patient(Session s, [String nom = 'TEST']) => Patients.creer(s, nom: nom, prenoms: 'Patient').d<String>('id');

void main() {
  group('§13.1 Toute opération génère une écriture équilibrée', () {
    test('28 jours de données de démonstration : aucune écriture déséquilibrée', () {
      final env = Environnement();
      Demo.donneesFictives(env.central);
      expect(env.central.entier('SELECT COUNT(*) FROM ecritures'), greaterThan(100));
      expect(Moteur.ecrituresDesequilibrees(env.central), isEmpty);
    });

    test('chaque opération avec un montant a son écriture ; la gratuité est tracée sans écriture', () {
      final env = Environnement();
      final s = env.sessionCentrale('caisse');
      final p = patient(s);
      final payee = Actes.enregistrer(s, activite: 'LAB', actes: const [DemandeActe('LAB-NFS')], mode: Modes.especes, patient: p);
      final credit = Actes.enregistrer(s, activite: 'CONS', actes: const [DemandeActe('CONS-GEN')], mode: Modes.credit, patient: p);
      final gratuit = Actes.enregistrer(s,
          activite: 'LAB', actes: const [DemandeActe('LAB-GLY')], mode: Modes.gratuit, patient: p, motifGratuite: 'indigent');
      int nb(Operation o) => env.central.entier('SELECT COUNT(*) FROM ecritures WHERE uuid_op=?', [o.uuid]);
      expect(nb(payee), 1);
      expect(nb(credit), 1);
      expect(nb(gratuit), 0);
      expect(env.central.entier("SELECT COUNT(*) FROM actes WHERE mode='gratuit' AND montant=0 AND motif_gratuite='indigent'"), 1);
      // Débit 571 / crédit 7062 pour la prestation payée en espèces.
      final l = env.central.lignes(
          'SELECT compte, debit, credit FROM lignes_ecriture WHERE ecriture=(SELECT id FROM ecritures WHERE uuid_op=?) ORDER BY id',
          [payee.uuid]);
      expect(l, [
        {'compte': '5711', 'debit': 3500, 'credit': 0},
        {'compte': '7062', 'debit': 0, 'credit': 3500},
      ]);
      // La créance du patient vient de la comptabilité : 2 000 FCFA (compte 4111).
      expect(Actes.creance(env.central, p), 2000);
      expect(Moteur.ecrituresDesequilibrees(env.central), isEmpty);
    });

    test('deux comptabilités : un don va à l’ONG (SYCEBNL), un acte au centre (SYSCOHADA)', () {
      final env = Environnement();
      final c = env.sessionCentrale('comptable');
      final d = Dons.creerDonateur(c, nom: 'Donateur', type: 'particulier').d<String>('id');
      final don = Dons.recevoir(c, donateur: d, montant: 100000, nature: 'especes');
      final acte = Actes.enregistrer(c, activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes);
      expect(env.central.valeur('SELECT entite FROM ecritures WHERE uuid_op=?', [don.uuid]), 'ONG');
      expect(env.central.valeur('SELECT entite FROM ecritures WHERE uuid_op=?', [acte.uuid]), 'CS');
      expect(don.piece, startsWith('DON-ONG-PC1-'));
      expect(acte.piece, startsWith('REC-CS-PC1-'));
      expect(env.central.valeur('SELECT referentiel FROM entites WHERE code=?', ['ONG']), 'SYCEBNL');
      expect(env.central.valeur('SELECT referentiel FROM entites WHERE code=?', ['CS']), 'SYSCOHADA');
      expect(Moteur.solde(env.central, 'ONG', '7581'), -100000);
    });
  });

  group('§13.2 Aucune suppression ; aucune saisie sur une journée clôturée', () {
    test('les registres refusent modification et suppression, même en SQL direct', () {
      final env = Environnement();
      final s = env.sessionCentrale('caisse');
      Actes.enregistrer(s, activite: 'LAB', actes: const [DemandeActe('LAB-NFS')], mode: Modes.especes);
      for (final sql in [
        'DELETE FROM operations',
        "UPDATE operations SET donnees='{}'",
        'DELETE FROM ecritures',
        'UPDATE lignes_ecriture SET debit=0',
        'DELETE FROM audit',
        "UPDATE audit SET action='x'",
      ]) {
        expect(() => env.central.exec(sql), throwsA(anything), reason: sql);
      }
    });

    test('une opération validée s’annule par contre-opération avec motif', () {
      final env = Environnement();
      final s = env.sessionCentrale('comptable');
      final op = Actes.enregistrer(s, activite: 'LAB', actes: const [DemandeActe('LAB-NFS')], mode: Modes.especes);
      expect(Tresorerie.solde(env.central, 'CS-CAISSE'), 3500);
      expect(() => Operations.annuler(s, op.uuid, ''), throwsA(isA<RegleMetier>()));
      final ann = Operations.annuler(s, op.uuid, 'Erreur de saisie');
      expect(ann.piece, startsWith('ANN-CS-PC1-'));
      expect(Tresorerie.solde(env.central, 'CS-CAISSE'), 0);
      expect(Moteur.solde(env.central, 'CS', '7062'), 0);
      expect(env.central.entier('SELECT COUNT(*) FROM operations'), greaterThanOrEqualTo(2));
      expect(env.central.entier('SELECT annule FROM actes WHERE uuid_op=?', [op.uuid]), 1);
      expect(() => Operations.annuler(s, op.uuid, 'Encore'), throwsA(isA<RegleMetier>()));
      // Un caissier ne peut pas annuler.
      final op2 = Actes.enregistrer(s, activite: 'LAB', actes: const [DemandeActe('LAB-NFS')], mode: Modes.especes);
      expect(() => Operations.annuler(env.sessionCentrale('caisse'), op2.uuid, 'Essai'), throwsA(isA<DroitRefuse>()));
    });

    test('clôture : bloquée tant qu’un appareil n’est pas synchronisé ; plus de saisie ensuite ; réouverture à deux', () async {
      final env = Environnement();
      final t1 = await env.telephone('T01');
      await env.telephone('T02');
      final jour = dateIso(env.horloge.t);
      Actes.enregistrer(t1.session('labo'), activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes);
      env.horloge.avancer(jours: 1);
      final c = env.sessionCentrale('comptable');
      expect(() => Cloture.cloturer(c, entite: 'CS', date: jour), throwsA(isA<RegleMetier>()));
      await t1.sync();
      expect(Cloture.appareilsNonSynchronises(env.central, jour), ['T02']);
      Parametrage.changerStatutAppareil(env.sessionCentrale('admin'), 'T02', 'inactif');
      Cloture.cloturer(c, entite: 'CS', date: jour);
      // Plus aucune saisie datée de ce jour (horloge ramenée en arrière).
      env.horloge.avancer(jours: -1);
      expect(() => Actes.enregistrer(c, activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes),
          throwsA(isA<RegleMetier>().having((e) => e.message, 'message', contains('clôturée'))));
      // Le téléphone reçoit la clôture et bloque aussi.
      await t1.sync();
      expect(() => Actes.enregistrer(t1.session('labo'), activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes),
          throwsA(isA<RegleMetier>()));
      env.horloge.avancer(jours: 1);
      // Réouverture : le comptable demande, la direction approuve.
      expect(() => Cloture.approuverReouverture(c, 'x'), throwsA(isA<DroitRefuse>()));
      final dem = Cloture.demanderReouverture(c, entite: 'CS', date: jour, motif: 'Reçu oublié au laboratoire');
      expect(Operations.estCloturee(env.central, 'CS', jour), isTrue);
      Cloture.approuverReouverture(env.sessionCentrale('direction'), dem.uuid);
      expect(Operations.estCloturee(env.central, 'CS', jour), isFalse);
    });
  });

  group('§13.3 Numérotation sans trou par appareil', () {
    List<int> numeros(Base b, String prefixe) => b
        .lignes("SELECT piece FROM operations WHERE piece LIKE ? ORDER BY seq", ['$prefixe%'])
        .map((l) => int.parse((l['piece'] as String).split('-').last))
        .toList();

    test('continue après annulation et après une erreur en cours d’enregistrement', () {
      final env = Environnement();
      final s = env.sessionCentrale('comptable');
      for (var i = 0; i < 5; i++) {
        final op = Actes.enregistrer(s, activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes);
        if (i == 2) Operations.annuler(s, op.uuid, 'Erreur');
      }
      // Erreur APRÈS l'attribution du numéro : tout est annulé, numéro compris.
      expect(
          () => env.central.transaction(() {
                Actes.enregistrer(s, activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes);
                throw StateError('coupure simulée');
              }),
          throwsStateError);
      Actes.enregistrer(s, activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes);
      expect(numeros(env.central, 'REC-CS-PC1-'), [1, 2, 3, 4, 5, 6]);
      expect(numeros(env.central, 'ANN-CS-PC1-'), [1]);
    });

    test('coupure de courant / batterie vide simulée : rien n’est perdu ni à moitié écrit', () {
      final dossier = Directory.systemTemp.createTempSync('ah2-coupure');
      final chemin = '${dossier.path}/base.db';
      final h = Horloge(DateTime(2026, 11, 2, 9));
      var b = Base.ouvrir(chemin: chemin, appareil: 'PC1', horloge: h.call);
      Demo.installerCentral(b);
      var s = Session.pour(b, 'caisse');
      Actes.enregistrer(s, activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes);
      // Transaction interrompue en plein milieu (numéro réservé, opération non validée).
      b.exec('BEGIN IMMEDIATE');
      Numerotation.suivant(b, entite: 'CS', typePiece: 'REC', exercice: 2026);
      b.exec("INSERT INTO etat_sync(cle, valeur) VALUES ('test', 'x')");
      b.db.close(); // coupure brutale : pas de COMMIT
      b = Base.ouvrir(chemin: chemin, appareil: 'PC1', horloge: h.call);
      expect(b.valeur("SELECT valeur FROM etat_sync WHERE cle='test'"), isNull);
      s = Session.pour(b, 'caisse');
      Actes.enregistrer(s, activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes);
      expect(numeros(b, 'REC-CS-PC1-'), [1, 2]);
      expect(Tresorerie.solde(b, 'CS-CAISSE'), 2000);
      b.fermer();
      dossier.deleteSync(recursive: true);
    });

    test('chaque appareil a sa propre série, même hors ligne', () async {
      final env = Environnement();
      final t1 = await env.telephone('T01');
      final t2 = await env.telephone('T02');
      env.wifi = false;
      final p1 = Actes.enregistrer(t1.session('labo'), activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes);
      final p2 = Actes.enregistrer(t2.session('labo'), activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes);
      expect(p1.piece, 'REC-CS-T01-2026-000001');
      expect(p2.piece, 'REC-CS-T02-2026-000001');
    });
  });

  group('§13.4 Solde de caisse = somme des mouvements ; sortie supérieure au solde bloquée', () {
    test('solde, blocage, dépense à valider, virement, arrêté avec écart', () {
      final env = Environnement();
      final s = env.sessionCentrale('caisse');
      for (var i = 0; i < 3; i++) {
        Actes.enregistrer(s, activite: 'CONS', actes: const [DemandeActe('CONS-SPE')], mode: Modes.especes);
      }
      final b = env.central;
      int somme() => b.entier("SELECT SUM(montant) FROM mouvements_tresorerie WHERE tresorerie='CS-CAISSE'");
      expect(Tresorerie.solde(b, 'CS-CAISSE'), 15000);
      expect(() => Tresorerie.depense(s, entite: 'CS', beneficiaire: 'X', motif: 'Y', compteCharge: '6055', activite: 'ADM_CS', montant: 20000),
          throwsA(isA<RegleMetier>().having((e) => e.message, 'm', contains('solde disponible'))));
      Tresorerie.depense(s, entite: 'CS', beneficiaire: 'Librairie', motif: 'Cahiers', compteCharge: '6055', activite: 'ADM_CS', montant: 4000);
      expect(Tresorerie.solde(b, 'CS-CAISSE'), 11000);
      // Au-delà du seuil (100 000) : en attente, aucune sortie tant que la direction n'a pas validé.
      Parametrage.modifierParametre(env.sessionCentrale('admin'), 'seuil_validation_depense', '5000');
      final dep = Tresorerie.depense(s,
          entite: 'CS', beneficiaire: 'Plombier', motif: 'Réparation', compteCharge: '6241', activite: 'ADM_CS', montant: 8000);
      expect(Tresorerie.solde(b, 'CS-CAISSE'), 11000);
      expect(() => Tresorerie.validerDepense(s, dep.uuid), throwsA(isA<DroitRefuse>()));
      Tresorerie.validerDepense(env.sessionCentrale('direction'), dep.uuid);
      expect(Tresorerie.solde(b, 'CS-CAISSE'), 3000);
      // Virement caisse -> banque : ni recette ni charge.
      final rec = Rapports.recettesParActivite(b, du: '2026-01-01', au: '2026-12-31').values.reduce((a, c) => a + c);
      Tresorerie.virement(env.sessionCentrale('comptable'), source: 'CS-CAISSE', destination: 'CS-BQ', montant: 2000, reference: 'BORD-1');
      expect(Rapports.recettesParActivite(b, du: '2026-01-01', au: '2026-12-31').values.reduce((a, c) => a + c), rec);
      expect(Tresorerie.solde(b, 'CS-BQ'), 2000);
      expect(Moteur.solde(b, 'CS', '5851'), 0);
      // Arrêté : on compte 500 FCFA au lieu de 1 000 vers manquant de 500 enregistré.
      expect(() => Tresorerie.arreterCaisse(s, caisse: 'CS-CAISSE', billetage: {500: 1}), throwsA(isA<RegleMetier>()));
      final arr = Tresorerie.arreterCaisse(s, caisse: 'CS-CAISSE', billetage: {500: 1}, motifEcart: 'Erreur de rendu');
      expect(arr.d<int>('ecart'), -500);
      expect(Tresorerie.solde(b, 'CS-CAISSE'), 500);
      expect(Moteur.solde(b, 'CS', '6588'), 500);
      expect(Tresorerie.solde(b, 'CS-CAISSE'), somme());
      expect(Moteur.ecrituresDesequilibrees(b), isEmpty);
    });

    test('mobile money : la référence de transaction est obligatoire', () {
      final env = Environnement();
      final s = env.sessionCentrale('caisse');
      expect(() => Actes.enregistrer(s, activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.mtn),
          throwsA(isA<RegleMetier>()));
      Actes.enregistrer(s, activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.mtn, reference: '1234567890');
      expect(Tresorerie.solde(env.central, 'CS-MTN'), 1000);
    });
  });

  group('§13.5 Synchronisation : deux téléphones hors ligne toute une journée', () {
    test('aucune perte, aucun doublon, conflits signalés', () async {
      final env = Environnement();
      final t1 = await env.telephone('T01');
      final t2 = await env.telephone('T02');
      final patientCommun = patient(env.sessionCentrale('caisse'), 'COMMUN');
      await t1.sync();
      await t2.sync();
      env.wifi = false;
      final r = Random(7);
      var total = 0;
      for (var h = 0; h < 10; h++) {
        env.horloge.avancer(minutes: 30);
        for (final t in [t1, t2]) {
          final s = t.session(t == t1 ? 'labo' : 'consult');
          final p = patient(s, 'P${t.base.appareil}$h');
          final op = t == t1
              ? Actes.enregistrer(s, activite: 'LAB', actes: [DemandeActe(['LAB-GE', 'LAB-NFS', 'LAB-GLY'][r.nextInt(3)])], mode: Modes.especes, patient: p)
              : Actes.enregistrer(s, activite: 'CONS', actes: const [DemandeActe('CONS-GEN')], mode: Modes.especes, patient: p);
          total += op.d<int>('total');
        }
      }
      // Les deux téléphones modifient le même dossier patient hors ligne.
      Patients.modifier(t1.session('labo'), patientCommun, {'contact': '6 11 11 11 11'});
      env.horloge.avancer(minutes: 5);
      Patients.modifier(t2.session('consult'), patientCommun, {'contact': '6 22 22 22 22'});
      expect(() => t1.sync(), throwsStateError); // pas de Wi-Fi : rien ne part
      env.wifi = true;
      final n = env.central.entier('SELECT COUNT(*) FROM operations');
      await t1.sync();
      await t2.sync();
      await t1.sync(); // re-synchroniser ne crée aucun doublon
      await t2.sync();
      final b = env.central;
      expect(b.entier('SELECT COUNT(*) FROM operations') - n, 2 * (10 * 2) + 2);
      expect(b.entier('SELECT COUNT(*) FROM operations'), b.entier('SELECT COUNT(DISTINCT uuid) FROM operations'));
      expect(b.entier("SELECT COALESCE(SUM(montant),0) FROM actes WHERE date=?", [dateIso(env.horloge.t)]), total);
      // Les téléphones ont la même vision que le PC central.
      for (final t in [t1, t2]) {
        expect(t.base.entier('SELECT COUNT(*) FROM operations'), b.entier('SELECT COUNT(*) FROM operations'));
        expect(t.base.entier('SELECT COUNT(*) FROM actes'), b.entier('SELECT COUNT(*) FROM actes'));
      }
      // Conflit sur le même dossier : deux versions conservées, la plus récente affichée, alerte.
      expect(Patients.historique(b, patientCommun).length, 3);
      expect(Patients.lire(b, patientCommun)['contact'], '6 22 22 22 22');
      expect(b.entier("SELECT COUNT(*) FROM anomalies_sync WHERE type='conflit_patient'"), 1);
      expect(Moteur.ecrituresDesequilibrees(b), isEmpty);
      expect(ClientSync.etat(t1.base).enAttente, 0);
    });

    test('conflit de montant hors ligne (versements simultanés > reste dû) : accepté et signalé', () async {
      final env = Environnement();
      final c = env.sessionCentrale('caisse');
      final p = patient(c);
      final dos = Desintox.inscrire(c, patient: p, programme: 'RES-30', responsables: const [Responsable('Parent', 'père', '600')]);
      final t1 = await env.telephone('T01');
      final t2 = await env.telephone('T02');
      env.wifi = false;
      Desintox.verser(t1.session('desintox'), dossierId: dos.d('id'), montant: 150000, payeur: 'Parent', mode: Modes.especes);
      Desintox.verser(t2.session('desintox'), dossierId: dos.d('id'), montant: 100000, payeur: 'Parent', mode: Modes.especes);
      env.wifi = true;
      await t1.sync();
      await t2.sync();
      expect(env.central.entier("SELECT COUNT(*) FROM anomalies_sync WHERE type='trop_percu'"), 1);
      expect(Desintox.situation(env.central, dos.d('id')).verse, 250000);
    });

    test('le paramétrage du PC central est diffusé ; il ne se modifie pas sur un téléphone', () async {
      final env = Environnement();
      final t1 = await env.telephone('T01');
      Parametrage.definirTarif(env.sessionCentrale('admin'), 'LAB-GE', 1200);
      await t1.sync();
      expect(Parametrage.tarif(t1.base, 'LAB-GE', dateIso(env.horloge.t)), 1200);
      expect(() => Parametrage.modifierParametre(Session.pour(t1.base, 'admin'), 'plafond_encaisse', '1'),
          throwsA(isA<RegleMetier>()));
    });

    test('lecture seule après le nombre maximal de jours sans synchronisation', () async {
      final env = Environnement();
      final t1 = await env.telephone('T01');
      env.horloge.avancer(jours: 4);
      expect(() => Actes.enregistrer(t1.session('labo'), activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes),
          throwsA(isA<RegleMetier>().having((e) => e.message, 'm', contains('Lecture seule'))));
      await t1.sync();
      Actes.enregistrer(t1.session('labo'), activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes);
    });

    test('un intrus sans la clé ne peut ni lire ni injecter ; le rejeu est refusé', () async {
      final env = Environnement();
      final faux = Enveloppe.fermer('T01', 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', {'compteur': 99, 'operations': []});
      expect(env.serveur.traiter(faux)['erreur'], 'authentification');
      final vrai = Enveloppe.fermer('T01', env.cles['T01']!,
          {'compteur': 5, 'operations': [], 'recu_jusqua': 0, 'version_parametrage': -1, 'complet': true});
      expect(env.serveur.traiter(vrai)['erreur'], isNull);
      expect(env.serveur.traiter(vrai)['erreur'], 'rejeu');
    });
  });

  group('§13.6 Désintoxication', () {
    test('total versé = somme des versements ; reste = total - versé ; reçu', () {
      final env = Environnement();
      final s = env.sessionCentrale('caisse');
      final p = patient(s, 'MBARGA');
      final ins = Desintox.inscrire(s,
          patient: p, programme: 'RES-90', responsables: const [Responsable('MBARGA Thérèse', 'mère', '677000001')]);
      final id = ins.d<String>('id');
      expect(() => Desintox.inscrire(s, patient: p, programme: 'RES-30', responsables: const [Responsable('A', 'b', '1')]),
          throwsA(isA<RegleMetier>()));
      // Modifier le montant exige un rôle autorisé.
      expect(() => Desintox.inscrire(s, patient: patient(s), programme: 'RES-30', montantTotal: 1, motifMontant: 'x',
          responsables: const [Responsable('A', 'b', '1')]), throwsA(isA<DroitRefuse>()));
      final v1 = Desintox.verser(s, dossierId: id, montant: 50000, payeur: 'MBARGA Thérèse', mode: Modes.especes);
      final v2 = Desintox.verser(s, dossierId: id, montant: 100000, payeur: 'MBARGA Thérèse', mode: Modes.especes);
      Desintox.verser(s, dossierId: id, montant: 75000, payeur: 'MBARGA Paul', mode: Modes.mtn, reference: '7654321098');
      expect(v1.d<int>('reste_apres'), 400000);
      expect(v2.d<int>('total_verse_apres'), 150000);
      var sit = Desintox.situation(env.central, id);
      expect(sit.total, 450000);
      expect(sit.verse, 225000);
      expect(sit.reste, 225000);
      expect(sit.pourcentage, 50);
      expect(() => Desintox.verser(s, dossierId: id, montant: 300000, payeur: 'X', mode: Modes.especes), throwsA(isA<RegleMetier>()));
      // Annuler un versement le retire du total.
      Operations.annuler(env.sessionCentrale('comptable'), v1.uuid, 'Doublon');
      sit = Desintox.situation(env.central, id);
      expect(sit.verse, 175000);
      expect(sit.reste, sit.total - sit.verse);
      // La créance patient (4111) est cohérente avec le reste à payer.
      expect(Actes.creance(env.central, p), sit.reste);
      expect(Moteur.ecrituresDesequilibrees(env.central), isEmpty);
    });

    test('archivage au bon délai, jamais avec un solde dû, dossier retrouvable, réadmission', () {
      final env = Environnement(debut: DateTime(2026, 9, 1, 9));
      final s = env.sessionCentrale('caisse');
      final p = patient(s, 'SOLDE');
      final q = patient(s, 'DOIT');
      final a = Desintox.inscrire(s, patient: p, programme: 'RES-30', responsables: const [Responsable('A', 'b', '1')]).d<String>('id');
      final b = Desintox.inscrire(s, patient: q, programme: 'RES-30', responsables: const [Responsable('A', 'b', '1')]).d<String>('id');
      Desintox.verser(s, dossierId: a, montant: 180000, payeur: 'A', mode: Modes.especes);
      Desintox.verser(s, dossierId: b, montant: 100000, payeur: 'A', mode: Modes.especes);
      env.horloge.avancer(jours: 30);
      Desintox.sortir(s, a, motif: 'programme termine');
      Desintox.sortir(s, b, motif: 'programme termine');
      final base = env.central;
      expect(Desintox.situation(base, a).statut, 'sorti_solde');
      expect(Desintox.situation(base, b).statut, 'sorti_solde_du');
      env.horloge.avancer(jours: 29);
      expect(Desintox.situation(base, a).statut, 'sorti_solde');
      env.horloge.avancer(jours: 1); // 30 jours après la sortie
      expect(Desintox.situation(base, a).statut, 'archive');
      expect(Desintox.listeTravail(base).map((x) => x.dossier['id']), isNot(contains(a)));
      // 200 jours plus tard, le patient qui doit reste dans « Sortis avec solde dû ».
      env.horloge.avancer(jours: 200);
      expect(Desintox.listeTravail(base, onglet: 'solde_du').map((x) => x.dossier['id']), contains(b));
      // Il solde : archivé 30 jours après le DERNIER versement.
      Desintox.verser(s, dossierId: b, montant: 80000, payeur: 'A', mode: Modes.especes);
      env.horloge.avancer(jours: 29);
      expect(Desintox.situation(base, b).statut, 'sorti_solde');
      env.horloge.avancer(jours: 1);
      expect(Desintox.situation(base, b).statut, 'archive');
      // Archivé ≠ effacé : retrouvable, rapport imprimable, écritures intactes.
      expect(Desintox.archives(base, recherche: 'SOLDE').single.dossier['id'], a);
      final rapport = Desintox.rapportSortie(base, a);
      expect(rapport['total_verse'], 180000);
      expect(rapport['reste'], 0);
      expect(rapport['duree_effective'], 30);
      // Réadmission : nouveau dossier, historique conservé.
      final nouveau = Desintox.inscrire(s, patient: p, programme: 'RES-30', responsables: const [Responsable('A', 'b', '1')]);
      expect(nouveau.d<String>('numero'), isNot(base.valeur('SELECT numero FROM desintox_dossiers WHERE id=?', [a])));
      expect(base.entier('SELECT COUNT(*) FROM desintox_dossiers WHERE patient=?', [p]), 2);
    });

    test('échéance non reçue : alerte', () {
      final env = Environnement(debut: DateTime(2026, 10, 1, 9));
      final s = env.sessionCentrale('caisse');
      final id = Desintox.inscrire(s,
          patient: patient(s),
          programme: 'RES-90',
          responsables: const [Responsable('A', 'b', '1')],
          echeancier: const [Echeance('2026-10-10', 100000), Echeance('2026-11-10', 100000)]).d<String>('id');
      Desintox.verser(s, dossierId: id, montant: 100000, payeur: 'A', mode: Modes.especes);
      env.horloge.le(2026, 11, 20);
      final al = Desintox.echeancesImpayees(env.central);
      expect(al.single['manquant'], 100000);
      expect(al.single['date'], '2026-11-10');
    });

    test('reconnaissance étalée : produit constaté au prorata, totalité à la sortie', () {
      final env = Environnement(debut: DateTime(2026, 9, 1, 9));
      Parametrage.modifierParametre(env.sessionCentrale('admin'), 'desintox_reconnaissance', 'etalee');
      final s = env.sessionCentrale('caisse');
      final id = Desintox.inscrire(s, patient: patient(s), programme: 'RES-30', responsables: const [Responsable('A', 'b', '1')])
          .d<String>('id');
      final c = env.sessionCentrale('comptable');
      expect(Moteur.solde(env.central, 'CS', '7064'), 0);
      env.horloge.avancer(jours: 15);
      Desintox.constaterProduits(c);
      expect(Moteur.solde(env.central, 'CS', '7064'), -90000);
      Desintox.sortir(s, id, motif: 'abandon');
      Desintox.constaterProduits(c);
      expect(Moteur.solde(env.central, 'CS', '7064'), -180000);
      expect(Moteur.solde(env.central, 'CS', '4770'), 0);
    });
  });

  group('§13.7 Totaux = somme des lignes ; pourcentages = 100 %', () {
    test('plus fort reste sur 1 000 tirages aléatoires', () {
      final r = Random(1);
      for (var i = 0; i < 1000; i++) {
        final m = List.generate(1 + r.nextInt(8), (_) => r.nextInt(200000));
        final p = Rapports.pourcentages(m);
        if (m.any((x) => x > 0)) expect(p.reduce((a, b) => a + b), 100, reason: '$m');
      }
    });

    test('rapport financier du jour cohérent, note de synthèse rédigée', () {
      final env = Environnement();
      Demo.donneesFictives(env.central);
      final hier = ajouterJours(dateIso(env.horloge.t), -1);
      final r = Rapports.financierDuJour(env.central, hier);
      final lignes = (r['lignes'] as List).cast<Map>();
      expect(lignes.fold<int>(0, (t, l) => t + (l['montant'] as int)), r['recettes']);
      expect(lignes.fold<int>(0, (t, l) => t + (l['pourcentage'] as int)), 100);
      expect(r['note'] as String, startsWith('Recettes '));
      final brouillard = Rapports.brouillard(env.central, 'CS-CAISSE', hier);
      final mv = (brouillard['mouvements'] as List).cast<Map>().fold<int>(0, (t, m) => t + (m['montant'] as int));
      expect(brouillard['cloture'], (brouillard['ouverture'] as int) + mv);
      expect(brouillard['cloture'], Tresorerie.solde(env.central, 'CS-CAISSE', jusquau: hier));
    });
  });

  group('§13.8 Le relevé contient exactement les actes du service et de la date, tous appareils confondus', () {
    test('relevé du laboratoire', () async {
      final env = Environnement();
      final t1 = await env.telephone('T01');
      final t2 = await env.telephone('T02');
      final jour = dateIso(env.horloge.t);
      final c = env.sessionCentrale('caisse');
      Actes.enregistrer(c, activite: 'LAB', actes: const [DemandeActe('LAB-NFS')], mode: Modes.especes);
      Actes.enregistrer(t1.session('labo'), activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.mtn, reference: '12345');
      Actes.enregistrer(t2.session('labo'), activite: 'LAB',
          actes: const [DemandeActe('LAB-GLY')], mode: Modes.gratuit, motifGratuite: 'campagne');
      Actes.enregistrer(t2.session('consult'), activite: 'CONS', actes: const [DemandeActe('CONS-GEN')], mode: Modes.especes);
      final annule = Actes.enregistrer(t1.session('labo'), activite: 'LAB', actes: const [DemandeActe('LAB-WID')], mode: Modes.especes);
      env.horloge.avancer(jours: 1);
      Actes.enregistrer(c, activite: 'LAB', actes: const [DemandeActe('LAB-ECBU')], mode: Modes.especes); // autre jour
      final compta = env.sessionCentrale('comptable');
      expect(() => Releves.generer(compta, activite: 'LAB', date: jour), throwsA(isA<RegleMetier>()));
      await t1.sync();
      Operations.annuler(compta, annule.uuid, 'Examen non réalisé');
      await t2.sync();
      final op = Releves.generer(compta, activite: 'LAB', date: jour);
      expect(op.d<String>('numero'), 'RJA-LAB-2026-0001');
      final contenu = Releves.contenu(env.central, 'RJA-LAB-2026-0001');
      final lignes = (contenu['lignes'] as List).cast<Map>();
      expect(lignes.map((l) => l['acte']), ['NFS (numération)', 'Goutte épaisse (paludisme)', 'Glycémie à jeun']);
      expect(lignes.map((l) => l['appareil']).toSet(), {'PC1', 'T01', 'T02'});
      final syn = contenu['synthese'] as Map;
      expect(syn['nombre_actes'], 3);
      expect(syn['gratuites'], 1);
      expect(syn['total_encaisse'], 4500);
      expect(() => Releves.generer(compta, activite: 'LAB', date: jour), throwsA(isA<RegleMetier>()));
      // Retour signé et fiche d'écart.
      Releves.marquerRetourne(compta, 'RJA-LAB-2026-0001', scan: 'scan.jpg');
      final e = Releves.saisirEcart(compta, releve: 'RJA-LAB-2026-0001', ligne: '2', nature: 'montant different');
      Releves.suivreEcart(compta, e.d('numero'), statut: 'justifie', observation: 'Tarif affiché ancien');
      expect(Releves.suivi(env.central).first['statut'], 'retourne_signe');
    });
  });

  group('§13.10 Journal d’audit', () {
    test('chaque action et chaque synchronisation est tracée ; toute altération est détectée', () async {
      final env = Environnement();
      final t1 = await env.telephone('T01');
      final op = Actes.enregistrer(t1.session('labo'), activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes);
      await t1.sync();
      final b = env.central;
      expect(b.entier("SELECT COUNT(*) FROM audit WHERE action='synchronisation' AND objet LIKE ?", ['%${op.uuid}%']), 1);
      expect(t1.base.entier("SELECT COUNT(*) FROM audit WHERE action='creation' AND objet LIKE ?", ['%${op.uuid}%']), 1);
      expect(b.entier("SELECT COUNT(*) FROM audit WHERE action='synchronisation' AND objet='appareil:T01'"), greaterThanOrEqualTo(2));
      expect(Audit.verifier(b), isNull);
      // Falsification « hors logiciel » : suppression du verrou puis modification.
      b.exec('DROP TRIGGER audit_pas_de_modif');
      b.exec("UPDATE audit SET utilisateur='quelqu’un' WHERE id=3");
      expect(Audit.verifier(b), 3);
    });

    test('connexion : mot de passe chiffré, verrouillage après 5 échecs', () {
      final env = Environnement();
      final b = env.central;
      expect(b.valeur("SELECT empreinte FROM utilisateurs WHERE identifiant='caisse'"), isNot(Demo.motDePasse));
      expect(Securite.connecter(b, 'caisse', Demo.motDePasse)['role'], 'caissier');
      for (var i = 0; i < 5; i++) {
        expect(() => Securite.connecter(b, 'caisse', 'faux'), throwsA(isA<RegleMetier>()));
      }
      expect(() => Securite.connecter(b, 'caisse', Demo.motDePasse),
          throwsA(isA<RegleMetier>().having((e) => e.message, 'm', contains('verrouillé'))));
      env.horloge.avancer(minutes: 16);
      expect(Securite.connecter(b, 'caisse', '1234', parCode: true)['role'], 'caissier');
    });

    test('droits : l’administrateur ne saisit pas d’opérations ; l’auditeur lit seulement', () {
      final env = Environnement();
      for (final u in ['admin', 'auditeur']) {
        expect(() => Actes.enregistrer(env.sessionCentrale(u), activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes),
            throwsA(isA<DroitRefuse>()));
      }
      expect(env.sessionCentrale('auditeur').peut('audit', 'voir'), isTrue);
      expect(() => Actes.enregistrer(env.sessionCentrale('labo'), activite: 'CONS', actes: const [DemandeActe('CONS-GEN')], mode: Modes.especes),
          throwsA(isA<DroitRefuse>()));
    });
  });

  group('§13.11 Sauvegarde puis restauration : base identique', () {
    test('sauvegarde chiffrée, restauration, mauvais mot de passe refusé', () {
      final dossier = Directory.systemTemp.createTempSync('ah2-svg');
      final h = Horloge(DateTime(2026, 11, 2, 9));
      final b = Base.ouvrir(chemin: '${dossier.path}/central.db', appareil: 'PC1', horloge: h.call);
      Demo.installerCentral(b);
      Demo.donneesFictives(b, jours: 5);
      final fichier = Sauvegarde.sauvegarder(Session.pour(b, 'admin'), dossier: dossier.path, motDePasse: 'motdepasse-svg');
      final attendu = Sauvegarde.empreinteContenu(b);
      expect(File(fichier).readAsBytesSync().length, greaterThan(1000));
      expect(String.fromCharCodes(File(fichier).readAsBytesSync()).contains('NKOULOU'), isFalse, reason: 'chiffrée');
      expect(() => Sauvegarde.restaurer(fichier: fichier, motDePasse: 'faux-mot-de-passe', cheminBase: '${dossier.path}/r.db'),
          throwsA(isA<RegleMetier>()));
      Sauvegarde.restaurer(fichier: fichier, motDePasse: 'motdepasse-svg', cheminBase: '${dossier.path}/r.db');
      final r = Base.ouvrir(chemin: '${dossier.path}/r.db', appareil: 'PC1', horloge: h.call);
      expect(Sauvegarde.empreinteContenu(r), attendu);
      expect(Rapports.alertes(b).where((a) => a['titre'] == 'Sauvegarde non effectuée'), isEmpty);
      r.fermer();
      b.fermer();
      dossier.deleteSync(recursive: true);
    });
  });

  group('§13.12 Un téléphone révoqué ne peut plus se synchroniser ni accéder aux données', () {
    test('révocation', () async {
      final env = Environnement();
      final t1 = await env.telephone('T01');
      Actes.enregistrer(t1.session('labo'), activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes);
      Parametrage.revoquerAppareil(env.sessionCentrale('admin'), 'T01', 'Téléphone perdu');
      final avant = env.central.entier('SELECT COUNT(*) FROM operations');
      await expectLater(t1.sync(), throwsA(isA<AppareilRevoque>()));
      expect(t1.efface, isTrue, reason: 'les données locales sont effacées');
      expect(env.central.entier('SELECT COUNT(*) FROM operations'), avant, reason: 'rien n’est accepté');
      await expectLater(t1.sync(), throwsA(isA<AppareilRevoque>()));
      expect(env.central.entier("SELECT COUNT(*) FROM audit WHERE action='synchronisation_refusee'"), greaterThanOrEqualTo(1));
    });
  });

  test('§13.9 Stocks et CUMP : prévus en phase 2 (pharmacies)', () {}, skip: 'Phase 2 : pharmacies moderne et traditionnelle');
}
