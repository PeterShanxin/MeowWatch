// Action archive cache for the self-hosted Windows runner.
//
// The runner deletes `_work\_actions` at the start of every job
// (`ActionManager.PrepareActionsAsync`), so its own per-action `.completed`
// watermark never survives and every job re-downloads `actions/checkout` from
// codeload.github.com — 194 of 194 recorded jobs on this host, zero cache hits.
// That download happens during job *initialization*, before any step exists, so
// nothing in a workflow can retry it: `timeout-minutes` doesn't apply, a retry
// loop in a `run:` block is never reached, and the runner simply fails the job
// with `Caught exception from JobExtension Initialization`. On 2026-07-12 a job
// here lost two of its three attempts over four minutes and scraped through on
// the third. See docs/AGENT_GUIDE.md → Self-hosted Windows runner, and #240.
//
// The runner's own escape hatch is `ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE`: a
// directory it consults before the network, laid out as
// `<cache>\<owner>_<repo>\<resolved-sha>.zip` on Windows.
//
//   dart run tool/action_cache.dart plan
//       Print what the cache should hold. Reads the workflows and resolves each
//       action through `gh`; touches no cache directory.
//
//   dart run tool/action_cache.dart sync [--runner-dir <dir>] [--no-prune]
//       Place the archives, verify their bytes, drop the ones no workflow names
//       any more, and record the cache directory in the runner's `.env`.
//
// It never restarts the runner. `.env` is read once, in
// `Program.LoadAndSetEnv`, when the listener starts, and restarting a live
// listener can sever a dispatched job. Start the runner after running this and
// the setting is picked up; until then the file existing proves nothing about
// the running process.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Where the runner is installed. Matches docs/AGENT_GUIDE.md.
const String defaultRunnerDirectory = r'C:\actions-runner';

/// The variable the runner reads. Its name is the runner's, not ours.
const String cacheEnvironmentVariable = 'ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE';

/// One `owner/repo@ref` a job asks for.
class ActionReference {
  const ActionReference({
    required this.nameWithOwner,
    required this.ref,
    required this.subPath,
  });

  final String nameWithOwner;
  final String ref;

  /// The path *inside* the repository, when the action is not at its root. The
  /// archive is the whole repository, so this never reaches a cache path.
  final String subPath;

  String get uses => '$nameWithOwner@$ref';

  @override
  bool operator ==(Object other) =>
      other is ActionReference &&
      other.nameWithOwner == nameWithOwner &&
      other.ref == ref &&
      other.subPath == subPath;

  @override
  int get hashCode => Object.hash(nameWithOwner, ref, subPath);

  @override
  String toString() => uses;
}

/// One archive to place, after the API has said what the ref resolves to.
class ActionCacheEntry {
  const ActionCacheEntry({
    required this.uses,
    required this.resolvedNameWithOwner,
    required this.sha,
  });

  final String uses;

  /// The name the runner *resolved*, which is where it will look. A renamed
  /// repository still answers under its old name, so the workflow's spelling is
  /// not necessarily this.
  final String resolvedNameWithOwner;

  /// The commit the ref points at. Naming the file by the ref instead would
  /// serve stale bytes under a name that no longer means them the moment a tag
  /// moves.
  final String sha;

  String get relativePath =>
      '${resolvedNameWithOwner.replaceAll(RegExp(r'[\\/]'), '_')}\\$sha.zip';

  String get url => 'https://codeload.github.com/$resolvedNameWithOwner/zip/$sha';
}

/// Strips a YAML end-of-line comment.
///
/// Load-bearing rather than cosmetic: without it a commented-out step would
/// seed the cache with an archive nothing uses, and a `#` inside a quoted
/// scalar would truncate a real value.
String stripYamlComment(String line) {
  String? quote;
  for (var index = 0; index < line.length; index += 1) {
    final character = line[index];
    if (quote != null) {
      if (character == quote) quote = null;
      continue;
    }
    if (character == '"' || character == "'") {
      quote = character;
      continue;
    }
    if (character == '#' &&
        (index == 0 || RegExp(r'\s').hasMatch(line[index - 1]))) {
      return line.substring(0, index).trimRight();
    }
  }
  return line;
}

int _indentOf(String line) => line.length - line.trimLeft().length;

/// One job's lines, keyed by job id.
///
/// Line-based on purpose: these files are checked in and read by humans, and a
/// YAML dependency for two shallow queries would be a larger surface than the
/// queries. A job header is a key with no value at the first indent inside
/// `jobs:`; every job-level key that matters here carries a value, and the ones
/// that do not (`steps:`, `permissions:`) are indented deeper.
Map<String, List<String>> splitWorkflowJobs(String contents) {
  final lines = contents.split(RegExp(r'\r?\n'));
  final jobsIndex = lines.indexWhere(
    (line) => RegExp(r'^\s*jobs:\s*$').hasMatch(stripYamlComment(line)),
  );
  if (jobsIndex == -1) return <String, List<String>>{};

  final jobsIndent = _indentOf(lines[jobsIndex]);
  final jobs = <String, List<String>>{};
  List<String>? current;
  int? jobIndent;

  for (var index = jobsIndex + 1; index < lines.length; index += 1) {
    final line = stripYamlComment(lines[index]);
    if (line.trim().isEmpty) continue;

    final indent = _indentOf(line);
    if (indent <= jobsIndent) break;

    final header = RegExp(r'^\s*([A-Za-z_][\w.-]*):\s*$').firstMatch(line);
    if (header != null && (jobIndent == null || indent == jobIndent)) {
      jobIndent = indent;
      current = <String>[];
      jobs[header.group(1)!] = current;
      continue;
    }

    current?.add(line);
  }

  return jobs;
}

/// The complete `runs-on:` value in these lines, folded onto one line.
///
/// A block scalar (`>-`, `|`) or a bare list continues on the following
/// more-indented lines, and the answer is wrong without them.
String? foldRunsOn(List<String> jobLines) {
  for (var index = 0; index < jobLines.length; index += 1) {
    final match = RegExp(r'^(\s*)runs-on:\s*(.*)$').firstMatch(jobLines[index]);
    if (match == null) continue;

    final inline = match.group(2)!.trim();
    if (inline.isNotEmpty && !const ['>-', '>', '|'].contains(inline)) {
      return inline;
    }

    final indent = match.group(1)!.length;
    final collected = <String>[];
    for (var next = index + 1; next < jobLines.length; next += 1) {
      final line = jobLines[next];
      if (line.trim().isEmpty) continue;
      if (_indentOf(line) <= indent) break;
      collected.add(line.trim());
    }
    return collected.join(' ');
  }
  return null;
}

/// True when this `runs-on:` selects one of the owner's own machines.
bool isSelfHosted(String? runsOn) =>
    runsOn != null && runsOn.contains('self-hosted');

/// Splits `owner/repo[/sub/path]@ref`.
///
/// Returns null for anything the archive cache cannot hold: a local reference
/// (`./.github/...`), a container action (`docker://...`), or a value with no
/// ref.
ActionReference? parseActionUses(String uses) {
  final value = uses.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
  if (value.isEmpty ||
      value.startsWith('./') ||
      value.startsWith(r'.\') ||
      value.startsWith('docker://')) {
    return null;
  }

  final separator = value.lastIndexOf('@');
  if (separator <= 0 || separator == value.length - 1) return null;

  final segments = value.substring(0, separator).split('/');
  if (segments.length < 2 || segments.any((segment) => segment.isEmpty)) {
    return null;
  }

  return ActionReference(
    nameWithOwner: '${segments[0]}/${segments[1]}',
    ref: value.substring(separator + 1),
    subPath: segments.skip(2).join('/'),
  );
}

/// Every action a job on our own hosts would download, deduped and sorted.
///
/// Hosted jobs are excluded deliberately: the cache is a property of this
/// machine, so caching a hosted runner's actions would be download with no
/// possible hit.
List<ActionReference> collectCacheableActions(Iterable<String> workflows) {
  final found = <String, ActionReference>{};

  for (final workflow in workflows) {
    for (final job in splitWorkflowJobs(workflow).values) {
      if (!isSelfHosted(foldRunsOn(job))) continue;

      for (final line in job) {
        final match = RegExp(r'^\s*(?:-\s+)?uses:\s*(\S.*)$').firstMatch(line);
        if (match == null) continue;
        final reference = parseActionUses(match.group(1)!);
        if (reference != null) found[reference.uses] = reference;
      }
    }
  }

  final references = found.values.toList()
    ..sort((a, b) => a.uses.compareTo(b.uses));
  return references;
}

/// The runner's `.env` after recording this cache directory.
///
/// The file is edited rather than rewritten: it is the runner's, not this
/// repository's, and a future setting must survive a cache refresh. Any
/// existing assignment of our own variable is replaced rather than appended to,
/// because two assignments would make the effective value depend on order.
List<String> composeEnvironmentFile(
  List<String> existingLines,
  String cacheDirectory,
) {
  final assignment = RegExp('^\\s*$cacheEnvironmentVariable\\s*=');
  final kept = existingLines
      .where((line) => !assignment.hasMatch(line))
      .toList();

  while (kept.isNotEmpty && kept.last.trim().isEmpty) {
    kept.removeLast();
  }

  return [...kept, '$cacheEnvironmentVariable=$cacheDirectory'];
}

/// True when these bytes are a readable zip with at least one entry.
///
/// A length check is not enough, and the difference is the whole point: a
/// rate-limit page or a truncated response is a perfectly good file of
/// plausible size. A corrupt archive in the cache fails *every* job, which is
/// worse than the download it replaces, so this runs on entries already present
/// as well as on new ones.
bool isReadableZip(List<int> bytes) {
  if (bytes.isEmpty) return false;
  try {
    return ZipDecoder().decodeBytes(bytes).isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// The cached archives no longer named by the plan.
///
/// The caller must refuse an empty plan first: "nothing is planned" and
/// "everything is stale" are the same set, and only one of them is a reason to
/// delete a working cache.
List<String> staleArchives({
  required List<String> present,
  required List<String> planned,
}) {
  if (planned.isEmpty) {
    throw ArgumentError('Refusing to treat an empty plan as a full cache sweep.');
  }
  final keep = planned.map((path) => path.toLowerCase()).toSet();
  return present
      .where((path) => !keep.contains(path.toLowerCase()))
      .toList();
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

Future<String> _gh(List<String> arguments) async {
  final result = await Process.run('gh', arguments, runInShell: true);
  if (result.exitCode != 0) {
    throw StateError(
      'gh ${arguments.join(' ')} failed (${result.exitCode}): ${result.stderr}',
    );
  }
  return (result.stdout as String).trim();
}

/// Asks the API what the runner itself would resolve.
///
/// `full_name` rather than the workflow's spelling, because a renamed
/// repository still answers under its old name and the runner files the archive
/// under the name it resolved. The commit rather than the ref, so a moved tag
/// misses and re-downloads.
Future<ActionCacheEntry> resolve(ActionReference reference) async {
  final fullName = await _gh([
    'api',
    'repos/${reference.nameWithOwner}',
    '--jq',
    '.full_name',
  ]);
  final sha = await _gh([
    'api',
    'repos/${reference.nameWithOwner}/commits/${reference.ref}',
    '--jq',
    '.sha',
  ]);

  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(sha)) {
    throw StateError('${reference.uses} resolved to "$sha", not a commit SHA.');
  }
  return ActionCacheEntry(
    uses: reference.uses,
    resolvedNameWithOwner: fullName,
    sha: sha,
  );
}

Future<List<ActionCacheEntry>> _buildPlan(Directory repositoryRoot) async {
  final workflowDirectory = Directory(
    p.join(repositoryRoot.path, '.github', 'workflows'),
  );
  final workflows = workflowDirectory
      .listSync()
      .whereType<File>()
      .where((file) => RegExp(r'\.ya?ml$').hasMatch(file.path))
      .map((file) => file.readAsStringSync());

  final references = collectCacheableActions(workflows);
  if (references.isEmpty) {
    // Never a quiet outcome: an empty plan is exactly what would make the sync
    // prune a working cache, so it stops here instead.
    throw StateError('No self-hosted job uses a downloadable action.');
  }

  return Future.wait(references.map(resolve));
}

Future<void> _sync(
  Directory repositoryRoot,
  String runnerDirectory, {
  required bool prune,
}) async {
  final plan = await _buildPlan(repositoryRoot);
  final cacheDirectory = p.join(runnerDirectory, 'action-archive-cache');

  if (!Directory(runnerDirectory).existsSync()) {
    throw StateError('No runner directory at $runnerDirectory.');
  }
  Directory(cacheDirectory).createSync(recursive: true);

  for (final entry in plan) {
    final destination = File(p.join(cacheDirectory, entry.relativePath));

    if (destination.existsSync()) {
      if (isReadableZip(destination.readAsBytesSync())) {
        stdout.writeln('present|${entry.relativePath}');
        continue;
      }
      // Repair is the same code path as a first fetch, so a corrupt entry
      // cannot become permanent by being reported as present every run.
      stdout.writeln('corrupt-cached|${entry.relativePath}');
      destination.deleteSync();
    }

    final response = await http.get(Uri.parse(entry.url));
    if (response.statusCode != 200) {
      throw StateError('${entry.url} answered ${response.statusCode}.');
    }
    if (!isReadableZip(response.bodyBytes)) {
      throw StateError('${entry.url} did not return a readable zip.');
    }
    destination.parent.createSync(recursive: true);
    destination.writeAsBytesSync(response.bodyBytes);
    stdout.writeln('cached|${entry.relativePath}');
  }

  if (prune) {
    final present = Directory(cacheDirectory)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.zip'))
        .map((file) => p.relative(file.path, from: cacheDirectory))
        .toList();
    for (final stale in staleArchives(
      present: present,
      planned: plan.map((entry) => entry.relativePath).toList(),
    )) {
      File(p.join(cacheDirectory, stale)).deleteSync();
      stdout.writeln('pruned|$stale');
    }
  }

  final environmentFile = File(p.join(runnerDirectory, '.env'));
  final existing = environmentFile.existsSync()
      ? environmentFile.readAsLinesSync()
      : <String>[];
  final wanted = '$cacheEnvironmentVariable=$cacheDirectory';

  if (existing.contains(wanted)) {
    stdout.writeln('env|unchanged');
    return;
  }

  environmentFile.writeAsStringSync(
    '${composeEnvironmentFile(existing, cacheDirectory).join('\n')}\n',
  );
  // What matters is not that the write returned but that the line is in the
  // file afterwards; a partial write differs from a failed one.
  if (!environmentFile.readAsLinesSync().contains(wanted)) {
    throw StateError('Wrote ${environmentFile.path} without "$wanted".');
  }
  stdout.writeln('env|updated');
  stdout.writeln(
    'The runner reads .env once at listener start; this engages at the next start.',
  );
}

Future<void> main(List<String> args) async {
  final repositoryRoot = Directory.current;
  final command = args.isEmpty ? '' : args.first;

  var runnerDirectory = defaultRunnerDirectory;
  final runnerFlag = args.indexOf('--runner-dir');
  if (runnerFlag != -1 && runnerFlag + 1 < args.length) {
    runnerDirectory = args[runnerFlag + 1];
  }

  switch (command) {
    case 'plan':
      for (final entry in await _buildPlan(repositoryRoot)) {
        stdout.writeln('${entry.uses} -> ${entry.relativePath}');
      }
    case 'sync':
      await _sync(
        repositoryRoot,
        runnerDirectory,
        prune: !args.contains('--no-prune'),
      );
    default:
      stderr.writeln(
        'Usage: dart run tool/action_cache.dart '
        '(plan | sync [--runner-dir <dir>] [--no-prune])',
      );
      exitCode = 2;
  }
}
