import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/doa_models.dart';
import '../../supabase/supabase_config.dart';
import 'base_service.dart';

/// Servicio para manejo de cuentas financieras, transacciones y liquidaciones
/// Implementa el sistema de contabilidad interna (ledger) de la plataforma
class FinancialService extends BaseService {
  
  @override
  String get serviceName => 'FINANCIAL';
  
  @override
  String get requiredRole => 'any'; // Disponible para restaurantes y repartidores
  
  // Getter para acceder a Supabase client
  SupabaseClient get supabase => SupabaseConfig.client;
  
  @override
  void onActivate() {
    print('💰 [FINANCIAL] Servicio financiero activado para: ${currentSession?.email}');
    // El servicio financiero no necesita carga automática inicial
  }
  
  @override
  void onDeactivate() {
    print('🛑 [FINANCIAL] Servicio financiero desactivado');
  }
  
  /// Helper para manejar errores
  void handleError(String message, dynamic error) {
    print('❌ [FINANCIAL] $message: $error');
  }
  static const String _accountsTable = 'accounts';
  static const String _transactionsTable = 'account_transactions';
  static const String _settlementsTable = 'settlements';

  FinancialService() : super();

  // PLATFORM HELPERS (RPCs)

  /// Obtiene el account_id de la cuenta de plataforma (evita RLS desde cliente)
  Future<String?> getPlatformAccountId() async {
    try {
      print('🔎 [FINANCIAL] getPlatformAccountId()');
      final result = await supabase.rpc('rpc_get_platform_account_id');
      if (result == null) return null;
      if (result is String) return result;
      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        final dynamic v = map['id'] ?? map['account_id'] ?? map['accountId'];
        return v?.toString();
      }
      return result.toString();
    } on PostgrestException catch (e) {
      handleError('Error RPC get_platform_account_id', 'code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
      return null;
    } catch (e) {
      handleError('Error inesperado en getPlatformAccountId', e);
      return null;
    }
  }

  /// Inicia una liquidación del restaurante hacia la plataforma
  /// Devuelve { settlementId, code } para mostrar al restaurante
  Future<Map<String, String>?> initiateRestaurantSettlementToPlatform({
    required double amount,
    String? notes,
  }) async {
    try {
      final acc = await getUserAccount();
      if (acc == null || acc.accountType != AccountType.restaurant) {
        throw Exception('Solo los restaurantes pueden iniciar esta liquidación');
      }
      if (amount <= 0) {
        throw Exception('El monto debe ser mayor a cero');
      }

      print('📨 [FINANCIAL] initiate_restaurant_settlement -> amount=$amount');
      print('🧪 [FINANCIAL] RPC params types -> p_amount:${amount.runtimeType}, p_notes:${notes?.runtimeType}');
      final result = await supabase.rpc('rpc_initiate_restaurant_settlement', params: {
        'p_amount': amount,
        'p_notes': (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
      });
      print('🧾 [FINANCIAL] RPC raw result -> $result');

      if (result == null) {
        throw Exception('La RPC no devolvió datos');
      }

      final map = Map<String, dynamic>.from(result);
      final settlementId = (map['settlement_id'] ?? map['id'] ?? '').toString();
      String codeFromRpc = (map['plain_code'] ?? map['code'] ?? '').toString();

      // Leer SIEMPRE el código directamente de la fila en DB para evitar desajustes
      String codeFromDb = '';
      if (settlementId.isNotEmpty) {
        try {
          final row = await supabase
              .from(_settlementsTable)
              .select('confirmation_code, code_hash')
              .eq('id', settlementId)
              .maybeSingle();
          if (row != null) {
            codeFromDb = (row['confirmation_code'] ?? '').toString();
            final hasHash = (row['code_hash']?.toString().isNotEmpty ?? false);
            print('🧾 [FINANCIAL] DB row for settlement=$settlementId -> confirmation_code=$codeFromDb, has_hash=$hasHash');
          } else {
            print('⚠️ [FINANCIAL] No se pudo leer la fila recien creada (settlement=$settlementId)');
          }
        } catch (e) {
          print('⚠️ [FINANCIAL] Error leyendo confirmation_code desde DB: $e');
        }
      }

      // Diagnóstico y decisión final del código a devolver
      String finalCode = codeFromDb.isNotEmpty ? codeFromDb : codeFromRpc;
      if (settlementId.isEmpty || finalCode.isEmpty) {
        print('⚠️ [FINANCIAL] Datos incompletos tras RPC: id=$settlementId, rpcCode=$codeFromRpc, dbCode=$codeFromDb');
      } else {
        if (codeFromDb.isNotEmpty && codeFromRpc.isNotEmpty && codeFromDb != codeFromRpc) {
          print('⚠️ [FINANCIAL] Mismatch RPC vs DB code -> rpc=$codeFromRpc db=$codeFromDb | Usando DB');
        }
        print('✅ [FINANCIAL] initiate_restaurant_settlement OK -> settlement=$settlementId code=$finalCode');
      }

      // Forzar refresco de balance local por si RPC ya afectó algo (normalmente no hasta CONFIRM)
      await _refreshAccountBalanceRobust(acc.id);

      return {
        'settlementId': settlementId,
        'code': finalCode,
      };
    } on PostgrestException catch (e) {
      handleError('Error al iniciar liquidación (PostgREST)', 'code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
      // Diagnóstico táctico: si falla digest es muy probable que la función esté en el schema "extensions"
      if ((e.code == '42883') && ((e.message ?? '').toLowerCase().contains('digest'))) {
        print('🧭 [FINANCIAL] Hint: En Supabase, pgcrypto suele instalarse en el esquema "extensions".');
        print('🧭 [FINANCIAL] Asegura que las RPC usen search_path = public, extensions o llamen extensions.digest(...) y extensions.gen_random_uuid(...)');
      }
      rethrow;
    } catch (e) {
      handleError('Error al iniciar liquidación', e);
      return null;
    }
  }

  /// Confirma una liquidación por parte de admin/plataforma (código de 6 dígitos)
  Future<bool> confirmRestaurantSettlementByAdmin({
    required String settlementId,
    required String code,
  }) async {
    try {
      print('📨 [FINANCIAL] confirm_restaurant_settlement (admin) -> settlement=$settlementId');
      final result = await supabase.rpc('rpc_confirm_settlement', params: {
        'p_settlement_id': settlementId,
        'p_code': code,
      });

      // La RPC debe devolver el registro actualizado o true
      // Intentar extraer payer/receiver para refresco de balances
      String? payerId;
      String? receiverId;
      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        payerId = map['payer_account_id']?.toString();
        receiverId = map['receiver_account_id']?.toString();
      }

      // Refrescar balances si tenemos ids
      if (payerId != null && payerId.isNotEmpty) await _refreshAccountBalanceRobust(payerId);
      if (receiverId != null && receiverId.isNotEmpty) await _refreshAccountBalanceRobust(receiverId);

      print('✅ [FINANCIAL] confirm_restaurant_settlement OK');
      return true;
    } on PostgrestException catch (e) {
      handleError('Error confirmando liquidación (PostgREST)', 'code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
      return false;
    } catch (e) {
      handleError('Error confirmando liquidación', e);
      return false;
    }
  }

  // ACCOUNT MANAGEMENT

  /// Obtiene la cuenta financiera del usuario actual
  Future<DoaAccount?> getUserAccount() async {
    try {
      final response = await supabase
          .from(_accountsTable)
          .select()
          .eq('user_id', supabase.auth.currentUser!.id)
          .maybeSingle();

      if (response == null) return null;
      
      return DoaAccount.fromJson(response);
    } catch (e) {
      handleError('Error al obtener cuenta del usuario', e);
      return null;
    }
  }

  /// Obtiene una cuenta por su ID
  Future<DoaAccount?> getAccountById(String accountId) async {
    try {
      final response = await supabase
          .from(_accountsTable)
          .select()
          .eq('id', accountId)
          .maybeSingle();

      if (response == null) return null;
      
      return DoaAccount.fromJson(response);
    } catch (e) {
      handleError('Error al obtener cuenta', e);
      return null;
    }
  }

  /// Obtiene todas las cuentas (solo admin)
  Future<List<DoaAccount>> getAllAccounts() async {
    try {
      final response = await supabase
          .from(_accountsTable)
          .select()
          .order('created_at', ascending: false);

      return response.map((json) => DoaAccount.fromJson(json)).toList();
    } catch (e) {
      handleError('Error al obtener todas las cuentas', e);
      return [];
    }
  }

  /// Crea una cuenta para un usuario (automática al aprobar)
  Future<DoaAccount?> createAccount({
    required String userId,
    required AccountType accountType,
  }) async {
    try {
      final response = await supabase
          .from(_accountsTable)
          .insert({
            'user_id': userId,
            'account_type': accountType.toString(),
            'balance': 0.00,
          })
          .select()
          .single();

      return DoaAccount.fromJson(response);
    } catch (e) {
      handleError('Error al crear cuenta', e);
      return null;
    }
  }

  // TRANSACTION MANAGEMENT

  /// Obtiene las transacciones de la cuenta del usuario actual
  Future<List<DoaAccountTransaction>> getUserTransactions({
    int? limit,
    int? offset,
  }) async {
    try {
      final account = await getUserAccount();
      if (account == null) return [];

      var query = supabase
          .from(_transactionsTable)
          .select()
          .eq('account_id', account.id)
          .order('created_at', ascending: false);

      if (limit != null) query = query.limit(limit);
      if (offset != null) query = query.range(offset, offset + (limit ?? 50) - 1);

      final response = await query;

      return response.map((json) => DoaAccountTransaction.fromJson(json)).toList();
    } catch (e) {
      handleError('Error al obtener transacciones del usuario', e);
      return [];
    }
  }

  /// Obtiene todas las transacciones de una cuenta específica
  Future<List<DoaAccountTransaction>> getAccountTransactions(String accountId, {
    int? limit,
    int? offset,
  }) async {
    try {
      var query = supabase
          .from(_transactionsTable)
          .select()
          .eq('account_id', accountId)
          .order('created_at', ascending: false);

      if (limit != null) query = query.limit(limit);
      if (offset != null) query = query.range(offset, offset + (limit ?? 50) - 1);

      final response = await query;

      return response.map((json) => DoaAccountTransaction.fromJson(json)).toList();
    } catch (e) {
      handleError('Error al obtener transacciones de la cuenta', e);
      return [];
    }
  }

  /// Obtiene transacciones relacionadas con una orden específica
  Future<List<DoaAccountTransaction>> getOrderTransactions(String orderId) async {
    try {
      final response = await supabase
          .from(_transactionsTable)
          .select()
          .eq('order_id', orderId)
          .order('created_at', ascending: false);

      return response.map((json) => DoaAccountTransaction.fromJson(json)).toList();
    } catch (e) {
      handleError('Error al obtener transacciones de la orden', e);
      return [];
    }
  }

  /// Crea una transacción financiera
  Future<DoaAccountTransaction?> createTransaction({
    required String accountId,
    required TransactionType type,
    required double amount,
    String? orderId,
    String? settlementId,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await supabase
          .from(_transactionsTable)
          .insert({
            'account_id': accountId,
            'type': type.toString(),
            'amount': amount,
            'order_id': orderId,
            'settlement_id': settlementId,
            'description': description,
            'metadata': metadata,
          })
          .select()
          .single();

      // Actualizar balance de la cuenta
      await _updateAccountBalance(accountId);

      return DoaAccountTransaction.fromJson(response);
    } catch (e) {
      handleError('Error al crear transacción', e);
      return null;
    }
  }

  // SETTLEMENT MANAGEMENT

  /// Obtiene las liquidaciones del usuario actual
  Future<List<DoaSettlement>> getUserSettlements() async {
    try {
      final account = await getUserAccount();
      if (account == null) return [];

      final response = await supabase
          .from(_settlementsTable)
          .select('''
            *,
            payer:payer_account_id(user_id, users(*)),
            receiver:receiver_account_id(user_id, users(*))
          ''')
          .or('payer_account_id.eq.${account.id},receiver_account_id.eq.${account.id}')
          .order('initiated_at', ascending: false);

      return response.map((json) {
        // Flatten nested user data
        final settlement = Map<String, dynamic>.from(json);
        if (json['payer'] != null && json['payer']['users'] != null) {
          settlement['payer'] = json['payer']['users'];
        }
        if (json['receiver'] != null && json['receiver']['users'] != null) {
          settlement['receiver'] = json['receiver']['users'];
        }
        return DoaSettlement.fromJson(settlement);
      }).toList();
    } catch (e) {
      handleError('Error al obtener liquidaciones del usuario', e);
      return [];
    }
  }

  /// Obtiene liquidaciones pendientes para el restaurante actual
  Future<List<DoaSettlement>> getPendingSettlementsForRestaurant() async {
    try {
      final account = await getUserAccount();
      if (account == null || account.accountType != AccountType.restaurant) {
        return [];
      }

      final response = await supabase
          .from(_settlementsTable)
          .select('''
            *,
            payer:payer_account_id(user_id, users(*)),
            receiver:receiver_account_id(user_id, users(*))
          ''')
          .eq('receiver_account_id', account.id)
          .eq('status', 'pending')
          .order('initiated_at', ascending: false);

      return response.map((json) {
        final settlement = Map<String, dynamic>.from(json);
        if (json['payer'] != null && json['payer']['users'] != null) {
          settlement['payer'] = json['payer']['users'];
        }
        if (json['receiver'] != null && json['receiver']['users'] != null) {
          settlement['receiver'] = json['receiver']['users'];
        }
        return DoaSettlement.fromJson(settlement);
      }).toList();
    } catch (e) {
      handleError('Error al obtener liquidaciones pendientes', e);
      return [];
    }
  }

  /// Obtiene las cuentas de restaurantes disponibles para liquidación
  /// Más tolerante a variaciones del schema (account_type en mayúsculas, etc.)
  /// Si RLS bloquea leer accounts de otros usuarios, retorna cuentas "virtuales"
  /// derivadas de restaurants (id = 'user:<user_id>') para que el frontend
  /// pueda mostrar el dropdown y la RPC resuelva el account_id por dentro.
  Future<List<DoaAccount>> getAvailableRestaurantAccounts() async {
    try {
      final currentUser = supabase.auth.currentUser;
      print('🔎 [FINANCIAL] getAvailableRestaurantAccounts() as ${currentUser?.id} (${currentUser?.email})');

      // 1) Traer restaurantes visibles (aprobados o todos si no hay campo)
      List<dynamic> restaurants = const [];
      try {
        restaurants = await SupabaseConfig.client
            .from('restaurants')
            .select('id, name, user_id, status')
            .order('name');
        print('📦 [FINANCIAL] restaurants rows: ${restaurants.length}');
        if (restaurants.isNotEmpty) {
          final sample = restaurants.take(3).toList();
          print('📋 [FINANCIAL] sample restaurants: ${sample.map((r) => {'id': r['id'], 'name': r['name'], 'user_id': r['user_id'], 'status': r['status']}).toList()}');
        }
      } on PostgrestException catch (e) {
        print('❌ [FINANCIAL] RLS/SQL error fetching restaurants: code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
        return [];
      } catch (e) {
        print('❌ [FINANCIAL] Unknown error fetching restaurants: $e');
        return [];
      }

      if (restaurants.isEmpty) {
        print('ℹ️ [FINANCIAL] No se encontraron restaurantes');
        return [];
      }

      // 2) Extraer user_ids válidos
      final userIds = (restaurants
              .map((r) => r['user_id']?.toString())
              .where((id) => id != null && id.isNotEmpty)
              .toSet())
          .toList();
      print('🧾 [FINANCIAL] extracted userIds: count=${userIds.length} sample=${userIds.take(5).toList()}');

      if (userIds.isEmpty) {
        print('ℹ️ [FINANCIAL] Restaurantes sin user_id válidos');
        return [];
      }

      // 3) Intento principal: filtrar por account_type = restaurant (case-insensitive)
      List<dynamic> accountsResp = const [];
      try {
        accountsResp = await supabase
            .from(_accountsTable)
            .select()
            // 'restaur%' cubre 'restaurant' y 'restaurante' (tolerante a idiomas)
            .ilike('account_type', 'restaur%')
            .inFilter('user_id', userIds);
        print('📦 [FINANCIAL] accounts (ilike restaur%): ${accountsResp.length}');
      } on PostgrestException catch (e) {
        print('❌ [FINANCIAL] PostgREST error fetching accounts (ilike): code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
        // Fallback con lista explícita de valores comunes
        try {
          accountsResp = await supabase
              .from(_accountsTable)
              .select()
              .inFilter('account_type', ['restaurant', 'RESTAURANT', 'restaurante', 'RESTAURANTE'])
              .inFilter('user_id', userIds);
          print('📦 [FINANCIAL] accounts (fallback types): ${accountsResp.length}');
        } on PostgrestException catch (e2) {
          print('❌ [FINANCIAL] PostgREST error on fallback types: code=${e2.code}, message=${e2.message}, details=${e2.details}, hint=${e2.hint}');
        }
      } catch (e) {
        print('❌ [FINANCIAL] Unknown error fetching accounts (ilike/fallback): $e');
      }

      // 4) Si sigue vacío, último fallback: quitar filtro por account_type
      if (accountsResp.isEmpty) {
        print('⚠️ [FINANCIAL] No hubo cuentas con tipo "restaurant"; intentando por user_id solamente');
        try {
          accountsResp = await supabase
              .from(_accountsTable)
              .select()
              .inFilter('user_id', userIds);
          print('📦 [FINANCIAL] accounts (by user_id only): ${accountsResp.length}');
        } on PostgrestException catch (e) {
          print('❌ [FINANCIAL] PostgREST error accounts by user_id: code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
        } catch (e) {
          print('❌ [FINANCIAL] Unknown error accounts by user_id: $e');
        }
      }

      var accounts = accountsResp
          .map<DoaAccount>((json) => DoaAccount.fromJson(Map<String, dynamic>.from(json)))
          .where((a) => a.accountType == AccountType.restaurant)
          .toList();

      // 5) Si aún no tenemos cuentas (probable RLS), construir VIRTUALES desde restaurants
      if (accounts.isEmpty) {
        print('🛡️ [FINANCIAL] RLS probablemente bloquea lectura de accounts ajenas. Construyendo lista VIRTUAL desde restaurants...');
        accounts = restaurants.map<DoaAccount>((r) {
          final uid = r['user_id']?.toString() ?? '';
          final virtualId = 'user:$uid';
          return DoaAccount(
            id: virtualId, // Marcador: id basado en user
            userId: uid,
            accountType: AccountType.restaurant,
            balance: 0.0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        }).toList();
        print('📦 [FINANCIAL] cuentas VIRTUALES construidas: ${accounts.length}. Ejemplo: ${accounts.take(3).map((a) => {'id': a.id, 'user_id': a.userId}).toList()}');
      }

      print('✅ [FINANCIAL] Cuentas de restaurantes encontradas: ${accounts.length}');
      if (accounts.isNotEmpty) {
        print('📋 [FINANCIAL] sample accounts: ${accounts.take(3).map((a) => {'id': a.id, 'user_id': a.userId, 'type': a.accountType.toString(), 'balance': a.balance}).toList()}');
      }
      return accounts;
    } catch (e) {
      handleError('Error al obtener cuentas de restaurantes', e);
      return [];
    }
  }

  /// Lista SOLO los restaurantes a los cuales el repartidor actual debe dinero (cuenta por pagar)
  /// Implementación vía RPC server-side; si no existe, hace fallback a getAvailableRestaurantAccounts()
  Future<List<DoaAccount>> getRestaurantsWithDebtForCurrentDelivery() async {
    try {
      final myAcc = await getUserAccount();
      if (myAcc == null || myAcc.accountType != AccountType.delivery_agent) {
        return [];
      }
      try {
        final rows = await supabase.rpc('rpc_list_restaurants_with_debt_for_delivery', params: {
          'p_delivery_account_id': myAcc.id,
        });
        if (rows is List && rows.isNotEmpty) {
          final accounts = <DoaAccount>[];
          for (final r in rows) {
            final m = Map<String, dynamic>.from(r);
            // Prefer account_id from RPC; fallback to marker by user
            final accId = (m['account_id']?.toString().isNotEmpty ?? false)
                ? m['account_id'].toString()
                : 'user:${m['restaurant_user_id']?.toString() ?? ''}';
            final userId = m['restaurant_user_id']?.toString() ?? m['user_id']?.toString() ?? '';
            accounts.add(DoaAccount(
              id: accId,
              userId: userId,
              accountType: AccountType.restaurant,
              balance: 0.0,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ));
          }
          print('✅ [FINANCIAL] RPC restaurants with debt -> ${accounts.length}');
          return accounts;
        }
      } on PostgrestException catch (e) {
        print('🧪 [FINANCIAL] RPC rpc_list_restaurants_with_debt_for_delivery no disponible o error (${e.code}). Fallback a listado general.');
      } catch (e) {
        print('🧪 [FINANCIAL] Error genérico en RPC de deudas: $e. Fallback a listado general.');
      }
      // Fallback
      return await getAvailableRestaurantAccounts();
    } catch (e) {
      handleError('Error al listar restaurantes con deuda', e);
      return [];
    }
  }

  /// ADMIN: Crear una liquidación manual entre dos cuentas (opción de completar de inmediato)
  Future<DoaSettlement?> adminCreateSettlement({
    required String payerAccountId,
    required String receiverAccountId,
    required double amount,
    String? notes,
    bool autoComplete = true,
  }) async {
    try {
      final res = await supabase.rpc('rpc_admin_create_settlement', params: {
        'p_payer_account_id': payerAccountId,
        'p_receiver_account_id': receiverAccountId,
        'p_amount': amount,
        'p_notes': notes,
        'p_auto_complete': autoComplete,
      });
      if (res == null) return null;
      final map = Map<String, dynamic>.from(res as Map);
      print('✅ [FINANCIAL] admin_create_settlement -> id=${map['id']} status=${map['status']}');
      return DoaSettlement.fromJson(map);
    } on PostgrestException catch (e) {
      handleError('Error adminCreateSettlement (PostgREST)', 'code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
      rethrow;
    } catch (e) {
      handleError('Error adminCreateSettlement', e);
      return null;
    }
  }

  /// ADMIN: Listar cuentas existentes; intenta lectura directa y hace fallback a RPC si RLS lo impide
  Future<List<DoaAccount>> adminListAllAccounts({AccountType? type}) async {
    try {
      List<dynamic> rows = const [];
      try {
        var q = supabase.from(_accountsTable).select();
        if (type != null) {
          q = q.eq('account_type', type.toString());
        }
        rows = await q.order('created_at', ascending: false);
      } on PostgrestException catch (e) {
        print('🛡️ [FINANCIAL] RLS al leer accounts directamente (${e.code}). Intentando RPC.');
        try {
          final params = <String, dynamic>{};
          if (type != null) params['p_account_type'] = type.toString();
          rows = await supabase.rpc('rpc_admin_list_accounts', params: params) as List<dynamic>;
        } catch (e2) {
          print('❌ [FINANCIAL] RPC rpc_admin_list_accounts falló: $e2');
          rethrow;
        }
      }
      return rows.map((j) => DoaAccount.fromJson(Map<String, dynamic>.from(j))).toList();
    } catch (e) {
      handleError('Error adminListAllAccounts', e);
      return [];
    }
  }

  /// Obtiene el adeudo mínimo requerido (balance negativo) del usuario actual
  Future<double> getRequiredMinPaymentForCurrentUser() async {
    try {
      final account = await getUserAccount();
      if (account == null) return 0.0;

      final result = await supabase.rpc('fn_required_min_payment', params: {
        'p_account_id': account.id,
      });

      if (result == null) return 0.0;
      if (result is num) return result.toDouble();
      // PostgREST puede retornar string/numeric
      return double.tryParse(result.toString()) ?? 0.0;
    } catch (e) {
      handleError('Error al obtener adeudo mínimo requerido', e);
      return 0.0;
    }
  }

  /// Resuelve account_id del restaurante a partir de user_id del restaurante
  /// Devuelve null si no se pudo resolver (por RLS o inexistente)
  Future<String?> _resolveRestaurantAccountIdByUser(String restaurantUserId) async {
    try {
      print('🔎 [FINANCIAL] Resolviendo account_id para restaurant user_id=$restaurantUserId');

      // Intento 1: tabla accounts con filtro por tipo (restaurant/restaurante)
      try {
        final row = await supabase
            .from(_accountsTable)
            .select('id, account_type')
            .eq('user_id', restaurantUserId)
            .ilike('account_type', 'restaur%')
            .maybeSingle();
        if (row != null && row['id'] != null) {
          print('✅ [FINANCIAL] account_id encontrado en accounts: ${row['id']} (type=${row['account_type']})');
          return row['id'].toString();
        }
      } on PostgrestException catch (e) {
        print('🛡️ [FINANCIAL] RLS al leer accounts (ilike) para user_id=$restaurantUserId -> code=${e.code}, message=${e.message}, hint=${e.hint}');
      }

      // Intento 2: tabla accounts sin filtro de tipo (primer registro visible)
      try {
        final row2 = await supabase
            .from(_accountsTable)
            .select('id, account_type')
            .eq('user_id', restaurantUserId)
            .order('created_at', ascending: true)
            .limit(1)
            .maybeSingle();
        if (row2 != null && row2['id'] != null) {
          print('✅ [FINANCIAL] account_id encontrado en accounts (sin tipo): ${row2['id']} (type=${row2['account_type']})');
          return row2['id'].toString();
        } else {
          print('ℹ️ [FINANCIAL] No hay cuentas visibles para el user_id=$restaurantUserId');
        }
      } on PostgrestException catch (e) {
        print('🛡️ [FINANCIAL] RLS al leer accounts (sin tipo) para user_id=$restaurantUserId -> code=${e.code}, message=${e.message}, hint=${e.hint}');
      } catch (e) {
        print('❌ [FINANCIAL] Error no esperado al resolver account_id via accounts(sin tipo): $e');
      }

      return null;
    } catch (e) {
      print('❌ [FINANCIAL] Error en _resolveRestaurantAccountIdByUser: $e');
      return null;
    }
  }

  /// Intento alternativo: resolver account_id vía RPC de seguridad definida (server-side)
  /// Requiere que exista public.rpc_get_restaurant_account_id(p_user_id uuid) RETURNS uuid
  Future<String?> _resolveRestaurantAccountIdViaRPC(String restaurantUserId) async {
    try {
      print('🧰 [FINANCIAL] Intentando rpc_get_restaurant_account_id para user_id=$restaurantUserId');
      final result = await supabase.rpc('rpc_get_restaurant_account_id', params: {
        'p_user_id': restaurantUserId,
      });

      if (result == null) {
        print('ℹ️ [FINANCIAL] RPC rpc_get_restaurant_account_id devolvió null');
        return null;
      }

      // La función puede devolver un uuid escalar o un objeto con {id: ...}
      String? idStr;
      if (result is String) {
        idStr = result;
      } else if (result is Map) {
        final map = Map<String, dynamic>.from(result as Map);
        final dynamic v = map['id'] ?? map['account_id'] ?? map['accountId'];
        idStr = v?.toString();
      }

      if (idStr != null && idStr.isNotEmpty) {
        print('✅ [FINANCIAL] RPC resolvió account_id=$idStr');
        return idStr;
      }

      print('ℹ️ [FINANCIAL] RPC no retornó un id usable: $result');
      return null;
    } on PostgrestException catch (e) {
      print('❌ [FINANCIAL] Error PostgREST al invocar rpc_get_restaurant_account_id: code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
      return null;
    } catch (e) {
      print('❌ [FINANCIAL] Error inesperado en _resolveRestaurantAccountIdViaRPC: $e');
      return null;
    }
  }

  /// Crear una nueva liquidación (repartidor -> restaurante) usando la RPC oficial
  /// Requiere SIEMPRE p_receiver_account_id (uuid) conforme a tu schema actual
  /// Si el dropdown entregó un marcador 'user:<user_id>', resolvemos el account_id primero.
  Future<DoaSettlement?> createSettlement({
    required String receiverAccountId,
    required double amount,
    String? notes,
  }) async {
    try {
      final payerAccount = await getUserAccount();
      if (payerAccount == null || payerAccount.accountType != AccountType.delivery_agent) {
        throw Exception('Solo los repartidores pueden iniciar liquidaciones');
      }
      if (amount <= 0) {
        throw Exception('El monto debe ser mayor a cero');
      }

      // ¿Llegó como marcador 'user:<uuid>'? Resolver a account_id real.
      String finalReceiverAccountId = receiverAccountId;
      if (receiverAccountId.startsWith('user:')) {
        final receiverUserId = receiverAccountId.substring(5);
        print('🧾 [FINANCIAL] createSettlement -> USER_ID marker detected | user_id=$receiverUserId | amount=$amount');
        String? resolved = await _resolveRestaurantAccountIdByUser(receiverUserId);
        if (resolved == null) {
          // Intento alternativo vía RPC de server (security definer)
          resolved = await _resolveRestaurantAccountIdViaRPC(receiverUserId);
        }
        if (resolved == null) {
          throw Exception('No se pudo resolver la cuenta del restaurante (account_id). Contacta a un administrador para habilitar el helper RPC rpc_get_restaurant_account_id o lectura mínima de accounts.');
        }
        print('🧾 [FINANCIAL] Resolved user_id -> account_id: $receiverUserId -> $resolved');
        finalReceiverAccountId = resolved;
      } else {
        print('🧾 [FINANCIAL] createSettlement -> using ACCOUNT_ID | value=$receiverAccountId | amount=$amount');
      }

      final params = <String, dynamic>{
        'p_receiver_account_id': finalReceiverAccountId,
        'p_amount': amount,
        'p_notes': notes,
      };
      print('📨 [FINANCIAL] calling rpc_create_settlement with params={p_receiver_account_id: $finalReceiverAccountId, p_amount: $amount, p_notes: ${notes != null ? '<text>' : null}}');

      final response = await supabase.rpc('rpc_create_settlement', params: params);
      if (response == null) {
        throw Exception('La RPC no devolvió datos');
      }
      final map = Map<String, dynamic>.from(response);
      print('✅ [FINANCIAL] rpc_create_settlement OK -> id=${map['id']} status=${map['status']} amount=${map['amount']}');
      return DoaSettlement.fromJson(map);
    } on PostgrestException catch (e) {
      handleError('Error al crear liquidación (PostgREST)', 'code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
      rethrow;
    } catch (e) {
      handleError('Error al crear liquidación', e);
      return null;
    }
  }

  /// Confirmar una liquidación usando RPC atómica en el servidor
  /// La RPC valida el código y completa la liquidación dentro de una sola transacción
  Future<bool> confirmSettlement({
    required String settlementId,
    required String confirmationCode,
  }) async {
    try {
      final input = confirmationCode.trim();
      print('📨 [FINANCIAL] confirmSettlement (RPC) -> id=$settlementId code_len=${input.length}');

      final result = await supabase.rpc('rpc_confirm_settlement', params: {
        'p_settlement_id': settlementId,
        'p_code': input,
      });

      String? payerId;
      String? receiverId;
      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        payerId = map['payer_account_id']?.toString();
        receiverId = map['receiver_account_id']?.toString();
        print('✅ [FINANCIAL] RPC confirm_settlement OK -> id=${map['id']} status=${map['status']}');
      } else {
        print('✅ [FINANCIAL] RPC confirm_settlement OK (no map) -> $result');
      }

      if (payerId != null && payerId.isNotEmpty) await _refreshAccountBalanceRobust(payerId);
      if (receiverId != null && receiverId.isNotEmpty) await _refreshAccountBalanceRobust(receiverId);
      return true;
    } on PostgrestException catch (e) {
      handleError('Error al confirmar liquidación (PostgREST)', 'code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
      return false;
    } catch (e) {
      handleError('Error al confirmar liquidación', e);
      return false;
    }
  }

  /// Intenta recomputar el balance de una cuenta de forma robusta (RPC primero para evitar RLS)
  Future<void> _refreshAccountBalanceRobust(String accountId) async {
    if (accountId.isEmpty) return;

    // 1) Intentar RPCs con nombres comunes (security definer) si existen
    final rpcCandidates = <String>[
      'rpc_recompute_account_balance',
      'rpc_refresh_account_balance',
      'fn_recompute_account_balance',
      'recompute_account_balance',
      'refresh_account_balance',
    ];

    for (final rpc in rpcCandidates) {
      try {
        await supabase.rpc(rpc, params: {'p_account_id': accountId});
        // Si no lanza excepción, asumimos éxito
        return;
      } catch (_) {
        // Continuar con el siguiente candidato
      }
    }

    // 2) Fallback: calcular por el cliente (puede fallar por RLS si no se pueden leer las transacciones)
    try {
      await _updateAccountBalance(accountId);
      return;
    } catch (e) {
      handleError('No se pudo recomputar balance por RLS; considera agregar RPC security definer', e);
    }
  }

  /// Cancelar una liquidación
  Future<bool> cancelSettlement(String settlementId) async {
    try {
      await supabase
          .from(_settlementsTable)
          .update({'status': 'cancelled'})
          .eq('id', settlementId)
          .eq('status', 'pending'); // Solo se pueden cancelar las pendientes

      return true;
    } catch (e) {
      handleError('Error al cancelar liquidación', e);
      return false;
    }
  }

  // HELPER METHODS

  /// Actualiza el balance de una cuenta basado en sus transacciones
  Future<void> _updateAccountBalance(String accountId) async {
    try {
      // Calcular el balance sumando todas las transacciones
      final transactions = await getAccountTransactions(accountId);
      final newBalance = transactions.fold<double>(0.0, (sum, transaction) => sum + transaction.amount);

      // Actualizar el balance en la cuenta
      await supabase
          .from(_accountsTable)
          .update({
            'balance': newBalance,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', accountId);
    } catch (e) {
      handleError('Error al actualizar balance de cuenta', e);
    }
  }

  /// Obtiene estadísticas financieras del usuario actual
  Future<Map<String, dynamic>> getUserFinancialStats() async {
    try {
      final account = await getUserAccount();
      if (account == null) {
        return {
          'currentBalance': 0.0,
          'totalEarnings': 0.0,
          'totalCommissions': 0.0,
          'pendingSettlements': 0,
        };
      }

      final transactions = await getUserTransactions();
      
      double totalEarnings = 0.0;
      double totalCommissions = 0.0;
      
      for (final transaction in transactions) {
        if (transaction.type == TransactionType.ORDER_REVENUE || 
            transaction.type == TransactionType.DELIVERY_EARNING) {
          totalEarnings += transaction.amount;
        } else if (transaction.type == TransactionType.PLATFORM_COMMISSION) {
          totalCommissions += transaction.amount.abs();
        }
      }

      final settlements = await getUserSettlements();
      final pendingSettlements = settlements.where((s) => s.status == SettlementStatus.pending).length;

      return {
        'currentBalance': account.balance,
        'totalEarnings': totalEarnings,
        'totalCommissions': totalCommissions,
        'pendingSettlements': pendingSettlements,
      };
    } catch (e) {
      handleError('Error al obtener estadísticas financieras', e);
      return {
        'currentBalance': 0.0,
        'totalEarnings': 0.0,
        'totalCommissions': 0.0,
        'pendingSettlements': 0,
      };
    }
  }

  /// Genera un reporte financiero detallado para admin
  Future<Map<String, dynamic>> getFinancialReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = supabase
          .from(_transactionsTable)
          .select();

      if (startDate != null) {
        query = query.gte('created_at', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('created_at', endDate.toIso8601String());
      }

      final transactions = await query.order('created_at', ascending: false);
      
      double totalRevenue = 0.0;
      double totalCommissions = 0.0;
      double totalDeliveryEarnings = 0.0;
      int totalOrders = 0;
      
      final orderIds = <String>{};
      
      for (final transactionData in transactions) {
        final transaction = DoaAccountTransaction.fromJson(transactionData);
        
        switch (transaction.type) {
          case TransactionType.ORDER_REVENUE:
            totalRevenue += transaction.amount;
            if (transaction.orderId != null) {
              orderIds.add(transaction.orderId!);
            }
            break;
          case TransactionType.PLATFORM_COMMISSION:
            totalCommissions += transaction.amount.abs();
            break;
          case TransactionType.DELIVERY_EARNING:
            totalDeliveryEarnings += transaction.amount;
            break;
          default:
            break;
        }
      }
      
      totalOrders = orderIds.length;

      return {
        'totalRevenue': totalRevenue,
        'totalCommissions': totalCommissions,
        'totalDeliveryEarnings': totalDeliveryEarnings,
        'totalOrders': totalOrders,
        'averageOrderValue': totalOrders > 0 ? (totalRevenue + totalDeliveryEarnings) / totalOrders : 0.0,
      };
    } catch (e) {
      handleError('Error al generar reporte financiero', e);
      return {};
    }
  }
}