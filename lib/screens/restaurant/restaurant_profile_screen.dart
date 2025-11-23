import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/widgets/address_picker_modal.dart';
import 'package:doa_repartos/widgets/image_upload_field.dart';
import 'package:doa_repartos/widgets/phone_dial_input.dart';
import 'package:doa_repartos/services/storage_service.dart';
import 'package:doa_repartos/services/onboarding_notification_service.dart';
import 'package:doa_repartos/services/validation_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:file_picker/file_picker.dart';
import 'dart:async';

/// Pantalla completa para gestionar el perfil del restaurante
class RestaurantProfileScreen extends StatefulWidget {
  const RestaurantProfileScreen({super.key});

  @override
  State<RestaurantProfileScreen> createState() => _RestaurantProfileScreenState();
}

class _RestaurantProfileScreenState extends State<RestaurantProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controladores de texto
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cuisineTypeController = TextEditingController();

  // Opciones fijas para el tipo de cocina
  static const List<String> _cuisineOptions = [
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
  ];
  
  // Ubicación
  LatLng? _selectedLocation;
  String? _selectedPlaceId;
  Map<String, dynamic>? _addressStructured;
  
  // URLs de imágenes
  String? _logoUrl;
  String? _coverImageUrl;
  String? _facadeImageUrl;
  String? _menuImageUrl;
  String? _businessPermitUrl;
  String? _healthPermitUrl;
  
  // Archivos seleccionados para subir
  PlatformFile? _logoFile;
  PlatformFile? _coverImageFile;
  PlatformFile? _facadeImageFile;
  PlatformFile? _menuImageFile;
  PlatformFile? _businessPermitFile;
  PlatformFile? _healthPermitFile;
  
  // Estado del restaurante
  DoaRestaurant? _restaurant;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isOnline = false;
  // Original values for change detection
  String? _originalName;
  String? _originalPhone;

  // Realtime validation state
  String? _nameError;
  String? _phoneError;
  bool _isValidatingName = false;
  bool _isValidatingPhone = false;
  Timer? _nameTimer;
  Timer? _phoneTimer;
  
  // Onboarding/calculo de porcentaje y checklist (alineado con dashboard)
  OnboardingStatus? _onboardingStatus;
  bool _loadingChecklist = false;
  
  // Horario de negocio (simplificado por ahora)
  Map<String, dynamic>? _businessHours;

  @override
  void initState() {
    super.initState();
    _loadRestaurantProfile();
  }

  /// Abrir modal de selección de dirección
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
    }
  }

  /// Cargar perfil del restaurante del usuario actual
  Future<void> _loadRestaurantProfile() async {
    try {
      setState(() => _isLoading = true);
      
      final currentUser = SupabaseConfig.client.auth.currentUser;
      if (currentUser == null) return;
      
      // Buscar restaurante del usuario actual
      final response = await SupabaseConfig.client
          .from('restaurants')
          .select()
          .eq('user_id', currentUser.id)
          .maybeSingle();
      
      if (response != null) {
        _restaurant = DoaRestaurant.fromJson(response);
        
        // Cargar datos en controladores
        _nameController.text = _restaurant!.name;
        _descriptionController.text = _restaurant!.description ?? '';
        _addressController.text = response['address'] ?? '';
        _phoneController.text = response['phone'] ?? '';
        _originalName = _nameController.text.trim();
        _originalPhone = _phoneController.text.trim();
        _cuisineTypeController.text = _restaurant!.cuisineType ?? '';
        
        // Cargar ubicación
        if (response['location_lat'] != null && response['location_lon'] != null) {
          _selectedLocation = LatLng(
            (response['location_lat'] as num).toDouble(),
            (response['location_lon'] as num).toDouble(),
          );
          _selectedPlaceId = response['location_place_id'];
          _addressStructured = response['address_structured'];
        }
        
        // Cargar URLs de imágenes
        _logoUrl = _restaurant!.logoUrl;
        _coverImageUrl = _restaurant!.coverImageUrl;
        _facadeImageUrl = response['facade_image_url'];
        _menuImageUrl = _restaurant!.menuImageUrl;
        _businessPermitUrl = _restaurant!.businessPermitUrl;
        _healthPermitUrl = _restaurant!.healthPermitUrl;
        
        // Estado online
        _isOnline = _restaurant!.online;
        
        // Horario de negocio
        _businessHours = _restaurant!.businessHours;

        // Calcular checklist/porcentaje igual que en el dashboard principal
        _loadingChecklist = true;
        try {
          final status = await OnboardingNotificationService
              .calculateRestaurantOnboardingAsync(_restaurant!);
          _onboardingStatus = status;
        } catch (_) {
          // Silencioso; mantenemos fallback al porcentaje básico
        } finally {
          _loadingChecklist = false;
        }
      }
      
    } catch (e) {
      print('Error cargando perfil: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando perfil: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Subir imágenes a Supabase Storage
  Future<void> _uploadImages(String restaurantId, String userId) async {
    print('🚀 [UPLOAD] Iniciando subida de imágenes');
    print('   Restaurant ID: $restaurantId');
    print('   User ID: $userId');
    
    // Subir logo
    if (_logoFile != null) {
      print('📤 [UPLOAD] Subiendo logo...');
      final logoUrl = await StorageService.uploadRestaurantLogo(
        restaurantId,
        _logoFile!,
      );
      if (logoUrl != null) {
        _logoUrl = logoUrl;
        print('✅ [UPLOAD] Logo subido: $logoUrl');
      } else {
        print('❌ [UPLOAD] Error al subir logo');
      }
    }
    
    // Subir cover image
    if (_coverImageFile != null) {
      print('📤 [UPLOAD] Subiendo imagen de portada...');
      final coverUrl = await StorageService.uploadRestaurantCover(
        restaurantId,
        _coverImageFile!,
      );
      if (coverUrl != null) {
        _coverImageUrl = coverUrl;
        print('✅ [UPLOAD] Cover subido: $coverUrl');
      } else {
        print('❌ [UPLOAD] Error al subir cover');
      }
    }

    // Subir imagen de fachada
    if (_facadeImageFile != null) {
      print('📤 [UPLOAD] Subiendo imagen de fachada...');
      final facadeUrl = await StorageService.uploadRestaurantFacade(
        restaurantId,
        _facadeImageFile!,
      );
      if (facadeUrl != null) {
        _facadeImageUrl = facadeUrl;
        print('✅ [UPLOAD] Fachada subida: $facadeUrl');
      } else {
        print('❌ [UPLOAD] Error al subir fachada');
      }
    }
    
    // Subir business permit (usa userId para cumplir políticas)
    if (_businessPermitFile != null) {
      print('📤 [UPLOAD] Subiendo permiso de negocio...');
      final permitUrl = await StorageService.uploadRestaurantPermit(
        userId, // Cambiar a userId
        _businessPermitFile!,
        'business',
      );
      if (permitUrl != null) {
        _businessPermitUrl = permitUrl;
        print('✅ [UPLOAD] Permiso de negocio subido: $permitUrl');
      } else {
        print('❌ [UPLOAD] Error al subir permiso de negocio');
      }
    }
    
    // Subir health permit (usa userId para cumplir políticas)
    if (_healthPermitFile != null) {
      print('📤 [UPLOAD] Subiendo permiso de salubridad...');
      final healthUrl = await StorageService.uploadRestaurantPermit(
        userId, // Cambiar a userId
        _healthPermitFile!,
        'health',
      );
      if (healthUrl != null) {
        _healthPermitUrl = healthUrl;
        print('✅ [UPLOAD] Permiso de salubridad subido: $healthUrl');
      } else {
        print('❌ [UPLOAD] Error al subir permiso de salubridad');
      }
    }
    
    print('🏁 [UPLOAD] Subida de imágenes completada');
  }

  /// Guardar o crear perfil del restaurante
  Future<void> _saveRestaurantProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    try {
      setState(() => _isSaving = true);
      
      final currentUser = SupabaseConfig.client.auth.currentUser;
      if (currentUser == null) return;
      
      String restaurantId = _restaurant?.id ?? '';

      // Detectar cambios críticos (nombre/teléfono)
      final newName = _nameController.text.trim();
      final newPhone = _phoneController.text.trim();
      final changedCritical = (newName != (_originalName ?? newName)) || (newPhone != (_originalPhone ?? newPhone));

      // Validación de unicidad en BD (quirúrgica, bloquea duplicados) antes de confirmar
      final currentId = _restaurant?.id;
      // Nombre
      if (_restaurant == null) {
        final availableName = await ValidationService.isRestaurantNameAvailable(newName);
        if (!availableName) {
          setState(() { _nameError = 'Este nombre de restaurante ya está en uso'; });
          _formKey.currentState!.validate();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('❌ El nombre ya existe. Elige otro.')),
            );
          }
          setState(() => _isSaving = false);
          return;
        }
      } else if (newName != (_originalName ?? '')) {
        final availableName = await ValidationService.isRestaurantNameAvailableForUpdate(
          newName,
          excludeRestaurantId: currentId,
        );
        if (!availableName) {
          setState(() { _nameError = 'Este nombre de restaurante ya está en uso'; });
          _formKey.currentState!.validate();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('❌ El nombre ya existe. Elige otro.')),
            );
          }
          setState(() => _isSaving = false);
          return;
        }
      }

      // Teléfono (opcional)
      if (newPhone.isNotEmpty) {
        if (_restaurant == null) {
          final okPhone = await ValidationService.isRestaurantPhoneAvailable(newPhone);
          if (!okPhone) {
            setState(() { _phoneError = 'Este teléfono ya está registrado para otro restaurante'; });
            _formKey.currentState!.validate();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('❌ El teléfono ya existe. Verifica.')),
              );
            }
            setState(() => _isSaving = false);
            return;
          }
        } else if (newPhone != (_originalPhone ?? '')) {
          final okPhone = await ValidationService.isRestaurantPhoneAvailableForUpdate(
            newPhone,
            excludeRestaurantId: currentId,
          );
          if (!okPhone) {
            setState(() { _phoneError = 'Este teléfono ya está registrado para otro restaurante'; });
            _formKey.currentState!.validate();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('❌ El teléfono ya existe. Verifica.')),
              );
            }
            setState(() => _isSaving = false);
            return;
          }
        }
      }

      if (changedCritical) {
        final proceed = await _confirmPendingApprovalDialog();
        if (!proceed) {
          setState(() => _isSaving = false);
          return;
        }
      }
      
      // Si es actualización y hay imágenes nuevas, subirlas
      if (_restaurant != null && restaurantId.isNotEmpty) {
        print('🔄 [SAVE] Actualizando restaurante existente: $restaurantId');
        await _uploadImages(restaurantId, currentUser.id);
      } else {
        print('🆕 [SAVE] Creando nuevo restaurante...');
      }
      
      final data = {
        'user_id': currentUser.id,
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty 
            ? null 
            : _phoneController.text.trim(),
        'location_lat': _selectedLocation?.latitude,
        'location_lon': _selectedLocation?.longitude,
        'location_place_id': _selectedPlaceId,
        'address_structured': _addressStructured,
        'logo_url': _logoUrl,
        'cover_image_url': _coverImageUrl,
        'facade_image_url': _facadeImageUrl,
        'menu_image_url': _menuImageUrl,
        'business_permit_url': _businessPermitUrl,
        'health_permit_url': _healthPermitUrl,
        'cuisine_type': _cuisineTypeController.text.trim().isEmpty 
            ? null 
            : _cuisineTypeController.text.trim(),
        'online': _isOnline,
        'business_hours': _businessHours,
        'status': 'pending', // Nuevo restaurante siempre pending
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      if (_restaurant == null) {
        // Crear nuevo restaurante
        data['created_at'] = DateTime.now().toIso8601String();
        
        final response = await SupabaseConfig.client
            .from('restaurants')
            .insert(data)
            .select()
            .single();
        
        _restaurant = DoaRestaurant.fromJson(response);
        restaurantId = _restaurant!.id;
        print('✅ [SAVE] Restaurante creado con ID: $restaurantId');
        
        // Subir imágenes después de crear el restaurante
        await _uploadImages(restaurantId, currentUser.id);
        
        // Actualizar URLs de imágenes en la BD si hay imágenes
        if (_logoUrl != null || _coverImageUrl != null || _facadeImageUrl != null || _businessPermitUrl != null || _healthPermitUrl != null) {
          print('💾 [SAVE] Actualizando URLs de imágenes en la BD...');
          await SupabaseConfig.client
              .from('restaurants')
              .update({
                'logo_url': _logoUrl,
                'cover_image_url': _coverImageUrl,
                'facade_image_url': _facadeImageUrl,
                'business_permit_url': _businessPermitUrl,
                'health_permit_url': _healthPermitUrl,
              })
              .eq('id', restaurantId);
          print('✅ [SAVE] URLs de imágenes actualizadas');
        }
            
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Restaurante creado exitosamente')),
          );
        }
      } else {
        // Actualizar restaurante existente
        await SupabaseConfig.client
            .from('restaurants')
            .update(data)
            .eq('id', _restaurant!.id);
            
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Restaurante actualizado exitosamente')),
          );
          if (changedCritical) {
            _showPendingAfterSaveSheet();
          }
        }
      }
      
      // Recargar datos
      await _loadRestaurantProfile();
      
    } catch (e) {
      print('Error guardando perfil: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error guardando: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Restaurante'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoading)
            TextButton.icon(
              onPressed: _isSaving ? null : _saveRestaurantProfile,
              icon: _isSaving 
                  ? const SizedBox(
                      width: 16, 
                      height: 16, 
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save, color: Colors.white),
              label: const Text('GUARDAR', style: TextStyle(color: Colors.white)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isDesktop ? 24 : 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 1200 : double.infinity),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Estado del restaurante
                        if (_restaurant != null) ...[
                          _buildStatusCard(),
                          const SizedBox(height: 16),
                          _buildChecklistInfoSection(),
                          const SizedBox(height: 24),
                        ],
                        
                        // Layout adaptivo
                        if (isDesktop)
                          _buildDesktopLayout()
                        else
                          _buildMobileLayout(),
                        
                        const SizedBox(height: 32),
                        
                        // Botón guardar (móvil)
                        if (!isDesktop) _buildSaveButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ==== Validation and dialogs ====
  void _onNameChangedDebounced(String value) {
    _nameTimer?.cancel();
    // Skip validation if unchanged from original
    if (value.trim() == (_originalName ?? '')) {
      setState(() {
        _nameError = null;
        _isValidatingName = false;
      });
      return;
    }
    if (value.trim().length < 3) {
      setState(() {
        _nameError = 'El nombre debe tener al menos 3 caracteres';
        _isValidatingName = false;
      });
      return;
    }
    setState(() => _isValidatingName = true);
    _nameTimer = Timer(const Duration(milliseconds: 700), () async {
      try {
        final err = await ValidationService.validateRestaurantNameRealtime(value);
        if (!mounted) return;
        setState(() {
          _nameError = err; // null if OK
          _isValidatingName = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _nameError = 'Error validando nombre';
          _isValidatingName = false;
        });
      }
    });
  }

  void _onPhoneChangedDebounced(String fullPhone) {
    _phoneTimer?.cancel();
    final trimmed = fullPhone.trim();
    if (trimmed == (_originalPhone ?? '')) {
      setState(() {
        _phoneError = null;
        _isValidatingPhone = false;
      });
      return;
    }
    // Extract digits only for quick local check
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8) {
      setState(() {
        _phoneError = 'Ingresa un teléfono válido';
        _isValidatingPhone = false;
      });
      return;
    }
    setState(() => _isValidatingPhone = true);
    _phoneTimer = Timer(const Duration(milliseconds: 700), () async {
      try {
        final err = await ValidationService.validateRestaurantPhoneRealtime(trimmed);
        if (!mounted) return;
        setState(() {
          _phoneError = err; // null if OK
          _isValidatingPhone = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _phoneError = 'Error validando teléfono';
          _isValidatingPhone = false;
        });
      }
    });
  }

  Future<bool> _confirmPendingApprovalDialog() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.security, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Revisión Administrativa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Estás modificando datos sensibles (nombre o teléfono). Por seguridad, tu restaurante quedará PENDIENTE de aprobación hasta que el equipo admin revise los cambios. Este proceso puede tardar hasta 24 horas. Durante ese periodo, no podrás conectarte para recibir pedidos.',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                          child: const Text('Entiendo y continuar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result == true;
  }

  void _showPendingAfterSaveSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Row(
                  children: [
                    Icon(Icons.hourglass_bottom, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Cambios enviados para aprobación', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                SizedBox(height: 12),
                Text('Tu restaurante quedó pendiente de aprobación. Te notificaremos cuando sea aprobado (máximo 24 horas). Mientras tanto, la opción de conectarte estará deshabilitada.'),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Tarjeta de estado del restaurante
  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getStatusColor().withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getStatusColor().withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(_getStatusIcon(), color: _getStatusColor(), size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Estado: ${_getStatusText()}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _getStatusColor(),
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Badge compacto de estado
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getStatusShortLabel(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Ayuda/tooltip: abre explicación del flujo de revisión
                    IconButton(
                      tooltip: '¿Cómo funciona la aprobación?',
                      icon: const Icon(Icons.help_outline, size: 20),
                      color: _getStatusColor(),
                      onPressed: _showStatusHelpSheet,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _getStatusDescription(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          // Badge de completitud
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _getCompletionColor(),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_onboardingStatus?.percentage ?? _restaurant?.profileCompletionPercentage ?? 0}%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Checklist informativo (todas las tareas, con estilos según estado)
  Widget _buildChecklistInfoSection() {
    if (_loadingChecklist) {
      return Row(
        children: const [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Calculando checklist...'),
        ],
      );
    }

    final status = _onboardingStatus;
    if (status == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Checklist de Perfil',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade800,
              ),
        ),
        const SizedBox(height: 12),
        ...status.tasks.map((t) {
          final color = t.isCompleted ? Colors.green : Colors.red;
          final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                decoration: t.isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
              );
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  t.isCompleted ? Icons.check_circle : Icons.cancel,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, style: textStyle),
                      const SizedBox(height: 2),
                      Text(
                        t.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: color.withValues(alpha: 0.8),
                            ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  /// Layout para desktop (2 columnas)
  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Columna izquierda
        Expanded(
          child: Column(
            children: [
              _buildBasicInfoSection(),
              const SizedBox(height: 24),
              _buildImagesSection(),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Columna derecha
        Expanded(
          child: Column(
            children: [
              _buildBusinessDetailsSection(),
              const SizedBox(height: 24),
              _buildDocumentsSection(),
            ],
          ),
        ),
      ],
    );
  }

  /// Layout para móvil (1 columna)
  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildBasicInfoSection(),
        const SizedBox(height: 24),
        _buildImagesSection(),
        const SizedBox(height: 24),
        _buildBusinessDetailsSection(),
        const SizedBox(height: 24),
        _buildDocumentsSection(),
      ],
    );
  }

  /// Sección: Información Básica
  Widget _buildBasicInfoSection() {
    return _buildSection(
      title: 'Información Básica',
      icon: Icons.store,
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Nombre del Restaurante *',
            hintText: 'Ej: Pizzería Don Luigi',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.restaurant),
          ),
          onChanged: _onNameChangedDebounced,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'El nombre es obligatorio';
            }
            if (value.trim().length < 3) {
              return 'El nombre debe tener al menos 3 caracteres';
            }
            // If changed from original, include uniqueness error when present
            if (value.trim() != (_originalName ?? value.trim())) {
              if (_nameError != null) return _nameError;
              if (_isValidatingName) return 'Validando nombre...';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          decoration: const InputDecoration(
            labelText: 'Descripción',
            hintText: 'Ej: La mejor pizza italiana de la ciudad...',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.description),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        PhoneDialInput(
          controller: _phoneController,
          label: 'Teléfono',
          hint: 'Ej: 656-123-4567',
          prefixIcon: Icons.phone,
          onChangedFull: _onPhoneChangedDebounced,
          isValidating: _isValidatingPhone,
          errorText: (() {
            final val = _phoneController.text.trim();
            // only show uniqueness error if changed
            if (val != (_originalPhone ?? val)) return _phoneError;
            return null;
          })(),
          validator: (digits) {
            if (digits.isEmpty) return null; // optional
            if (digits.length < 8) return 'Ingresa un teléfono válido';
            // if changed and there is error
            final full = _phoneController.text.trim();
            if (full != (_originalPhone ?? full) && _phoneError != null) return _phoneError;
            if (_isValidatingPhone) return 'Validando teléfono...';
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _addressController,
          readOnly: true,
          onTap: _selectAddress,
          decoration: InputDecoration(
            labelText: 'Ubicación del Restaurante *',
            hintText: 'Toca para buscar dirección',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.location_on),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: _selectAddress,
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'La ubicación es obligatoria';
            }
            return null;
          },
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
          const SizedBox(height: 12),
          // Mini-mapa estático para confirmar visualmente la ubicación
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: fm.FlutterMap(
                options: fm.MapOptions(
                  initialCenter: ll.LatLng(
                    _selectedLocation!.latitude,
                    _selectedLocation!.longitude,
                  ),
                  initialZoom: 15,
                  interactionOptions: const fm.InteractionOptions(
                    flags: fm.InteractiveFlag.drag | fm.InteractiveFlag.pinchZoom,
                  ),
                ),
                children: [
                  fm.TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.doa.repartos',
                  ),
                  fm.MarkerLayer(
                    markers: [
                      fm.Marker(
                        point: ll.LatLng(
                          _selectedLocation!.latitude,
                          _selectedLocation!.longitude,
                        ),
                        width: 36,
                        height: 36,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.orange, width: 2),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: Offset(0, 2)),
                            ],
                          ),
                          child: const Center(child: Icon(Icons.storefront, color: Colors.orange, size: 18)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Sección: Imágenes del Restaurante (sin imagen del menú)
  Widget _buildImagesSection() {
    return _buildSection(
      title: 'Imágenes del Restaurante',
      icon: Icons.image,
      children: [
        ImageUploadField(
          label: 'Logo del Restaurante',
          icon: Icons.store,
          imageUrl: _logoUrl,
          onImageSelected: (file) {
            setState(() => _logoFile = file);
            print('🖼️ Logo seleccionado: ${file?.name}');
          },
          helpText: 'Logo que aparecerá en tu perfil',
        ),
        const SizedBox(height: 16),
        ImageUploadField(
          label: 'Imagen de Portada',
          icon: Icons.image,
          imageUrl: _coverImageUrl,
          onImageSelected: (file) {
            setState(() => _coverImageFile = file);
            print('🖼️ Cover seleccionado: ${file?.name}');
          },
          helpText: 'Imagen de banner de tu restaurante',
        ),
        const SizedBox(height: 16),
        ImageUploadField(
          label: 'Foto de Fachada (nueva)',
          icon: Icons.storefront,
          imageUrl: _facadeImageUrl,
          onImageSelected: (file) {
            setState(() => _facadeImageFile = file);
            print('🖼️ Fachada seleccionada: ${file?.name}');
          },
          helpText: 'Fachada del local/food truck para ayudar a repartidores',
        ),
      ],
    );
  }

  /// Sección: Detalles de Negocio
  Widget _buildBusinessDetailsSection() {
    return _buildSection(
      title: 'Detalles de Negocio',
      icon: Icons.business,
      children: [
        DropdownButtonFormField<String>(
          value: _cuisineTypeController.text.isNotEmpty
              ? _cuisineTypeController.text
              : null,
          decoration: const InputDecoration(
            labelText: 'Tipo de Cocina',
            hintText: 'Selecciona una opción',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.restaurant_menu),
          ),
          items: _cuisineOptions
              .map((c) => DropdownMenuItem<String>(
                    value: c,
                    child: Text(c),
                  ))
              .toList(),
          onChanged: (value) {
            setState(() {
              _cuisineTypeController.text = value ?? '';
            });
          },
        ),
        const SizedBox(height: 8),
        Text(
          'El radio de entrega, el mínimo y el tiempo se calcularán automáticamente según tu ubicación.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Sección: Documentos Legales
  Widget _buildDocumentsSection() {
    return _buildSection(
      title: 'Documentos Legales',
      icon: Icons.description,
      children: [
        ImageUploadField(
          label: 'Permiso de Negocio',
          icon: Icons.business_center,
          imageUrl: _businessPermitUrl,
          onImageSelected: (file) => setState(() => _businessPermitFile = file),
          helpText: 'Foto del permiso de operación de negocio',
        ),
        const SizedBox(height: 16),
        ImageUploadField(
          label: 'Permiso de Salubridad',
          icon: Icons.medical_services,
          imageUrl: _healthPermitUrl,
          onImageSelected: (file) => setState(() => _healthPermitFile = file),
          helpText: 'Foto del permiso de sanidad',
        ),
      ],
    );
  }

  /// Sección: Toggle Online/Offline
  Widget _buildToggleOnlineSection() {
    return _buildSection(
      title: 'Estado de Operación',
      icon: Icons.power_settings_new,
      children: [
        SwitchListTile(
          title: const Text('Restaurante en Línea'),
          subtitle: Text(_isOnline 
              ? 'Aceptando pedidos' 
              : 'No aceptando pedidos'),
          value: _isOnline,
          onChanged: (value) => setState(() => _isOnline = value),
          activeColor: Colors.green,
          secondary: Icon(
            _isOnline ? Icons.check_circle : Icons.cancel,
            color: _isOnline ? Colors.green : Colors.grey,
          ),
        ),
      ],
    );
  }

  /// Widget reutilizable para secciones
  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de la sección
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.orange),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ),
          // Contenido de la sección
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  /// Botón de guardar para móvil
  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveRestaurantProfile,
        icon: _isSaving 
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save),
        label: Text(_isSaving ? 'Guardando...' : 'Guardar Información'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  // Helpers de estado
  Color _getStatusColor() {
    if (_restaurant == null) return Colors.grey;
    
    switch (_restaurant!.status) {
      case RestaurantStatus.pending:
        return Colors.orange;
      case RestaurantStatus.approved:
        return Colors.green;
      case RestaurantStatus.rejected:
        return Colors.red;
    }
  }
  
  IconData _getStatusIcon() {
    if (_restaurant == null) return Icons.help_outline;
    
    switch (_restaurant!.status) {
      case RestaurantStatus.pending:
        return Icons.schedule;
      case RestaurantStatus.approved:
        return Icons.check_circle;
      case RestaurantStatus.rejected:
        return Icons.cancel;
    }
  }
  
  String _getStatusText() {
    if (_restaurant == null) return 'Sin registrar';
    
    switch (_restaurant!.status) {
      case RestaurantStatus.pending:
        return 'Pendiente de aprobación';
      case RestaurantStatus.approved:
        return 'Aprobado';
      case RestaurantStatus.rejected:
        return 'Rechazado';
    }
  }
  
  String _getStatusDescription() {
    if (_restaurant == null) return '';
    
    switch (_restaurant!.status) {
      case RestaurantStatus.pending:
        return 'Tu restaurante está siendo revisado por nuestro equipo';
      case RestaurantStatus.approved:
        return 'Tu restaurante está activo y puede recibir pedidos';
      case RestaurantStatus.rejected:
        return 'Tu restaurante fue rechazado. Contacta soporte para más información';
    }
  }

  String _getStatusShortLabel() {
    if (_restaurant == null) return '—';
    switch (_restaurant!.status) {
      case RestaurantStatus.pending:
        return 'Pendiente';
      case RestaurantStatus.approved:
        return 'Aprobado';
      case RestaurantStatus.rejected:
        return 'Rechazado';
    }
  }
  
  Color _getCompletionColor() {
    final percentage = _onboardingStatus?.percentage ?? _restaurant?.profileCompletionPercentage ?? 0;
    if (percentage >= 80) return Colors.green;
    if (percentage >= 50) return Colors.orange;
    return Colors.red;
  }

  void _showStatusHelpSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.info_outline, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Ayuda sobre estados y aprobación', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('• Pendiente: Tu perfil fue editado o creado y está en revisión (hasta 24 h).\n• Aprobado: Puedes conectarte y recibir pedidos.\n• Rechazado: Revisa observaciones del equipo y corrige la información.'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(Icons.privacy_tip_outlined, color: Colors.orange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('Cualquier cambio en tu perfil se envía a revisión. Durante ese tiempo, no podrás conectarte hasta la aprobación.'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text('Entendido'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _cuisineTypeController.dispose();
    _nameTimer?.cancel();
    _phoneTimer?.cancel();
    super.dispose();
  }
}
