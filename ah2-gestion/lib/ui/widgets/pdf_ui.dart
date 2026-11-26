/// Impression et partage des documents PDF (imprimante Wi-Fi ou Bluetooth,
/// WhatsApp, e-mail…).
library;

import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../../pdf/documents.dart';
import '../etat_app.dart';

Future<void> afficherPdf(BuildContext context, Future<Uint8List> Function() fabriquer, String nom) async {
  final octets = await fabriquer();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(nom, style: const TextStyle(fontWeight: FontWeight.w700))),
        ListTile(
          leading: const Icon(Icons.print_outlined),
          title: const Text('Imprimer'),
          onTap: () async {
            Navigator.pop(c);
            await Printing.layoutPdf(onLayout: (_) async => octets, name: nom);
          },
        ),
        ListTile(
          leading: const Icon(Icons.share_outlined),
          title: const Text('Partager (WhatsApp, e-mail…) ou enregistrer'),
          onTap: () async {
            Navigator.pop(c);
            await Printing.sharePdf(bytes: octets, filename: '$nom.pdf');
          },
        ),
      ]),
    ),
  );
}

Future<void> afficherRecu(BuildContext context, String uuidOp) {
  final b = Etat.lire(context).base!;
  final piece = b.valeur('SELECT piece FROM operations WHERE uuid=?', [uuidOp]) as String? ?? 'recu';
  return afficherPdf(context, () => Documents.recu(b, uuidOp), piece);
}
