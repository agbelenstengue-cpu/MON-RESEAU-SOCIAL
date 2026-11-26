/// Utilisateur connecté sur un appareil, et contrôle des droits.
library;

import 'base.dart';
import 'outils.dart';

class Session {
  final Base base;
  final String utilisateur; // id
  final String nom;
  final String role;
  final String? activite;

  Session(this.base, {required this.utilisateur, required this.nom, required this.role, this.activite});

  factory Session.depuisLigne(Base base, Ligne u) => Session(base,
      utilisateur: u['id'] as String,
      nom: u['nom'] as String,
      role: u['role'] as String,
      activite: u['activite'] as String?);

  /// Ouvre une session pour l'utilisateur [identifiant] sans mot de passe
  /// (usage interne : tests, données de démonstration).
  factory Session.pour(Base base, String identifiant) {
    final u = base.ligne('SELECT * FROM utilisateurs WHERE identifiant=?', [identifiant]);
    if (u == null) throw RegleMetier('Utilisateur inconnu : $identifiant');
    return Session.depuisLigne(base, u);
  }

  bool peut(String module, String action) =>
      base.valeur('SELECT 1 FROM droits WHERE role=? AND module=? AND action=?',
          [role, module, action]) !=
      null;

  static const _verbes = {
    'voir': 'consulter',
    'creer': 'saisir',
    'valider': 'valider',
    'annuler': 'annuler',
  };

  void exiger(String module, String action) {
    if (!peut(module, action)) {
      throw DroitRefuse(
          "Vous n'avez pas le droit de ${_verbes[action] ?? action} dans le module « $module ».");
    }
  }
}
