/// Enregistrement des documents produits (PDF, Excel, export Sage) :
/// - une copie est toujours gardée dans « Mes documents » de l'application ;
/// - « Enregistrer » laisse choisir le dossier (Téléchargements par défaut
///   sur le téléphone, n'importe quel dossier sur le PC) ;
/// - « Partager » ouvre WhatsApp, e-mail, Bluetooth…
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Dossier « Mes documents » de l'application.
Future<Directory> dossierMesDocuments() async {
  final base = await getApplicationDocumentsDirectory();
  final d = Directory('${base.path}${Platform.pathSeparator}AH2 Gestion documents');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

String _nomPropre(String nom) => nom.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');

/// Garde une copie dans « Mes documents » ; renvoie le chemin.
Future<String?> garderCopie(Uint8List octets, String nom) async {
  try {
    final d = await dossierMesDocuments();
    final f = File('${d.path}${Platform.pathSeparator}${_nomPropre(nom)}');
    await f.writeAsBytes(octets, flush: true);
    return f.path;
  } catch (_) {
    return null;
  }
}

String _mime(String nom) => switch (nom.split('.').last.toLowerCase()) {
      'pdf' => 'application/pdf',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'csv' => 'text/csv',
      _ => 'application/octet-stream',
    };

/// Enregistre le fichier à l'endroit choisi par l'utilisateur.
Future<void> enregistrerSous(BuildContext context, Uint8List octets, String nom) async {
  final messager = ScaffoldMessenger.of(context);
  nom = _nomPropre(nom);
  await garderCopie(octets, nom);
  try {
    String? chemin;
    if (Platform.isAndroid || Platform.isIOS) {
      chemin = await FlutterFileDialog.saveFile(params: SaveFileDialogParams(data: octets, fileName: nom, mimeTypesFilter: [_mime(nom)]));
    } else {
      final ext = nom.split('.').last;
      final cible = await getSaveLocation(
        suggestedName: nom,
        initialDirectory: (await getDownloadsDirectory())?.path,
        acceptedTypeGroups: [XTypeGroup(label: ext.toUpperCase(), extensions: [ext])],
      );
      if (cible != null) {
        await File(cible.path).writeAsBytes(octets, flush: true);
        chemin = cible.path;
      }
    }
    if (chemin != null) messager.showSnackBar(SnackBar(content: Text('Document enregistré : $nom')));
  } catch (e) {
    messager.showSnackBar(SnackBar(content: Text("Impossible d'enregistrer : $e. Une copie est dans Mes documents.")));
  }
}

Future<void> partagerFichier(Uint8List octets, String nom) async {
  nom = _nomPropre(nom);
  await garderCopie(octets, nom);
  await SharePlus.instance.share(ShareParams(files: [XFile.fromData(octets, name: nom, mimeType: _mime(nom))], fileNameOverrides: [nom]));
}

/// Choix proposé pour un fichier non PDF (Excel, export Sage).
Future<void> enregistrerFichier(BuildContext context, Uint8List octets, String nom) async {
  await garderCopie(octets, nom);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(nom, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: const Text('Une copie est gardée dans Mes documents.')),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Enregistrer (Téléchargements ou autre dossier)'),
          onTap: () {
            Navigator.pop(c);
            enregistrerSous(context, octets, nom);
          },
        ),
        ListTile(
          leading: const Icon(Icons.share_outlined),
          title: const Text('Partager (WhatsApp, e-mail…)'),
          onTap: () {
            Navigator.pop(c);
            partagerFichier(octets, nom);
          },
        ),
      ]),
    ),
  );
}
