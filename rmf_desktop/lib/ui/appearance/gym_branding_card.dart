import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/branding_cubit.dart';
import '../../services/logo_storage.dart';
import '../../theme/app_theme.dart';

/// Upload, preview and replace the gym logo.
///
/// Saves immediately rather than through the preview bar: a logo is a file on
/// disk, and "previewing" one the owner has not kept would mean writing it
/// anyway. The upload is validated by [LogoStorage] before it is written.
class GymBrandingCard extends StatefulWidget {
  const GymBrandingCard({super.key, required this.state});

  final BrandingState state;

  @override
  State<GymBrandingCard> createState() => _GymBrandingCardState();
}

class _GymBrandingCardState extends State<GymBrandingCard> {
  final _storage = LogoStorage();
  bool _busy = false;

  Future<void> _pick() async {
    // Deliberately no SVG in the accepted types: it is refused on content too,
    // so offering it in the dialog would only invite a rejection.
    const typeGroup = XTypeGroup(
      label: 'Logo image',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
    );

    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<BrandingCubit>();

    try {
      final bytes = await file.readAsBytes();
      final path = await _storage.save(
        bytes,
        replacing: widget.state.saved.logoPath,
      );
      final saved = await cubit.applyNow(
        widget.state.draft.copyWith(logoPath: path),
      );
      messenger.showSnackBar(SnackBar(
        content: Text(saved
            ? 'Logo updated'
            : 'Could not save the logo. See the Logs screen.'),
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
    final previous = widget.state.saved.logoPath;

    final saved = await cubit.applyNow(
      widget.state.draft.copyWith(clearLogo: true),
    );
    // The file goes only after the database has forgotten it, so a failed write
    // cannot leave a path pointing at nothing.
    if (saved) await _storage.remove(previous);

    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(saved
          ? 'Logo removed'
          : 'Could not remove the logo. See the Logs screen.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final logoPath = widget.state.draft.logoPath;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LogoPreview(path: logoPath),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                logoPath == null ? 'No logo set' : 'Logo set',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'PNG, JPEG, GIF or WebP, up to 2MB. The logo keeps its '
                'proportions — it is never stretched. SVG files are not '
                'supported.',
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.upload_outlined, size: 16),
                    label: Text(logoPath == null ? 'Upload logo' : 'Replace'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.accentText,
                      side: BorderSide(color: palette.accent),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  if (logoPath != null) ...[
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

/// The logo as the sidebar will show it, or an empty frame.
class _LogoPreview extends StatelessWidget {
  const _LogoPreview({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: 132,
      height: 92,
      decoration: BoxDecoration(
        color: palette.surfaceBase,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.all(10),
      alignment: Alignment.center,
      child: path == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image_outlined,
                    size: 22, color: palette.textHint),
                const SizedBox(height: 6),
                Text(
                  'No logo',
                  style: TextStyle(fontSize: 11, color: palette.textHint),
                ),
              ],
            )
          // contain, never cover: the brief is explicit that the logo must keep
          // its aspect ratio and never stretch, and a gym's mark is usually
          // wider than it is tall.
          : Image.file(
              File(path!),
              fit: BoxFit.contain,
              // A file that has gone missing shows the empty state rather than
              // Flutter's grey broken-image box.
              errorBuilder: (context, error, stack) => Icon(
                Icons.broken_image_outlined,
                size: 22,
                color: palette.textHint,
              ),
            ),
    );
  }
}
