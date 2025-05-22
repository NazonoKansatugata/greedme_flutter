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
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

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

  Future<void> _showHowToPlayDialog(BuildContext context, String title, String description, VoidCallback onOk) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    onOk();
  }

  void _startGame(String userId) async {
    final rand = Random();
    final gameType = rand.nextInt(4); // 0:shooting, 1:whack, 2:flappy, 3:tetris
    Widget gameWidget;
    String howToTitle = '';
    String howToDesc = '';
    if (gameType == 0) {
      gameWidget = ShootingGamePage(userId: userId);
      howToTitle = 'シューティングゲームの遊び方';
      howToDesc = '左右ボタンまたは←→キーで移動し、中央のボタンまたはスペースキーで弾を連射して障害物を撃ちましょう。\n30秒間でたくさん撃ち落とそう！';
    } else if (gameType == 1) {
      gameWidget = WhackAMolePage(userId: userId);
      howToTitle = 'もぐらたたきの遊び方';
      howToDesc = '3種類のもぐらが出てきます。タップして素早くたたきましょう。\n30秒間でたくさん叩いてスコアを稼ごう！';
    } else if (gameType == 2) {
      gameWidget = FlappyCollectPage(userId: userId);
      howToTitle = 'フラッピーバード風ゲームの遊び方';
      howToDesc = '画面タップまたはジャンプボタンで上昇します。\n3種類のオブジェクトを取ってスコアを稼ごう！30秒間の勝負です。';
    } else {
      gameWidget = TetrisGamePage(userId: userId);
      howToTitle = 'テトリス風ゲームの遊び方';
      howToDesc = 'ブロックを左右移動・回転・落下させて横一列を揃えましょう。\n操作: ←→で移動、回転ボタン、↓でソフトドロップ、⏬でハードドロップ。';
    }
    await _showHowToPlayDialog(context, howToTitle, howToDesc, () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Center(
            child: SizedBox(
              width: 600, // パソコン向けに幅を広げる
              height: 900, // パソコン向けに高さを広げる
              child: gameWidget,
            ),
          ),
        ),
      );
    });
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

  // WebSocket関連
  WebSocketChannel? _channel;
  String _lastInput = '';

  @override
  void initState() {
    super.initState();
    // 必要に応じてアドレスを変更
    _channel = WebSocketChannel.connect(Uri.parse('wss://greendme-websocket.onrender.com'));
    // ゲーム画面として登録
    _channel!.sink.add(jsonEncode({'type': 'register', 'role': 'game'}));
    _channel!.stream.listen((message) {
      try {
        final msg = jsonDecode(message);
        if (msg['type'] == 'input') {
          setState(() {
            _lastInput = msg['data'].toString();
          });
          // ログ出力
          print('コントローラーからの指示: ${msg['data']}');
        }
      } catch (e) {
        print('WebSocket受信エラー: $e');
      }
    }, onError: (error) {
      print('WebSocketエラー: $error');
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
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
                child: Column(
                  children: [
                    ElevatedButton.icon(
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
                    const SizedBox(height: 16),
                    // 追加: コントローラーからの指示を表示
                    if (_lastInput.isNotEmpty)
                      Text(
                        'コントローラーからの指示: $_lastInput',
                        style: const TextStyle(fontSize: 20, color: Colors.deepPurple),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
