# getsomepuzzle — Task Completion

After any coding task, run these in order:

```bash
dart format .
flutter analyze
flutter test
```

All three must pass clean. `flutter analyze` must have zero issues. `flutter test` must be fully green.

If `dart format` changes files, re-run `flutter analyze` and `flutter test`.

## Additional verification per domain

- **Constraints**: if you modified a constraint, also verify its paired regression tests exist (reachable-incomplete → verify true, unreachable-incomplete → verify false). See `test/constraints_test.dart`.
- **ARB changes**: run `flutter gen-l10n` before the above three.
- **Launcher icons**: run `dart run flutter_launcher_icons` if you changed the source icon.
