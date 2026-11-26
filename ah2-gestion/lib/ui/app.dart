/// Racine de l'application : installation, connexion, puis espace de travail.
library;

import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;
import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:material_ui/material_ui.dart';

import 'ecrans/connexion.dart';
import 'ecrans/coquille.dart';
import 'ecrans/installation.dart';
import 'etat_app.dart';
import 'theme.dart';

class Ah2App extends StatelessWidget {
  final EtatApp etat;
  const Ah2App({super.key, required this.etat});

  @override
  Widget build(BuildContext context) => Etat(
        etat: etat,
        child: ListenableBuilder(
          listenable: etat,
          builder: (context, _) => MaterialApp(
            title: 'AH2 Gestion',
            debugShowCheckedModeBanner: false,
            theme: themeAh2(Brightness.light),
            darkTheme: themeAh2(Brightness.dark),
            themeMode: etat.modeTheme,
            locale: const Locale('fr', 'FR'),
            supportedLocales: const [Locale('fr', 'FR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(etat.tailleTexte)),
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => etat.signalerActivite(),
                child: child!,
              ),
            ),
            home: const _Aiguillage(),
          ),
        ),
      );
}

class _Aiguillage extends StatelessWidget {
  const _Aiguillage();

  @override
  Widget build(BuildContext context) {
    final etat = Etat.de(context);
    if (etat.revoque) return const _Revoque();
    if (!etat.installe) return const EcranInstallation();
    if (etat.session == null) return const EcranConnexion();
    return const Coquille();
  }
}

class _Revoque extends StatelessWidget {
  const _Revoque();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.phonelink_lock, size: 56),
              SizedBox(height: 16),
              Text('Appareil révoqué', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text("Cet appareil a été révoqué par l'administrateur. Ses données locales ont été effacées.",
                  textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
}
