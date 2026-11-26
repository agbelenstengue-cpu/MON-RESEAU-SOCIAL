/// Logo animé à l'ouverture : court (environ 1,5 s), sobre, et on peut le
/// passer d'un simple toucher.
library;

import 'package:material_ui/material_ui.dart';

class LogoAnime extends StatefulWidget {
  final VoidCallback fini;
  const LogoAnime({super.key, required this.fini});
  @override
  State<LogoAnime> createState() => _LogoAnimeState();
}

class _LogoAnimeState extends State<LogoAnime> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  bool _termine = false;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_terminer);
  }

  void _terminer() {
    if (_termine) return;
    _termine = true;
    widget.fini();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final apparition = CurvedAnimation(parent: _c, curve: const Interval(0, 0.55, curve: Curves.easeOutCubic));
    final texte = CurvedAnimation(parent: _c, curve: const Interval(0.35, 0.85, curve: Curves.easeOut));
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _terminer,
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
              Opacity(
                opacity: apparition.value,
                child: Transform.scale(
                  scale: 0.82 + 0.18 * apparition.value,
                  child: Image.asset('assets/images/logo_ah2.png', width: 150, height: 150),
                ),
              ),
              const SizedBox(height: 20),
              Opacity(
                opacity: texte.value,
                child: Transform.translate(
                  offset: Offset(0, 8 * (1 - texte.value)),
                  child: const Column(children: [
                    Text('AH2 Gestion', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                    SizedBox(height: 4),
                    Text('A Hand to Humanity', style: TextStyle(fontSize: 14)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
