import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

class RhythmGamePage extends StatefulWidget {
  final String userId;
  const RhythmGamePage({Key? key, required this.userId}) : super(key: key);

  @override
  State<RhythmGamePage> createState() => _RhythmGamePageState();
}

class _RhythmGamePageState extends State<RhythmGamePage> {
  static const int laneCount = 3; // レーン3つ
  static const int noteTypeCount = 3; // ノーツ種類3種
  static const double noteSpeed = 300; // px/sec
  static const Duration gameDuration = Duration(seconds: 30);

  // レーン: 0=上左, 1=右下, 2=AB
  static const List<List<String>> laneInputs = [
    ['up', 'left'],   // レーン0: 上 or 左
    ['right', 'down'],// レーン1: 右 or 下
    ['A', 'B'],       // レーン2: A or B
  ];
  static const List<String> laneLabels = ['↑/←', '→/↓', 'A/B'];
  static const List<IconData> laneIcons = [
    Icons.unfold_less, // 上/左
    Icons.unfold_more, // 右/下
    Icons.games,       // A/B
  ];

  late Timer timer;
  late Timer gameTimer;
  double elapsed = 0;
  bool isGameOver = false;
  List<_Note> notes = [];
  int scoreA = 0;
  int scoreB = 0;
  int scoreC = 0;
  Random rand = Random();

  WebSocketChannel? _channel;

  // 入力→lane
  int? _inputToLane(String input) {
    for (int i = 0; i < laneInputs.length; i++) {
      if (laneInputs[i].contains(input)) return i;
    }
    return null;
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
          final lane = _inputToLane(input);
          if (lane != null) {
            _hitLane(lane);
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
      int lane = rand.nextInt(laneCount); // 0,1,2
      notes.add(_Note(lane: lane, time: t));
      t += 0.5 + rand.nextDouble() * 0.7;
    }
  }

  void _update(Timer _) {
    if (isGameOver) return;
    setState(() {
      elapsed += 0.016;
    });
  }

  void _hitLane(int lane) {
    if (isGameOver) return;
    for (final note in notes) {
      if (note.hit) continue;
      if (note.lane == lane && (note.time - elapsed).abs() < 0.25) {
        note.hit = true;
        if (lane == 0) {
          scoreA += 10;
        } else if (lane == 1) {
          scoreB += 10;
        } else {
          scoreC += 10;
        }
        break;
      }
    }
  }

  Future<void> _saveScoreToFirestore() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .set({
      'scoreA': scoreA,
      'scoreB': scoreB,
      'scoreC': scoreC,
    }, SetOptions(merge: true));
  }

  void _endGame() async {
    isGameOver = true;
    timer.cancel();
    gameTimer.cancel();
    await _saveScoreToFirestore();
    setState(() {});
  }

  @override
  void dispose() {
    _channel?.sink.close();
    timer.cancel();
    gameTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = 420;
    double screenHeight = 600;
    double laneWidth = screenWidth / laneCount;
    double hitLineY = screenHeight - 100;

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
                left: 0,
                right: 0,
                top: hitLineY,
                height: 4,
                child: Container(color: Colors.white54),
              ),
              // ノーツ
              ...notes.map((note) {
                if (note.hit) return const SizedBox.shrink();
                double y = hitLineY - (note.time - elapsed) * noteSpeed;
                if (y > screenHeight || y < -30) return const SizedBox.shrink();
                return Positioned(
                  left: note.lane * laneWidth + laneWidth * 0.15,
                  top: y,
                  child: Container(
                    width: laneWidth * 0.7,
                    height: 28,
                    decoration: BoxDecoration(
                      color: note.lane == 0
                          ? Colors.red
                          : note.lane == 1
                              ? Colors.blue
                              : Colors.orange,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Center(
                      child: Icon(laneIcons[note.lane], color: Colors.white, size: 20),
                    ),
                  ),
                );
              }),
              // レーン区切り
              ...List.generate(laneCount - 1, (i) {
                return Positioned(
                  left: (i + 1) * laneWidth,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.white24),
                );
              }),
              // スコア表示
              Positioned(
                left: 16,
                top: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ScoreA: $scoreA', style: const TextStyle(color: Colors.red, fontSize: 18)),
                    Text('ScoreB: $scoreB', style: const TextStyle(color: Colors.blue, fontSize: 18)),
                    Text('ScoreC: $scoreC', style: const TextStyle(color: Colors.orange, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text('合計: ${scoreA + scoreB + scoreC}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              // 操作ボタン
              if (!isGameOver)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 20,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(laneCount, (i) {
                      return _laneButton(laneIcons[i], () => _hitLane(i), laneLabels[i]);
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
                          Text('ScoreA: $scoreA', style: const TextStyle(fontSize: 20, color: Colors.red)),
                          Text('ScoreB: $scoreB', style: const TextStyle(fontSize: 20, color: Colors.blue)),
                          Text('ScoreC: $scoreC', style: const TextStyle(fontSize: 20, color: Colors.orange)),
                          const SizedBox(height: 8),
                          Text('合計: ${scoreA + scoreB + scoreC}', style: const TextStyle(fontSize: 24, color: Colors.white)),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                elapsed = 0;
                                scoreA = 0;
                                scoreB = 0;
                                scoreC = 0;
                                isGameOver = false;
                                _generateNotes();
                                timer = Timer.periodic(const Duration(milliseconds: 16), _update);
                                gameTimer = Timer(gameDuration, _endGame);
                              });
                            },
                            child: const Text('もう一度プレイ'),
                          ),
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

  Widget _laneButton(IconData icon, VoidCallback onTap, String label) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}

class _Note {
  final int lane;
  final double time;
  bool hit = false;
  _Note({required this.lane, required this.time});
}
