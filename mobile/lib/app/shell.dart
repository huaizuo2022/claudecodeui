import 'package:flutter/material.dart';

import '../features/sessions/session_list_page.dart';
import '../features/settings/settings_page.dart';
import '../features/workspace/workspace_page.dart';
import 'theme/tokens.dart';

/// The three-tab shell. Pages are kept alive in an [IndexedStack] so the
/// session list keeps its scroll position when the user visits settings.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: IndexedStack(
        index: _index,
        children: [
          SessionListPage(),
          WorkspacePage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        onSelect: (value) => setState(() => _index = value),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.chat_bubble_outline, label: '会话'),
    (icon: Icons.terminal, label: '工作区'),
    (icon: Icons.settings_outlined, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 10),
      decoration: BoxDecoration(
        color: palette.navBarBg,
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onSelect(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _items[i].icon,
                        size: 23,
                        color: i == index ? palette.accent : palette.text3,
                      ),
                      SizedBox(height: 4),
                      Text(
                        _items[i].label,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: i == index ? palette.accent : palette.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
