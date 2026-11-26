/// Logo de la structure (paramétrable) et filigrane d'écran.
library;

import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../etat_app.dart';

Uint8List? _logo(BuildContext context, {String entite = 'CS'}) {
  final b = Etat.de(context).base;
  if (b == null) return null;
  try {
    return b.valeur('SELECT logo FROM entites WHERE code=?', [entite]) as Uint8List?;
  } catch (_) {
    return null;
  }
}

/// Logo de la structure ; celui livré par défaut si aucun n'est paramétré.
class LogoStructure extends StatelessWidget {
  final double taille;
  const LogoStructure({super.key, this.taille = 48});

  @override
  Widget build(BuildContext context) {
    final o = _logo(context);
    return SizedBox(
      width: taille,
      height: taille,
      child: o != null
          ? Image.memory(o, fit: BoxFit.contain, gaplessPlayback: true)
          : Image.asset('assets/images/logo_ah2.png', fit: BoxFit.contain),
    );
  }
}

/// Le logo de la structure en filigrane derrière le contenu (désactivable
/// dans Paramétrage › Structure).
class Filigrane extends StatelessWidget {
  final Widget child;
  const Filigrane({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final b = Etat.de(context).base;
    final actif = b != null && b.valeur("SELECT filigrane FROM entites WHERE code='CS'") == 1;
    final o = _logo(context);
    if (!actif || o == null) return child;
    return Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Opacity(
              opacity: Theme.of(context).brightness == Brightness.dark ? 0.035 : 0.05,
              child: Image.memory(o, width: 420, fit: BoxFit.contain, gaplessPlayback: true),
            ),
          ),
        ),
      ),
      child,
    ]);
  }
}
