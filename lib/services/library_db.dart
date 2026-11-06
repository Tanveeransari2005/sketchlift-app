/// Local library (SQLite via sqflite) — works fully offline.
///
/// Tables
///   diagrams   (id, title, subject, chapter, created_at, meta_json, image_path)
///   classes    (id, name, section)                       — teacher dashboard
///   worksheets (id, class_id, title, diagram_ids, created_at) — worksheet history
///
/// Pictures are stored as PNG files in the app's documents folder; the DB keeps
/// the path. Folders in the UI are simply GROUP BY subject → chapter.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/diagram_doc.dart';

class SavedDiagramRow {
  final int id;
  final String title, subject, chapter, imagePath;
  final DateTime createdAt;
  const SavedDiagramRow(this.id, this.title, this.subject, this.chapter, this.imagePath, this.createdAt);
}

class ClassRow {
  final int id;
  final String name, section;
  const ClassRow(this.id, this.name, this.section);
  String get label => section.isEmpty ? name : '$name – $section';
}

class WorksheetRow {
  final int id;
  final int? classId;
  final String title;
  final List<int> diagramIds;
  final DateTime createdAt;
  const WorksheetRow(this.id, this.classId, this.title, this.diagramIds, this.createdAt);
}

class LibraryDb {
  LibraryDb._(this._db, this._dir);
  final Database _db;
  final Directory _dir;

  static LibraryDb? _instance;

  static Future<LibraryDb> open() async {
    if (_instance != null) return _instance!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'diagrams'));
    await dir.create(recursive: true);
    final db = await openDatabase(
      p.join(docs.path, 'library.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''CREATE TABLE diagrams(
          id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, subject TEXT, chapter TEXT,
          created_at INTEGER, meta_json TEXT, image_path TEXT)''');
        await db.execute('CREATE TABLE classes(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, section TEXT)');
        await db.execute('''CREATE TABLE worksheets(
          id INTEGER PRIMARY KEY AUTOINCREMENT, class_id INTEGER, title TEXT,
          diagram_ids TEXT, created_at INTEGER)''');
      },
    );
    return _instance = LibraryDb._(db, dir);
  }

  // ---- diagrams --------------------------------------------------------------

  /// Inserts or updates [doc]; returns its id.
  Future<int> save(DiagramDoc doc) async {
    final path = doc.id == null
        ? p.join(_dir.path, 'd_${DateTime.now().microsecondsSinceEpoch}.png')
        : (await _imagePath(doc.id!)) ?? p.join(_dir.path, 'd_${doc.id}.png');
    await File(path).writeAsBytes(doc.bodyPng, flush: true);
    final row = {
      'title': doc.title,
      'subject': doc.subject,
      'chapter': doc.chapter.trim().isEmpty ? 'General' : doc.chapter.trim(),
      'created_at': doc.createdAt.millisecondsSinceEpoch,
      'meta_json': doc.encodeMeta(),
      'image_path': path,
    };
    if (doc.id == null) {
      doc.id = await _db.insert('diagrams', row);
    } else {
      await _db.update('diagrams', row, where: 'id = ?', whereArgs: [doc.id]);
    }
    return doc.id!;
  }

  Future<String?> _imagePath(int id) async {
    final r = await _db.query('diagrams', columns: ['image_path'], where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first['image_path'] as String?;
  }

  /// All diagrams, newest first, optionally filtered by a search [query]
  /// (matches title, subject, chapter and part names).
  Future<List<SavedDiagramRow>> list({String query = '', String? subject}) async {
    final where = <String>[];
    final args = <Object>[];
    if (query.trim().isNotEmpty) {
      where.add('(title LIKE ? OR subject LIKE ? OR chapter LIKE ? OR meta_json LIKE ?)');
      final q = '%${query.trim()}%';
      args.addAll([q, q, q, q]);
    }
    if (subject != null) {
      where.add('subject = ?');
      args.add(subject);
    }
    final rows = await _db.query('diagrams',
        columns: ['id', 'title', 'subject', 'chapter', 'image_path', 'created_at'],
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'created_at DESC');
    return rows
        .map((r) => SavedDiagramRow(
              r['id'] as int,
              r['title'] as String? ?? '',
              r['subject'] as String? ?? 'Other',
              r['chapter'] as String? ?? 'General',
              r['image_path'] as String? ?? '',
              DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int? ?? 0),
            ))
        .toList();
  }

  Future<DiagramDoc?> load(int id) async {
    final r = await _db.query('diagrams', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) return null;
    final row = r.first;
    final (result, used) = DiagramDoc.decodeMeta(row['meta_json'] as String);
    Uint8List png;
    try {
      png = await File(row['image_path'] as String).readAsBytes();
    } catch (_) {
      return null;
    }
    return DiagramDoc(
      id: id,
      result: result,
      bodyPng: png,
      usedBody: used,
      chapter: row['chapter'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int? ?? 0),
    );
  }

  Future<void> delete(int id) async {
    final path = await _imagePath(id);
    await _db.delete('diagrams', where: 'id = ?', whereArgs: [id]);
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  // ---- classes & worksheets (teacher dashboard) -----------------------------

  Future<List<ClassRow>> classes() async => (await _db.query('classes', orderBy: 'name'))
      .map((r) => ClassRow(r['id'] as int, r['name'] as String, r['section'] as String? ?? ''))
      .toList();

  Future<void> addClass(String name, String section) =>
      _db.insert('classes', {'name': name.trim(), 'section': section.trim()});

  Future<void> deleteClass(int id) => _db.delete('classes', where: 'id = ?', whereArgs: [id]);

  Future<void> addWorksheet(int? classId, String title, List<int> diagramIds) => _db.insert('worksheets', {
        'class_id': classId,
        'title': title,
        'diagram_ids': diagramIds.join(','),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

  Future<List<WorksheetRow>> worksheets() async =>
      (await _db.query('worksheets', orderBy: 'created_at DESC')).map((r) {
        final ids = (r['diagram_ids'] as String? ?? '').split(',').where((s) => s.isNotEmpty).map(int.parse).toList();
        return WorksheetRow(r['id'] as int, r['class_id'] as int?, r['title'] as String? ?? '', ids,
            DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int));
      }).toList();
}
