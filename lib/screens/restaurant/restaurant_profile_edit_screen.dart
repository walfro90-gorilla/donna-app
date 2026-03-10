import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/widgets/address_picker_modal.dart';
import 'package:doa_repartos/widgets/image_upload_field.dart';
import 'package:doa_repartos/widgets/profile_completion_card.dart';
import 'package:doa_repartos/screens/restaurants/restaurant_detail_screen.dart';
import 'package:doa_repartos/services/storage_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;
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
  final _phoneController = TextEditingController();
  final _deliveryRadiusController = TextEditingController();
  final _minOrderAmountController = TextEditingController();
  final _estimatedDeliveryTimeController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _websiteController = TextEditingController();
  
  // Image URLs
  String? _logoUrl;
  String? _coverImageUrl;
  
  // Image Uploading States
  bool _isUploadingLogo = false;
  bool _isUploadingCover = false;
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
    _phoneController.addListener(_markChanged);
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
    _addressController.text = widget.restaurant.address ?? '';
    _phoneController.text = widget.restaurant.phone ?? '';
    _logoUrl = widget.restaurant.logoUrl;
    _coverImageUrl = widget.restaurant.coverImageUrl;
    
    if (widget.restaurant.deliveryRadiusKm != null) {
      _deliveryRadiusController.text = widget.restaurant.deliveryRadiusKm!.toString();
    }
    if (widget.restaurant.minOrderAmount != null) {
      _minOrderAmountController.text = widget.restaurant.minOrderAmount!.toString();
    }
    if (widget.restaurant.estimatedDeliveryTimeMinutes != null) {
      _estimatedDeliveryTimeController.text = widget.restaurant.estimatedDeliveryTimeMinutes!.toString();
    }
    _facebookController.text = widget.restaurant.facebookUrl ?? '';
    _instagramController.text = widget.restaurant.instagramUrl ?? '';
    _websiteController.text = widget.restaurant.websiteUrl ?? '';

    if (widget.restaurant.locationLat != null && widget.restaurant.locationLon != null) {
      _selectedLocation = LatLng(widget.restaurant.locationLat!, widget.restaurant.locationLon!);
      _selectedPlaceId = widget.restaurant.locationPlaceId;
      _addressStructured = widget.restaurant.addressStructured;
    }
  }

  Future<void> _selectAddress() async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddressPickerModal(),
    );

    if (result is AddressPickResult && mounted) {
      setState(() {
        _addressController.text = result.formattedAddress;
        _selectedLocation = LatLng(result.lat, result.lon);
        _selectedPlaceId = result.placeId;
        _addressStructured = result.addressStructured;
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
        'address': _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
        'phone': _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        'logo_url': _logoUrl,
        'cover_image_url': _coverImageUrl,
        'facebook_url': _facebookController.text.trim().isEmpty ? null : _facebookController.text.trim(),
        'instagram_url': _instagramController.text.trim().isEmpty ? null : _instagramController.text.trim(),
        'website_url': _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

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
            content: const Text('¡Perfil actualizado correctamente!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Perfil del Restaurante'),
        backgroundColor: theme.colorScheme.primary,
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
          IconButton(
            tooltip: 'Ver vista previa pública',
            icon: const Icon(Icons.visibility),
            onPressed: () {
              // Navegar al perfil público con los datos actuales (clonando el modelo)
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => RestaurantDetailScreen(
                    restaurant: widget.restaurant.copyWith(
                      name: _nameController.text.trim(),
                      description: _descriptionController.text.trim(),
                      cuisineType: _cuisineTypeController.text.trim(),
                      logoUrl: _logoUrl,
                      coverImageUrl: _coverImageUrl,
                      facebookUrl: _facebookController.text.trim(),
                      instagramUrl: _instagramController.text.trim(),
                      websiteUrl: _websiteController.text.trim(),
                    ),
                  ),
                ),
              );
            },
          ),
          TextButton.icon(
            onPressed: (_isSaving || _isUploadingLogo || _isUploadingCover) ? null : _confirmAndSaveChanges,
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
    final theme = Theme.of(context);
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
              style: const TextStyle(fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                labelText: 'Dirección del Restaurante',
                hintText: 'Toca para buscar dirección',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.location_on),
                suffixIcon: Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.search, size: 20),
                      onPressed: _selectAddress,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Teléfono
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono de Contacto',
                hintText: 'Ej: +52 656 123 4567',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            
            if (_selectedLocation != null) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(Icons.map_outlined, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Vista Previa de Ubicación',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _buildMiniMap(_selectedLocation!),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Confirmado en coordenadas: ${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w500),
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

  Widget _buildMiniMap(LatLng location) {
    return fm.FlutterMap(
      options: fm.MapOptions(
        initialCenter: ll.LatLng(location.latitude, location.longitude),
        initialZoom: 15.0,
        interactionOptions: const fm.InteractionOptions(flags: fm.InteractiveFlag.none),
      ),
      children: [
        fm.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.donarepartos.app',
        ),
        fm.MarkerLayer(
          markers: [
            fm.Marker(
              point: ll.LatLng(location.latitude, location.longitude),
              width: 40,
              height: 40,
              child: const Icon(
                Icons.location_on,
                color: Colors.red,
                size: 40,
              ),
            ),
          ],
        ),
      ],
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
          _buildUploadItem(
            title: 'Logo del Restaurante',
            subtitle: 'Imagen cuadrada (recomendado 512x512)',
            currentUrl: _logoUrl,
            isUploading: _isUploadingLogo,
            onUpload: (file) async {
              setState(() => _isUploadingLogo = true);
              try {
                final userId = SupabaseConfig.client.auth.currentUser?.id ?? widget.restaurant.userId;
                final url = await StorageService.uploadRestaurantLogo(userId, file);
                await SupabaseConfig.client
                    .from('restaurants')
                    .update({'logo_url': url, 'updated_at': DateTime.now().toIso8601String()})
                    .eq('id', widget.restaurant.id);
                debugPrint('✅ [EDIT] logo_url guardado en DB: $url');
                if (mounted) {
                  setState(() {
                    _logoUrl = url;
                    _isUploadingLogo = false;
                    _hasChanges = true;
                  });
                }
              } on StorageUploadException catch (e) {
                if (mounted) {
                  setState(() => _isUploadingLogo = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ ${e.message}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('❌ [EDIT] Error guardando logo_url en DB: $e');
                if (mounted) {
                  setState(() => _isUploadingLogo = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Error guardando imagen: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: Icons.storefront,
          ),
          
          const SizedBox(height: 24),
          
          // Foto de portada
          _buildUploadItem(
            title: 'Foto de Portada',
            subtitle: 'Imagen horizontal (recomendado 1920x1080)',
            currentUrl: _coverImageUrl,
            isUploading: _isUploadingCover,
            onUpload: (file) async {
              setState(() => _isUploadingCover = true);
              try {
                final userId = SupabaseConfig.client.auth.currentUser?.id ?? widget.restaurant.userId;
                final url = await StorageService.uploadRestaurantCover(userId, file);
                await SupabaseConfig.client
                    .from('restaurants')
                    .update({'cover_image_url': url, 'updated_at': DateTime.now().toIso8601String()})
                    .eq('id', widget.restaurant.id);
                debugPrint('✅ [EDIT] cover_image_url guardado en DB: $url');
                if (mounted) {
                  setState(() {
                    _coverImageUrl = url;
                    _isUploadingCover = false;
                    _hasChanges = true;
                  });
                }
              } on StorageUploadException catch (e) {
                if (mounted) {
                  setState(() => _isUploadingCover = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ ${e.message}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('❌ [EDIT] Error guardando cover_image_url en DB: $e');
                if (mounted) {
                  setState(() => _isUploadingCover = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Error guardando imagen: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: Icons.photo_library,
          ),
          
          const SizedBox(height: 24),
          // Eliminado: Foto del Menú (Opcional)
        ],
      ),
    );
  }

  Widget _buildUploadItem({
    required String title,
    required String subtitle,
    required String? currentUrl,
    required bool isUploading,
    required Function(PlatformFile) onUpload,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ImageUploadField(
            label: '',
            icon: Icons.cloud_upload,
            imageUrl: currentUrl,
            onImageSelected: (file) {
              if (file != null) {
                onUpload(file);
              }
            },
          ),
          if (isUploading)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              ),
            ),
        ],
      ),
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
          const SizedBox(height: 24),
          
          Text(
            'Redes Sociales',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
          _buildSocialField(
            controller: _facebookController,
            label: 'Facebook URL',
            hint: 'https://facebook.com/tu-restaurante',
            icon: Icons.facebook,
            color: Colors.blue.shade800,
          ),
          const SizedBox(height: 12),
          _buildSocialField(
            controller: _instagramController,
            label: 'Instagram URL',
            hint: 'https://instagram.com/tu-restaurante',
            icon: Icons.camera_alt,
            color: Colors.pink,
          ),
          const SizedBox(height: 12),
          _buildSocialField(
            controller: _websiteController,
            label: 'Sitio Web',
            hint: 'https://www.tu-restaurante.com',
            icon: Icons.language,
            color: Colors.teal,
          ),
        ],
      ),
    );
  }

  Widget _buildSocialField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            child: Icon(icon, color: color, size: 20),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          filled: true,
          fillColor: theme.colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        onChanged: (_) => _markChanged(),
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
    _phoneController.dispose();
    _deliveryRadiusController.dispose();
    _minOrderAmountController.dispose();
    _estimatedDeliveryTimeController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _websiteController.dispose();
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
