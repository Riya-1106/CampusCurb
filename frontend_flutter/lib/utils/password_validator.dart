class PasswordValidator {
  static const int _minLength = 8;

  static final RegExp _upper = RegExp(r'[A-Z]');
  static final RegExp _lower = RegExp(r'[a-z]');
  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _special = RegExp(r'[^A-Za-z0-9]');
  static final RegExp _space = RegExp(r'\s');

  static const String strongPasswordHint =
      'Use at least 8 characters with uppercase, lowercase, number, and special character.';

  static String? validateForLogin(String password) {
    if (password.isEmpty) {
      return 'Password is required.';
    }
    if (password.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  static String? validateForCreation(String password) {
    if (password.isEmpty) {
      return 'Password is required.';
    }
    if (password.length < _minLength) {
      return 'Password must be at least 8 characters.';
    }
    if (_space.hasMatch(password)) {
      return 'Password cannot contain spaces.';
    }
    if (!_upper.hasMatch(password)) {
      return 'Password must include at least one uppercase letter.';
    }
    if (!_lower.hasMatch(password)) {
      return 'Password must include at least one lowercase letter.';
    }
    if (!_digit.hasMatch(password)) {
      return 'Password must include at least one number.';
    }
    if (!_special.hasMatch(password)) {
      return 'Password must include at least one special character.';
    }
    return null;
  }
}
