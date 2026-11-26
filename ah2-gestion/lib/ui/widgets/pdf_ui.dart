/// Affichage des documents PDF dans l'application, puis : Enregistrer,
/// Partager (WhatsApp, e-mail…), Imprimer (imprimante Wi-Fi ou Bluetooth).
library;

import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../../pdf/documents.dart';
import '../etat_app.dart';
import 'enregistrer_fichier.dart';

Future<void> afficherPdf(BuildContext context, Future<Uint8List> Function() fabriquer, String nom) async {
  final octets = await fabriquer();
  if (!context.mounted) return;
  await garderCopie(octets, '$nom.pdf');
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VisionneusePdf(octets: octets, nom: nom)));
}

/// Visionneuse plein écran.
class VisionneusePdf extends StatelessWidget {
  final Uint8List octets;
  final String nom;
  const VisionneusePdf({super.key, required this.octets, required this.nom});

  @override
  Widget build(BuildContext context) {
    final etroit = MediaQuery.sizeOf(context).width < 600;
    Widget bouton(IconData i, String t, VoidCallback f) => etroit
        ? IconButton(tooltip: t, icon: Icon(i), onPressed: f)
        : TextButton.icon(onPressed: f, icon: Icon(i), label: Text(t));
    return Scaffold(
      appBar: AppBar(
        title: Text(nom, overflow: TextOverflow.ellipsis),
        actions: [
          bouton(Icons.download_outlined, 'Enregistrer', () => enregistrerSous(context, octets, '$nom.pdf')),
          bouton(Icons.share_outlined, 'Partager', () => partagerFichier(octets, '$nom.pdf')),
          bouton(Icons.print_outlined, 'Imprimer', () => Printing.layoutPdf(onLayout: (_) async => octets, name: nom)),
          const SizedBox(width: 8),
        ],
      ),
      body: PdfPreview(
        build: (_) async => octets,
        useActions: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: '$nom.pdf',
      ),
    );
  }
}

Future<void> afficherRecu(BuildContext context, String uuidOp) {
  final b = Etat.lire(context).base!;
  final piece = b.valeur('SELECT piece FROM operations WHERE uuid=?', [uuidOp]) as String? ?? 'recu';
  return afficherPdf(context, () => Documents.recu(b, uuidOp), piece);
}
