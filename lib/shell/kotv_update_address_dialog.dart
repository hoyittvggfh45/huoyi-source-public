import 'package:flutter/material.dart';

import '../app_page_route.dart';
import '../app_update_screen.dart';
import '../update_config.dart';
import 'kotv_theme.dart';

class KotvUpdateAddressDialog extends StatefulWidget {
  const KotvUpdateAddressDialog({super.key});

  @override
  State<KotvUpdateAddressDialog> createState() =>
      _KotvUpdateAddressDialogState();
}

class _KotvUpdateAddressDialogState extends State<KotvUpdateAddressDialog> {
  final _address = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.pop(context);
    Navigator.push(
      context,
      appPageRoute<void>(builder: (_) => const AppUpdateScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '更新地址',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                '当前更新地址',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                releasesPageUrl ?? '未配置',
                style: const TextStyle(
                  fontSize: 13,
                  color: KotvTokens.unselectedColor,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'version.json 地址',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '我方更新地址为编译期配置，无法在此修改；上方输入不会被保存。确定后打开软件更新屏，按既有地址检查更新。',
                style: TextStyle(
                  fontSize: 13,
                  color: KotvTokens.unselectedColor,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _confirm,
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showKotvUpdateAddressDialog({required BuildContext context}) {
  return showDialog<void>(
    context: context,
    builder: (_) => const KotvUpdateAddressDialog(),
  );
}
