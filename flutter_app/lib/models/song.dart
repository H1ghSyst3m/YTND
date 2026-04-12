class Song {
  const Song({
    required this.title,
    required this.artist,
    this.id,
    this.filename,
    this.fileAvailable = false,
    this.coverAvailable = false,
    this.coverFilename,
  });

  final String title;
  final String artist;
  final String? id;
  final String? filename;
  final bool fileAvailable;
  final bool coverAvailable;
  final String? coverFilename;

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      title: (json['title'] as String?) ?? '',
      artist: (json['artist'] as String?) ?? '',
      id: json['id'] as String?,
      filename: json['filename'] as String?,
      fileAvailable: (json['file_available'] as bool?) ?? false,
      coverAvailable: (json['cover_available'] as bool?) ?? false,
      coverFilename: json['cover'] as String?,
    );
  }
}
