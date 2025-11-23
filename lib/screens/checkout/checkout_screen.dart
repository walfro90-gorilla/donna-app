import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/screens/checkout/order_confirmation_screen.dart';
import 'package:doa_repartos/screens/checkout/card_payment_form_screen.dart';
import 'package:doa_repartos/services/places_service.dart';
import 'package:doa_repartos/widgets/address_picker_modal.dart';
import 'package:doa_repartos/services/realtime_service.dart';
import 'dart:async';
import 'package:doa_repartos/widgets/address_search_field.dart';
import 'dart:convert';
import 'package:doa_repartos/core/supabase/supabase_rpc.dart';
import 'package:doa_repartos/core/supabase/rpc_names.dart';
import 'package:doa_repartos/widgets/phone_dial_input.dart';

class CheckoutScreen extends StatefulWidget {
  final DoaRestaurant restaurant;
  final Map<String, int> cartItems;
  final List<DoaProduct> products;

  const CheckoutScreen({
    super.key,
    required this.restaurant,
    required this.cartItems,
    required this.products,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  
  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  bool _isProcessingOrder = false;
  bool _hasActiveCouriers = true;
  StreamSubscription<void>? _couriersUpdatesSubscription;
  // UX: Mensaje inferior pegajoso para indicar qué falta completar
  String? _stickyWarning;
  // Control de adeudo del cliente
  double _clientTotalDebt = 0.0;
  bool _isLoadingDebt = true;
  // Debounce para guardar teléfono en usuarios al editar
  Timer? _phoneDebounce;
  // Validación asíncrona de teléfono único
  bool _isPhoneValidating = false;
  String? _phoneErrorText; // Texto de error visible bajo el campo
  bool _isPhoneUnique = true; // Para bloquear el pedido cuando esté en uso

  // Google Places selected data
  String? _deliveryPlaceId;
  double? _deliveryLat;
  double? _deliveryLon;
  Map<String, dynamic>? _deliveryAddressStructured;
  String? _placesSessionToken;
  String? _lastSelectedAddress;
  
  // Fixed delivery fee - you can make this dynamic later
  static const double _deliveryFee = 35.0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadClientDebt();
    _placesSessionToken = PlacesService.newSessionToken();
    _initCourierGate();
    // Si el usuario edita manualmente tras seleccionar desde Google, invalidamos la selección
    _addressController.addListener(() {
      final current = _addressController.text.trim();
      if (_lastSelectedAddress == null) return;
      if (current != _lastSelectedAddress) {
        _deliveryPlaceId = null;
        _deliveryLat = null;
        _deliveryLon = null;
        _deliveryAddressStructured = null;
      }
    });
  }

  Future<void> _initCourierGate() async {
    try {
      final hasCouriers = await DoaRepartosService.hasActiveCouriers();
      if (mounted) setState(() => _hasActiveCouriers = hasCouriers);
    } catch (_) {}

    final user = SupabaseAuth.currentUser;
    if (user != null) {
      final realtime = RealtimeNotificationService.forUser(user.id);
      _couriersUpdatesSubscription = realtime.couriersUpdated.listen((_) async {
        final hasCouriers = await DoaRepartosService.hasActiveCouriers();
        if (!mounted) return;
        setState(() => _hasActiveCouriers = hasCouriers);
        if (!hasCouriers) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay repartidores activos. No es posible procesar pedidos por ahora.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    }
  }

  Future<void> _loadClientDebt() async {
    final user = SupabaseAuth.currentUser;
    if (user == null) return;

    try {
      debugPrint('💰 [CHECKOUT._loadClientDebt] Consultando adeudo del cliente...');
      final response = await SupabaseRpc.call(
        'get_client_total_debt',
        params: {'p_client_id': user.id},
      );

      if (!response.success) {
        throw Exception(response.error ?? 'Error al consultar adeudo');
      }

      final debt = (response.data as num?)?.toDouble() ?? 0.0;
      debugPrint('💰 [CHECKOUT._loadClientDebt] Adeudo total: \$${debt.toStringAsFixed(2)} MXN');

      if (mounted) {
        setState(() {
          _clientTotalDebt = debt;
          _isLoadingDebt = false;
          // Si tiene deuda, forzar pago con tarjeta
          if (_clientTotalDebt > 0) {
            _selectedPaymentMethod = PaymentMethod.card;
            debugPrint('⚠️ [CHECKOUT._loadClientDebt] Cliente con adeudo: forzando pago con tarjeta');
          }
        });
      }
    } catch (e) {
      debugPrint('❌ [CHECKOUT._loadClientDebt] Error al cargar adeudo: \$e');
      if (mounted) {
        setState(() {
          _clientTotalDebt = 0.0;
          _isLoadingDebt = false;
        });
      }
    }
  }

  Future<void> _loadUserData() async {
    final user = SupabaseAuth.currentUser;
    if (user != null) {
      try {
        debugPrint('📖 [CHECKOUT._loadUserData] Cargando datos del usuario: ${user.id}');
        final userData = await DoaRepartosService.getUserById(user.id);
        debugPrint('📖 [CHECKOUT._loadUserData] Datos recibidos: $userData');
        
        if (userData != null && mounted) {
          // Conversores seguros a double
          double? _toDouble(dynamic v) {
            if (v == null) return null;
            if (v is num) return v.toDouble();
            return double.tryParse(v.toString());
          }

          final Map<String, dynamic> profile = (userData['client_profiles'] is Map)
              ? Map<String, dynamic>.from(userData['client_profiles'])
              : <String, dynamic>{};

          debugPrint('📖 [CHECKOUT._loadUserData] client_profiles: $profile');

          final String address = (profile['address'] ?? userData['address'] ?? '').toString();
          final String phone = (userData['phone'] ?? '').toString();
          final double? lat = _toDouble(profile['lat'] ?? userData['lat']);
          final double? lon = _toDouble(profile['lon'] ?? userData['lon']);
          final Map<String, dynamic>? structured = (profile['address_structured'] is Map)
              ? Map<String, dynamic>.from(profile['address_structured'])
              : (userData['address_structured'] is Map)
                  ? Map<String, dynamic>.from(userData['address_structured'])
                  : null;

          debugPrint('📖 [CHECKOUT._loadUserData] Valores extraídos:');
          debugPrint('   - address: $address');
          debugPrint('   - phone: $phone');
          debugPrint('   - lat: $lat');
          debugPrint('   - lon: $lon');
          debugPrint('   - structured: $structured');

          setState(() {
            // Prefill visual fields
            _addressController.text = address;
            _phoneController.text = phone;

            // Importante: si ya existe lat/lon guardados en perfil, úsalos para pasar validación
            _deliveryLat = lat;
            _deliveryLon = lon;
            _deliveryAddressStructured = structured;
            _deliveryPlaceId = null; // Desconocido al cargar desde perfil
            _lastSelectedAddress = address.isNotEmpty ? address : null;
          });
          
          debugPrint('✅ [CHECKOUT._loadUserData] Estado actualizado con coordenadas: lat=$_deliveryLat, lon=$_deliveryLon');
        } else {
          debugPrint('⚠️ [CHECKOUT._loadUserData] No se encontraron datos del usuario');
        }
      } catch (e) {
        debugPrint('❌ [CHECKOUT._loadUserData] Error: $e');
      }
    }
  }

  Future<void> _updateUserData() async {
    final user = SupabaseAuth.currentUser;
    if (user != null) {
      try {
        debugPrint('🔄 [CHECKOUT._updateUserData] ===== INICIO =====');
        
        // Siempre actualizamos el teléfono
        final phone = _phoneController.text.trim();
        if (phone.isNotEmpty && _isPhoneUnique) {
          debugPrint('📞 [CHECKOUT._updateUserData] Actualizando teléfono: $phone');
          await DoaRepartosService.updateUserProfile(user.id, {'phone': phone});
        }

        // Dirección y geolocalización -> guardar en client_profiles (nuevo esquema)
        final address = _addressController.text.trim();
        debugPrint('📍 [CHECKOUT._updateUserData] Guardando ubicación:');
        debugPrint('   - userId: ${user.id}');
        debugPrint('   - address: $address');
        debugPrint('   - lat: $_deliveryLat');
        debugPrint('   - lon: $_deliveryLon');
        debugPrint('   - addressStructured: $_deliveryAddressStructured');
        
        final ok = await DoaRepartosService.updateClientDefaultAddress(
          userId: user.id,
          address: address,
          lat: _deliveryLat,
          lon: _deliveryLon,
          addressStructured: _deliveryAddressStructured,
        );
        
        if (ok) {
          debugPrint('✅ [CHECKOUT._updateUserData] Ubicación guardada exitosamente');
        } else {
          debugPrint('⚠️ [CHECKOUT._updateUserData] No se pudo guardar la dirección en client_profiles');
        }

        debugPrint('✅ [CHECKOUT._updateUserData] ===== FIN =====');
      } catch (e) {
        debugPrint('❌ [CHECKOUT._updateUserData] Error: $e');
      }
    }
  }

  // Guarda el teléfono cada vez que el usuario lo cambia (con debounce)
  void _schedulePhoneAutosave(String fullPhone) {
    final user = SupabaseAuth.currentUser;
    if (user == null) return;
    _phoneDebounce?.cancel();
    setState(() {
      _isPhoneValidating = true;
      _phoneErrorText = null;
    });
    _phoneDebounce = Timer(const Duration(milliseconds: 700), () async {
      try {
        final trimmed = fullPhone.trim();
        if (trimmed.isEmpty) {
          if (!mounted) return;
          setState(() {
            _isPhoneValidating = false;
            _phoneErrorText = 'Ingresa tu teléfono';
            _isPhoneUnique = false;
          });
          return;
        }

        // Verificar que el teléfono esté libre en tabla users (excluyendo el propio id)
        final List<dynamic> dup = await SupabaseConfig.client
            .from('users')
            .select('id')
            .eq('phone', trimmed)
            .neq('id', user.id)
            .limit(1);

        if (dup.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _isPhoneValidating = false;
            _phoneErrorText = 'Este teléfono ya está en uso';
            _isPhoneUnique = false;
            _stickyWarning = 'Teléfono en uso: cambia tu número para continuar';
          });
          return; // No guardar si está ocupado
        }

        // Libre: guardar de forma segura vía RPC (evita RLS y valida unicidad en servidor)
        await DoaRepartosService.updateMyPhoneIfUnique(trimmed);
        if (!mounted) return;
        setState(() {
          _isPhoneValidating = false;
          _phoneErrorText = null;
          _isPhoneUnique = true;
          if (_stickyWarning != null && _stickyWarning!.contains('Teléfono en uso')) {
            _stickyWarning = null;
          }
        });
        debugPrint('📞 [CHECKOUT] Teléfono actualizado con RPC update_my_phone_if_unique');
      } catch (e) {
        debugPrint('⚠️ [CHECKOUT] No se pudo validar/guardar teléfono: $e');
        if (!mounted) return;
        setState(() {
          _isPhoneValidating = false;
          // Mostrar mensaje específico si es de unicidad/permiso, sino genérico
          final msg = e.toString();
          if (msg.contains('en uso')) {
            _phoneErrorText = 'Este teléfono ya está en uso';
          } else if (msg.contains('Permisos') || msg.contains('denied')) {
            _phoneErrorText = 'No tienes permisos para actualizar el teléfono';
          } else {
            _phoneErrorText = 'No se pudo validar el teléfono. Intenta de nuevo';
          }
          _isPhoneUnique = false;
        });
      }
    });
  }

  double get _subtotal {
    return widget.cartItems.entries.fold(0.0, (sum, entry) {
      final product = widget.products.firstWhere((p) => p.id == entry.key);
      return sum + (product.price * entry.value);
    });
  }

  double get _total => _subtotal + _deliveryFee;

  List<DoaProduct> get _cartProducts {
    return widget.products.where((p) => widget.cartItems.containsKey(p.id)).toList();
  }

  Future<void> _placeOrder() async {
    // Bloquear si el teléfono está ocupado o en validación
    if (_isPhoneValidating) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Espera a que se valide el teléfono...')),
      );
      return;
    }
    if (!_isPhoneUnique) {
      setState(() => _stickyWarning = 'Teléfono en uso: cambia tu número para continuar');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El teléfono ya está en uso. Usa otro número.')),
      );
      return;
    }
    // Validar y mostrar mensaje inferior si algo falta
    if (!_formKey.currentState!.validate()) {
      final needsPhone = _phoneController.text.trim().isEmpty;
      final needsAddress = _addressController.text.trim().isEmpty || _deliveryLat == null || _deliveryLon == null;
      String msg = 'Completa: ';
      final parts = <String>[];
      if (needsPhone) parts.add('teléfono');
      if (needsAddress) parts.add('dirección');
      msg += parts.join(' y ');
      setState(() => _stickyWarning = msg);
      // Además, realzar con un snackbar discreto
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final user = SupabaseAuth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to place an order')),
      );
      return;
    }

    setState(() => _isProcessingOrder = true);

    try {
      debugPrint('🛒 [CHECKOUT] ===== INICIANDO PROCESO DE PEDIDO =====');

      // Guardar datos del usuario SIEMPRE (teléfono, dirección)
      debugPrint('💾 [CHECKOUT._placeOrder] Guardando datos del usuario...');
      await _updateUserData();

      // **FLUJO BIFURCADO**: Efectivo vs Tarjeta
      if (_selectedPaymentMethod == PaymentMethod.card) {
        debugPrint('💳 [CHECKOUT] Método de pago: TARJETA');
        debugPrint('💳 [CHECKOUT] NO se crea la orden aún - MercadoPago la creará tras pago exitoso');
        
        // Preparar datos de la orden para enviar a MercadoPago
        final orderData = {
          'user_id': user.id,
          'restaurant_id': widget.restaurant.id,
          'restaurant_name': widget.restaurant.name,
          'total_amount': _total,
          'delivery_address': _addressController.text.trim(),
          'delivery_lat': _deliveryLat,
          'delivery_lon': _deliveryLon,
          'delivery_place_id': _deliveryPlaceId,
          'delivery_address_structured': _deliveryAddressStructured,
          'order_notes': _notesController.text.trim(),
          'items': widget.cartItems.entries.map((entry) {
            final product = widget.products.firstWhere((p) => p.id == entry.key);
            return {
              'product_id': entry.key,
              'product_name': product.name,
              'quantity': entry.value,
              'unit_price': product.price,
              'price_at_time_of_order': product.price,
            };
          }).toList(),
        };
        
        if (mounted) {
          final mpResult = await Navigator.of(context).push<Map<String, dynamic>>(
            MaterialPageRoute(
              builder: (context) => CardPaymentFormScreen(
                totalAmount: _total + _clientTotalDebt,
                clientDebt: _clientTotalDebt > 0 ? _clientTotalDebt : null,
                description: 'Pedido - ${widget.restaurant.name}',
                clientEmail: user.email ?? '',
                orderData: orderData,
              ),
            ),
          );

          if (!mounted) return;

          // Manejar resultado del checkout de MercadoPago
          if (mpResult == null || mpResult['success'] != true) {
            final message = mpResult?['message'] ?? 'Pago cancelado';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
            return; // No navegar a confirmación si el pago falló
          }

          debugPrint('✅ [CHECKOUT] Pago con MercadoPago exitoso: ${mpResult['status']}');
          final orderId = mpResult['order_id'] as String?;
          
          if (orderId == null || orderId.isEmpty) {
            throw Exception('No se pudo obtener el ID de la orden después del pago');
          }

          // Navegar a confirmación con la orden creada por el webhook
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => OrderConfirmationScreen(
                  orderId: orderId,
                  restaurant: widget.restaurant,
                  cartItems: widget.cartItems,
                  products: widget.products,
                  deliveryAddress: _addressController.text.trim(),
                  paymentMethod: _selectedPaymentMethod,
                  total: _total,
                ),
              ),
            );
          }
        }
      } else {
        // **PAGO EN EFECTIVO**: Crear orden inmediatamente
        debugPrint('💵 [CHECKOUT] Método de pago: EFECTIVO - Creando orden...');
        
        final orderItems = widget.cartItems.entries.map((entry) {
          final product = widget.products.firstWhere((p) => p.id == entry.key);
          return {
            'product_id': entry.key,
            'quantity': entry.value,
            'unit_price': product.price,
            'price_at_time_of_order': product.price,
            'created_at': DateTime.now().toIso8601String(),
          };
        }).toList();

        debugPrint('📦 [CHECKOUT._placeOrder] Creando orden con coordenadas:');
        debugPrint('   - deliveryLat: $_deliveryLat');
        debugPrint('   - deliveryLon: $_deliveryLon');
        debugPrint('   - deliveryAddress: ${_addressController.text.trim()}');
        debugPrint('   - deliveryPlaceId: $_deliveryPlaceId');
        debugPrint('   - deliveryAddressStructured: $_deliveryAddressStructured');
        
        final result = await DoaRepartosService.createOrderWithItemsStatic(
          userId: user.id,
          restaurantId: widget.restaurant.id,
          totalAmount: _total,
          deliveryAddress: _addressController.text.trim(),
          items: orderItems,
          orderNotes: _notesController.text.trim(),
          paymentMethod: _selectedPaymentMethod.toString().split('.').last,
          deliveryLat: _deliveryLat,
          deliveryLon: _deliveryLon,
          deliveryPlaceId: _deliveryPlaceId,
          deliveryAddressStructured: _deliveryAddressStructured,
        );

        if (result['success'] != true) {
          throw Exception(result['error'] ?? 'Failed to create order');
        }

        final orderId = result['order_id'] as String;
        debugPrint('✅ [CHECKOUT] Orden creada con ID: $orderId');
        if (_deliveryLat != null && _deliveryLon != null) {
          debugPrint('✅ [CHECKOUT] Coordenadas incluidas: lat=$_deliveryLat, lon=$_deliveryLon');
        } else {
          debugPrint('⚠️ [CHECKOUT] ADVERTENCIA: Orden creada SIN coordenadas!');
        }

        // Navegar a confirmación
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => OrderConfirmationScreen(
                orderId: orderId,
                restaurant: widget.restaurant,
                cartItems: widget.cartItems,
                products: widget.products,
                deliveryAddress: _addressController.text.trim(),
                paymentMethod: _selectedPaymentMethod,
                total: _total,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ [CHECKOUT._placeOrder] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar pedido: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingOrder = false);
    }
  }

  Future<void> _openPlacePicker() async {
    _placesSessionToken ??= PlacesService.newSessionToken();
    final token = _placesSessionToken!;
    debugPrint('🧭 [CHECKOUT] Open address picker with sessionToken=$token');

    final result = await showDialog<AddressPickResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: AddressPickerModal(
          initialAddress: _addressController.text,
          sessionToken: token,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _addressController.text = result.formattedAddress;
        _deliveryLat = result.lat;
        _deliveryLon = result.lon;
        _deliveryPlaceId = result.placeId;
        _deliveryAddressStructured = result.addressStructured;
      });
      debugPrint('✅ [CHECKOUT] Dirección confirmada: ${result.formattedAddress}');
      debugPrint('✅ [CHECKOUT] Coordenadas: lat=${result.lat}, lon=${result.lon}');
      debugPrint('✅ [CHECKOUT] Structured: ${result.addressStructured}');
      // Regenerate session token for next search (best practice)
      _placesSessionToken = PlacesService.newSessionToken();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Checkout'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
                child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                      if (!_hasActiveCouriers)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text('No hay repartidores activos. No podrás completar el pedido hasta que haya disponibilidad.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
              _buildOrderSummaryCard(),
              const SizedBox(height: 24),
              _buildDeliveryAddressCard(),
              const SizedBox(height: 24),
              _buildPaymentMethodCard(),
              const SizedBox(height: 24),
              _buildOrderNotesCard(),
              const SizedBox(height: 24),
              _buildTotalSummaryCard(),
              const SizedBox(height: 12),
              if (_stickyWarning != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _stickyWarning!,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onErrorContainer,
                              ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _stickyWarning = null);
                        },
                        child: Text('Ok', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isProcessingOrder || !_hasActiveCouriers) ? null : _placeOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isProcessingOrder
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'Place Order - MXN ${_total.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restaurant, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(widget.restaurant.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            ..._cartProducts.map((product) {
              final quantity = widget.cartItems[product.id]!;
              final itemTotal = product.price * quantity;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Theme.of(context).colorScheme.primaryContainer),
                      child: product.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(product.imageUrl!, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) =>
                                  Icon(Icons.restaurant_menu, color: Theme.of(context).colorScheme.primary)),
                            )
                          : Icon(Icons.restaurant_menu, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          Text('${quantity} × \$${product.price.toStringAsFixed(2)} MXN',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              )),
                        ],
                      ),
                    ),
                    Text('\$${itemTotal.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryAddressCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Delivery Address', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            // Autocomplete con Google Places (igual que registro de restaurantes)
            AddressSearchField(
              controller: _addressController,
              labelText: 'Full Address',
              hintText: 'Buscar dirección...',
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your delivery address';
                }
                if (_deliveryLat == null || _deliveryLon == null) {
                  return 'Selecciona una dirección de Google para confirmar';
                }
                return null;
              },
              onPlaceSelected: (placeDetails) {
                debugPrint('📍 [CHECKOUT.onPlaceSelected] Dirección seleccionada desde Google Places');
                debugPrint('📍 [CHECKOUT.onPlaceSelected] placeDetails: $placeDetails');
                
                final lat = (placeDetails['lat'] ?? placeDetails['latitude'])?.toDouble();
                final lon = (placeDetails['lon'] ?? placeDetails['lng'] ?? placeDetails['longitude'])?.toDouble();
                final formatted = (placeDetails['formatted_address'] ?? placeDetails['address'] ?? _addressController.text).toString();
                
                debugPrint('📍 [CHECKOUT.onPlaceSelected] Valores extraídos:');
                debugPrint('   - lat: $lat');
                debugPrint('   - lon: $lon');
                debugPrint('   - formatted: $formatted');
                
                if (lat != null && lon != null) {
                  setState(() {
                    _deliveryLat = lat;
                    _deliveryLon = lon;
                    _deliveryPlaceId = placeDetails['place_id'] ?? placeDetails['placeId'];
                    _deliveryAddressStructured = placeDetails;
                    _lastSelectedAddress = formatted;
                    _addressController.text = formatted;
                  });
                  debugPrint('✅ [CHECKOUT.onPlaceSelected] Estado actualizado: lat=$_deliveryLat, lon=$_deliveryLon');
                  _formKey.currentState?.validate();
                } else {
                  debugPrint('⚠️ [CHECKOUT.onPlaceSelected] ADVERTENCIA: lat o lon son null!');
                }
              },
            ),
            if (_deliveryLat != null && _deliveryLon != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Coordenadas confirmadas: ${_deliveryLat!.toStringAsFixed(5)}, ${_deliveryLon!.toStringAsFixed(5)}',
                      style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis, softWrap: true)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            // Teléfono con selector de lada (MX/US) y autosave
            PhoneDialInput(
              controller: _phoneController,
              label: 'Teléfono',
              hint: 'Tu número con lada',
              isValidating: _isPhoneValidating,
              errorText: _phoneErrorText,
              onChangedFull: (full) {
                // limpiar aviso si el usuario ya empezó a completar
                if (_stickyWarning != null && full.trim().isNotEmpty) {
                  setState(() => _stickyWarning = null);
                }
                _schedulePhoneAutosave(full);
              },
              validator: (digits) {
                if (digits.isEmpty) return 'Ingresa tu teléfono';
                if (digits.length < 8) return 'Número no válido';
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Payment Method', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            // Mostrar banner de adeudo si existe
            if (_clientTotalDebt > 0)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Text('Adeudo Pendiente',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                          )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tienes un adeudo de \$${_clientTotalDebt.toStringAsFixed(2)} MXN por una orden anterior no entregada.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Debes pagar con tarjeta para liquidar tu adeudo (\$${_clientTotalDebt.toStringAsFixed(2)}) + este pedido (\$${_total.toStringAsFixed(2)}) = \$${(_clientTotalDebt + _total).toStringAsFixed(2)} MXN',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Radio<PaymentMethod>(
                value: PaymentMethod.cash,
                groupValue: _selectedPaymentMethod,
                onChanged: _clientTotalDebt > 0 ? null : (value) => setState(() => _selectedPaymentMethod = value!),
              ),
              title: Text('Cash on Delivery', 
                style: TextStyle(color: _clientTotalDebt > 0 ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4) : null)),
              subtitle: Text(
                _clientTotalDebt > 0 
                  ? 'No disponible (tienes adeudo pendiente)'
                  : 'Pay with cash when your order arrives',
                style: TextStyle(color: _clientTotalDebt > 0 ? Theme.of(context).colorScheme.error : null),
              ),
              trailing: Icon(Icons.money, color: _clientTotalDebt > 0 ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4) : null),
              enabled: _clientTotalDebt == 0,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Radio<PaymentMethod>(
                value: PaymentMethod.card,
                groupValue: _selectedPaymentMethod,
                onChanged: (value) => setState(() => _selectedPaymentMethod = value!),
              ),
              title: const Text('Credit/Debit Card'),
              subtitle: const Text('Pay with credit or debit card (via Mercado Pago)'),
              trailing: const Icon(Icons.credit_card),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderNotesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.note_add, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Order Notes (Optional)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                hintText: 'Any special instructions for your order...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              maxLines: 3,
              maxLength: 200,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order Summary', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Subtotal', style: Theme.of(context).textTheme.bodyLarge),
                Text('MXN ${_subtotal.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Delivery Fee', style: Theme.of(context).textTheme.bodyLarge),
                Text('MXN ${_deliveryFee.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                Text('MXN ${_total.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _addressController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _couriersUpdatesSubscription?.cancel();
    _phoneDebounce?.cancel();
    super.dispose();
  }
}
