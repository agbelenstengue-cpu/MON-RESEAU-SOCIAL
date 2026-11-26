/// Paramétrage (PC central) : tout s'ajoute, se modifie et se retire ici,
/// sans toucher au code. Ce qui a déjà servi est désactivé plutôt que
/// supprimé, pour que l'historique et la comptabilité restent intacts.
library;


import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../modules/parametrage/parametrage.dart';
import '../../modules/parametrage/referentiels.dart';
import '../../modules/sauvegarde/sauvegarde.dart';
import '../../noyau/outils.dart';
import '../../noyau/session.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';
import '../widgets/formulaire.dart';

class EcranParametrage extends StatelessWidget {
  const EcranParametrage({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    if (!etat.estCentral) {
      return const PageContenu(enfants: [
        Carte(child: Text('Le paramétrage se modifie uniquement sur le PC central ; il est diffusé à chaque synchronisation.')),
      ]);
    }
    final s = etat.session!;
    final onglets = <(String, Widget Function(BuildContext))>[
      ('Structure et documents', _structure),
      ('Services, actes et prix', _actes),
      ('Programmes de désintoxication', _programmes),
      ('Comptes de trésorerie', _tresoreries),
      ('Plan comptable', _plan),
      ("Schémas d'écritures", _schemas),
      ('Seuils et délais', _seuils),
      if (s.peut('utilisateurs', 'voir')) ('Utilisateurs', _utilisateurs),
      if (s.peut('appareils', 'voir')) ('Appareils', _appareils),
      if (s.peut('sauvegardes', 'voir')) ('Sauvegardes', _sauvegardes),
    ];
    return DefaultTabController(
      length: onglets.length,
      child: Column(children: [
        TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final o in onglets) Tab(text: o.$1)]),
        Expanded(child: TabBarView(children: [for (final o in onglets) Builder(builder: o.$2)])),
      ]),
    );
  }

  static Session _s(BuildContext c) => Etat.lire(c).session!;
  static bool _peut(BuildContext c, [String module = 'parametrage']) => Etat.de(c).session!.peut(module, 'creer');

  static Widget _liste(List<Widget> enfants) => ListView(padding: const EdgeInsets.all(16), children: enfants);

  static Widget _boutons(List<Widget> b) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Wrap(spacing: 8, runSpacing: 8, children: b));

  static Widget _actionsLigne(List<Widget> b) => Wrap(spacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: b);

  static IconButton _icone(String aide, IconData i, VoidCallback? f, {Color? couleur}) =>
      IconButton(tooltip: aide, icon: Icon(i, color: couleur), onPressed: f);

  static void _retirer(BuildContext context, String quoi, String Function() action) async {
    if (!await confirmer(context, 'Retirer $quoi ? S’il a déjà servi, il sera seulement désactivé (l’historique est conservé).')) return;
    if (!context.mounted) return;
    final r = executer(context, action);
    if (r != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${quoi[0].toUpperCase()}${quoi.substring(1)} : $r.')));
    }
  }

  static Future<Uint8List?> _choisirImage() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400);
    return f == null ? null : await f.readAsBytes();
  }

  static List<(String, String)> _comptes(BuildContext c, String entite, {String prefixe = ''}) => [
        for (final x in Etat.lire(c)
            .base!
            .lignes("SELECT numero, libelle FROM comptes WHERE entite=? AND actif=1 AND numero LIKE ? ORDER BY numero", [entite, '$prefixe%']))
          (x['numero'] as String, '${x['numero']} ${x['libelle']}')
      ];

  // ===================================================================== structure
  Widget _structure(BuildContext context) {
    final b = Etat.de(context).base!;
    final ok = _peut(context);
    return _liste([
      const Text(
          'Le logo apparaît en haut des documents et en filigrane (sur les documents et à l’écran). '
          'Une entête importée (image de votre papier à en-tête) remplace l’entête générée sur les documents A4.',
          style: TextStyle(fontSize: 13)),
      const SizedBox(height: 12),
      for (final e in b.lignes('SELECT * FROM entites ORDER BY code'))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Carte(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['nom']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('${e['code'] == 'CS' ? 'Centre de santé' : 'ONG'} · comptabilité ${e['referentiel']}', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              Wrap(spacing: 24, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.start, children: [
                _apercu('Logo', e['logo'] as Uint8List?, 96, 96),
                _apercu('Entête importée', e['entete'] as Uint8List?, 360, 96),
                SizedBox(
                  width: 320,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _info('Sigle', e['sigle']),
                    _info('Adresse', e['adresse']),
                    _info('Contacts', e['contacts']),
                    _info('Numéros administratifs', e['numeros_administratifs']),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              if (ok)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Importer le logo'),
                    onPressed: () async {
                      final o = await _choisirImage();
                      if (o != null && context.mounted) {
                        reussir(context, () => Parametrage.definirLogo(_s(context), e['code'] as String, o), succes: 'Logo enregistré.');
                      }
                    },
                  ),
                  if (e['logo'] != null)
                    TextButton(
                        onPressed: () => reussir(context, () => Parametrage.definirLogo(_s(context), e['code'] as String, null), succes: 'Logo retiré.'),
                        child: const Text('Retirer le logo')),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.wallpaper_outlined),
                    label: const Text('Importer une entête'),
                    onPressed: () async {
                      final o = await _choisirImage();
                      if (o != null && context.mounted) {
                        reussir(context, () => Parametrage.definirEntete(_s(context), e['code'] as String, o), succes: 'Entête enregistrée.');
                      }
                    },
                  ),
                  if (e['entete'] != null)
                    TextButton(
                        onPressed: () =>
                            reussir(context, () => Parametrage.definirEntete(_s(context), e['code'] as String, null), succes: 'Entête retirée.'),
                        child: const Text('Revenir à l’entête générée')),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier les textes'),
                    onPressed: () => _textes(context, e),
                  ),
                ]),
              if (ok)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: e['filigrane'] == 1,
                  onChanged: (v) => reussir(context, () => Parametrage.definirFiligrane(_s(context), e['code'] as String, v)),
                  title: const Text('Logo en filigrane'),
                ),
            ]),
          ),
        ),
    ]);
  }

  static Widget _apercu(String titre, Uint8List? o, double l, double h) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Container(
          width: l,
          height: h,
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFBDBDBD)), borderRadius: BorderRadius.circular(4)),
          child: o == null ? const Text('Aucun', style: TextStyle(fontSize: 12)) : Image.memory(o, fit: BoxFit.contain),
        ),
      ]);

  static Widget _info(String l, Object? v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text('$l : ${(v as String? ?? '').isEmpty ? 'non renseigné' : v}', style: const TextStyle(fontSize: 13)),
      );

  void _textes(BuildContext context, Map<String, Object?> e) => formulaire(context, 'Textes de l’entête', [
        Champ('nom', 'Nom', initial: e['nom'] as String),
        Champ('sigle', 'Sigle', initial: e['sigle'] as String),
        Champ('adresse', 'Adresse', initial: e['adresse'] as String),
        Champ('contacts', 'Contacts (téléphone, e-mail)', initial: e['contacts'] as String),
        Champ('numeros', 'Numéros administratifs', initial: e['numeros_administratifs'] as String),
      ], (c, v) => reussir(c, () => Parametrage.modifierEntite(_s(c), e['code'] as String,
          nom: v['nom']!, sigle: v['sigle']!, adresse: v['adresse']!, contacts: v['contacts']!, numeros: v['numeros']!), succes: 'Entête mise à jour.'));

  // ===================================================================== actes
  Widget _actes(BuildContext context) {
    final b = Etat.de(context).base!;
    final ok = _peut(context);
    final j = dateIso(b.maintenant);
    final services = b.lignes('SELECT * FROM activites ORDER BY entite, actif DESC, libelle');
    return _liste([
      if (ok)
        _boutons([
          FilledButton.icon(onPressed: () => _nouvelActe(context), icon: const Icon(Icons.add), label: const Text('Ajouter un acte')),
          OutlinedButton.icon(onPressed: () => _nouveauService(context), icon: const Icon(Icons.add_business_outlined), label: const Text('Ajouter un service')),
        ]),
      const Text('Un nouveau prix s’applique à partir d’aujourd’hui ; les actes passés gardent leur prix.', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      for (final sv in services)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: Column(children: [
              ListTile(
                title: Text('${sv['libelle']}${sv['actif'] == 0 ? ' (désactivé)' : ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${sv['code']} · ${sv['entite'] == 'CS' ? 'Centre de santé' : 'ONG'}${sv['service'] == 1 ? ' · relevé journalier' : ''}'),
                trailing: !ok
                    ? null
                    : _actionsLigne([
                        _icone('Renommer', Icons.edit_outlined, () => formulaire(context, 'Renommer le service', [
                              Champ('libelle', 'Libellé', initial: sv['libelle'] as String),
                            ], (c, v) => reussir(c, () => Parametrage.modifierActivite(_s(c), sv['code'] as String, libelle: v['libelle']!)))),
                        if (sv['actif'] == 1)
                          _icone('Retirer', Icons.delete_outline, () => _retirer(context, 'le service ${sv['libelle']}', () => Parametrage.retirerActivite(_s(context), sv['code'] as String)))
                        else
                          _icone('Réactiver', Icons.restore, () => reussir(context, () => Parametrage.reactiverActivite(_s(context), sv['code'] as String))),
                      ]),
              ),
              for (final a in b.lignes('SELECT * FROM actes_catalogue WHERE activite=? ORDER BY actif DESC, libelle', [sv['code']]))
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 32, right: 8),
                  title: Text('${a['libelle']}${a['actif'] == 0 ? ' (désactivé)' : ''}'),
                  subtitle: Text('${a['code']} · compte ${a['compte_produit']}'),
                  trailing: _actionsLigne([
                    TextButton(
                      onPressed: ok ? () => _prix(context, a['code'] as String, Parametrage.tarif(b, a['code'] as String, j)) : null,
                      child: Text(fcfa(Parametrage.tarif(b, a['code'] as String, j))),
                    ),
                    if (ok) ...[
                      _icone('Modifier', Icons.edit_outlined, () => formulaire(context, 'Modifier l’acte', [
                            Champ('libelle', 'Libellé', initial: a['libelle'] as String),
                            Champ('compte', 'Compte de produit', initial: a['compte_produit'] as String, choix: _comptes(context, sv['entite'] as String, prefixe: '7')),
                          ], (c, v) => reussir(c, () => Parametrage.modifierActe(_s(c), a['code'] as String, libelle: v['libelle']!, compteProduit: v['compte']!)))),
                      if (a['actif'] == 1)
                        _icone('Retirer', Icons.delete_outline, () => _retirer(context, 'l’acte ${a['libelle']}', () => Parametrage.retirerActe(_s(context), a['code'] as String)))
                      else
                        _icone('Réactiver', Icons.restore, () => reussir(context, () => Parametrage.reactiverActe(_s(context), a['code'] as String))),
                    ],
                  ]),
                ),
            ]),
          ),
        ),
    ]);
  }

  void _prix(BuildContext context, String code, int actuel) => formulaire(context, 'Nouveau prix · $code', [
        Champ('prix', 'Prix (FCFA)', initial: '$actuel', nombre: true, aide: 'En vigueur à partir d’aujourd’hui'),
      ], (c, v) => reussir(c, () => Parametrage.definirTarif(_s(c), code, int.tryParse(v['prix']!) ?? -1), succes: 'Prix enregistré.'));

  void _nouvelActe(BuildContext context) {
    final b = Etat.lire(context).base!;
    final services = [for (final a in b.lignes('SELECT code, libelle FROM activites WHERE actif=1 ORDER BY libelle')) (a['code'] as String, a['libelle'] as String)];
    formulaire(context, 'Ajouter un acte', [
      Champ('activite', 'Service', choix: services),
      const Champ('code', 'Code (ex. LAB-HB)'),
      const Champ('libelle', 'Libellé (ex. Hémoglobine)'),
      const Champ('prix', 'Prix (FCFA)', nombre: true),
      const Champ('compte', 'Compte de produit (laisser vide : celui du service)'),
    ], (c, v) {
      var compte = v['compte']!;
      if (compte.isEmpty) {
        compte = (b.valeur('SELECT compte_produit FROM actes_catalogue WHERE activite=? LIMIT 1', [v['activite']]) as String?) ?? '';
      }
      return reussir(
          c,
          () => Parametrage.ajouterActe(_s(c),
              code: v['code']!, libelle: v['libelle']!, activite: v['activite']!, compteProduit: compte, prix: int.tryParse(v['prix']!) ?? -1),
          succes: 'Acte ajouté.');
    });
  }

  void _nouveauService(BuildContext context) => formulaire(context, 'Ajouter un service', [
        const Champ('code', 'Code (ex. ECHO)'),
        const Champ('libelle', 'Libellé (ex. Échographie)'),
        const Champ('entite', 'Entité', choix: [('CS', 'Centre de santé'), ('ONG', 'ONG')]),
        const Champ('service', 'Relevé journalier des actes', choix: [('1', 'Oui (service qui enregistre des actes)'), ('0', 'Non')]),
      ], (c, v) => reussir(c, () => Parametrage.ajouterActivite(_s(c),
          code: v['code']!, libelle: v['libelle']!, entite: v['entite']!, service: v['service'] == '1'), succes: 'Service ajouté.'));

  // ===================================================================== programmes
  Widget _programmes(BuildContext context) {
    final b = Etat.de(context).base!;
    final ok = _peut(context);
    return _liste([
      if (ok)
        _boutons([FilledButton.icon(onPressed: () => _programme(context, null), icon: const Icon(Icons.add), label: const Text('Ajouter un programme'))]),
      const Text('Une modification ne change pas le montant des patients déjà inscrits.', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      Card(
        child: Column(children: [
          for (final p in b.lignes('SELECT * FROM programmes_desintox ORDER BY actif DESC, libelle'))
            ListTile(
              title: Text('${p['libelle']}${p['actif'] == 0 ? ' (désactivé)' : ''}'),
              subtitle: Text('${p['code']} · ${p['type']} · ${p['duree_jours']} jours · '
                  '${p['mode_calcul'] == 'forfait' ? 'forfait ${fcfa(p['montant'] as int)}' : '${fcfa(p['montant'] as int)} par jour'}'),
              trailing: !ok
                  ? null
                  : _actionsLigne([
                      _icone('Modifier', Icons.edit_outlined, () => _programme(context, p)),
                      _icone('Retirer', Icons.delete_outline, () => _retirer(context, 'le programme ${p['libelle']}', () => Parametrage.retirerProgramme(_s(context), p['code'] as String))),
                    ]),
            ),
        ]),
      ),
    ]);
  }

  void _programme(BuildContext context, Map<String, Object?>? p) => formulaire(context, p == null ? 'Ajouter un programme' : 'Modifier le programme', [
        Champ('code', 'Code (ex. RES-60)', initial: (p?['code'] ?? '') as String, modifiable: p == null),
        Champ('libelle', 'Libellé', initial: (p?['libelle'] ?? '') as String),
        Champ('type', 'Type', initial: (p?['type'] ?? 'residentiel') as String, choix: const [('residentiel', 'Résidentiel'), ('ambulatoire', 'Ambulatoire')]),
        Champ('duree', 'Durée (jours)', initial: '${p?['duree_jours'] ?? ''}', nombre: true),
        Champ('mode', 'Calcul du montant', initial: (p?['mode_calcul'] ?? 'forfait') as String,
            choix: const [('forfait', 'Forfait (montant total)'), ('journalier', 'Prix par jour × durée')]),
        Champ('montant', 'Montant (FCFA)', initial: '${p?['montant'] ?? ''}', nombre: true),
        Champ('phases', 'Phases (facultatif)', initial: (p?['phases'] ?? '') as String),
      ], (c, v) => reussir(c, () => Parametrage.enregistrerProgramme(_s(c),
          code: v['code']!, libelle: v['libelle']!, type: v['type']!, duree: int.tryParse(v['duree']!) ?? 0,
          modeCalcul: v['mode']!, montant: int.tryParse(v['montant']!) ?? 0, phases: v['phases']!), succes: 'Programme enregistré.'));

  // ===================================================================== trésorerie
  Widget _tresoreries(BuildContext context) {
    final b = Etat.de(context).base!;
    final ok = _peut(context);
    return _liste([
      if (ok)
        _boutons([FilledButton.icon(onPressed: () => _nouvelleTreso(context), icon: const Icon(Icons.add), label: const Text('Ajouter un compte (banque, mobile money, caisse)'))]),
      for (final ent in ['CS', 'ONG']) ...[
        TitreSection(ent == 'CS' ? 'Centre de santé' : 'ONG'),
        const SizedBox(height: 6),
        Card(
          child: Column(children: [
            for (final t in b.lignes('SELECT * FROM tresoreries WHERE entite=? ORDER BY actif DESC, centrale DESC, type, id', [ent]))
              ListTile(
                title: Text('${t['libelle']}${t['actif'] == 0 ? ' (désactivé)' : ''}'),
                subtitle: Text('${t['type']} · compte ${t['compte']} · journal ${t['journal']}${t['appareil'] != null ? ' · appareil ${t['appareil']}' : ''}'),
                trailing: !ok || t['actif'] == 0 || t['centrale'] == 1
                    ? null
                    : _icone('Retirer', Icons.delete_outline, () => _retirer(context, 'le compte ${t['libelle']}', () => Parametrage.retirerTresorerie(_s(context), t['id'] as String))),
              ),
          ]),
        ),
        const SizedBox(height: 12),
      ],
    ]);
  }

  void _nouvelleTreso(BuildContext context) => formulaire(context, 'Ajouter un compte de trésorerie', [
        const Champ('entite', 'Entité', choix: [('CS', 'Centre de santé'), ('ONG', 'ONG')]),
        const Champ('type', 'Type', choix: [('banque', 'Banque'), ('momo', 'Mobile money'), ('caisse', 'Caisse')]),
        const Champ('libelle', 'Libellé (ex. Banque Afriland, compte projet)'),
        const Champ('compte', 'Numéro de compte comptable (ex. 5212)', nombre: true, aide: 'Créé dans le plan comptable s’il n’existe pas'),
        const Champ('operateur', 'Opérateur (mobile money)', choix: [('', 'Sans objet'), ('MTN', 'MTN'), ('ORANGE', 'Orange')]),
      ], (c, v) => reussir(c, () => Parametrage.ajouterTresorerie(_s(c),
          entite: v['entite']!, type: v['type']!, libelle: v['libelle']!, compte: v['compte']!, operateur: v['operateur']!.isEmpty ? null : v['operateur']), succes: 'Compte ajouté.'));

  // ===================================================================== plan comptable
  Widget _plan(BuildContext context) {
    final b = Etat.de(context).base!;
    final ok = _peut(context, 'comptabilite');
    final valider = Etat.de(context).session!.peut('comptabilite', 'valider');
    return _liste([
      if (ok)
        _boutons([FilledButton.icon(onPressed: () => _nouveauCompte(context), icon: const Icon(Icons.add), label: const Text('Ajouter un compte'))]),
      const Text('Centre de santé : SYSCOHADA révisé. ONG : SYCEBNL. Un compte déjà mouvementé est désactivé au lieu d’être supprimé.',
          style: TextStyle(fontSize: 12)),
      for (final ent in ['CS', 'ONG']) ...[
        const SizedBox(height: 12),
        TitreSection(ent == 'CS' ? 'Centre de santé, SYSCOHADA' : 'ONG, SYCEBNL'),
        const SizedBox(height: 6),
        Card(
          child: Column(children: [
            for (final c in b.lignes('SELECT * FROM comptes WHERE entite=? ORDER BY numero', [ent]))
              ListTile(
                dense: true,
                title: Text('${c['numero']}  ${c['libelle']}${c['actif'] == 0 ? ' (désactivé)' : ''}'),
                trailing: _actionsLigne([
                  if (c['a_valider'] == 1)
                    valider
                        ? TextButton(onPressed: () => reussir(context, () => Parametrage.validerCompte(_s(context), ent, c['numero'] as String)), child: const Text('Valider'))
                        : const Pastille('à valider', couleur: Couleurs.stable),
                  if (ok) ...[
                    _icone('Modifier le libellé', Icons.edit_outlined, () => formulaire(context, 'Compte ${c['numero']}', [
                          Champ('libelle', 'Libellé', initial: c['libelle'] as String),
                        ], (d, v) => reussir(d, () => Parametrage.modifierCompte(_s(d), entite: ent, numero: c['numero'] as String, libelle: v['libelle']!)))),
                    if (c['actif'] == 1)
                      _icone('Retirer', Icons.delete_outline,
                          () => _retirer(context, 'le compte ${c['numero']}', () => Parametrage.retirerCompte(_s(context), entite: ent, numero: c['numero'] as String)))
                    else
                      _icone('Réactiver', Icons.restore, () => reussir(context, () => Parametrage.reactiverCompte(_s(context), entite: ent, numero: c['numero'] as String))),
                  ],
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }

  void _nouveauCompte(BuildContext context) => formulaire(context, 'Ajouter un compte', [
        const Champ('entite', 'Entité', choix: [('CS', 'Centre de santé (SYSCOHADA)'), ('ONG', 'ONG (SYCEBNL)')]),
        const Champ('numero', 'Numéro', nombre: true),
        const Champ('libelle', 'Libellé'),
      ], (c, v) => reussir(c, () => Parametrage.ajouterCompte(_s(c), entite: v['entite']!, numero: v['numero']!, libelle: v['libelle']!), succes: 'Compte ajouté.'));

  // ===================================================================== schémas
  Widget _schemas(BuildContext context) {
    final b = Etat.de(context).base!;
    final ok = _peut(context, 'comptabilite');
    return _liste([
      const Text(
          'Chaque opération génère son écriture selon ces schémas. Les mots entre accolades sont remplacés automatiquement '
          '({tresorerie} : la caisse ou la banque utilisée, {produit} : le compte de l’acte, {charge} : le compte choisi pour la dépense).',
          style: TextStyle(fontSize: 12)),
      for (final ent in ['CS', 'ONG']) ...[
        const SizedBox(height: 12),
        TitreSection(ent == 'CS' ? 'Centre de santé' : 'ONG'),
        const SizedBox(height: 6),
        Card(
          child: Column(children: [
            for (final l in b.lignes('SELECT * FROM schemas_ecritures WHERE entite=? ORDER BY type_ecriture, ordre', [ent]))
              ListTile(
                dense: true,
                title: Text('${l['libelle']}'),
                subtitle: Text('${l['type_ecriture']} · ligne ${l['ordre']}'),
                trailing: TextButton(
                  onPressed: !ok
                      ? null
                      : () => formulaire(context, '${l['libelle']} · ${l['sens'] == 'D' ? 'débit' : 'crédit'}', [
                            Champ('compte', 'Compte ou variable', initial: l['compte'] as String),
                          ], (c, v) => reussir(c, () => Parametrage.modifierSchema(_s(c),
                              entite: ent, type: l['type_ecriture'] as String, ordre: l['ordre'] as int, compte: v['compte']!), succes: 'Schéma modifié.')),
                  child: Text('${l['sens'] == 'D' ? 'Débit' : 'Crédit'} ${l['compte']}'),
                ),
              ),
          ]),
        ),
      ],
    ]);
  }

  // ===================================================================== seuils
  Widget _seuils(BuildContext context) {
    final b = Etat.de(context).base!;
    final ok = _peut(context);
    const libelles = {
      'plafond_encaisse': 'Plafond d’encaisse (FCFA)',
      'seuil_validation_depense': 'Seuil de validation des dépenses par la direction (FCFA)',
      'seuil_piece_jointe': 'Pièce jointe obligatoire au-delà de (FCFA)',
      'remise_plafond_pourcent': 'Plafond des remises (%)',
      'peremption_alerte_jours': 'Alerte avant péremption (jours)',
      'baisse_activite_pourcent': 'Seuil de baisse d’activité (%)',
      'desintox_archivage_jours': 'Archivage des patients sortis de désintoxication (jours)',
      'desintox_reconnaissance': 'Reconnaissance du produit de désintoxication (inscription ou etalee)',
      'sync_jours_max': 'Jours sans synchronisation avant lecture seule',
      'sync_alerte_heures': 'Alerte appareil non synchronisé (heures)',
      'connexion_echecs_max': 'Échecs de connexion avant verrouillage',
      'connexion_verrou_minutes': 'Durée du verrouillage (minutes)',
      'inactivite_minutes': 'Déconnexion après inactivité (minutes, si la connexion est demandée)',
      'remede_litres_par_patient': 'Quantité de remède servie par patient et par jour (litres)',
      'releve_section_ecarts': 'Section « Écarts constatés » sur les relevés (1 = oui, 0 = non)',
      'seuil_don_liste': 'Liste des dons supérieurs à (FCFA)',
      'sauvegarde_conservation_jours': 'Conservation des sauvegardes (jours)',
      'coupures': 'Billets et pièces pour le billetage (séparés par des virgules)',
    };
    final etat = Etat.de(context);
    return _liste([
      Card(
        child: SwitchListTile(
          value: etat.connexionRequise,
          title: const Text('Demander un identifiant et un mot de passe à l’ouverture'),
          subtitle: Text(etat.connexionRequise
              ? 'Chaque personne se connecte avec son identifiant.'
              : 'Le logiciel s’ouvre directement sur le compte « ${etat.session!.nom} ».'),
          onChanged: !ok
              ? null
              : (v) {
                  if (!v) {
                    reussir(context, () => Parametrage.exigerConnexion(_s(context), false), succes: 'Ouverture directe rétablie.');
                    return;
                  }
                  formulaire(context, 'Mot de passe du comptable', const [
                    Champ('mdp', 'Nouveau mot de passe (6 caractères minimum)'),
                    Champ('code', 'Code court pour le téléphone (4 chiffres, facultatif)', nombre: true),
                  ], (c, x) => reussir(c, () {
                    Parametrage.changerMotDePasse(_s(c), 'comptable', x['mdp']!, code: x['code']!.isEmpty ? null : x['code']);
                    Parametrage.exigerConnexion(_s(c), true);
                  }, succes: 'Connexion activée. Identifiant : comptable.'));
                },
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: Column(children: [
          for (final e in libelles.entries)
            ListTile(
              title: Text(e.value),
              trailing: TextButton(
                onPressed: !ok
                    ? null
                    : () => formulaire(context, e.value, [Champ('v', 'Valeur', initial: b.param(e.key, ''))],
                        (c, v) => reussir(c, () => Parametrage.modifierParametre(_s(c), e.key, v['v']!), succes: 'Paramètre enregistré.')),
                child: Text(b.param(e.key, 'non renseigné')),
              ),
            ),
        ]),
      ),
    ]);
  }

  // ===================================================================== utilisateurs
  Widget _utilisateurs(BuildContext context) {
    final b = Etat.de(context).base!;
    final ok = _peut(context, 'utilisateurs');
    return _liste([
      if (ok) _boutons([FilledButton.icon(onPressed: () => _nouvelUtilisateur(context), icon: const Icon(Icons.person_add_alt), label: const Text('Ajouter un utilisateur'))]),
      Card(
        child: Column(children: [
          for (final u in b.lignes('SELECT u.*, r.libelle AS role_libelle FROM utilisateurs u JOIN roles r ON r.code=u.role ORDER BY u.actif DESC, u.nom'))
            ListTile(
              title: Text('${u['nom']} (${u['identifiant']})${u['actif'] == 0 ? ' (désactivé)' : ''}'),
              subtitle: Text('${u['role_libelle']}${u['activite'] != null ? ' · ${u['activite']}' : ''}'),
              trailing: !ok
                  ? null
                  : (u['actif'] == 1
                      ? _icone('Désactiver', Icons.person_off_outlined, () => reussir(context, () => Parametrage.desactiverUtilisateur(_s(context), u['id'] as String)))
                      : _icone('Réactiver', Icons.restore, () => reussir(context, () => Parametrage.desactiverUtilisateur(_s(context), u['id'] as String, actif: true)))),
            ),
        ]),
      ),
    ]);
  }

  void _nouvelUtilisateur(BuildContext context) {
    final b = Etat.lire(context).base!;
    formulaire(context, 'Ajouter un utilisateur', [
      const Champ('nom', 'Nom complet'),
      const Champ('identifiant', 'Identifiant personnel'),
      const Champ('mdp', 'Mot de passe (6 caractères minimum)'),
      const Champ('code', 'Code court pour le téléphone (4 chiffres minimum, facultatif)', nombre: true),
      Champ('role', 'Rôle', initial: 'caissier', choix: [for (final r in rolesDefaut.entries) (r.key, r.value)]),
      Champ('activite', 'Service (agents et responsables)',
          choix: [('', 'Aucun'), for (final a in b.lignes('SELECT code, libelle FROM activites WHERE service=1 AND actif=1')) (a['code'] as String, a['libelle'] as String)]),
    ], (c, v) => reussir(c, () => Parametrage.ajouterUtilisateur(_s(c),
        identifiant: v['identifiant']!, nom: v['nom']!, role: v['role']!, motDePasse: v['mdp']!,
        activite: v['activite']!.isEmpty ? null : v['activite'], code: v['code']!.isEmpty ? null : v['code']), succes: 'Utilisateur ajouté.'));
  }

  // ===================================================================== appareils
  Widget _appareils(BuildContext context) {
    final b = Etat.de(context).base!;
    final s = Etat.de(context).session!;
    return _liste([
      if (s.peut('appareils', 'creer'))
        _boutons([FilledButton.icon(onPressed: () => _nouvelAppareil(context), icon: const Icon(Icons.add_to_home_screen), label: const Text('Autoriser un appareil'))]),
      Card(
        child: Column(children: [
          for (final a in b.lignes('SELECT * FROM appareils ORDER BY central DESC, code'))
            ListTile(
              leading: Icon(a['type'] == 'pc' ? Icons.computer : Icons.smartphone),
              title: Text('${a['code']} · ${a['nom']}${a['central'] == 1 ? ' (PC central)' : ''}'),
              subtitle: Text(a['statut'] as String),
              trailing: a['central'] == 1 || !s.peut('appareils', 'valider')
                  ? null
                  : _actionsLigne([
                      _icone('Afficher la clé de synchronisation', Icons.key_outlined, () => _afficherCle(context, a['code'] as String, a['cle_sync'] as String)),
                      if (a['statut'] == 'autorise')
                        _icone('Déclarer inactif', Icons.pause_circle_outline, () => reussir(context, () => Parametrage.changerStatutAppareil(s, a['code'] as String, 'inactif'))),
                      if (a['statut'] == 'inactif')
                        _icone('Réactiver', Icons.play_circle_outline, () => reussir(context, () => Parametrage.changerStatutAppareil(s, a['code'] as String, 'autorise'))),
                      if (a['statut'] != 'revoque')
                        _icone('Révoquer (appareil perdu)', Icons.block, couleur: Couleurs.baisse, () async {
                          if (await confirmer(context, 'Révoquer ${a['code']} ? Il sera bloqué et ses données locales effacées à sa prochaine connexion.') && context.mounted) {
                            reussir(context, () => Parametrage.revoquerAppareil(s, a['code'] as String, 'Révoqué depuis le paramétrage'), succes: 'Appareil révoqué.');
                          }
                        }),
                    ]),
            ),
        ]),
      ),
    ]);
  }

  void _nouvelAppareil(BuildContext context) => formulaire(context, 'Autoriser un appareil', [
        const Champ('code', 'Code (T01, PC2…)'),
        const Champ('nom', 'Nom (ex. Téléphone laboratoire)'),
        const Champ('type', 'Type', choix: [('telephone', 'Téléphone'), ('pc', 'PC')]),
      ], (c, v) {
        final code = v['code']!.toUpperCase();
        final cle = executer(c, () => Parametrage.ajouterAppareil(_s(c), code: code, nom: v['nom']!, type: v['type']!));
        if (cle == null) return false;
        Future.microtask(() => context.mounted ? _afficherCle(context, code, cle) : null);
        return true;
      }, bouton: 'Autoriser');

  void _afficherCle(BuildContext context, String code, String cle) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Clé de synchronisation de $code'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("À saisir sur l'appareil lors de son installation. Ne la communiquez à personne d'autre."),
              const SizedBox(height: 12),
              SelectableText(cle, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: cle)), child: const Text('Copier')),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
          ],
        ),
      );

  // ===================================================================== sauvegardes
  Widget _sauvegardes(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final dossier = TextEditingController(text: b.param('sauvegarde_dossier', ''));
    final mdp = TextEditingController();
    final derniere = b.valeur("SELECT valeur FROM etat_sync WHERE cle='derniere_sauvegarde'") as String?;
    return _liste([
      Carte(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(derniere == null || derniere.isEmpty
              ? 'Aucune sauvegarde effectuée.'
              : 'Dernière sauvegarde : ${dateFr(DateTime.parse(derniere))} à ${heureFr(DateTime.parse(derniere))}'),
          const SizedBox(height: 12),
          TextField(controller: dossier, decoration: const InputDecoration(labelText: 'Dossier (disque externe ou clé USB), ex. E:\\Sauvegardes AH2')),
          const SizedBox(height: 10),
          TextField(controller: mdp, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe de sauvegarde (8 caractères minimum)')),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: etat.session!.peut('sauvegardes', 'creer')
                ? () {
                    final f = executer(context, () => Sauvegarde.sauvegarder(etat.session!, dossier: dossier.text.trim(), motDePasse: mdp.text));
                    if (f != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sauvegarde chiffrée créée : $f')));
                  }
                : null,
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Sauvegarder maintenant'),
          ),
          const SizedBox(height: 8),
          if (etat.session!.peut('sauvegardes', 'valider'))
            OutlinedButton.icon(
              onPressed: () => _restaurer(context),
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text('Restaurer une sauvegarde'),
            ),
          const SizedBox(height: 8),
          const Text('Un appareil se reconstruit depuis le PC central par simple synchronisation.', style: TextStyle(fontSize: 12)),
        ]),
      ),
    ]);
  }

  void _restaurer(BuildContext context) {
    final fichier = TextEditingController(), mdp = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restaurer une sauvegarde'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('La base actuelle sera remplacée par la sauvegarde. Vous serez déconnecté.', style: TextStyle(color: Couleurs.baisse)),
            const SizedBox(height: 10),
            TextField(controller: fichier, decoration: const InputDecoration(labelText: 'Chemin du fichier .ah2s')),
            const SizedBox(height: 10),
            TextField(controller: mdp, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe de sauvegarde')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final etat = Etat.lire(c);
              final code = etat.base!.appareil;
              final chemin = etat.cheminBase;
              if (chemin == null) return;
              try {
                etat.base!.fermer();
                Sauvegarde.restaurer(fichier: fichier.text.trim(), motDePasse: mdp.text, cheminBase: chemin);
                Navigator.pop(c);
              } on RegleMetier catch (e) {
                ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Couleurs.baisse));
              } finally {
                etat.reouvrirAvecCode(code);
                etat.deconnecter();
              }
            },
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
  }
}
