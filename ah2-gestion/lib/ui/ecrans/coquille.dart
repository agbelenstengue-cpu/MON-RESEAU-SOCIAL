/// Espace de travail : barre latérale sur PC, barre en bas sur téléphone,
/// bouton (+) d'actions rapides, recherche instantanée, état de synchronisation.
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/desintox/desintox.dart';
import '../../modules/patients/patients.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/logo.dart';
import '../widgets/pdf_ui.dart';
import '../widgets/formulaire.dart';
import 'assistants.dart';
import 'caisse.dart';
import 'comptabilite.dart';
import 'desintox.dart';
import 'depenses_ecran.dart';
import 'dons.dart';
import 'encaissement.dart';
import 'hospitalisation_ecran.dart';
import 'laboratoire.dart';
import 'mes_documents.dart';
import 'paie_immo_ecran.dart';
import 'parametrage_ecran.dart';
import 'patients.dart';
import 'rapports_ecran.dart';
import 'releves.dart';
import 'statistiques_ecran.dart';
import 'stocks_ecran.dart';
import 'synchro.dart';
import 'tableau_bord.dart';

class Destination {
  final String id;
  final String libelle;
  String get court => const {
        'accueil': 'Accueil',
        'encaissement': 'Encaisser',
        'laboratoire': 'Labo',
        'depenses': 'Dépenses',
        'patients': 'Patients',
        'desintox': 'Désintox',
        'caisse': 'Trésorerie',
        'stocks': 'Stocks',
        'hospitalisation': 'Hospit.',
        'releves': 'Relevés',
        'dons': 'Dons',
        'rapports': 'Rapports',
      }[id] ??
      libelle;
  final IconData icone;
  final bool Function(EtatApp) visible;
  final Widget Function() ecran;
  const Destination(this.id, this.libelle, this.icone, this.visible, this.ecran);
}

bool _peut(EtatApp e, String module, [String action = 'voir']) => e.session!.peut(module, action);

final destinations = <Destination>[
  Destination('accueil', 'Tableau de bord', Icons.space_dashboard_outlined, (e) => true, () => const EcranTableauBord()),
  Destination('encaissement', 'Encaissement', Icons.point_of_sale_outlined, (e) => _peut(e, 'actes', 'creer'), () => const EcranEncaissement()),
  Destination('laboratoire', 'Laboratoire', Icons.biotech_outlined, (e) => _peut(e, 'actes'), () => const EcranLaboratoire()),
  Destination('depenses', 'Dépenses et achats', Icons.receipt_long_outlined, (e) => _peut(e, 'depenses'), () => const EcranDepenses()),
  Destination('patients', 'Patients', Icons.people_alt_outlined, (e) => _peut(e, 'patients'), () => const EcranPatients()),
  Destination('desintox', 'Désintoxication', Icons.healing_outlined, (e) => _peut(e, 'desintox'), () => const EcranDesintox()),
  Destination('hospitalisation', 'Hospitalisation', Icons.bed_outlined, (e) => _peut(e, 'hospitalisation'), () => const EcranHospitalisation()),
  Destination('stocks', 'Pharmacies et stocks', Icons.inventory_2_outlined, (e) => _peut(e, 'stocks'), () => const EcranStocks()),
  Destination('caisse', 'Caisse et trésorerie', Icons.account_balance_wallet_outlined,
      (e) => _peut(e, 'caisse') || _peut(e, 'tresorerie'), () => const EcranCaisse()),
  Destination('rapports', 'Rapports et états', Icons.insert_chart_outlined, (e) => _peut(e, 'rapports'), () => const EcranRapports()),
  Destination('statistiques', 'Statistiques', Icons.show_chart, (e) => _peut(e, 'statistiques') || _peut(e, 'rapports'), () => const EcranStatistiques()),
  Destination('comptabilite', 'Comptabilité', Icons.menu_book_outlined, (e) => _peut(e, 'comptabilite'), () => const EcranComptabilite()),
  Destination('paie', 'Personnel et paie', Icons.badge_outlined, (e) => _peut(e, 'paie'), () => const EcranPaie()),
  Destination('immobilisations', 'Immobilisations', Icons.domain_outlined, (e) => _peut(e, 'immobilisations'), () => const EcranImmobilisations()),
  Destination('releves', 'Relevés journaliers', Icons.fact_check_outlined, (e) => _peut(e, 'releves'), () => const EcranReleves()),
  Destination('dons', 'Dons et subventions', Icons.volunteer_activism_outlined, (e) => _peut(e, 'dons'), () => const EcranDons()),
  Destination('documents', 'Mes documents', Icons.folder_outlined, (e) => true, () => const EcranMesDocuments()),
  Destination('parametrage', 'Paramétrage', Icons.tune_outlined,
      (e) => _peut(e, 'parametrage') || _peut(e, 'utilisateurs'), () => const EcranParametrage()),
  Destination('synchro', 'Synchronisation', Icons.sync, (e) => true, () => const EcranSynchro()),
];

/// Permet à un écran d'en ouvrir un autre (ex. tableau de bord vers désintox).
class Navigation extends InheritedWidget {
  final void Function(String id) ouvrir;
  const Navigation({super.key, required this.ouvrir, required super.child});
  static Navigation de(BuildContext c) => c.dependOnInheritedWidgetOfExactType<Navigation>()!;
  @override
  bool updateShouldNotify(Navigation old) => false;
}

class Coquille extends StatefulWidget {
  const Coquille({super.key});
  @override
  State<Coquille> createState() => _CoquilleState();
}

class _CoquilleState extends State<Coquille> {
  String _courant = 'accueil';

  void _ouvrir(String id) => setState(() => _courant = id);

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final visibles = destinations.where((d) => d.visible(etat)).toList();
    final dest = visibles.firstWhere((d) => d.id == _courant, orElse: () => visibles.first);
    final large = MediaQuery.sizeOf(context).width >= 900;
    final contenu = Navigation(
      ouvrir: _ouvrir,
      child: Column(children: [
        const BandeauReprise(),
        Expanded(child: Filigrane(child: KeyedSubtree(key: ValueKey(dest.id), child: dest.ecran()))),
      ]),
    );
    final s = etat.session!;
    final barre = AppBar(
      title: Text(dest.libelle, style: const TextStyle(fontWeight: FontWeight.w700)),
      actions: [
        IconButton(tooltip: 'Recherche', icon: const Icon(Icons.search), onPressed: () => _rechercher(context)),
        if (large && s.peut('rapports', 'voir'))
          IconButton(tooltip: 'Compte rendu du soir', icon: const Icon(Icons.summarize_outlined), onPressed: () => ouvrirCompteRendu(context)),
        if (s.peut('retroactif', 'creer'))
          IconButton(
            tooltip: 'Date de saisie (reprise des mois passés)',
            icon: Icon(Icons.edit_calendar_outlined, color: etat.dateSaisie != null ? Couleurs.stable : null),
            onPressed: () => choisirDateSaisie(context),
          ),
        _IndicateurSync(compact: !large),
        PopupMenuButton<String>(
          tooltip: 'Compte',
          icon: const Icon(Icons.account_circle_outlined),
          onSelected: (v) async {
            switch (v) {
              case 'clair':
                etat.changerTheme(ThemeMode.light);
              case 'sombre':
                etat.changerTheme(ThemeMode.dark);
              case 'texte+':
                etat.changerTailleTexte((etat.tailleTexte + 0.1).clamp(0.8, 1.6));
              case 'texte-':
                etat.changerTailleTexte((etat.tailleTexte - 0.1).clamp(0.8, 1.6));
              case 'quitter':
                etat.deconnecter();
              case 'demo':
                if (await confirmer(context,
                    'Quitter la démonstration ? Toutes les données fictives seront effacées et vous pourrez installer le logiciel pour la structure.')) {
                  etat.quitterDemonstration();
                }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(enabled: false, child: Text('${etat.session!.nom} · ${etat.base!.appareil}')),
            const PopupMenuItem(value: 'clair', child: Text('Mode clair')),
            const PopupMenuItem(value: 'sombre', child: Text('Mode sombre')),
            const PopupMenuItem(value: 'texte+', child: Text('Agrandir le texte')),
            const PopupMenuItem(value: 'texte-', child: Text('Réduire le texte')),
            if (etat.connexionRequise) const PopupMenuItem(value: 'quitter', child: Text('Se déconnecter')),
            if (etat.demonstration) const PopupMenuItem(value: 'demo', child: Text('Quitter la démonstration')),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
    final fab = const {'encaissement', 'laboratoire', 'documents'}.contains(dest.id)
        ? null
        : FloatingActionButton(
      tooltip: 'Actions rapides',
      onPressed: () => _actionsRapides(context, etat),
      child: const Icon(Icons.add),
    );
    if (large) {
      return Scaffold(
        floatingActionButton: fab,
        body: Row(children: [
          _BarreLaterale(visibles: visibles, courant: dest.id, ouvrir: _ouvrir),
          Expanded(child: Scaffold(appBar: barre, body: contenu)),
        ]),
      );
    }
    final principaux = visibles.take(4).toList();
    final indice = principaux.indexWhere((d) => d.id == dest.id);
    return Scaffold(
      appBar: barre,
      body: contenu,
      floatingActionButton: fab,
      bottomNavigationBar: NavigationBar(
        selectedIndex: indice < 0 ? principaux.length : indice,
        onDestinationSelected: (i) {
          if (i < principaux.length) {
            _ouvrir(principaux[i].id);
          } else {
            _plus(context, visibles.skip(4).toList());
          }
        },
        destinations: [
          for (final d in principaux) NavigationDestination(icon: Icon(d.icone), label: d.court),
          const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Plus'),
        ],
      ),
    );
  }

  void _plus(BuildContext context, List<Destination> autres) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            for (final d in autres)
              ListTile(
                leading: Icon(d.icone),
                title: Text(d.libelle),
                onTap: () {
                  Navigator.pop(c);
                  _ouvrir(d.id);
                },
              ),
          ]),
        ),
      );

  void _actionsRapides(BuildContext context, EtatApp etat) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) {
          ListTile tuile(IconData i, String t, VoidCallback f) => ListTile(
                leading: CircleAvatar(child: Icon(i)),
                title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(c);
                  f();
                },
              );
          final s = etat.session!;
          return SafeArea(
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (s.peut('actes', 'creer')) tuile(Icons.point_of_sale, 'Nouvel encaissement', () => _ouvrir('encaissement')),
              if (s.peut('actes', 'creer')) tuile(Icons.biotech_outlined, 'Nouvel examen de laboratoire', () => _ouvrir('laboratoire')),
              if (s.peut('patients', 'creer'))
                tuile(Icons.person_add_alt, 'Nouveau patient', () => nouveauPatient(context)),
              if (s.peut('desintox', 'creer'))
                tuile(Icons.payments_outlined, 'Nouveau versement en désintoxication', () => _ouvrir('desintox')),
              if (s.peut('depenses', 'creer')) tuile(Icons.receipt_long, 'Dépense ou achat', () => _ouvrir('depenses')),
              if (s.peut('stocks', 'creer')) tuile(Icons.local_drink_outlined, 'Servir les remèdes du jour', () => servirRemedes(context)),
              if (s.peut('rapports', 'voir')) tuile(Icons.summarize_outlined, 'Compte rendu du soir', () => ouvrirCompteRendu(context)),
            ])),
          );
        },
      );

  void _rechercher(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Recherche());
}

class _BarreLaterale extends StatelessWidget {
  final List<Destination> visibles;
  final String courant;
  final void Function(String) ouvrir;
  const _BarreLaterale({required this.visibles, required this.courant, required this.ouvrir});

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    return Container(
      width: 248,
      color: Couleurs.barreLaterale,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                child: const LogoStructure(taille: 40),
              ),
              const SizedBox(width: 10),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AH2 Gestion', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                Text('A Hand to Humanity', style: TextStyle(color: Color(0xFFA9C2BA), fontSize: 12)),
              ]),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final d in visibles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: d.id == courant ? const Color(0xFF1E4A40) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      leading: Icon(d.icone, color: d.id == courant ? Colors.white : const Color(0xFFD3E2DC), size: 20),
                      title: Text(d.libelle,
                          style: TextStyle(
                              color: d.id == courant ? Colors.white : const Color(0xFFD3E2DC),
                              fontWeight: d.id == courant ? FontWeight.w700 : FontWeight.w500)),
                      onTap: () => ouvrir(d.id),
                    ),
                  ),
                ),
            ]),
          ),
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF163A32), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Appareil ${etat.base!.appareil}${etat.estCentral ? ' · PC central' : ''}',
                  style: const TextStyle(color: Color(0xFFA9C2BA), fontSize: 12)),
              const SizedBox(height: 2),
              Text(etat.session!.nom, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Indicateur permanent : synchronisé, en attente (nombre), hors ligne depuis X heures.
class _IndicateurSync extends StatelessWidget {
  final bool compact;
  const _IndicateurSync({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    if (etat.estCentral) {
      final n = etat.base!.entier("SELECT COUNT(*) FROM appareils WHERE central=0 AND statut='autorise'");
      if (compact) {
        return const Tooltip(message: 'PC central', child: Padding(padding: EdgeInsets.all(8), child: Icon(Icons.dns_outlined, color: Couleurs.hausse)));
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Chip(
          avatar: const Icon(Icons.dns_outlined, size: 18, color: Couleurs.hausse),
          label: Text('PC central · $n appareil${n > 1 ? 's' : ''}'),
        ),
      );
    }
    final s = etat.etatSync!;
    final ok = s.enAttente == 0 && s.derniere != null && etat.base!.maintenant.difference(s.derniere!).inHours < 1;
    if (compact) {
      return IconButton(
        tooltip: s.libelle(etat.base!.maintenant),
        icon: Badge(
          isLabelVisible: s.enAttente > 0,
          label: Text('${s.enAttente}'),
          child: Icon(ok ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: ok ? Couleurs.hausse : Couleurs.stable),
        ),
        onPressed: () async {
          final m = await etat.synchroniser();
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ActionChip(
        avatar: etat.synchronisationEnCours
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(ok ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, size: 18, color: ok ? Couleurs.hausse : Couleurs.stable),
        label: Text(s.libelle(etat.base!.maintenant)),
        onPressed: () async {
          final m = await etat.synchroniser();
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
        },
      ),
    );
  }
}

/// Recherche instantanée : patient, reçu, donateur.
class _Recherche extends StatefulWidget {
  const _Recherche();
  @override
  State<_Recherche> createState() => _RechercheState();
}

class _RechercheState extends State<_Recherche> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final res = <Widget>[];
    if (_q.trim().length >= 2) {
      for (final p in Patients.rechercher(b, _q, limite: 8)) {
        res.add(ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(Patients.libelle(s, p)),
          subtitle: Text(p['numero_dossier'] as String),
          onTap: () {
            Navigator.pop(context);
            ouvrirFichePatient(context, p['id'] as String);
          },
        ));
      }
      for (final o in b.lignes('SELECT uuid, piece, type, horodatage FROM operations WHERE piece LIKE ? ORDER BY seq DESC LIMIT 8',
          ['%${_q.trim().toUpperCase()}%'])) {
        res.add(ListTile(
          leading: const Icon(Icons.receipt_outlined),
          title: Text(o['piece'] as String),
          subtitle: Text(o['type'] as String),
          onTap: () {
            Navigator.pop(context);
            afficherRecu(context, o['uuid'] as String);
          },
        ));
      }
      for (final d in b.lignes('SELECT * FROM donateurs WHERE UPPER(nom) LIKE ? LIMIT 5', ['%${_q.trim().toUpperCase()}%'])) {
        res.add(ListTile(leading: const Icon(Icons.volunteer_activism_outlined), title: Text(d['nom'] as String), subtitle: Text(d['type'] as String)));
      }
      for (final d in Desintox.listeTravail(b, recherche: _q).take(5)) {
        res.add(ListTile(
          leading: const Icon(Icons.healing_outlined),
          title: Text('Désintox ${d.dossier['numero']}'),
          subtitle: Text('Reste ${d.reste}'),
          onTap: () {
            Navigator.pop(context);
            ouvrirFicheDesintox(context, d.dossier['id'] as String);
          },
        ));
      }
    }
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Patient, reçu, produit, donateur…'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Flexible(
            child: res.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_q.length < 2 ? 'Tapez au moins 2 caractères.' : 'Aucun résultat.'),
                  )
                : ListView(shrinkWrap: true, children: res),
          ),
        ]),
      ),
    );
  }
}
