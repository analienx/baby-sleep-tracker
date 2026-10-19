import 'package:baby_sleep_tracker/app/clock.dart';

final class FakeClock implements Clock {
  FakeClock(this.nowUtc);

  @override
  DateTime nowUtc;

  void advance(Duration duration) => nowUtc = nowUtc.add(duration);
}
