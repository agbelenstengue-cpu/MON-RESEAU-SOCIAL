/// Outils du comptable : saisie d'écritures (opérations diverses, soldes
/// d'ouverture), clôture d'exercice, rapprochement bancaire, lettrage.
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../modules/comptabilite/comptabilite.dart';
import '../../noyau/outils.dart';
import '../etat_app.dart';
import '../widgets/commun.dart';
import '../widgets/formulaire.dart';

class SaisieEcriture extends StatefulWidget {
  final String entite;
  const SaisieEcriture({super.key, required this.entite});
  @override
  State<SaisieEcriture> createState() => _SaisieEcritureState();
}

class _LigneUi {
  String? compte;
  final debit = TextEditingController();
  final credit = TextEditingController();
}

class _SaisieEcritureState extends State<SaisieEcriture> {
  String _journal = 'OD';
  final _libelle = TextEditingController();
  final _lignes = [_LigneUi(), _LigneUi()];

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    if (etat.session!.role != 'comptable') {
      return const EtatVide('La saisie manuelle d’écritures est réservée au comptable.', icone: Icons.lock_outline);
    }
    final comptes = b.lignes('SELECT numero, libelle FROM comptes WHERE entite=? AND actif=1 ORDER BY numero', [widget.entite]);
    final journaux = b.lignes('SELECT code, libelle FROM journaux WHERE entite=? ORDER BY code', [widget.entite]);
    int somme(TextEditingController Function(_LigneUi) f) => _lignes.fold<int>(0, (t, l) => t + (int.tryParse(f(l).text) ?? 0));
    final d = somme((l) => l.debit), c = somme((l) => l.credit);
    final annee = b.maintenant.year - 1;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Carte(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Saisie d’une écriture', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Text('Choisissez le journal AN pour saisir les soldes d’ouverture (situation de départ : banque, caisses, créances, dettes, fonds propres).',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                initialValue: _journal,
                decoration: const InputDecoration(labelText: 'Journal', isDense: true),
                items: [for (final j in journaux) DropdownMenuItem(value: j['code'] as String, child: Text('${j['code']} ${j['libelle']}'))],
                onChanged: (v) => setState(() => _journal = v!),
              ),
            ),
            SizedBox(width: 420, child: TextField(controller: _libelle, decoration: const InputDecoration(labelText: 'Libellé', isDense: true))),
          ]),
          const SizedBox(height: 12),
          for (final l in _lignes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 380,
                  child: DropdownButtonFormField<String>(
                    initialValue: l.compte,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Compte', isDense: true),
                    items: [for (final x in comptes) DropdownMenuItem(value: x['numero'] as String, child: Text('${x['numero']} ${x['libelle']}', overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => l.compte = v),
                  ),
                ),
                for (final (ctrl, lib) in [(l.debit, 'Débit'), (l.credit, 'Crédit')])
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(labelText: lib, isDense: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                IconButton(
                  tooltip: 'Retirer la ligne',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _lignes.length <= 2 ? null : () => setState(() => _lignes.remove(l)),
                ),
              ]),
            ),
          Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            TextButton.icon(onPressed: () => setState(() => _lignes.add(_LigneUi())), icon: const Icon(Icons.add), label: const Text('Ajouter une ligne')),
            Text('Total débit ${fcfa(d)} · total crédit ${fcfa(c)}', style: TextStyle(fontWeight: FontWeight.bold, color: d == c ? null : Colors.red.shade800)),
          ]),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final ok = reussir(
                  context,
                  () => Comptabilite.saisir(etat.session!, entite: widget.entite, journal: _journal, libelle: _libelle.text, lignes: [
                        for (final l in _lignes)
                          if (l.compte != null)
                            LigneSaisie(l.compte!, debit: int.tryParse(l.debit.text) ?? 0, credit: int.tryParse(l.credit.text) ?? 0)
                      ]),
                  succes: 'Écriture enregistrée.');
              if (ok) {
                setState(() {
                  _libelle.clear();
                  _lignes
                    ..clear()
                    ..addAll([_LigneUi(), _LigneUi()]);
                });
              }
            },
            child: const Text('Enregistrer l’écriture'),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Carte(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Clôture de l'exercice", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Text('Solde les comptes de charges et de produits vers le résultat, puis verrouille l’année.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              if (await confirmer(context, "Clôturer l'exercice $annee de l'entité ${widget.entite} ? Plus aucune saisie ne sera possible sur cette année.") &&
                  context.mounted) {
                reussir(context, () => Comptabilite.cloturerExercice(etat.session!, entite: widget.entite, annee: annee), succes: 'Exercice clôturé.');
              }
            },
            child: Text("Clôturer l'exercice $annee"),
          ),
        ]),
      ),
    ]);
  }
}

class Rapprochement extends StatefulWidget {
  final String entite;
  const Rapprochement({super.key, required this.entite});
  @override
  State<Rapprochement> createState() => _RapprochementState();
}

class _RapprochementState extends State<Rapprochement> {
  String? _treso;
  final Set<String> _coches = {};

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final tresos = b.lignes("SELECT id, libelle FROM tresoreries WHERE entite=? AND type<>'caisse' AND actif=1 ORDER BY id", [widget.entite]);
    if (tresos.isEmpty) return const EtatVide('Aucun compte bancaire.');
    _treso ??= tresos.first['id'] as String;
    final mvts = Comptabilite.mouvementsAvecCle(b, _treso!).where((m) => m['pointe'] != true).toList();
    final releve = b.ligne('SELECT * FROM releves_bancaires WHERE tresorerie=? ORDER BY date DESC LIMIT 1', [_treso]);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 300,
          child: DropdownButtonFormField<String>(
            initialValue: _treso,
            decoration: const InputDecoration(labelText: 'Compte', isDense: true),
            items: [for (final t in tresos) DropdownMenuItem(value: t['id'] as String, child: Text(t['libelle'] as String))],
            onChanged: (v) => setState(() {
              _treso = v;
              _coches.clear();
            }),
          ),
        ),
        OutlinedButton(
          onPressed: () => formulaire(context, 'Relevé bancaire', [
            Champ('date', 'Date du relevé (JJ/MM/AAAA)', initial: dateFr(b.maintenant)),
            const Champ('solde', 'Solde du relevé (FCFA)', nombre: true),
            const Champ('reference', 'Référence du relevé'),
          ], (c, v) => reussir(c, () => Comptabilite.saisirReleveBancaire(etat.session!,
              tresorerie: _treso!, date: isoDepuisFr(v['date']!), solde: int.tryParse(v['solde']!) ?? 0, reference: v['reference']!), succes: 'Relevé enregistré.')),
          child: const Text('Saisir le solde du relevé'),
        ),
        if (releve != null) Text('Dernier relevé : ${fcfa(releve['solde'] as int)} au ${dateFr(depuisIso(releve['date'] as String))}'),
      ]),
      const SizedBox(height: 12),
      Text('Cochez les mouvements présents sur le relevé (${mvts.length} non pointés).'),
      Card(
        child: Column(children: [
          for (final m in mvts)
            CheckboxListTile(
              dense: true,
              value: _coches.contains(m['cle']),
              onChanged: (v) => setState(() => v! ? _coches.add(m['cle'] as String) : _coches.remove(m['cle'])),
              title: Text('${dateFr(depuisIso(m['date'] as String))} · ${m['libelle']}'),
              subtitle: Text('${m['piece'] ?? ''}${m['reference'] != null ? ' · réf. ${m['reference']}' : ''}'),
              secondary: Text(fcfa(m['montant'] as int)),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _coches.isEmpty
            ? null
            : () {
                if (reussir(context, () => Comptabilite.pointer(etat.session!, entite: widget.entite, mouvements: _coches.toList(), releve: releve?['uuid_op'] as String?),
                    succes: 'Mouvements pointés.')) {
                  setState(_coches.clear);
                }
              },
        child: Text('Pointer ${_coches.length} mouvement(s)'),
      ),
    ]);
  }
}

class Lettrage extends StatelessWidget {
  final String entite;
  const Lettrage({super.key, required this.entite});

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    // Tiers dont des lignes non lettrées se compensent (solde nul).
    final tiers = b.lignes(
        "SELECT x.compte, x.tiers, SUM(x.debit - x.credit) AS solde, COUNT(*) AS n FROM (SELECT l.*, e.uuid_op || ':' || "
        "ROW_NUMBER() OVER (PARTITION BY e.uuid_op ORDER BY l.id) AS cle FROM lignes_ecriture l JOIN ecritures e ON e.id=l.ecriture "
        "WHERE e.entite=? AND l.tiers IS NOT NULL) x LEFT JOIN lettrages t ON t.ligne=x.cle WHERE t.ligne IS NULL "
        "GROUP BY x.compte, x.tiers HAVING n >= 2 ORDER BY solde",
        [entite]);
    String nom(String id) =>
        (b.valeur("SELECT nom || ' ' || prenoms FROM patients WHERE id=?", [id]) ?? b.valeur('SELECT nom FROM fournisseurs WHERE id=?', [id]) ?? id) as String;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Un tiers dont les factures et les règlements non lettrés se compensent peut être lettré en un clic.', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      Card(
        child: Column(children: [
          for (final t in tiers)
            ListTile(
              title: Text('${t['compte']} · ${nom(t['tiers'] as String)}'),
              subtitle: Text('${t['n']} lignes non lettrées · solde ${fcfa(t['solde'] as int)}'),
              trailing: t['solde'] == 0
                  ? FilledButton(
                      onPressed: () => reussir(
                          context,
                          () => Comptabilite.lettrer(etat.session!, entite: entite, compte: t['compte'] as String, tiers: t['tiers'] as String, lignes: [
                                for (final l in Comptabilite.lignesTiers(b, entite, t['compte'] as String, t['tiers'] as String))
                                  if (l['code'] == null) l['cle'] as String
                              ]),
                          succes: 'Lettrage effectué.'),
                      child: const Text('Lettrer'))
                  : null,
            ),
        ]),
      ),
    ]);
  }
}
