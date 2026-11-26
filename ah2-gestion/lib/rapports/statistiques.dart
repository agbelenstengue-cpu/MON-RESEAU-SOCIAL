/// Statistiques : séries chiffrées pour les courbes et histogrammes de
/// l'écran Statistiques, et leur version tableau (PDF, Excel).
library;

import '../modules/rapports/rapports.dart';
import '../noyau/base.dart';
import '../noyau/outils.dart';
import 'modele.dart';

/// Une série de points (étiquette, valeur).
class Serie {
  final String titre;
  final List<(String, int)> points;
  final bool montant;
  const Serie(this.titre, this.points, {this.montant = true});
  int get total => points.fold(0, (t, p) => t + p.$2);
}

class Statistiques {
  final Periode periode;
  final bool parMois;
  final Serie recettes;
  final Serie depenses;
  final Serie recettesParService;
  final Serie actesParService;
  final Serie depensesParNature;
  final Serie nouveauxPatients;
  final Serie entreesDesintox;
  const Statistiques({
    required this.periode,
    required this.parMois,
    required this.recettes,
    required this.depenses,
    required this.recettesParService,
    required this.actesParService,
    required this.depensesParNature,
    required this.nouveauxPatients,
    required this.entreesDesintox,
  });

  List<Serie> get evolutions => [recettes, depenses, nouveauxPatients, entreesDesintox];
  List<Serie> get repartitions => [recettesParService, actesParService, depensesParNature];

  static const _mois = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

  /// Découpe la période en jours (jusqu'à 62 jours) ou en mois.
  static List<(String, String, String)> _tranches(Periode p) {
    final r = <(String, String, String)>[];
    if (p.jours <= 62) {
      for (var d = p.du; d.compareTo(p.au) <= 0; d = ajouterJours(d, 1)) {
        r.add((d, d, '${d.substring(8)}/${d.substring(5, 7)}'));
      }
    } else {
      var a = int.parse(p.du.substring(0, 4)), m = int.parse(p.du.substring(5, 7));
      while (true) {
        final debut = '$a-${m.toString().padLeft(2, '0')}-01';
        if (debut.compareTo(p.au) > 0) break;
        final suivant = m == 12 ? '${a + 1}-01-01' : '$a-${(m + 1).toString().padLeft(2, '0')}-01';
        final fin = ajouterJours(suivant, -1);
        r.add((debut.compareTo(p.du) < 0 ? p.du : debut, fin.compareTo(p.au) > 0 ? p.au : fin, '${_mois[m - 1]} ${a % 100}'));
        m++;
        if (m == 13) {
          m = 1;
          a++;
        }
      }
    }
    return r;
  }

  static Statistiques calculer(Base b, Periode p, {String? entite}) {
    final tr = _tranches(p);
    final ent = entite != null ? 'AND e.entite=?' : '';
    Serie parTranche(String titre, String sql, {bool montant = true, bool avecEntite = true}) => Serie(titre, [
          for (final t in tr) (t.$3, b.entier(sql, [t.$1, t.$2, if (avecEntite) ?entite]))
        ], montant: montant);

    final recettes = parTranche('Recettes',
        "SELECT COALESCE(SUM(l.credit - l.debit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE l.compte LIKE '7%' AND e.date BETWEEN ? AND ? $ent");
    final depenses = parTranche('Charges',
        "SELECT COALESCE(SUM(l.debit - l.credit),0) FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture WHERE l.compte LIKE '6%' AND e.date BETWEEN ? AND ? $ent");
    final patients = parTranche('Nouveaux patients', "SELECT COUNT(*) FROM operations WHERE type='patient_creation' AND date_op BETWEEN ? AND ?",
        montant: false, avecEntite: false);
    final desintox = parTranche('Entrées en désintoxication', 'SELECT COUNT(*) FROM desintox_dossiers WHERE date_entree BETWEEN ? AND ?',
        montant: false, avecEntite: false);

    final libelles = {for (final a in b.lignes('SELECT code, libelle FROM activites')) a['code'] as String: a['libelle'] as String};
    final parAct = Rapports.recettesParActivite(b, du: p.du, au: p.au, entite: entite).entries.where((e) => e.value != 0).toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    final actes = b.lignes(
        'SELECT a.activite, COUNT(*) AS n FROM actes a WHERE a.date BETWEEN ? AND ? AND a.annule=0 GROUP BY a.activite ORDER BY n DESC', [p.du, p.au]);
    final natures = b.lignes(
        "SELECT COALESCE(n.libelle, c.libelle, d.compte) AS lib, SUM(d.montant) AS m FROM depenses d "
        "LEFT JOIN natures_depenses n ON n.code=d.nature AND n.entite=d.entite LEFT JOIN comptes c ON c.numero=d.compte AND c.entite=d.entite "
        "WHERE d.date BETWEEN ? AND ? AND d.annule=0 AND d.statut='payee' ${entite != null ? 'AND d.entite=?' : ''} GROUP BY lib ORDER BY m DESC",
        [p.du, p.au, ?entite]);
    return Statistiques(
      periode: p,
      parMois: p.jours > 62,
      recettes: recettes,
      depenses: depenses,
      recettesParService: Serie('Recettes par service', [for (final e in parAct) (libelles[e.key] ?? e.key, e.value)]),
      actesParService: Serie('Nombre d’actes par service', [for (final a in actes) (libelles[a['activite']] ?? a['activite'] as String, a['n'] as int)],
          montant: false),
      depensesParNature: Serie('Dépenses par nature', [for (final n in natures) (n['lib'] as String, n['m'] as int)]),
      nouveauxPatients: patients,
      entreesDesintox: desintox,
    );
  }

  /// Version tableau, pour l'impression et l'export Excel.
  Rapport rapport() {
    Section evolution() => Section(
          titre: 'Évolution ${parMois ? 'mensuelle' : 'journalière'}',
          colonnes: const [
            Colonne('Période', poids: 1.2),
            Colonne('Recettes', type: TypeColonne.montant),
            Colonne('Charges', type: TypeColonne.montant),
            Colonne('Résultat', type: TypeColonne.montant),
            Colonne('Nouveaux patients', type: TypeColonne.nombre),
            Colonne('Entrées désintox', type: TypeColonne.nombre),
          ],
          lignes: [
            for (var i = 0; i < recettes.points.length; i++)
              [
                recettes.points[i].$1,
                recettes.points[i].$2,
                depenses.points[i].$2,
                recettes.points[i].$2 - depenses.points[i].$2,
                nouveauxPatients.points[i].$2,
                entreesDesintox.points[i].$2,
              ]
          ],
        );
    Section repartition(Serie s) {
      final pct = Rapports.pourcentages([for (final p in s.points) p.$2]);
      return Section(titre: s.titre, colonnes: [
        const Colonne('Libellé', poids: 3),
        Colonne(s.montant ? 'Montant' : 'Nombre', type: s.montant ? TypeColonne.montant : TypeColonne.nombre),
        const Colonne('Part', type: TypeColonne.pourcentage),
      ], lignes: [
        for (var i = 0; i < s.points.length; i++) [s.points[i].$1, s.points[i].$2, pct[i]]
      ]);
    }

    return Rapport(
      titre: 'Statistiques',
      periode: periode.libelle,
      sections: [evolution(), for (final s in repartitions) repartition(s)],
      synthese: [
        ('Recettes', fcfa(recettes.total)),
        ('Charges', fcfa(depenses.total)),
        ('Résultat', fcfa(recettes.total - depenses.total)),
        ('Nouveaux patients', '${nouveauxPatients.total}'),
        ('Entrées en désintoxication', '${entreesDesintox.total}'),
      ],
    );
  }
}
