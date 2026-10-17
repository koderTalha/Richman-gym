import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/app_theme.dart';

/// One editable form's unsaved state, as the save bar sees it.
///
/// A card registers one of these when its fields differ from what is stored,
/// and withdraws it when they match again. Holding [save] and [discard] here —
/// rather than having the bar know about gym details, WhatsApp credentials and
/// reminder schedules — is what lets one bar serve every form without knowing
/// what any of them contain.
@immutable
class UnsavedForm {
  const UnsavedForm({
    required this.save,
    required this.discard,
    this.canSave = true,
  });

  /// Commits the draft. Usually dispatches the card's own bloc event.
  final VoidCallback save;

  /// Puts the fields back to what is stored.
  final VoidCallback discard;

  /// False while the draft is incomplete or invalid, which greys out Save
  /// without hiding the bar — the owner still needs to be told there is
  /// something unsaved, and that it cannot be saved as it stands.
  final bool canSave;
}

/// Tracks which settings forms have unsaved edits.
///
/// The handoff replaces per-section save buttons with a single bar that
/// appears when anything differs from what is stored. That only works if the
/// bar can see every form at once, so the forms report to this and the bar
/// reads it.
class UnsavedChanges extends ChangeNotifier {
  final _forms = <Object, UnsavedForm>{};

  /// Records that [owner]'s form has unsaved edits, or clears it when [form]
  /// is null.
  ///
  /// Keyed by owner so a card can call this freely on every keystroke: the
  /// last word from a given form replaces its previous one rather than
  /// stacking up.
  void report(Object owner, UnsavedForm? form) {
    final existing = _forms[owner];
    if (form == null) {
      if (existing == null) return;
      _forms.remove(owner);
    } else {
      if (existing != null && existing.canSave == form.canSave) {
        // Same shape as last time: keep the newer callbacks, which close over
        // the current field values, but do not rebuild the bar for a keystroke
        // that changed nothing it displays.
        _forms[owner] = form;
        return;
      }
      _forms[owner] = form;
    }
    notifyListeners();
  }

  /// Forgets [owner] entirely, for a card being disposed.
  void withdraw(Object owner) => report(owner, null);

  bool get isDirty => _forms.isNotEmpty;

  /// True only when every outstanding form could be saved as it stands.
  bool get canSaveAll =>
      _forms.isNotEmpty && _forms.values.every((f) => f.canSave);

  /// How many forms are waiting. Shown when it is more than one, so "Save
  /// changes" does not quietly write a tab the owner has forgotten about.
  int get count => _forms.length;

  void saveAll() {
    // Over a copy: a save triggers a rebuild that re-reports the forms.
    for (final form in _forms.values.toList()) {
      form.save();
    }
  }

  void discardAll() {
    for (final form in _forms.values.toList()) {
      form.discard();
    }
    _forms.clear();
    notifyListeners();
  }
}

/// Hands the [UnsavedChanges] for this screen down to the cards inside it.
class UnsavedChangesScope extends InheritedWidget {
  const UnsavedChangesScope({
    super.key,
    required this.changes,
    required super.child,
  });

  final UnsavedChanges changes;

  static UnsavedChanges? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<UnsavedChangesScope>()
      ?.changes;

  @override
  bool updateShouldNotify(UnsavedChangesScope old) => changes != old.changes;
}

/// What a settings form mixes in to report itself to the save bar.
///
/// The form says what its fields are, whether they differ from what is
/// stored, and how to save or put them back; this does the bookkeeping — it
/// listens to the fields, re-checks when the stored values change underneath
/// (as they do after a save), and withdraws the form when it is disposed.
mixin ReportsUnsavedChanges<T extends StatefulWidget> on State<T> {
  UnsavedChanges? _changes;

  /// The fields whose edits should be noticed.
  List<Listenable> get watchedFields;

  /// True when what is on screen differs from what is stored.
  bool get isDirty;

  /// False while the edits could not be saved as they stand.
  bool get canSave => true;

  /// Commits the edits.
  void save();

  /// Puts every field back to its stored value.
  void discard();

  @override
  void initState() {
    super.initState();
    for (final field in watchedFields) {
      field.addListener(reportUnsaved);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final changes = UnsavedChangesScope.maybeOf(context);
    if (!identical(changes, _changes)) {
      _changes?.withdraw(this);
      _changes = changes;
      reportUnsaved();
    }
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The stored values arrive through the widget, so a save that succeeded
    // shows up here as "nothing differs any more" and takes the bar away.
    reportUnsaved();
  }

  @override
  void dispose() {
    for (final field in watchedFields) {
      field.removeListener(reportUnsaved);
    }
    _changes?.withdraw(this);
    super.dispose();
  }

  /// Re-checks the form and tells the bar. Call it after changing anything
  /// that is not one of [watchedFields] — a switch or a dropdown held in state.
  void reportUnsaved() {
    final changes = _changes;
    if (changes == null) return;

    void send() => changes.report(
          this,
          isDirty
              ? UnsavedForm(save: save, discard: discard, canSave: canSave)
              : null,
        );

    // Reporting notifies the bar, which may itself be building when this runs
    // from didUpdateWidget. Deferring to after the frame keeps that legal.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) send();
      });
    } else {
      send();
    }
  }
}

/// The floating bar at the bottom of Settings: "You have unsaved changes".
///
/// Pops in when any form on the screen differs from what is stored, and takes
/// the place of the save button each card used to carry.
class UnsavedChangesBar extends StatelessWidget {
  const UnsavedChangesBar({super.key, required this.changes});

  final UnsavedChanges changes;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ListenableBuilder(
      listenable: changes,
      builder: (context, _) {
        return AnimatedSlide(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          offset: changes.isDirty ? Offset.zero : const Offset(0, 1.6),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: changes.isDirty ? 1 : 0,
            // Not just invisible: a hidden bar must not swallow clicks meant
            // for the card underneath it.
            child: IgnorePointer(
              ignoring: !changes.isDirty,
              child: Container(
                margin: const EdgeInsets.fromLTRB(32, 0, 32, 20),
                padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.borderStrong),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: palette.due,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        changes.count > 1
                            ? 'You have unsaved changes in '
                                '${changes.count} sections'
                            : 'You have unsaved changes',
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: changes.discardAll,
                      style: TextButton.styleFrom(
                        foregroundColor: palette.textSecondary,
                      ),
                      child: const Text('Discard'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: changes.canSaveAll ? changes.saveAll : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.accentText,
                        side: BorderSide(color: palette.accent),
                        backgroundColor:
                            palette.accent.withValues(alpha: 0.14),
                      ),
                      child: const Text('Save changes'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
