import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/league.dart';
import '../providers/league_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import '../widgets/league_table.dart';

/// Full-screen La Liga table. Pass [data] to render a specific [LeagueData]
/// (e.g. a preview); otherwise it shows the live league from [leagueProvider].
class LeagueTableScreen extends ConsumerWidget {
  final LeagueData? data;
  final String title;

  const LeagueTableScreen({super.key, this.data, this.title = 'CLASIFICACIÓN'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        title: Text(title),
      ),
      body: data != null
          ? _body(data!)
          : ref
                .watch(leagueProvider)
                .when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.read(leagueProvider.notifier).refresh(),
                  ),
                  data: _body,
                ),
    );
  }

  Widget _body(LeagueData ld) => ListView(
    padding: const EdgeInsets.all(12),
    children: [LeagueTable(rows: ld.computeTable())],
  );
}
