/// Désintoxication (§6.6) : programmes, inscriptions, versements progressifs,
/// sortie, rapport de sortie, archivage automatique et réadmission.
///
/// Règles garanties :
///  * total versé = somme des versements (non annulés) ;
///  * reste à payer = montant total − total versé ;
///  * archivage automatique au délai paramétré, jamais si un solde est dû ;
///  * archiver n'efface rien : le dossier reste dans la comptabilité et les archives.
library;

import 'dart:convert';

import '../../noyau/base.dart';
import '../../noyau/numerotation.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../comptabilite/moteur.dart';
import '../tresorerie/tresorerie.dart';

class Responsable {
  final String nom;
  final String lien;
  final String telephone;
  const Responsable(this.nom, this.lien, this.telephone);
  Map<String, String> versJson() => {'nom': nom, 'lien': lien, 'telephone': telephone};
}

class Echeance {
  final String date; // ISO
  final int montant;
  const Echeance(this.date, this.montant);
  Map<String, Object> versJson() => {'date': date, 'montant': montant};
}

/// Situation calculée d'un dossier.
class SituationDesintox {
  final Ligne dossier;
  final int total;
  final int verse;
  final List<Ligne> versements;
  final String statut; // en_cours, sorti_solde_du, sorti_solde, archive
  final String? dateArchivage;
  SituationDesintox(this.dossier, this.total, this.verse, this.versements, this.statut, this.dateArchivage);

  int get reste => total - verse;
  int get pourcentage => total == 0 ? 100 : (verse * 100 ~/ total);
  bool get solde => reste == 0;
}

class Desintox {
  static const motifsSortie = ['programme termine', 'abandon', 'transfert', 'autre'];
  static const libellesMotifs = {
    'programme termine': 'Programme terminé',
    'abandon': 'Abandon',
    'transfert': 'Transfert',
    'autre': 'Autre',
  };

  /// Montant total calculé depuis le programme (forfait, ou prix par jour × durée).
  static int montantProgramme(Base base, String programme, int duree) {
    final p = base.ligne('SELECT * FROM programmes_desintox WHERE code=?', [programme]) ??
        (throw RegleMetier('Programme inconnu : $programme'));
    return p['mode_calcul'] == 'forfait' ? p['montant'] as int : (p['montant'] as int) * duree;
  }

  static Operation inscrire(
    Session s, {
    required String patient,
    required String programme,
    required List<Responsable> responsables,
    int? duree,
    int? montantTotal,
    String? motifMontant,
    List<Echeance> echeancier = const [],
  }) {
    final base = s.base;
    return base.transaction(() {
      if (base.valeur('SELECT 1 FROM patients WHERE id=?', [patient]) == null) {
        throw const RegleMetier('Patient introuvable.');
      }
      final enCours = base.valeur('SELECT numero FROM desintox_dossiers WHERE patient=? AND date_sortie IS NULL', [patient]);
      if (enCours != null) throw RegleMetier('Ce patient a déjà un programme en cours ($enCours).');
      final prog = base.ligne('SELECT * FROM programmes_desintox WHERE code=?', [programme]) ??
          (throw RegleMetier('Programme inconnu : $programme'));
      final d = duree ?? prog['duree_jours'] as int;
      if (d <= 0) throw const RegleMetier('Durée invalide.');
      final calcule = montantProgramme(base, programme, d);
      final total = montantTotal ?? calcule;
      if (total != calcule) {
        // Montant modifié : rôle autorisé et motif obligatoires.
        s.exiger('desintox', 'valider');
        if (motifMontant == null || motifMontant.trim().isEmpty) {
          throw const RegleMetier('Le montant diffère du programme : motif obligatoire.');
        }
      }
      if (total <= 0) throw const RegleMetier('Le montant total doit être positif.');
      if (responsables.isEmpty) throw const RegleMetier('Indiquez au moins un responsable du paiement.');
      for (final r in responsables) {
        if (r.nom.trim().isEmpty || r.telephone.trim().isEmpty) {
          throw const RegleMetier('Nom et téléphone de chaque responsable sont obligatoires.');
        }
      }
      final sommeEch = echeancier.fold<int>(0, (t, e) => t + e.montant);
      if (sommeEch > total) throw const RegleMetier("L'échéancier dépasse le montant total.");
      final numero = Numerotation.dossier(base, prefixe: 'D', exercice: base.maintenant.year);
      return Operations.enregistrer(s, type: 'desintox_inscription', entite: 'CS', donnees: {
        'id': base.nouvelUuid(),
        'numero': numero,
        'patient': patient,
        'programme': programme,
        'date_entree': dateIso(base.maintenant),
        'duree': d,
        'montant_total': total,
        'motif_montant': motifMontant,
        'responsables': [for (final r in responsables) r.versJson()],
        'echeancier': [for (final e in echeancier) e.versJson()],
        'reconnaissance': base.param('desintox_reconnaissance'),
      });
    });
  }

  static Ligne dossier(Base base, String id) =>
      base.ligne('SELECT * FROM desintox_dossiers WHERE id=?', [id]) ?? (throw const RegleMetier('Dossier introuvable.'));

  /// Versement progressif. Le reçu indique : versé ce jour, total versé, reste.
  static Operation verser(Session s,
      {required String dossierId, required int montant, required String payeur, required String mode, String? reference}) {
    final base = s.base;
    return base.transaction(() {
      final sit = situation(base, dossierId);
      if (montant <= 0) throw const RegleMetier('Le montant doit être positif.');
      if (montant > sit.reste) throw RegleMetier('Le versement dépasse le reste à payer (${fcfa(sit.reste)}).');
      if (payeur.trim().isEmpty) throw const RegleMetier('Indiquez le nom de la personne qui paie.');
      if (!Modes.encaissables.contains(mode)) throw const RegleMetier('Mode de paiement invalide.');
      Tresorerie.verifierReference(mode, reference);
      return Operations.enregistrer(s, type: 'desintox_versement', entite: 'CS', typePiece: 'REC', donnees: {
        'dossier': dossierId,
        'patient': sit.dossier['patient'],
        'montant': montant,
        'payeur': payeur.trim(),
        'mode': mode,
        'reference': reference,
        'tresorerie': Tresorerie.pourMode(base, 'CS', mode),
        // Informations figées sur le reçu :
        'total_verse_apres': sit.verse + montant,
        'reste_apres': sit.reste - montant,
      });
    });
  }

  /// Modification du montant total (rôle autorisé, motif tracé).
  static Operation modifierMontant(Session s, String dossierId, int nouveauTotal, String motif) {
    final base = s.base;
    return base.transaction(() {
      s.exiger('desintox', 'valider');
      final sit = situation(base, dossierId);
      if (motif.trim().isEmpty) throw const RegleMetier('Le motif est obligatoire.');
      if (nouveauTotal < sit.verse) throw RegleMetier('Le montant ne peut pas être inférieur au total déjà versé (${fcfa(sit.verse)}).');
      if (nouveauTotal == sit.total) throw const RegleMetier('Le montant est inchangé.');
      return Operations.enregistrer(s, type: 'desintox_montant', entite: 'CS', donnees: {
        'dossier': dossierId,
        'patient': sit.dossier['patient'],
        'ancien': sit.total,
        'nouveau': nouveauTotal,
        'motif': motif.trim(),
      });
    });
  }

  static Operation sortir(Session s, String dossierId, {required String motif, String? precision}) {
    final base = s.base;
    return base.transaction(() {
      final d = dossier(base, dossierId);
      if (d['date_sortie'] != null) throw const RegleMetier('La sortie est déjà enregistrée.');
      if (!motifsSortie.contains(motif)) throw RegleMetier('Motif de sortie : ${motifsSortie.join(', ')}.');
      return Operations.enregistrer(s,
          type: 'desintox_sortie', entite: 'CS', donnees: {'dossier': dossierId, 'motif': motif, 'precision': precision});
    });
  }

  /// Reconnaissance étalée : constate le produit acquis jusqu'à [jusquau]
  /// (prorata des jours écoulés ; totalité à la sortie).
  static Operation? constaterProduits(Session s, {String? jusquau}) {
    final base = s.base;
    return base.transaction(() {
      final fin = jusquau ?? dateIso(base.maintenant);
      final montants = <Map<String, Object?>>[];
      for (final d in base.lignes("SELECT * FROM desintox_dossiers WHERE reconnaissance='etalee'")) {
        final sit = situation(base, d['id'] as String);
        final duree = d['duree_prevue'] as int;
        int acquis;
        if (d['date_sortie'] != null && (d['date_sortie'] as String).compareTo(fin) <= 0) {
          acquis = sit.total;
        } else {
          final jours = joursEntre(d['date_entree'] as String, fin).clamp(0, duree);
          acquis = sit.total * jours ~/ duree;
        }
        final delta = acquis - (d['produit_constate'] as int);
        if (delta > 0) montants.add({'dossier': d['id'], 'montant': delta, 'numero': d['numero']});
      }
      if (montants.isEmpty) return null;
      return Operations.enregistrer(s, type: 'desintox_constatation', entite: 'CS', donnees: {'jusquau': fin, 'montants': montants});
    });
  }

  // ------------------------------------------------------------------ calculs

  static SituationDesintox situation(Base base, String dossierId, {String? aLaDate}) {
    final d = dossier(base, dossierId);
    final versements = base.lignes(
        'SELECT * FROM desintox_versements WHERE dossier=? AND annule=0 ORDER BY horodatage', [dossierId]);
    final verse = versements.fold<int>(0, (t, v) => t + (v['montant'] as int));
    final total = d['montant_total'] as int;
    final aujourdhui = aLaDate ?? dateIso(base.maintenant);
    String statut;
    String? dateArchivage;
    if (d['date_sortie'] == null) {
      statut = 'en_cours';
    } else if (verse < total) {
      statut = 'sorti_solde_du';
    } else {
      // Soldé : archivé [délai] jours après la sortie, ou après le dernier
      // versement si le solde a été réglé après la sortie.
      final dernier = versements.isEmpty ? d['date_sortie'] as String : versements.last['date'] as String;
      final reference = dernier.compareTo(d['date_sortie'] as String) > 0 ? dernier : d['date_sortie'] as String;
      dateArchivage = ajouterJours(reference, base.paramInt('desintox_archivage_jours'));
      statut = aujourdhui.compareTo(dateArchivage) >= 0 ? 'archive' : 'sorti_solde';
    }
    return SituationDesintox(d, total, verse, versements, statut, dateArchivage);
  }

  /// Liste de travail : onglet « en_cours » (en cours + sortis soldés non
  /// encore archivés) ou « solde_du » (sortis avec solde dû).
  static List<SituationDesintox> listeTravail(Base base, {String onglet = 'en_cours', String recherche = ''}) {
    final t = '%${recherche.trim().toUpperCase()}%';
    final ids = base.lignes(
        'SELECT d.id FROM desintox_dossiers d JOIN patients p ON p.id=d.patient '
        'WHERE UPPER(p.nom) LIKE ? OR UPPER(p.prenoms) LIKE ? OR UPPER(d.numero) LIKE ? OR UPPER(p.numero_dossier) LIKE ? '
        'ORDER BY d.date_entree DESC',
        [t, t, t, t]);
    final r = <SituationDesintox>[];
    for (final i in ids) {
      final sit = situation(base, i['id'] as String);
      final garder = onglet == 'solde_du'
          ? sit.statut == 'sorti_solde_du'
          : onglet == 'archives'
              ? sit.statut == 'archive'
              : sit.statut == 'en_cours' || sit.statut == 'sorti_solde';
      if (garder) r.add(sit);
    }
    return r;
  }

  static List<SituationDesintox> archives(Base base, {String recherche = ''}) =>
      listeTravail(base, onglet: 'archives', recherche: recherche);

  /// Échéances non honorées : cumul prévu à date > total versé.
  static List<Map<String, Object?>> echeancesImpayees(Base base, {String? aLaDate}) {
    final aujourdhui = aLaDate ?? dateIso(base.maintenant);
    final r = <Map<String, Object?>>[];
    for (final d in base.lignes('SELECT id FROM desintox_dossiers')) {
      final sit = situation(base, d['id'] as String, aLaDate: aujourdhui);
      if (sit.statut == 'archive') continue;
      final ech = (jsonDecode(sit.dossier['echeancier'] as String) as List).cast<Map>();
      var cumul = 0;
      for (final e in ech) {
        if ((e['date'] as String).compareTo(aujourdhui) >= 0) break;
        cumul += e['montant'] as int;
        if (sit.verse < cumul) {
          r.add({
            'dossier': sit.dossier['id'],
            'numero': sit.dossier['numero'],
            'date': e['date'],
            'manquant': cumul - sit.verse,
          });
          break;
        }
      }
    }
    return r;
  }

  /// Total restant à encaisser sur tous les dossiers non soldés.
  static int resteTotal(Base base) {
    var t = 0;
    for (final d in base.lignes('SELECT id FROM desintox_dossiers')) {
      t += situation(base, d['id'] as String).reste;
    }
    return t;
  }

  /// Données du rapport de sortie (PDF).
  static Map<String, Object?> rapportSortie(Base base, String dossierId) {
    final sit = situation(base, dossierId);
    final d = sit.dossier;
    final p = base.ligne('SELECT * FROM patients WHERE id=?', [d['patient']])!;
    final prog = base.ligne('SELECT * FROM programmes_desintox WHERE code=?', [d['programme']])!;
    final sortie = d['date_sortie'] as String?;
    return {
      'patient': p,
      'dossier': d,
      'programme': prog['libelle'],
      'responsables': jsonDecode(d['responsables'] as String),
      'date_entree': d['date_entree'],
      'date_sortie': sortie,
      'duree_effective': sortie == null ? null : joursEntre(d['date_entree'] as String, sortie),
      'motif_sortie': d['motif_sortie'],
      'montant_total': sit.total,
      'versements': sit.versements,
      'total_verse': sit.verse,
      'reste': sit.reste,
    };
  }

  static void declarer() {
    Operations.declarer(_Inscription());
    Operations.declarer(_Versement());
    Operations.declarer(_Montant());
    Operations.declarer(_Sortie());
    Operations.declarer(_Constatation());
  }
}

class _Inscription extends TypeOperation {
  @override
  String get type => 'desintox_inscription';
  @override
  String get module => 'desintox';
  @override
  String get libelle => 'Inscription en désintoxication';
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    final d = op.donnees;
    base.exec(
        'INSERT INTO desintox_dossiers(id, numero, patient, programme, date_entree, duree_prevue, montant_total, responsables, echeancier, reconnaissance, uuid_op) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        [d['id'], d['numero'], d['patient'], d['programme'], d['date_entree'], d['duree'], d['montant_total'],
          jsonEncode(d['responsables']), jsonEncode(d['echeancier']), d['reconnaissance'], op.uuid]);
    final etalee = d['reconnaissance'] == 'etalee';
    Moteur.generer(base, op, etalee ? 'desintox_inscription_etalee' : 'desintox_inscription',
        total: d['montant_total'] as int, tiers: d['patient'] as String, activite: 'DESINTOX', libelle: 'Inscription ${d['numero']}');
  }
}

class _Versement extends TypeOperation {
  @override
  String get type => 'desintox_versement';
  @override
  String get module => 'desintox';
  @override
  String get libelle => 'Versement désintoxication';

  @override
  void appliquer(Base base, Operation op) {
    final m = op.d<int>('montant');
    final treso = op.d<String>('tresorerie');
    base.exec(
        'INSERT INTO desintox_versements(uuid_op, dossier, date, horodatage, montant, payeur, mode, reference, piece) VALUES (?,?,?,?,?,?,?,?,?)',
        [op.uuid, op.d('dossier'), op.dateOp, op.horodatage, m, op.d('payeur'), op.d('mode'), op.d('reference'), op.piece]);
    final d = base.ligne('SELECT numero, montant_total FROM desintox_dossiers WHERE id=?', [op.d('dossier')]);
    Moteur.generer(base, op, 'desintox_versement',
        total: m,
        variables: Tresorerie.variables(base, treso),
        tiers: op.d<String>('patient'),
        activite: 'DESINTOX',
        libelle: 'Versement ${d?['numero'] ?? ''} – ${op.d('payeur')}');
    Tresorerie.mouvement(base, op, treso, m, 'Versement désintoxication ${d?['numero'] ?? ''}', reference: op.d('reference'));
    final verse = base.entier('SELECT COALESCE(SUM(montant),0) FROM desintox_versements WHERE dossier=? AND annule=0', [op.d('dossier')]);
    if (d != null && verse > (d['montant_total'] as int)) {
      Operations.signalerAnomalie(base, 'trop_percu', op.uuid,
          'Dossier ${d['numero']} : versements supérieurs au montant total (versements hors ligne simultanés).');
    }
  }

  @override
  void annuler(Base base, Operation cible, Operation annulation) =>
      base.exec('UPDATE desintox_versements SET annule=1 WHERE uuid_op=?', [cible.uuid]);
}

class _Montant extends TypeOperation {
  @override
  String get type => 'desintox_montant';
  @override
  String get module => 'desintox';
  @override
  String get action => 'valider';
  @override
  String get libelle => 'Modification du montant de désintoxication';
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    final d = base.ligne('SELECT * FROM desintox_dossiers WHERE id=?', [op.d('dossier')])!;
    final delta = op.d<int>('nouveau') - (d['montant_total'] as int);
    base.exec('UPDATE desintox_dossiers SET montant_total=? WHERE id=?', [op.d('nouveau'), d['id']]);
    if (delta == 0) return;
    final compteProduit = d['reconnaissance'] == 'etalee' ? '4770' : '7064';
    Moteur.generer(base, op, delta > 0 ? 'desintox_hausse' : 'desintox_baisse',
        total: delta.abs(),
        variables: {'compte_produit': compteProduit},
        tiers: d['patient'] as String,
        activite: 'DESINTOX',
        libelle: 'Ajustement ${d['numero']} : ${op.d('motif')}');
  }
}

class _Sortie extends TypeOperation {
  @override
  String get type => 'desintox_sortie';
  @override
  String get module => 'desintox';
  @override
  String get libelle => 'Sortie de désintoxication';
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) => base.exec(
      'UPDATE desintox_dossiers SET date_sortie=?, motif_sortie=? WHERE id=?', [op.dateOp, op.d('motif'), op.d('dossier')]);
}

class _Constatation extends TypeOperation {
  @override
  String get type => 'desintox_constatation';
  @override
  String get module => 'comptabilite';
  @override
  String get libelle => 'Constatation des produits de désintoxication';
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    for (final m in op.d<List>('montants').cast<Map>()) {
      base.exec('UPDATE desintox_dossiers SET produit_constate = produit_constate + ? WHERE id=?', [m['montant'], m['dossier']]);
      Moteur.generer(base, op, 'desintox_constatation',
          total: m['montant'] as int, activite: 'DESINTOX', libelle: 'Produit acquis ${m['numero']} au ${dateFr(depuisIso(op.d('jusquau')))}');
    }
  }
}
