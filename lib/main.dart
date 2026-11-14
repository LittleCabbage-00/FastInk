import 'src/app/fastink_app.dart' as application;

export 'src/app/fastink_app.dart';

/// Flutter 入口保留在固定位置，转交应用初始化并透传 Windows 命令行参数。
Future<void> main(List<String> arguments) => application.main(arguments);
