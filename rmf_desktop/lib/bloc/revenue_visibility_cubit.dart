import 'package:flutter_bloc/flutter_bloc.dart';

/// Whether the dashboard's revenue figures are on show — true by default.
///
/// One switch for every figure, so hiding the month's takings from somebody
/// looking over the counter also hides the same number in the greeting and
/// today's figure beside it. Held in memory above MaterialApp: it survives
/// moving between screens and the inactivity lock, and a fresh start of the
/// app shows the figures again. It changes nothing but what is painted.
class RevenueVisibilityCubit extends Cubit<bool> {
  RevenueVisibilityCubit() : super(true);

  void toggle() => emit(!state);
}
