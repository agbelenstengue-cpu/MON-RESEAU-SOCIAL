/// Statistiques : courbes et histogrammes (recettes, charges, patients,
/// répartitions par service et par nature), exportables en PDF et Excel.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../noyau/outils.dart';
import '../../pdf/documents.dart';
import '../../rapports/export_xlsx.dart';
import '../../rapports/modele.dart';
import '../../rapports/statistiques.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';
import '../widgets/enregistrer_fichier.dart';
import '../widgets/pdf_ui.dart';

const _couleurs = [Color(0xFF1F4D36), Color(0xFFB45309), Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFF0F766E), Color(0xFFBE185D), Color(0xFF64748B)];

String _court(int v) {
  final a = v.abs();
  if (a >= 1000000) return '${(v / 1000000).toStringAsFixed(a >= 10000000 ? 0 : 1)} M';
  if (a >= 1000) return '${(v / 1000).round()} k';
  return '$v';
}

class EcranStatistiques extends StatefulWidget {
  const EcranStatistiques({super.key});
  @override
  State<EcranStatistiques> createState() => _EcranStatistiquesState();
}

class _EcranStatistiquesState extends State<EcranStatistiques> {
  String _choix = 'mois';
  String? _entite;
  DateTimeRange? _libre;

  Periode _periode(DateTime t) {
    final d = dateIso(t);
    return switch (_choix) {
      '30j' => Periode(ajouterJours(d, -29), d),
      'mois' => Periode('${d.substring(0, 7)}-01', d),
      '12m' => Periode('${t.year - 1}-${t.month.toString().padLeft(2, '0')}-01', d),
      'annee' => Periode('${t.year}-01-01', d),
      'precedente' => Periode('${t.year - 1}-01-01', '${t.year - 1}-12-31'),
      _ => _libre == null ? Periode('${d.substring(0, 7)}-01', d) : Periode(dateIso(_libre!.start), dateIso(_libre!.end)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final b = Etat.de(context).base!;
    final p = _periode(b.maintenant);
    final st = Statistiques.calculer(b, p, entite: _entite);
    final rapport = st.rapport();
    final large = MediaQuery.sizeOf(context).width >= 900;
    Widget carte(String titre, Widget graphe, {String? sous}) => Carte(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (sous != null) Text(sous, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
            const SizedBox(height: 12),
            graphe,
          ]),
        );
    final graphes = [
      carte('Recettes et charges', SizedBox(height: 240, child: _Barres(series: [st.recettes, st.depenses])),
          sous: 'Recettes ${fcfa(st.recettes.total)} · charges ${fcfa(st.depenses.total)} · résultat ${fcfa(st.recettes.total - st.depenses.total)}'),
      carte('Fréquentation', SizedBox(height: 240, child: _Courbes(series: [st.nouveauxPatients, st.entreesDesintox])),
          sous: '${st.nouveauxPatients.total} nouveaux patients · ${st.entreesDesintox.total} entrées en désintoxication'),
      carte('Recettes par service', _Repartition(st.recettesParService)),
      carte('Nombre d’actes par service', _Repartition(st.actesParService)),
      carte('Dépenses par nature', _Repartition(st.depensesParNature)),
    ];
    return PageContenu(enfants: [
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ChoixPastilles<String>(
          options: const [
            ('30j', '30 derniers jours'),
            ('mois', 'Ce mois'),
            ('annee', 'Cette année'),
            ('12m', '12 derniers mois'),
            ('precedente', 'Année précédente'),
            ('libre', 'Dates libres'),
          ],
          valeur: _choix,
          onChanged: (v) async {
            if (v == 'libre') {
              final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: b.maintenant, initialDateRange: _libre);
              if (r == null) return;
              _libre = r;
            }
            setState(() => _choix = v);
          },
        ),
        ChoixPastilles<String?>(
          options: const [(null, 'Les deux entités'), ('CS', 'Centre de santé'), ('ONG', 'ONG')],
          valeur: _entite,
          onChanged: (v) => setState(() => _entite = v),
        ),
      ]),
      const SizedBox(height: 8),
      Text(p.libelle, style: TextStyle(color: Theme.of(context).hintColor)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: () => afficherPdf(context, () => Documents.rapport(b, rapport), rapport.nomFichier),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Afficher en PDF'),
        ),
        OutlinedButton.icon(
          onPressed: () => enregistrerFichier(context, ExportXlsx.generer(rapport, structure: (b.valeur("SELECT nom FROM entites WHERE code='CS'") as String?) ?? ''),
              '${rapport.nomFichier}.xlsx'),
          icon: const Icon(Icons.table_view_outlined),
          label: const Text('Excel'),
        ),
      ]),
      const SizedBox(height: 16),
      if (large)
        LayoutBuilder(
          builder: (c, cons) => Wrap(spacing: 16, runSpacing: 16, children: [
            for (final g in graphes) SizedBox(width: (cons.maxWidth - 16) / 2, child: g),
          ]),
        )
      else
        for (final g in graphes) Padding(padding: const EdgeInsets.only(bottom: 12), child: g),
    ]);
  }
}

class _Legende extends StatelessWidget {
  final List<Serie> series;
  const _Legende(this.series);
  @override
  Widget build(BuildContext context) => Wrap(spacing: 16, children: [
        for (var i = 0; i < series.length; i++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, color: _couleurs[i]),
            const SizedBox(width: 6),
            Text(series[i].titre, style: const TextStyle(fontSize: 12)),
          ]),
      ]);
}

/// Histogramme groupé.
class _Barres extends StatelessWidget {
  final List<Serie> series;
  const _Barres({required this.series});
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(child: CustomPaint(size: Size.infinite, painter: _PeintreBarres(series, Theme.of(context).hintColor))),
        const SizedBox(height: 8),
        _Legende(series),
      ]);
}

/// Courbes.
class _Courbes extends StatelessWidget {
  final List<Serie> series;
  const _Courbes({required this.series});
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(child: CustomPaint(size: Size.infinite, painter: _PeintreCourbes(series, Theme.of(context).hintColor))),
        const SizedBox(height: 8),
        _Legende(series),
      ]);
}

abstract class _PeintreAxes extends CustomPainter {
  final List<Serie> series;
  final Color texte;
  _PeintreAxes(this.series, this.texte);

  static const gauche = 44.0, bas = 22.0;

  int get maximum {
    final m = series.expand((s) => s.points).fold<int>(0, (a, p) => math.max(a, p.$2));
    if (m < 4) return 4;
    final e = math.pow(10, (math.log(m) / math.ln10).floor()).toInt();
    return ((m / e).ceil() * e);
  }

  void _texte(Canvas c, String t, Offset o, {bool centre = false, bool droite = false}) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(color: texte, fontSize: 10, fontFamily: 'Arial')), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, o - Offset(centre ? tp.width / 2 : (droite ? tp.width : 0), tp.height / 2));
  }

  /// Dessine la grille et les étiquettes ; renvoie la zone de tracé.
  Rect axes(Canvas c, Size s) {
    final zone = Rect.fromLTRB(gauche, 6, s.width - 4, s.height - bas);
    final grille = Paint()
      ..color = texte.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = zone.bottom - zone.height * i / 4;
      c.drawLine(Offset(zone.left, y), Offset(zone.right, y), grille);
      _texte(c, _court(maximum * i ~/ 4), Offset(zone.left - 6, y), droite: true);
    }
    final n = series.first.points.length;
    if (n > 0) {
      final pas = (n / 8).ceil();
      for (var i = 0; i < n; i += pas) {
        _texte(c, series.first.points[i].$1, Offset(zone.left + zone.width * (i + 0.5) / n, zone.bottom + 11), centre: true);
      }
    }
    return zone;
  }

  @override
  bool shouldRepaint(covariant _PeintreAxes old) => true;
}

class _PeintreBarres extends _PeintreAxes {
  _PeintreBarres(super.series, super.texte);
  @override
  void paint(Canvas c, Size s) {
    final zone = axes(c, s);
    final n = series.first.points.length;
    if (n == 0) return;
    final largeur = zone.width / n;
    final barre = largeur * 0.8 / series.length;
    for (var k = 0; k < series.length; k++) {
      final pinceau = Paint()..color = _couleurs[k];
      for (var i = 0; i < n; i++) {
        final v = math.max(0, series[k].points[i].$2);
        final h = zone.height * v / maximum;
        final x = zone.left + largeur * i + largeur * 0.1 + barre * k;
        c.drawRect(Rect.fromLTWH(x, zone.bottom - h, math.max(1, barre - 1), h), pinceau);
      }
    }
  }
}

class _PeintreCourbes extends _PeintreAxes {
  _PeintreCourbes(super.series, super.texte);
  @override
  void paint(Canvas c, Size s) {
    final zone = axes(c, s);
    final n = series.first.points.length;
    if (n == 0) return;
    for (var k = 0; k < series.length; k++) {
      final trait = Paint()
        ..color = _couleurs[k]
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final chemin = Path();
      for (var i = 0; i < n; i++) {
        final p = Offset(zone.left + zone.width * (i + 0.5) / n, zone.bottom - zone.height * series[k].points[i].$2 / maximum);
        i == 0 ? chemin.moveTo(p.dx, p.dy) : chemin.lineTo(p.dx, p.dy);
        if (n <= 31) c.drawCircle(p, 2.5, Paint()..color = _couleurs[k]);
      }
      c.drawPath(chemin, trait);
    }
  }
}

/// Barres horizontales avec pourcentage.
class _Repartition extends StatelessWidget {
  final Serie serie;
  const _Repartition(this.serie);
  @override
  Widget build(BuildContext context) {
    if (serie.points.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('Aucune donnée sur la période.'));
    final total = serie.total == 0 ? 1 : serie.total;
    final max = serie.points.map((p) => p.$2).reduce(math.max);
    return Column(children: [
      for (var i = 0; i < serie.points.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(serie.points[i].$1, overflow: TextOverflow.ellipsis)),
              Text('${serie.montant ? fcfa(serie.points[i].$2) : serie.points[i].$2} · ${(serie.points[i].$2 * 100 / total).round()} %',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: max == 0 ? 0 : serie.points[i].$2 / max,
                minHeight: 8,
                color: Couleurs.primaire,
                backgroundColor: Couleurs.primaire.withValues(alpha: 0.1),
              ),
            ),
          ]),
        ),
    ]);
  }
}
