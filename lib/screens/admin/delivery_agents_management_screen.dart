import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/services/onboarding_notification_service.dart';
import 'package:doa_repartos/screens/admin/delivery_agent_detail_admin_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeliveryAgentsManagementScreen extends StatefulWidget {
  const DeliveryAgentsManagementScreen({super.key});

  @override
  State<DeliveryAgentsManagementScreen> createState() => _DeliveryAgentsManagementScreenState();
}

class _DeliveryAgentsManagementScreenState extends State<DeliveryAgentsManagementScreen> {
  List<DoaUser> _allDeliveryAgents = [];
  List<DoaUser> _filteredDeliveryAgents = [];
  bool _isLoading = true;
  String _statusFilter = 'all'; // all, pending, approved
  final Map<String, OnboardingStatus> _checklistCache = {};

  @override
  void initState() {
    super.initState();
    _loadDeliveryAgents();
  }

  Future<void> _loadDeliveryAgents() async {
    setState(() => _isLoading = true);
    
    try {
      print('🔄 [ADMIN] Loading delivery agents from Supabase (profiles+users)...');

      // Usar método centralizado que prioriza status de delivery_agent_profiles
      final flat = await DoaRepartosService.getDeliveryAgents();

      // Convertir los datos a DoaUser
      final agents = flat.map<DoaUser>((row) => DoaUser.fromJson(Map<String, dynamic>.from(row))).toList();

      print('✅ [ADMIN] Loaded ${agents.length} delivery agents (profiles+users)');
      for (var agent in agents) {
        print('📋 Agent: ${agent.name} - Email: ${agent.email} - Status: ${agent.status.displayName} - Active: ${agent.isActive}');
      }

      setState(() {
        _allDeliveryAgents = agents;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      print('❌ [ADMIN] Error loading delivery agents: $e');
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading delivery agents: $e')),
        );
      }
    }
  }
  Future<OnboardingStatus> _computeDeliveryChecklist(DoaUser agent) async {
    // Intentar usar caché reciente
    final cached = _checklistCache[agent.id];
    try {
      // Traer datos frescos del repartidor (vista unificada o merge users+profile)
      final merged = await DoaRepartosService.getDeliveryAgentByUserId(agent.id);
      final enriched = merged != null
          ? DoaUser.fromJson(Map<String, dynamic>.from(merged))
          : agent;
      final status = OnboardingNotificationService.calculateDeliveryOnboarding(enriched);
      _checklistCache[agent.id] = status;
      return status;
    } catch (e) {
      // En caso de error, usar lo que tengamos y marcar inconcluso
      debugPrint('❌ [ADMIN] Error computing delivery checklist: $e');
      if (cached != null) return cached;
      final fallback = OnboardingNotificationService.calculateDeliveryOnboarding(agent);
      _checklistCache[agent.id] = fallback;
      return fallback;
    }
  }

  void _openChecklistSheet(DoaUser agent, OnboardingStatus onboarding) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.fact_check, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Checklist de ${(agent.name?.isNotEmpty ?? false) ? agent.name : agent.email}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (onboarding.percentage / 100.0).clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: Colors.grey.withValues(alpha: 0.3),
                  color: onboarding.isComplete ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(height: 8),
              Text('Progreso de perfil: ${onboarding.percentage}%'),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: onboarding.tasks.length,
                  itemBuilder: (context, i) {
                    final t = onboarding.tasks[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            t.isCompleted ? Icons.check_circle : Icons.cancel,
                            color: t.isCompleted ? Colors.green : Colors.red,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(t.title)),
                          if (t.isOptional)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text('Opcional', style: TextStyle(fontSize: 11)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onboarding.isComplete
                          ? () => Navigator.pop(context)
                          : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Aprobar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.green.withValues(alpha: 0.3),
                        disabledForegroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Cerrar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  void _applyFilter() {
    if (_statusFilter == 'all') {
      _filteredDeliveryAgents = _allDeliveryAgents;
    } else if (_statusFilter == 'online') {
      // Los repartidores online
      _filteredDeliveryAgents = _allDeliveryAgents.where((agent) => agent.status == UserStatus.online).toList();
    } else if (_statusFilter == 'offline') {
      // Los repartidores offline
      _filteredDeliveryAgents = _allDeliveryAgents.where((agent) => agent.status == UserStatus.offline).toList();
    } else {
      // Filter by account_state (pending, approved)
      final accountState = DeliveryAccountState.values.firstWhere(
        (s) => s.name == _statusFilter,
        orElse: () => DeliveryAccountState.pending,
      );
      _filteredDeliveryAgents = _allDeliveryAgents.where((agent) => agent.accountState == accountState).toList();
    }
    print('🎯 [ADMIN] Filtered to ${_filteredDeliveryAgents.length} delivery agents (filter: $_statusFilter)');
  }

  // FUNCIÓN REMOVIDA: _updateDeliveryAgentStatus 
  // Ya que la columna 'is_active' no existe en la tabla 'users'
  // Usamos solo el campo 'status' para manejar todos los estados

  Future<void> _approveDeliveryAgent(String userId) async {
    print('================ [ADMIN ▶︎ APPROVAL FLOW] ================');
    print('👤 user_id=$userId  ➜  action=approve');
    try {
      // Call the RPC function to approve
      final result = await SupabaseConfig.client.rpc('admin_approve_delivery_agent', params: {
        'p_user_id': userId,
      });
      print('📬 RPC result: $result');

      final success = result['success'] == true;
      print('🏁 Approval flow success=$success');

      await _loadDeliveryAgents();

      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Repartidor aprobado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'No se pudo aprobar el repartidor'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, st) {
      print('❌ [ADMIN] Fatal error in approval flow: $e');
      print('❌ [ADMIN] Stack: $st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error aprobando repartidor: $e'), backgroundColor: Colors.red),
      );
    } finally {
      print('================ [ADMIN ◀︎ APPROVAL FLOW END] ================');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Agents'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          // Filter dropdown
          Container(
            margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: _statusFilter,
              dropdownColor: Colors.blue.shade800,
              style: const TextStyle(color: Colors.white),
              underline: Container(),
              icon: const Icon(Icons.filter_list, color: Colors.white),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todos', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 'pending', child: Text('Pendientes', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 'approved', child: Text('Aprobados', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 'online', child: Text('En línea', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 'offline', child: Text('Desconectados', style: TextStyle(color: Colors.white))),
              ],
              onChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    _statusFilter = value;
                    _applyFilter();
                  });
                }
              },
            ),
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _buildDeliveryAgentsList(),
    );
  }

  Widget _buildDeliveryAgentsList() {
    if (_filteredDeliveryAgents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delivery_dining, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _statusFilter == 'all' 
                  ? 'No delivery agents found'
                  : 'No $_statusFilter delivery agents',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Total agents in system: ${_allDeliveryAgents.length}',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDeliveryAgents,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredDeliveryAgents.length,
        itemBuilder: (context, index) {
          final agent = _filteredDeliveryAgents[index];
          return _buildDeliveryAgentCard(agent);
        },
      ),
    );
  }

  Widget _buildDeliveryAgentCard(DoaUser agent) {
    // account_state determina si está aprobado, status determina si está online
    final isApproved = agent.accountState == DeliveryAccountState.approved;
    final isOnline = agent.status == UserStatus.online;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Agent avatar
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.blue.shade100,
                  child: Text(
                    (agent.name?.isNotEmpty ?? false) ? agent.name![0].toUpperCase() : 'D',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Agent info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (agent.name?.isNotEmpty ?? false) ? agent.name! : 'Delivery Agent',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        agent.email,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      
                      // Status badges
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          // Account State Badge (pending/approved)
                          if (agent.accountState != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: agent.accountState!.color,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(agent.accountState!.icon, color: Colors.white, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    agent.accountState!.displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Online/Offline Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: agent.status.color,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(agent.status.icon, color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  agent.status.displayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Email verification badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: agent.emailConfirm 
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: agent.emailConfirm 
                                    ? Colors.green 
                                    : Colors.red,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  agent.emailConfirm 
                                      ? Icons.check_circle 
                                      : Icons.warning,
                                  color: agent.emailConfirm 
                                      ? Colors.green 
                                      : Colors.red,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  agent.emailConfirm 
                                      ? 'Email verificado' 
                                      : 'Email pendiente',
                                  style: TextStyle(
                                    color: agent.emailConfirm 
                                        ? Colors.green.shade700 
                                        : Colors.red.shade700,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Agent details
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.email, color: Colors.grey, size: 16),
                    const SizedBox(width: 4),
                    Flexible(child: Text(agent.email, overflow: TextOverflow.ellipsis)),
                  ],
                ),
                if (agent.phone?.isNotEmpty ?? false)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone, color: Colors.grey, size: 16),
                      const SizedBox(width: 4),
                      Text(agent.phone ?? ''),
                    ],
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person, color: Colors.grey, size: 16),
                    const SizedBox(width: 4),
                    Text(agent.role.toString()),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 16),

            // Action buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Quick actions
                TextButton.icon(
                  onPressed: () async {
                    final checklist = await _computeDeliveryChecklist(agent);
                    if (!mounted) return;
                    _openChecklistSheet(agent, checklist);
                  },
                  icon: const Icon(Icons.fact_check, color: Colors.blue),
                  label: const Text('Ver checklist'),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AdminDeliveryAgentDetailScreen(agent: agent),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new, color: Colors.blue),
                  label: const Text('Ver detalle'),
                ),
                // Approval actions - solo si está pendiente
                if (agent.accountState == DeliveryAccountState.pending) ...[
                  ElevatedButton.icon(
                    onPressed: () => _showApprovalDialog(agent),
                    icon: const Icon(Icons.check_circle, size: 16),
                    label: const Text('Aprobar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showApprovalDialog(DoaUser agent) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aprobar Repartidor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Repartidor: ${agent.name ?? 'Sin nombre'}'),
            Text('Email: ${agent.email}'),
            Text('Estado actual: ${agent.accountState?.displayName ?? "Desconocido"}'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Nuevo estado: Aprobado',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'El repartidor podrá conectarse y recibir órdenes.',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _approveDeliveryAgent(agent.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
  }
}