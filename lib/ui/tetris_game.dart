import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

const int rowCount = 20;
const int colCount = 10;
const Duration tick = Duration(milliseconds: 400);

enum BlockType { I, O, T, S, Z, J, L }

const Map<BlockType, List<List<List<int>>>> blockShapes = {
  BlockType.I: [
    [
      [1, 1, 1, 1]
    ],
    [
      [1],
      [1],
      [1],
      [1]
    ]
  ],
  BlockType.O: [
    [
      [1, 1],
      [1, 1]
    ]
  ],
  BlockType.T: [
    [
      [0, 1, 0],
      [1, 1, 1]
    ],
    [
      [1, 0],
      [1, 1],
      [1, 0]
    ],
    [
      [1, 1, 1],
      [0, 1, 0]
    ],
    [
      [0, 1],
      [1, 1],
      [0, 1]
    ]
  ],
  BlockType.S: [
    [
      [0, 1, 1],
      [1, 1, 0]
    ],
    [
      [1, 0],
      [1, 1],
      [0, 1]
    ]
  ],
  BlockType.Z: [
    [
      [1, 1, 0],
      [0, 1, 1]
    ],
    [
      [0, 1],
      [1, 1],
      [1, 0]
    ]
  ],
  BlockType.J: [
    [
      [1, 0, 0],
      [1, 1, 1]
    ],
    [
      [1, 1],
      [1, 0],
      [1, 0]
    ],
    [
      [1, 1, 1],
      [0, 0, 1]
    ],
    [
      [0, 1],
      [0, 1],
      [1, 1]
    ]
  ],
  BlockType.L: [
    [
      [0, 0, 1],
      [1, 1, 1]
    ],
    [
      [1, 0],
      [1, 0],
      [1, 1]
    ],
    [
      [1, 1, 1],
      [1, 0, 0]
    ],
    [
      [1, 1],
      [0, 1],
      [0, 1]
    ]
  ],
};

const Map<BlockType, Color> blockColors = {
  BlockType.I: Colors.cyan,
  BlockType.O: Colors.yellow,
  BlockType.T: Colors.purple,
  BlockType.S: Colors.green,
  BlockType.Z: Colors.red,
  BlockType.J: Colors.blue,
  BlockType.L: Colors.orange,
};

class Block {
  BlockType type;
  int rotation;
  int x;
  int y;

  Block(this.type, this.rotation, this.x, this.y);

  List<List<int>> get shape => blockShapes[type]![rotation];

  int get width => shape[0].length;
  int get height => shape.length;

  Block copyWith({int? x, int? y, int? rotation}) {
    return Block(
      type,
      rotation ?? this.rotation,
      x ?? this.x,
      y ?? this.y,
    );
  }
}

class TetrisGamePage extends StatefulWidget {
  const TetrisGamePage({Key? key}) : super(key: key);

  @override
  State<TetrisGamePage> createState() => _TetrisGamePageState();
}

class _TetrisGamePageState extends State<TetrisGamePage> {
  late List<List<BlockType?>> field;
  Block? currentBlock;
  BlockType? nextBlockType;
  Timer? timer;
  int score = 0;
  bool isGameOver = false;
  final Random rand = Random();

  // WebSocket関連
  WebSocketChannel? _channel;

  @override
  void initState() {
    super.initState();
    _startGame();

    // WebSocket接続
    _channel = WebSocketChannel.connect(Uri.parse('wss://greendme-websocket.onrender.com'));
    // ゲーム画面として登録
    _channel!.sink.add(jsonEncode({'type': 'register', 'role': 'game'}));
    _channel!.stream.listen((message) {
      try {
        final msg = jsonDecode(message);
        if (msg['type'] == 'input') {
          final input = msg['data'];
          // コントローラーからの指示に応じて操作
          if (input == 'left') {
            _move(-1);
          } else if (input == 'right') {
            _move(1);
          } else if (input == 'rotate') {
            _rotate();
          } else if (input == 'soft_drop') {
            _tick();
          } else if (input == 'hard_drop') {
            _drop();
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
    isGameOver = false;
    nextBlockType = _randomBlockType();
    _spawnBlock();
    timer = Timer.periodic(tick, (_) => _tick());
  }

  BlockType _randomBlockType() {
    return BlockType.values[rand.nextInt(BlockType.values.length)];
  }

  void _spawnBlock() {
    final type = nextBlockType ?? _randomBlockType();
    nextBlockType = _randomBlockType();
    currentBlock = Block(type, 0, (colCount ~/ 2) - 2, 0);
    if (_isCollision(currentBlock!)) {
      isGameOver = true;
      timer?.cancel();
      setState(() {});
    }
  }

  bool _isCollision(Block block) {
    final shape = block.shape;
    for (int dy = 0; dy < shape.length; dy++) {
      for (int dx = 0; dx < shape[dy].length; dx++) {
        if (shape[dy][dx] == 0) continue;
        int fx = block.x + dx;
        int fy = block.y + dy;
        if (fx < 0 || fx >= colCount || fy < 0 || fy >= rowCount) return true;
        if (field[fy][fx] != null) return true;
      }
    }
    return false;
  }

  void _fixBlock() {
    final block = currentBlock!;
    final shape = block.shape;
    for (int dy = 0; dy < shape.length; dy++) {
      for (int dx = 0; dx < shape[dy].length; dx++) {
        if (shape[dy][dx] == 0) continue;
        int fx = block.x + dx;
        int fy = block.y + dy;
        if (fy >= 0 && fy < rowCount && fx >= 0 && fx < colCount) {
          field[fy][fx] = block.type;
        }
      }
    }
    _clearLines();
    _spawnBlock();
  }

  void _clearLines() {
    int cleared = 0;
    field.removeWhere((row) {
      if (row.every((cell) => cell != null)) {
        cleared++;
        return true;
      }
      return false;
    });
    while (field.length < rowCount) {
      field.insert(0, List.filled(colCount, null));
    }
    score += cleared * 100;
  }

  void _tick() {
    if (isGameOver || currentBlock == null) return;
    final moved = currentBlock!.copyWith(y: currentBlock!.y + 1);
    if (!_isCollision(moved)) {
      setState(() {
        currentBlock = moved;
      });
    } else {
      _fixBlock();
      setState(() {});
    }
  }

  void _move(int dx) {
    if (isGameOver || currentBlock == null) return;
    final moved = currentBlock!.copyWith(x: currentBlock!.x + dx);
    if (!_isCollision(moved)) {
      setState(() {
        currentBlock = moved;
      });
    }
  }

  void _rotate() {
    if (isGameOver || currentBlock == null) return;
    final shapes = blockShapes[currentBlock!.type]!;
    final nextRot = (currentBlock!.rotation + 1) % shapes.length;
    final rotated = currentBlock!.copyWith(rotation: nextRot);
    if (!_isCollision(rotated)) {
      setState(() {
        currentBlock = rotated;
      });
    }
  }

  void _drop() {
    if (isGameOver || currentBlock == null) return;
    var dropped = currentBlock!;
    while (!_isCollision(dropped.copyWith(y: dropped.y + 1))) {
      dropped = dropped.copyWith(y: dropped.y + 1);
    }
    setState(() {
      currentBlock = dropped;
    });
    _fixBlock();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    timer?.cancel();
    super.dispose();
  }

  Widget _buildCell(BlockType? type) {
    return Container(
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: type != null ? blockColors[type] : Colors.grey[200],
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black12),
      ),
    );
  }

  Widget _buildField() {
    // 描画用フィールド
    List<List<BlockType?>> displayField = List.generate(rowCount, (y) => List<BlockType?>.from(field[y]));
    if (currentBlock != null) {
      final shape = currentBlock!.shape;
      for (int dy = 0; dy < shape.length; dy++) {
        for (int dx = 0; dx < shape[dy].length; dx++) {
          if (shape[dy][dx] == 0) continue;
          int fx = currentBlock!.x + dx;
          int fy = currentBlock!.y + dy;
          if (fy >= 0 && fy < rowCount && fx >= 0 && fx < colCount) {
            displayField[fy][fx] = currentBlock!.type;
          }
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

  Widget _buildNextBlock() {
    if (nextBlockType == null) return const SizedBox.shrink();
    final shape = blockShapes[nextBlockType]![0];
    return Column(
      children: shape.map((row) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: row.map((cell) {
            return Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: cell == 1 ? blockColors[nextBlockType] : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: Colors.black12),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[50],
      appBar: AppBar(
        title: const Text('テトリス風ゲーム'),
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
                  const Text('Next', style: TextStyle(fontWeight: FontWeight.bold)),
                  _buildNextBlock(),
                ],
              ),
              Text('Score: $score', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                    icon: const Icon(Icons.vertical_align_bottom, size: 36),
                    onPressed: _drop,
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
                  Text('Score: $score', style: const TextStyle(fontSize: 22)),
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
