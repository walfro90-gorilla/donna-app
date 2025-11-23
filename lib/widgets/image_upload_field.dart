import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';

/// Widget reutilizable para cargar imágenes con preview
/// Soporta web y móvil usando file_picker
class ImageUploadField extends StatefulWidget {
  final String label;
  final String? hint;
  final IconData icon;
  final String? imageUrl;
  final bool isRequired;
  final Function(PlatformFile?) onImageSelected;
  final String? helpText;
  final double aspectRatio;

  const ImageUploadField({
    super.key,
    required this.label,
    this.hint,
    required this.icon,
    this.imageUrl,
    this.isRequired = false,
    required this.onImageSelected,
    this.helpText,
    this.aspectRatio = 1.0,
  });

  @override
  State<ImageUploadField> createState() => _ImageUploadFieldState();
}

class _ImageUploadFieldState extends State<ImageUploadField> {
  PlatformFile? _selectedFile;
  bool _isLoading = false;

  Future<void> _pickImage() async {
    setState(() => _isLoading = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'svg'],
        allowMultiple: false,
        withData: true, // Siempre cargar bytes para cross-platform support
      );

      if (result != null && result.files.isNotEmpty) {
        final picked = result.files.first;
        final ext = (picked.extension ?? '').toLowerCase();
        const allowed = ['png', 'jpg', 'jpeg', 'svg'];
        if (!allowed.contains(ext)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Formato no permitido. Usa PNG, JPG/JPEG o SVG.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        setState(() => _selectedFile = picked);
        print('🖼️ Imagen seleccionada: ${_selectedFile?.name} (${_selectedFile?.bytes?.length} bytes)');
        widget.onImageSelected(_selectedFile);
      }
    } catch (e) {
      print('❌ Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _removeImage() {
    setState(() {
      _selectedFile = null;
    });
    widget.onImageSelected(null);
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _selectedFile != null || widget.imageUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Row(
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),
            if (widget.isRequired)
              const Text(
                ' *',
                style: TextStyle(color: Colors.red, fontSize: 14),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Image preview or upload button
        GestureDetector(
          onTap: _isLoading ? null : _pickImage,
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              color: hasImage ? Colors.black12 : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasImage ? const Color(0xFF4CAF50) : const Color(0xFFDDDDDD),
                width: hasImage ? 2 : 1,
              ),
            ),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : hasImage
                    ? _buildImagePreview()
                    : _buildUploadPrompt(),
          ),
        ),

        // Help text
        if (widget.helpText != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.helpText!,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF666666),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: _selectedFile != null
                ? _buildSelectedImage()
                : _buildNetworkImage(),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.red,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: _removeImage,
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 16),
                SizedBox(width: 6),
                Text(
                  'Imagen cargada',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedImage() {
    if (_selectedFile?.bytes != null) {
      return Image.memory(
        _selectedFile!.bytes!,
        fit: BoxFit.cover,
      );
    } else if (_selectedFile?.path != null) {
      // En plataformas nativas usaríamos File(_selectedFile!.path!)
      // pero como debe ser cross-platform, mostramos un placeholder
      return const Center(
        child: Icon(Icons.image, size: 64, color: Colors.grey),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildNetworkImage() {
    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      return Image.network(
        widget.imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildUploadPrompt() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFF2D55).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            widget.icon,
            size: 32,
            color: const Color(0xFFFF2D55),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.hint ?? 'Toca para subir imagen',
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF666666),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'PNG, JPG/JPEG, SVG • Max 5MB',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }
}
