class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.username,
    required this.role,
    this.rating,
  });

  final String id;
  final String email;
  final String username;
  final String role;
  final double? rating;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? 'passenger',
      rating: (json['rating'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'role': role,
      if (rating != null) 'rating': rating,
    };
  }
}
