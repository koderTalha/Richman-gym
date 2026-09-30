/// The developer's public key for "Send to developer" — see
/// `diagnostics_crypto.dart`. Public by design: it can seal a bundle but not
/// open one. The private half lives only on the developer's machine, at
/// ~/.rich-man-fitness/diagnostics-private-key.
///
/// Written by `tool/diagnostics_keygen.dart`; regenerate it there rather than
/// editing it by hand.
const developerPublicKeyBase64 = 'eBzXaaKiG5Gn5JeoYZXx0Tj+gUH6je/J0XsWa1rFtGQ=';
