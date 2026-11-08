import 'dart:convert';

bool isValidEmail(String value) =>
    value.trim().length <= 254 &&
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

/// Mirrors the server's policy. Passwords are sent only to Supabase Auth over TLS.
bool isStrongPassword(String value) =>
    value.runes.length >= 8 && utf8.encode(value).length <= 72;
