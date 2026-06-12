class DrillSessionController {
  int _sessionId = 0;
  bool _isStarting = false;
  bool _isFinishing = false;
  bool _isGlobalFinishing = false;

  int get currentSession => _sessionId;
  bool get isStarting => _isStarting;
  bool get isFinishing => _isFinishing;
  bool get isGlobalFinishing => _isGlobalFinishing;

  bool beginStartGuard() {
    if (_isStarting) return false;
    _isStarting = true;
    return true;
  }

  void endStartGuard() {
    _isStarting = false;
  }

  int startNewSession() {
    _sessionId++;
    _isFinishing = false;
    return _sessionId;
  }

  void invalidateSession() {
    _sessionId++;
  }

  bool isCurrent(int session) => session == _sessionId;

  bool beginFinish({int? session}) {
    if (session != null && session != _sessionId) return false;
    if (_isGlobalFinishing) return false;

    _isFinishing = true;
    _isGlobalFinishing = true;
    return true;
  }

  void endFinish() {
    _isFinishing = false;
    _isGlobalFinishing = false;
  }
}
