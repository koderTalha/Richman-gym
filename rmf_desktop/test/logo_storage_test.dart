import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/services/logo_storage.dart';

/// The logo is the one file the owner can put into this app from outside it, so
/// what it refuses matters as much as what it accepts.
void main() {
  Uint8List bytesOf(List<int> values) => Uint8List.fromList(values);

  final png = bytesOf([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);
  final jpeg = bytesOf([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
  final gif = bytesOf([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 2]);
  final webp = bytesOf([
    0x52, 0x49, 0x46, 0x46, // RIFF
    0x00, 0x00, 0x00, 0x00, // size
    0x57, 0x45, 0x42, 0x50, // WEBP
    1, 2, 3,
  ]);

  group('accepts the raster formats a receipt can draw', () {
    test('PNG', () => expect(LogoStorage.validate(png), 'png'));
    test('JPEG', () => expect(LogoStorage.validate(jpeg), 'jpg'));
    test('GIF', () => expect(LogoStorage.validate(gif), 'gif'));
    test('WebP', () => expect(LogoStorage.validate(webp), 'webp'));
  });

  group('refuses what it should', () {
    test('an SVG, however it is named', () {
      // The security case from the brief: an SVG can carry script and external
      // references, and nothing here can safely render one.
      final svg = bytesOf('<svg xmlns="http://www.w3.org/2000/svg"><script>'
              'alert(1)</script></svg>'
          .codeUnits);

      expect(
        () => LogoStorage.validate(svg),
        throwsA(isA<LogoRejected>().having(
          (e) => e.message,
          'message',
          contains('SVG'),
        )),
      );
    });

    test('an SVG renamed to .png — the extension is never trusted', () {
      // validate() takes bytes, not a filename, precisely so this cannot work.
      final disguised = bytesOf('<?xml version="1.0"?><svg/>'.codeUnits);
      expect(() => LogoStorage.validate(disguised), throwsA(isA<LogoRejected>()));
    });

    test('an HTML file', () {
      final html = bytesOf('<!DOCTYPE html><html></html>'.codeUnits);
      expect(() => LogoStorage.validate(html), throwsA(isA<LogoRejected>()));
    });

    test('an executable', () {
      // MZ header — a Windows .exe renamed to logo.png.
      final exe = bytesOf([0x4D, 0x5A, 0x90, 0x00, 1, 2, 3]);
      expect(() => LogoStorage.validate(exe), throwsA(isA<LogoRejected>()));
    });

    test('a WAV, which shares the RIFF header with WebP', () {
      final wav = bytesOf([
        0x52, 0x49, 0x46, 0x46,
        0x00, 0x00, 0x00, 0x00,
        0x57, 0x41, 0x56, 0x45, // WAVE, not WEBP
        1, 2, 3,
      ]);
      expect(() => LogoStorage.validate(wav), throwsA(isA<LogoRejected>()));
    });

    test('an empty file', () {
      expect(() => LogoStorage.validate(bytesOf([])),
          throwsA(isA<LogoRejected>()));
    });

    test('anything over 2MB', () {
      final huge = Uint8List(LogoStorage.maxBytes + 1);
      // A valid PNG header on an oversized file: the size check must not be
      // skippable by looking like an image.
      huge.setRange(0, 8, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

      expect(
        () => LogoStorage.validate(huge),
        throwsA(isA<LogoRejected>().having(
          (e) => e.message,
          'message',
          contains('2MB'),
        )),
      );
    });

    test('a file just under the limit is still fine', () {
      final big = Uint8List(LogoStorage.maxBytes - 1);
      big.setRange(0, 8, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(LogoStorage.validate(big), 'png');
    });
  });

  group('photographs get a larger allowance than logos', () {
    /// An oversized but otherwise valid PNG.
    Uint8List pngOf(int size) {
      final bytes = Uint8List(size);
      bytes.setRange(0, 8, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      return bytes;
    }

    test('a photo off a phone is too big to be a logo but fine as a photo', () {
      // The case this split exists for: 4MB is a perfectly ordinary camera
      // photo, and the logo ceiling would reject every one of them.
      final photo = pngOf(4 * 1024 * 1024);

      expect(() => LogoStorage.validate(photo), throwsA(isA<LogoRejected>()));
      expect(LogoStorage.validate(photo, kind: ImageKind.photo), 'png');
    });

    test('a photo over its own ceiling is still refused', () {
      final enormous = pngOf(ImageKind.photo.maxBytes + 1);

      expect(
        () => LogoStorage.validate(enormous, kind: ImageKind.photo),
        throwsA(isA<LogoRejected>().having(
          (e) => e.message,
          'message',
          // The message must quote the ceiling that actually applied, not the
          // logo's.
          contains(ImageKind.photo.limitLabel),
        )),
      );
    });

    test('the format rules do not relax for photographs', () {
      // A larger allowance is about size only: an SVG is refused whatever it
      // is going to be used for.
      final svg = bytesOf('<svg xmlns="http://www.w3.org/2000/svg"/>'.codeUnits);

      expect(
        () => LogoStorage.validate(svg, kind: ImageKind.photo),
        throwsA(isA<LogoRejected>()),
      );
    });

    test('each kind names its own ceiling in the message', () {
      expect(ImageKind.logo.limitLabel, '2MB');
      expect(ImageKind.photo.limitLabel, '8MB');
      // The label is what the owner is told; it must describe the number the
      // check actually uses.
      expect(ImageKind.logo.maxBytes, 2 * 1024 * 1024);
      expect(ImageKind.photo.maxBytes, 8 * 1024 * 1024);
    });
  });

  group('on disk', () {
    late Directory workspace;
    late LogoStorage storage;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('rmf-logo');
      storage = LogoStorage(root: workspace);
    });

    tearDown(() async {
      if (await workspace.exists()) await workspace.delete(recursive: true);
    });

    test('saves inside the branding directory', () async {
      final path = await storage.save(png);

      expect(p.isWithin(workspace.path, path), isTrue);
      expect(await File(path).readAsBytes(), png);
      expect(p.extension(path), '.png');
    });

    test('a replacement gets a new name so the image cache cannot win',
        () async {
      final first = await storage.save(png);
      final second = await storage.save(jpeg, replacing: first);

      expect(second, isNot(first),
          reason: 'reusing one filename leaves the old mark on screen');
      expect(await File(first).exists(), isFalse,
          reason: 'the replaced file is cleaned up');
      expect(await File(second).exists(), isTrue);
    });

    test('a rejected replacement leaves the existing logo alone', () async {
      final first = await storage.save(png);

      await expectLater(
        storage.save(bytesOf('<svg/>'.codeUnits), replacing: first),
        throwsA(isA<LogoRejected>()),
      );

      expect(await File(first).exists(), isTrue,
          reason: 'a bad upload must not cost the gym the logo it had');
    });

    test('reads back what it wrote', () async {
      final path = await storage.save(png);
      expect(await LogoStorage.read(path), png);
    });

    test('reads null for a missing file rather than throwing', () async {
      // The receipt renderer and the sidebar both call this; neither may fail
      // because a logo file was deleted or a database came from another
      // machine.
      expect(await LogoStorage.read(p.join(workspace.path, 'gone.png')),
          isNull);
      expect(await LogoStorage.read(null), isNull);
    });

    test('reads null when the file has been swapped for something unsafe',
        () async {
      final path = await storage.save(png);
      await File(path).writeAsBytes(bytesOf('<svg/>'.codeUnits));

      expect(await LogoStorage.read(path), isNull,
          reason: 'bytes are re-validated on read, not trusted once');
    });

    test('removing deletes our file', () async {
      final path = await storage.save(png);
      await storage.remove(path);
      expect(await File(path).exists(), isFalse);
    });

    test('removing never touches a file outside the branding directory',
        () async {
      // A hand-edited logo_path must not turn "Remove logo" into a delete of
      // whatever it names.
      final outsider = File(p.join(workspace.parent.path, 'rmf-not-ours.png'));
      await outsider.writeAsBytes(png);
      addTearDown(() async {
        if (await outsider.exists()) await outsider.delete();
      });

      await storage.remove(outsider.path);

      expect(await outsider.exists(), isTrue,
          reason: 'only files this class wrote are deleted');
    });

    test('a photo and a logo can live side by side', () async {
      // Both kinds share one branding directory, and all three paths are held
      // in the same settings row: saving one must never overwrite another.
      final photos = LogoStorage(root: workspace, kind: ImageKind.photo);

      final logo = await storage.save(png);
      final login = await photos.save(jpeg);
      final dashboard = await photos.save(webp);

      expect({logo, login, dashboard}, hasLength(3),
          reason: 'three uploads, three distinct files');
      for (final path in [logo, login, dashboard]) {
        expect(await File(path).exists(), isTrue);
      }
      expect(p.basename(logo), startsWith('logo-'));
      expect(p.basename(login), startsWith('photo-'));
    });

    test('replacing a photo does not disturb the logo', () async {
      final photos = LogoStorage(root: workspace, kind: ImageKind.photo);

      final logo = await storage.save(png);
      final first = await photos.save(jpeg);
      final second = await photos.save(webp, replacing: first);

      expect(await File(first).exists(), isFalse,
          reason: 'the photo it replaced is cleaned up');
      expect(await File(second).exists(), isTrue);
      expect(await File(logo).exists(), isTrue,
          reason: 'the logo is a different file and is left alone');
    });
  });
}
