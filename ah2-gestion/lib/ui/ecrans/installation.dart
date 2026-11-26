/// Première installation : PC central, ou appareil qui rejoint la structure.
library;

import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../demo/demonstration.dart';
import '../../main.dart' show enregistrerCodeAppareil, logoParDefaut;
import '../../modules/parametrage/parametrage.dart';
import '../../noyau/outils.dart';
import '../../sync/synchronisation.dart';
import '../etat_app.dart';
import '../theme.dart';
import '../widgets/commun.dart';

class EcranInstallation extends StatefulWidget {
  const EcranInstallation({super.key});
  @override
  State<EcranInstallation> createState() => _EcranInstallationState();
}

class _EcranInstallationState extends State<EcranInstallation> {
  String? _mode; // central ou appareil
  final _code = TextEditingController();
  final _adresse = TextEditingController();
  final _cle = TextEditingController();
  bool _demo = false;
  bool _enCours = false;
  String? _erreur;

  Future<void> _installerCentral() async {
    final etat = Etat.lire(context);
    final code = _code.text.trim().toUpperCase();
    setState(() => _erreur = null);
    if (!RegExp(r'^[A-Z][A-Z0-9]{1,5}$').hasMatch(code)) return setState(() => _erreur = 'Code appareil invalide (ex. PC1).');
    setState(() => _enCours = true);
    try {
      await enregistrerCodeAppareil(code);
      etat.reouvrirAvecCode(code);
      final logo = await logoParDefaut();
      if (_demo) {
        Demo.installerCentral(etat.base!, logo: logo);
        Demo.donneesFictives(etat.base!);
      } else {
        // Ouverture directe : pas de mot de passe à retenir. Le mot de passe
        // administrateur est tiré au hasard ; le comptable pourra en définir
        // un dans Paramétrage s'il active la connexion.
        final r = Random.secure();
        final mdp = List.generate(24, (_) => 'abcdefghjkmnpqrstuvwxyz23456789'[r.nextInt(31)]).join();
        Parametrage.installerPcCentral(etat.base!, motDePasseAdmin: mdp, logo: logo);
      }
      await etat.demarrerServices();
      etat.rafraichir();
    } on RegleMetier catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _rejoindre() async {
    final etat = Etat.lire(context);
    final code = _code.text.trim().toUpperCase();
    setState(() => _erreur = null);
    if (!RegExp(r'^[A-Z][A-Z0-9]{1,5}$').hasMatch(code)) return setState(() => _erreur = 'Code appareil invalide (ex. T01).');
    if (_adresse.text.trim().isEmpty || _cle.text.trim().length < 40) {
      return setState(() => _erreur = "Saisissez l'adresse du PC central et la clé remise par l'administrateur.");
    }
    setState(() => _enCours = true);
    try {
      await enregistrerCodeAppareil(code);
      etat.reouvrirAvecCode(code);
      final b = etat.base!;
      ClientSync.enroler(b, cleSync: _cle.text.trim());
      b.transaction(() => b.exec(
          "INSERT INTO etat_sync(cle, valeur) VALUES ('adresse_central', ?) ON CONFLICT(cle) DO UPDATE SET valeur=excluded.valeur",
          [_adresse.text.trim()]));
      final message = await etat.synchroniser();
      if (!etat.installe) {
        setState(() => _erreur = message);
      } else {
        await etat.demarrerServices();
      }
    } on RegleMetier catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const LogoAh2(),
              const SizedBox(height: 24),
              Text('Installation', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text("Aucune donnée ne quitte les appareils de la structure : pas d'Internet, pas d'hébergement web."),
              const SizedBox(height: 20),
              ChoixPastilles<String>(
                options: const [('central', 'Ce PC est le PC central'), ('appareil', 'Cet appareil rejoint la structure')],
                valeur: _mode,
                onChanged: (v) => setState(() {
                  _mode = v;
                  _code.text = v == 'central' ? 'PC1' : 'T01';
                }),
              ),
              const SizedBox(height: 20),
              if (_mode != null)
                TextField(controller: _code, decoration: const InputDecoration(labelText: "Code de l'appareil (PC1, T01…)")),
              if (_mode == 'central') ...[
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _demo,
                  onChanged: (v) => setState(() => _demo = v),
                  title: const Text('Charger les données de démonstration (fictives)'),
                  subtitle: const Text('Pour essayer : on la quitte ensuite depuis le menu du compte (en haut à droite).'),
                ),
                const SizedBox(height: 4),
                const Text('Le logiciel s’ouvre directement sur le compte du comptable, avec tous les menus. Aucun identifiant ni mot de passe '
                    'n’est demandé ; vous pourrez en exiger un plus tard dans Paramétrage.', style: TextStyle(fontSize: 13)),
              ],
              if (_mode == 'appareil') ...[
                const SizedBox(height: 12),
                TextField(
                    controller: _adresse,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Adresse du PC central sur le Wi-Fi', hintText: 'ex. 192.168.1.10')),
                const SizedBox(height: 12),
                TextField(
                    controller: _cle,
                    decoration: const InputDecoration(
                        labelText: 'Clé de synchronisation',
                        helperText: "Affichée sur le PC central : Paramétrage › Appareils")),
              ],
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Text(_erreur!, style: const TextStyle(color: Couleurs.baisse, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 20),
              if (_mode != null)
                FilledButton(
                  onPressed: _enCours ? null : (_mode == 'central' ? _installerCentral : _rejoindre),
                  child: _enCours
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(_mode == 'central' ? 'Installer le PC central' : 'Rejoindre et synchroniser'),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class LogoAh2 extends StatelessWidget {
  const LogoAh2({super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
        Image.asset('assets/images/logo_ah2.png', width: 64, height: 64),
        const SizedBox(width: 14),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('AH2 Gestion', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text('A Hand to Humanity', style: TextStyle(fontSize: 13)),
        ]),
      ]);
}
