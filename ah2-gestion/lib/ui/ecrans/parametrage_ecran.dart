/// Paramétrage (PC central) : structure, utilisateurs, appareils, tarifs,
/// seuils, plan comptable, sauvegardes.
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../modules/parametrage/parametrage.dart';
import '../../modules/parametrage/referentiels.dart';
import '../../modules/sauvegarde/sauvegarde.dart';
import '../../noyau/outils.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';

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
    final onglets = <(String, Widget Function(BuildContext))>[
      ('Structure', _structure),
      ('Utilisateurs', _utilisateurs),
      ('Appareils', _appareils),
      ('Tarifs', _tarifs),
      ('Seuils et délais', _seuils),
      ('Plan comptable', _plan),
      ('Sauvegardes', _sauvegardes),
    ];
    return DefaultTabController(
      length: onglets.length,
      child: Column(children: [
        TabBar(isScrollable: true, tabs: [for (final o in onglets) Tab(text: o.$1)]),
        Expanded(child: TabBarView(children: [for (final o in onglets) Builder(builder: o.$2)])),
      ]),
    );
  }

  // --------------------------------------------------------------- structure
  Widget _structure(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final e in b.lignes('SELECT * FROM entites ORDER BY code'))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Carte(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['nom']} (${e['code']} · ${e['referentiel']})', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Sigle : ${e['sigle']}'),
              Text('Adresse : ${e['adresse']}'),
              Text('Contacts : ${e['contacts']}'),
              Text('Numéros administratifs : ${e['numeros_administratifs']}'),
              const SizedBox(height: 8),
              if (etat.session!.peut('parametrage', 'creer'))
                OutlinedButton(onPressed: () => _editerEntite(context, e), child: const Text('Modifier (en-tête des documents)')),
            ]),
          ),
        ),
    ]);
  }

  void _editerEntite(BuildContext context, Map<String, Object?> e) {
    final c = {
      for (final k in ['nom', 'sigle', 'adresse', 'contacts', 'numeros_administratifs']) k: TextEditingController(text: e[k] as String)
    };
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Entité ${e['code']}'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final k in c.keys)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: c[k], decoration: InputDecoration(labelText: k.replaceAll('_', ' ')))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (reussir(
                      d,
                      () => Parametrage.modifierEntite(Etat.lire(d).session!, e['code'] as String,
                          nom: c['nom']!.text,
                          sigle: c['sigle']!.text,
                          adresse: c['adresse']!.text,
                          contacts: c['contacts']!.text,
                          numeros: c['numeros_administratifs']!.text),
                      succes: 'Entité mise à jour.')) {
                Navigator.pop(d);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- utilisateurs
  Widget _utilisateurs(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (etat.session!.peut('utilisateurs', 'creer'))
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(onPressed: () => _nouvelUtilisateur(context), icon: const Icon(Icons.person_add_alt), label: const Text('Nouvel utilisateur')),
        ),
      const SizedBox(height: 12),
      Card(
        child: Column(children: [
          for (final u in b.lignes('SELECT u.*, r.libelle AS role_libelle FROM utilisateurs u JOIN roles r ON r.code=u.role ORDER BY u.nom'))
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text('${u['nom']} (${u['identifiant']})'),
              subtitle: Text('${u['role_libelle']}${u['activite'] != null ? ' · ${u['activite']}' : ''}'),
            ),
        ]),
      ),
    ]);
  }

  void _nouvelUtilisateur(BuildContext context) {
    final b = Etat.lire(context).base!;
    final id = TextEditingController(), nom = TextEditingController(), mdp = TextEditingController(), code = TextEditingController();
    String role = 'caissier';
    String? activite;
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: const Text('Nouvel utilisateur'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom complet')),
                const SizedBox(height: 10),
                TextField(controller: id, decoration: const InputDecoration(labelText: 'Identifiant personnel')),
                const SizedBox(height: 10),
                TextField(controller: mdp, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe (6 caractères min.)')),
                const SizedBox(height: 10),
                TextField(
                    controller: code,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Code court pour téléphone (4 chiffres min.)')),
                const SizedBox(height: 10),
                ChoixPastilles<String>(options: [for (final r in rolesDefaut.entries) (r.key, r.value)], valeur: role, onChanged: (v) => maj(() => role = v)),
                if (role == 'agent' || role == 'responsable') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: activite,
                    items: [
                      for (final a in b.lignes('SELECT code, libelle FROM activites WHERE service=1'))
                        DropdownMenuItem(value: a['code'] as String, child: Text(a['libelle'] as String))
                    ],
                    onChanged: (v) => maj(() => activite = v),
                    decoration: const InputDecoration(labelText: 'Service'),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (executer(
                        c,
                        () => Parametrage.ajouterUtilisateur(Etat.lire(c).session!,
                            identifiant: id.text.trim(),
                            nom: nom.text.trim(),
                            role: role,
                            motDePasse: mdp.text,
                            activite: activite,
                            code: code.text.isEmpty ? null : code.text),
                        succes: 'Utilisateur créé.') !=
                    null) {
                  Navigator.pop(c);
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- appareils
  Widget _appareils(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final s = etat.session!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (s.peut('appareils', 'creer'))
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(onPressed: () => _nouvelAppareil(context), icon: const Icon(Icons.add_to_home_screen), label: const Text('Autoriser un appareil')),
        ),
      const SizedBox(height: 12),
      Card(
        child: Column(children: [
          for (final a in b.lignes('SELECT * FROM appareils ORDER BY central DESC, code'))
            ListTile(
              leading: Icon(a['type'] == 'pc' ? Icons.computer : Icons.smartphone),
              title: Text('${a['code']} · ${a['nom']}${a['central'] == 1 ? ' (PC central)' : ''}'),
              subtitle: Text(a['statut'] as String),
              trailing: a['central'] == 1 || !s.peut('appareils', 'valider')
                  ? null
                  : Wrap(spacing: 4, children: [
                      IconButton(
                        tooltip: 'Afficher la clé de synchronisation',
                        icon: const Icon(Icons.key_outlined),
                        onPressed: () => _afficherCle(context, a['code'] as String, a['cle_sync'] as String),
                      ),
                      if (a['statut'] == 'autorise')
                        IconButton(
                          tooltip: 'Déclarer inactif',
                          icon: const Icon(Icons.pause_circle_outline),
                          onPressed: () => executer(context, () => Parametrage.changerStatutAppareil(s, a['code'] as String, 'inactif')),
                        ),
                      if (a['statut'] == 'inactif')
                        IconButton(
                          tooltip: 'Réactiver',
                          icon: const Icon(Icons.play_circle_outline),
                          onPressed: () => executer(context, () => Parametrage.changerStatutAppareil(s, a['code'] as String, 'autorise')),
                        ),
                      if (a['statut'] != 'revoque')
                        IconButton(
                          tooltip: 'Révoquer (appareil perdu)',
                          icon: const Icon(Icons.block, color: Couleurs.baisse),
                          onPressed: () => executer(context, () => Parametrage.revoquerAppareil(s, a['code'] as String, 'Révoqué depuis le paramétrage'),
                              succes: 'Appareil révoqué : il sera bloqué et effacé à sa prochaine connexion.'),
                        ),
                    ]),
            ),
        ]),
      ),
    ]);
  }

  void _nouvelAppareil(BuildContext context) {
    final code = TextEditingController(), nom = TextEditingController();
    String type = 'telephone';
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: const Text('Autoriser un appareil'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Code (T01, PC2…)')),
              const SizedBox(height: 10),
              TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom (ex. Téléphone laboratoire)')),
              const SizedBox(height: 10),
              ChoixPastilles<String>(options: const [('telephone', 'Téléphone'), ('pc', 'PC')], valeur: type, onChanged: (v) => maj(() => type = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final cle = executer(c,
                    () => Parametrage.ajouterAppareil(Etat.lire(c).session!, code: code.text.trim().toUpperCase(), nom: nom.text.trim(), type: type));
                if (cle != null) {
                  Navigator.pop(c);
                  _afficherCle(context, code.text.trim().toUpperCase(), cle);
                }
              },
              child: const Text('Autoriser'),
            ),
          ],
        ),
      ),
    );
  }

  void _afficherCle(BuildContext context, String code, String cle) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Clé de synchronisation de $code'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("À saisir sur l'appareil lors de son installation. Ne la communiquez à personne d'autre."),
              const SizedBox(height: 12),
              SelectableText(cle, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: cle)), child: const Text('Copier')),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
          ],
        ),
      );

  // --------------------------------------------------------------- tarifs
  Widget _tarifs(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final j = dateIso(b.maintenant);
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Un nouveau tarif ne modifie jamais les actes passés.', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      Card(
        child: Column(children: [
          for (final a in b.lignes('SELECT c.*, a.libelle AS service FROM actes_catalogue c JOIN activites a ON a.code=c.activite ORDER BY c.activite, c.libelle'))
            ListTile(
              title: Text('${a['libelle']} (${a['code']})'),
              subtitle: Text('${a['service']} · compte ${a['compte_produit']}'),
              trailing: TextButton(
                onPressed: etat.session!.peut('parametrage', 'creer') ? () => _tarif(context, a['code'] as String, Parametrage.tarif(b, a['code'] as String, j)) : null,
                child: Text(fcfa(Parametrage.tarif(b, a['code'] as String, j))),
              ),
            ),
        ]),
      ),
    ]);
  }

  void _tarif(BuildContext context, String code, int actuel) {
    final m = TextEditingController(text: '$actuel');
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Nouveau tarif · $code'),
        content: ChampMontant(controleur: m, aide: 'En vigueur à partir d’aujourd’hui'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (reussir(c, () => Parametrage.definirTarif(Etat.lire(c).session!, code, lireMontant(m)), succes: 'Tarif enregistré.')) {
                Navigator.pop(c);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- seuils
  Widget _seuils(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    const libelles = {
      'plafond_encaisse': 'Plafond d’encaisse (FCFA)',
      'seuil_validation_depense': 'Seuil de validation des dépenses (FCFA)',
      'seuil_piece_jointe': 'Pièce jointe obligatoire au-delà de (FCFA)',
      'peremption_alerte_jours': 'Alerte avant péremption (jours)',
      'baisse_activite_pourcent': 'Seuil de baisse d’activité (%)',
      'desintox_archivage_jours': 'Archivage des patients sortis de désintoxication (jours)',
      'desintox_reconnaissance': 'Reconnaissance du produit de désintoxication (inscription ou etalee)',
      'sync_jours_max': 'Jours sans synchronisation avant lecture seule',
      'sync_alerte_heures': 'Alerte appareil non synchronisé (heures)',
      'remise_plafond_pourcent': 'Plafond des remises (%)',
      'connexion_echecs_max': 'Échecs de connexion avant verrouillage',
      'inactivite_minutes': 'Déconnexion après inactivité (minutes)',
      'releve_section_ecarts': 'Section « Écarts constatés » sur les relevés (1 = oui, 0 = non)',
      'seuil_don_liste': 'Liste des dons supérieurs à (FCFA)',
      'sauvegarde_conservation_jours': 'Conservation des sauvegardes (jours)',
    };
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Column(children: [
          for (final e in libelles.entries)
            ListTile(
              title: Text(e.value),
              trailing: TextButton(
                onPressed: etat.session!.peut('parametrage', 'creer') ? () => _seuil(context, e.key, e.value, b.param(e.key, '')) : null,
                child: Text(b.param(e.key, '—')),
              ),
            ),
        ]),
      ),
    ]);
  }

  void _seuil(BuildContext context, String cle, String libelle, String valeur) {
    final t = TextEditingController(text: valeur);
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(libelle),
        content: TextField(controller: t),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (reussir(c, () => Parametrage.modifierParametre(Etat.lire(c).session!, cle, t.text.trim()), succes: 'Paramètre enregistré.')) {
                Navigator.pop(c);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- plan comptable
  Widget _plan(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Plans livrés pré-remplis, à valider par le comptable : SYSCOHADA pour le centre de santé, SYCEBNL pour l’ONG.',
          style: TextStyle(fontSize: 12)),
      for (final ent in ['CS', 'ONG']) ...[
        const SizedBox(height: 12),
        TitreSection(ent == 'CS' ? 'Centre de santé · SYSCOHADA' : 'ONG · SYCEBNL'),
        Card(
          child: Column(children: [
            for (final c in b.lignes('SELECT * FROM comptes WHERE entite=? ORDER BY numero', [ent]))
              ListTile(
                dense: true,
                title: Text('${c['numero']} · ${c['libelle']}'),
                trailing: c['a_valider'] == 1
                    ? (etat.session!.peut('comptabilite', 'valider')
                        ? TextButton(
                            onPressed: () => executer(context, () => Parametrage.validerCompte(etat.session!, ent, c['numero'] as String)),
                            child: const Text('Valider'))
                        : const Pastille('à valider', couleur: Couleurs.stable))
                    : const Pastille('validé', couleur: Couleurs.hausse),
              ),
          ]),
        ),
      ],
    ]);
  }

  // --------------------------------------------------------------- sauvegardes
  Widget _sauvegardes(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final dossier = TextEditingController(text: b.param('sauvegarde_dossier', ''));
    final mdp = TextEditingController();
    final derniere = b.valeur("SELECT valeur FROM etat_sync WHERE cle='derniere_sauvegarde'") as String?;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Carte(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(derniere == null || derniere.isEmpty
              ? 'Aucune sauvegarde effectuée.'
              : 'Dernière sauvegarde : ${dateFr(DateTime.parse(derniere))} à ${heureFr(DateTime.parse(derniere))}'),
          const SizedBox(height: 12),
          TextField(controller: dossier, decoration: const InputDecoration(labelText: 'Dossier (disque externe ou clé USB), ex. E:\\Sauvegardes AH2')),
          const SizedBox(height: 10),
          TextField(controller: mdp, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe de sauvegarde (8 caractères min.)')),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: etat.session!.peut('sauvegardes', 'creer')
                ? () {
                    final f = executer(context, () => Sauvegarde.sauvegarder(etat.session!, dossier: dossier.text.trim(), motDePasse: mdp.text));
                    if (f != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sauvegarde chiffrée créée : $f')));
                    }
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
              label: const Text('Restaurer une sauvegarde…'),
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
