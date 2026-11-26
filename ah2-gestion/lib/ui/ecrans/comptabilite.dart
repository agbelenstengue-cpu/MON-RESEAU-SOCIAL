/// Comptabilité (deux entités) : écritures, balance, clôtures, anomalies de
/// synchronisation, journal d'audit.
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/cloture/cloture.dart';
import '../../modules/comptabilite/moteur.dart';
import '../../noyau/audit.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';

class EcranComptabilite extends StatefulWidget {
  const EcranComptabilite({super.key});
  @override
  State<EcranComptabilite> createState() => _EcranComptabiliteState();
}

class _EcranComptabiliteState extends State<EcranComptabilite> {
  String _entite = 'CS';

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final s = etat.session!;
    final onglets = [
      ('Écritures', _ecritures),
      ('Balance', _balance),
      ('Clôtures', _clotures),
      ('Anomalies', _anomalies),
      if (s.peut('audit', 'voir')) ('Audit', _audit),
    ];
    return DefaultTabController(
      length: onglets.length,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(child: ChoixPastilles<String>(
              options: const [('CS', 'Centre de santé · SYSCOHADA'), ('ONG', 'ONG · SYCEBNL')],
              valeur: _entite,
              onChanged: (v) => setState(() => _entite = v),
            )),
          ]),
        ),
        TabBar(isScrollable: true, tabs: [for (final o in onglets) Tab(text: o.$1)]),
        Expanded(child: TabBarView(children: [for (final o in onglets) o.$2(context)])),
      ]),
    );
  }

  Widget _ecritures(BuildContext context) {
    final b = Etat.de(context).base!;
    final ecr = b.lignes('SELECT * FROM ecritures WHERE entite=? ORDER BY id DESC LIMIT 200', [_entite]);
    final deseq = Moteur.ecrituresDesequilibrees(b);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Pastille(deseq.isEmpty ? 'Toutes les écritures sont équilibrées' : '${deseq.length} écriture(s) déséquilibrée(s)',
          couleur: deseq.isEmpty ? Couleurs.hausse : Couleurs.baisse),
      const SizedBox(height: 8),
      for (final e in ecr)
        Card(
          child: ExpansionTile(
            title: Text('${e['journal']} · ${dateFr(depuisIso(e['date'] as String))} · ${e['libelle']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${e['piece'] ?? ''} · ${e['appareil']}${e['contre_passation'] == 1 ? ' · contre-passation' : ''}'),
            children: [
              for (final l in b.lignes(
                  'SELECT l.*, c.libelle FROM lignes_ecriture l LEFT JOIN comptes c ON c.entite=? AND c.numero=l.compte WHERE ecriture=?',
                  [_entite, e['id']]))
                ListTile(
                  dense: true,
                  title: Text('${l['compte']} ${l['libelle'] ?? ''}'),
                  subtitle: Text([if (l['activite'] != null) 'activité ${l['activite']}', if (l['tiers'] != null) 'tiers'].join(' · ')),
                  trailing: Text((l['debit'] as int) > 0 ? 'D ${fcfa(l['debit'] as int)}' : 'C ${fcfa(l['credit'] as int)}'),
                ),
            ],
          ),
        ),
    ]);
  }

  Widget _balance(BuildContext context) {
    final b = Etat.de(context).base!;
    final j = dateIso(b.maintenant);
    final lignes = Moteur.balance(b, _entite, du: '${j.substring(0, 4)}-01-01', au: j);
    final td = lignes.fold<int>(0, (t, l) => t + (l['debit'] as int));
    final tc = lignes.fold<int>(0, (t, l) => t + (l['credit'] as int));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Balance générale du 01/01/${j.substring(0, 4)} au ${dateFr(b.maintenant)}', style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Card(
        child: Column(children: [
          for (final l in lignes)
            ListTile(
              dense: true,
              title: Text('${l['compte']} ${l['libelle'] ?? ''}'),
              trailing: Text('D ${fcfa(l['debit'] as int, unite: false)} · C ${fcfa(l['credit'] as int, unite: false)}'),
            ),
          ListTile(
            title: const Text('Totaux', style: TextStyle(fontWeight: FontWeight.w800)),
            trailing: Text('D ${fcfa(td, unite: false)} · C ${fcfa(tc, unite: false)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    ]);
  }

  Widget _clotures(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final hier = ajouterJours(dateIso(b.maintenant), -1);
    final non = Cloture.appareilsNonSynchronises(b, hier);
    final demandes = b.lignes(
        "SELECT * FROM operations WHERE type='reouverture_demande' AND entite=? AND uuid NOT IN "
        "(SELECT json_extract(donnees,'\$.demande') FROM operations WHERE type='reouverture_jour') ORDER BY seq DESC",
        [_entite]);
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (etat.estCentral && s.peut('cloture', 'creer'))
        Carte(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Clôture de la journée du ${dateFr(depuisIso(hier))}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(non.isEmpty ? 'Tous les appareils sont synchronisés.' : 'Appareils à synchroniser d’abord : ${non.join(', ')}'),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: Operations.estCloturee(b, _entite, hier)
                  ? null
                  : () => executer(context, () => Cloture.cloturer(s, entite: _entite, date: hier), succes: 'Journée clôturée.'),
              child: Text(Operations.estCloturee(b, _entite, hier) ? 'Déjà clôturée' : 'Clôturer'),
            ),
          ]),
        ),
      const SizedBox(height: 12),
      if (demandes.isNotEmpty) ...[
        const TitreSection('Demandes de réouverture'),
        for (final d in demandes)
          Card(
            child: ListTile(
              title: Text('Demande du ${dateFr(DateTime.parse(d['horodatage'] as String))}'),
              subtitle: Text(d['donnees'] as String),
              trailing: s.role == 'direction'
                  ? FilledButton(
                      onPressed: () => executer(context, () => Cloture.approuverReouverture(s, d['uuid'] as String), succes: 'Journée rouverte.'),
                      child: const Text('Approuver'))
                  : null,
            ),
          ),
      ],
      const TitreSection('Journées clôturées'),
      for (final c in b.lignes('SELECT * FROM clotures WHERE entite=? ORDER BY date DESC LIMIT 60', [_entite]))
        ListTile(
          dense: true,
          title: Text(dateFr(depuisIso(c['date'] as String))),
          trailing: c['cloture'] == 1
              ? (s.role == 'comptable'
                  ? TextButton(onPressed: () => _demander(context, c['date'] as String), child: const Text('Demander la réouverture'))
                  : const Pastille('clôturée', couleur: Couleurs.primaire))
              : const Pastille('rouverte', couleur: Couleurs.stable),
        ),
    ]);
  }

  void _demander(BuildContext context, String date) {
    final m = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Réouverture du ${dateFr(depuisIso(date))}'),
        content: TextField(controller: m, decoration: const InputDecoration(labelText: 'Motif (tracé)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (executer(c, () => Cloture.demanderReouverture(Etat.lire(c).session!, entite: _entite, date: date, motif: m.text),
                      succes: 'Demande envoyée à la direction.') !=
                  null) {
                Navigator.pop(c);
              }
            },
            child: const Text('Demander'),
          ),
        ],
      ),
    );
  }

  Widget _anomalies(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final l = b.lignes('SELECT * FROM anomalies_sync ORDER BY statut, id DESC LIMIT 200');
    if (l.isEmpty) return const EtatVide('Aucune anomalie de synchronisation.', icone: Icons.check_circle_outline);
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final a in l)
        Card(
          child: ListTile(
            leading: Icon(a['statut'] == 'a_traiter' ? Icons.error_outline : Icons.check, color: a['statut'] == 'a_traiter' ? Couleurs.baisse : Couleurs.hausse),
            title: Text(a['type'] as String),
            subtitle: Text('${a['detail']}\n${dateFr(DateTime.parse(a['horodatage'] as String))}'),
            isThreeLine: true,
            trailing: a['statut'] == 'a_traiter' && etat.session!.peut('anomalies', 'valider')
                ? TextButton(
                    onPressed: () => executer(context, () {
                      b.transaction(() {
                        b.exec("UPDATE anomalies_sync SET statut='traitee', traitee_par=? WHERE id=?", [etat.session!.utilisateur, a['id']]);
                        Audit.tracer(b, utilisateur: etat.session!.utilisateur, action: 'traitement', objet: 'anomalie:${a['id']}');
                      });
                    }, succes: 'Anomalie marquée traitée.'),
                    child: const Text('Traitée'))
                : null,
          ),
        ),
    ]);
  }

  Widget _audit(BuildContext context) {
    final b = Etat.de(context).base!;
    final rompu = Audit.verifier(b);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Pastille(rompu == null ? 'Chaîne d’audit intacte' : 'Altération détectée à la ligne $rompu', couleur: rompu == null ? Couleurs.hausse : Couleurs.baisse),
      const SizedBox(height: 8),
      for (final a in b.lignes('SELECT * FROM audit ORDER BY id DESC LIMIT 300'))
        ListTile(
          dense: true,
          title: Text('${a['action']} · ${a['objet']}', maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${a['horodatage']} · ${a['appareil']} · ${b.valeur('SELECT nom FROM utilisateurs WHERE id=?', [a['utilisateur']]) ?? a['utilisateur']}'),
        ),
    ]);
  }
}

