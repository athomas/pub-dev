// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:pana/pana.dart';
import 'package:pana/src/maintenance.dart';
import 'package:pana/src/version.dart';
import 'package:path/path.dart' as p;

import '../job/job.dart';
import '../shared/analyzer_service.dart';
import '../shared/configuration.dart';
import '../shared/platform.dart';

import 'backend.dart';
import 'models.dart';

final Logger _logger = new Logger('pub.analyzer.pana');

class AnalyzerJobProcessor extends JobProcessor {
  AnalyzerJobProcessor({Duration lockDuration})
      : super(service: JobService.analyzer, lockDuration: lockDuration);

  @override
  Future<bool> shouldProcess(
      String package, String version, DateTime updated) async {
    final status =
        await analysisBackend.checkTargetStatus(package, version, updated);
    return !status.shouldSkip;
  }

  @override
  Future<JobStatus> process(Job job) async {
    final packageStatus = await analysisBackend.getPackageStatus(
        job.packageName, job.packageVersion);
    if (!packageStatus.exists) {
      _logger.info('Package does not exist: $job.');
      return JobStatus.skipped;
    }

    try {
      await analysisBackend.deleteObsoleteAnalysis(
          job.packageName, job.packageVersion);
    } catch (e) {
      _logger.warning('Analysis GC failed: $job', e);
    }

    final DateTime timestamp = new DateTime.now().toUtc();
    final Analysis analysis =
        new Analysis.init(job.packageName, job.packageVersion, timestamp);

    if (packageStatus.isDiscontinued) {
      _logger.info('Package is discontinued: $job.');
      analysis.analysisStatus = AnalysisStatus.discontinued;
      analysis.maintenanceScore = 0.0;
      await analysisBackend.storeAnalysis(analysis);
      return JobStatus.skipped;
    }

    if (packageStatus.isObsolete) {
      _logger
          .info('Package is older than two years and has newer release: $job.');
      analysis.analysisStatus = AnalysisStatus.outdated;
      analysis.maintenanceScore = 0.0;
      await analysisBackend.storeAnalysis(analysis);
      return JobStatus.skipped;
    }

    Future<Summary> analyze() async {
      Directory tempDir;
      try {
        tempDir = await Directory.systemTemp.createTemp('pana');
        final tempDirPath = await tempDir.resolveSymbolicLinks();
        final pubCacheDir = p.join(tempDirPath, 'pub-cache');
        await new Directory(pubCacheDir).create();
        final toolEnv = await ToolEnvironment.create(
          flutterSdkDir: envConfig.flutterSdkDir,
          pubCacheDir: pubCacheDir,
          useGlobalDartdoc: true,
        );
        final PackageAnalyzer analyzer = new PackageAnalyzer(toolEnv);
        return await analyzer.inspectPackage(
          job.packageName,
          version: job.packageVersion,
          logger: new Logger.detached(
              'pana/${job.packageName}/${job.packageVersion}'),
        );
      } catch (e, st) {
        _logger.severe(
            'Failed (v$panaPkgVersion) - ${job.packageVersion}/${job.packageVersion}',
            e,
            st);
      } finally {
        if (tempDir != null) {
          await tempDir.delete(recursive: true);
        }
      }
      return null;
    }

    Summary summary = await analyze();
    final bool firstRunWithErrors =
        summary?.suggestions?.where((s) => s.isError)?.isNotEmpty ?? false;
    if (summary == null || firstRunWithErrors) {
      _logger.info('Retrying $job...');
      await new Future.delayed(new Duration(seconds: 15));
      summary = await analyze();
    }

    JobStatus status = JobStatus.failed;
    if (summary == null) {
      analysis.analysisStatus = AnalysisStatus.aborted;
    } else {
      summary = applyPlatformOverride(summary);
      final bool lastRunWithErrors =
          summary.suggestions?.where((s) => s.isError)?.isNotEmpty ?? false;
      if (!lastRunWithErrors) {
        analysis.analysisStatus = AnalysisStatus.success;
        status = JobStatus.success;
      } else {
        analysis.analysisStatus = AnalysisStatus.failure;
      }
      analysis.analysisJson = summary.toJson();
      analysis.maintenanceScore = summary.maintenance == null
          ? 0.0
          : getMaintenanceScore(summary.maintenance, age: packageStatus.age);
    }

    final backendStatus = await analysisBackend.storeAnalysis(analysis);

    if (backendStatus.isLatestStable &&
        analysis.analysisStatus != AnalysisStatus.success &&
        analysis.analysisStatus != AnalysisStatus.discontinued) {
      reportIssueWithLatest(job, '${analysis.analysisStatus}');
    }

    return status;
  }
}
