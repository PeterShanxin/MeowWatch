import 'package:flutter/material.dart';

import 'core/connect/room_config.dart';
import 'core/data/stores.dart';
import 'ui/connect/connect_screen.dart';
import 'ui/home_screen.dart';

class MeowWatchApp extends StatelessWidget {
  const MeowWatchApp({
    required this.profiles,
    required this.history,
    super.key,
  });

  final ProfileStore profiles;
  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeowWatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD4A574),
          brightness: Brightness.dark,
        ),
      ),
      home: Builder(
        builder: (context) => ConnectScreen(
          profiles: profiles,
          history: history,
          onConnect: (RoomConfig config) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HomeScreen(config: config, history: history),
            ),
          ),
        ),
      ),
    );
  }
}
