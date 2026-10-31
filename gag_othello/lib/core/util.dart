/// 小さなユーティリティ。`num.clamp` は戻り値が num になり型が合わないことがあるので自前で持つ。
int clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);
