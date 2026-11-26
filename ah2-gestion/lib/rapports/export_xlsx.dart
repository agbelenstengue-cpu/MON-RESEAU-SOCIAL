/// Export Excel (.xlsx) des rapports, sans dépendance externe : un classeur
/// Office Open XML minimal (une feuille, titres en gras, nombres en vrais
/// nombres pour pouvoir recalculer dans Excel).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'modele.dart';

class ExportXlsx {
  static String _x(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  static String _col(int i) {
    var n = i + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static Uint8List generer(Rapport r, {String structure = ''}) {
    final lignes = <String>[];
    var numero = 0;
    String ligne(List<(Object?, int)> cellules) {
      numero++;
      final b = StringBuffer('<row r="$numero">');
      for (var i = 0; i < cellules.length; i++) {
        final (v, style) = cellules[i];
        final ref = '${_col(i)}$numero';
        if (v == null || (v is String && v.isEmpty)) continue;
        if (v is num) {
          b.write('<c r="$ref" s="$style"><v>$v</v></c>');
        } else {
          b.write('<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${_x('$v')}</t></is></c>');
        }
      }
      b.write('</row>');
      return b.toString();
    }

    if (structure.isNotEmpty) lignes.add(ligne([(structure, 1)]));
    lignes.add(ligne([(r.titre, 2)]));
    lignes.add(ligne([(r.periode, 0)]));
    for (final f in r.filtres) {
      lignes.add(ligne([(f, 0)]));
    }
    if (r.note != null) lignes.add(ligne([(r.note, 0)]));
    var maxCol = 1;
    for (final s in r.sections) {
      numero++;
      lignes.add('<row r="$numero"/>');
      if (s.titre != null) lignes.add(ligne([(s.titre, 1)]));
      maxCol = s.colonnes.length > maxCol ? s.colonnes.length : maxCol;
      lignes.add(ligne([for (final c in s.colonnes) (c.titre, 3)]));
      for (final l in s.lignes) {
        lignes.add(ligne([
          for (var i = 0; i < s.colonnes.length; i++) (i < l.length ? l[i] : null, s.colonnes[i].type == TypeColonne.montant ? 4 : 0)
        ]));
      }
      final t = s.ligneTotal;
      if (t != null) {
        lignes.add(ligne([for (var i = 0; i < s.colonnes.length; i++) (i < t.length ? t[i] : null, s.colonnes[i].type == TypeColonne.montant ? 5 : 1)]));
      }
    }
    if (r.synthese.isNotEmpty) {
      numero++;
      lignes.add('<row r="$numero"/>');
      for (final (a, b) in r.synthese) {
        lignes.add(ligne([(a, 1), (b, 0)]));
      }
    }
    final largeurs = [for (var i = 0; i < maxCol; i++) '<col min="${i + 1}" max="${i + 1}" width="${i == 0 ? 34 : 16}" customWidth="1"/>'].join();
    final feuille = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<cols>$largeurs</cols><sheetData>${lignes.join()}</sheetData></worksheet>';

    const styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0"/></numFmts>'
        '<fonts count="3"><font><sz val="10"/><name val="Arial"/></font><font><b/><sz val="10"/><name val="Arial"/></font>'
        '<font><b/><sz val="13"/><name val="Arial"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFE7E6E6"/></patternFill></fill></fills>'
        '<borders count="2"><border/><border><bottom style="thin"/></border></borders>'
        '<cellStyleXfs count="1"><xf/></cellStyleXfs>'
        '<cellXfs count="6">'
        '<xf fontId="0"/>'
        '<xf fontId="1" applyFont="1"/>'
        '<xf fontId="2" applyFont="1"/>'
        '<xf fontId="1" fillId="2" borderId="1" applyFont="1" applyFill="1" applyBorder="1"/>'
        '<xf fontId="0" numFmtId="164" applyNumberFormat="1"/>'
        '<xf fontId="1" numFmtId="164" applyFont="1" applyNumberFormat="1"/>'
        '</cellXfs></styleSheet>';

    String nomFeuille() {
      final n = r.titre.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ');
      return n.length > 31 ? n.substring(0, 31) : n;
    }

    final fichiers = <String, String>{
      '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '</Types>',
      '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>',
      'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="${_x(nomFeuille())}" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '</Relationships>',
      'xl/styles.xml': styles,
      'xl/worksheets/sheet1.xml': feuille,
    };
    final archive = Archive();
    fichiers.forEach((nom, contenu) {
      final o = utf8.encode(contenu);
      archive.addFile(ArchiveFile(nom, o.length, o));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
