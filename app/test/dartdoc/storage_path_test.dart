// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub_dartlang_org/dartdoc/models.dart';
import 'package:pub_dartlang_org/dartdoc/storage_path.dart';

void main() {
  test('shared assets', () {
    expect(isSharedAsset('static-assets/css/style.css'), isTrue);
    expect(isSharedAsset('static-assets/whatever.js'), isTrue);
    expect(isSharedAsset('static-files/style.css'), isFalse);
  });

  test('shared asset ObjectName', () {
    expect(sharedAssetObjectName('0.16.0', 'static-assets/style.css'),
        'shared-assets/dartdoc/0.16.0/static-assets/style.css');
  });

  test('entry paths', () {
    final entry = new DartdocEntry(
      uuid: '12345678-abcdef10',
      packageName: 'pkg_foo',
      packageVersion: '1.2.3',
      usesFlutter: false,
      dartdocVersion: '0.16.0',
      flutterVersion: '0.1.6',
      customizationVersion: '0.0.1',
      timestamp: new DateTime(2018, 03, 08),
      depsResolved: true,
      hasContent: true,
    );
    expect(entry.inProgressPrefix, 'pkg_foo/1.2.3/in-progress');
    expect(entry.inProgressObjectName,
        'pkg_foo/1.2.3/in-progress/12345678-abcdef10.json');
    expect(entry.entryPrefix, 'pkg_foo/1.2.3/entry');
    expect(entry.entryObjectName, 'pkg_foo/1.2.3/entry/12345678-abcdef10.json');
    expect(entry.contentPrefix, 'pkg_foo/1.2.3/content/12345678-abcdef10');
    expect(entry.objectName('static-assets/css/style.css'),
        'pkg_foo/1.2.3/content/12345678-abcdef10/static-assets/css/style.css');
    expect(entry.objectName('index.html'),
        'pkg_foo/1.2.3/content/12345678-abcdef10/index.html');
    expect(entry.objectName('library/index.html'),
        'pkg_foo/1.2.3/content/12345678-abcdef10/library/index.html');
  });
}