part of '../../app/fastink_app.dart';

extension _FastInkAboutSettingsCards on _FastInkHomeState {
  /// 构建语言选择设置，显示当前模式并将变更交给根语言回调保存。
  Widget _languageSettingsCard() {
    final AppLanguage selected = widget.language;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ListTile(
          leading: const Icon(Icons.language_rounded),
          title: Text(
            tr('语言'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(tr('更改后立即应用到整个软件')),
          trailing: DropdownButtonHideUnderline(
            child: DropdownButton<AppLanguage>(
              value: selected,
              borderRadius: BorderRadius.circular(12),
              onChanged: (AppLanguage? value) {
                if (value != null) widget.onLanguageChanged(value);
              },
              items: <DropdownMenuItem<AppLanguage>>[
                DropdownMenuItem<AppLanguage>(
                  value: AppLanguage.system,
                  child: Text(tr('跟随系统')),
                ),
                DropdownMenuItem<AppLanguage>(
                  value: AppLanguage.zh,
                  child: Text(tr('简体中文')),
                ),
                DropdownMenuItem<AppLanguage>(
                  value: AppLanguage.en,
                  child: Text(tr('英语')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Windows 右键上下文菜单集成设置卡片（仅 Windows）。
  /// 检测当前 exe 是否位于构建输出目录（flutter run / flutter build 产物）。
  ///
  /// 构建产物路径不稳定：重新构建会切换 Debug/Release，flutter clean 会删除整个目录。
  /// 只有把 exe 放到固定位置（安装版或手动复制到某目录）才能保证右键菜单持续可用。
  static bool _isBuildOutputPath(String exePath) {
    final String lower = exePath.toLowerCase();
    return lower.contains(
          '${Platform.pathSeparator}build${Platform.pathSeparator}',
        ) ||
        lower.contains('\\build\\');
  }

  /// 显示 Windows 文件右键集成当前注册状态与可执行切换入口。
  Widget _contextMenuSettingsCard() {
    if (!Platform.isWindows) return const SizedBox.shrink();
    final bool registered = _contextMenuRegistered;
    final String exePath = winreg.getExecutablePath();
    final bool unstablePath = _isBuildOutputPath(exePath);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.integration_instructions_outlined),
              title: Text(
                tr('右键菜单集成', 'Context menu integration'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                tr(
                  '在资源管理器中右键点击文件，选择"用 FastInk 打开"',
                  'Right-click any file in Explorer to open it with FastInk',
                ),
              ),
            ),
            if (unstablePath)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(
                          '当前运行的是构建产物，重新构建后右键菜单会失效。'
                              '请将 exe 复制到固定目录后再启用。',
                          'Running from build output — the context menu will '
                              'break after rebuild. Copy the exe to a permanent '
                              'folder first.',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SwitchListTile.adaptive(
              secondary: Icon(
                registered
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
              ),
              title: Text(
                registered
                    ? tr('已添加到右键菜单', 'Added to context menu')
                    : tr('添加到右键菜单', 'Add to context menu'),
              ),
              subtitle: Text(
                registered
                    ? tr(
                        '再次点击可从右键菜单中移除',
                        'Click again to remove from context menu',
                      )
                    : tr(
                        '写入当前用户注册表，无需管理员权限',
                        'Writes to HKCU — no admin rights required',
                      ),
              ),
              value: registered,
              onChanged: unstablePath
                  ? null
                  : (bool value) {
                      _toggleContextMenu(value);
                    },
            ),
            if (registered && exePath.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  exePath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 仅注册/移除本应用拥有的文件关联入口，更新实际结果并向用户反馈失败。
  void _toggleContextMenu(bool enable) {
    if (!Platform.isWindows) return;
    if (enable) {
      final String exePath = winreg.getExecutablePath();
      if (exePath.isEmpty) {
        _updateState(
          () => _doc.status = tr('无法获取可执行文件路径', 'Cannot get executable path'),
        );
        return;
      }
      final bool ok = winreg.registerContextMenu(exePath);
      _updateState(() {
        _contextMenuRegistered = ok;
        _doc.status = ok
            ? tr('已添加到右键菜单', 'Added to context menu')
            : tr('添加右键菜单失败', 'Could not add the context menu');
      });
    } else {
      final bool ok = winreg.unregisterContextMenu();
      _updateState(() {
        _contextMenuRegistered = !ok ? _contextMenuRegistered : false;
        _doc.status = ok
            ? tr('已从右键菜单移除', 'Removed from context menu')
            : tr('移除右键菜单失败', 'Failed to remove context menu');
      });
    }
  }

  /// 构建版本、数据和配置位置等关于信息，路径使用当前平台分隔符展示。
  Widget _aboutSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ListTile(
          leading: const Icon(Icons.info_outline_rounded),
          title: Text(
            tr('关于'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text('FastInk ${AppVersion.name}'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _showAboutFastInk,
        ),
      ),
    );
  }

  /// 打开关于窗口，版本来自同步生成常量，目录文本可复制。
  void _showAboutFastInk() {
    showAboutDialog(
      context: context,
      applicationName: 'FastInk',
      applicationVersion: AppVersion.display,
      applicationIcon: Image.asset(
        'assets/fastink_icon.png',
        width: 46,
        height: 46,
      ),
      applicationLegalese: 'Copyright © 2026 FastInk',
      children: <Widget>[
        const SizedBox(height: 8),
        Text(tr('高性能、按页加载的手写笔记软件。')),
        const SizedBox(height: 16),
        SelectableText(
          '${tr('数据位置')}\n${_displayLocalPath(_dataRoot)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        SelectableText(
          '${tr('配置位置')}\n${_displayLocalPath(SettingsRepository.activeConfigRoot)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Text(tr('隐私说明：FastInk 的笔记和设置默认保存在本机，不会自动上传。')),
      ],
    );
  }
}
