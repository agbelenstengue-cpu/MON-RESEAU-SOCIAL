/// Modèle commun à tous les rapports et états : une ou plusieurs sections
/// (tableaux), avec totaux calculés. Le même rapport s'affiche à l'écran,
/// s'exporte en PDF (entête de la structure) et en Excel.
library;

import '../noyau/outils.dart';

enum TypeColonne { texte, montant, nombre, pourcentage }

class Colonne {
  final String titre;
  final TypeColonne type;
  final double poids; // largeur relative
  const Colonne(this.titre, {this.type = TypeColonne.texte, this.poids = 1});
  bool get aDroite => type != TypeColonne.texte;
}

class Section {
  final String? titre;
  final List<Colonne> colonnes;
  final List<List<Object?>> lignes;

  /// Ligne de total (null : calculée automatiquement pour les colonnes de
  /// montants et de nombres si [totaliser] est vrai).
  final List<Object?>? total;
  final bool totaliser;
  final String libelleTotal;

  Section({
    this.titre,
    required this.colonnes,
    required this.lignes,
    this.total,
    this.totaliser = true,
    this.libelleTotal = 'TOTAL',
  });

  /// Total réellement affiché : toujours égal à la somme des lignes.
  List<Object?>? get ligneTotal {
    if (total != null) return total;
    if (!totaliser) return null;
    if (!colonnes.any((c) => c.type == TypeColonne.montant || c.type == TypeColonne.nombre)) return null;
    return [
      for (var i = 0; i < colonnes.length; i++)
        if (i == 0)
          libelleTotal
        else if (colonnes[i].type == TypeColonne.montant || colonnes[i].type == TypeColonne.nombre)
          lignes.fold<int>(0, (t, l) => t + ((l[i] as num?)?.toInt() ?? 0))
        else
          null
    ];
  }
}

class Rapport {
  final String titre;
  final String entite; // entête utilisée (CS ou ONG)
  final String periode;
  final List<String> filtres;
  final String? note;
  final List<Section> sections;
  final List<(String, String)> synthese;
  final bool paysage;
  final List<String> signatures;

  Rapport({
    required this.titre,
    this.entite = 'CS',
    required this.periode,
    this.filtres = const [],
    this.note,
    required this.sections,
    this.synthese = const [],
    this.paysage = false,
    this.signatures = const [],
  });

  String get nomFichier =>
      '${titre.replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ]+'), '_')}_${periode.replaceAll(RegExp(r'[^0-9]+'), '_')}'.replaceAll(RegExp('_+'), '_');
}

/// Formatage d'une cellule selon le type de colonne.
String cellule(Object? v, TypeColonne t) {
  if (v == null) return '';
  switch (t) {
    case TypeColonne.montant:
      return v is num ? fcfa(v.toInt(), unite: false) : '$v';
    case TypeColonne.nombre:
      return v is num ? fcfa(v.toInt(), unite: false) : '$v';
    case TypeColonne.pourcentage:
      return v is num ? '$v %' : '$v';
    case TypeColonne.texte:
      return '$v';
  }
}

/// Période d'un rapport.
class Periode {
  final String du;
  final String au;
  const Periode(this.du, this.au);

  String get libelle => du == au ? 'Journée du ${dateFr(depuisIso(du))}' : 'Du ${dateFr(depuisIso(du))} au ${dateFr(depuisIso(au))}';

  int get jours => joursEntre(du, au) + 1;

  /// Période précédente de même durée.
  Periode get precedente => Periode(ajouterJours(du, -jours), ajouterJours(du, -1));

  /// Même période l'année précédente.
  Periode get anneePrecedente {
    String moinsUnAn(String d) {
      final a = int.parse(d.substring(0, 4)) - 1;
      final r = '$a${d.substring(4)}';
      return r.endsWith('02-29') ? '$a-02-28' : r;
    }

    return Periode(moinsUnAn(du), moinsUnAn(au));
  }

  static Periode jour(String d) => Periode(d, d);

  static Periode semaine(String d) {
    final j = depuisIso(d);
    final lundi = j.subtract(Duration(days: j.weekday - 1));
    return Periode(dateIso(lundi), dateIso(lundi.add(const Duration(days: 6))));
  }

  static Periode mois(String d) {
    final a = int.parse(d.substring(0, 4)), m = int.parse(d.substring(5, 7));
    final fin = DateTime.utc(a, m + 1, 0);
    return Periode('${d.substring(0, 7)}-01', dateIso(fin));
  }

  static Periode trimestre(String d) {
    final a = int.parse(d.substring(0, 4)), m = int.parse(d.substring(5, 7));
    final debut = ((m - 1) ~/ 3) * 3 + 1;
    return Periode(dateIso(DateTime.utc(a, debut, 1)), dateIso(DateTime.utc(a, debut + 3, 0)));
  }

  static Periode annee(String d) => Periode('${d.substring(0, 4)}-01-01', '${d.substring(0, 4)}-12-31');
}

/// Filtres communs (§8) : période, entité, service, utilisateur, appareil, subvention.
class Filtres {
  final Periode periode;
  final String? entite;
  final String? activite;
  final String? utilisateur;
  final String? appareil;
  final String? subvention;
  final String? compte;
  final String? journal;
  final String? tresorerie;
  final String? stock;
  const Filtres(this.periode,
      {this.entite, this.activite, this.utilisateur, this.appareil, this.subvention, this.compte, this.journal, this.tresorerie, this.stock});
}
