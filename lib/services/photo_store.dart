import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps the photos of checked products so a misread can be compared with the
/// package later.
class PhotoStore {
  PhotoStore._();

  static Future<Directory> _dir() async {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'expiry_photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Moves a captured photo out of the temporary folder and returns its new
  /// path.
  static Future<String> keep(String tempPath) async {
    final dir = await _dir();
    final target = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}.jpg');
    final src = File(tempPath);
    try {
      await src.rename(target);
    } on FileSystemException {
      await src.copy(target);
      await src.delete().catchError((Object _) => src);
    }
    return target;
  }

  static Future<void> delete(String path) async {
    if (path.isEmpty) return;
    try {
      await File(path).delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  static Future<void> deleteAll() async {
    final dir = await _dir();
    await for (final f in dir.list()) {
      if (f is File) await f.delete().catchError((Object _) => f);
    }
  }
}
