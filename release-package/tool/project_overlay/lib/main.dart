import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CommandsApp());
}

class CommandsApp extends StatelessWidget {
  const CommandsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Commands',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          surface: Colors.black,
          surfaceDim: Colors.black,
          surfaceBright: Colors.black,
          surfaceContainerLowest: Colors.black,
          surfaceContainerLow: Colors.black,
          surfaceContainer: Colors.black,
          surfaceContainerHigh: Colors.black,
          surfaceContainerHighest: Colors.black,
          surfaceTint: Colors.transparent,
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: Colors.white,
          onSecondary: Colors.black,
          onSurface: Colors.white,
          error: Colors.white,
          onError: Colors.black,
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(color: Colors.white),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: Colors.black,
          surfaceTintColor: Colors.transparent,
          textStyle: TextStyle(color: Colors.white),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.black,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white, width: 2),
          ),
          labelStyle: TextStyle(color: Colors.white),
          hintStyle: TextStyle(color: Colors.white),
        ),
      ),
      home: const CommandsPage(),
    );
  }
}

enum _SettingsSection {
  system('System'),
  global('Global'),
  secure('Secure'),
  prop('Prop');

  const _SettingsSection(this.title);
  final String title;
}

class _SettingEntry {
  const _SettingEntry({required this.key, required this.value});
  final String key;
  final String value;
}

class _CommandResult {
  const _CommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.timedOut,
  });

  final String stdout;
  final String stderr;
  final int exitCode;
  final bool timedOut;
}

class CommandsPage extends StatefulWidget {
  const CommandsPage({super.key});

  @override
  State<CommandsPage> createState() => _CommandsPageState();
}

class _CommandsPageState extends State<CommandsPage> {
  static const channel = MethodChannel('com.hyouka.commands/shizuku');

  final commandController = TextEditingController();
  final outputController = ScrollController();

  bool running = false;
  bool installed = false;
  bool shizukuRunning = false;
  bool permission = false;

  String status = 'Checking Shizuku...';
  String terminalText = '';

  @override
  void initState() {
    super.initState();
    refreshStatus();
  }

  @override
  void dispose() {
    commandController.dispose();
    outputController.dispose();
    super.dispose();
  }

  bool get authorized => installed && shizukuRunning && permission;

  String _statusText() {
    if (!installed) return 'Shizuku is not installed.';
    if (!shizukuRunning) return 'Shizuku is installed but not running.';
    if (!permission) return 'Shizuku permission is required.';
    return 'Shizuku is ready.';
  }

  Future<void> refreshStatus() async {
    try {
      final raw = await channel.invokeMethod<Map<dynamic, dynamic>>('status');
      final data = Map<String, dynamic>.from(raw ?? const {});
      if (!mounted) return;
      setState(() {
        installed = data['installed'] == true;
        shizukuRunning = data['running'] == true;
        permission = data['permission'] == true;
        status = _statusText();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => status = e.toString());
    }
  }

  Future<void> requestPermission() async {
    try {
      final granted = await channel.invokeMethod<bool>('requestPermission');
      await refreshStatus();
      if (!mounted) return;
      showMessage(
        granted == true
            ? 'Shizuku permission granted.'
            : 'Shizuku permission was not granted.',
      );
    } on PlatformException catch (e) {
      if (mounted) showMessage(e.message ?? e.code);
    }
  }

  Future<_CommandResult> _runShell(String command) async {
    final raw = await channel.invokeMethod<Map<dynamic, dynamic>>(
      'runCommand',
      <String, dynamic>{'command': command, 'timeoutMs': 120000},
    );
    final data = Map<String, dynamic>.from(raw ?? const {});
    return _CommandResult(
      stdout: data['stdout'] as String? ?? '',
      stderr: data['stderr'] as String? ?? '',
      exitCode: (data['exitCode'] as num?)?.toInt() ?? -1,
      timedOut: data['timedOut'] == true,
    );
  }

  Future<void> runCommand() async {
    final command = commandController.text.trim();
    if (command.isEmpty || running) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      running = true;
      terminalText = '';
    });

    try {
      final result = await _runShell(command);
      final parts = <String>[
        if (result.stdout.isNotEmpty) result.stdout.trimRight(),
        if (result.stderr.isNotEmpty) result.stderr.trimRight(),
        if (result.timedOut) 'Command timed out after 120 seconds.',
        if (!result.timedOut && result.exitCode != 0)
          'Command failed with exit code ' +
              result.exitCode.toString() +
              (result.stdout.isEmpty && result.stderr.isEmpty
                  ? ' (no output was returned).'
                  : '.'),
      ];
      if (!mounted) return;
      setState(() => terminalText = parts.join('\n'));
    } on PlatformException catch (e) {
      if (mounted) setState(() => terminalText = e.message ?? e.code);
    } catch (e) {
      if (mounted) setState(() => terminalText = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => running = false);
      await refreshStatus();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (outputController.hasClients) {
        outputController.animateTo(
          outputController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _openSettingsPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SettingsPage(
          isAuthorized: () => authorized,
          currentStatus: () => status,
          canGrantPermission: () => installed && shizukuRunning && !permission,
          onRefresh: refreshStatus,
          onRequestPermission: requestPermission,
          onOpenSection: _openSettingsSection,
        ),
      ),
    );
  }

  Future<void> _openSettingsSection(_SettingsSection section) async {
    if (!authorized) {
      showMessage('Shizuku must be running and authorized first.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _SectionDialog(
        section: section,
        channel: channel,
        parentContext: context,
      ),
    );
  }

  Future<void> saveOutput() async {
    try {
      final raw = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'saveOutput',
        <String, dynamic>{'content': terminalText},
      );
      final data = Map<String, dynamic>.from(raw ?? const {});
      final filename = data['filename'] as String? ?? 'commands file';
      if (!mounted) return;
      showMessage(
        data['success'] == true
            ? 'Saved as $filename in Downloads.'
            : 'Save failed.',
      );
    } on PlatformException catch (e) {
      if (mounted) showMessage(e.message ?? e.code);
    }
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.black,
          content: Text(message, style: const TextStyle(color: Colors.white)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Commands', style: TextStyle(color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: refreshStatus,
        color: Colors.white,
        backgroundColor: Colors.black,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!authorized) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: Colors.white),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.terminal, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            status,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        if (installed && shizukuRunning && !permission)
                          OutlinedButton(
                            onPressed: requestPermission,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white),
                            ),
                            child: const Text('Grant', style: TextStyle(color: Colors.white)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                OutlinedButton.icon(
                  onPressed: _openSettingsPage,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  ),
                  icon: const Icon(Icons.settings_outlined, color: Colors.white),
                  label: const Text(
                    'System settings',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 18),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Shell command',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(Icons.terminal, color: Colors.white, size: 19),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: commandController,
                  enabled: authorized && !running,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'Enter a shell command',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: authorized && !running ? runCommand : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                    ),
                    icon: running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow, color: Colors.white),
                    label: Text(running ? 'Running...' : 'Run'),
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Output',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      terminalText.isEmpty ? Icons.article_outlined : Icons.article,
                      color: Colors.white,
                      size: 19,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 260,
                  child: Scrollbar(
                    controller: outputController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: outputController,
                      child: SelectionArea(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            terminalText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: saveOutput,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.save_outlined, color: Colors.white),
                  label: const Text('Save Output', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.isAuthorized,
    required this.currentStatus,
    required this.canGrantPermission,
    required this.onRefresh,
    required this.onRequestPermission,
    required this.onOpenSection,
  });

  final bool Function() isAuthorized;
  final String Function() currentStatus;
  final bool Function() canGrantPermission;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRequestPermission;
  final Future<void> Function(_SettingsSection) onOpenSection;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  Future<void> _refresh() async {
    await widget.onRefresh();
    if (mounted) setState(() {});
  }

  Widget _sectionButton(_SettingsSection section) {
    final authorized = widget.isAuthorized();
    return OutlinedButton(
      onPressed: authorized ? () => widget.onOpenSection(section) : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white,
        side: const BorderSide(color: Colors.white),
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 14),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              section.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authorized = widget.isAuthorized();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: Colors.white,
        backgroundColor: Colors.black,
        child: SafeArea(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (!authorized) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.white),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.terminal, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.currentStatus(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      if (widget.canGrantPermission())
                        OutlinedButton(
                          onPressed: () async {
                            await widget.onRequestPermission();
                            if (mounted) setState(() {});
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white),
                          ),
                          child: const Text('Grant', style: TextStyle(color: Colors.white)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
              const Text(
                'System settings',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              _sectionButton(_SettingsSection.system),
              const SizedBox(height: 8),
              _sectionButton(_SettingsSection.global),
              const SizedBox(height: 8),
              _sectionButton(_SettingsSection.secure),
              const SizedBox(height: 8),
              _sectionButton(_SettingsSection.prop),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionDialog extends StatefulWidget {
  const _SectionDialog({
    required this.section,
    required this.channel,
    required this.parentContext,
  });

  final _SettingsSection section;
  final MethodChannel channel;
  final BuildContext parentContext;

  @override
  State<_SectionDialog> createState() => _SectionDialogState();
}

class _SectionDialogState extends State<_SectionDialog> {
  List<_SettingEntry> entries = const [];
  bool loading = true;
  String? error;
  bool searching = false;
  final searchController = TextEditingController();

  List<_SettingEntry> get visibleEntries {
    final query = searchController.text.trim().toLowerCase();
    if (query.isEmpty) return entries;
    return entries
        .where(
          (entry) =>
              entry.key.toLowerCase().contains(query) ||
              entry.value.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String _shellQuote(String value) {
    return "'" + value.replaceAll("'", "'\\''") + "'";
  }

  String _readCommand() {
    switch (widget.section) {
      case _SettingsSection.system:
        return 'settings list system';
      case _SettingsSection.global:
        return 'settings list global';
      case _SettingsSection.secure:
        return 'settings list secure';
      case _SettingsSection.prop:
        return 'getprop';
    }
  }

  String _writePrefix() {
    if (widget.section == _SettingsSection.prop) return 'setprop';
    return 'settings put ' + widget.section.title.toLowerCase();
  }

  String _getCommand(String key) {
    if (widget.section == _SettingsSection.prop) {
      return 'getprop ' + _shellQuote(key);
    }
    return 'settings get ' +
        widget.section.title.toLowerCase() +
        ' ' +
        _shellQuote(key);
  }

  Future<_CommandResult> _run(String command) async {
    final raw = await widget.channel.invokeMethod<Map<dynamic, dynamic>>(
      'runCommand',
      <String, dynamic>{'command': command, 'timeoutMs': 120000},
    );
    final data = Map<String, dynamic>.from(raw ?? const {});
    return _CommandResult(
      stdout: data['stdout'] as String? ?? '',
      stderr: data['stderr'] as String? ?? '',
      exitCode: (data['exitCode'] as num?)?.toInt() ?? -1,
      timedOut: data['timedOut'] == true,
    );
  }

  List<_SettingEntry> _parse(String raw) {
    final values = <_SettingEntry>[];
    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (widget.section == _SettingsSection.prop) {
        if (!line.startsWith('[')) continue;
        final keyEnd = line.indexOf(']');
        final valueStart = line.indexOf('[', keyEnd + 1);
        if (keyEnd <= 1 || valueStart < 0 || !line.endsWith(']')) continue;
        values.add(
          _SettingEntry(
            key: line.substring(1, keyEnd),
            value: line.substring(valueStart + 1, line.length - 1),
          ),
        );
      } else {
        final equals = line.indexOf('=');
        if (equals <= 0) continue;
        values.add(
          _SettingEntry(
            key: line.substring(0, equals),
            value: line.substring(equals + 1),
          ),
        );
      }
    }
    values.sort((a, b) => a.key.compareTo(b.key));
    return values;
  }

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }

    try {
      final result = await _run(_readCommand());
      if (!mounted) return;

      if (result.exitCode != 0 && result.stdout.trim().isEmpty) {
        setState(() {
          loading = false;
          error = result.stderr.trim().isEmpty
              ? 'Unable to read ' + widget.section.title + '.'
              : result.stderr.trim();
        });
        return;
      }

      final parsed = _parse(result.stdout);
      setState(() {
        loading = false;
        entries = parsed;
        error = parsed.isEmpty ? 'No values were returned.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  Future<void> _editEntry(_SettingEntry entry) async {
    final controller = TextEditingController(text: entry.value);
    final readOnly =
        widget.section == _SettingsSection.prop && entry.key.startsWith('ro.');

    try {
      final apply = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.black,
          title: Text(
            entry.key,
            style: const TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            readOnly: readOnly,
            autofocus: !readOnly,
            minLines: 1,
            maxLines: 8,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              labelText: readOnly ? 'Read-only value' : 'Value',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white),
              ),
            ),
            if (!readOnly)
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'Apply',
                  style: TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
      );

      if (apply != true || readOnly) return;

      final command = _writePrefix() +
          ' ' +
          _shellQuote(entry.key) +
          ' ' +
          _shellQuote(controller.text);

      final result = await _run(command);
      if (!mounted) return;

      if (result.exitCode != 0) {
        final details = result.stderr.trim().isNotEmpty
            ? result.stderr.trim()
            : result.stdout.trim().isNotEmpty
                ? result.stdout.trim()
                : 'Command failed with exit code ' + result.exitCode.toString() + '.';
        showMessage(details);
        return;
      }

      final verified = await _run(_getCommand(entry.key));
      if (!mounted) return;

      if (verified.exitCode != 0) {
        showMessage(
          verified.stderr.trim().isEmpty
              ? 'Value was applied, but verification failed (exit code ' +
                  verified.exitCode.toString() +
                  ').'
              : verified.stderr.trim(),
        );
      } else if (verified.stdout.trim() == controller.text) {
        showMessage('Value applied.');
      } else {
        showMessage('The system returned a different value after Apply.');
      }

      await _reload();
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      controller.dispose();
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(widget.parentContext)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.black,
          content: Text(message, style: const TextStyle(color: Colors.white)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: SizedBox(
        width: 700,
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.section.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: loading
                        ? null
                        : () => setState(() => searching = true),
                    tooltip: 'Search',
                    icon: const Icon(Icons.search, color: Colors.white),
                  ),
                  IconButton(
                    onPressed: loading ? null : _reload,
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh, color: Colors.white),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            if (searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                child: TextField(
                  controller: searchController,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, color: Colors.white),
                    hintText: 'Search by key or value',
                    suffixIcon: IconButton(
                      onPressed: () {
                        searchController.clear();
                        setState(() => searching = false);
                      },
                      tooltip: 'Close search',
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                          itemCount: visibleEntries.length,
                          separatorBuilder: (_, __) => const Divider(
                            color: Colors.white12,
                            height: 1,
                          ),
                          itemBuilder: (context, index) {
                            final entry = visibleEntries[index];
                            final readOnly =
                                widget.section == _SettingsSection.prop &&
                                entry.key.startsWith('ro.');

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 8,
                                    ),
                                    child: SelectableText(
                                      entry.key,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 5,
                                  child: InkWell(
                                    onTap: () => _editEntry(entry),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 8,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              entry.value.isEmpty
                                                  ? '(empty)'
                                                  : entry.value,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontFamily: 'monospace',
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            readOnly
                                                ? Icons.lock_outline
                                                : Icons.edit_outlined,
                                            color: Colors.white54,
                                            size: 16,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
