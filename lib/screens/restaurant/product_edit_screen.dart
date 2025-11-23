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
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Editar producto' : 'Nuevo producto'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ImageUploadField(
              label: 'Foto del Producto',
              hint: 'Toca para subir foto',
              icon: Icons.camera_alt,
              imageUrl: widget.product?.imageUrl,
              isRequired: false,
              onImageSelected: (file) => setState(() => _selectedImage = file),
              helpText: 'Una buena foto ayuda a vender más',
            ),
            const SizedBox(height: 16),
            // Type selector (simple categories only)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Categoría *',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedType,
                  items: _types
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t[0].toUpperCase() + t.substring(1)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedType = v ?? 'principal'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(
                labelText: 'Precio *',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                final p = double.tryParse((v ?? '').trim());
                if (p == null || p <= 0) return 'Precio inválido';
                return null;
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _isAvailable,
              onChanged: (v) => setState(() => _isAvailable = v),
              title: const Text('Disponible'),
              subtitle: Text(_isAvailable ? 'Aparecerá en el menú' : 'Oculto para clientes'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isEdit ? 'Guardar cambios' : 'Crear producto'),
            ),
          ],
        ),
      ),
    );
  }
}
