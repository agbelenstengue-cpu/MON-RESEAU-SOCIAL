/// Le comptable ajoute, modifie et retire le paramétrage ; le logo et
/// l'entête sont diffusés aux appareils et utilisés dans les documents.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:ah2_gestion/modules/actes/actes.dart';
import 'package:ah2_gestion/modules/comptabilite/moteur.dart';
import 'package:ah2_gestion/modules/desintox/desintox.dart';
import 'package:ah2_gestion/modules/parametrage/parametrage.dart';
import 'package:ah2_gestion/modules/patients/patients.dart';
import 'package:ah2_gestion/modules/tresorerie/tresorerie.dart';
import 'package:ah2_gestion/noyau/outils.dart';
import 'package:ah2_gestion/pdf/documents.dart';
import 'package:test/test.dart';

import 'aide.dart';

void main() {
  test('le comptable gère services, actes, prix, programmes, comptes et trésorerie', () {
    final env = Environnement();
    final c = env.sessionCentrale('comptable');
    final b = env.central;
    Parametrage.ajouterActivite(c, code: 'ECHO', libelle: 'Échographie', entite: 'CS');
    Parametrage.ajouterCompte(c, entite: 'CS', numero: '7066', libelle: "Prestations d'échographie");
    Parametrage.ajouterActe(c, code: 'ECHO-ABD', libelle: 'Échographie abdominale', activite: 'ECHO', compteProduit: '7066', prix: 15000);
    final op = Actes.enregistrer(env.sessionCentrale('caisse'), activite: 'ECHO', actes: const [DemandeActe('ECHO-ABD')], mode: Modes.especes);
    expect(op.d<int>('total'), 15000);
    expect(Moteur.solde(b, 'CS', '7066'), -15000);
    // Nouveau prix : le passé ne change pas.
    Parametrage.definirTarif(c, 'ECHO-ABD', 18000);
    expect(b.valeur('SELECT montant FROM actes WHERE uuid_op=?', [op.uuid]), 15000);
    // Retirer un acte déjà utilisé : désactivé ; jamais utilisé : supprimé.
    expect(Parametrage.retirerActe(c, 'ECHO-ABD'), 'désactivé');
    expect(() => Actes.enregistrer(c, activite: 'ECHO', actes: const [DemandeActe('ECHO-ABD')], mode: Modes.especes), throwsA(isA<RegleMetier>()));
    expect(Parametrage.retirerActe(c, 'MASS-60'), 'supprimé');
    // Compte utilisé par un acte actif : refusé ; compte libre : supprimé.
    expect(() => Parametrage.retirerCompte(c, entite: 'CS', numero: '7062'), throwsA(isA<RegleMetier>()));
    Parametrage.ajouterCompte(c, entite: 'CS', numero: '6058', libelle: 'Autres fournitures');
    expect(Parametrage.retirerCompte(c, entite: 'CS', numero: '6058'), 'supprimé');
    // Programmes.
    Parametrage.enregistrerProgramme(c, code: 'RES-60', libelle: 'Résidentiel 60 jours', type: 'residentiel', duree: 60, modeCalcul: 'forfait', montant: 300000);
    final p = Patients.creer(c, nom: 'TEST').d<String>('id');
    final ins = Desintox.inscrire(c, patient: p, programme: 'RES-60', responsables: const [Responsable('A', 'b', '1')]);
    expect(ins.d<int>('montant_total'), 300000);
    expect(Parametrage.retirerProgramme(c, 'RES-60'), 'désactivé');
    expect(Parametrage.retirerProgramme(c, 'RES-30'), 'supprimé');
    // Nouveau compte bancaire.
    final id = Parametrage.ajouterTresorerie(c, entite: 'ONG', type: 'banque', libelle: 'Banque projet', compte: '5212');
    expect(Tresorerie.compte(b, id)['compte'], '5212');
    expect(Parametrage.retirerTresorerie(c, id), 'supprimé');
    // Un caissier ne peut rien modifier.
    expect(() => Parametrage.ajouterCompte(env.sessionCentrale('caisse'), entite: 'CS', numero: '7067', libelle: 'x'), throwsA(isA<RegleMetier>()));
  });

  test('logo, entête et filigrane : paramétrés, diffusés et utilisés dans les PDF', () async {
    final env = Environnement();
    final c = env.sessionCentrale('comptable');
    final logo = File('assets/images/logo_ah2.png').readAsBytesSync();
    expect(() => Parametrage.definirLogo(c, 'CS', Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<RegleMetier>()));
    Parametrage.definirEntete(c, 'ONG', logo);
    Parametrage.definirFiligrane(c, 'CS', false);
    final t1 = await env.telephone('T01');
    expect(t1.base.valeur("SELECT entete FROM entites WHERE code='ONG'"), logo);
    expect(t1.base.valeur("SELECT logo FROM entites WHERE code='CS'"), logo);
    expect(t1.base.valeur("SELECT filigrane FROM entites WHERE code='CS'"), 0);
    final op = Actes.enregistrer(c, activite: 'LAB', actes: const [DemandeActe('LAB-GE')], mode: Modes.especes);
    expect((await Documents.recu(env.central, op.uuid)).length, greaterThan(10000));
  });

  test('aucun tiret long dans les libellés livrés', () {
    final env = Environnement();
    for (final t in ['comptes', 'journaux', 'activites', 'actes_catalogue', 'programmes_desintox', 'schemas_ecritures', 'tresoreries']) {
      for (final l in env.central.lignes('SELECT * FROM $t')) {
        for (final v in l.values.whereType<String>()) {
          expect(v.contains('—') || v.contains('–'), isFalse, reason: '$t : $v');
        }
      }
    }
  });
}
