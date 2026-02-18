import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:doa_repartos/services/mercadopago_service.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'dart:html' as html;

/// Pantalla de checkout con MercadoPago
/// 
/// Muestra el checkout de MercadoPago en un WebView y maneja:
/// 1. Callbacks de success/failure/pending
/// 2. Actualización automática del estado del pago en Supabase
/// 3. Navegación de regreso con resultado
class MercadoPagoCheckoutScreen extends StatefulWidget {
  final String orderId; // Puede estar vacío si se crea después del pago
  final double totalAmount;
  final double? clientDebt;
  final String description;
  final String clientEmail;
  final Map<String, dynamic>? orderData; // Datos para crear orden tras pago exitoso

  const MercadoPagoCheckoutScreen({
    super.key,
    required this.orderId,
    required this.totalAmount,
    this.clientDebt,
    required this.description,
    required this.clientEmail,
    this.orderData,
  });

  @override
  State<MercadoPagoCheckoutScreen> createState() => _MercadoPagoCheckoutScreenState();
}

class _MercadoPagoCheckoutScreenState extends State<MercadoPagoCheckoutScreen> {
  late Future<WebViewController?> _controllerFuture;
  bool _isPageLoading = true;
  final bool _isWebPlatform = kIsWeb;

  @override
  void initState() {
    super.initState();
    _controllerFuture = _initializePayment();
  }

  /// Crea la preferencia de pago y retorna el WebViewController configurado
  /// Lanza excepción si hay error - el FutureBuilder lo maneja
  /// En web, retorna null (no se usa WebView)
  Future<WebViewController?> _initializePayment() async {
    try {
      debugPrint('💳 [MP_CHECKOUT] Creando preferencia de pago...');
      
      final result = await MercadoPagoService.createPaymentPreference(
        orderId: widget.orderId,
        totalAmount: widget.totalAmount,
        clientDebt: widget.clientDebt,
        description: widget.description,
        clientEmail: widget.clientEmail,
        orderData: widget.orderData,
      );

      if (!result['success']) {
        throw Exception(result['error'] ?? 'Error desconocido');
      }

      final initPoint = result['init_point'] as String;
      debugPrint('✅ [MP_CHECKOUT] Init point: $initPoint');
      
      // En web, abrir en nueva pestaña y NO retornar controller
      if (kIsWeb) {
        debugPrint('🌐 [MP_CHECKOUT] Abriendo MercadoPago en nueva pestaña (Web)');
        html.window.open(initPoint, '_blank');
        
        // Retornar null - en web no usamos WebView
        return null;
      }
      
      // En móvil, usar WebView nativo
      debugPrint('📱 [MP_CHECKOUT] Inicializando WebView nativo (Móvil)');
      
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              debugPrint('🌐 [MP_CHECKOUT] Page started: $url');
            },
            onPageFinished: (url) {
              debugPrint('🌐 [MP_CHECKOUT] Page finished: $url');
              if (mounted) {
                setState(() => _isPageLoading = false);
              }
            },
            onNavigationRequest: (request) {
              final url = request.url;
              debugPrint('🌐 [MP_CHECKOUT] Navigation request: $url');

              // Detectar callbacks de MercadoPago
              if (url.contains('/payment/success') || url.contains('status=approved')) {
                _handlePaymentSuccess();
                return NavigationDecision.prevent;
              } else if (url.contains('/payment/failure') || url.contains('status=rejected')) {
                _handlePaymentFailure();
                return NavigationDecision.prevent;
              } else if (url.contains('/payment/pending') || url.contains('status=pending')) {
                _handlePaymentPending();
                return NavigationDecision.prevent;
              }

              return NavigationDecision.navigate;
            },
            onWebResourceError: (error) {
              debugPrint('❌ [MP_CHECKOUT] WebView error: ${error.description}');
            },
          ),
        )
        ..loadRequest(Uri.parse(initPoint));

      return controller;
    } catch (e) {
      debugPrint('❌ [MP_CHECKOUT] Error al crear preferencia: $e');
      rethrow; // El FutureBuilder captura esto
    }
  }

  void _handlePaymentSuccess() async {
    debugPrint('✅ [MP_CHECKOUT] Pago exitoso');
    
    // Si hay orderData, significa que debemos obtener el order_id creado por el webhook
    if (widget.orderData != null) {
      debugPrint('🔍 [MP_CHECKOUT] Buscando orden creada por webhook...');
      
      final userId = widget.orderData!['user_id'] as String;
      final restaurantId = widget.orderData!['restaurant_id'] as String;
      
      // Reintentar hasta 8 veces (16 segundos total) - dar más tiempo al webhook
      String? orderId;
      for (int attempt = 1; attempt <= 8; attempt++) {
        debugPrint('🔍 [MP_CHECKOUT] Intento $attempt/8...');
        
        try {
          // Buscar orden recién creada por el webhook
          // Buscar la más reciente creada en los últimos 60 segundos
          final now = DateTime.now();
          final oneMinuteAgo = now.subtract(const Duration(seconds: 60));
          
          final response = await SupabaseConfig.client
              .from('orders')
              .select('id, created_at, status')
              .eq('user_id', userId)
              .eq('restaurant_id', restaurantId)
              .eq('payment_method', 'card')
              .gte('created_at', oneMinuteAgo.toIso8601String())
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          
          if (response != null && response['id'] != null) {
            orderId = response['id'] as String;
            debugPrint('✅ [MP_CHECKOUT] Orden encontrada: $orderId (status: ${response['status']})');
            break; // Salir del loop
          }
        } catch (e) {
          debugPrint('⚠️ [MP_CHECKOUT] Error en intento $attempt: $e');
        }
        
        // Si no es el último intento, esperar antes de reintentar
        if (attempt < 8) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
      
      if (mounted) {
        if (orderId != null) {
          Navigator.of(context).pop({
            'success': true,
            'status': 'approved',
            'message': 'Pago procesado exitosamente',
            'order_id': orderId,
          });
        } else {
          debugPrint('❌ [MP_CHECKOUT] No se encontró la orden después de 8 intentos (16 segundos)');
          debugPrint('⚠️ [MP_CHECKOUT] El webhook puede estar tardando más de lo esperado');
          Navigator.of(context).pop({
            'success': true,
            'status': 'pending',
            'message': 'Tu pago fue procesado. La orden aparecerá en "Mis Pedidos" en unos momentos.',
          });
        }
      }
    } else {
      // Orden ya existía (flujo antiguo)
      if (mounted) {
        Navigator.of(context).pop({
          'success': true,
          'status': 'approved',
          'message': 'Pago procesado exitosamente',
          'order_id': widget.orderId,
        });
      }
    }
  }

  void _handlePaymentFailure() {
    debugPrint('❌ [MP_CHECKOUT] Pago rechazado');
    if (mounted) {
      Navigator.of(context).pop({
        'success': false,
        'status': 'rejected',
        'message': 'El pago fue rechazado. Intenta con otro método de pago.',
      });
    }
  }

  void _handlePaymentPending() {
    debugPrint('⏳ [MP_CHECKOUT] Pago pendiente');
    if (mounted) {
      Navigator.of(context).pop({
        'success': true,
        'status': 'pending',
        'message': 'Tu pago está siendo procesado. Te notificaremos cuando se confirme.',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Pago con MercadoPago'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            Navigator.of(context).pop({
              'success': false,
              'status': 'cancelled',
              'message': 'Pago cancelado por el usuario',
            });
          },
        ),
      ),
      body: FutureBuilder<WebViewController?>(
        future: _controllerFuture,
        builder: (context, snapshot) {
          // Estado: Cargando
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingView();
          }

          // Estado: Error
          if (snapshot.hasError) {
            return _buildErrorView(snapshot.error.toString());
          }

          // Estado: Completado
          if (snapshot.connectionState == ConnectionState.done) {
            // En web, snapshot.data será null - mostrar instrucciones
            if (_isWebPlatform || snapshot.data == null) {
              return _buildWebInstructions();
            }
            
            // En móvil, mostrar WebView con el controller
            return Stack(
              children: [
                WebViewWidget(controller: snapshot.data!),
                if (_isPageLoading) _buildLoadingView(),
              ],
            );
          }

          // Estado: Otro (nunca debería llegar aquí)
          return _buildLoadingView();
        },
      ),
    );
  }

  Widget _buildLoadingView() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Cargando checkout de MercadoPago...',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String errorMessage) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error al cargar el checkout',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isPageLoading = true;
                  _controllerFuture = _initializePayment();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Reintentar'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop({
                  'success': false,
                  'status': 'error',
                  'message': errorMessage,
                });
              },
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebInstructions() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.open_in_new,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Checkout Abierto en Nueva Pestaña',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'El checkout de MercadoPago se ha abierto en una nueva pestaña de tu navegador.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Completa el pago allí y regresa a esta pantalla.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                // Buscar orden creada tras pago
                if (widget.orderData != null) {
                  _handlePaymentSuccess();
                } else {
                  Navigator.of(context).pop({
                    'success': true,
                    'status': 'pending',
                    'message': 'Verifica el estado de tu pago en "Mis Pedidos"',
                    'order_id': widget.orderId,
                  });
                }
              },
              icon: const Icon(Icons.check),
              label: const Text('Ya completé el pago'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop({
                  'success': false,
                  'status': 'cancelled',
                  'message': 'Pago cancelado',
                });
              },
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
