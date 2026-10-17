import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/branding_cubit.dart';
import '../../services/logo_storage.dart';
import '../../theme/app_theme.dart';
import '../../theme/branding_config.dart';

/// Which hero slot a row of this card edits.
///
/// The two slots behave identically — pick a file, validate it, copy it in,
/// save the path — and differ only in which field of [BrandingConfig] they
/// write and what the owner is told the picture is for. Holding that difference
/// as data means the row below is written once instead of twice.
enum _PhotoTarget {
  login(
    title: 'Sign-in screen',
    description:
        'Fills the panel beside the sign-in form. This is the screen anyone '
        'walking past the front desk can see, so pick something you are happy '
        'to have on display.',
  ),
  dashboard(
    title: 'Dashboard banner',
    description:
        'Sits behind the greeting at the top of your dashboard. Only you see '
        'this one.',
  );

  const _PhotoTarget({required this.title, required this.description});

  final String title;
  final String description;

  String? pathIn(BrandingConfig config) => switch (this) {
        _PhotoTarget.login => config.loginPhotoPath,
        _PhotoTarget.dashboard => config.dashboardPhotoPath,
      };

  BrandingConfig withPath(BrandingConfig config, String path) =>
      switch (this) {
        _PhotoTarget.login => config.copyWith(loginPhotoPath: path),
        _PhotoTarget.dashboard => config.copyWith(dashboardPhotoPath: path),
      };

  BrandingConfig cleared(BrandingConfig config) => switch (this) {
        _PhotoTarget.login => config.copyWith(clearLoginPhoto: true),
        _PhotoTarget.dashboard => config.copyWith(clearDashboardPhoto: true),
      };
}

/// Choose the gym's own photographs for the sign-in panel and the dashboard
/// banner.
///
/// Saves immediately rather than through the preview bar, for the same reason
/// the logo does: the picture is a file that has to be written to disk before
/// anything can show it, so "previewing" one would mean saving it anyway.
class GymPhotosCard extends StatelessWidget {
  const GymPhotosCard({super.key, required this.state});

  final BrandingState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final target in _PhotoTarget.values) ...[
          if (target != _PhotoTarget.values.first) ...[
            const SizedBox(height: 20),
            Divider(height: 1, color: context.palette.border),
            const SizedBox(height: 20),
          ],
          _PhotoRow(state: state, target: target),
        ],
      ],
    );
  }
}

class _PhotoRow extends StatefulWidget {
  const _PhotoRow({required this.state, required this.target});

  final BrandingState state;
  final _PhotoTarget target;

  @override
  State<_PhotoRow> createState() => _PhotoRowState();
}

class _PhotoRowState extends State<_PhotoRow> {
  /// Photographs are larger than logos, so this storage is told what it is
  /// holding — see [ImageKind].
  final _storage = LogoStorage(kind: ImageKind.photo);
  bool _busy = false;

  Future<void> _pick() async {
    const typeGroup = XTypeGroup(
      label: 'Photo',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
    );

    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<BrandingCubit>();
    final target = widget.target;

    try {
      final bytes = await file.readAsBytes();
      final path = await _storage.save(
        bytes,
        replacing: target.pathIn(widget.state.saved),
      );
      final saved =
          await cubit.applyNow(target.withPath(widget.state.draft, path));
      messenger.showSnackBar(SnackBar(
        content: Text(saved
            ? 'Photo updated'
            : 'Could not save the photo. See the Logs screen.'),
      ));
    } on LogoRejected catch (e) {
      // The owner's mistake, told plainly: wrong format, too big, empty.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not read that image.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<BrandingCubit>();
    final target = widget.target;
    final previous = target.pathIn(widget.state.saved);

    final saved = await cubit.applyNow(target.cleared(widget.state.draft));
    // The file goes only after the database has forgotten it, so a failed write
    // cannot leave a path pointing at nothing.
    if (saved) await _storage.remove(previous);

    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(saved
          ? 'Photo removed'
          : 'Could not remove the photo. See the Logs screen.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final target = widget.target;
    final path = target.pathIn(widget.state.draft);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PhotoPreview(path: path),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                target.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                target.description,
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
              const SizedBox(height: 6),
              Text(
                'PNG, JPEG, GIF or WebP, up to ${ImageKind.photo.limitLabel}. '
                'A wide picture shot on a dark background works best — the '
                'photo is dimmed so the writing over it stays readable.',
                style: TextStyle(fontSize: 12, color: palette.textHint),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: Text(path == null ? 'Choose photo' : 'Replace'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.accentText,
                      side: BorderSide(color: palette.accent),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  if (path != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _busy ? null : _remove,
                      style: TextButton.styleFrom(
                          foregroundColor: palette.textSecondary),
                      child: const Text('Remove'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The photograph at roughly the proportions of the band it will fill.
class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final photoPath = path;

    return Container(
      width: 164,
      height: 92,
      decoration: BoxDecoration(
        color: palette.surfaceBase,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: photoPath == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_outlined, size: 22, color: palette.textHint),
                const SizedBox(height: 6),
                Text(
                  'No photo',
                  style: TextStyle(fontSize: 11, color: palette.textHint),
                ),
              ],
            )
          // cover, unlike the logo: a photograph is meant to fill its band, and
          // this preview should show the owner the crop they will actually get.
          : Image.file(
              File(photoPath),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Icon(
                Icons.broken_image_outlined,
                size: 22,
                color: palette.textHint,
              ),
            ),
    );
  }
}
