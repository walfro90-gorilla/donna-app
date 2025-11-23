import 'package:file_picker/file_picker.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    String restaurantId,
    PlatformFile file,
  ) async {
    return _uploadFile(
      bucket: _restaurantImagesBucket,
      path: '$restaurantId/logo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file: file,
    );
  }

  /// Subir imagen de portada de restaurante
  static Future<String?> uploadRestaurantCover(
    String restaurantId,
    PlatformFile file,
  ) async {
    return _uploadFile(
      bucket: _restaurantImagesBucket,
      path: '$restaurantId/cover_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file: file,
    );
  }

  /// Subir imagen de fachada de restaurante (nueva)
  static Future<String?> uploadRestaurantFacade(
    String restaurantId,
    PlatformFile file,
  ) async {
    return _uploadFile(
      bucket: _restaurantImagesBucket,
      path: '$restaurantId/facade_${DateTime.now().millisecondsSinceEpoch}.jpg',
      file: file,
    );
  }

  /// Subir imagen de menú de restaurante
  static Future<String?> uploadRestaurantMenu(
    String restaurantId,
    PlatformFile file,
  ) async {
    return _uploadFile(
      bucket: _restaurantImagesBucket,
      path: '$restaurantId/menu_${DateTime.now().millisecondsSinceEpoch}.jpg',
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
    String restaurantId,
    PlatformFile file,
  ) async {
    return _uploadFile(
      bucket: _restaurantImagesBucket,
      path: '$restaurantId/products/product_${DateTime.now().millisecondsSinceEpoch}.jpg',
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

  /// Método genérico para subir archivo
  static Future<String?> _uploadFile({
    required String bucket,
    required String path,
    required PlatformFile file,
  }) async {
    try {
      print('📤 [STORAGE] Iniciando subida a $bucket/$path');
      print('📊 [STORAGE] Archivo: ${file.name}, Tamaño: ${file.size} bytes');

      // Obtener los bytes del archivo
      if (file.bytes == null) {
        print('❌ [STORAGE] Error: No hay bytes disponibles para el archivo ${file.name}');
        return null;
      }

      final fileBytes = file.bytes!;
      print('✅ [STORAGE] Bytes obtenidos: ${fileBytes.length} bytes');

      // Detectar content-type básico por extensión para cumplir con restricciones del bucket
      String _inferContentType(String name) {
        final lower = name.toLowerCase();
        if (lower.endsWith('.png')) return 'image/png';
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
        if (lower.endsWith('.webp')) return 'image/webp';
        if (lower.endsWith('.gif')) return 'image/gif';
        return 'application/octet-stream';
      }

      final contentType = _inferContentType(file.name);

      // Subir a Supabase Storage con opción de sobrescritura y contentType explícito
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

      print('✅ [STORAGE] Archivo subido exitosamente: $storageResponse');

      // Generar URL firmada (bucket privado). Si el bucket fuera público, podríamos usar getPublicUrl.
      try {
        final signedUrl = await SupabaseConfig.client.storage
            .from(bucket)
            .createSignedUrl(path, 60 * 60 * 24 * 7); // 7 días
        print('🔗 [STORAGE] URL firmada generada: $signedUrl');
        return signedUrl;
      } catch (e) {
        // Fallback: intentar URL pública si por alguna razón falla la firmada
        final publicUrl = SupabaseConfig.client.storage
            .from(bucket)
            .getPublicUrl(path);
        print('ℹ️ [STORAGE] Fallback a URL pública: $publicUrl');
        return publicUrl;
      }
    } catch (e, stackTrace) {
      print('❌ [STORAGE] Error al subir archivo: $e');
      print('📍 [STORAGE] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Eliminar archivo
  static Future<bool> deleteFile({
    required String bucket,
    required String path,
  }) async {
    try {
      print('🗑️ [STORAGE] Deleting file from $bucket/$path');

      await SupabaseConfig.client.storage.from(bucket).remove([path]);

      print('✅ [STORAGE] File deleted successfully');
      return true;
    } catch (e) {
      print('❌ [STORAGE] Error deleting file: $e');
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
        // Bucket está en bucketIndex + 1, path empieza en bucketIndex + 2
        return segments.sublist(bucketIndex + 2).join('/');
      }
      return null;
    } catch (e) {
      print('❌ [STORAGE] Error extracting path from URL: $e');
      return null;
    }
  }
}
