/// Déclaration de tous les modules (un module par domaine du §6).
library;

import '../noyau/operations.dart';
import 'actes/actes.dart';
import 'cloture/cloture.dart';
import 'desintox/desintox.dart';
import 'dons/dons.dart';
import 'patients/patients.dart';
import 'releves/releves.dart';
import 'tresorerie/tresorerie.dart';

bool _fait = false;

/// À appeler une fois au démarrage (et avant toute synchronisation).
void initialiserModules() {
  if (_fait) return;
  _fait = true;
  Operations.initialiser();
  Patients.declarer();
  Tresorerie.declarer();
  Actes.declarer();
  Desintox.declarer();
  Dons.declarer();
  Cloture.declarer();
  Releves.declarer();
}
