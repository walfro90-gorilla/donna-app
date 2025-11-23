import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/widgets/address_picker_modal.dart';
import 'package:doa_repartos/widgets/image_upload_field.dart';
import 'package:doa_repartos/widgets/profile_completion_card.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:file_picker/file_picker.dart';

/// Pantalla completa para editar el perfil del restaurante
class RestaurantProfileEditScreen extends StatefulWidget {
  final DoaRestaurant restaurant;
  final ProfileSection? initialSection;

  const RestaurantProfileEditScreen({
    super.key,
    required this.restaurant,
    this.initialSection,
  });

  @override
  State<RestaurantProfileEditScreen> createState() => _RestaurantProfileEditScreenState();
}

class _RestaurantProfileEditScreenState extends State<RestaurantProfileEditScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _basicInfoFormKey = GlobalKey<FormState>();
  
  // Controllers
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _cuisineTypeController = TextEditingController();
  final _addressController = TextEditingController();
  final _deliveryRadiusController = TextEditingController();
  final _minOrderAmountController = TextEditingController();
  final _estimatedDeliveryTimeController = TextEditingController();
  
  // Image URLs
  String? _logoUrl;
  String? _coverImageUrl;
  // String? _menuImageUrl; // Eliminado: ya no usamos foto del menú
  
  // Location data
  LatLng? _selectedLocation;
  String? _selectedPlaceId;
  Map<String, dynamic>? _addressStructured;
  
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    
    // Inicializar tabs (3 secciones)
    _tabController = TabController(length: 3, vsync: this);
    
    // Navegar al tab inicial si se especificó
    if (widget.initialSection != null) {
      _tabController.index = _getSectionIndex(widget.initialSection!);
    }
    
    // Cargar datos existentes
    _loadRestaurantData();

    // Listeners para detectar cambios en campos de texto
    _nameController.addListener(_markChanged);
    _descriptionController.addListener(_markChanged);
    _cuisineTypeController.addListener(_markChanged);
    _addressController.addListener(_markChanged);
  }

  int _getSectionIndex(ProfileSection section) {
    switch (section) {
      case ProfileSection.basicInfo:
        return 0;
      case ProfileSection.logo:
      case ProfileSection.cover:
        return 1;
      case ProfileSection.products:
        return 2;
      default:
        return 0;
    }
  }

  void _loadRestaurantData() {
    _nameController.text = widget.restaurant.name;
    _descriptionController.text = widget.restaurant.description ?? '';
    _cuisineTypeController.text = widget.restaurant.cuisineType ?? '';
    _logoUrl = widget.restaurant.logoUrl;
    _coverImageUrl = widget.restaurant.coverImageUrl;
    // _menuImageUrl = widget.restaurant.menuImageUrl; // Eliminado
    
    if (widget.restaurant.deliveryRadiusKm != null) {
      _deliveryRadiusController.text = widget.restaurant.deliveryRadiusKm!.toString();
    }
    if (widget.restaurant.minOrderAmount != null) {
      _minOrderAmountController.text = widget.restaurant.minOrderAmount!.toString();
    }
    if (widget.restaurant.estimatedDeliveryTimeMinutes != null) {
      _estimatedDeliveryTimeController.text = widget.restaurant.estimatedDeliveryTimeMinutes!.toString();
    }
  }

  Future<void> _selectAddress() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddressPickerModal(),
    );

    if (result != null && mounted) {
      setState(() {
        _addressController.text = result['formatted_address'] ?? '';
        _selectedLocation = result['location'];
        _selectedPlaceId = result['place_id'];
        _addressStructured = result['address_structured'];
      });
      _markChanged();
    }
  }

  void _markChanged() {
    if (!_hasChanges) {
      setState(() {
        _hasChanges = true;
      });
    }
  }

  Future<void> _confirmAndSaveChanges() async {
    if (!_hasChanges) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay cambios para guardar')),
        );
      }
      return;
    }

    final proceed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReviewWarningSheet(onConfirm: () => Navigator.of(ctx).pop(true)),
    );

    if (proceed == true) {
      await _saveChanges();
    }
  }

  Future<void> _saveChanges() async {
    // Validar formulario básico
    if (!_basicInfoFormKey.currentState!.validate()) {
      _tabController.animateTo(0);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim().isNotEmpty 
            ? _descriptionController.text.trim() 
            : null,
        'cuisine_type': _cuisineTypeController.text.trim().isNotEmpty 
            ? _cuisineTypeController.text.trim() 
            : null,
        'logo_url': _logoUrl,
        'cover_image_url': _coverImageUrl,
        // 'menu_image_url': _menuImageUrl, // Eliminado: no persistir foto del menú
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Parámetros de delivery se calculan automáticamente (no se guardan manualmente)
      if (_selectedLocation != null) {
        updateData['location_lat'] = _selectedLocation!.latitude;
        updateData['location_lon'] = _selectedLocation!.longitude;
        updateData['location_place_id'] = _selectedPlaceId;
        updateData['address_structured'] = _addressStructured;
      }

      await SupabaseConfig.client
          .from('restaurants')
          .update(updateData)
          .eq('id', widget.restaurant.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Tus cambios fueron enviados a revisión. Tu restaurante quedará en estado Pendiente hasta aprobación (hasta 24 h).'),
            backgroundColor: Colors.orange.shade700,
          ),
        );
        Navigator.of(context).pop(true); // Regresar con éxito
      }
    } catch (e) {
      print('❌ Error guardando cambios: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error guardando cambios: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Perfil del Restaurante'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline), text: 'Información'),
            Tab(icon: Icon(Icons.image_outlined), text: 'Imágenes'),
            Tab(icon: Icon(Icons.settings_outlined), text: 'Configuración'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _confirmAndSaveChanges,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save, color: Colors.white),
            label: const Text('GUARDAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBasicInfoTab(),
          _buildImagesTab(),
          _buildConfigurationTab(),
        ],
      ),
    );
  }

  /// TAB 1: Información básica
  Widget _buildBasicInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _basicInfoFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Información General',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            
            // Nombre del restaurante
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre del Restaurante *',
                hintText: 'Ej: Pizzería Don Luigi',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.store),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El nombre es obligatorio';
                }
                if (value.trim().length < 3) {
                  return 'Mínimo 3 caracteres';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 16),
            
            // Descripción
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                hintText: 'Describe tu restaurante...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 4,
            ),
            
            const SizedBox(height: 16),
            
            // Tipo de cocina
            DropdownButtonFormField<String>(
              value: _cuisineTypeController.text.isNotEmpty
                  ? _cuisineTypeController.text
                  : null,
              decoration: const InputDecoration(
                labelText: 'Tipo de Cocina',
                hintText: 'Selecciona una opción',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_dining),
              ),
              items: const [
                'Mexicana',
                'Venezolana',
                'Casera',
                'Pizza',
                'Postres',
                'Árabe',
                'Italiana',
                'China',
                'Japonesa',
                'Peruana',
                'Vegetariana/Vegana',
                'Mariscos',
              ].map((c) => DropdownMenuItem<String>(value: c, child: Text(c))).toList(),
              onChanged: (value) {
                setState(() {
                  _cuisineTypeController.text = value ?? '';
                });
                _markChanged();
              },
            ),
            
            const SizedBox(height: 24),
            
            Text(
              'Ubicación',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            
            // Dirección
            TextFormField(
              controller: _addressController,
              readOnly: true,
              onTap: _selectAddress,
              decoration: InputDecoration(
                labelText: 'Dirección del Restaurante',
                hintText: 'Toca para buscar dirección',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.location_on),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _selectAddress,
                ),
              ),
            ),
            
            if (_selectedLocation != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ubicación confirmada: ${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// TAB 2: Imágenes
  Widget _buildImagesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Imágenes del Restaurante',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Las imágenes ayudan a atraer más clientes',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 24),
          
          // Logo del restaurante
          _buildImageSection(
            title: 'Logo del Restaurante',
            subtitle: 'Imagen cuadrada (recomendado 512x512)',
            currentUrl: _logoUrl,
            onImageSelected: (url) => setState(() => _logoUrl = url),
            icon: Icons.image,
          ),
          
          const SizedBox(height: 24),
          
          // Foto de portada
          _buildImageSection(
            title: 'Foto de Portada',
            subtitle: 'Imagen horizontal (recomendado 1920x1080)',
            currentUrl: _coverImageUrl,
            onImageSelected: (url) => setState(() => _coverImageUrl = url),
            icon: Icons.photo_camera,
          ),
          
          const SizedBox(height: 24),
          // Eliminado: Foto del Menú (Opcional)
        ],
      ),
    );
  }

  Widget _buildImageSection({
    required String title,
    required String subtitle,
    required String? currentUrl,
    required Function(String?) onImageSelected,
    required IconData icon,
    bool isOptional = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (isOptional)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Opcional',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 12),
        ImageUploadField(
          label: '',
          icon: Icons.cloud_upload,
          imageUrl: currentUrl,
          onImageSelected: (file) {
            // TODO: Implementar upload de imagen a Supabase Storage
            if (file != null) {
              print('📷 Imagen seleccionada: ${file.name}');
              // Por ahora, usar una URL placeholder
              onImageSelected('https://via.placeholder.com/512');
              _markChanged();
            }
          },
        ),
      ],
    );
  }

  /// TAB 3: Configuración
  Widget _buildConfigurationTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parámetros de Delivery',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'El radio de entrega, el pedido mínimo y el tiempo estimado se calculan automáticamente en base a la geolocalización del cliente y del restaurante. No es necesario configurarlos manualmente.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _cuisineTypeController.dispose();
    _addressController.dispose();
    _deliveryRadiusController.dispose();
    _minOrderAmountController.dispose();
    _estimatedDeliveryTimeController.dispose();
    super.dispose();
  }
}

/// Bottom sheet moderno para advertir revisión administrativa al guardar cambios
class _ReviewWarningSheet extends StatelessWidget {
  final VoidCallback onConfirm;
  const _ReviewWarningSheet({required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.privacy_tip_outlined, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tus cambios se enviarán a revisión', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Por seguridad y consistencia, cualquier actualización en tu perfil será revisada por nuestro equipo. Durante este proceso:'),
                      const SizedBox(height: 8),
                      const _Bullet(text: 'Tu restaurante quedará en estado Pendiente.'),
                      const _Bullet(text: 'No podrás conectarte para recibir pedidos temporalmente.'),
                      const _Bullet(text: 'El proceso puede tardar hasta 24 horas.'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    label: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check_circle, color: Colors.white),
                    label: const Text('Enviar a revisión y guardar'),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
