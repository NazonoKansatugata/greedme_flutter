class Bullet {
  double x;
  double y;
  double dy;
  bool isPlayer;
  Bullet({required this.x, required this.y, required this.dy, required this.isPlayer});

  void move() {
    y += dy;
  }
}
