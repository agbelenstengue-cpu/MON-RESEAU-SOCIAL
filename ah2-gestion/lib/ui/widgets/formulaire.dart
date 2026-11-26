/// Formulaire générique (boîte de dialogue) pour le paramétrage.
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class Champ {
  final String cle;
  final String libelle;
  final String initial;
  final bool nombre;
  final List<(String, String)>? choix;
  final String? aide;
  final bool modifiable;
  const Champ(this.cle, this.libelle, {this.initial = '', this.nombre = false, this.choix, this.aide, this.modifiable = true});
}

/// Affiche un formulaire. [valider] reçoit les valeurs saisies et renvoie
/// true pour fermer la fenêtre (false si une erreur a été signalée).
Future<void> formulaire(
  BuildContext context,
  String titre,
  List<Champ> champs,
  bool Function(BuildContext c, Map<String, String> valeurs) valider, {
  String bouton = 'Enregistrer',
}) {
  final ctrl = {for (final c in champs) c.cle: TextEditingController(text: c.initial)};
  final choix = {for (final c in champs) if (c.choix != null) c.cle: c.initial.isEmpty ? c.choix!.first.$1 : c.initial};
  return showDialog<void>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, maj) => AlertDialog(
        title: Text(titre),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final c in champs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: c.choix != null
                      ? DropdownButtonFormField<String>(
                          initialValue: choix[c.cle],
                          isExpanded: true,
                          items: [for (final (v, l) in c.choix!) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
                          onChanged: c.modifiable ? (v) => maj(() => choix[c.cle] = v!) : null,
                          decoration: InputDecoration(labelText: c.libelle, helperText: c.aide),
                        )
                      : TextField(
                          controller: ctrl[c.cle],
                          enabled: c.modifiable,
                          keyboardType: c.nombre ? TextInputType.number : TextInputType.text,
                          inputFormatters: c.nombre ? [FilteringTextInputFormatter.digitsOnly] : null,
                          decoration: InputDecoration(labelText: c.libelle, helperText: c.aide),
                        ),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final v = {for (final c in champs) c.cle: c.choix != null ? choix[c.cle]! : ctrl[c.cle]!.text.trim()};
              if (valider(d, v)) Navigator.pop(d);
            },
            child: Text(bouton),
          ),
        ],
      ),
    ),
  );
}

/// Demande une confirmation avant une action irréversible.
Future<bool> confirmer(BuildContext context, String question) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(question),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Confirmer')),
        ],
      ),
    ) ??
    false;
