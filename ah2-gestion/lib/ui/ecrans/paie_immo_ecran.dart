/// Personnel et paie ; immobilisations.
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/immobilisations/immobilisations.dart';
import '../../modules/paie/paie.dart';
import '../../modules/tresorerie/tresorerie.dart';
import '../../noyau/outils.dart';
import '../../pdf/documents.dart';
import '../../rapports/etats_phase3.dart';
import '../../rapports/modele.dart';
import '../etat_app.dart';
import '../widgets/commun.dart';
import '../widgets/formulaire.dart';
import '../widgets/pdf_ui.dart';

const _entites = [('CS', 'Centre de santé'), ('ONG', 'ONG')];

class EcranPaie extends StatefulWidget {
  const EcranPaie({super.key});
  @override
  State<EcranPaie> createState() => _EcranPaieState();
}

class _EcranPaieState extends State<EcranPaie> {
  String _entite = 'CS';
  late String _periode;

  @override
  void initState() {
    super.initState();
    _periode = dateIso(Etat.lire(context).base!.maintenant).substring(0, 7);
  }

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final ok = s.peut('paie', 'creer');
    final employes = b.lignes('SELECT * FROM employes WHERE entite=? ORDER BY actif DESC, nom', [_entite]);
    final totaux = totauxPaie(b, _entite, _periode);
    final calculee = b.valeur('SELECT 1 FROM bulletins b JOIN employes e ON e.id=b.employe WHERE e.entite=? AND b.periode=? AND b.annule=0', [_entite, _periode]) != null;
    return PageContenu(enfants: [
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ChoixPastilles<String>(options: _entites, valeur: _entite, onChanged: (v) => setState(() => _entite = v)),
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text('Mois : ${_periode.substring(5)}/${_periode.substring(0, 4)}'),
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: depuisIso('$_periode-01'), firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (d != null) setState(() => _periode = dateIso(d).substring(0, 7));
          },
        ),
      ]),
      const SizedBox(height: 16),
      Carte(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Paie de ${_periode.substring(5)}/${_periode.substring(0, 4)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text(calculee
              ? 'Brut ${fcfa(totaux['brut']!)} · net ${fcfa(totaux['net']!)} · charges patronales ${fcfa(totaux['patronales']!)} · reste à payer ${fcfa(totaux['reste_a_payer']!)}'
              : 'Paie non encore calculée.'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (ok && !calculee)
              FilledButton(
                onPressed: () => reussir(context, () => Paie.calculer(s, entite: _entite, periode: _periode), succes: 'Paie calculée et comptabilisée.'),
                child: const Text('Calculer la paie du mois'),
              ),
            if (ok && calculee && totaux['reste_a_payer']! > 0)
              FilledButton(
                onPressed: () => formulaire(context, 'Paiement des salaires', [
                  Champ('mode', 'Mode de paiement', initial: Modes.virement, choix: [for (final m in Modes.encaissables) (m, Modes.libelles[m]!)]),
                  const Champ('reference', 'Référence (ordre de virement)'),
                ], (c, v) => reussir(c, () => Paie.payer(s, entite: _entite, periode: _periode, mode: v['mode']!, reference: v['reference']!.isEmpty ? null : v['reference']),
                    succes: 'Salaires payés.')),
                child: const Text('Payer les salaires'),
              ),
            if (calculee)
              OutlinedButton(
                onPressed: () => afficherPdf(context, () => Documents.rapport(b, EtatsPaie.livre(b, _entite, Periode.mois('$_periode-01'))), 'Livre de paie'),
                child: const Text('Livre de paie'),
              ),
            if (calculee)
              OutlinedButton(
                onPressed: () => afficherPdf(context, () => Documents.rapport(b, EtatsPaie.declaration(b, _entite, _periode, organisme: 'CNPS')), 'Déclaration CNPS'),
                child: const Text('Déclaration CNPS'),
              ),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        const Expanded(child: TitreSection('Employés')),
        if (ok) FilledButton.icon(onPressed: () => _employe(context, null), icon: const Icon(Icons.person_add_alt), label: const Text('Ajouter')),
      ]),
      const SizedBox(height: 8),
      if (employes.isEmpty) const EtatVide('Aucun employé.'),
      Card(
        child: Column(children: [
          for (final e in employes)
            ListTile(
              title: Text('${e['nom']}${e['actif'] == 0 ? ' (sorti)' : ''}'),
              subtitle: Text('${e['matricule']} · ${e['poste']} · ${e['statut'] == 'salarie' ? 'salarié' : 'bénévole indemnisé'} · base ${fcfa(e['salaire_base'] as int)}'
                  '${Paie.avancesEnCours(b, e['id'] as String) > 0 ? ' · avance ${fcfa(Paie.avancesEnCours(b, e['id'] as String))}' : ''}'),
              trailing: Wrap(children: [
                if (bulletinExiste(b, e['id'] as String, _periode))
                  IconButton(
                    tooltip: 'Bulletin',
                    icon: const Icon(Icons.receipt_long_outlined),
                    onPressed: () => afficherPdf(context, () => Documents.rapport(b, EtatsPaie.bulletin(b, e['id'] as String, _periode)), 'Bulletin ${e['nom']}'),
                  ),
                if (ok) ...[
                  IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit_outlined), onPressed: () => _employe(context, e)),
                  IconButton(
                    tooltip: 'Avance sur salaire',
                    icon: const Icon(Icons.payments_outlined),
                    onPressed: () => formulaire(context, 'Avance à ${e['nom']}', [
                      const Champ('montant', 'Montant (FCFA)', nombre: true),
                      Champ('mode', 'Mode', choix: [for (final m in Modes.encaissables) (m, Modes.libelles[m]!)]),
                    ], (c, v) => reussir(c, () => Paie.avance(s, employe: e['id'] as String, montant: int.tryParse(v['montant']!) ?? 0, mode: v['mode']!),
                        succes: 'Avance enregistrée ; elle sera déduite à la prochaine paie.')),
                  ),
                  IconButton(
                    tooltip: 'Congé',
                    icon: const Icon(Icons.beach_access_outlined),
                    onPressed: () => formulaire(context, 'Congé de ${e['nom']}', const [
                      Champ('debut', 'Début (JJ/MM/AAAA)'),
                      Champ('fin', 'Fin (JJ/MM/AAAA)'),
                      Champ('motif', 'Motif'),
                    ], (c, v) => reussir(c, () => Paie.conge(s, employe: e['id'] as String, debut: isoDepuisFr(v['debut']!), fin: isoDepuisFr(v['fin']!), motif: v['motif']!),
                        succes: 'Congé enregistré.')),
                  ),
                ],
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      const TitreSection('Rubriques de cotisations', sousTitre: 'taux datés, à valider avec la législation en vigueur'),
      const SizedBox(height: 8),
      Card(
        child: Column(children: [
          for (final r in Paie.rubriques(b, _periode))
            ListTile(
              dense: true,
              title: Text('${r['libelle']}'),
              subtitle: Text('${r['nature'] == 'retenue_salariale' ? 'Retenue salariale' : 'Charge patronale'} · ${r['organisme']} · depuis le ${dateFr(depuisIso(r['depuis'] as String))}'
                  '${(r['plafond'] as int) > 0 ? ' · plafond ${fcfa(r['plafond'] as int)}' : ''}'),
              trailing: TextButton(
                onPressed: !(etat.estCentral && ok)
                    ? null
                    : () => formulaire(context, '${r['libelle']}', [
                          Champ('taux', 'Taux en pour dix mille (420 = 4,20 %)', initial: '${r['taux']}', nombre: true),
                          Champ('plafond', 'Plafond de la base (0 = aucun)', initial: '${r['plafond']}', nombre: true),
                          Champ('depuis', 'Applicable à partir du (JJ/MM/AAAA)', initial: dateFr(depuisIso('$_periode-01'))),
                        ], (c, v) => reussir(c, () => Paie.enregistrerRubrique(s,
                            code: r['code'] as String, libelle: r['libelle'] as String, nature: r['nature'] as String, organisme: r['organisme'] as String,
                            taux: int.tryParse(v['taux']!) ?? 0, plafond: int.tryParse(v['plafond']!) ?? 0, depuis: isoDepuisFr(v['depuis']!)), succes: 'Taux enregistré.')),
                child: Text('${((r['taux'] as int) / 100).toStringAsFixed(2).replaceAll('.', ',')} %'),
              ),
            ),
        ]),
      ),
    ]);
  }

  void _employe(BuildContext context, Map<String, Object?>? e) {
    final b = Etat.lire(context).base!;
    formulaire(context, e == null ? 'Nouvel employé' : 'Dossier de ${e['nom']}', [
      Champ('nom', 'Nom et prénoms', initial: (e?['nom'] ?? '') as String),
      Champ('poste', 'Poste', initial: (e?['poste'] ?? '') as String),
      Champ('activite', 'Service', initial: (e?['activite'] ?? '') as String, choix: [
        ('', 'Aucun'),
        for (final a in b.lignes('SELECT code, libelle FROM activites WHERE entite=? AND actif=1', [_entite])) (a['code'] as String, a['libelle'] as String)
      ]),
      Champ('statut', 'Statut', initial: (e?['statut'] ?? 'salarie') as String, choix: const [('salarie', 'Salarié'), ('benevole', 'Bénévole indemnisé')]),
      Champ('embauche', "Date d'embauche (JJ/MM/AAAA)", initial: e?['embauche'] == null ? '' : dateFr(depuisIso(e!['embauche'] as String))),
      Champ('contrat', 'Contrat (CDI, CDD…)', initial: (e?['contrat'] ?? '') as String),
      Champ('base', 'Salaire de base (FCFA)', initial: '${e?['salaire_base'] ?? ''}', nombre: true),
      Champ('primes', 'Primes et indemnités fixes (FCFA)', initial: '${e?['primes'] ?? 0}', nombre: true),
      Champ('cnps', 'N° CNPS', initial: (e?['cnps'] ?? '') as String),
      Champ('paiement', 'Banque ou mobile money (pour le paiement)', initial: (e?['paiement'] ?? '') as String),
      Champ('actif', 'Situation', initial: '${e?['actif'] ?? 1}', choix: const [('1', 'En poste'), ('0', 'Sorti des effectifs')]),
    ], (c, v) => reussir(c, () => Paie.enregistrerEmploye(Etat.lire(c).session!,
        id: e?['id'] as String?, nom: v['nom']!, entite: _entite, poste: v['poste']!, activite: v['activite']!.isEmpty ? null : v['activite'],
        embauche: v['embauche']!.isEmpty ? null : isoDepuisFr(v['embauche']!), contrat: v['contrat']!, statut: v['statut']!,
        salaireBase: int.tryParse(v['base']!) ?? 0, primes: int.tryParse(v['primes']!) ?? 0, cnps: v['cnps']!, paiement: v['paiement']!,
        actif: v['actif'] == '1'), succes: 'Dossier enregistré.'));
  }
}

class EcranImmobilisations extends StatefulWidget {
  const EcranImmobilisations({super.key});
  @override
  State<EcranImmobilisations> createState() => _EcranImmobilisationsState();
}

class _EcranImmobilisationsState extends State<EcranImmobilisations> {
  String _entite = 'CS';

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    final ok = s.peut('immobilisations', 'creer');
    final aujourdhui = dateIso(b.maintenant);
    final liste = b.lignes(
        'SELECT i.*, c.libelle AS cat FROM immobilisations i JOIN categories_immobilisations c ON c.code=i.categorie WHERE i.entite=? ORDER BY i.date_sortie IS NOT NULL, i.numero',
        [_entite]);
    return PageContenu(enfants: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ChoixPastilles<String>(options: _entites, valeur: _entite, onChanged: (v) => setState(() => _entite = v)),
        if (ok) FilledButton.icon(onPressed: () => _acquerir(context), icon: const Icon(Icons.add), label: const Text('Nouvelle acquisition')),
        if (ok)
          OutlinedButton(
            onPressed: () {
              final op = executer(context, () => Immobilisations.amortir(s, entite: _entite, periode: aujourdhui.substring(0, 7)));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(op == null ? 'Aucune dotation à passer pour ce mois.' : 'Amortissements du mois comptabilisés.')));
              }
            },
            child: const Text('Passer les amortissements du mois'),
          ),
        OutlinedButton(
          onPressed: () => afficherPdf(context, () => Documents.rapport(b, EtatsImmobilisations.registre(b, _entite, aujourdhui)), 'Registre des immobilisations'),
          child: const Text('Registre (PDF)'),
        ),
        OutlinedButton(
          onPressed: () => afficherPdf(context, () => Documents.rapport(b, EtatsImmobilisations.ficheInventaire(b, _entite)), 'Inventaire des biens'),
          child: const Text("Fiche d'inventaire"),
        ),
      ]),
      const SizedBox(height: 16),
      if (liste.isEmpty) const EtatVide('Aucune immobilisation enregistrée.'),
      Card(
        child: Column(children: [
          for (final i in liste)
            ListTile(
              title: Text('${i['designation']}${i['date_sortie'] != null ? ' (sorti : ${i['motif_sortie']})' : ''}'),
              subtitle: Text('${i['numero']} · ${i['cat']} · ${i['localisation']} · acquis le ${dateFr(depuisIso(i['date_acquisition'] as String))}'),
              trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fcfa(i['valeur'] as int), style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Valeur nette ${fcfa((i['valeur'] as int) - (i['amorti'] as int))}', style: const TextStyle(fontSize: 12)),
                ]),
                if (ok && i['date_sortie'] == null)
                  IconButton(
                    tooltip: 'Sortie (cession, rebut, perte)',
                    icon: const Icon(Icons.logout),
                    onPressed: () => formulaire(context, 'Sortie : ${i['designation']}', [
                      const Champ('motif', 'Motif', choix: [('cession', 'Cession (vente)'), ('rebut', 'Mise au rebut'), ('perte', 'Perte ou vol')]),
                      const Champ('prix', 'Prix de cession (FCFA)', nombre: true, initial: '0'),
                    ], (c, v) => reussir(c, () => Immobilisations.sortir(s, i['id'] as String, motif: v['motif']!, prixCession: int.tryParse(v['prix']!) ?? 0),
                        succes: 'Sortie enregistrée.')),
                  ),
              ]),
            ),
        ]),
      ),
    ]);
  }

  void _acquerir(BuildContext context) {
    final b = Etat.lire(context).base!;
    formulaire(context, 'Nouvelle acquisition', [
      const Champ('designation', 'Désignation'),
      Champ('categorie', 'Catégorie', choix: [
        for (final c in b.lignes('SELECT * FROM categories_immobilisations ORDER BY libelle')) (c['code'] as String, '${c['libelle']} (${c['duree_mois']} mois)')
      ]),
      const Champ('valeur', "Valeur d'acquisition (FCFA)", nombre: true),
      const Champ('origine', 'Origine', choix: [('achat', 'Achat'), ('don', 'Don')]),
      Champ('paiement', 'Paiement (achat)', choix: [('', 'À crédit (dette fournisseur)'), for (final m in Modes.encaissables) (m, 'Payé : ${Modes.libelles[m]}')]),
      const Champ('localisation', 'Localisation'),
      Champ('activite', 'Service affecté', choix: [
        ('', 'Aucun'),
        for (final a in b.lignes('SELECT code, libelle FROM activites WHERE entite=? AND actif=1', [_entite])) (a['code'] as String, a['libelle'] as String)
      ]),
    ], (c, v) => reussir(c, () => Immobilisations.acquerir(Etat.lire(c).session!,
        entite: _entite, designation: v['designation']!, categorie: v['categorie']!, valeur: int.tryParse(v['valeur']!) ?? 0, origine: v['origine']!,
        mode: v['paiement']!.isEmpty ? null : v['paiement'], localisation: v['localisation']!, activite: v['activite']!.isEmpty ? null : v['activite']),
        succes: 'Immobilisation enregistrée.'));
  }
}
