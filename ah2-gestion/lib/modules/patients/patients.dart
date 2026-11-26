/// Patients : fiche, numéro de dossier unique, historique des versions.
///
/// Deux appareils peuvent modifier le même dossier hors ligne : les deux
/// versions sont conservées, la plus récente s'affiche, et une alerte est
/// levée (anomalie de synchronisation).
library;

import 'dart:convert';

import '../../noyau/base.dart';
import '../../noyau/numerotation.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';

class Patients {
  static const champs = ['nom', 'prenoms', 'sexe', 'naissance', 'contact', 'personne_a_prevenir'];

  static Operation creer(Session s,
      {required String nom,
      String prenoms = '',
      String sexe = '',
      String? naissance,
      String contact = '',
      String personneAPrevenir = ''}) {
    final base = s.base;
    return base.transaction(() {
      if (nom.trim().isEmpty) throw const RegleMetier('Le nom du patient est obligatoire.');
      if (sexe.isNotEmpty && !['F', 'M'].contains(sexe)) throw const RegleMetier('Sexe : F ou M.');
      final numero = Numerotation.dossier(base, prefixe: 'P', exercice: base.maintenant.year);
      return Operations.enregistrer(s, type: 'patient_creation', entite: 'CS', donnees: {
        'id': base.nouvelUuid(),
        'numero_dossier': numero,
        'nom': nom.trim().toUpperCase(),
        'prenoms': prenoms.trim(),
        'sexe': sexe,
        'naissance': naissance,
        'contact': contact.trim(),
        'personne_a_prevenir': personneAPrevenir.trim(),
      });
    });
  }

  static Operation modifier(Session s, String patientId, Map<String, Object?> changements) {
    final base = s.base;
    return base.transaction(() {
      final p = lire(base, patientId);
      final inconnus = changements.keys.where((k) => !champs.contains(k));
      if (inconnus.isNotEmpty) throw RegleMetier('Champ non modifiable : ${inconnus.join(', ')}');
      return Operations.enregistrer(s, type: 'patient_modification', entite: 'CS', donnees: {
        'id': patientId,
        'version_base': p['version_op'],
        'changements': changements,
      });
    });
  }

  static Ligne lire(Base base, String id) =>
      base.ligne('SELECT * FROM patients WHERE id=?', [id]) ?? (throw const RegleMetier('Patient introuvable.'));

  /// Recherche par nom, prénoms ou numéro de dossier.
  static List<Ligne> rechercher(Base base, String texte, {int limite = 30}) {
    final t = '%${texte.trim().toUpperCase()}%';
    return base.lignes(
        'SELECT * FROM patients WHERE UPPER(nom) LIKE ? OR UPPER(prenoms) LIKE ? OR UPPER(numero_dossier) LIKE ? '
        'ORDER BY nom, prenoms LIMIT ?',
        [t, t, t, limite]);
  }

  /// Nom affichable selon les droits (confidentialité §6.1).
  static String libelle(Session s, Ligne p) => s.peut('patients_noms', 'voir')
      ? '${p['nom']} ${p['prenoms']}'.trim()
      : p['numero_dossier'] as String;

  static List<Ligne> historique(Base base, String id) =>
      base.lignes('SELECT * FROM patients_historique WHERE patient=? ORDER BY horodatage', [id]);

  static void declarer() {
    Operations.declarer(_Creation());
    Operations.declarer(_Modification());
  }
}

class _Creation extends TypeOperation {
  @override
  String get type => 'patient_creation';
  @override
  String get module => 'patients';
  @override
  String get libelle => 'Création de patient';
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    final d = op.donnees;
    base.exec(
        'INSERT INTO patients(id, numero_dossier, nom, prenoms, sexe, naissance, contact, personne_a_prevenir, version_op, horodatage_version) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [d['id'], d['numero_dossier'], d['nom'], d['prenoms'], d['sexe'], d['naissance'], d['contact'],
          d['personne_a_prevenir'], op.uuid, op.horodatage]);
    base.exec('INSERT INTO patients_historique(uuid_op, patient, horodatage, donnees) VALUES (?,?,?,?)',
        [op.uuid, d['id'], op.horodatage, jsonEncode(d)]);
  }
}

class _Modification extends TypeOperation {
  @override
  String get type => 'patient_modification';
  @override
  String get module => 'patients';
  @override
  String get libelle => 'Modification de patient';
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    final id = op.d<String>('id');
    final p = base.ligne('SELECT * FROM patients WHERE id=?', [id]);
    if (p == null) {
      Operations.signalerAnomalie(base, 'patient_inconnu', op.uuid, 'Modification d’un patient inconnu.');
      return;
    }
    base.exec('INSERT INTO patients_historique(uuid_op, patient, horodatage, donnees) VALUES (?,?,?,?)',
        [op.uuid, id, op.horodatage, jsonEncode(op.donnees)]);
    if (p['version_op'] != op.d<String?>('version_base')) {
      Operations.signalerAnomalie(base, 'conflit_patient', op.uuid,
          'Le dossier ${p['numero_dossier']} a été modifié sur deux appareils. Les deux versions sont conservées dans l’historique ; la plus récente est affichée.');
    }
    // La version la plus récente (horodatage) s'affiche.
    if (op.horodatage.compareTo(p['horodatage_version'] as String) >= 0) {
      final ch = Map<String, Object?>.from(op.d<Map>('changements'));
      final sets = ch.keys.map((k) => '$k=?').join(', ');
      base.exec('UPDATE patients SET $sets, version_op=?, horodatage_version=? WHERE id=?',
          [...ch.values, op.uuid, op.horodatage, id]);
    }
  }
}
