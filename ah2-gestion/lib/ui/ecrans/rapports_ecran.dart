/// Rapports et états : choix du rapport, de la période (jour, semaine, mois,
/// trimestre, année, dates libres) et des filtres ; aperçu ; export PDF et Excel.
library;

import 'package:material_ui/material_ui.dart';

import '../../noyau/outils.dart';
import '../../pdf/documents.dart';
import '../../rapports/catalogue.dart';
import '../../rapports/export_xlsx.dart';
import '../../rapports/modele.dart';
import '../etat_app.dart';
import '../widgets/commun.dart';
import '../widgets/enregistrer_fichier.dart';
import '../widgets/pdf_ui.dart';

class EcranRapports extends StatefulWidget {
  const EcranRapports({super.key});
  @override
  State<EcranRapports> createState() => _EcranRapportsState();
}

enum _TypePeriode { jour, semaine, mois, trimestre, annee, libre }

class _EcranRapportsState extends State<EcranRapports> {
  String _id = 'financier';
  _TypePeriode _type = _TypePeriode.mois;
  DateTime? _ref;
  DateTimeRange? _libre;
  String? _entite;
  String? _activite;
  String? _utilisateur;
  String? _appareil;
  String? _subvention;
  String? _tresorerie;
  final _racine = TextEditingController();

  Periode _periode(DateTime ref) {
    final d = dateIso(ref);
    return switch (_type) {
      _TypePeriode.jour => Periode.jour(d),
      _TypePeriode.semaine => Periode.semaine(d),
      _TypePeriode.mois => Periode.mois(d),
      _TypePeriode.trimestre => Periode.trimestre(d),
      _TypePeriode.annee => Periode.annee(d),
      _TypePeriode.libre => _libre == null ? Periode.mois(d) : Periode(dateIso(_libre!.start), dateIso(_libre!.end)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final def = Catalogue.parId(_id);
    final ref = _ref ?? b.maintenant;
    final periode = _periode(ref);
    final params = Parametres(
      Filtres(periode,
          entite: _entite,
          activite: _activite,
          utilisateur: _utilisateur,
          appareil: _appareil,
          subvention: _subvention,
          tresorerie: _tresorerie),
      date: dateIso(ref),
      racine: _racine.text.trim(),
    );
    Rapport? produit;
    String? erreur;
    try {
      produit = def.produire(b, params);
    } on RegleMetier catch (e) {
      erreur = e.message;
    }
    final rapport = produit;
    final large = MediaQuery.sizeOf(context).width >= 1000;
    final liste = _liste(context);
    final contenu = ListView(padding: const EdgeInsets.all(16), children: [
      if (!large)
        DropdownButtonFormField<String>(
          initialValue: _id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Rapport'),
          items: [for (final d in Catalogue.tous) DropdownMenuItem(value: d.id, child: Text('${d.categorie} : ${d.titre}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _id = v!),
        ),
      if (!large) const SizedBox(height: 12),
      Text(def.titre, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      if (def.description.isNotEmpty) Text(def.description, style: TextStyle(color: Theme.of(context).hintColor)),
      const SizedBox(height: 12),
      _filtres(context, def, ref, periode),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: rapport == null ? null : () => afficherPdf(context, () => Documents.rapport(b, rapport), rapport.titre),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('PDF (imprimer, partager)'),
        ),
        OutlinedButton.icon(
          onPressed: rapport == null
              ? null
              : () => enregistrerFichier(
                    context,
                    ExportXlsx.generer(rapport, structure: (b.valeur('SELECT nom FROM entites WHERE code=?', [rapport.entite]) as String?) ?? ''),
                    '${rapport.nomFichier}.xlsx',
                  ),
          icon: const Icon(Icons.table_view_outlined),
          label: const Text('Excel'),
        ),
      ]),
      const SizedBox(height: 16),
      if (erreur != null) Carte(child: Text(erreur)),
      if (rapport != null) _apercu(context, rapport),
    ]);
    if (!large) return contenu;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 300, child: Material(color: Theme.of(context).colorScheme.surface, child: liste)),
      const VerticalDivider(width: 1),
      Expanded(child: contenu),
    ]);
  }

  /// Les états comptables portent toujours sur une seule entité.
  static bool _comptable(DefRapport d) => d.categorie == 'Comptabilité' || d.categorie == 'États financiers' || d.id == 'balance_agee';

  Widget _liste(BuildContext context) {
    final groupes = <String, List<DefRapport>>{};
    for (final d in Catalogue.tous) {
      groupes.putIfAbsent(d.categorie, () => []).add(d);
    }
    return ListView(children: [
      for (final g in groupes.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(g.key.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(context).hintColor)),
        ),
        for (final d in g.value)
          ListTile(
            dense: true,
            selected: d.id == _id,
            title: Text(d.titre),
            onTap: () => setState(() => _id = d.id),
          ),
      ],
    ]);
  }

  Widget _filtres(BuildContext context, DefRapport def, DateTime ref, Periode periode) {
    final b = Etat.de(context).base!;
    final f = def.filtres;
    Widget liste(String libelle, String? valeur, List<(String, String)> options, ValueChanged<String?> maj) => SizedBox(
          width: 230,
          child: DropdownButtonFormField<String?>(
            initialValue: valeur,
            isExpanded: true,
            decoration: InputDecoration(labelText: libelle, isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Tous')),
              for (final (v, l) in options) DropdownMenuItem<String?>(value: v, child: Text(l, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => maj(v)),
          ),
        );
    return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (f.contains(Filtre.periode))
        ChoixPastilles<_TypePeriode>(
          options: const [
            (_TypePeriode.jour, 'Jour'),
            (_TypePeriode.semaine, 'Semaine'),
            (_TypePeriode.mois, 'Mois'),
            (_TypePeriode.trimestre, 'Trimestre'),
            (_TypePeriode.annee, 'Année'),
            (_TypePeriode.libre, 'Dates libres'),
          ],
          valeur: _type,
          onChanged: (v) => setState(() => _type = v),
        ),
      if (f.contains(Filtre.periode) && _type == _TypePeriode.libre)
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range),
          label: Text(periode.libelle),
          onPressed: () async {
            final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDateRange: _libre);
            if (r != null) setState(() => _libre = r);
          },
        )
      else if (f.contains(Filtre.periode) || f.contains(Filtre.date))
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text(f.contains(Filtre.periode) ? periode.libelle : 'Au ${dateFr(ref)}'),
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: ref, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (d != null) setState(() => _ref = d);
          },
        ),
      if (f.contains(Filtre.entite))
        SizedBox(
          width: 230,
          child: DropdownButtonFormField<String?>(
            key: ValueKey('entite-${_comptable(def)}'),
            initialValue: _comptable(def) ? (_entite ?? 'CS') : _entite,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Entité', isDense: true),
            items: [
              if (!_comptable(def)) const DropdownMenuItem<String?>(value: null, child: Text('Les deux entités')),
              const DropdownMenuItem<String?>(value: 'CS', child: Text('Centre de santé (SYSCOHADA)')),
              const DropdownMenuItem<String?>(value: 'ONG', child: Text('ONG (SYCEBNL)')),
            ],
            onChanged: (v) => setState(() => _entite = v),
          ),
        ),
      if (f.contains(Filtre.activite))
        liste('Service', _activite, [for (final a in b.lignes('SELECT code, libelle FROM activites ORDER BY libelle')) (a['code'] as String, a['libelle'] as String)],
            (v) => _activite = v),
      if (f.contains(Filtre.utilisateur))
        liste('Utilisateur', _utilisateur, [for (final u in b.lignes('SELECT id, nom FROM utilisateurs ORDER BY nom')) (u['id'] as String, u['nom'] as String)],
            (v) => _utilisateur = v),
      if (f.contains(Filtre.appareil))
        liste('Appareil', _appareil, [for (final a in b.lignes('SELECT code, nom FROM appareils ORDER BY code')) (a['code'] as String, '${a['code']} ${a['nom']}')],
            (v) => _appareil = v),
      if (f.contains(Filtre.subvention))
        liste('Subvention', _subvention, [for (final s in b.lignes('SELECT id, reference FROM subventions')) (s['id'] as String, s['reference'] as String)],
            (v) => _subvention = v),
      if (f.contains(Filtre.tresorerie))
        liste('Caisse ou banque', _tresorerie,
            [for (final t in b.lignes('SELECT id, libelle, entite FROM tresoreries ORDER BY entite, id')) (t['id'] as String, '${t['libelle']} (${t['entite']})')],
            (v) => _tresorerie = v),
      if (f.contains(Filtre.racine))
        SizedBox(
          width: 200,
          child: TextField(
            controller: _racine,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Comptes commençant par', isDense: true),
            onSubmitted: (_) => setState(() {}),
          ),
        ),
    ]);
  }

  Widget _apercu(BuildContext context, Rapport r) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(r.periode, style: t.titleSmall),
      for (final f in r.filtres) Text(f, style: t.bodySmall),
      if (r.note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Carte(child: Text(r.note!))),
      for (final s in r.sections) ...[
        const SizedBox(height: 14),
        if (s.titre != null) Text(s.titre!, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (s.lignes.isEmpty)
          const Text('Aucune donnée pour cette période.')
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 30,
                dataRowMaxHeight: 44,
                columnSpacing: 18,
                columns: [for (final c in s.colonnes) DataColumn(label: Text(c.titre, style: const TextStyle(fontWeight: FontWeight.bold)), numeric: c.aDroite)],
                rows: [
                  for (final l in s.lignes.take(500))
                    DataRow(cells: [for (var i = 0; i < s.colonnes.length; i++) DataCell(Text(cellule(i < l.length ? l[i] : null, s.colonnes[i].type)))]),
                  if (s.ligneTotal != null)
                    DataRow(cells: [
                      for (var i = 0; i < s.colonnes.length; i++)
                        DataCell(Text(cellule(i < s.ligneTotal!.length ? s.ligneTotal![i] : null, s.colonnes[i].type),
                            style: const TextStyle(fontWeight: FontWeight.bold)))
                    ]),
                ],
              ),
            ),
          ),
        if (s.lignes.length > 500) Text('Aperçu limité aux 500 premières lignes ; le PDF et Excel contiennent tout (${s.lignes.length} lignes).'),
      ],
      if (r.synthese.isNotEmpty) ...[
        const SizedBox(height: 14),
        Card(
          child: Column(children: [
            for (final (a, v) in r.synthese) ListTile(dense: true, title: Text(a), trailing: Text(v, style: const TextStyle(fontWeight: FontWeight.bold))),
          ]),
        ),
      ],
    ]);
  }
}
