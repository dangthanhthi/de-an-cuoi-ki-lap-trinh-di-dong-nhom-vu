import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

const String defaultAvatarUrl = 'https://ui-avatars.com/api/?background=random';

String sanitizeFileName(String fileName, {String fallback = 'tep-dinh-kem'}) {
  final parts = fileName
      .split(RegExp(r'[\\/]'))
      .where((part) => part.trim().isNotEmpty)
      .toList();
  final rawName = parts.isEmpty ? null : parts.last.trim();
  final safeName = (rawName?.isNotEmpty == true ? rawName! : fallback)
      .replaceAll(RegExp(r'[\x00-\x1F\x7F#?\[\]*:<>|"]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (safeName.isEmpty) return fallback;
  if (safeName.length <= 120) return safeName;

  final dotIndex = safeName.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex > safeName.length - 2) {
    return safeName.substring(0, 120);
  }
  final extension = safeName.substring(dotIndex);
  final baseLength = 120 - extension.length;
  if (baseLength <= 0) return safeName.substring(0, 120);
  return '${safeName.substring(0, baseLength)}$extension';
}

String guessMimeType(String fileName) {
  final name = fileName.toLowerCase();
  if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.gif')) return 'image/gif';
  if (name.endsWith('.webp')) return 'image/webp';
  if (name.endsWith('.pdf')) return 'application/pdf';
  if (name.endsWith('.txt')) return 'text/plain';
  if (name.endsWith('.doc')) return 'application/msword';
  if (name.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  return 'application/octet-stream';
}

String buildDataUri(Uint8List bytes, String fileName, {String? mimeType}) {
  final safeName = Uri.encodeComponent(
    sanitizeFileName(fileName).replaceAll(';', '_'),
  );
  return 'data:${mimeType ?? guessMimeType(fileName)};name=$safeName;base64,${base64Encode(bytes)}';
}

bool isDataUri(String value) => value.startsWith('data:');

Uint8List? bytesFromDataUri(String value) {
  if (!isDataUri(value)) return null;
  final commaIndex = value.indexOf(',');
  if (commaIndex < 0) return null;
  try {
    return base64Decode(value.substring(commaIndex + 1));
  } catch (_) {
    return null;
  }
}

String fileNameFromDataUri(String value, {String fallback = 'tep-dinh-kem'}) {
  if (!isDataUri(value)) return fallback;
  final commaIndex = value.indexOf(',');
  final header = commaIndex >= 0 ? value.substring(0, commaIndex) : value;
  final nameMatch = RegExp(r'name=([^;]+)').firstMatch(header);
  if (nameMatch == null) return fallback;
  return sanitizeFileName(
    Uri.decodeComponent(nameMatch.group(1)!),
    fallback: fallback,
  );
}

String mimeTypeFromDataUri(String value) {
  if (!isDataUri(value)) return '';
  final end = value.indexOf(';');
  if (end <= 5) return '';
  return value.substring(5, end);
}

bool isImageValue(String value) {
  if (isDataUri(value)) return mimeTypeFromDataUri(value).startsWith('image/');
  final lower = value.toLowerCase();
  return lower.contains('.jpg') ||
      lower.contains('.jpeg') ||
      lower.contains('.png') ||
      lower.contains('.gif') ||
      lower.contains('.webp');
}

String attachmentLabel(String value, int index) {
  if (isDataUri(value)) {
    return fileNameFromDataUri(value, fallback: 'Tệp ${index + 1}');
  }
  final uri = Uri.tryParse(value);
  final path = uri?.pathSegments.isNotEmpty == true
      ? uri!.pathSegments.last
      : 'Tệp ${index + 1}';
  final cleanPath = sanitizeFileName(Uri.decodeComponent(path));
  return cleanPath.length > 28 ? 'Tệp ${index + 1}' : cleanPath;
}

ImageProvider avatarImageProvider(String? avatar, {String? name}) {
  final value = avatar?.trim() ?? '';
  final bytes = bytesFromDataUri(value);
  if (bytes != null) return MemoryImage(bytes);

  if (value.isNotEmpty) return NetworkImage(value);

  final safeName = Uri.encodeComponent(
    name?.trim().isNotEmpty == true ? name!.trim() : 'User',
  );
  return NetworkImage('https://ui-avatars.com/api/?name=$safeName');
}


