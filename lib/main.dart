import 'package:flutter/material.dart';
import 'dart:math';
import 'ui/shooting_game.dart';
import 'ui/whack_a_mole.dart';
import 'ui/flappy_collect.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String? userId;

  Future<void> _showUserIdDialog() async {
    String tempId = '';
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('ユーザーID入力'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'ユーザーIDを入力してください'),
          onChanged: (value) => tempId = value,
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (tempId.isNotEmpty) {
                setState(() {
                  userId = tempId;
                });
                Navigator.of(context).pop();
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _startGame() async {
    await _showUserIdDialog();
    if (userId != null && userId!.isNotEmpty) {
      // FirestoreでユーザーIDの存在確認
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (!doc.exists) {
        // エラーダイアログ表示
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('エラー'),
              content: const Text('入力されたユーザーIDは存在しません。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }
      final rand = Random();
      final gameType = rand.nextInt(3);
      Widget gameWidget;
      if (gameType == 0) {
        gameWidget = ShootingGamePage(userId: userId!);
      } else if (gameType == 1) {
        gameWidget = WhackAMolePage(userId: userId!);
      } else {
        gameWidget = FlappyCollectPage(userId: userId!);
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => gameWidget),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: ElevatedButton(
          child: const Text('ゲーム開始'),
          onPressed: _startGame,
        ),
      ),
    );
  }
}
