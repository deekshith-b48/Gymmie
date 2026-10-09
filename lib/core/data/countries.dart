/// Dial codes offered on phone inputs (the original app fetches `/v5/masters/country/phone-code`;
/// a bundled copy keeps sign-in usable before the first network call).
class Country {
  const Country(this.code, this.name, this.dial);
  final String code;
  final String name;
  final String dial;
}

const countries = <Country>[
  Country('IN', 'India', '+91'),
  Country('AE', 'United Arab Emirates', '+971'),
  Country('US', 'United States', '+1'),
  Country('GB', 'United Kingdom', '+44'),
  Country('SG', 'Singapore', '+65'),
  Country('AU', 'Australia', '+61'),
  Country('NP', 'Nepal', '+977'),
  Country('LK', 'Sri Lanka', '+94'),
  Country('BD', 'Bangladesh', '+880'),
];

/// Normalises user input to E.164 using [dial] when no country code was typed.
String toE164(String input, {String dial = '+91'}) {
  var s = input.trim().replaceAll(RegExp(r'[\s\-()]'), '');
  if (s.startsWith('00')) s = '+${s.substring(2)}';
  if (!s.startsWith('+')) s = dial + s.replaceFirst(RegExp(r'^0+'), '');
  return s;
}
