import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../config/app_config.dart';
import '../network/api_client.dart';

/// Network image for server-hosted files. The backend serves files behind auth, so the
/// bearer token is attached; the cache key ignores the host so changing backend URL is harmless.
class AuthImage extends StatelessWidget {
  const AuthImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final api = GetIt.I<ApiClient>();
    final cfg = GetIt.I<AppConfig>();
    final full = cfg.absolute(url);
    final fallback =
        placeholder ??
        const Icon(Icons.broken_image_outlined, color: Colors.grey);
    return CachedNetworkImage(
      imageUrl: full,
      cacheKey: url,
      httpHeaders: api.authHeaders(gym: false),
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, _) => SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      errorWidget: (_, _, _) => Center(child: fallback),
    );
  }
}
