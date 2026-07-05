class Review {
  final String author;
  final String content;
  final double? rating;
  final String date;

  const Review({
    required this.author,
    required this.content,
    this.rating,
    required this.date,
  });

  factory Review.fromJson(Map<String, dynamic> json) => Review(
    author: json['author'] as String? ?? 'Anonim',
    content: (json['content'] as String? ?? '').trim(),
    rating: (json['author_details']?['rating'] as num?)?.toDouble(),
    date: (json['created_at'] as String? ?? '').length >= 10
        ? (json['created_at'] as String).substring(0, 10)
        : '',
  );
}
