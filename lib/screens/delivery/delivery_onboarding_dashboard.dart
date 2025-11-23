import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/widgets/delivery_profile_progress_card.dart';
import 'package:doa_repartos/services/storage_service.dart';
import 'package:doa_repartos/widgets/phone_dial_input.dart';

/// Stage 2: Delivery onboarding dashboard with checklist and document uploads
/// Route: /delivery/onboarding
class DeliveryOnboardingDashboard extends StatefulWidget {
  const DeliveryOnboardingDashboard({super.key});

  @override
  State<DeliveryOnboardingDashboard> createState() => _DeliveryOnboardingDashboardState();
}

class _DeliveryOnboardingDashboardState extends State<DeliveryOnboardingDashboard> {
  DoaUser? _agent;
  bool _loading = true;
  bool _saving = false;

  PlatformFile? _profileImage;
  PlatformFile? _idFront;
  PlatformFile? _idBack;
  PlatformFile? _vehiclePhoto;
  PlatformFile? _vehicleRegistration;
  PlatformFile? _vehicleInsurance;

  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        if (mounted) Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      // Prefer reading from users + delivery_agent_profiles to ensure profile fields are present
      Map<String, dynamic>? userRow;
      Map<String, dynamic>? profileRow;

      try {
        userRow = await SupabaseConfig.client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();
      } catch (_) {}

      try {
        // Primary source of document fields
        profileRow = await SupabaseConfig.client
            .from('delivery_agent_profiles')
            .select()
            .eq('user_id', user.id)
            .maybeSingle();
      } catch (_) {}

      // If a consolidated view exists, try it as an extra source
      if ((profileRow == null || profileRow.isEmpty) || (userRow == null)) {
        try {
          final viewRow = await SupabaseConfig.client
              .from('delivery_agents_view')
              .select('*')
              .or('id.eq.${user.id},user_id.eq.${user.id}')
              .maybeSingle();
          if (viewRow != null) {
            // viewRow may already contain merged fields; use it as base
            userRow ??= viewRow;
            // But prefer explicit profileRow overlay if exists
            profileRow ??= viewRow;
          }
        } catch (_) {}
      }

      // Merge maps: user base + overlay profile fields
      final merged = <String, dynamic>{
        if (userRow != null) ...userRow,
        if (profileRow != null) ...profileRow,
      };

      if (merged.isNotEmpty) {
        _agent = DoaUser.fromJson(merged);
        _emergencyNameController.text = _agent?.emergencyContactName ?? '';
        _emergencyPhoneController.text = _agent?.emergencyContactPhone ?? '';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando perfil: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_agent == null) return;
    setState(() => _saving = true);
    try {
      final userId = _agent!.id;

      String? profileImageUrl;
      String? idFrontUrl;
      String? idBackUrl;
      String? vehiclePhotoUrl;
      String? vehicleRegUrl;
      String? vehicleInsUrl;

      if (_profileImage != null) profileImageUrl = await StorageService.uploadProfileImage(userId, _profileImage!);
      if (_idFront != null) idFrontUrl = await StorageService.uploadIdDocumentFront(userId, _idFront!);
      if (_idBack != null) idBackUrl = await StorageService.uploadIdDocumentBack(userId, _idBack!);
      if (_vehiclePhoto != null) vehiclePhotoUrl = await StorageService.uploadVehiclePhoto(userId, _vehiclePhoto!);
      if (_vehicleRegistration != null) vehicleRegUrl = await StorageService.uploadVehicleRegistration(userId, _vehicleRegistration!);
      if (_vehicleInsurance != null) vehicleInsUrl = await StorageService.uploadVehicleInsurance(userId, _vehicleInsurance!);

      // Upsert delivery profile via secure RPC wrapper
      await SupabaseDeliveryProfileExtensions.updateMyDeliveryProfile({
        'p_user_id': userId,
        if (profileImageUrl != null) 'profile_image_url': profileImageUrl,
        if (idFrontUrl != null) 'id_document_front_url': idFrontUrl,
        if (idBackUrl != null) 'id_document_back_url': idBackUrl,
        if (vehiclePhotoUrl != null) 'vehicle_photo_url': vehiclePhotoUrl,
        if (vehicleRegUrl != null) 'vehicle_registration_url': vehicleRegUrl,
        if (vehicleInsUrl != null) 'vehicle_insurance_url': vehicleInsUrl,
        if (_emergencyNameController.text.trim().isNotEmpty) 'emergency_contact_name': _emergencyNameController.text.trim(),
        if (_emergencyPhoneController.text.trim().isNotEmpty) 'emergency_contact_phone': _emergencyPhoneController.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos guardados'), backgroundColor: Colors.green),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando datos: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickFile(Function(PlatformFile) setter) async {
    final res = await FilePicker.platform.pickFiles(withReadStream: false, allowMultiple: false, type: FileType.image);
    if (res != null && res.files.isNotEmpty) {
      setter(res.files.first);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Completar registro de Repartidor'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _agent == null
              ? const Center(child: Text('No se encontró el usuario'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DeliveryProfileProgressCard(
                          deliveryAgent: _agent!,
                          onUploadDocsTap: () {},
                        ),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('Sube tus documentos', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 8),

                        _Section(
                          title: 'Foto de Perfil',
                          description: 'Una foto clara de tu rostro',
                          color: Colors.blue,
                          children: [
                            _UploadTile(
                              label: 'Foto de perfil',
                              value: _profileImage?.name ?? (_agent?.profileImageUrl != null ? 'Ya cargada' : 'Sin archivo'),
                              isUploaded: _profileImage != null || (_agent?.profileImageUrl != null && _agent!.profileImageUrl!.isNotEmpty),
                              onPick: () => _pickFile((f) => _profileImage = f),
                            ),
                          ],
                        ),

                        _Section(
                          title: 'Identificación oficial',
                          description: 'INE/IFE frente y reverso',
                          color: Colors.orange,
                          children: [
                            _UploadTile(
                              label: 'Frente',
                              value: _idFront?.name ?? (_agent?.idDocumentFrontUrl != null ? 'Ya cargada' : 'Sin archivo'),
                              isUploaded: _idFront != null || (_agent?.idDocumentFrontUrl != null && _agent!.idDocumentFrontUrl!.isNotEmpty),
                              onPick: () => _pickFile((f) => _idFront = f),
                            ),
                            _UploadTile(
                              label: 'Reverso',
                              value: _idBack?.name ?? (_agent?.idDocumentBackUrl != null ? 'Ya cargada' : 'Sin archivo'),
                              isUploaded: _idBack != null || (_agent?.idDocumentBackUrl != null && _agent!.idDocumentBackUrl!.isNotEmpty),
                              onPick: () => _pickFile((f) => _idBack = f),
                            ),
                          ],
                        ),

                        _Section(
                          title: 'Vehículo',
                          description: 'Sube una foto y documentos (si aplica)',
                          color: Colors.purple,
                          children: [
                            _UploadTile(
                              label: 'Foto del vehículo',
                              value: _vehiclePhoto?.name ?? (_agent?.vehiclePhotoUrl != null ? 'Ya cargada' : 'Sin archivo'),
                              isUploaded: _vehiclePhoto != null || (_agent?.vehiclePhotoUrl != null && _agent!.vehiclePhotoUrl!.isNotEmpty),
                              onPick: () => _pickFile((f) => _vehiclePhoto = f),
                            ),
                            _UploadTile(
                              label: 'Tarjeta de circulación',
                              value: _vehicleRegistration?.name ?? (_agent?.vehicleRegistrationUrl != null ? 'Ya cargada' : 'Sin archivo'),
                              isUploaded: _vehicleRegistration != null || (_agent?.vehicleRegistrationUrl != null && _agent!.vehicleRegistrationUrl!.isNotEmpty),
                              onPick: () => _pickFile((f) => _vehicleRegistration = f),
                            ),
                            _UploadTile(
                              label: 'Seguro del vehículo',
                              value: _vehicleInsurance?.name ?? (_agent?.vehicleInsuranceUrl != null ? 'Ya cargada' : 'Sin archivo'),
                              isUploaded: _vehicleInsurance != null || (_agent?.vehicleInsuranceUrl != null && _agent!.vehicleInsuranceUrl!.isNotEmpty),
                              onPick: () => _pickFile((f) => _vehicleInsurance = f),
                            ),
                          ],
                        ),

                        _Section(
                          title: 'Contacto de emergencia',
                          description: 'Alguien a quien podamos llamar si es necesario',
                          color: Colors.red,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: TextFormField(
                                controller: _emergencyNameController,
                                decoration: const InputDecoration(labelText: 'Nombre'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: PhoneDialInput(
                                controller: _emergencyPhoneController,
                                label: 'Teléfono',
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: const Icon(Icons.save, color: Colors.white),
                            label: _saving
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Guardar cambios', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14)),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String description;
  final Color color;
  final List<Widget> children;
  const _Section({
    required this.title,
    required this.description,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rtl, color: color),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(description, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          ...children,
          const SizedBox(height: 8),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  final String label;
  final String value;
  final bool isUploaded;
  final VoidCallback onPick;
  const _UploadTile({
    required this.label,
    required this.value,
    required this.isUploaded,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final color = isUploaded ? Colors.green : Colors.red;
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: isUploaded ? Colors.green : Colors.red,
          fontWeight: FontWeight.w600,
        );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(isUploaded ? Icons.check_circle : Icons.upload_file, color: color),
      title: Text(label, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isUploaded ? Icons.check : Icons.error_outline, size: 14, color: color),
                const SizedBox(width: 4),
                Text(isUploaded ? 'Ya cargada' : 'Sin archivo', style: textStyle),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
      trailing: ElevatedButton.icon(
        onPressed: onPick,
        icon: Icon(isUploaded ? Icons.edit : Icons.attach_file, color: Colors.white),
        label: Text(isUploaded ? 'Cambiar' : 'Seleccionar', style: const TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}
