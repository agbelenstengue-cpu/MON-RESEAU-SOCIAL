/// Dépenses et achats : natures de dépenses (reliées à leur compte),
/// dépenses répétitives (loyer, abonnements…), compte rendu du soir.
library;

import '../../noyau/base.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../parametrage/parametrage.dart';

class Depenses {
  static List<Ligne> natures(Base b, String entite) =>
      b.lignes('SELECT * FROM natures_depenses WHERE entite=? AND actif=1 ORDER BY libelle', [entite]);

  /// Ajoute ou modifie une nature de dépense (le comptable choisit le compte une fois pour toutes).
  static void enregistrerNature(Session s,
          {required String entite, required String code, required String libelle, required String compte, String? activite}) =>
      Parametrage.modifier(s, 'parametrage', 'nature_depense:$entite:$code', () {
        final c = code.trim().toUpperCase();
        if (c.isEmpty || libelle.trim().isEmpty) throw const RegleMetier('Code et libellé obligatoires.');
        if (s.base.valeur('SELECT 1 FROM comptes WHERE entite=? AND numero=? AND actif=1', [entite, compte]) == null) {
          throw RegleMetier("Le compte $compte n'existe pas dans le plan comptable.");
        }
        s.base.exec(
            'INSERT INTO natures_depenses(code, entite, libelle, compte, activite) VALUES (?,?,?,?,?) '
            'ON CONFLICT(code, entite) DO UPDATE SET libelle=excluded.libelle, compte=excluded.compte, activite=excluded.activite, actif=1',
            [c, entite, libelle.trim(), compte, activite]);
      }, nouveau: {'libelle': libelle, 'compte': compte});

  static void retirerNature(Session s, String entite, String code) => Parametrage.modifier(s, 'parametrage', 'nature_depense:$entite:$code',
      () => s.base.exec('UPDATE natures_depenses SET actif=0 WHERE entite=? AND code=?', [entite, code]), nouveau: 'retirée');

  // ------------------------------------------------------------ dépenses répétitives
  static void enregistrerModele(Session s,
          {String? id, required String entite, required String nature, required String beneficiaire, required int montant, required int jour}) =>
      Parametrage.modifier(s, 'parametrage', 'depense_repetitive:$nature', () {
        if (montant <= 0 || jour < 1 || jour > 28) throw const RegleMetier('Montant positif ; jour du mois entre 1 et 28.');
        s.base.exec(
            'INSERT INTO depenses_modeles(id, entite, nature, beneficiaire, montant, jour) VALUES (?,?,?,?,?,?) '
            'ON CONFLICT(id) DO UPDATE SET nature=excluded.nature, beneficiaire=excluded.beneficiaire, montant=excluded.montant, jour=excluded.jour, actif=1',
            [id ?? s.base.nouvelUuid(), entite, nature, beneficiaire.trim(), montant, jour]);
      }, nouveau: {'nature': nature, 'montant': montant, 'jour': jour});

  static void retirerModele(Session s, String id) => Parametrage.modifier(s, 'parametrage', 'depense_repetitive:$id',
      () => s.base.exec('UPDATE depenses_modeles SET actif=0 WHERE id=?', [id]), nouveau: 'retirée');

  /// Dépenses répétitives du mois en cours, avec leur état (payée ou à payer).
  static List<Map<String, Object?>> aPayerCeMois(Base b) {
    final mois = dateIso(b.maintenant).substring(0, 7);
    return [
      for (final m in b.lignes(
          'SELECT m.*, n.libelle FROM depenses_modeles m JOIN natures_depenses n ON n.code=m.nature AND n.entite=m.entite WHERE m.actif=1 ORDER BY m.jour'))
        {
          ...m,
          'payee': b.valeur(
                  "SELECT 1 FROM depenses WHERE entite=? AND nature=? AND beneficiaire=? AND substr(date,1,7)=? AND annule=0 AND statut<>'rejetee'",
                  [m['entite'], m['nature'], m['beneficiaire'], mois]) !=
              null,
          'echeance': '$mois-${(m['jour'] as int).toString().padLeft(2, '0')}',
        }
    ];
  }

  // ------------------------------------------------------------ compte rendu du soir
  /// Enregistre les observations du comptable pour une journée.
  static Operation observer(Session s, {required String date, required String observations}) => Operations.enregistrer(s,
      type: 'compte_rendu', entite: 'CS', donnees: {'date': date, 'observations': observations.trim()});

  static String observations(Base b, String date) => (b.valeur('SELECT observations FROM comptes_rendus WHERE date=?', [date]) as String?) ?? '';

  static void declarer() => Operations.declarer(_CompteRendu());
}

class _CompteRendu extends TypeOperation {
  @override
  String get type => 'compte_rendu';
  @override
  String get module => 'rapports';
  @override
  String get action => 'voir';
  @override
  String get libelle => 'Compte rendu de la journée';
  @override
  bool get horsJournee => true;
  @override
  bool get annulable => false;
  @override
  void appliquer(Base base, Operation op) => base.exec(
      'INSERT INTO comptes_rendus(date, observations, uuid_op) VALUES (?,?,?) ON CONFLICT(date) DO UPDATE SET observations=excluded.observations, uuid_op=excluded.uuid_op',
      [op.d('date'), op.d('observations'), op.uuid]);
}
