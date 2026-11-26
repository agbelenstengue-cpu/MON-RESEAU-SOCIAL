/// Enregistre un fichier (Excel, export Sage…) : choix de l'emplacement sur
/// PC, partage (WhatsApp, e-mail) sur téléphone.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

Future<void> enregistrerFichier(BuildContext context, Uint8List octets, String nom) async {
  final messager = ScaffoldMessenger.of(context);
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      await SharePlus.instance.share(ShareParams(files: [XFile.fromData(octets, name: nom)], fileNameOverrides: [nom]));
      return;
    }
    final ext = nom.split('.').last;
    final cible = await getSaveLocation(
      suggestedName: nom,
      acceptedTypeGroups: [XTypeGroup(label: ext.toUpperCase(), extensions: [ext])],
    );
    if (cible == null) return;
    await File(cible.path).writeAsBytes(octets, flush: true);
    messager.showSnackBar(SnackBar(content: Text('Fichier enregistré : ${cible.path}')));
  } catch (e) {
    messager.showSnackBar(SnackBar(content: Text("Impossible d'enregistrer le fichier : $e")));
  }
}
