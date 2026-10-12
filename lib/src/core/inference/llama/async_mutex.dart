import 'dart:async';

/// Serialises access to the single native llama context.
class AsyncMutex {
  Future<void> _tail = Future.value();

  /// Waits for the lock and returns the function that releases it.
  Future<void Function()> acquire() {
    final previous = _tail;
    final next = Completer<void>();
    _tail = next.future;
    return previous.then((_) => next.complete);
  }
}
