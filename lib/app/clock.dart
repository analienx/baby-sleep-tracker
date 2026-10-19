/// Source of time injected into all domain calculations and actions.
/// No background process is required to preserve elapsed sleep duration.
abstract interface class Clock {
  DateTime get nowUtc;
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime get nowUtc => DateTime.now().toUtc();
}
