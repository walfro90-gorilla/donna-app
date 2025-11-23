import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable phone input with MX/US dial selector and flags.
///
/// Behavior:
/// - Displays digits-only text field to the user.
/// - Maintains the full phone in [controller] as +<dial><digits> (e.g., +526565731023).
/// - Defaults to MX +52, detects +52/+1 if [controller.text] is prefilled.
/// - Shows optional validation spinner and error via [isValidating] and [errorText].
class PhoneDialInput extends StatefulWidget {
  final TextEditingController controller; // Holds full phone with +dial
  final String label;
  final String? hint;
  final bool isValidating;
  final String? errorText;
  final ValueChanged<String>? onChangedFull; // Called with full +dial+digits
  final IconData prefixIcon;
    // Optional validator that receives ONLY the digits (no +dial)
    final String? Function(String digits)? validator;

  const PhoneDialInput({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.isValidating = false,
    this.errorText,
    this.onChangedFull,
    this.prefixIcon = Icons.phone_outlined,
    this.validator,
  });

  @override
  State<PhoneDialInput> createState() => _PhoneDialInputState();
}

class _PhoneDialInputState extends State<PhoneDialInput> {
  late final TextEditingController _digitsController;
  String _countryCode = 'MX';
  String _dialCode = '52';
  // Mantener sincronía con el controller externo
  late VoidCallback _controllerListener;
  bool _isSyncingFromExternal = false;

  @override
  void initState() {
    super.initState();
    _digitsController = TextEditingController();

    // Parse initial value from external controller if present
    final parsed = _parsePhone(widget.controller.text.trim());
    _countryCode = parsed.countryCode;
    _dialCode = parsed.dialCode;
    _digitsController.text = parsed.digits;

    // Ensure external controller is canonical
    widget.controller.text = '+${_dialCode}${parsed.digits}';

    // Escuchar cambios externos (ej. cuando la pantalla precarga phone desde BD)
    _controllerListener = () {
      if (_isSyncingFromExternal) return;
      final parsedNow = _parsePhone(widget.controller.text.trim());
      // Evitar rebuilds innecesarios: solo si cambia algo
      final shouldUpdate = parsedNow.countryCode != _countryCode ||
          parsedNow.dialCode != _dialCode ||
          parsedNow.digits != _digitsController.text;
      if (shouldUpdate) {
        setState(() {
          _countryCode = parsedNow.countryCode;
          _dialCode = parsedNow.dialCode;
          _digitsController.text = parsedNow.digits;
        });
      }
    };
    widget.controller.addListener(_controllerListener);
  }

  @override
  void didUpdateWidget(covariant PhoneDialInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      // Desuscribir del anterior y suscribir al nuevo
      oldWidget.controller.removeListener(_controllerListener);
      _controllerListener = () {
        if (_isSyncingFromExternal) return;
        final parsedNow = _parsePhone(widget.controller.text.trim());
        final shouldUpdate = parsedNow.countryCode != _countryCode ||
            parsedNow.dialCode != _dialCode ||
            parsedNow.digits != _digitsController.text;
        if (shouldUpdate) {
          setState(() {
            _countryCode = parsedNow.countryCode;
            _dialCode = parsedNow.dialCode;
            _digitsController.text = parsedNow.digits;
          });
        }
      };
      widget.controller.addListener(_controllerListener);

      // Sincronizar inmediatamente con el nuevo controller
      final parsed = _parsePhone(widget.controller.text.trim());
      _countryCode = parsed.countryCode;
      _dialCode = parsed.dialCode;
      _digitsController.text = parsed.digits;
    }
  }

  @override
  void dispose() {
    _digitsController.dispose();
    widget.controller.removeListener(_controllerListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget? suffixIcon;
    final hasDigits = _digitsController.text.isNotEmpty;
    if (widget.isValidating) {
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (hasDigits && widget.errorText == null) {
      suffixIcon = const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 22);
    }

    Widget countryPrefix() {
      final flag = _countryCode == 'US' ? '🇺🇸' : '🇲🇽';
      final dial = _dialCode;
      return Padding(
        padding: const EdgeInsets.only(left: 8, right: 6),
        child: PopupMenuButton<String>(
          tooltip: 'Seleccionar lada',
          onSelected: (value) {
            setState(() {
              if (value == 'US') {
                _countryCode = 'US';
                _dialCode = '1';
              } else {
                _countryCode = 'MX';
                _dialCode = '52';
              }
              final digits = _onlyDigits(_digitsController.text);
              _digitsController.text = digits;
              widget.controller.text = '+$_dialCode$digits';
              widget.onChangedFull?.call(widget.controller.text);
            });
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'MX',
              child: Row(
                children: const [
                  Text('🇲🇽', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 8),
                  Text('MX +52'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'US',
              child: Row(
                children: const [
                  Text('🇺🇸', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 8),
                  Text('US +1'),
                ],
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDDDDDD), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(flag, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text('+$dial', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333))),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF666666)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _digitsController,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            final digits = _onlyDigits(value);
            if (digits != value) {
              final selectionIndex = digits.length;
              _digitsController.value = TextEditingValue(
                text: digits,
                selection: TextSelection.collapsed(offset: selectionIndex),
              );
            }
            // Evitar bucles: marcamos sincronización interna al actualizar el externo
            _isSyncingFromExternal = true;
            widget.controller.text = '+$_dialCode$digits';
            _isSyncingFromExternal = false;
            widget.onChangedFull?.call(widget.controller.text);
            setState(() {}); // update check icon state
          },
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: Icon(widget.prefixIcon),
            prefix: countryPrefix(),
            suffixIcon: suffixIcon,
            border: const OutlineInputBorder(),
          ),
          validator: (value) {
            if (widget.validator == null) return null;
            final digits = _onlyDigits(value ?? '');
            return widget.validator!(digits);
          },
        ),
        if (widget.errorText != null && !widget.isValidating) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              widget.errorText!,
              style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  String _onlyDigits(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

  ({String countryCode, String dialCode, String digits}) _parsePhone(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\s|-'), '');
    String cc = 'MX';
    String dial = '52';
    String digits = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('+52')) {
      cc = 'MX';
      dial = '52';
      digits = cleaned.substring(3).replaceAll(RegExp(r'[^0-9]'), '');
    } else if (cleaned.startsWith('+1')) {
      cc = 'US';
      dial = '1';
      digits = cleaned.substring(2).replaceAll(RegExp(r'[^0-9]'), '');
    } else if (cleaned.startsWith('52')) {
      cc = 'MX';
      dial = '52';
      digits = cleaned.substring(2).replaceAll(RegExp(r'[^0-9]'), '');
    } else if (cleaned.startsWith('1')) {
      cc = 'US';
      dial = '1';
      digits = cleaned.substring(1).replaceAll(RegExp(r'[^0-9]'), '');
    }
    return (countryCode: cc, dialCode: dial, digits: digits);
  }
}
