/// Connexion : identifiant personnel + mot de passe, ou code court sur téléphone.
library;

import 'package:material_ui/material_ui.dart';

import '../../noyau/outils.dart';
import '../../noyau/securite.dart';
import '../../noyau/session.dart';
import '../etat_app.dart';
import '../theme.dart';
import 'installation.dart';

class EcranConnexion extends StatefulWidget {
  const EcranConnexion({super.key});
  @override
  State<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends State<EcranConnexion> {
  final _id = TextEditingController();
  final _mdp = TextEditingController();
  bool _visible = false;
  String? _erreur;
  bool _enCours = false;

  Future<void> _connecter() async {
    final etat = Etat.lire(context);
    setState(() {
      _erreur = null;
      _enCours = true;
    });
    // Le calcul de l'empreinte prend un court instant : on laisse l'écran se redessiner.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    try {
      final u = Securite.connecter(etat.base!, _id.text, _mdp.text);
      etat.connecter(Session.depuisLigne(etat.base!, u));
    } on RegleMetier catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    final b = etat.base!;
    final appareil = b.ligne('SELECT * FROM appareils WHERE code=?', [b.appareil]);
    final sync = etat.estCentral ? null : etat.etatSync;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const LogoAh2(),
              const SizedBox(height: 32),
              Text('Connexion', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Appareil ${b.appareil}${appareil != null ? ' · ${appareil['nom']}' : ''}'
                  '${sync != null ? ' · ${sync.libelle(b.maintenant)}' : ''}'),
              const SizedBox(height: 20),
              TextField(
                controller: _id,
                autofillHints: const [AutofillHints.username],
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                keyboardType: TextInputType.visiblePassword,
                decoration: const InputDecoration(labelText: 'Identifiant', prefixIcon: Icon(Icons.person_outline)),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mdp,
                obscureText: !_visible,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                decoration: InputDecoration(
                  labelText: 'Mot de passe ou code court',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _visible ? 'Masquer' : 'Afficher',
                    icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _visible = !_visible),
                  ),
                ),
                onSubmitted: (_) => _connecter(),
              ),
              const SizedBox(height: 12),
              if (b.param('demonstration', '0') == '1')
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Données de démonstration : identifiant « comptable » (ou caisse, direction, admin…), mot de passe « demo1234 ».',
                      style: TextStyle(fontSize: 13)),
                ),
              if (_erreur != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_erreur!, style: const TextStyle(color: Couleurs.baisse, fontWeight: FontWeight.w600)),
                ),
              FilledButton(
                onPressed: _enCours ? null : _connecter,
                child: _enCours
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Se connecter'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
