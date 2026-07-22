import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/solver_report.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';

/// Modal dialog that shows a progress phase while [solverFuture] runs,
/// then replaces its content with the solver report (deduction counts,
/// verdict, OK button).
///
/// The dialog is never barrier-dismissible (`barrierDismissible: false`).
/// During the progress phase a *Cancel* button is shown that invokes
/// [onCancel] and pops the dialog with `null`.  Once the report is ready
/// a single *OK* button returns the [SolverReport].
/// If [solverFuture] fails, the dialog pops with `null`.
///
/// When [webMode] is true, the dialog initially shows an explanatory
/// message and a *Launch* button instead of the spinner. The computation
/// only starts once the user taps *Launch*.
Future<SolverReport?> showSolverReportDialog(
  BuildContext context, {
  required Future<SolverReport> solverFuture,
  VoidCallback? onCancel,
  bool webMode = false,
}) {
  return showDialog<SolverReport>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SolverReportDialogBody(
      solverFuture: solverFuture,
      onCancel: onCancel,
      webMode: webMode,
    ),
  );
}

class _SolverReportDialogBody extends StatefulWidget {
  final Future<SolverReport> solverFuture;
  final VoidCallback? onCancel;
  final bool webMode;
  const _SolverReportDialogBody({
    required this.solverFuture,
    this.onCancel,
    this.webMode = false,
  });

  @override
  State<_SolverReportDialogBody> createState() =>
      _SolverReportDialogBodyState();
}

class _SolverReportDialogBodyState extends State<_SolverReportDialogBody> {
  SolverReport? _report;
  bool _webLaunched = false;

  @override
  void initState() {
    super.initState();
    if (!widget.webMode) _startListening();
  }

  void _startListening() {
    widget.solverFuture.then(
      (report) {
        if (mounted) setState(() => _report = report);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[editor] solver report failed: $error');
        if (mounted) Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    // Web mode, not yet launched: show explanation + launch button.
    if (widget.webMode && !_webLaunched) {
      return AlertDialog(
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text(loc.createSolverWebExplanation),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _webLaunched = true);
              _startListening();
            },
            child: Text(loc.createSolverWebLaunch),
          ),
        ],
      );
    }

    // Waiting for the solver (spinner + cancel).
    if (_report == null) {
      return AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(loc.createSolverChecking),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.onCancel?.call();
              Navigator.pop(context);
            },
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
        ],
      );
    }

    // Report ready.
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
    if (report.aborted) {
      return Row(
        children: [
          const Icon(Icons.timer_off, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loc.createSolverTimedOut(
                report.deducedCount.toString(),
                report.totalFreeCells.toString(),
              ),
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
