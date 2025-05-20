import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:math';
import 'ui/shooting_game.dart';
import 'ui/whack_a_mole.dart';
import 'ui/flappy_collect.dart';
import 'ui/tetris_game.dart';
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
      title: 'GreedMe Game Portal',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontWeight: FontWeight.bold, fontSize: 28, color: Colors.white),
          bodyMedium: TextStyle(fontSize: 18, color: Colors.black87),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      home: const MyHomePage(title: 'GreedMe Game Portal'),
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
  // ユーザーリスト取得
  Stream<QuerySnapshot<Map<String, dynamic>>> get _usersStream =>
      FirebaseFirestore.instance.collection('users').snapshots();

  void _startGame(String userId) async {
    final rand = Random();
    final gameType = rand.nextInt(4); // 0:shooting, 1:whack, 2:flappy, 3:tetris
    Widget gameWidget;
    if (gameType == 0) {
      gameWidget = ShootingGamePage(userId: userId);
    } else if (gameType == 1) {
      gameWidget = WhackAMolePage(userId: userId);
    } else if (gameType == 2) {
      gameWidget = FlappyCollectPage(userId: userId);
    } else {
      gameWidget = const TetrisGamePage();
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => gameWidget),
    );
  }

  Future<void> _onUserTap(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final password = doc.data()?['password'] ?? '';
    String? inputPassword = await showDialog<String>(
      context: context,
      builder: (context) {
        String temp = '';
        return AlertDialog(
          title: const Text('合言葉を入力してください'),
          content: TextField(
            autofocus: true,
            obscureText: false, // ここをfalseに
            decoration: const InputDecoration(hintText: '合言葉'),
            onChanged: (value) => temp = value,
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, temp),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (inputPassword == null) return;
    if (inputPassword == password) {
      _startGame(doc.id);
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('エラー'),
          content: const Text('合言葉が一致しませんでした。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.deepPurple.withOpacity(0.85),
        elevation: 8,
        title: Row(
          children: [
            const Icon(Icons.sports_esports, color: Colors.amber, size: 32),
            const SizedBox(width: 12),
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        centerTitle: false,
        toolbarHeight: 70,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF7F7FD5), Color(0xFF86A8E7), Color(0xFF91EAE4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
                child: Text(
                  'ユーザーを選んでゲームを始めよう！',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.deepPurple.shade900,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _usersStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(child: Text('ユーザーが見つかりません'));
                    }
                    final users = snapshot.data!.docs;
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final doc = users[index];
                        final name = doc.data()['name'] ?? doc.id;
                        return Card(
                          elevation: 6,
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.deepPurple.shade200,
                              child: Text(
                                name.isNotEmpty ? name[0] : '',
                                style: const TextStyle(fontSize: 22, color: Colors.white),
                              ),
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: Colors.deepPurple,
                              ),
                            ),
                            subtitle: Text(
                              'ID: ${doc.id}',
                              style: const TextStyle(fontSize: 14, color: Colors.black54),
                            ),
                            onTap: () => _onUserTap(doc),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0, top: 8),
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ユーザーをタップしてゲームを始めてください')),
                    );
                  },
                  icon: const Icon(Icons.info_outline),
                  label: const Text('遊び方'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
