import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Disk cache for the images that are allowed to go through
/// `CachedNetworkImage`: artist avatars, large covers, and any remaining
/// one-off artwork. Track icons and the mini player are owned by
/// [CacheManager]'s artwork store instead.
class AppImageCacheManager {
  static const cacheKey = 'groundpipe_images';

  static final CacheManager instance = CacheManager(
    Config(
      cacheKey,
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 50,
    ),
  );
}
