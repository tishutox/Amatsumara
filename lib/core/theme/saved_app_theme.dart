import 'package:flutter/material.dart';
import 'package:lumii_quest/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const systemColorModePrefKey = 'system_color_mode';

enum SystemColorMode { light, dark, hellaverse, glitch }

class SystemPalette {
  const SystemPalette({
    required this.navColor,
    required this.backgroundColor,
    required this.brightness,
  });

  final Color navColor;
  final Color backgroundColor;
  final Brightness brightness;
}

const systemPalettes = <SystemColorMode, SystemPalette>{
  SystemColorMode.light: SystemPalette(
    navColor: Color(0xFF5860C3),
    backgroundColor: Color(0xFFFFFFFF),
    brightness: Brightness.light,
  ),
  SystemColorMode.dark: SystemPalette(
    navColor: Color(0xFF5860C3),
    backgroundColor: Color(0xFF121212),
    brightness: Brightness.dark,
  ),
  SystemColorMode.hellaverse: SystemPalette(
    navColor: Color(0xFFF90142),
    backgroundColor: Color(0xFF121212),
    brightness: Brightness.dark,
  ),
  SystemColorMode.glitch: SystemPalette(
    navColor: Color(0xFFDB5DC9),
    backgroundColor: Color(0xFF121212),
    brightness: Brightness.dark,
  ),
};

ThemeData themeForSystemColorMode(SystemColorMode mode) {
  final palette = systemPalettes[mode]!;
  return AppTheme.system(
    primary: palette.navColor,
    background: palette.backgroundColor,
    brightness: palette.brightness,
  );
}

SystemColorMode systemColorModeFromName(String? name) {
  return SystemColorMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => SystemColorMode.light,
  );
}

class SavedAppTheme extends StatefulWidget {
  const SavedAppTheme({required this.child, super.key});

  final Widget child;

  @override
  State<SavedAppTheme> createState() => _SavedAppThemeState();
}

class _SavedAppThemeState extends State<SavedAppTheme> {
  SystemColorMode _mode = SystemColorMode.light;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = systemColorModeFromName(
      prefs.getString(systemColorModePrefKey),
    );
    if (mounted && mode != _mode) {
      setState(() => _mode = mode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(data: themeForSystemColorMode(_mode), child: widget.child);
  }
}
