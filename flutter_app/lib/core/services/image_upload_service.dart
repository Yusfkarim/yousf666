import 'marketplace_client.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_lib;

abstract interface class ImageUploadService {
  Future<String> upload(File file, {required String folder});
}

class CompressedImage {
  const CompressedImage(this.bytes);
  final Uint8List bytes;
}

Future<CompressedImage> compressMarketplaceImage(File file) async {
  final original = await file.readAsBytes();
  final decoded = image_lib.decodeImage(original);
  if (decoded == null) throw const FormatException('Could not read the selected image');

  final longestSide = math.max(decoded.width, decoded.height);
  final scale = math.min(1.0, 1080 / longestSide);
  var width = math.max(1, (decoded.width * scale).round()).toInt();
  var height = math.max(1, (decoded.height * scale).round()).toInt();
  const qualities = [70, 60, 50, 40];

  for (var attempt = 0; attempt < 16; attempt++) {
    final quality = qualities[attempt % qualities.length];
    final result = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: width,
      minHeight: height,
      quality: quality,
      format: CompressFormat.webp,
      keepExif: false,
    );
    if (result == null || result.isEmpty) throw const FormatException('Image compression failed');
    if (result.lengthInBytes < 120 * 1024) return CompressedImage(result);

    if (attempt % qualities.length == qualities.length - 1) {
      width = math.max(240, (width * .82).round()).toInt();
      height = math.max(240, (height * .82).round()).toInt();
    }
  }
  throw const FormatException('Choose a smaller image; compressed photos must be under 120 KB');
}

class LocalImageUploadService implements ImageUploadService {
  LocalImageUploadService(this.client);
  final MarketplaceClient client;

  @override
  Future<String> upload(File file, {required String folder}) async {
    final compressed = await compressMarketplaceImage(file);
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Sign in to upload images');
    final safeFolder = folder.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final path = '$userId/$safeFolder/${DateTime.now().microsecondsSinceEpoch}.webp';
    await client.storage.from('marketplace-images').uploadBinary(
          path,
          compressed.bytes,
          fileOptions: const FileOptions(contentType: 'image/webp', upsert: false),
        );
    return client.storage.from('marketplace-images').getPublicUrl(path);
  }
}

class CloudinaryImageUploadService implements ImageUploadService {
  CloudinaryImageUploadService({required this.cloudName, required this.uploadPreset});

  final String cloudName;
  final String uploadPreset;

  @override
  Future<String> upload(File file, {required String folder}) async {
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      throw StateError('Set CLOUDINARY_CLOUD_NAME and CLOUDINARY_UPLOAD_PRESET to upload images');
    }
    final compressed = await compressMarketplaceImage(file);
    final request = http.MultipartRequest(
      'POST',
      Uri.https('api.cloudinary.com', '/v1_1/$cloudName/image/upload'),
    )
      ..fields['upload_preset'] = uploadPreset
      ..fields['folder'] = folder
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        compressed.bytes,
        filename: 'marketplace-${DateTime.now().microsecondsSinceEpoch}.webp',
      ));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(body['error']?['message'] as String? ?? 'Image upload failed');
    }
    final url = body['secure_url'] as String?;
    if (url == null || url.isEmpty) throw StateError('Image provider returned no secure URL');
    return url;
  }
}

ImageUploadService createImageUploadService(MarketplaceClient client) {
  const cloudName = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
  const uploadPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');
  const provider = String.fromEnvironment('IMAGE_PROVIDER', defaultValue: 'local');
  if (provider == 'cloudinary') {
    return CloudinaryImageUploadService(cloudName: cloudName, uploadPreset: uploadPreset);
  }
  return LocalImageUploadService(client);
}
