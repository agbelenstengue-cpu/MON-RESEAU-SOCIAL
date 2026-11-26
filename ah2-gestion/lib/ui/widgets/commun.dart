/// Composants communs de l'interface.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../noyau/outils.dart';
import '../etat_app.dart';
import '../theme.dart';

/// Exécute une action métier : affiche l'erreur en français si une règle est
/// violée, sinon un message de succès, puis rafraîchit les écrans.
T? executer<T>(BuildContext context, T Function() action, {String? succes}) {
  final etat = Etat.lire(context);
  final messager = ScaffoldMessenger.of(context);
  try {
    final r = action();
    etat.rafraichir();
    if (succes != null) {
      messager.showSnackBar(SnackBar(content: Text(succes), behavior: SnackBarBehavior.floating));
    }
    return r;
  } on RegleMetier catch (e) {
    messager.showSnackBar(SnackBar(
      content: Text(e.message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Couleurs.baisse,
    ));
    return null;
  }
}

/// Variante pour une action sans résultat : renvoie true si elle a réussi.
bool reussir(BuildContext context, void Function() action, {String? succes}) =>
    executer<bool>(context, () {
      action();
      return true;
    }, succes: succes) ??
    false;

class Carte extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const Carte({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

class TitreSection extends StatelessWidget {
  final String titre;
  final String? sousTitre;
  final Widget? action;
  const TitreSection(this.titre, {super.key, this.sousTitre, this.action});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(children: [
      Expanded(
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 12, children: [
          Text(titre, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (sousTitre != null) Text(sousTitre!, style: t.bodySmall?.copyWith(color: Theme.of(context).hintColor)),
        ]),
      ),
      ?action,
    ]);
  }
}

class CarteIndicateur extends StatelessWidget {
  final String libelle;
  final String valeur;
  final String? detail;
  final Color? couleurDetail;
  const CarteIndicateur({super.key, required this.libelle, required this.valeur, this.detail, this.couleurDetail});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Carte(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(libelle, style: t.bodySmall?.copyWith(color: Theme.of(context).hintColor, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(valeur, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (detail != null) ...[
          const SizedBox(height: 6),
          Text(detail!, style: t.bodySmall?.copyWith(color: couleurDetail ?? Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}

/// Champ de montant : clavier numérique, chiffres uniquement (FCFA entiers).
class ChampMontant extends StatelessWidget {
  final TextEditingController controleur;
  final String libelle;
  final String? aide;
  final ValueChanged<String>? onChanged;
  const ChampMontant({super.key, required this.controleur, this.libelle = 'Montant (FCFA)', this.aide, this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controleur,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        decoration: InputDecoration(labelText: libelle, helperText: aide, suffixText: 'FCFA'),
        onChanged: onChanged,
      );
}

int lireMontant(TextEditingController c) => int.tryParse(c.text) ?? 0;

/// Choix par pastilles (sélection plutôt que saisie libre).
class ChoixPastilles<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T? valeur;
  final ValueChanged<T> onChanged;
  const ChoixPastilles({super.key, required this.options, required this.valeur, required this.onChanged});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (v, l) in options)
          ChoiceChip(
            label: Text(l),
            selected: v == valeur,
            onSelected: (_) => onChanged(v),
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          ),
      ]);
}

class Etape extends StatelessWidget {
  final String numero;
  final String titre;
  final Widget child;
  const Etape(this.numero, this.titre, {super.key, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$numero · $titre', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          child,
        ]),
      );
}

class EtatVide extends StatelessWidget {
  final String message;
  final IconData icone;
  const EtatVide(this.message, {super.key, this.icone = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Icon(icone, size: 40, color: Theme.of(context).hintColor),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
        ]),
      );
}

class Pastille extends StatelessWidget {
  final String texte;
  final Color couleur;
  const Pastille(this.texte, {super.key, required this.couleur});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
        child: Text(texte, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

Color couleurTendance(String t) => switch (t) {
      'en_hausse' => Couleurs.hausse,
      'en_baisse' => Couleurs.baisse,
      _ => Couleurs.stable,
    };

String libelleTendance(String t) => switch (t) {
      'en_hausse' => 'en hausse',
      'en_baisse' => 'en baisse',
      _ => 'stable',
    };

/// Page avec largeur maximale confortable sur PC.
class PageContenu extends StatelessWidget {
  final List<Widget> enfants;
  final double largeurMax;
  const PageContenu({super.key, required this.enfants, this.largeurMax = 1200});

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.symmetric(horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 32, vertical: 20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: largeurMax),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: enfants),
            ),
          ),
          const SizedBox(height: 96),
        ],
      );
}

String montant(int m) => fcfa(m);
