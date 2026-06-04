import 'package:flutter/services.dart';

class InputSanitizer {
  const InputSanitizer._();

  static const String invalidInputMessage = 'Invalid characters detected.';

  static final RegExp _htmlTagPattern = RegExp(
    r'<[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _scriptSchemePattern = RegExp(
    r'\b(?:javascript|vbscript|data)\s*:',
    caseSensitive: false,
  );
  static final RegExp _sqlKeywordPattern = RegExp(
    r'\b(?:select|insert|update|delete|drop|alter|truncate|union|exec|execute|grant|revoke)\b',
    caseSensitive: false,
  );
  static final RegExp _sqlCommentPattern = RegExp(r'(--|/\*|\*/|;)');
  static final RegExp _controlCharsPattern = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',
  );
  static final RegExp _unsafeTypedCharsPattern = RegExp(r'[<>;]');
  static final RegExp _namePattern = RegExp(r"^[A-Za-z][A-Za-z .'-]{0,49}$");
  static final RegExp _shortTextPattern = RegExp(
    r"^[A-Za-z0-9][A-Za-z0-9 .,'()&/\-]{0,79}$",
  );
  static final RegExp _longTextPattern = RegExp(
    r"^[A-Za-z0-9][A-Za-z0-9\s.,'()&/\-:!?%+#]{0,799}$",
    multiLine: true,
  );

  static String _normalizeText(String value) {
    final collapsed = value
        .replaceAll(_controlCharsPattern, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return collapsed;
  }

  static String cleanText(String value, {int maxLength = 500}) {
    final collapsed = _normalizeText(value)
        .replaceAll(_htmlTagPattern, '')
        .replaceAll(_scriptSchemePattern, '')
        .replaceAll(_sqlKeywordPattern, '')
        .replaceAll(_sqlCommentPattern, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (collapsed.length <= maxLength) {
      return collapsed;
    }
    return collapsed.substring(0, maxLength).trim();
  }

  static String? validateName(String? value, {bool required = true}) {
    return _validate(
      value,
      required: required,
      minLength: 1,
      maxLength: 50,
      allowedPattern: _namePattern,
    );
  }

  static String? validateShortText(
    String? value, {
    bool required = true,
    int minLength = 1,
    int maxLength = 80,
  }) {
    return _validate(
      value,
      required: required,
      minLength: minLength,
      maxLength: maxLength,
      allowedPattern: _shortTextPattern,
    );
  }

  static String? validateLongText(
    String? value, {
    bool required = true,
    int minLength = 1,
    int maxLength = 800,
  }) {
    return _validate(
      value,
      required: required,
      minLength: minLength,
      maxLength: maxLength,
      allowedPattern: _longTextPattern,
    );
  }

  static String? _validate(
    String? value, {
    required bool required,
    required int minLength,
    required int maxLength,
    required RegExp allowedPattern,
  }) {
    final text = _normalizeText(value ?? '');
    if (text.isEmpty) {
      return required ? 'This field is required.' : null;
    }
    if (text.length < minLength) {
      return 'Please enter at least $minLength characters.';
    }
    if (text.length > maxLength) {
      return 'Please enter $maxLength characters or fewer.';
    }
    if (_looksMalicious(text) || !allowedPattern.hasMatch(text)) {
      return invalidInputMessage;
    }
    return null;
  }

  static bool _looksMalicious(String value) {
    return _htmlTagPattern.hasMatch(value) ||
        _scriptSchemePattern.hasMatch(value) ||
        _sqlKeywordPattern.hasMatch(value) ||
        _sqlCommentPattern.hasMatch(value);
  }
}

class SanitizingTextInputFormatter extends TextInputFormatter {
  const SanitizingTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sanitized = newValue.text
        .replaceAll(InputSanitizer._controlCharsPattern, '')
        .replaceAll(InputSanitizer._unsafeTypedCharsPattern, '')
        .replaceAll('--', '')
        .replaceAll('/*', '')
        .replaceAll('*/', '');

    if (sanitized == newValue.text) {
      return newValue;
    }

    return TextEditingValue(
      text: sanitized,
      selection: TextSelection.collapsed(offset: sanitized.length),
    );
  }
}
