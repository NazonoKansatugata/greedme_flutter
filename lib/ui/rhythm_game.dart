import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class RhythmGamePage extends StatefulWidget {
  final String userId;
  const RhythmGamePage({Key? key, required this.userId}) : super(key: key);

  @override
  State<RhythmGamePage> createState() => _RhythmGamePageState();
}

class _RhythmGamePageState extends State<RhythmGamePage> {
  static const int laneCount = 1;
  static const int noteTypeCount = 6;
  static const double noteSpeed = 120; // ここを遅く
  static const Duration gameDuration = Duration(seconds: 30);

  static const List<String> noteInputs = [
    'A', 'B', 'up', 'down', 'left', 'right'
  ];
  static const List<String> noteLabels = [
    'A', 'B', '↑', '↓', '←', '→'
  ];
  static const List<IconData> noteIcons = [
    Icons.circle, Icons.square, Icons.arrow_upward, Icons.arrow_downward, Icons.arrow_left, Icons.arrow_right
  ];
  static const List<Color> noteColors = [
    Colors.red, Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.amber
  ];

  late Timer timer;
  late Timer gameTimer;
  double elapsed = 0;
  bool isGameOver = false;
  List<_Note> notes = [];
  Random rand = Random();

  WebSocketChannel? _channel;

  int scoreA = 0; // A, B
  int scoreB = 0; // ↑, ↓
  int scoreC = 0; // ←, →
  
  // 入力→ノーツ種別
  int? _inputToNoteType(String input) {
    return noteInputs.indexOf(input);
  }

  @override
  void initState() {
    super.initState();
    _generateNotes();
    timer = Timer.periodic(const Duration(milliseconds: 16), _update);
    gameTimer = Timer(gameDuration, _endGame);

    _channel = WebSocketChannel.connect(Uri.parse('wss://greendme-websocket.onrender.com'));
    _channel!.sink.add(jsonEncode({'type': 'register', 'role': 'game', 'userId': widget.userId}));
    _channel!.stream.listen((message) {
      try {
        final msg = jsonDecode(message);
        if (msg['type'] == 'input') {
          final input = msg['data'];
          final noteType = _inputToNoteType(input);
          if (noteType != -1 && noteType != null) {
            _hitNote(noteType);
          }
        }
      } catch (e) {
        print('WebSocket受信エラー: $e');
      }
    }, onError: (error) {
      print('WebSocketエラー: $error');
    });
  }

  void _generateNotes() {
    notes.clear();
    double t = 1.0;
    while (t < gameDuration.inSeconds - 1) {
      int noteType = rand.nextInt(noteTypeCount);
      notes.add(_Note(type: noteType, time: t));
      t += 0.5 + rand.nextDouble() * 0.7;
    }
  }

  void _update(Timer _) {
    if (isGameOver) return;
    setState(() {
      elapsed += 0.016;
    });
  }

  void _hitNote(int noteType) {
    if (isGameOver) return;
    for (final note in notes) {
      if (note.hit) continue;
      if (note.type == noteType) {
        double noteX = _noteX(note);
        double hitLineX = 60;
        if ((noteX - hitLineX).abs() < 32) {
          note.hit = true;
          if (noteType == 0 || noteType == 1) {
            scoreA += 10;
          } else if (noteType == 2 || noteType == 3) {
            scoreB += 10;
          } else if (noteType == 4 || noteType == 5) {
            scoreC += 10;
          }
          break;
        }
      }
    }
  }

  Future<void> _saveScoreToFirestore() async {
    // Firestore保存処理を削除
    // await FirebaseFirestore.instance
    //     .collection('users')
    //     .doc(widget.userId)
    //     .set({
    //   'scoreA': scoreA,
    //   'scoreB': scoreB,
    //   'scoreC': scoreC,
    // }, SetOptions(merge: true));
  }

  void _endGame() async {
    isGameOver = true;
    timer.cancel();
    gameTimer.cancel();
    // await _saveScoreToFirestore(); // 削除
    setState(() {});
    // リダイレクト
    Future.delayed(const Duration(milliseconds: 500), () async {
      final url = Uri.parse('https://unity-greendme.web.app/');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    timer.cancel();
    gameTimer.cancel();
    super.dispose();
  }

  double _noteX(_Note note) {
    double screenWidth = 420;
    // 右から左へ流れるように修正
    return screenWidth - ((note.time - elapsed) * noteSpeed) - 40;
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = 420;
    double screenHeight = 200;
    double hitLineX = 60;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('リズムゲーム'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Center(
        child: SizedBox(
          width: screenWidth,
          height: screenHeight,
          child: Stack(
            children: [
              // 判定ライン
              Positioned(
                left: hitLineX,
                top: 0,
                bottom: 0,
                width: 6,
                child: Container(color: Colors.white54),
              ),
              // ノーツ
              ...notes.map((note) {
                if (note.hit) return const SizedBox.shrink();
                double x = _noteX(note);
                if (x < -40 || x > screenWidth) return const SizedBox.shrink();
                return Positioned(
                  left: x,
                  top: 60,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: noteColors[note.type],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Center(
                      child: Icon(noteIcons[note.type], color: Colors.white, size: 28),
                    ),
                  ),
                );
              }),
              // スコア表示
              Positioned(
                left: 16,
                top: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ScoreA: $scoreA', style: TextStyle(color: Colors.red, fontSize: 16)),
                    Text('ScoreB: $scoreB', style: TextStyle(color: Colors.green, fontSize: 16)),
                    Text('ScoreC: $scoreC', style: TextStyle(color: Colors.purple, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('合計: ${scoreA + scoreB + scoreC}',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              // 操作ボタン
              if (!isGameOver)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(noteTypeCount, (i) {
                      return _noteButton(noteIcons[i], () => _hitNote(i), noteLabels[i], noteColors[i]);
                    }),
                  ),
                ),
              if (isGameOver)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.7),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Game Over', style: TextStyle(fontSize: 32, color: Colors.red, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          Text('ScoreA: $scoreA', style: const TextStyle(fontSize: 18, color: Colors.red)),
                          Text('ScoreB: $scoreB', style: const TextStyle(fontSize: 18, color: Colors.green)),
                          Text('ScoreC: $scoreC', style: const TextStyle(fontSize: 18, color: Colors.purple)),
                          const SizedBox(height: 8),
                          Text('合計: ${scoreA + scoreB + scoreC}', style: const TextStyle(fontSize: 24, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteButton(IconData icon, VoidCallback onTap, String label, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}

class _Note {
  final int type;
  final double time;
  bool hit = false;
  _Note({required this.type, required this.time});
}
