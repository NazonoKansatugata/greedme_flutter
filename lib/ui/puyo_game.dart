import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

const int rowCount = 15; // 以前は20
const int colCount = 6;
const Duration tick = Duration(milliseconds: 400);

enum PuyoColor { red, green, blue, yellow, purple, orange }

const Map<PuyoColor, Color> puyoColors = {
  PuyoColor.red: Colors.red,
  PuyoColor.green: Colors.green,
  PuyoColor.blue: Colors.blue,
  PuyoColor.yellow: Colors.yellow,
  PuyoColor.purple: Colors.purple,
  PuyoColor.orange: Colors.orange, // シアン→オレンジ
};

class PuyoPair {
  PuyoColor color1;
  PuyoColor color2;
  int x;
  int y;
  int dir; // 0:上,1:右,2:下,3:左

  PuyoPair(this.color1, this.color2, this.x, this.y, this.dir);

  List<_PuyoBlock> get blocks {
    // dir=0: color1(中心), color2(上)
    // dir=1: color1(中心), color2(右)
    // dir=2: color1(中心), color2(下)
    // dir=3: color1(中心), color2(左)
    int dx = 0, dy = 0;
    switch (dir) {
      case 0: dx = 0; dy = -1; break;
      case 1: dx = 1; dy = 0; break;
      case 2: dx = 0; dy = 1; break;
      case 3: dx = -1; dy = 0; break;
    }
    return [
      _PuyoBlock(x, y, color1),
      _PuyoBlock(x + dx, y + dy, color2),
    ];
  }

  PuyoPair copyWith({int? x, int? y, int? dir}) {
    return PuyoPair(
      color1,
      color2,
      x ?? this.x,
      y ?? this.y,
      dir ?? this.dir,
    );
  }
}

class _PuyoBlock {
  int x, y;
  PuyoColor color;
  _PuyoBlock(this.x, this.y, this.color);
}

class PuyoGamePage extends StatefulWidget {
  final String userId;
  const PuyoGamePage({Key? key, required this.userId}) : super(key: key);

  @override
  State<PuyoGamePage> createState() => _PuyoGamePageState();
}

class _PuyoGamePageState extends State<PuyoGamePage> {
  late List<List<PuyoColor?>> field;
  PuyoPair? currentPair;
  PuyoPair? holdPair;
  bool holdUsed = false;
  Timer? timer;
  int score = 0;
  bool isGameOver = false;
  final Random rand = Random();

  WebSocketChannel? _channel;

  int scoreA = 0; // 赤・緑
  int scoreB = 0; // 青・黄
  int scoreC = 0; // 紫・シアン

  List<PuyoPair> nextPairs = [];

  @override
  void initState() {
    super.initState();
    _startGame();

    _channel = WebSocketChannel.connect(Uri.parse('wss://greendme-websocket.onrender.com'));
    _channel!.sink.add(jsonEncode({'type': 'register', 'role': 'game', 'userId': widget.userId}));
    _channel!.stream.listen((message) {
      try {
        final msg = jsonDecode(message);
        if (msg['type'] == 'input') {
          final input = msg['data'];
          if (input == 'left') {
            _move(-1);
          } else if (input == 'right') {
            _move(1);
          } else if (input == 'down') {
            _tick();
          } else if (input == 'A') {
            _rotate();
          } else if (input == 'B') {
            _hold();
          }
        }
      } catch (e) {
        print('WebSocket受信エラー: $e');
      }
    }, onError: (error) {
      print('WebSocketエラー: $error');
    });
  }

  void _startGame() {
    field = List.generate(rowCount, (_) => List.filled(colCount, null));
    score = 0;
    scoreA = 0;
    scoreB = 0;
    scoreC = 0;
    isGameOver = false;
    holdPair = null;
    holdUsed = false;
    nextPairs = List.generate(1, (_) => _randomPair()); // 1個先だけ
    _spawnPair();
    timer = Timer.periodic(tick, (_) => _tick());
  }

  PuyoColor _randomColor() {
    return PuyoColor.values[rand.nextInt(PuyoColor.values.length)];
  }

  PuyoPair _randomPair() {
    return PuyoPair(_randomColor(), _randomColor(), colCount ~/ 2, 1, 0);
  }

  void _spawnPair() {
    currentPair = nextPairs.removeAt(0);
    nextPairs.add(_randomPair());
    holdUsed = false;
    if (_isCollision(currentPair!)) {
      _endGame();
    }
  }

  bool _isCollision(PuyoPair pair) {
    for (final b in pair.blocks) {
      if (b.x < 0 || b.x >= colCount || b.y < 0 || b.y >= rowCount) return true;
      if (field[b.y][b.x] != null) return true;
    }
    return false;
  }

  void _fixPair() {
    // まず両方のぷよを配置
    for (final b in currentPair!.blocks) {
      if (b.y >= 0 && b.y < rowCount && b.x >= 0 && b.x < colCount) {
        field[b.y][b.x] = b.color;
      }
    }
    // 配置直後に全ての列で下まで落とす（浮いているぷよを解消）
    _fall();
    _resolve();
    _spawnPair();
  }

  void _resolve() async {
    int chain = 1;
    while (true) {
      final erasedMap = _eraseConnectedWithColor();
      int erased = erasedMap.values.fold(0, (a, b) => a + b);
      if (erased > 0) {
        // 連鎖倍率でスコア加算
        score += erased * 10 * chain;
        scoreA += (erasedMap['A'] ?? 0) * chain;
        scoreB += (erasedMap['B'] ?? 0) * chain;
        scoreC += (erasedMap['C'] ?? 0) * chain;
        chain++;
        await Future.delayed(const Duration(milliseconds: 200));
        _fall();
      } else {
        break;
      }
    }
  }

  /// 色ごとに消した数を返す: {'A': 赤緑, 'B': 青黄, 'C': 紫シアン}
  Map<String, int> _eraseConnectedWithColor() {
    List<List<bool>> visited = List.generate(rowCount, (_) => List.filled(colCount, false));
    int erasedA = 0, erasedB = 0, erasedC = 0;
    int erasedTotal = 0;
    for (int y = 0; y < rowCount; y++) {
      for (int x = 0; x < colCount; x++) {
        if (field[y][x] == null || visited[y][x]) continue;
        final color = field[y][x];
        List<_PuyoBlock> group = [];
        _dfs(x, y, color!, visited, group);
        if (group.length >= 4) {
          for (final b in group) {
            if (b.color == PuyoColor.red || b.color == PuyoColor.green) {
              erasedA++;
            } else if (b.color == PuyoColor.blue || b.color == PuyoColor.yellow) {
              erasedB++;
            } else if (b.color == PuyoColor.purple || b.color == PuyoColor.orange) {
              erasedC++;
            }
            field[b.y][b.x] = null;
            erasedTotal++;
          }
        }
      }
    }
    return {'A': erasedA, 'B': erasedB, 'C': erasedC};
  }

  void _dfs(int x, int y, PuyoColor color, List<List<bool>> visited, List<_PuyoBlock> group) {
    if (x < 0 || x >= colCount || y < 0 || y >= rowCount) return;
    if (visited[y][x] || field[y][x] != color) return;
    visited[y][x] = true;
    group.add(_PuyoBlock(x, y, color));
    _dfs(x + 1, y, color, visited, group);
    _dfs(x - 1, y, color, visited, group);
    _dfs(x, y + 1, color, visited, group);
    _dfs(x, y - 1, color, visited, group);
  }

  void _fall() {
    // 1つ下にぷよか地面がなければ、何度も繰り返し1マスずつ下に落とす
    bool moved;
    do {
      moved = false;
      for (int y = rowCount - 2; y >= 0; y--) {
        for (int x = 0; x < colCount; x++) {
          if (field[y][x] != null && field[y + 1][x] == null) {
            field[y + 1][x] = field[y][x];
            field[y][x] = null;
            moved = true;
          }
        }
      }
    } while (moved);
  }

  void _tick() {
    if (isGameOver || currentPair == null) return;
    final moved = currentPair!.copyWith(y: currentPair!.y + 1);
    if (!_isCollision(moved)) {
      setState(() {
        currentPair = moved;
      });
    } else {
      _fixPair();
      setState(() {});
    }
  }

  void _move(int dx) {
    if (isGameOver || currentPair == null) return;
    final moved = currentPair!.copyWith(x: currentPair!.x + dx);
    if (!_isCollision(moved)) {
      setState(() {
        currentPair = moved;
      });
    }
  }

  void _rotate() {
    if (isGameOver || currentPair == null) return;
    final nextDir = (currentPair!.dir + 1) % 4;
    final rotated = currentPair!.copyWith(dir: nextDir);
    if (!_isCollision(rotated)) {
      setState(() {
        currentPair = rotated;
      });
    }
  }

  void _hold() {
    if (isGameOver || currentPair == null || holdUsed) return;
    setState(() {
      if (holdPair == null) {
        holdPair = currentPair;
        _spawnPair();
      } else {
        final tmp = holdPair;
        holdPair = currentPair;
        currentPair = tmp;
        if (_isCollision(currentPair!)) {
          _endGame();
        }
      }
      holdUsed = true;
    });
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
    timer?.cancel();
    await _saveScoreToFirestore();
    setState(() {});
  }

  @override
  void dispose() {
    _channel?.sink.close();
    timer?.cancel();
    super.dispose();
  }

  Widget _buildCell(PuyoColor? color) {
    return Container(
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: color != null ? puyoColors[color] : Colors.grey[200],
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12),
      ),
    );
  }

  Widget _buildField() {
    List<List<PuyoColor?>> displayField = List.generate(rowCount, (y) => List<PuyoColor?>.from(field[y]));
    if (currentPair != null) {
      for (final b in currentPair!.blocks) {
        if (b.y >= 0 && b.y < rowCount && b.x >= 0 && b.x < colCount) {
          displayField[b.y][b.x] = b.color;
        }
      }
    }
    return AspectRatio(
      aspectRatio: colCount / rowCount,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: colCount,
          ),
          itemCount: rowCount * colCount,
          itemBuilder: (context, idx) {
            int y = idx ~/ colCount;
            int x = idx % colCount;
            return _buildCell(displayField[y][x]);
          },
        ),
      ),
    );
  }

  Widget _buildHoldPair() {
    if (holdPair == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: puyoColors[holdPair!.color1],
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black12),
          ),
        ),
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: puyoColors[holdPair!.color2],
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black12),
          ),
        ),
      ],
    );
  }

  Widget _buildNextPairs() {
    // 1個先だけ表示
    final pair = nextPairs[0];
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: puyoColors[pair.color1],
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 2),
          ),
        ),
        Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: puyoColors[pair.color2],
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 2),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[50],
      appBar: AppBar(
        title: const Text('ぷよぷよ風ゲーム'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  const Text('Hold', style: TextStyle(fontWeight: FontWeight.bold)),
                  _buildHoldPair(),
                ],
              ),
              Column(
                children: [
                  const Text('Next', style: TextStyle(fontWeight: FontWeight.bold)),
                  _buildNextPairs(),
                ],
              ),
              // スコア表示
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ScoreA: $scoreA', style: const TextStyle(fontSize: 16, color: Colors.red)),
                  Text('ScoreB: $scoreB', style: const TextStyle(fontSize: 16, color: Colors.blue)),
                  Text('ScoreC: $scoreC', style: const TextStyle(fontSize: 16, color: Colors.purple)),
                  const SizedBox(height: 4),
                  Text('合計: ${scoreA + scoreB + scoreC}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(child: _buildField()),
          ),
          if (!isGameOver)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_left, size: 36),
                    onPressed: () => _move(-1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.rotate_right, size: 36),
                    onPressed: _rotate,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_right, size: 36),
                    onPressed: () => _move(1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward, size: 36),
                    onPressed: _tick,
                  ),
                  IconButton(
                    icon: const Icon(Icons.pause, size: 36),
                    onPressed: _hold,
                  ),
                ],
              ),
            ),
          if (isGameOver)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Game Over', style: TextStyle(fontSize: 28, color: Colors.red, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('ScoreA: $scoreA', style: const TextStyle(fontSize: 18, color: Colors.red)),
                  Text('ScoreB: $scoreB', style: const TextStyle(fontSize: 18, color: Colors.blue)),
                  Text('ScoreC: $scoreC', style: const TextStyle(fontSize: 18, color: Colors.purple)),
                  const SizedBox(height: 8),
                  Text('合計: ${scoreA + scoreB + scoreC}', style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _startGame,
                    child: const Text('もう一度プレイ'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
