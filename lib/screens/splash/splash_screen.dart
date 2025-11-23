import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doa_repartos/core/session/session_manager.dart';
import 'package:doa_repartos/core/session/user_session.dart';
import 'package:doa_repartos/services/navigation_service.dart';
import 'package:doa_repartos/widgets/app_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.9, end: 1.0)
        .chain(CurveTween(curve: Curves.easeOutBack))
        .animate(_controller);

    // Start the animation
    _controller.forward();

    // Hold the splash screen longer to ensure everything is loaded
    _timer = Timer(const Duration(milliseconds: 2000), _goNext);
  }

  Future<void> _goNext() async {
    if (!mounted) return;

    final sessionManager = SessionManager.instance;

    // Esperar a que el SessionManager termine de inicializar (máx 5s)
    if (sessionManager.state == SessionState.initializing) {
      try {
        await sessionManager.stateStream
            .firstWhere((s) => s != SessionState.initializing)
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        debugPrint('⏱️ [SPLASH] SessionManager initialization timeout');
      }
    }
    if (!mounted) return;

    // Esperar a que todas las imágenes y recursos estén precargados
    try {
      await Future.wait([
        // Precarga del logo si existe
        precacheImage(const AssetImage('assets/images/donna_logo.png'), context),
        // Dar tiempo adicional para que otros componentes se inicialicen
        Future.delayed(const Duration(milliseconds: 500)),
      ]);
    } catch (e) {
      debugPrint('⚠️ [SPLASH] Error precargando recursos: $e');
    }
    if (!mounted) return;

    // Decidir destino: si hay sesión activa, navegar según rol; si no, ir a login
    if (sessionManager.hasActiveSession) {
      // Delay para transición suave
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      await NavigationService.navigateByRole(
        context,
        sessionManager.currentSession.role,
        userData: sessionManager.currentSession.userData,
      );
    } else {
      // Delay para transición suave
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary.withValues(alpha: 0.10),
              colorScheme.secondary.withValues(alpha: 0.10),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Soft radial highlight behind the logo
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: CustomPaint(
                  painter: _RadialGlowPainter(
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),

            // Centered animated logo
            Center(
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: const AppLogo(size: 140, showTitle: true, title: 'Doña Repartos'),
                ),
              ),
            ),

            // Bottom subtle progress indicator
            Positioned(
              left: 0,
              right: 0,
              bottom: 64,
              child: Opacity(
                opacity: 0.7,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cargando...',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadialGlowPainter extends CustomPainter {
  final Color color;
  const _RadialGlowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.45);
    final radius = size.shortestSide * 0.45;

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.25),
          color.withValues(alpha: 0.05),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _RadialGlowPainter oldDelegate) =>
      oldDelegate.color != color;
}
