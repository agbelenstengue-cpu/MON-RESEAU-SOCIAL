/// Compte rendu du soir aux dirigeants (un geste), mise en route guidée,
/// choix de la date de saisie (reprise de l'historique).
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/depenses/depenses.dart';
import '../../noyau/outils.dart';
import '../../pdf/documents.dart';
import '../../rapports/etats_suivi_audit.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';
import '../widgets/enregistrer_fichier.dart';
import '../widgets/pdf_ui.dart';
import 'coquille.dart';
import 'desintox.dart';

// ------------------------------------------------------------ compte rendu du soir
Future<void> ouvrirCompteRendu(BuildContext context, {String? date}) {
  final etat = Etat.lire(context);
  final b = etat.base!;
  var jour = date ?? dateIso(b.maintenantReel);
  final obs = TextEditingController(text: Depenses.observations(b, jour));
  return showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, maj) {
      Future<void> enregistrer() async {
        final texte = obs.text.trim();
        if (texte != Depenses.observations(b, jour)) {
          executer(c, () => Depenses.observer(Etat.lire(c).session!, date: jour, observations: texte));
        }
      }

      return AlertDialog(
        title: const Text('Compte rendu de la journée'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('Journée du ${dateFr(depuisIso(jour))}'),
                onPressed: () async {
                  final d = await showDatePicker(context: c, firstDate: DateTime(2020), lastDate: b.maintenantReel, initialDate: depuisIso(jour));
                  if (d != null) {
                    maj(() {
                      jour = dateIso(d);
                      obs.text = Depenses.observations(b, jour);
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              const Text(
                  'Le compte rendu reprend automatiquement l’activité de chaque service, les dépenses, les caisses, la désintoxication, '
                  'l’hospitalisation et les alertes. Ajoutez vos observations :'),
              const SizedBox(height: 10),
              TextField(
                controller: obs,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Observations du comptable', hintText: 'ex. coupure de courant, visite, manque de réactifs…'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
          OutlinedButton.icon(
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Afficher'),
            onPressed: () async {
              await enregistrer();
              if (!c.mounted) return;
              await afficherPdf(c, () => Documents.rapport(b, EtatsSuivi.compteRendu(b, jour)), 'Compte rendu $jour');
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.share_outlined),
            label: const Text('Envoyer (WhatsApp…)'),
            onPressed: () async {
              await enregistrer();
              final octets = await Documents.rapport(b, EtatsSuivi.compteRendu(b, jour));
              await partagerFichier(octets, 'Compte rendu $jour.pdf');
            },
          ),
        ],
      );
    }),
  );
}

// ------------------------------------------------------------ date de saisie
/// Le comptable choisit la date à laquelle il saisit (reprise des mois
/// passés). L'heure réelle de saisie est toujours conservée.
Future<void> choisirDateSaisie(BuildContext context) async {
  final etat = Etat.lire(context);
  final b = etat.base!;
  final reel = b.maintenantReel;
  final d = await showDatePicker(
    context: context,
    helpText: 'Saisir les opérations à la date du',
    firstDate: DateTime(reel.year - 1, 1, 1),
    lastDate: reel,
    initialDate: etat.dateSaisie == null ? reel : depuisIso(etat.dateSaisie!),
  );
  if (d == null) return;
  etat.changerDateSaisie(dateIso(d) == dateIso(reel) ? null : dateIso(d));
}

/// Bandeau affiché tant qu'on saisit à une date passée.
class BandeauReprise extends StatelessWidget {
  const BandeauReprise({super.key});
  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final d = etat.dateSaisie;
    if (d == null) return const SizedBox.shrink();
    return Material(
      color: Couleurs.alerteOrangeFond,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          const Icon(Icons.history, color: Couleurs.stable),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Reprise de l’historique : les opérations sont enregistrées à la date du ${dateFr(depuisIso(d))}.',
                style: const TextStyle(color: Couleurs.encre, fontWeight: FontWeight.w600)),
          ),
          TextButton(onPressed: () => choisirDateSaisie(context), child: const Text('Changer')),
          TextButton(onPressed: () => etat.changerDateSaisie(null), child: const Text('Revenir à aujourd’hui')),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ mise en route
class EtapeMiseEnRoute {
  final String cle;
  final String titre;
  final String detail;
  final IconData icone;
  final void Function(BuildContext) ouvrir;
  const EtapeMiseEnRoute(this.cle, this.titre, this.detail, this.icone, this.ouvrir);
}

final etapesMiseEnRoute = <EtapeMiseEnRoute>[
  EtapeMiseEnRoute('structure', 'Nom, logo et entête de la structure', 'Paramétrage › Structure : vérifiez le nom, le logo, l’entête des documents.',
      Icons.business_outlined, (c) => Navigation.de(c).ouvrir('parametrage')),
  EtapeMiseEnRoute('prix', 'Prix des consultations, examens et massages', 'Laboratoire › Liste et prix des examens ; Paramétrage › Actes et prix.',
      Icons.price_change_outlined, (c) => Navigation.de(c).ouvrir('laboratoire')),
  EtapeMiseEnRoute('desintox', 'Programmes de désintoxication et prix du litre (AE, SE)', 'Montant de chaque abonnement, prix du litre des remèdes.',
      Icons.healing_outlined, programmesEtTarifs),
  EtapeMiseEnRoute('caisses', 'Caisses, banque et mobile money : soldes de départ', 'Comptabilité › Saisie : soldes d’ouverture de chaque caisse et compte.',
      Icons.account_balance_wallet_outlined, (c) => Navigation.de(c).ouvrir('comptabilite')),
  EtapeMiseEnRoute('depenses', 'Natures de dépenses et dépenses répétitives', 'Électricité, eau, loyer… déjà prêtes ; ajoutez les vôtres et le loyer mensuel.',
      Icons.receipt_long_outlined, (c) => Navigation.de(c).ouvrir('depenses')),
  EtapeMiseEnRoute('stocks', 'Produits et stocks de départ', 'Pharmacie moderne, pharmacie traditionnelle, réactifs du laboratoire.',
      Icons.inventory_2_outlined, (c) => Navigation.de(c).ouvrir('stocks')),
  EtapeMiseEnRoute('personnel', 'Téléphones et personnes', 'Paramétrage › Appareils et Utilisateurs : un téléphone par service si besoin.',
      Icons.phone_android_outlined, (c) => Navigation.de(c).ouvrir('parametrage')),
  EtapeMiseEnRoute('reprise', 'Reprise des mois passés', 'Choisissez une date passée (icône calendrier en haut) puis saisissez comme d’habitude.',
      Icons.history, choisirDateSaisie),
];

bool miseEnRouteTerminee(EtatApp e) => etapesMiseEnRoute.every((x) => e.base!.param('mise_en_route_${x.cle}', '0') == '1');

class CarteMiseEnRoute extends StatelessWidget {
  const CarteMiseEnRoute({super.key});
  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    if (!etat.estCentral || !etat.session!.peut('parametrage', 'creer') || etat.demonstration) return const SizedBox.shrink();
    final faites = etapesMiseEnRoute.where((x) => b.param('mise_en_route_${x.cle}', '0') == '1').length;
    if (faites == etapesMiseEnRoute.length) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Carte(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TitreSection('Mise en route', sousTitre: '$faites étape(s) sur ${etapesMiseEnRoute.length}. Le logiciel est déjà utilisable ; ces réglages l’adaptent à la structure.'),
          const SizedBox(height: 8),
          for (final x in etapesMiseEnRoute)
            () {
              final fait = b.param('mise_en_route_${x.cle}', '0') == '1';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(fait ? Icons.check_circle : x.icone, color: fait ? Couleurs.hausse : Couleurs.primaire),
                title: Text(x.titre, style: TextStyle(fontWeight: FontWeight.w600, decoration: fait ? TextDecoration.lineThrough : null)),
                subtitle: Text(x.detail),
                onTap: () => x.ouvrir(context),
                trailing: TextButton(
                  onPressed: () {
                    b.transaction(() => b.definirParam('mise_en_route_${x.cle}', fait ? '0' : '1'));
                    etat.rafraichir();
                  },
                  child: Text(fait ? 'À refaire' : 'Fait'),
                ),
              );
            }(),
        ]),
      ),
    );
  }
}
