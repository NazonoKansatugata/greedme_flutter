import 'bullet.dart';

class Player {
  double x;
  double y;
  Player({required this.x, required this.y});

  Bullet shoot() {
    return Bullet(x: x, y: y, dy: -8, isPlayer: true);
  }
}
