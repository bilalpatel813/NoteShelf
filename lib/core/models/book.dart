/// Shared domain models. Owned by T1; T2-T5 import these, do not fork them.
library;

import 'package:flutter/foundation.dart';

/// How the user prefers to read a book. T3/T4 decide how each mode renders.
enum ReadingMode { singlePage, twoPageSpread, continuousScroll }

/// Reference to a cover: a generated cover (colour only) or an image.
///
/// [imagePath] is an opaque reference: an absolute path or a path relative to
/// the book folder. T2 decides the convention and resolves it.
@immutable
class BookCoverRef {
  const BookCoverRef({this.imagePath, this.colorValue = 0xFF7A2E2E});

  final String? imagePath;
  final int colorValue;

  Map<String, Object?> toJson() => {
    'imagePath': imagePath,
    'colorValue': colorValue,
  };

  factory BookCoverRef.fromJson(Map<String, Object?> j) => BookCoverRef(
    imagePath: j['imagePath'] as String?,
    colorValue: (j['colorValue'] as num?)?.toInt() ?? 0xFF7A2E2E,
  );
}

@immutable
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.subject,
    required this.folderRef,
    this.cover = const BookCoverRef(),
    this.pageCount = 0,
    this.lastOpenedPage = 1,
    this.lastOpenedAt,
    this.preferredReadingMode = ReadingMode.singlePage,
  });

  /// Unique, stable ID. Never derived from the title.
  final String id;
  final String title;
  final String subject;

  /// Opaque reference to the folder holding this book's TXT pages.
  /// The format is owned by T2 (e.g. an absolute directory path).
  final String folderRef;
  final BookCoverRef cover;
  final int pageCount;

  /// 1-based page number.
  final int lastOpenedPage;
  final DateTime? lastOpenedAt;
  final ReadingMode preferredReadingMode;

  Book copyWith({
    String? title,
    String? subject,
    String? folderRef,
    BookCoverRef? cover,
    int? pageCount,
    int? lastOpenedPage,
    DateTime? lastOpenedAt,
    ReadingMode? preferredReadingMode,
  }) => Book(
    id: id,
    title: title ?? this.title,
    subject: subject ?? this.subject,
    folderRef: folderRef ?? this.folderRef,
    cover: cover ?? this.cover,
    pageCount: pageCount ?? this.pageCount,
    lastOpenedPage: lastOpenedPage ?? this.lastOpenedPage,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    preferredReadingMode: preferredReadingMode ?? this.preferredReadingMode,
  );

  /// Suggested JSON shape for T2's metadata file. T2 may extend it.
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'subject': subject,
    'folderRef': folderRef,
    'cover': cover.toJson(),
    'pageCount': pageCount,
    'lastOpenedPage': lastOpenedPage,
    'lastOpenedAt': lastOpenedAt?.toIso8601String(),
    'preferredReadingMode': preferredReadingMode.name,
  };

  factory Book.fromJson(Map<String, Object?> j) => Book(
    id: j['id'] as String,
    title: j['title'] as String,
    subject: (j['subject'] as String?) ?? 'General',
    folderRef: j['folderRef'] as String,
    cover: BookCoverRef.fromJson(
      Map<String, Object?>.from((j['cover'] as Map?) ?? const {}),
    ),
    pageCount: (j['pageCount'] as num?)?.toInt() ?? 0,
    lastOpenedPage: (j['lastOpenedPage'] as num?)?.toInt() ?? 1,
    lastOpenedAt: j['lastOpenedAt'] == null
        ? null
        : DateTime.parse(j['lastOpenedAt'] as String),
    preferredReadingMode: ReadingMode.values.firstWhere(
      (m) => m.name == j['preferredReadingMode'],
      orElse: () => ReadingMode.singlePage,
    ),
  );
}

/// One page of a book. In T2 each page maps to one TXT file.
@immutable
class BookPage {
  const BookPage({
    required this.bookId,
    required this.number,
    required this.fileName,
    this.content = '',
    this.updatedAt,
  });

  final String bookId;

  /// 1-based position in the book.
  final int number;

  /// File name inside the book folder. Naming scheme is owned by T2.
  final String fileName;
  final String content;
  final DateTime? updatedAt;

  BookPage copyWith({
    int? number,
    String? fileName,
    String? content,
    DateTime? updatedAt,
  }) => BookPage(
    bookId: bookId,
    number: number ?? this.number,
    fileName: fileName ?? this.fileName,
    content: content ?? this.content,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
