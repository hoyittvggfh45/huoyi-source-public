import 'package:flutter/material.dart';

import 'hongguo_account.dart';
import 'login_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  @override
  void initState() {
    super.initState();
    ensureHongguoAccountLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账号')),
      body: ValueListenableBuilder<HongguoAccount?>(
        valueListenable: hongguoAccountNotifier,
        builder: (context, account, _) {
          if (account == null || !account.loggedIn) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('未登录'),
                  subtitle: Text('登录后这里显示你的账号'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => LoginScreen()),
                  ),
                  child: const Text('去登录'),
                ),
                const SizedBox(height: 16),
                const Text(loginLimitationNote),
                const SizedBox(height: 8),
                const Text('收藏与观看进度同步暂未接入，仍只保存在本机。'),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(account.displayName),
                subtitle: Text(
                  [
                    if (account.maskedPhone.isNotEmpty) account.maskedPhone,
                    account.methodLabel,
                  ].join(' · '),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  await clearHongguoAccount();
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已退出登录')));
                  }
                },
                child: const Text('退出登录'),
              ),
              const SizedBox(height: 16),
              const Text(loginLimitationNote),
              const SizedBox(height: 8),
              const Text('收藏与观看进度同步暂未接入，仍只保存在本机。'),
            ],
          );
        },
      ),
    );
  }
}
