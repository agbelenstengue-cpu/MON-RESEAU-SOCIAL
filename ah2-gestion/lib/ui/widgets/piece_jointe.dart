/// Prise de photo (téléphone) ou choix d'un fichier (PC) pour une pièce jointe.
library;

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../noyau/outils.dart';
import '../../noyau/pieces_jointes.dart';

Future<Map<String, Object?>?> prendrePieceJointe(BuildContext context) async {
  final mobile = Platform.isAndroid || Platform.isIOS;
  final source = mobile
      ? await showModalBottomSheet<ImageSource>(
          context: context,
          showDragHandle: true,
          builder: (c) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Prendre une photo'),
                  onTap: () => Navigator.pop(c, ImageSource.camera)),
              ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choisir dans la galerie'),
                  onTap: () => Navigator.pop(c, ImageSource.gallery)),
            ]),
          ),
        )
      : ImageSource.gallery;
  if (source == null) return null;
  final f = await ImagePicker().pickImage(source: source, maxWidth: 1800, imageQuality: 70);
  if (f == null) return null;
  try {
    return PiecesJointes.preparer(f.name, await f.readAsBytes());
  } on RegleMetier catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    return null;
  }
}

/// Bouton « pièce jointe » avec aperçu de l'état.
class BoutonPieceJointe extends StatelessWidget {
  final Map<String, Object?>? fichier;
  final ValueChanged<Map<String, Object?>?> onChanged;
  final String libelle;
  const BoutonPieceJointe({super.key, required this.fichier, required this.onChanged, this.libelle = 'Pièce jointe (photo ou scan)'});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: () async => onChanged(await prendrePieceJointe(context) ?? fichier),
        icon: Icon(fichier == null ? Icons.add_a_photo_outlined : Icons.check_circle, color: fichier == null ? null : const Color(0xFF15803D)),
        label: Text(fichier == null ? libelle : 'Jointe : ${fichier!['nom']}', overflow: TextOverflow.ellipsis),
      );
}
