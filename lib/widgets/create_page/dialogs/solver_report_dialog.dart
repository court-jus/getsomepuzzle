import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/solver_report.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';

/// Modal dialog that shows a progress phase while [solverFuture] runs,
/// then replaces its content with the solver report (deduction counts,
/// verdict, OK button).
///
/// The dialog is never barrier-dismissible (`barrierDismissible: false`)
/// and has no close button: the only way out is the single *OK* button
/// shown once the report is ready, which pops the dialog and returns
/// the [SolverReport]. If [solverFuture] fails, the dialog pops with
/// `null`.
Future<SolverReport?> showSolverReportDialog(
  BuildContext context, {
  required Future<SolverReport> solverFuture,
}) {
  return showDialog<SolverReport>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SolverReportDialogBody(solverFuture: solverFuture),
  );
}

class _SolverReportDialogBody extends StatefulWidget {
  final Future<SolverReport> solverFuture;
  const _SolverReportDialogBody({required this.solverFuture});

  @override
  State<_SolverReportDialogBody> createState() =>
      _SolverReportDialogBodyState();
}

class _SolverReportDialogBodyState extends State<_SolverReportDialogBody> {
  SolverReport? _report;

  @override
  void initState() {
    super.initState();
    widget.solverFuture.then(
      (report) {
        if (mounted) setState(() => _report = report);
      },
      onError: (Object error, StackTrace stackTrace) {
        // Without this the dialog would sit on the spinner forever.
        debugPrint('[editor] solver report failed: $error');
        if (mounted) Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    if (_report == null) {
      return AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(loc.createSolverChecking),
          ],
        ),
      );
    }

    final report = _report!;
    return AlertDialog(
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(report, loc),
            const SizedBox(height: 16),
            _buildDeductionCounts(report, loc),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, report),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }

  Widget _buildHeader(SolverReport report, AppLocalizations loc) {
    if (report.impossibleBy != null) {
      return Row(
        children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loc.createSolverContradiction(report.impossibleBy!),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    }
    if (!report.solved) {
      return Row(
        children: [
          const Icon(Icons.warning, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loc.createSolverIncomplete,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(Icons.check_circle, color: Colors.green),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _solvedLabel(report, loc),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildDeductionCounts(SolverReport report, AppLocalizations loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.createSolverDeducible(
            report.deducedCount.toString(),
            report.totalFreeCells.toString(),
          ),
        ),
        if (report.bruteForceCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              loc.createSolverBruteForce(report.bruteForceCount.toString()),
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }

  String _solvedLabel(SolverReport report, AppLocalizations loc) {
    final level = classifyTrace(
      steps: report.steps,
      solved: true,
      prefillRatio: 0,
      maxPrefill: 1.0,
    );
    final collectionKey = levelToPlayableCollectionKey[level];
    final labels = CollectionLabels.fromLocalizations(loc);
    final collectionLabel = collectionKey != null
        ? labels.labelFor(collectionKey)
        : null;
    return loc.createSolverValid(collectionLabel ?? '?');
  }
}
