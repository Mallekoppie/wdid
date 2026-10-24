/// A labeled external reference attached to an entry, project or milestone.
class LinkRef {
  const LinkRef({required this.label, required this.url});

  final String label;
  final String url;

  factory LinkRef.fromJson(Map<String, dynamic> json) => LinkRef(
    label: json['label']?.toString() ?? json['url']?.toString() ?? 'Link',
    url: json['url']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {'label': label, 'url': url};
}
