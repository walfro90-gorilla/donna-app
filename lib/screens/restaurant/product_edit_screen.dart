import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/services/storage_service.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/widgets/image_upload_field.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class ProductEditScreen extends StatefulWidget {
  final DoaRestaurant restaurant;
  final DoaProduct? product;

  const ProductEditScreen({super.key, required this.restaurant, this.product});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _isAvailable = true;
  bool _saving = false;
  PlatformFile? _selectedImage;
  // New: product type selector
  static const _types = ['principal', 'bebida', 'postre', 'entrada'];
  String _selectedType = 'principal';

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _nameCtrl.text = p.name;
      _descCtrl.text = p.description ?? '';
      _priceCtrl.text = p.price.toStringAsFixed(2);
      _isAvailable = p.isAvailable;
      if ((p.type ?? '').isNotEmpty && p.type != 'combo') {
        final t = (p.type ?? '').toLowerCase();
        if (_types.contains(t)) _selectedType = t; // keep combos out of this screen
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      String? imageUrl = widget.product?.imageUrl;

      if (_selectedImage != null) {
        imageUrl = await StorageService.uploadProductImage(widget.restaurant.id, _selectedImage!);
      }

      final payload = {
        'restaurant_id': widget.restaurant.id,
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'price': double.parse(_priceCtrl.text.trim()),
        'image_url': imageUrl,
        'is_available': _isAvailable,
        // Backend schema now expects one of: principal|bebida|postre|entrada (combo se maneja en otra pantalla)
        'type': _selectedType,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (widget.product == null) {
        payload['created_at'] = DateTime.now().toIso8601String();
        await SupabaseConfig.client.from('products').insert(payload);
      } else {
        await SupabaseConfig.client.from('products').update(payload).eq('id', widget.product!.id);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error guardando: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Editar Producto' : 'Nuevo Producto'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image Section
              Center(
                child: ImageUploadField(
                  label: 'Foto del Producto',
                  hint: 'Toca para subir foto',
                  icon: Icons.add_a_photo_outlined,
                  imageUrl: widget.product?.imageUrl,
                  isRequired: false,
                  onImageSelected: (file) => setState(() => _selectedImage = file),
                  helpText: 'Una buena foto ayuda a vender más',
                ),
              ),
              const SizedBox(height: 32),
              
              // Form Fields
              Text(
                'Información General',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              
              // Category Dropdown
              DropdownButtonFormField<String>(
                value: _selectedType,
                decoration: _buildInputDecoration('Categoría', Icons.category_outlined),
                items: _types
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t[0].toUpperCase() + t.substring(1)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedType = v ?? 'principal'),
              ),
              const SizedBox(height: 16),
              
              // Name
              TextFormField(
                controller: _nameCtrl,
                decoration: _buildInputDecoration('Nombre del producto', Icons.drive_file_rename_outline),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa el nombre' : null,
              ),
              const SizedBox(height: 16),
              
              // Description
              TextFormField(
                controller: _descCtrl,
                decoration: _buildInputDecoration('Descripción (opcional)', Icons.description_outlined),
                maxLines: 1,
              ),
              const SizedBox(height: 16),
              
              // Price
              TextFormField(
                controller: _priceCtrl,
                decoration: _buildInputDecoration('Precio', Icons.payments_outlined).copyWith(
                  prefixText: r'$ ',
                  prefixStyle: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final p = double.tryParse((v ?? '').trim());
                  if (p == null || p <= 0) return 'Precio inválido';
                  return null;
                },
              ),
              
              const SizedBox(height: 24),
              
              // Availability Switch
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withValues(alpha: isDark ? 0.3 : 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isAvailable,
                  onChanged: (v) => setState(() => _isAvailable = v),
                  title: const Text('Disponible para venta', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _isAvailable ? 'Aparecerá en el menú' : 'Oculto para clientes',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                  ),
                  activeColor: theme.colorScheme.primary,
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Action Button
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        isEdit ? 'GUARDAR CAMBIOS' : 'CREAR PRODUCTO',
                        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 22),
      filled: true,
      fillColor: theme.colorScheme.surfaceVariant.withValues(alpha: isDark ? 0.2 : 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
      ),
      labelStyle: TextStyle(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        fontSize: 14,
      ),
    );
  }
}

