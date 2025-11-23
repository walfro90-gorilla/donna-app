import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'dart:async';

/// Pantalla de formulario de pago con tarjeta (Nativo - 100% Server-Side)
/// 
/// Captura datos de tarjeta y los envía directamente al Edge Function
/// que tokeniza y procesa el pago server-side
class CardPaymentFormScreen extends StatefulWidget {
  final double totalAmount;
  final double? clientDebt;
  final String description;
  final String clientEmail;
  final Map<String, dynamic> orderData;

  const CardPaymentFormScreen({
    super.key,
    required this.totalAmount,
    this.clientDebt,
    required this.description,
    required this.clientEmail,
    required this.orderData,
  });

  @override
  State<CardPaymentFormScreen> createState() => _CardPaymentFormScreenState();
}

class _CardPaymentFormScreenState extends State<CardPaymentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberController = TextEditingController();
  final _cardHolderController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _docNumberController = TextEditingController();
  
  bool _isProcessing = false;
  String? _errorMessage;
  String _selectedDocType = 'CURP';
  int _selectedInstallments = 1;

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cardHolderController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _docNumberController.dispose();
    super.dispose();
  }

  Future<void> _processPayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      debugPrint('💳 [CARD_FORM] Procesando pago 100% server-side...');
      
      // Extraer mes y año de expiración
      final expiryParts = _expiryController.text.split('/');
      if (expiryParts.length != 2) {
        throw Exception('Formato de fecha inválido');
      }
      
      final expiryMonth = expiryParts[0].trim();
      final expiryYear = '20${expiryParts[1].trim()}';
      
      // Enviar datos de tarjeta directamente al Edge Function
      // que tokenizará y procesará el pago server-side
      final response = await SupabaseConfig.client.functions.invoke(
        'process-card-payment',
        body: {
          'card_data': {
            'card_number': _cardNumberController.text.replaceAll(' ', ''),
            'cardholder_name': _cardHolderController.text,
            'expiration_month': expiryMonth,
            'expiration_year': expiryYear,
            'security_code': _cvvController.text,
            'identification_type': _selectedDocType,
            'identification_number': _docNumberController.text,
          },
          'installments': _selectedInstallments,
          'payer': {
            'email': widget.clientEmail,
            'identification': {
              'type': _selectedDocType,
              'number': _docNumberController.text,
            },
          },
          'amount': widget.totalAmount,
          'description': widget.description,
          'order_data': widget.orderData,
          'client_debt': widget.clientDebt ?? 0.0,
        },
      );

      debugPrint('📦 [CARD_FORM] Response status: ${response.status}');
      debugPrint('📦 [CARD_FORM] Response data: ${response.data}');

      if (response.status != 200) {
        final errorMsg = response.data is Map 
          ? (response.data['error'] ?? response.data.toString())
          : response.data.toString();
        throw Exception('Error ${response.status}: $errorMsg');
      }

      final data = response.data as Map<String, dynamic>;
      debugPrint('📦 [CARD_FORM] Data parsed: success=${data['success']}, status=${data['status']}');

      if (data['success'] == true) {
        final status = data['status'] as String;
        final orderId = data['order_id'] as String;

        debugPrint('✅ [CARD_FORM] Pago procesado: status=$status, orderId=$orderId');

        if (mounted) {
          Navigator.of(context).pop({
            'success': true,
            'status': status,
            'order_id': orderId,
            'message': data['message'] ?? 'Pago procesado',
          });
        }
      } else {
        final errorMsg = data['error'] ?? data['message'] ?? 'Error desconocido al procesar pago';
        debugPrint('❌ [CARD_FORM] Pago rechazado: $errorMsg');
        throw Exception(errorMsg);
      }
    } catch (e) {
      debugPrint('❌ [CARD_FORM] Error: $e');
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Pago con Tarjeta'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Resumen de pago
              _buildPaymentSummary(),
              const SizedBox(height: 32),

              // Número de tarjeta
              _buildCardNumberField(),
              const SizedBox(height: 16),

              // Titular de la tarjeta
              _buildCardHolderField(),
              const SizedBox(height: 16),

              // Expiración y CVV
              Row(
                children: [
                  Expanded(child: _buildExpiryField()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildCVVField()),
                ],
              ),
              const SizedBox(height: 16),

              // Tipo de documento
              _buildDocTypeField(),
              const SizedBox(height: 16),

              // Número de documento
              _buildDocNumberField(),
              const SizedBox(height: 16),

              // Cuotas
              _buildInstallmentsField(),
              const SizedBox(height: 24),

              // Mensaje de error
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Botón de pago
              ElevatedButton(
                onPressed: _isProcessing ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        'Pagar \$${widget.totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 16),

              // Mensaje de seguridad
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Pago seguro con MercadoPago',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen de Pago',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total a pagar:', style: Theme.of(context).textTheme.bodyLarge),
              Text(
                '\$${widget.totalAmount.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          if (widget.clientDebt != null && widget.clientDebt! > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Incluye deuda pendiente: \$${widget.clientDebt!.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardNumberField() {
    return TextFormField(
      controller: _cardNumberController,
      decoration: InputDecoration(
        labelText: 'Número de Tarjeta',
        hintText: '1234 5678 9012 3456',
        prefixIcon: const Icon(Icons.credit_card),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(16),
        _CardNumberFormatter(),
      ],
      validator: (value) {
        if (value == null || value.isEmpty) return 'Ingrese el número de tarjeta';
        final clean = value.replaceAll(' ', '');
        if (clean.length < 13 || clean.length > 16) return 'Número inválido';
        return null;
      },
    );
  }

  Widget _buildCardHolderField() {
    return TextFormField(
      controller: _cardHolderController,
      decoration: InputDecoration(
        labelText: 'Titular de la Tarjeta',
        hintText: 'NOMBRE APELLIDO',
        prefixIcon: const Icon(Icons.person),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      textCapitalization: TextCapitalization.characters,
      validator: (value) {
        if (value == null || value.isEmpty) return 'Ingrese el titular';
        return null;
      },
    );
  }

  Widget _buildExpiryField() {
    return TextFormField(
      controller: _expiryController,
      decoration: InputDecoration(
        labelText: 'Vencimiento',
        hintText: 'MM/AA',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
        _ExpiryDateFormatter(),
      ],
      validator: (value) {
        if (value == null || value.isEmpty) return 'Requerido';
        if (!value.contains('/') || value.length != 5) return 'Formato: MM/AA';
        return null;
      },
    );
  }

  Widget _buildCVVField() {
    return TextFormField(
      controller: _cvvController,
      decoration: InputDecoration(
        labelText: 'CVV',
        hintText: '123',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      validator: (value) {
        if (value == null || value.isEmpty) return 'Requerido';
        if (value.length < 3) return 'Inválido';
        return null;
      },
    );
  }

  Widget _buildDocTypeField() {
    return DropdownButtonFormField<String>(
      value: _selectedDocType,
      decoration: InputDecoration(
        labelText: 'Tipo de Documento',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: const [
        DropdownMenuItem(value: 'CURP', child: Text('CURP')),
        DropdownMenuItem(value: 'RFC', child: Text('RFC')),
        DropdownMenuItem(value: 'IFE', child: Text('IFE/INE')),
      ],
      onChanged: (value) {
        setState(() => _selectedDocType = value!);
      },
    );
  }

  Widget _buildDocNumberField() {
    return TextFormField(
      controller: _docNumberController,
      decoration: InputDecoration(
        labelText: 'Número de Documento',
        hintText: 'Ingrese su $_selectedDocType',
        prefixIcon: const Icon(Icons.badge),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      textCapitalization: TextCapitalization.characters,
      validator: (value) {
        if (value == null || value.isEmpty) return 'Ingrese el número de documento';
        return null;
      },
    );
  }

  Widget _buildInstallmentsField() {
    return DropdownButtonFormField<int>(
      value: _selectedInstallments,
      decoration: InputDecoration(
        labelText: 'Cuotas',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: const [
        DropdownMenuItem(value: 1, child: Text('1 pago (Sin intereses)')),
        DropdownMenuItem(value: 3, child: Text('3 cuotas')),
        DropdownMenuItem(value: 6, child: Text('6 cuotas')),
        DropdownMenuItem(value: 12, child: Text('12 cuotas')),
      ],
      onChanged: (value) {
        setState(() => _selectedInstallments = value!);
      },
    );
  }
}

// Formateador para número de tarjeta (espacios cada 4 dígitos)
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    
    for (int i = 0; i < text.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(text[i]);
    }
    
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// Formateador para fecha de vencimiento (MM/AA)
class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll('/', '');
    final buffer = StringBuffer();
    
    for (int i = 0; i < text.length; i++) {
      if (i == 2) buffer.write('/');
      buffer.write(text[i]);
    }
    
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
