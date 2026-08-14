import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/payments_bloc.dart';
import '../../data/database.dart';
import '../../data/payment_repository.dart';
import '../../domain/money.dart';
import '../../theme/app_theme.dart';
import 'payment_history_table.dart';

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => PaymentsBloc(context.read<PaymentRepository>())
        ..add(const PaymentsRequested()),
      child: const _PaymentsView(),
    );
  }
}

class _PaymentsView extends StatefulWidget {
  const _PaymentsView();

  @override
  State<_PaymentsView> createState() => _PaymentsViewState();
}

class _PaymentsViewState extends State<_PaymentsView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() => context
      .read<PaymentsBloc>()
      .add(PaymentsSearchSubmitted(_searchController.text));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: BlocBuilder<PaymentsBloc, PaymentsState>(
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payments',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.palette.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${state.rows.length} shown · '
                    '${formatMinorUnits(state.totalMinor)} total',
                    style: mutedStyleOf(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search member, phone, or receipt…',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<PaymentMethod?>(
                      initialValue: state.method,
                      isDense: true,
                      decoration: const InputDecoration(isDense: true),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('All methods')),
                        ...PaymentMethod.values.map((m) => DropdownMenuItem(
                            value: m, child: Text(paymentMethodLabel(m)))),
                      ],
                      onChanged: (v) => context
                          .read<PaymentsBloc>()
                          .add(PaymentsMethodChanged(v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                      onPressed: _search, child: const Text('Filter')),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: state.status == PaymentsStatus.loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: PaymentHistoryTable(
                          rows: state.rows,
                          emptyMessage: 'No payments match this view.',
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
