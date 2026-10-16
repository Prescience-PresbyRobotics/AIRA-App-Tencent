import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'controller.dart';
import 'theme.dart';
import 'screens/auth.dart';
import 'screens/onboarding.dart';
import 'screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  SupabaseClient? client;
  if (url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(url: url, publishableKey: key);
    client = Supabase.instance.client;
  }
  runApp(AiraApp(controller: AiraController(client)));
}

class AiraApp extends StatelessWidget {
  final AiraController controller;
  const AiraApp({super.key, required this.controller});
  @override
  Widget build(BuildContext c) => ListenableBuilder(
    listenable: controller,
    builder: (c, _) => MaterialApp(
      key: ValueKey(controller.sessionEpoch),
      title: 'AIRA · A little company, every day',
      debugShowCheckedModeBanner: false,
      theme: airaTheme(largerText: controller.largerText),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: AiraTextScaler(
            MediaQuery.textScalerOf(context),
            factor: controller.largerText ? .9 : .78,
          ),
        ),
        child: child!,
      ),
      home: controller.recovering
          ? AuthScreen(controller: controller, recovery: true)
          : !controller.signedIn
          ? AuthScreen(controller: controller)
          : controller.loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : !controller.onboarded
          ? OnboardingScreen(controller: controller)
          : AiraShell(controller: controller),
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => controller.signedIn && controller.onboarded
            ? AiraShell(controller: controller, initialRoute: settings.name)
            : AuthScreen(controller: controller),
      ),
    ),
  );
}
