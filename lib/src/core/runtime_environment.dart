import 'dart:io';

/// 提供与安装方式有关的运行环境信息。
///
/// Portable 包会在可执行文件旁放置一个标记文件。应用只依赖该标记判断
/// 数据是否随程序保存，避免把安装器、打包路径等发布细节带入业务代码。
abstract final class RuntimeEnvironment {
  /// portableMarkerName：便携模式标记文件名，存在时采用程序旁的数据目录。
  static const String portableMarkerName = '.fastink-portable';

  /// 返回当前可执行程序所在目录，统一便携路径与随包工具定位。
  static String get applicationDirectory =>
      File(Platform.resolvedExecutable).parent.path;

  /// 返回便携模式程序旁的 FastInk 数据根目录，不等于源代码目录。
  static String get portableDataDirectory =>
      '$applicationDirectory/FastInkData';

  /// 返回便携模式配置目录，与资料内容分开定位。
  static String get portableConfigDirectory =>
      '$portableDataDirectory/.fastink';

  /// 检查程序旁的便携标记，决定是否采用便携目录约定。
  static bool get isPortable =>
      File('$applicationDirectory/$portableMarkerName').existsSync();
}
