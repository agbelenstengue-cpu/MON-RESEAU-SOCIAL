/// Mes documents : tous les reçus, rapports, états et exports produits sur
/// cet appareil, à rouvrir, enregistrer ou partager.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../noyau/outils.dart';
import '../widgets/commun.dart';
import '../widgets/enregistrer_fichier.dart';
import '../widgets/formulaire.dart';
import '../widgets/pdf_ui.dart';

class EcranMesDocuments extends StatefulWidget {
  const EcranMesDocuments({super.key});
  @override
  State<EcranMesDocuments> createState() => _EcranMesDocumentsState();
}

class _EcranMesDocumentsState extends State<EcranMesDocuments> {
  List<File>? _fichiers;
  String _filtre = '';

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final d = await dossierMesDocuments().timeout(const Duration(seconds: 5));
      final f = d.listSync().whereType<File>().toList()..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (mounted) setState(() => _fichiers = f);
    } catch (_) {
      if (mounted) setState(() => _fichiers = []);
    }
  }

  String _nom(File f) => f.uri.pathSegments.last;

  Future<void> _ouvrir(File f) async {
    final octets = await f.readAsBytes();
    if (!mounted) return;
    final nom = _nom(f);
    if (nom.toLowerCase().endsWith('.pdf')) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VisionneusePdf(octets: octets, nom: nom.substring(0, nom.length - 4))));
    } else {
      await enregistrerFichier(context, octets, nom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _fichiers;
    if (f == null) return const Center(child: CircularProgressIndicator());
    final visibles = f.where((x) => _nom(x).toLowerCase().contains(_filtre.toLowerCase())).toList();
    return PageContenu(enfants: [
      const TitreSection('Mes documents', sousTitre: 'Chaque document affiché ou exporté est gardé ici.'),
      const SizedBox(height: 12),
      TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un document'), onChanged: (v) => setState(() => _filtre = v)),
      const SizedBox(height: 12),
      if (visibles.isEmpty)
        const EtatVide('Aucun document pour le moment. Affichez un rapport ou un reçu : il sera gardé ici.', icone: Icons.folder_open_outlined)
      else
        Card(
          child: Column(children: [
            for (final x in visibles)
              ListTile(
                leading: Icon(_nom(x).toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_outlined : Icons.table_chart_outlined),
                title: Text(_nom(x), overflow: TextOverflow.ellipsis),
                subtitle: Text('${dateFr(x.lastModifiedSync())} ${heureFr(x.lastModifiedSync())} · ${(x.lengthSync() / 1024).ceil()} Ko'),
                onTap: () => _ouvrir(x),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    final octets = await x.readAsBytes();
                    if (!context.mounted) return;
                    switch (v) {
                      case 'enregistrer':
                        await enregistrerSous(context, octets, _nom(x));
                      case 'partager':
                        await partagerFichier(octets, _nom(x));
                      case 'retirer':
                        if (await confirmer(context, 'Retirer ${_nom(x)} de Mes documents ? (Les données du logiciel ne changent pas.)')) {
                          x.deleteSync();
                          _charger();
                        }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'enregistrer', child: Text('Enregistrer dans un dossier')),
                    PopupMenuItem(value: 'partager', child: Text('Partager')),
                    PopupMenuItem(value: 'retirer', child: Text('Retirer de la liste')),
                  ],
                ),
              ),
          ]),
        ),
    ]);
  }
}
