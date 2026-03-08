import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Excepción lanzada cuando falla una subida de archivo a Supabase Storage.
class StorageUploadException implements Exception {
  final String message;
  const StorageUploadException(this.message);
  @override
  String toString() => message;
}

/// Servicio para gestionar la carga de archivos a Supabase Storage
class StorageService {
  static const String _profileImagesBucket = 'profile-images';
  static const String _restaurantImagesBucket = 'restaurant-images';
  static const String _documentsBucket = 'documents';
  static const String _vehicleImagesBucket = 'vehicle-images';
  static const String _deliveryEvidenceFolder = 'delivery-evidence';

  /// Subir imagen de perfil de usuario
  static Future<String?> uploadProfileImage(
    String userId,
    PlatformFile file,
  ) async {
    return _uploadFile(
      bucket: _profileImagesBucket,
      path: '$userId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file: file,
    );
  }

  /// Subir documento de identidad
  static Future<String?> uploadIdDocument(
    String userId,
    PlatformFile file,
    String side, // 'front' or 'back'
  ) async {
    return _uploadFile(
      bucket: _documentsBucket,
      path: '$userId/id_$side\_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file: file,
    );
  }

  /// Subir imagen de vehículo
  static Future<String?> uploadVehicleImage(
    String userId,
    PlatformFile file,
    String type, // 'photo', 'registration', 'insurance'
  ) async {
    return _uploadFile(
      bucket: _vehicleImagesBucket,
      path: '$userId/$type\_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file: file,
    );
  }

  /// Subir documento de identidad (frente)
  static Future<String?> uploadIdDocumentFront(String userId, PlatformFile file) =>
      uploadIdDocument(userId, file, 'front');

  /// Subir documento de identidad (reverso)
  static Future<String?> uploadIdDocumentBack(String userId, PlatformFile file) =>
      uploadIdDocument(userId, file, 'back');

  /// Subir foto del vehículo
  static Future<String?> uploadVehiclePhoto(String userId, PlatformFile file) =>
      uploadVehicleImage(userId, file, 'photo');

  /// Subir tarjeta de circulación del vehículo
  static Future<String?> uploadVehicleRegistration(String userId, PlatformFile file) =>
      uploadVehicleImage(userId, file, 'registration');

  /// Subir seguro del vehículo
  static Future<String?> uploadVehicleInsurance(String userId, PlatformFile file) =>
      uploadVehicleImage(userId, file, 'insurance');

  /// Subir logo de restaurante
  static Future<String?> uploadRestaurantLogo(
    String userId,
    PlatformFile file,
  ) async {
    return _uploadFile(
      bucket: _restaurantImagesBucket,
      path: '$userId/logo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file: file,
    );
  }

  /// Subir imagen de portada de restaurante
  static Future<String?> uploadRestaurantCover(
    String userId,
    PlatformFile file,
  ) async {
    return _uploadFile(
      bucket: _restaurantImagesBucket,
      path: '$userId/cover_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file: file,
    );
  }

  /// Subir imagen de fachada de restaurante (nueva)
  static Future<String?> uploadRestaurantFacade(
    String userId,
    PlatformFile file,
  ) async {
    return _uploadFile(
      bucket: _restaurantImagesBucket,
      path: '$userId/facade_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file: file,
    );
  }

  /// Subir imagen de menú de restaurante
  static Future<String?> uploadRestaurantMenu(
    String userId,
    PlatformFile file,
  ) async {
    return _uploadFile(
      bucket: _restaurantImagesBucket,
      path: '$userId/menu_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file: file,
    );
  }

  /// Subir permiso de restaurante
  static Future<String?> uploadRestaurantPermit(
    String userId, // Cambiar a userId para cumplir con las políticas de storage
    PlatformFile file,
    String type, // 'business' or 'health'
  ) async {
    return _uploadFile(
      bucket: _documentsBucket,
      path: '$userId/$type\_permit_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file: file,
    );
  }

  /// Subir imagen de producto
  static Future<String?> uploadProductImage(
    String userId,
    PlatformFile file,
  ) async {
    return _uploadFile(
      bucket: _restaurantImagesBucket,
      path: '$userId/products/product_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file: file,
    );
  }

  /// Subir evidencia de no entrega (foto) al bucket de documentos
  /// Path: documents/delivery-evidence/<userId>/<orderId>_<ts>.jpg
  static Future<String?> uploadDeliveryEvidence({
    required String userId,
    required String orderId,
    required PlatformFile file,
  }) async {
    return _uploadFile(
      bucket: _documentsBucket,
      path: '$_deliveryEvidenceFolder/$userId/${orderId}_evidence_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file: file,
    );
  }

  /// Método genérico para subir archivo.
  /// Lanza [StorageUploadException] si el upload falla, para que los callers
  /// puedan mostrar el error específico al usuario.
  static Future<String> _uploadFile({
    required String bucket,
    required String path,
    required PlatformFile file,
  }) async {
    debugPrint('📤 [STORAGE] Iniciando subida a $bucket/$path');
    debugPrint('📊 [STORAGE] Archivo: ${file.name}, Tamaño: ${file.size} bytes');

    // Obtener los bytes del archivo — primero de memoria, luego del path (Android nativo)
    Uint8List? fileBytes = file.bytes;
    if (fileBytes == null && file.path != null && !kIsWeb) {
      debugPrint('📂 [STORAGE] bytes nulos, leyendo desde path: ${file.path}');
      try {
        fileBytes = await File(file.path!).readAsBytes();
      } catch (e) {
        debugPrint('❌ [STORAGE] No se pudo leer desde path: $e');
      }
    }
    if (fileBytes == null) {
      const msg = 'No hay bytes disponibles. Intenta seleccionar la imagen de nuevo.';
      debugPrint('❌ [STORAGE] $msg');
      throw StorageUploadException(msg);
    }

    String inferContentType(String name) {
      final lower = name.toLowerCase();
      if (lower.endsWith('.png')) return 'image/png';
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
      if (lower.endsWith('.webp')) return 'image/webp';
      if (lower.endsWith('.gif')) return 'image/gif';
      return 'image/jpeg'; // fallback seguro para imágenes
    }

    final contentType = inferContentType(file.name);

    try {
      final storageResponse = await SupabaseConfig.client.storage
          .from(bucket)
          .uploadBinary(
            path,
            fileBytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentType,
            ),
          );

      debugPrint('✅ [STORAGE] Archivo subido exitosamente: $storageResponse');

      final publicUrl = SupabaseConfig.client.storage
          .from(bucket)
          .getPublicUrl(path);

      debugPrint('🔗 [STORAGE] URL pública generada: $publicUrl');
      return publicUrl;
    } catch (e) {
      final msg = _friendlyStorageError(e);
      debugPrint('❌ [STORAGE] Error al subir $bucket/$path: $e');
      throw StorageUploadException(msg);
    }
  }

  /// Convierte errores de Supabase Storage en mensajes legibles para el usuario.
  static String _friendlyStorageError(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('bucket not found') || raw.contains("doesn't exist")) {
      return 'El bucket de almacenamiento no existe. Contacta al administrador.';
    }
    if (raw.contains('row-level security') || raw.contains('403') || raw.contains('unauthorized')) {
      return 'Sin permisos para subir imágenes (RLS). Verifica las políticas de storage.';
    }
    if (raw.contains('too large') || raw.contains('413')) {
      return 'Archivo demasiado grande. Máximo 5MB.';
    }
    if (raw.contains('mime') || raw.contains('content-type') || raw.contains('invalid')) {
      return 'Formato de archivo no permitido. Usa PNG, JPG o JPEG.';
    }
    return 'Error al subir imagen: $e';
  }

  /// Eliminar archivo
  static Future<bool> deleteFile({
    required String bucket,
    required String path,
  }) async {
    try {
      debugPrint('🗑️ [STORAGE] Deleting file from $bucket/$path');
      await SupabaseConfig.client.storage.from(bucket).remove([path]);
      debugPrint('✅ [STORAGE] File deleted successfully');
      return true;
    } catch (e) {
      debugPrint('❌ [STORAGE] Error deleting file: $e');
      return false;
    }
  }

  /// Extraer el path del storage desde una URL pública
  static String? extractPathFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      // URL típica: https://<project>.supabase.co/storage/v1/object/public/<bucket>/<path>
      final bucketIndex = segments.indexOf('public');
      if (bucketIndex >= 0 && segments.length > bucketIndex + 2) {
        return segments.sublist(bucketIndex + 2).join('/');
      }
      return null;
    } catch (e) {
      debugPrint('❌ [STORAGE] Error extracting path from URL: $e');
      return null;
    }
  }
}
