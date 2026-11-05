import 'dart:convert';

bool isValidEmail(String value) =>
    value.trim().length <= 254 &&
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

/// Mirrors the server's policy. Passwords are sent only to Supabase Auth over TLS.
bool isStrongPassword(String value) =>
    value.runes.length >= 12 &&
    utf8.encode(value).length <= 72 &&
    RegExp('[a-z]').hasMatch(value) &&
    RegExp('[A-Z]').hasMatch(value) &&
    RegExp('[0-9]').hasMatch(value) &&
    RegExp(r'[^a-zA-Z0-9\s]').hasMatch(value);
