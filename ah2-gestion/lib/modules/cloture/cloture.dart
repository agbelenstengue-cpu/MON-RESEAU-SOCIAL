/// Clôtures journalières, réouverture exceptionnelle, verrouillage des périodes.
library;

import '../../noyau/base.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../parametrage/parametrage.dart';

class Cloture {
  /// Appareils autorisés qui ne se sont pas synchronisés depuis la fin de [date] :
  /// ils ont peut-être travaillé ce jour-là sans que le PC central le sache.
  static List<String> appareilsNonSynchronises(Base base, String date) {
    final finJour = '${ajouterJours(date, 1)}T00:00:00';
    return base
        .lignes("SELECT code, derniere_sync FROM appareils WHERE central=0 AND statut='autorise' ORDER BY code")
        .where((a) => a['derniere_sync'] == null || (a['derniere_sync'] as String).compareTo(finJour) < 0)
        .map((a) => a['code'] as String)
        .toList();
  }

  static void exigerTousSynchronises(Base base, String date) {
    final manquants = appareilsNonSynchronises(base, date);
    if (manquants.isNotEmpty) {
      throw RegleMetier('Appareils non synchronisés depuis le ${dateFr(depuisIso(date))} : ${manquants.join(', ')}. '
          'Synchronisez-les (ou déclarez-les inactifs) avant de continuer.');
    }
  }

  static Operation cloturer(Session s, {required String entite, required String date}) {
    final base = s.base;
    return base.aDateReelle(() => base.transaction(() {
      if (!Parametrage.estCentral(base)) throw const RegleMetier('La clôture se fait sur le PC central.');
      if (date.compareTo(dateIso(base.maintenantReel)) >= 0) {
        throw const RegleMetier('Seule une journée terminée peut être clôturée.');
      }
      if (Operations.estCloturee(base, entite, date)) throw const RegleMetier('Cette journée est déjà clôturée.');
      exigerTousSynchronises(base, date);
      return Operations.enregistrer(s, type: 'cloture_jour', entite: entite, donnees: {'date': date});
    }));
  }

  /// Étape 1 : le comptable demande la réouverture, avec motif.
  static Operation demanderReouverture(Session s, {required String entite, required String date, required String motif}) {
    if (s.role != 'comptable') throw const DroitRefuse('Seul le comptable peut demander une réouverture.');
    if (!Operations.estCloturee(s.base, entite, date)) throw const RegleMetier("Cette journée n'est pas clôturée.");
    if (motif.trim().length < 5) throw const RegleMetier('Le motif de réouverture est obligatoire.');
    return Operations.enregistrer(s, type: 'reouverture_demande', entite: entite, donnees: {'date': date, 'motif': motif.trim()});
  }

  /// Étape 2 : la direction approuve. La journée est rouverte.
  static Operation approuverReouverture(Session s, String uuidDemande) {
    final base = s.base;
    if (s.role != 'direction') throw const DroitRefuse('La réouverture doit être approuvée par la direction.');
    final dem = Operations.lire(base, uuidDemande) ?? (throw const RegleMetier('Demande introuvable.'));
    if (dem.type != 'reouverture_demande') throw const RegleMetier('Ce n’est pas une demande de réouverture.');
    if (base.valeur("SELECT 1 FROM operations WHERE type='reouverture_jour' AND donnees LIKE ?", ['%$uuidDemande%']) != null) {
      throw const RegleMetier('Cette demande a déjà été approuvée.');
    }
    return Operations.enregistrer(s,
        type: 'reouverture_jour', entite: dem.entite, donnees: {'date': dem.d('date'), 'demande': uuidDemande, 'motif': dem.d('motif')});
  }

  /// Verrouillage mensuel (AAAA-MM) ou annuel (AAAA).
  static Operation verrouiller(Session s, {required String entite, required String periode}) {
    final base = s.base;
    if (!RegExp(r'^\d{4}(-\d{2})?$').hasMatch(periode)) throw const RegleMetier('Période : AAAA-MM ou AAAA.');
    if (periode.compareTo(dateIso(base.maintenantReel).substring(0, periode.length)) >= 0) {
      throw const RegleMetier('Seule une période terminée peut être verrouillée.');
    }
    return Operations.enregistrer(s, type: 'verrouillage_periode', entite: entite, donnees: {'periode': periode});
  }

  static void declarer() {
    Operations.declarer(_Cloture());
    Operations.declarer(_Demande());
    Operations.declarer(_Reouverture());
    Operations.declarer(_Verrouillage());
  }
}

abstract class _Admin extends TypeOperation {
  @override
  String get module => 'cloture';
  @override
  bool get annulable => false;
  @override
  bool get horsJournee => true;
}

class _Cloture extends _Admin {
  @override
  String get type => 'cloture_jour';
  @override
  String get action => 'creer';
  @override
  String get libelle => 'Clôture journalière';
  @override
  void appliquer(Base base, Operation op) => base.exec(
      'INSERT INTO clotures(entite, date, cloture, uuid_op) VALUES (?,?,1,?) '
      'ON CONFLICT(entite, date) DO UPDATE SET cloture=1, uuid_op=excluded.uuid_op',
      [op.entite, op.d('date'), op.uuid]);
}

class _Demande extends _Admin {
  @override
  String get type => 'reouverture_demande';
  @override
  String get action => 'creer';
  @override
  String get libelle => 'Demande de réouverture';
  @override
  void appliquer(Base base, Operation op) {}
}

class _Reouverture extends _Admin {
  @override
  String get type => 'reouverture_jour';
  @override
  String get action => 'valider';
  @override
  String get libelle => 'Réouverture de journée';
  @override
  void appliquer(Base base, Operation op) =>
      base.exec('UPDATE clotures SET cloture=0, uuid_op=? WHERE entite=? AND date=?', [op.uuid, op.entite, op.d('date')]);
}

class _Verrouillage extends _Admin {
  @override
  String get type => 'verrouillage_periode';
  @override
  String get action => 'valider';
  @override
  String get libelle => 'Verrouillage de période';
  @override
  void appliquer(Base base, Operation op) => base.exec(
      'INSERT OR IGNORE INTO periodes_verrouillees(entite, periode, uuid_op) VALUES (?,?,?)', [op.entite, op.d('periode'), op.uuid]);
}
