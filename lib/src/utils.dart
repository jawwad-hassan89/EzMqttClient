import 'dart:io';

import 'package:device_info/device_info.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class Utils {
  Utils._();

  ///
  /// Accepts an input [filePath] from the assets, and an optional [outputFileName].
  /// Returns the file with the fileName [outputFileName]
  /// * The files in the assets folder cannot be accessed directly using the
  /// asset's path, so it needs to be copied to the internal storage before
  /// it can be accessed in the app.
  ///
  static Future<File> getFileFromAssets(String filePath,
      {String outputFileName}) async {
    ByteData data = await rootBundle.load(filePath);
    String directory = (await getTemporaryDirectory()).path;
    if (outputFileName == null) outputFileName = filePath.split('/').last;

    return await File('$directory/$outputFileName').writeAsBytes(
      data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ),
    );
  }

  ///
  /// returns a uniqueandroidId in case of android and identifierForVendor
  /// in case of iOS.
  ///
  static Future<String> get deviceUniqueId async {
    final _deviceInfo = DeviceInfoPlugin();

    return Platform.isIOS
        ? _deviceInfo.iosInfo.then((info) => info.identifierForVendor)
        : _deviceInfo.androidInfo.then((info) => info.androidId);
  }

  /// Generates a random uuid
  static String get uuid => Uuid().v4();
}
