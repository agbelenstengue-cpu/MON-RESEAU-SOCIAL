/// État global de l'application : base locale, utilisateur connecté,
/// synchronisation, préférences d'affichage.
library;

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../modules/parametrage/parametrage.dart';
import '../noyau/base.dart';
import '../noyau/session.dart';
import '../sync/synchronisation.dart';
import '../sync/transport_http.dart';

class EtatApp extends ChangeNotifier {
  Base? base;
  String? cheminBase;
  Session? session;
  ThemeMode modeTheme = ThemeMode.system;
  double tailleTexte = 1.0;
  bool revoque = false;

  ServeurHttpSync? _serveur;
  Timer? _minuteurSync;
  Timer? _minuteurInactivite;
  bool synchronisationEnCours = false;
  String? derniereErreurSync;

  bool get installe => base != null && base!.entier('SELECT COUNT(*) FROM appareils') > 0;
  bool get estCentral => base != null && Parametrage.estCentral(base!);
  bool get enrole => base?.valeur("SELECT valeur FROM etat_sync WHERE cle='cle_sync'") != null;

  String? _cle;

  void ouvrir(Base b, String? chemin, {String? cle}) {
    base = b;
    cheminBase = chemin;
    _cle = cle;
    notifyListeners();
  }

  /// Rouvre la base sous le code d'appareil choisi à l'installation.
  void reouvrirAvecCode(String code) {
    base?.fermer();
    base = Base.ouvrir(chemin: cheminBase, appareil: code, cle: _cle);
    notifyListeners();
  }

  /// Démarre le service réseau (PC central) ou la synchronisation automatique (appareil).
  Future<void> demarrerServices() async {
    final b = base;
    if (b == null || !installe) return;
    if (estCentral) {
      if (_serveur == null) {
        _serveur = ServeurHttpSync(ServeurSync(b));
        try {
          await _serveur!.demarrer();
        } catch (e) {
          derniereErreurSync = 'Service de synchronisation indisponible : $e';
          _serveur = null;
        }
      }
    } else {
      _minuteurSync ??= Timer.periodic(const Duration(minutes: 2), (_) => synchroniser(silencieux: true));
    }
  }

  String? get adresseCentral => base?.valeur("SELECT valeur FROM etat_sync WHERE cle='adresse_central'") as String?;

  ClientSync? _client() {
    final b = base;
    final adresse = adresseCentral;
    if (b == null || adresse == null || estCentral) return null;
    return ClientSync(b, transport: transportHttp(adresse), effacerDonnees: _effacer);
  }

  void _effacer() {
    final chemin = cheminBase;
    base?.fermer();
    base = null;
    session = null;
    revoque = true;
    if (chemin != null) {
      for (final s in ['', '-wal', '-shm']) {
        final f = File('$chemin$s');
        if (f.existsSync()) f.deleteSync();
      }
    }
    notifyListeners();
  }

  /// Synchronise si le PC central est joignable (Wi-Fi de la structure).
  Future<String> synchroniser({bool silencieux = false}) async {
    final client = _client();
    if (client == null || synchronisationEnCours) return 'Rien à synchroniser.';
    synchronisationEnCours = true;
    notifyListeners();
    try {
      if (!await centralJoignable(adresseCentral!)) {
        derniereErreurSync = 'PC central injoignable (êtes-vous sur le Wi-Fi de la structure ?)';
        return derniereErreurSync!;
      }
      final r = await client.synchroniser();
      derniereErreurSync = null;
      return 'Synchronisé : ${r.envoyees} envoyée(s), ${r.recues} reçue(s).';
    } on AppareilRevoque catch (e) {
      return e.message;
    } catch (e) {
      derniereErreurSync = '$e';
      return derniereErreurSync!;
    } finally {
      synchronisationEnCours = false;
      notifyListeners();
    }
  }

  EtatSync? get etatSync => base == null ? null : ClientSync.etat(base!);

  void connecter(Session s) {
    session = s;
    signalerActivite();
    notifyListeners();
  }

  void deconnecter() {
    session = null;
    _minuteurInactivite?.cancel();
    notifyListeners();
  }

  /// Déconnexion automatique après inactivité (paramètre).
  void signalerActivite() {
    _minuteurInactivite?.cancel();
    final b = base;
    if (b == null || session == null) return;
    _minuteurInactivite = Timer(Duration(minutes: b.paramInt('inactivite_minutes', 10)), deconnecter);
  }

  /// À appeler après chaque opération : rafraîchit les écrans.
  void rafraichir() => notifyListeners();

  void changerTheme(ThemeMode m) {
    modeTheme = m;
    notifyListeners();
  }

  void changerTailleTexte(double t) {
    tailleTexte = t;
    notifyListeners();
  }
}

/// Accès à l'état depuis l'arbre de widgets.
class Etat extends InheritedNotifier<EtatApp> {
  const Etat({super.key, required EtatApp etat, required super.child}) : super(notifier: etat);

  static EtatApp de(BuildContext context) => context.dependOnInheritedWidgetOfExactType<Etat>()!.notifier!;
  static EtatApp lire(BuildContext context) => context.getInheritedWidgetOfExactType<Etat>()!.notifier!;
}
