/// Encaissement (maquette « Encaissement ») : patient vers service vers actes  vers 
/// mode de paiement vers reçu. Trois gestes pour une opération courante.
library;

import 'package:material_ui/material_ui.dart';

import '../../modules/actes/actes.dart';
import '../../modules/facturation/facturation.dart';
import '../../modules/parametrage/parametrage.dart';
import '../../modules/patients/patients.dart';
import '../../modules/tresorerie/tresorerie.dart';
import '../../noyau/operations.dart';
import '../../noyau/outils.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';
import '../widgets/formulaire.dart';
import '../widgets/pdf_ui.dart';
import 'patients.dart';

class EcranEncaissement extends StatefulWidget {
  const EcranEncaissement({super.key});
  @override
  State<EcranEncaissement> createState() => _EcranEncaissementState();
}

class _EcranEncaissementState extends State<EcranEncaissement> {
  String? _patient;
  String? _service;
  final Set<String> _actes = {};
  String _mode = Modes.especes;
  String? _motifGratuite;
  final _reference = TextEditingController();
  final _organisme = TextEditingController();
  Operation? _fait;

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    if (_fait != null) return _confirmation(context, _fait!);
    final services = b
        .lignes("SELECT a.code, a.libelle FROM activites a WHERE a.service=1 AND a.actif=1 AND EXISTS "
            "(SELECT 1 FROM actes_catalogue c WHERE c.activite=a.code AND c.actif=1) ORDER BY a.code")
        .where((a) => s.role != 'agent' || s.activite == null || s.activite == a['code'])
        .toList();
    _service ??= services.isEmpty ? null : services.first['code'] as String;
    final aujourdhui = dateIso(b.maintenant);
    final catalogue = _service == null
        ? <Map<String, Object?>>[]
        : b.lignes('SELECT * FROM actes_catalogue WHERE activite=? AND actif=1 ORDER BY libelle', [_service]);
    var total = 0;
    for (final c in catalogue) {
      if (_actes.contains(c['code'])) total += Parametrage.tarif(b, c['code'] as String, aujourdhui);
    }
    if (_mode == Modes.gratuit) total = 0;
    final caisse = () {
      try {
        final id = Tresorerie.caisseDe(b, 'CS');
        return '${Tresorerie.compte(b, id)['libelle']} · solde ${fcfa(Tresorerie.solde(b, id))}';
      } on RegleMetier {
        return null;
      }
    }();
    final patient = _patient == null ? null : b.ligne('SELECT * FROM patients WHERE id=?', [_patient]);

    return Column(children: [
      Expanded(
        child: PageContenu(largeurMax: 720, enfants: [
          Row(children: [
            if (caisse != null) Expanded(child: Text(caisse, style: TextStyle(color: Theme.of(context).hintColor))),
            TextButton.icon(onPressed: () => _carnets(context), icon: const Icon(Icons.confirmation_number_outlined), label: const Text('Carnets de séances')),
          ]),
          const SizedBox(height: 12),
          Etape('1', 'Patient',
              child: Carte(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                onTap: () async {
                  final id = await choisirPatient(context);
                  if (id != null) setState(() => _patient = id);
                },
                child: Row(children: [
                  CircleAvatar(
                    backgroundColor: Couleurs.primaire.withValues(alpha: 0.12),
                    child: Text(patient == null ? '?' : (patient['nom'] as String).substring(0, 1),
                        style: const TextStyle(color: Couleurs.primaire, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(patient == null ? 'Choisir un patient (facultatif si payé)' : Patients.libelle(s, patient),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (patient != null) Text(patient['numero_dossier'] as String, style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                  Text(patient == null ? 'Choisir' : 'Changer', style: const TextStyle(color: Couleurs.primaire, fontWeight: FontWeight.w600)),
                ]),
              )),
          Etape('2', 'Service',
              child: ChoixPastilles<String>(
                options: [for (final a in services) (a['code'] as String, a['libelle'] as String)],
                valeur: _service,
                onChanged: (v) => setState(() {
                  _service = v;
                  _actes.clear();
                }),
              )),
          Etape('3', 'Actes',
              child: Column(children: [
                for (final c in catalogue)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CheckboxListTile(
                      value: _actes.contains(c['code']),
                      onChanged: (v) => setState(() => v! ? _actes.add(c['code'] as String) : _actes.remove(c['code'])),
                      tileColor: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(c['libelle'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
                      secondary: Text(fcfa(Parametrage.tarif(b, c['code'] as String, aujourdhui)),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
              ])),
          Etape('4', 'Mode de paiement',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ChoixPastilles<String>(
                  options: [for (final m in Modes.tous) (m, Modes.libelles[m]!)],
                  valeur: _mode,
                  onChanged: (v) => setState(() => _mode = v),
                ),
                if (Modes.estMomo(_mode)) ...[
                  const SizedBox(height: 12),
                  TextField(
                      controller: _reference,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Référence de transaction (obligatoire)')),
                ],
                if (_mode == Modes.cheque || _mode == Modes.virement) ...[
                  const SizedBox(height: 12),
                  TextField(controller: _reference, decoration: const InputDecoration(labelText: 'Référence (n° de chèque, virement)')),
                ],
                if (_mode == Modes.gratuit) ...[
                  const SizedBox(height: 12),
                  const Text('Motif de la gratuité', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ChoixPastilles<String>(
                    options: [for (final m in Actes.motifsGratuite) (m, m)],
                    valeur: _motifGratuite,
                    onChanged: (v) => setState(() => _motifGratuite = v),
                  ),
                ],
                if (_mode == Modes.priseEnCharge) ...[
                  const SizedBox(height: 12),
                  TextField(controller: _organisme, decoration: const InputDecoration(labelText: 'Organisme ou programme qui prend en charge')),
                ],
              ])),
        ]),
      ),
      Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Flex(
                  direction: MediaQuery.sizeOf(context).width < 600 ? Axis.vertical : Axis.horizontal,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: MediaQuery.sizeOf(context).width < 600 ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                  children: [
                  Flexible(
                    fit: FlexFit.loose,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('Total à encaisser', style: TextStyle(color: Theme.of(context).hintColor)),
                      Text(fcfa(total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  const SizedBox(width: 12, height: 8),
                  FilledButton.icon(
                    onPressed: _actes.isEmpty || _service == null
                        ? null
                        : () {
                            final op = executer(
                                context,
                                () => Actes.enregistrer(s,
                                    activite: _service!,
                                    actes: [for (final c in _actes) DemandeActe(c)],
                                    mode: _mode,
                                    patient: _patient,
                                    reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
                                    motifGratuite: _motifGratuite,
                                    organismePec: _organisme.text.trim().isEmpty ? null : _organisme.text.trim()));
                            if (op != null) setState(() => _fait = op);
                          },
                    icon: const Icon(Icons.check),
                    label: Text(_mode == Modes.credit ? 'Enregistrer (à crédit)' : 'Encaisser et émettre le reçu'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _confirmation(BuildContext context, Operation op) {
    final etat = Etat.de(context);
    Widget ligne(String a, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(color: Theme.of(context).hintColor))),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        );
    return PageContenu(largeurMax: 520, enfants: [
      const SizedBox(height: 24),
      const CircleAvatar(radius: 36, backgroundColor: Color(0xFFE3F4E8), child: Icon(Icons.check, size: 40, color: Couleurs.hausse)),
      const SizedBox(height: 16),
      const Text('Encaissement enregistré', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      Carte(
        child: Column(children: [
          ligne('Pièce', op.piece ?? ''),
          ligne('Montant', fcfa(op.d<int>('total'))),
          ligne('Mode', Modes.libelles[op.d('mode')] ?? ''),
          ligne('Écriture', op.d<int>('total') == 0 ? 'aucune (gratuité tracée)' : 'générée · équilibrée'),
          if (!etat.estCentral) ligne('Synchronisation', etat.etatSync!.libelle(etat.base!.maintenant)),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
              onPressed: () => afficherRecu(context, op.uuid), icon: const Icon(Icons.receipt_long), label: const Text('Reçu (imprimer, partager)')),
        ),
      ]),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () => setState(() {
          _fait = null;
          _actes.clear();
          _patient = null;
          _reference.clear();
          _organisme.clear();
          _motifGratuite = null;
          _mode = Modes.especes;
        }),
        child: const Text('Nouvel encaissement'),
      ),
    ]);
  }

  void _carnets(BuildContext context) {
    final etat = Etat.lire(context);
    final b = etat.base!;
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, maj) {
        final carnets = b.lignes(
            'SELECT k.*, a.libelle, p.nom, p.prenoms FROM carnets k JOIN actes_catalogue a ON a.code=k.acte LEFT JOIN patients p ON p.id=k.patient '
            'WHERE k.consommees < k.seances ORDER BY k.date DESC');
        return AlertDialog(
          title: const Text('Carnets de séances (massages et soins)'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: ListView(children: [
              for (final k in carnets)
                ListTile(
                  title: Text('${k['libelle']} · ${k['nom'] ?? 'sans patient'} ${k['prenoms'] ?? ''}'),
                  subtitle: Text('${k['consommees']} séance(s) consommée(s) sur ${k['seances']} · payé ${fcfa(k['montant'] as int)}'),
                  trailing: FilledButton(
                    onPressed: () {
                      if (reussir(c, () => Facturation.consommerSeance(etat.session!, k['id'] as String), succes: 'Séance enregistrée.')) maj(() {});
                    },
                    child: const Text('Séance'),
                  ),
                ),
              if (carnets.isEmpty) const EtatVide('Aucun carnet en cours.'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
            FilledButton(
              onPressed: () async {
                final patient = await choisirPatient(c);
                if (!c.mounted) return;
                final prestations = [
                  for (final a in b.lignes("SELECT code, libelle FROM actes_catalogue WHERE activite='MASS' AND actif=1 ORDER BY libelle")) (a['code'] as String, a['libelle'] as String)
                ];
                await formulaire(c, 'Vendre un carnet', [
                  Champ('acte', 'Prestation', choix: prestations),
                  const Champ('seances', 'Nombre de séances', nombre: true, initial: '5'),
                  const Champ('montant', 'Prix du carnet (FCFA)', nombre: true),
                  Champ('mode', 'Mode de paiement', choix: [for (final m in Modes.encaissables) (m, Modes.libelles[m]!)]),
                  const Champ('reference', 'Référence (mobile money)'),
                ], (d, v) {
                  final op = executer(
                      d,
                      () => Facturation.vendreCarnet(etat.session!,
                          acte: v['acte']!,
                          seances: int.tryParse(v['seances']!) ?? 0,
                          montant: int.tryParse(v['montant']!) ?? 0,
                          patient: patient,
                          mode: v['mode']!,
                          reference: v['reference']!.isEmpty ? null : v['reference']),
                      succes: 'Carnet vendu.');
                  if (op != null) Future.microtask(() => context.mounted ? afficherRecu(context, op.uuid) : null);
                  return op != null;
                });
                maj(() {});
              },
              child: const Text('Vendre un carnet'),
            ),
          ],
        );
      }),
    );
  }
}
