/// Immobilisations (§6.13) : registre, amortissements linéaires mensuels
/// (durée par catégorie, paramétrable), sorties (cession, rebut, perte),
/// inventaire physique.
library;

import '../../noyau/base.dart';
import '../../noyau/numerotation.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../comptabilite/moteur.dart';
import '../parametrage/parametrage.dart';
import '../tresorerie/tresorerie.dart';

class Immobilisations {
  static void enregistrerCategorie(Session s,
          {required String code, required String libelle, required String compteImmobilisation, required String compteAmortissement, required int dureeMois}) =>
      Parametrage.modifier(s, 'parametrage', 'categorie_immo:$code', () {
        if (dureeMois <= 0) throw const RegleMetier('Durée en mois invalide.');
        s.base.exec(
            'INSERT INTO categories_immobilisations(code, libelle, compte_immobilisation, compte_amortissement, duree_mois) VALUES (?,?,?,?,?) '
            'ON CONFLICT(code) DO UPDATE SET libelle=excluded.libelle, compte_immobilisation=excluded.compte_immobilisation, '
            'compte_amortissement=excluded.compte_amortissement, duree_mois=excluded.duree_mois',
            [code.trim().toUpperCase(), libelle.trim(), compteImmobilisation, compteAmortissement, dureeMois]);
      }, nouveau: {'libelle': libelle, 'duree': dureeMois});

  /// Acquisition : achat (dette fournisseur ou paiement immédiat) ou don.
  static Operation acquerir(Session s,
      {required String entite,
      required String designation,
      required String categorie,
      required int valeur,
      required String origine, // achat ou don
      String? fournisseur,
      String? mode, // paiement immédiat
      String? reference,
      String localisation = '',
      String? activite,
      int? dureeMois,
      String? dateAcquisition}) {
    final b = s.base;
    return b.transaction(() {
      final cat = b.ligne('SELECT * FROM categories_immobilisations WHERE code=?', [categorie]) ?? (throw const RegleMetier('Catégorie inconnue.'));
      if (designation.trim().isEmpty) throw const RegleMetier('La désignation est obligatoire.');
      if (valeur <= 0) throw const RegleMetier('La valeur doit être positive.');
      if (!['achat', 'don'].contains(origine)) throw const RegleMetier('Origine : achat ou don.');
      String contrepartie;
      String? treso;
      if (origine == 'don') {
        contrepartie = '1411';
      } else if (mode != null) {
        treso = Tresorerie.pourMode(b, entite, mode);
        Tresorerie.verifierReference(mode, reference);
        Tresorerie.verifierDisponible(b, treso, valeur);
        contrepartie = Tresorerie.compte(b, treso)['compte'] as String;
      } else {
        contrepartie = '4011';
      }
      final n = Numerotation.suivant(b, entite: '*', typePiece: 'IMM', exercice: b.maintenant.year);
      return Operations.enregistrer(s, type: 'immobilisation', entite: entite, typePiece: 'IMM', donnees: {
        'id': b.nouvelUuid(),
        'numero': 'INV-${b.appareil}-${b.maintenant.year}-${n.toString().padLeft(4, '0')}',
        'designation': designation.trim(),
        'categorie': categorie,
        'valeur': valeur,
        'origine': origine,
        'fournisseur': fournisseur,
        'contrepartie': contrepartie,
        'tresorerie': treso,
        'reference': reference,
        'localisation': localisation,
        'activite': activite,
        'duree': dureeMois ?? cat['duree_mois'],
        'compte_immobilisation': cat['compte_immobilisation'],
        'date_acquisition': dateAcquisition ?? dateIso(b.maintenant),
      });
    });
  }

  static int _mois(String debut, String periode) {
    final a = int.parse(debut.substring(0, 4)), m = int.parse(debut.substring(5, 7));
    final pa = int.parse(periode.substring(0, 4)), pm = int.parse(periode.substring(5, 7));
    return (pa - a) * 12 + (pm - m) + 1; // le mois d'acquisition compte
  }

  /// Amortissement cumulé théorique à la fin d'un mois.
  static int cumulTheorique(Ligne i, String periode) {
    final mois = _mois(i['date_acquisition'] as String, periode).clamp(0, i['duree_mois'] as int);
    final valeur = i['valeur'] as int;
    return mois >= (i['duree_mois'] as int) ? valeur : (valeur * mois / (i['duree_mois'] as int)).round();
  }

  /// Dotations du mois (rattrape les mois non encore passés).
  static Operation? amortir(Session s, {required String entite, required String periode}) {
    final b = s.base;
    return b.transaction(() {
      if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(periode)) throw const RegleMetier('Période : AAAA-MM.');
      final lignes = <Map<String, Object?>>[];
      for (final i in b.lignes('SELECT * FROM immobilisations WHERE entite=? AND date_sortie IS NULL', [entite])) {
        final dot = cumulTheorique(i, periode) - (i['amorti'] as int);
        if (dot > 0) {
          final cat = b.ligne('SELECT * FROM categories_immobilisations WHERE code=?', [i['categorie']])!;
          lignes.add({'id': i['id'], 'numero': i['numero'], 'montant': dot, 'compte_amortissement': cat['compte_amortissement'], 'activite': i['activite']});
        }
      }
      if (lignes.isEmpty) return null;
      return Operations.enregistrer(s, type: 'amortissements', entite: entite, typePiece: 'AMO', donnees: {'periode': periode, 'lignes': lignes});
    });
  }

  static Operation sortir(Session s, String id, {required String motif, int prixCession = 0, String mode = Modes.especes, String? reference}) {
    final b = s.base;
    return b.transaction(() {
      final i = b.ligne('SELECT * FROM immobilisations WHERE id=?', [id]) ?? (throw const RegleMetier('Immobilisation introuvable.'));
      if (i['date_sortie'] != null) throw const RegleMetier('Ce bien est déjà sorti.');
      if (!['cession', 'rebut', 'perte'].contains(motif)) throw const RegleMetier('Motif : cession, rebut ou perte.');
      if (motif == 'cession' && prixCession <= 0) throw const RegleMetier('Indiquez le prix de cession.');
      final cat = b.ligne('SELECT * FROM categories_immobilisations WHERE code=?', [i['categorie']])!;
      return Operations.enregistrer(s, type: 'immobilisation_sortie', entite: i['entite'] as String, typePiece: 'SIM', donnees: {
        'id': id,
        'motif': motif,
        'valeur': i['valeur'],
        'amorti': i['amorti'],
        'compte_immobilisation': cat['compte_immobilisation'],
        'compte_amortissement': cat['compte_amortissement'],
        'prix': prixCession,
        'tresorerie': prixCession > 0 ? Tresorerie.pourMode(b, i['entite'] as String, mode) : null,
        'reference': reference,
      });
    });
  }

  static void declarer() {
    Operations.declarer(_Acquisition());
    Operations.declarer(_Amortissements());
    Operations.declarer(_Sortie());
  }
}

class _Acquisition extends TypeOperation {
  @override
  String get type => 'immobilisation';
  @override
  String get module => 'immobilisations';
  @override
  String get libelle => "Acquisition d'immobilisation";
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    base.exec(
        'INSERT INTO immobilisations(id, numero, designation, categorie, entite, date_acquisition, valeur, origine, localisation, activite, duree_mois, uuid_op) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        [op.d('id'), op.d('numero'), op.d('designation'), op.d('categorie'), op.entite, op.d('date_acquisition'), op.d('valeur'), op.d('origine'),
          op.d('localisation'), op.d('activite'), op.d('duree'), op.uuid]);
    final treso = op.d<String?>('tresorerie');
    Moteur.generer(base, op, 'immo_acquisition',
        total: op.d<int>('valeur'),
        variables: {'compte_immobilisation': op.d<String>('compte_immobilisation'), 'contrepartie': op.d<String>('contrepartie')},
        tiers: op.d('fournisseur'),
        activite: op.d('activite'),
        libelle: '${op.d('designation')} (${op.d('numero')})');
    if (treso != null) Tresorerie.mouvement(base, op, treso, -op.d<int>('valeur'), 'Acquisition : ${op.d('designation')}', reference: op.d('reference'));
  }
}

class _Amortissements extends TypeOperation {
  @override
  String get type => 'amortissements';
  @override
  String get module => 'immobilisations';
  @override
  String get libelle => 'Dotations aux amortissements';
  @override
  bool get horsJournee => true;
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    for (final l in op.d<List>('lignes').cast<Map>()) {
      base.exec('UPDATE immobilisations SET amorti = amorti + ? WHERE id=?', [l['montant'], l['id']]);
      Moteur.generer(base, op, 'dotation_amortissement',
          total: l['montant'] as int,
          variables: {'compte_amortissement': l['compte_amortissement'] as String},
          activite: l['activite'] as String?,
          libelle: 'Amortissement ${l['numero']} ${op.d('periode')}');
    }
  }
}

class _Sortie extends TypeOperation {
  @override
  String get type => 'immobilisation_sortie';
  @override
  String get module => 'immobilisations';
  @override
  String get libelle => "Sortie d'immobilisation";
  @override
  bool get annulable => false;

  @override
  void appliquer(Base base, Operation op) {
    base.exec('UPDATE immobilisations SET date_sortie=?, motif_sortie=? WHERE id=?', [op.dateOp, op.d('motif'), op.d('id')]);
    final vars = {'compte_immobilisation': op.d<String>('compte_immobilisation'), 'compte_amortissement': op.d<String>('compte_amortissement')};
    final amorti = op.d<int>('amorti');
    final vnc = op.d<int>('valeur') - amorti;
    if (amorti > 0) Moteur.generer(base, op, 'sortie_immo_amortissement', total: amorti, variables: vars, libelle: 'Sortie ${op.piece}');
    if (vnc > 0) Moteur.generer(base, op, 'sortie_immo_vnc', total: vnc, variables: vars, libelle: 'Sortie ${op.piece} (${op.d('motif')})');
    final prix = op.d<int>('prix');
    if (prix > 0) {
      final treso = op.d<String>('tresorerie');
      Moteur.generer(base, op, 'cession_immo', total: prix, variables: Tresorerie.variables(base, treso), libelle: 'Cession ${op.piece}');
      Tresorerie.mouvement(base, op, treso, prix, 'Cession d’immobilisation', reference: op.d('reference'));
    }
  }
}
