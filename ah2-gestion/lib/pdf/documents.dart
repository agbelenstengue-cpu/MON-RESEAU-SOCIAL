/// Documents imprimables (§7, §10.2) : en-tête commune, A4 et ticket 80 mm.
///
/// La charte (nom, sigle, adresse, contacts, numéros) est lue dans le
/// paramétrage de l'entité : modifiable sans code.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../modules/desintox/desintox.dart';
import '../modules/rapports/rapports.dart';
import '../modules/tresorerie/tresorerie.dart';
import '../noyau/base.dart';
import '../noyau/operations.dart';
import '../noyau/outils.dart';

// Présentation sobre : noir, gris, un seul trait de couleur institutionnelle.
const _vert = PdfColor.fromInt(0xFF1F4D36);
const _gris = PdfColor.fromInt(0xFFF2F2F2);
const _bord = PdfColor.fromInt(0xFFBFBFBF);
const _sombre = PdfColor.fromInt(0xFF2B2B2B);

class Documents {
  static String _m(int v) => fcfa(v);

  // ------------------------------------------------------------ police Arial
  static Uint8List? _normale, _gras, _italique, _grasItalique;

  /// Polices des documents. L'application fournit Arial (Windows) ou son
  /// équivalent métrique libre Liberation Sans (Android), embarqué.
  static void configurerPolices({required Uint8List normale, required Uint8List gras, Uint8List? italique, Uint8List? grasItalique}) {
    _normale = normale;
    _gras = gras;
    _italique = italique ?? normale;
    _grasItalique = grasItalique ?? gras;
  }

  static Uint8List? _lire(List<String> chemins) {
    for (final c in chemins) {
      final f = File(c);
      if (f.existsSync()) return f.readAsBytesSync();
    }
    return null;
  }

  static void _chargerPolicesParDefaut() {
    const win = r'C:\Windows\Fonts\';
    final n = _lire(['${win}arial.ttf', 'assets/polices/LiberationSans-Regular.ttf']);
    final g = _lire(['${win}arialbd.ttf', 'assets/polices/LiberationSans-Bold.ttf']);
    if (n == null || g == null) return;
    configurerPolices(
      normale: n,
      gras: g,
      italique: _lire(['${win}ariali.ttf', 'assets/polices/LiberationSans-Italic.ttf']),
      grasItalique: _lire(['${win}arialbi.ttf', 'assets/polices/LiberationSans-BoldItalic.ttf']),
    );
  }

  static pw.ThemeData _theme() {
    if (_normale == null) _chargerPolicesParDefaut();
    if (_normale == null) return pw.ThemeData.base();
    pw.Font f(Uint8List o) => pw.Font.ttf(ByteData.sublistView(o));
    return pw.ThemeData.withFont(base: f(_normale!), bold: f(_gras!), italic: f(_italique!), boldItalic: f(_grasItalique!));
  }

  /// Page A4 avec, si l'option est active, le logo de la structure en filigrane.
  static pw.PageTheme _page(Base base, String entite, {pw.EdgeInsets marge = const pw.EdgeInsets.fromLTRB(36, 32, 36, 24)}) {
    final e = base.ligne('SELECT logo, filigrane FROM entites WHERE code=?', [entite]);
    final logo = e?['logo'] as Uint8List?;
    final filigrane = logo != null && e?['filigrane'] == 1;
    return pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: marge,
      theme: _theme(),
      buildBackground: filigrane
          ? (c) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Center(child: pw.Opacity(opacity: 0.07, child: pw.Image(pw.MemoryImage(logo), width: 360))),
              )
          : null,
    );
  }

  static pw.Widget _entete(Base base, String entite, {bool compact = false}) {
    final e = base.ligne('SELECT * FROM entites WHERE code=?', [entite])!;
    final logo = e['logo'] as Uint8List?;
    final entete = e['entete'] as Uint8List?;
    final lignes = [
      if ((e['adresse'] as String).isNotEmpty) e['adresse'] as String,
      if ((e['contacts'] as String).isNotEmpty) e['contacts'] as String,
      if ((e['numeros_administratifs'] as String).isNotEmpty) e['numeros_administratifs'] as String,
    ];
    if (compact) {
      return pw.Column(children: [
        if (logo != null) pw.Image(pw.MemoryImage(logo), height: 42),
        pw.Text(e['nom'] as String, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center),
        for (final l in lignes) pw.Text(l, style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
        pw.Divider(thickness: 0.5),
      ]);
    }
    // Entête importée (papier à en-tête de la structure) : utilisée telle quelle.
    if (entete != null) {
      return pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _sombre, width: 0.8))),
        child: pw.Image(pw.MemoryImage(entete), height: 90, fit: pw.BoxFit.contain),
      );
    }
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _vert, width: 1.2))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        if (logo != null) ...[
          pw.Image(pw.MemoryImage(logo), width: 58, height: 58, fit: pw.BoxFit.contain),
          pw.SizedBox(width: 14),
        ],
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text((e['nom'] as String).toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12.5)),
            if ((e['sigle'] as String).isNotEmpty) pw.Text(e['sigle'] as String, style: const pw.TextStyle(fontSize: 9.5)),
            for (final l in lignes) pw.Text(l, style: const pw.TextStyle(fontSize: 9)),
          ]),
        ),
      ]),
    );
  }

  static pw.Widget _pied(pw.Context c, String numero) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _bord))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Page ${c.pageNumber} / ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
          pw.Text(numero, style: const pw.TextStyle(fontSize: 8)),
          pw.Text('Document généré par AH2 Gestion', style: const pw.TextStyle(fontSize: 8)),
        ]),
      );

  static pw.Widget _cadreSignature(String titre, List<String> champs) => pw.Expanded(
        child: pw.Container(
          height: 90,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600), borderRadius: pw.BorderRadius.circular(3)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(titre, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.SizedBox(height: 4),
            for (final c in champs) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Text('$c :', style: const pw.TextStyle(fontSize: 9))),
          ]),
        ),
      );

  static pw.Widget _tableau(List<String> entetes, List<List<String>> lignes,
      {Map<int, pw.TableColumnWidth>? largeurs, Set<int> droite = const {}}) {
    return pw.Table(
      border: pw.TableBorder.all(color: _bord, width: 0.5),
      columnWidths: largeurs,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _sombre),
          children: [
            for (var i = 0; i < entetes.length; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(entetes[i],
                    style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold),
                    textAlign: droite.contains(i) ? pw.TextAlign.right : pw.TextAlign.left),
              ),
          ],
        ),
        for (var r = 0; r < lignes.length; r++)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: r.isOdd ? _gris : PdfColors.white),
            children: [
              for (var i = 0; i < lignes[r].length; i++)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
                  child: pw.Text(lignes[r][i],
                      style: const pw.TextStyle(fontSize: 8), textAlign: droite.contains(i) ? pw.TextAlign.right : pw.TextAlign.left),
                ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _synthese(String titre, List<(String, String)> lignes, {double largeur = 220}) => pw.Container(
        width: largeur,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _bord), borderRadius: pw.BorderRadius.circular(3)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Text(titre, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.SizedBox(height: 4),
          for (var i = 0; i < lignes.length; i++)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              decoration: i == lignes.length - 1
                  ? const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _bord)))
                  : null,
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text(lignes[i].$1, style: pw.TextStyle(fontSize: 9, fontWeight: i == lignes.length - 1 ? pw.FontWeight.bold : null)),
                pw.Text(lignes[i].$2, style: pw.TextStyle(fontSize: 9, fontWeight: i == lignes.length - 1 ? pw.FontWeight.bold : null)),
              ]),
            ),
        ]),
      );

  // ============================================================ REÇU 80 mm

  static Future<Uint8List> recu(Base base, String uuidOp) async {
    final op = Operations.lire(base, uuidOp)!;
    final doc = pw.Document(title: op.piece);
    final patient = op.donnees['patient'] == null
        ? null
        : base.ligne('SELECT * FROM patients WHERE id=?', [op.donnees['patient']]);
    final caissier = base.valeur('SELECT nom FROM utilisateurs WHERE id=?', [op.utilisateur]) ?? '';
    final annule = Operations.estAnnulee(base, uuidOp);
    final lignes = <(String, String)>[];
    String titre = 'REÇU';
    int total = 0;
    switch (op.type) {
      case 'acte':
        titre = op.d('mode') == Modes.credit ? 'FACTURE' : (op.d('mode') == Modes.priseEnCharge ? 'PRISE EN CHARGE' : 'REÇU');
        for (final l in op.d<List>('lignes').cast<Map>()) {
          lignes.add(('${l['libelle']}${(l['quantite'] as int) > 1 ? ' x${l['quantite']}' : ''}', _m(l['montant'] as int)));
        }
        total = op.d<int>('total');
      case 'desintox_versement':
        final d = base.ligne('SELECT numero FROM desintox_dossiers WHERE id=?', [op.d('dossier')]);
        lignes.add(('Versement désintoxication ${d?['numero'] ?? ''}', _m(op.d<int>('montant'))));
        total = op.d<int>('montant');
      case 'don':
        titre = 'REÇU DE DON';
        final nom = base.valeur('SELECT nom FROM donateurs WHERE id=?', [op.d('donateur')]) ?? '';
        lignes.add(('Don de $nom${op.d('nature') == 'nature' ? ' (en nature, valeur estimée)' : ''}', _m(op.d<int>('montant'))));
        total = op.d<int>('montant');
      default:
        total = (op.donnees['montant'] as int?) ?? 0;
        lignes.add((op.type, _m(total)));
    }
    final petit = const pw.TextStyle(fontSize: 8);
    doc.addPage(pw.Page(
      pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.roll80, margin: const pw.EdgeInsets.all(8), theme: _theme()),
      build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        _entete(base, op.entite, compact: true),
        pw.Text(titre, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.Text(op.piece ?? '', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        if (annule) pw.Text('*** ANNULÉ ***', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Le ${dateFr(op.instant)} à ${heureFr(op.instant)}', style: petit),
        if (patient != null) pw.Text('Patient : ${patient['nom']} ${patient['prenoms']} (${patient['numero_dossier']})', style: petit),
        if (op.type == 'desintox_versement') pw.Text('Payé par : ${op.d('payeur')}', style: petit),
        pw.Divider(thickness: 0.5),
        for (final l in lignes)
          pw.Row(children: [pw.Expanded(child: pw.Text(l.$1, style: petit)), pw.Text(l.$2, style: petit)]),
        pw.Divider(thickness: 0.5),
        pw.Row(children: [
          pw.Expanded(child: pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
          pw.Text(_m(total), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        ]),
        if (op.donnees['mode'] != null) pw.Text('Mode : ${Modes.libelles[op.d('mode')] ?? op.d('mode')}', style: petit),
        if (op.donnees['reference'] != null) pw.Text('Réf. transaction : ${op.d('reference')}', style: petit),
        if (op.donnees['motif_gratuite'] != null) pw.Text('Gratuité : ${op.d('motif_gratuite')}', style: petit),
        if (op.type == 'desintox_versement') ...[
          pw.SizedBox(height: 4),
          pw.Text('Versé ce jour : ${_m(op.d<int>('montant'))}', style: petit),
          pw.Text('Total déjà versé : ${_m(op.d<int>('total_verse_apres'))}', style: petit),
          pw.Text('Reste à payer : ${op.d<int>('reste_apres') == 0 ? 'Soldé' : _m(op.d<int>('reste_apres'))}',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ],
        pw.SizedBox(height: 6),
        pw.Text('Caissier : $caissier · Appareil ${op.appareil}', style: petit),
        pw.SizedBox(height: 6),
        pw.Text('Document généré par AH2 Gestion', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7)),
      ]),
    ));
    return doc.save();
  }

  // ============================================================ RELEVÉ A4

  static Future<Uint8List> releve(Base base, String numero) async {
    final r = base.ligne('SELECT * FROM releves WHERE numero=?', [numero])!;
    final contenu = jsonDecode(r['contenu'] as String) as Map;
    final entite = base.valeur('SELECT entite FROM activites WHERE code=?', [r['activite']]) as String;
    final lignes = (contenu['lignes'] as List).cast<Map>();
    final syn = contenu['synthese'] as Map;
    final parMode = Map<String, Object?>.from(syn['par_mode'] as Map);
    final ecarts = base.param('releve_section_ecarts', '1') == '1';
    final genere = DateTime.parse(r['genere_le'] as String);
    final doc = pw.Document(title: numero);
    doc.addPage(pw.MultiPage(
      pageTheme: _page(base, entite, marge: const pw.EdgeInsets.fromLTRB(32, 32, 32, 24)),
      header: (c) => c.pageNumber == 1 ? _entete(base, entite) : pw.SizedBox(),
      footer: (c) => _pied(c, numero),
      build: (c) => [
        pw.SizedBox(height: 10),
        pw.Center(child: pw.Text(contenu['titre'] as String? ?? 'RELEVÉ JOURNALIER DES ACTES',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5))),
        pw.SizedBox(height: 10),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Service : ${contenu['service'] ?? r['activite']}', style: const pw.TextStyle(fontSize: 10)),
              pw.Text('Date des actes : ${dateFr(depuisIso(r['date_actes'] as String))}', style: const pw.TextStyle(fontSize: 10)),
            ]),
          ),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('N° : $numero', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('Généré le : ${dateFr(genere)} à ${heureFr(genere)}', style: const pw.TextStyle(fontSize: 10)),
              pw.Text('Par : ${r['genere_par']}', style: const pw.TextStyle(fontSize: 10)),
            ]),
          ),
        ]),
        pw.SizedBox(height: 10),
        _tableau(
          ['N°', 'Heure', 'N° reçu / facture', 'Dossier', 'Acte ou examen', 'Montant', 'Mode', 'Confirmé'],
          [
            for (final l in lignes)
              ['${l['n']}', l['heure'] as String, l['piece'] as String, l['dossier'] as String, l['acte'] as String,
                fcfa(l['montant'] as int, unite: false), l['mode'] as String, '[  ]'],
          ],
          largeurs: const {
            0: pw.FixedColumnWidth(20),
            1: pw.FixedColumnWidth(32),
            2: pw.FixedColumnWidth(122),
            3: pw.FixedColumnWidth(84),
            4: pw.FlexColumnWidth(),
            5: pw.FixedColumnWidth(46),
            6: pw.FixedColumnWidth(60),
            7: pw.FixedColumnWidth(50),
          },
          droite: {5},
        ),
        if (lignes.isEmpty) pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Aucun acte enregistré pour ce service à cette date.')),
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: _synthese('Synthèse', [
            ("Nombre d'actes", '${syn['nombre_actes']}'),
            for (final e in parMode.entries) (e.key, _m(e.value as int)),
            ('Nombre de gratuités', '${syn['gratuites']}'),
            ('Total encaissé', _m(syn['total_encaisse'] as int)),
          ]),
        ),
        if (ecarts) ...[
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _bord), borderRadius: pw.BorderRadius.circular(3)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Écarts constatés', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.SizedBox(height: 4),
              _tableau(['N° ligne / reçu', 'Nature : [ ] non réalisé  [ ] réalisé non enregistré  [ ] montant différent  [ ] autre', 'Observation'],
                  [for (var i = 0; i < 4; i++) ['', '', '']],
                  largeurs: const {0: pw.FixedColumnWidth(80), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(1)}),
            ]),
          ),
        ],
        pw.SizedBox(height: 10),
        pw.Text('Le responsable du service atteste que les actes cochés ci-dessus ont été réalisés ce jour.',
            style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic)),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          _cadreSignature('Responsable du service', ['Nom', 'Date', 'Signature et cachet']),
          pw.SizedBox(width: 16),
          _cadreSignature('Comptable', ['Nom', 'Date', 'Signature']),
        ]),
      ],
    ));
    return doc.save();
  }

  // ============================================================ RAPPORT DE SORTIE

  static Future<Uint8List> rapportSortie(Base base, String dossierId) async {
    final r = Desintox.rapportSortie(base, dossierId);
    final p = r['patient'] as Map;
    final d = r['dossier'] as Map;
    final versements = (r['versements'] as List).cast<Map>();
    final resp = (r['responsables'] as List).cast<Map>();
    final reste = r['reste'] as int;
    final sortie = r['date_sortie'] as String?;
    final doc = pw.Document(title: 'Rapport de sortie ${d['numero']}');
    pw.Widget ligne(String a, String b) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.SizedBox(width: 150, child: pw.Text(a, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(b, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
        ]));
    doc.addPage(pw.MultiPage(
      pageTheme: _page(base, 'CS', marge: const pw.EdgeInsets.fromLTRB(36, 32, 36, 24)),
      header: (c) => c.pageNumber == 1 ? _entete(base, 'CS') : pw.SizedBox(),
      footer: (c) => _pied(c, d['numero'] as String),
      build: (c) => [
        pw.SizedBox(height: 12),
        pw.Center(child: pw.Text('RAPPORT DE SORTIE DU PATIENT', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 14),
        ligne('Patient', '${p['nom']} ${p['prenoms']}'),
        ligne('N° de dossier', '${p['numero_dossier']} · programme ${d['numero']}'),
        for (final x in resp) ligne('Responsable du paiement', '${x['nom']} (${x['lien']}) · ${x['telephone']}'),
        pw.SizedBox(height: 8),
        ligne('Programme', r['programme'] as String),
        ligne("Date d'entrée", dateFr(depuisIso(r['date_entree'] as String))),
        ligne('Date de sortie', sortie == null ? 'En cours' : dateFr(depuisIso(sortie))),
        ligne('Durée effective', r['duree_effective'] == null ? 'Non renseigné' : '${r['duree_effective']} jours'),
        ligne('Motif de sortie', Desintox.libellesMotifs[r['motif_sortie']] ?? ''),
        ligne('Montant total', _m(r['montant_total'] as int)),
        pw.SizedBox(height: 12),
        _tableau(['Date', 'N° de reçu', 'Payé par', 'Mode', 'Montant'], [
          for (final v in versements)
            [dateFr(depuisIso(v['date'] as String)), v['piece'] as String, v['payeur'] as String, Modes.libelles[v['mode']] ?? '${v['mode']}', _m(v['montant'] as int)],
        ], droite: {4}),
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: _synthese('Situation', [
            ('Montant total', _m(r['montant_total'] as int)),
            ('Total versé', _m(r['total_verse'] as int)),
            (reste == 0 ? 'Situation' : 'Reste à payer', reste == 0 ? 'Soldé' : _m(reste)),
          ]),
        ),
        pw.SizedBox(height: 24),
        pw.Row(children: [
          _cadreSignature('Comptable', ['Nom', 'Signature']),
          pw.SizedBox(width: 10),
          _cadreSignature('Responsable du programme', ['Nom', 'Signature']),
          pw.SizedBox(width: 10),
          _cadreSignature('Parent ou tuteur', ['Nom', 'Signature']),
        ]),
      ],
    ));
    return doc.save();
  }

  // ============================================================ RAPPORT DU JOUR

  static Future<Uint8List> rapportJour(Base base, String date) async {
    final r = Rapports.financierDuJour(base, date);
    final lignes = (r['lignes'] as List).cast<Map>();
    final caisses = base.lignes("SELECT id FROM tresoreries WHERE actif=1 ORDER BY entite, centrale DESC, id");
    final numero = 'RFJ-${date.replaceAll('-', '')}';
    final doc = pw.Document(title: 'Rapport financier du ${dateFr(depuisIso(date))}');
    doc.addPage(pw.MultiPage(
      pageTheme: _page(base, 'CS', marge: const pw.EdgeInsets.fromLTRB(36, 32, 36, 24)),
      header: (c) => c.pageNumber == 1 ? _entete(base, 'CS') : pw.SizedBox(),
      footer: (c) => _pied(c, numero),
      build: (c) => [
        pw.SizedBox(height: 12),
        pw.Center(child: pw.Text('RAPPORT FINANCIER DU ${dateFr(depuisIso(date))}', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: _gris, borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Text(r['note'] as String, style: const pw.TextStyle(fontSize: 11)),
        ),
        pw.SizedBox(height: 12),
        _tableau(['Activité', 'Recettes', 'Part'], [
          for (final l in lignes) [l['libelle'] as String, _m(l['montant'] as int), '${l['pourcentage']} %'],
          ['TOTAL', _m(r['recettes'] as int), lignes.isEmpty ? '0 %' : '100 %'],
        ], droite: {1, 2}),
        pw.SizedBox(height: 12),
        _synthese('Résultat du jour', [
          ('Recettes', _m(r['recettes'] as int)),
          ('Charges', _m(r['charges'] as int)),
          ('Encaissements', _m(r['encaissements'] as int)),
          ('Résultat', _m(r['resultat'] as int)),
        ], largeur: 260),
        pw.SizedBox(height: 12),
        pw.Text('Soldes de trésorerie au ${dateFr(depuisIso(date))}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.SizedBox(height: 4),
        _tableau(['Entité', 'Compte', 'Solde'], [
          for (final c in caisses)
            () {
              final t = Tresorerie.compte(base, c['id'] as String);
              return [t['entite'] as String, t['libelle'] as String, _m(Tresorerie.solde(base, c['id'] as String, jusquau: date))];
            }(),
        ], droite: {2}),
      ],
    ));
    return doc.save();
  }

  // ============================================================ ARRÊTÉ DE CAISSE

  static Future<Uint8List> arreteCaisse(Base base, String uuidOp) async {
    final a = base.ligne('SELECT * FROM arretes_caisse WHERE uuid_op=?', [uuidOp])!;
    final op = Operations.lire(base, uuidOp)!;
    final t = Tresorerie.compte(base, a['tresorerie'] as String);
    final bill = Map<String, Object?>.from(jsonDecode(a['billetage'] as String) as Map);
    final doc = pw.Document(title: a['piece'] as String);
    doc.addPage(pw.Page(
      pageTheme: _page(base, t['entite'] as String, marge: const pw.EdgeInsets.fromLTRB(36, 32, 36, 24)),
      build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        _entete(base, t['entite'] as String),
        pw.SizedBox(height: 12),
        pw.Center(child: pw.Text('ARRÊTÉ DE CAISSE', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold))),
        pw.Center(child: pw.Text('${t['libelle']} · ${dateFr(op.instant)} à ${heureFr(op.instant)} · ${a['piece']}')),
        pw.SizedBox(height: 12),
        _tableau(['Coupure', 'Nombre', 'Montant'], [
          for (final e in bill.entries)
            if ((e.value as int) > 0) [_m(int.parse(e.key)), '${e.value}', _m(int.parse(e.key) * (e.value as int))],
        ], droite: {1, 2}),
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: _synthese('Contrôle', [
            ('Total compté', _m(a['compte'] as int)),
            ('Solde théorique', _m(a['theorique'] as int)),
            ((a['ecart'] as int) < 0 ? 'Manquant' : ((a['ecart'] as int) > 0 ? 'Excédent' : 'Écart'), _m(a['ecart'] as int)),
          ]),
        ),
        if (a['motif_ecart'] != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Text('Motif de l’écart : ${a['motif_ecart']}')),
        pw.Spacer(),
        pw.Row(children: [
          _cadreSignature('Caissier', ['Nom', 'Signature']),
          pw.SizedBox(width: 16),
          _cadreSignature('Comptable', ['Nom', 'Signature']),
        ]),
        pw.SizedBox(height: 8),
        pw.Center(child: pw.Text('Document généré par AH2 Gestion', style: const pw.TextStyle(fontSize: 8))),
      ]),
    ));
    return doc.save();
  }
}
