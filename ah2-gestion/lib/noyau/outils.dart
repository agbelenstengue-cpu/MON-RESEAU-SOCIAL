/// Outils communs : erreurs métier, formats français (FCFA, JJ/MM/AAAA).
library;

/// Erreur levée quand une règle de gestion est violée.
/// Le message est rédigé en français, prêt à être affiché à l'utilisateur.
class RegleMetier implements Exception {
  final String message;
  const RegleMetier(this.message);
  @override
  String toString() => message;
}

/// Erreur de droits : l'utilisateur n'a pas l'autorisation demandée.
class DroitRefuse extends RegleMetier {
  const DroitRefuse(super.message);
}

/// Formate un montant entier en FCFA : 185000 -> "185 000 FCFA".
String fcfa(int montant, {bool unite = true}) {
  final negatif = montant < 0;
  final chiffres = montant.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) buf.write(' ');
    buf.write(chiffres[i]);
  }
  return '${negatif ? '-' : ''}$buf${unite ? ' FCFA' : ''}';
}

String _d2(int n) => n.toString().padLeft(2, '0');

/// Date au format JJ/MM/AAAA.
String dateFr(DateTime d) => '${_d2(d.day)}/${_d2(d.month)}/${d.year}';

/// Heure au format HH:MM.
String heureFr(DateTime d) => '${_d2(d.hour)}:${_d2(d.minute)}';

/// Date ISO (AAAA-MM-JJ) utilisée en base.
String dateIso(DateTime d) => '${d.year}-${_d2(d.month)}-${_d2(d.day)}';

/// Convertit une date ISO en DateTime (minuit UTC, pour des calculs de jours exacts).
DateTime depuisIso(String iso) {
  final p = iso.substring(0, 10).split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

/// Convertit "JJ/MM/AAAA" en date ISO.
String isoDepuisFr(String fr) {
  final p = fr.split('/');
  return '${p[2]}-${p[1].padLeft(2, '0')}-${p[0].padLeft(2, '0')}';
}

/// Nombre de jours entre deux dates ISO (b - a).
int joursEntre(String a, String b) =>
    depuisIso(b).difference(depuisIso(a)).inDays;

/// Ajoute des jours à une date ISO.
String ajouterJours(String iso, int jours) =>
    dateIso(depuisIso(iso).add(Duration(days: jours)));
