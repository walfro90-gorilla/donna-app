import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Política de Privacidad'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Última actualización: ${DateTime.now().year}-01-01',
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Resumen',
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Esta Política de Privacidad describe cómo Doña Repartos ("nosotros", "la plataforma") recopila, utiliza y protege la información personal de los usuarios de nuestra aplicación. Al utilizar la aplicación, aceptas esta política.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              _Section(
                title: 'Datos que recopilamos',
                paragraphs: const [
                  '• Datos de cuenta: nombre, correo electrónico, número de teléfono.',
                  '• Datos transaccionales: pedidos, direcciones de entrega, métodos de pago (tokenizados).',
                  '• Datos técnicos: dispositivo, sistema operativo, dirección IP y datos de uso (analítica).',
                  '• Ubicación: cuando otorgas permiso, para mostrar restaurantes cercanos y mejorar entregas.',
                ],
              ),
              _Section(
                title: 'Cómo usamos tus datos',
                paragraphs: const [
                  '• Proveer el servicio: crear y gestionar tu cuenta, procesar pedidos y pagos.',
                  '• Seguridad y prevención de fraudes, cumplimiento de términos y de la ley.',
                  '• Soporte al cliente y comunicaciones importantes sobre tu cuenta y pedidos.',
                  '• Analítica para mejorar rendimiento, calidad y experiencia del usuario.',
                ],
              ),
              _Section(
                title: 'Compartición de datos',
                paragraphs: const [
                  '• Restaurantes y repartidores reciben solo la información necesaria para preparar y entregar tu pedido.',
                  '• Proveedores tecnológicos (por ejemplo, hosting, analítica, pasarelas de pago) bajo contratos de confidencialidad.',
                  '• Autoridades cuando la ley lo requiera.',
                ],
              ),
              _Section(
                title: 'Tus derechos',
                paragraphs: const [
                  '• Acceso, rectificación y eliminación de datos cuando aplique.',
                  '• Revocar consentimientos (por ejemplo, ubicación) desde los ajustes del dispositivo.',
                  '• Oposición y limitación del tratamiento en los supuestos previstos por la normativa vigente.',
                ],
              ),
              _Section(
                title: 'Conservación y seguridad',
                paragraphs: const [
                  '• Conservamos los datos el tiempo necesario para prestar el servicio y cumplir obligaciones legales.',
                  '• Implementamos medidas de seguridad razonables para proteger la información. Ningún sistema es 100% infalible.',
                ],
              ),
              _Section(
                title: 'Contacto',
                paragraphs: const [
                  'Si tienes dudas o solicitudes sobre privacidad, contáctanos en: soporte@donarepartos.app',
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Esta página se publica para cumplir con requisitos de plataformas de terceros (incluido Facebook Login) y proporcionar transparencia a los usuarios.',
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<String> paragraphs;
  const _Section({required this.title, required this.paragraphs});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...paragraphs.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  p,
                  style: textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
