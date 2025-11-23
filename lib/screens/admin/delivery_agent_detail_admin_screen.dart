import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

/// Admin view: Full delivery agent details page with tabs
/// - Combines users + delivery_agent_profiles + client_profiles (si lo reviso)
/// - Shows all info: general, documents, orders, reviews, finances, location history, admin actions
class AdminDeliveryAgentDetailScreen extends StatefulWidget {
  final DoaUser agent;
  const AdminDeliveryAgentDetailScreen({super.key, required this.agent});

  @override
  State<AdminDeliveryAgentDetailScreen> createState() => _AdminDeliveryAgentDetailScreenState();
}

class _AdminDeliveryAgentDetailScreenState extends State<AdminDeliveryAgentDetailScreen> with SingleTickerProviderStateMixin {
  bool _loading = true;
  DoaUser? _agent; // enriched with profile
  DoaAccount? _account;
  List<DoaAccountTransaction> _allTx = [];
  List<DoaOrder> _recentOrders = [];
  List<Map<String, dynamic>> _reviews = [];
  List<Map<String, dynamic>> _locationHistory = [];
  double _avgRating = 0;
  int _totalReviews = 0;
  late TabController _tabController;
  
  // Profile fields from delivery_agent_profiles según DATABASE_SCHEMA.sql
  String? _profileImageUrl;
  String? _idDocumentFrontUrl;
  String? _idDocumentBackUrl;
  String? _vehicleType;
  String? _vehiclePlate;
  String? _vehicleModel;
  String? _vehicleColor;
  String? _vehicleRegistrationUrl;
  String? _vehicleInsuranceUrl;
  String? _vehiclePhotoUrl;
  String? _emergencyContactName;
  String? _emergencyContactPhone;
  bool _onboardingCompleted = false;
  DateTime? _onboardingCompletedAt;
  String _status = 'pending';
  String _accountState = 'pending';
  DateTime? _createdAt;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final id = widget.agent.id;

      // 1) users base data
      final userRaw = await SupabaseConfig.client
          .from('users')
          .select('id, email, name, phone, role, created_at, updated_at, email_confirm')
          .eq('id', id)
          .maybeSingle();
      final agent = userRaw != null ? DoaUser.fromJson(userRaw) : widget.agent;

      // 2) delivery_agent_profiles - TODOS los campos según DATABASE_SCHEMA.sql
      String? profileImg, idFront, idBack, vType, vPlate, vModel, vColor, vReg, vIns, vPhoto, emergName, emergPhone;
      bool onbCompleted = false;
      DateTime? onbCompAt, profCreatedAt, profUpdatedAt;
      String status = 'pending', accState = 'pending';
      try {
        final profRaw = await SupabaseConfig.client
            .from('delivery_agent_profiles')
            .select('user_id, profile_image_url, id_document_front_url, id_document_back_url, vehicle_type, vehicle_plate, vehicle_model, vehicle_color, vehicle_registration_url, vehicle_insurance_url, vehicle_photo_url, emergency_contact_name, emergency_contact_phone, onboarding_completed, onboarding_completed_at, created_at, updated_at, status, account_state')
            .eq('user_id', id)
            .maybeSingle();
        if (profRaw != null) {
          profileImg = profRaw['profile_image_url'];
          idFront = profRaw['id_document_front_url'];
          idBack = profRaw['id_document_back_url'];
          vType = profRaw['vehicle_type'];
          vPlate = profRaw['vehicle_plate'];
          vModel = profRaw['vehicle_model'];
          vColor = profRaw['vehicle_color'];
          vReg = profRaw['vehicle_registration_url'];
          vIns = profRaw['vehicle_insurance_url'];
          vPhoto = profRaw['vehicle_photo_url'];
          emergName = profRaw['emergency_contact_name'];
          emergPhone = profRaw['emergency_contact_phone'];
          onbCompleted = profRaw['onboarding_completed'] ?? false;
          if (profRaw['onboarding_completed_at'] != null) {
            onbCompAt = DateTime.parse(profRaw['onboarding_completed_at']);
          }
          if (profRaw['created_at'] != null) profCreatedAt = DateTime.parse(profRaw['created_at']);
          if (profRaw['updated_at'] != null) profUpdatedAt = DateTime.parse(profRaw['updated_at']);
          status = profRaw['status'] ?? 'pending';
          accState = profRaw['account_state'] ?? 'pending';
        }
      } catch (e) {
        debugPrint('❌ Error loading delivery_agent_profiles: $e');
      }

      // 3) Financial account
      DoaAccount? account;
      List<DoaAccountTransaction> tx = [];
      try {
        final accRaw = await SupabaseConfig.client
            .from('accounts')
            .select('id, user_id, account_type, balance, created_at, updated_at')
            .eq('user_id', id)
            .maybeSingle();
        if (accRaw != null) {
          account = DoaAccount.fromJson(accRaw);
          final txRaw = await SupabaseConfig.client
              .from('account_transactions')
              .select('id, account_id, type, amount, order_id, settlement_id, description, metadata, created_at')
              .eq('account_id', account.id)
              .order('created_at', ascending: false)
              .limit(50);
          tx = txRaw.map<DoaAccountTransaction>((j) => DoaAccountTransaction.fromJson(j)).toList();
        }
      } catch (e) {
        debugPrint('❌ Error loading account: $e');
      }

      // 4) Recent orders assigned to this agent
      List<DoaOrder> orders = [];
      try {
        final ordersRaw = await SupabaseConfig.client
            .from('orders')
            .select('id, user_id, restaurant_id, delivery_agent_id, status, total_amount, delivery_fee, subtotal, created_at, updated_at, delivery_time, pickup_time, assigned_at, delivery_address, payment_method')
            .eq('delivery_agent_id', id)
            .order('created_at', ascending: false)
            .limit(30);
        orders = (ordersRaw as List).map((j) => DoaOrder.fromJson(Map<String, dynamic>.from(j))).toList();
      } catch (e) {
        debugPrint('❌ Error loading orders: $e');
      }

      // 5) Reviews about this delivery agent - con author name
      List<Map<String, dynamic>> reviews = [];
      double avg = 0;
      int total = 0;
      try {
        final reviewsRaw = await SupabaseConfig.client
            .from('reviews')
            .select('id, order_id, author_id, author_role, rating, comment, created_at, author:users!reviews_author_id_fkey(name)')
            .eq('subject_user_id', id)
            .order('created_at', ascending: false);
        if (reviewsRaw is List && reviewsRaw.isNotEmpty) {
          reviews = List<Map<String, dynamic>>.from(reviewsRaw);
          total = reviews.length;
          avg = reviews.map((e) => (e['rating'] as num?)?.toDouble() ?? 0).fold<double>(0, (a, b) => a + b) / total;
        }
      } catch (e) {
        debugPrint('❌ Error loading reviews: $e');
      }

      // 6) Location history from courier_locations_history
      List<Map<String, dynamic>> locHistory = [];
      try {
        final locRaw = await SupabaseConfig.client
            .from('courier_locations_history')
            .select('id, user_id, order_id, lat, lon, accuracy, speed, heading, recorded_at')
            .eq('user_id', id)
            .order('recorded_at', ascending: false)
            .limit(50);
        locHistory = List<Map<String, dynamic>>.from(locRaw);
      } catch (e) {
        debugPrint('❌ Error loading location history: $e');
      }

      if (!mounted) return;
      setState(() {
        _agent = agent;
        _profileImageUrl = profileImg;
        _idDocumentFrontUrl = idFront;
        _idDocumentBackUrl = idBack;
        _vehicleType = vType;
        _vehiclePlate = vPlate;
        _vehicleModel = vModel;
        _vehicleColor = vColor;
        _vehicleRegistrationUrl = vReg;
        _vehicleInsuranceUrl = vIns;
        _vehiclePhotoUrl = vPhoto;
        _emergencyContactName = emergName;
        _emergencyContactPhone = emergPhone;
        _onboardingCompleted = onbCompleted;
        _onboardingCompletedAt = onbCompAt;
        _status = status;
        _accountState = accState;
        _createdAt = profCreatedAt;
        _updatedAt = profUpdatedAt;
        _account = account;
        _allTx = tx;
        _recentOrders = orders;
        _reviews = reviews;
        _avgRating = avg;
        _totalReviews = total;
        _locationHistory = locHistory;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ ERROR LOADING DELIVERY AGENT: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando repartidor: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _agent ?? widget.agent;
    final displayName = (a.name?.isNotEmpty ?? false) ? a.name! : a.email;
    return Scaffold(
      appBar: AppBar(
        title: Text(displayName),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'General', icon: Icon(Icons.info_outline, size: 20)),
            Tab(text: 'Documentos', icon: Icon(Icons.description, size: 20)),
            Tab(text: 'Órdenes', icon: Icon(Icons.receipt_long, size: 20)),
            Tab(text: 'Reseñas', icon: Icon(Icons.star, size: 20)),
            Tab(text: 'Finanzas', icon: Icon(Icons.account_balance_wallet, size: 20)),
            Tab(text: 'Admin', icon: Icon(Icons.admin_panel_settings, size: 20)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildGeneralTab(),
                _buildDocumentsTab(),
                _buildOrdersTab(),
                _buildReviewsTab(),
                _buildFinancesTab(),
                _buildAdminTab(),
              ],
            ),
    );
  }

  // TAB 1: GENERAL
  Widget _buildGeneralTab() {
    final a = _agent ?? widget.agent;
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(a),
          const SizedBox(height: 16),
          _buildQuickStats(a),
          const SizedBox(height: 16),
          _buildProfileSection(),
          const SizedBox(height: 16),
          _buildVehicleSection(),
          const SizedBox(height: 16),
          _buildEmergencyContactSection(),
          const SizedBox(height: 16),
          _buildOnboardingSection(),
        ],
      ),
    );
  }

  // TAB 2: DOCUMENTOS
  Widget _buildDocumentsTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Documentos del Repartidor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildDocuments(),
        ],
      ),
    );
  }

  // TAB 3: ÓRDENES
  Widget _buildOrdersTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Órdenes Asignadas (${_recentOrders.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildOrdersList(),
        ],
      ),
    );
  }

  // TAB 4: RESEÑAS
  Widget _buildReviewsTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 28),
              const SizedBox(width: 8),
              Text('${_avgRating.toStringAsFixed(1)} / 5.0', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('($_totalReviews reseñas)', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 16),
          _buildReviewsList(),
        ],
      ),
    );
  }

  // TAB 5: FINANZAS
  Widget _buildFinancesTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Cuenta Financiera', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildFinancials(),
          const SizedBox(height: 16),
          const Text('Historial de Ubicaciones (últimas 50)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildLocationHistory(),
        ],
      ),
    );
  }

  // TAB 6: ADMIN (acciones administrativas)
  Widget _buildAdminTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Acciones Administrativas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildAdminActions(),
        ],
      ),
    );
  }

  Widget _buildHeader(DoaUser a) {
    final avatar = _profileImageUrl;
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: Colors.blue.shade100,
              backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
              child: (avatar == null || avatar.isEmpty)
                  ? Icon(Icons.person, color: Colors.blue.shade700, size: 36)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (a.name?.isNotEmpty ?? false) ? a.name! : a.email,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(icon: _statusIcon(_status), label: _statusLabel(_status), color: _statusColor(_status)),
                      _chip(icon: Icons.account_circle, label: _accountStateLabel(_accountState), color: _accountStateColor(_accountState)),
                      _chip(icon: Icons.star, label: _avgRating.toStringAsFixed(1), color: Colors.amber),
                      if ((_vehicleType ?? '').isNotEmpty)
                        _chip(icon: Icons.pedal_bike, label: _vehicleType!, color: Colors.blue),
                      if ((_vehiclePlate ?? '').isNotEmpty)
                        _chip(icon: Icons.confirmation_number, label: _vehiclePlate!, color: Colors.teal),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(String s) {
    if (s == 'approved') return Icons.check_circle;
    if (s == 'rejected') return Icons.cancel;
    return Icons.pending;
  }

  String _statusLabel(String s) {
    if (s == 'pending') return 'Pendiente';
    if (s == 'approved') return 'Aprobado';
    if (s == 'rejected') return 'Rechazado';
    return s;
  }

  Color _statusColor(String s) {
    if (s == 'approved') return Colors.green;
    if (s == 'rejected') return Colors.red;
    return Colors.orange;
  }

  String _accountStateLabel(String s) {
    if (s == 'pending') return 'Cuenta: Pendiente';
    if (s == 'active') return 'Cuenta: Activa';
    if (s == 'suspended') return 'Cuenta: Suspendida';
    return s;
  }

  Color _accountStateColor(String s) {
    if (s == 'active') return Colors.green;
    if (s == 'suspended') return Colors.red;
    return Colors.orange;
  }

  Widget _chip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildQuickStats(DoaUser a) {
    final cells = <_StatCell>[
      _StatCell(Icons.email, a.email, 'Email'),
      _StatCell(Icons.phone, a.phone ?? '—', 'Teléfono'),
      _StatCell(Icons.calendar_today, a.createdAt != null ? _formatDate(a.createdAt!) : '—', 'Usuario Creado'),
      _StatCell(Icons.verified_user, a.emailConfirm ? 'Sí' : 'No', 'Email Verificado'),
      _StatCell(Icons.directions_car, _vehicleModel ?? '—', 'Modelo vehículo'),
      _StatCell(Icons.color_lens, _vehicleColor ?? '—', 'Color vehículo'),
      _StatCell(Icons.account_balance_wallet, _account != null ? _formatCurrency(_account!.balance) : '—', 'Saldo'),
      _StatCell(Icons.receipt_long, '${_recentOrders.length}', 'Órdenes Asignadas'),
    ];

    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(builder: (context, c) {
          final width = c.maxWidth;
          final perRow = width > 1000
              ? 6
              : width > 700
                  ? 3
                  : 2;
          return Wrap(
            runSpacing: 12,
            spacing: 12,
            children: [
              for (final cell in cells)
                SizedBox(
                  width: (width - (perRow - 1) * 12) / perRow,
                  child: _buildStatTile(cell),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildStatTile(_StatCell cell) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(cell.icon, color: Colors.blue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cell.title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text(cell.value, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {IconData icon = Icons.info}) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildProfileSection() {
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.person, color: Colors.blue),
                SizedBox(width: 8),
                Text('Perfil del Repartidor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(Icons.image, 'Foto perfil', _profileImageUrl ?? 'No subida'),
            _infoRow(Icons.calendar_today, 'Perfil creado', _createdAt != null ? _formatDate(_createdAt!) : '—'),
            _infoRow(Icons.update, 'Perfil actualizado', _updatedAt != null ? _formatDate(_updatedAt!) : '—'),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleSection() {
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.directions_car, color: Colors.blue),
                SizedBox(width: 8),
                Text('Información del Vehículo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(Icons.category, 'Tipo', _vehicleType ?? '—'),
            _infoRow(Icons.confirmation_number, 'Placa', _vehiclePlate ?? '—'),
            _infoRow(Icons.car_repair, 'Modelo', _vehicleModel ?? '—'),
            _infoRow(Icons.palette, 'Color', _vehicleColor ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyContactSection() {
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.contact_phone, color: Colors.red),
                SizedBox(width: 8),
                Text('Contacto de Emergencia', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(Icons.person, 'Nombre', _emergencyContactName ?? '—'),
            _infoRow(Icons.phone, 'Teléfono', _emergencyContactPhone ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _buildOnboardingSection() {
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.checklist, color: Colors.green),
                SizedBox(width: 8),
                Text('Onboarding', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(Icons.check_circle, 'Completado', _onboardingCompleted ? 'Sí' : 'No'),
            if (_onboardingCompletedAt != null)
              _infoRow(Icons.calendar_today, 'Fecha completado', _formatDate(_onboardingCompletedAt!)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade600, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }

  Widget _buildDocuments() {
    final docs = <_DocCell>[
      _DocCell('Foto perfil', _profileImageUrl, Icons.person),
      _DocCell('INE Frente', _idDocumentFrontUrl, Icons.badge),
      _DocCell('INE Reverso', _idDocumentBackUrl, Icons.badge_outlined),
      _DocCell('Foto vehículo', _vehiclePhotoUrl, Icons.directions_bike),
      _DocCell('Tarjeta circulación', _vehicleRegistrationUrl, Icons.description),
      _DocCell('Seguro', _vehicleInsuranceUrl, Icons.shield_outlined),
    ];

    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      final perRow = width > 1000
          ? 6
          : width > 800
              ? 4
              : width > 500
                  ? 3
                  : 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final d in docs)
            SizedBox(
              width: (width - (perRow - 1) * 12) / perRow,
              child: _docTile(d),
            ),
        ],
      );
    });
  }

  Widget _docTile(_DocCell d) {
    final has = (d.url ?? '').isNotEmpty;
    final color = has ? Colors.green : Colors.red;
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: has
                ? Image.network(d.url!, fit: BoxFit.cover)
                : Container(
                    color: Colors.grey.shade200,
                    child: Icon(d.icon, color: Colors.grey, size: 36),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(has ? Icons.check_circle : Icons.cancel, color: color, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    d.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildReviewsList() {
    if (_reviews.isEmpty) {
      return _emptyState('Sin reseñas');
    }
    return Column(
      children: [
        for (final r in _reviews)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.blue.shade100,
                      child: Text(
                        ((r['author'] as Map?)?['name'] as String? ?? 'U')[0].toUpperCase(),
                        style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((r['author'] as Map?)?['name'] ?? 'Usuario', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(r['author_role'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    ...List.generate(
                      5,
                      (i) => Icon(
                        i < (r['rating'] as int? ?? 0) ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                if ((r['comment'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text((r['comment'] as String), style: TextStyle(color: Colors.grey.shade800)),
                ],
                const SizedBox(height: 6),
                Text(
                  r['created_at'] != null ? _formatDate(DateTime.parse(r['created_at'])) : '',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          )
      ],
    );
  }

  Widget _buildOrdersList() {
    if (_recentOrders.isEmpty) {
      return _emptyState('No hay órdenes asignadas a este repartidor');
    }
    return Column(
      children: [
        for (final o in _recentOrders)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.receipt_long, color: Colors.blue.shade600),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Orden ${o.id.substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('${o.status} • ${o.createdAt != null ? _formatDate(o.createdAt!) : ''}'),
                        ],
                      ),
                    ),
                    Text(_formatCurrency(o.totalAmount), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                _infoRow(Icons.location_on, 'Dirección', o.deliveryAddress ?? '—'),
                _infoRow(Icons.payment, 'Método pago', (o.paymentMethod ?? '—').toString()),
                if (o.deliveryFee != null) _infoRow(Icons.local_shipping, 'Tarifa entrega', _formatCurrency(o.deliveryFee!)),
              ],
            ),
          )
      ],
    );
  }

  Widget _buildFinancials() {
    if (_account == null) {
      return _emptyState('Sin cuenta financiera asociada');
    }

    final balance = _account!.balance;
    final balanceColor = balance > 0 ? Colors.green : (balance < 0 ? Colors.red : Colors.blue);
    final balanceLabel = balance > 0 ? 'SALDO' : (balance < 0 ? 'DEUDA' : 'LIQUIDADO');

    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet, color: balanceColor),
                const SizedBox(width: 8),
                Text('Saldo: ${_formatCurrency(balance)}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: balanceColor)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: balanceColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: balanceColor),
                  ),
                  child: Text(balanceLabel, style: TextStyle(color: balanceColor, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Tipo de cuenta: ${_account!.accountType}', style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Text('Transacciones (${_allTx.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_allTx.isEmpty) _emptyState('Sin transacciones'),
            if (_allTx.isNotEmpty)
              Column(
                children: [
                  for (final t in _allTx)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.grey.shade50,
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(t.type.icon, color: t.type.color, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(t.type.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              Text(_formatCurrency(t.amount), style: TextStyle(color: t.isCredit ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(t.createdAt != null ? _formatDate(t.createdAt!) : '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          if ((t.description ?? '').isNotEmpty) ...[ 
                            const SizedBox(height: 4),
                            Text(t.description!, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                          ],
                          if (t.orderId != null) Text('Orden: ${t.orderId!.substring(0, 8)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ),
                    )
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationHistory() {
    if (_locationHistory.isEmpty) {
      return _emptyState('Sin historial de ubicaciones');
    }
    return Column(
      children: [
        for (final loc in _locationHistory)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Lat: ${loc['lat']}, Lon: ${loc['lon']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(loc['recorded_at'] != null ? _formatDate(DateTime.parse(loc['recorded_at'])) : '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (loc['order_id'] != null) Text('Orden: ${(loc['order_id'] as String).substring(0, 8)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                if (loc['speed'] != null) Text('Velocidad: ${loc['speed']} m/s', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                if (loc['heading'] != null) Text('Dirección: ${loc['heading']}°', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          )
      ],
    );
  }

  Widget _buildAdminActions() {
    return Column(
      children: [
        _buildActionButton(
          icon: Icons.check_circle,
          label: 'Aprobar Repartidor',
          color: Colors.green,
          onTap: () => _updateStatus('approved'),
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: Icons.cancel,
          label: 'Rechazar Repartidor',
          color: Colors.red,
          onTap: () => _updateStatus('rejected'),
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: Icons.pending,
          label: 'Marcar como Pendiente',
          color: Colors.orange,
          onTap: () => _updateStatus('pending'),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: Icons.lock_open,
          label: 'Activar Cuenta',
          color: Colors.green,
          onTap: () => _updateAccountState('active'),
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: Icons.lock,
          label: 'Suspender Cuenta',
          color: Colors.red,
          onTap: () => _updateAccountState('suspended'),
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: Icons.pending_actions,
          label: 'Marcar Cuenta como Pendiente',
          color: Colors.orange,
          onTap: () => _updateAccountState('pending'),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: Icons.add_circle,
          label: 'Agregar Saldo Manual',
          color: Colors.blue,
          onTap: _addBalanceManual,
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: Icons.remove_circle,
          label: 'Descontar Saldo Manual',
          color: Colors.purple,
          onTap: _deductBalanceManual,
        ),
      ],
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color),
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
              ),
              Icon(Icons.arrow_forward_ios, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateStatus(String newStatus) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar cambio'),
        content: Text('¿Cambiar el status a "$newStatus"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await SupabaseConfig.client
          .from('delivery_agent_profiles')
          .update({'status': newStatus, 'updated_at': DateTime.now().toIso8601String()})
          .eq('user_id', widget.agent.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status actualizado a "$newStatus"')));
      _loadAll();
    } catch (e) {
      debugPrint('❌ Error updating status: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _updateAccountState(String newState) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar cambio'),
        content: Text('¿Cambiar el estado de la cuenta a "$newState"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await SupabaseConfig.client
          .from('delivery_agent_profiles')
          .update({'account_state': newState, 'updated_at': DateTime.now().toIso8601String()})
          .eq('user_id', widget.agent.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Estado de cuenta actualizado a "$newState"')));
      _loadAll();
    } catch (e) {
      debugPrint('❌ Error updating account_state: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _addBalanceManual() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar Saldo'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Monto (positivo)', hintText: '100.00'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Agregar')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final amount = double.tryParse(result);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monto inválido')));
      return;
    }
    await _adjustBalance(amount, 'Ajuste manual (admin): agregar saldo');
  }

  Future<void> _deductBalanceManual() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descontar Saldo'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Monto (positivo)', hintText: '50.00'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Descontar')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final amount = double.tryParse(result);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monto inválido')));
      return;
    }
    await _adjustBalance(-amount, 'Ajuste manual (admin): descontar saldo');
  }

  Future<void> _adjustBalance(double amount, String description) async {
    if (_account == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin cuenta financiera')));
      return;
    }
    try {
      // Insert transaction
      await SupabaseConfig.client.from('account_transactions').insert({
        'account_id': _account!.id,
        'type': amount > 0 ? 'DELIVERY_EARNING' : 'SETTLEMENT_PAYMENT',
        'amount': amount,
        'description': description,
        'created_at': DateTime.now().toIso8601String(),
      });
      // Update balance
      await SupabaseConfig.client
          .from('accounts')
          .update({'balance': _account!.balance + amount, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', _account!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saldo ajustado: ${_formatCurrency(amount)}')));
      _loadAll();
    } catch (e) {
      debugPrint('❌ Error adjusting balance: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _emptyState(String msg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: TextStyle(color: Colors.grey.shade700))),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)} ${_two(local.hour)}:${_two(local.minute)}';
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatCurrency(double amount) {
    final abs = amount.abs();
    final sign = amount < 0 ? '-' : '';
    final parts = abs.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '$sign$intPart.${parts[1]} mxn';
  }
}

class _StatCell {
  final IconData icon;
  final String value;
  final String title;
  _StatCell(this.icon, this.value, this.title);
}

class _DocCell {
  final String label;
  final String? url;
  final IconData icon;
  _DocCell(this.label, this.url, this.icon);
}
