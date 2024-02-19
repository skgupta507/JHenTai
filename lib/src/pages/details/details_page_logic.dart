import 'dart:async';
import 'dart:collection';

import 'package:clipboard/clipboard.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/consts/eh_consts.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/extension/get_logic_extension.dart';
import 'package:jhentai/src/extension/string_extension.dart';
import 'package:jhentai/src/mixin/login_required_logic_mixin.dart';
import 'package:jhentai/src/model/gallery_tag.dart';
import 'package:jhentai/src/model/gallery_thumbnail.dart';
import 'package:jhentai/src/model/read_page_info.dart';
import 'package:jhentai/src/network/eh_request.dart';
import 'package:jhentai/src/pages/download/download_base_page.dart';
import 'package:jhentai/src/service/super_resolution_service.dart';
import 'package:jhentai/src/setting/download_setting.dart';
import 'package:jhentai/src/setting/my_tags_setting.dart';
import 'package:jhentai/src/utils/string_uril.dart';
import 'package:jhentai/src/widget/eh_add_tag_dialog.dart';
import 'package:jhentai/src/widget/eh_alert_dialog.dart';
import 'package:jhentai/src/widget/eh_gallery_torrents_dialog.dart';
import 'package:jhentai/src/widget/eh_archive_dialog.dart';
import 'package:jhentai/src/widget/eh_favorite_dialog.dart';
import 'package:jhentai/src/widget/eh_rating_dialog.dart';
import 'package:jhentai/src/widget/eh_gallery_stat_dialog.dart';
import 'package:jhentai/src/routes/routes.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/tag_translation_service.dart';
import 'package:jhentai/src/setting/favorite_setting.dart';
import 'package:jhentai/src/setting/user_setting.dart';
import 'package:jhentai/src/utils/eh_spider_parser.dart';
import 'package:jhentai/src/utils/log.dart';
import 'package:jhentai/src/utils/screen_size_util.dart';
import 'package:jhentai/src/utils/snack_util.dart';
import 'package:jhentai/src/widget/loading_state_indicator.dart';
import 'package:share_plus/share_plus.dart';

import '../../exception/eh_site_exception.dart';
import '../../mixin/scroll_to_top_logic_mixin.dart';
import '../../mixin/scroll_to_top_state_mixin.dart';
import '../../mixin/update_global_gallery_status_logic_mixin.dart';
import '../../model/gallery.dart';
import '../../model/gallery_detail.dart';
import '../../model/gallery_image.dart';
import '../../model/tag_set.dart';
import '../../service/history_service.dart';
import '../../service/gallery_download_service.dart';
import '../../service/storage_service.dart';
import '../../setting/eh_setting.dart';
import '../../setting/read_setting.dart';
import '../../utils/process_util.dart';
import '../../utils/route_util.dart';
import '../../utils/search_util.dart';
import '../../utils/toast_util.dart';
import '../../widget/eh_download_dialog.dart';
import '../../widget/eh_download_hh_dialog.dart';
import '../../widget/eh_gallery_history_dialog.dart';
import '../../widget/jump_page_dialog.dart';
import 'details_page_state.dart';

class DetailsPageLogic extends GetxController with LoginRequiredMixin, Scroll2TopLogicMixin, UpdateGlobalGalleryStatusLogicMixin {
  static const String galleryId = 'galleryId';
  static const String uploaderId = 'uploaderId';
  static const String detailsId = 'detailsId';
  static const String languageId = 'languageId';
  static const String pageCountId = 'pageCountId';
  static const String ratingId = 'ratingId';
  static const String favoriteId = 'favoriteId';
  static const String readButtonId = 'readButtonId';
  static const String thumbnailsId = 'thumbnailsId';
  static const String thumbnailId = 'thumbnailId';
  static const String loadingStateId = 'fullPageLoadingStateId';
  static const String loadingThumbnailsStateId = 'loadingThumbnailsStateId';
  static const String addFavoriteStateId = 'addFavoriteStateId';
  static const String ratingStateId = 'ratingStateId';

  /// there may be more than one DetailsPages in route stack at same time, eg: tap a link in a comment.
  /// use this param as a 'tag' to get target [DetailsPageLogic] and [DetailsPageState].
  static final List<DetailsPageLogic> _stack = <DetailsPageLogic>[];

  static DetailsPageLogic? get current => _stack.isEmpty ? null : _stack.last;

  final DetailsPageState state = DetailsPageState();

  @override
  Scroll2TopStateMixin get scroll2TopState => state;

  final GalleryDownloadService galleryDownloadService = Get.find();
  final ArchiveDownloadService archiveDownloadService = Get.find();
  final SuperResolutionService superResolutionService = Get.find();
  final StorageService storageService = Get.find();
  final HistoryService historyService = Get.find();
  final TagTranslationService tagTranslationService = Get.find();

  DetailsPageLogic() {
    _stack.add(this);
  }

  DetailsPageLogic.preview();

  @override
  void onInit() {
    super.onInit();

    if (Get.arguments is! Map) {
      return;
    }

    state.galleryUrl = Get.arguments['galleryUrl'];
    state.gallery = Get.arguments['gallery'];
  }

  @override
  void onReady() async {
    super.onReady();
    getDetails();
  }

  @override
  void onClose() {
    super.onClose();
    _stack.remove(this);
  }

  Future<void> getDetails({bool refreshPageImmediately = true, bool useCacheIfAvailable = true}) async {
    if (state.loadingState == LoadingState.loading) {
      return;
    }

    state.loadingState = LoadingState.loading;
    if (refreshPageImmediately) {
      updateSafely([loadingStateId]);
    }

    Log.info('Get gallery details:${state.galleryUrl}');

    ({GalleryDetail galleryDetails, String apikey})? detailPageInfo;
    try {
      detailPageInfo = await _getDetailsWithRedirectAndFallback(useCache: useCacheIfAvailable);
    } on DioException catch (e) {
      Log.error('Get Gallery Detail Failed', e.message);
      snack('getGalleryDetailFailed'.tr, e.message ?? '', longDuration: true);
      state.loadingState = LoadingState.error;
      if (refreshPageImmediately) {
        updateSafely([loadingStateId]);
      }
      return;
    } on EHSiteException catch (e) {
      Log.error('Get Gallery Detail Failed', e.message);
      snack('getGalleryDetailFailed'.tr, e.message, longDuration: true);
      state.loadingState = LoadingState.error;
      if (refreshPageImmediately) {
        updateSafely([loadingStateId]);
      }

      if (e.type == EHSiteExceptionType.galleryDeleted) {
        await _handleGalleryDeleted();
      }
      return;
    } catch (e, s) {
      Log.error('Get Gallery Detail Failed', e, s);
      snack('getGalleryDetailFailed'.tr, e.toString(), longDuration: true);
      state.loadingState = LoadingState.error;
      if (refreshPageImmediately) {
        updateSafely([loadingStateId]);
      }
      return;
    }

    state.galleryDetails = detailPageInfo.galleryDetails;
    state.apikey = detailPageInfo.apikey;
    state.nextPageIndexToLoadThumbnails = 1;

    await tagTranslationService.translateTagsIfNeeded(state.galleryDetails!.tags);

    _addColor2WatchedTags(state.galleryDetails!.tags);

    state.loadingState = LoadingState.success;
    updateSafely(_judgeUpdateIds());

    SchedulerBinding.instance.scheduleTask(() => historyService.record(state.gallery), Priority.animation);
  }

  Future<void> _handleGalleryDeleted() async {
    /// todo
  }

  Future<void> loadMoreThumbnails() async {
    if (state.loadingThumbnailsState == LoadingState.loading) {
      return;
    }

    /// no more thumbnails
    if (state.nextPageIndexToLoadThumbnails >= state.galleryDetails!.thumbnailsPageCount) {
      state.loadingThumbnailsState = LoadingState.noMore;
      updateSafely([loadingThumbnailsStateId]);
      return;
    }

    state.loadingThumbnailsState = LoadingState.loading;
    updateSafely([loadingThumbnailsStateId]);

    List<GalleryThumbnail> newThumbNails;
    try {
      newThumbNails = await EHRequest.requestDetailPage(
        galleryUrl: state.galleryUrl.url,
        thumbnailsPageIndex: state.nextPageIndexToLoadThumbnails,
        parser: EHSpiderParser.detailPage2Thumbnails,
      );
    } on DioException catch (e) {
      Log.error('failToGetThumbnails'.tr, e.message);
      snack('failToGetThumbnails'.tr, e.message ?? '', longDuration: true);
      state.loadingThumbnailsState = LoadingState.error;
      updateSafely([loadingThumbnailsStateId]);
      return;
    } on EHSiteException catch (e) {
      Log.error('failToGetThumbnails'.tr, e.message);
      snack('failToGetThumbnails'.tr, e.message, longDuration: true);
      state.loadingThumbnailsState = LoadingState.error;
      updateSafely([loadingThumbnailsStateId]);
      return;
    } catch (e, s) {
      Log.error('failToGetThumbnails'.tr, e, s);
      snack('failToGetThumbnails'.tr, e.toString(), longDuration: true);
      state.loadingThumbnailsState = LoadingState.error;
      updateSafely([loadingThumbnailsStateId]);
      return;
    }

    state.galleryDetails!.thumbnails.addAll(newThumbNails);
    state.nextPageIndexToLoadThumbnails++;

    state.loadingThumbnailsState = LoadingState.idle;
    updateSafely([thumbnailsId]);
  }

  Future<void> handleRefresh() async {
    return getDetails(refreshPageImmediately: false, useCacheIfAvailable: false);
  }

  Future<void> handleTapDownload() async {
    GalleryDownloadService downloadService = Get.find<GalleryDownloadService>();
    GalleryDownloadedData? galleryDownloadedData = downloadService.gallerys.singleWhereOrNull((g) => g.gid == state.galleryUrl.gid);
    GalleryDownloadProgress? downloadProgress = downloadService.galleryDownloadInfos[state.galleryUrl.gid]?.downloadProgress;

    /// new download
    if (galleryDownloadedData == null || downloadProgress == null) {
      ({String group, bool downloadOriginalImage})? result = await Get.dialog(
        EHDownloadDialog(
          title: 'chooseGroup'.tr,
          currentGroup: DownloadSetting.defaultGalleryGroup.value,
          candidates: downloadService.allGroups,
          showDownloadOriginalImageCheckBox: UserSetting.hasLoggedIn(),
          downloadOriginalImage: DownloadSetting.downloadOriginalImageByDefault.value,
        ),
      );

      if (result == null) {
        return;
      }

      downloadService.downloadGallery(state.galleryDetails!.toGalleryDownloadedData(
        downloadOriginalImage: result.downloadOriginalImage,
        group: result.group,
      ));

      updateGlobalGalleryStatus();

      toast('${'beginToDownload'.tr}： ${state.galleryUrl.gid}', isCenter: false);
      return;
    }

    if (downloadProgress.downloadStatus == DownloadStatus.paused) {
      downloadService.resumeDownloadGallery(galleryDownloadedData);
      toast('${'resume'.tr}： ${state.galleryUrl.gid}', isCenter: false);
      return;
    } else if (downloadProgress.downloadStatus == DownloadStatus.downloading) {
      downloadService.pauseDownloadGallery(galleryDownloadedData);
      toast('${'pause'.tr}： ${state.galleryUrl.gid}', isCenter: false);
    } else if (downloadProgress.downloadStatus == DownloadStatus.downloaded && state.galleryDetails?.newVersionGalleryUrl == null) {
      goToReadPage();
    } else if (downloadProgress.downloadStatus == DownloadStatus.downloaded && state.galleryDetails?.newVersionGalleryUrl != null) {
      downloadService.updateGallery(galleryDownloadedData, state.galleryDetails!.newVersionGalleryUrl!);
      toast('${'update'.tr}： ${state.galleryUrl.gid}', isCenter: false);
    }
  }

  Future<void> handleTapFavorite({required bool useDefault}) async {
    if (!UserSetting.hasLoggedIn()) {
      showLoginToast();
      return;
    }

    if (state.favoriteState == LoadingState.loading) {
      return;
    }

    if (!FavoriteSetting.inited) {
      FavoriteSetting.refresh();
    }

    int? currentFavIndex = state.galleryDetails?.favoriteTagIndex ?? state.gallery?.favoriteTagIndex;

    int favIndex;
    if (useDefault && UserSetting.defaultFavoriteIndex.value != null) {
      favIndex = UserSetting.defaultFavoriteIndex.value!;
    } else {
      ({int favIndex, bool remember})? result = await Get.dialog(EHFavoriteDialog(selectedIndex: currentFavIndex));
      if (result == null) {
        return;
      }
      if (result.remember == true) {
        UserSetting.saveDefaultFavoriteIndex(result.favIndex);
      }
      favIndex = result.favIndex;
    }

    Log.info('Favorite gallery: ${state.galleryUrl.gid}');

    state.favoriteState = LoadingState.loading;
    updateSafely([addFavoriteStateId]);

    bool isRemoveFavorite = favIndex == currentFavIndex;
    try {
      if (isRemoveFavorite) {
        await EHRequest.requestRemoveFavorite(state.galleryUrl.gid, state.galleryUrl.token);
        FavoriteSetting.decrementFavByIndex(favIndex);
        state.gallery
          ?..favoriteTagIndex = null
          ..favoriteTagName = null;
      } else {
        await EHRequest.requestAddFavorite(state.galleryUrl.gid, state.galleryUrl.token, favIndex);
        FavoriteSetting.incrementFavByIndex(favIndex);
        FavoriteSetting.decrementFavByIndex(currentFavIndex);
        state.gallery
          ?..favoriteTagIndex = favIndex
          ..favoriteTagName = FavoriteSetting.favoriteTagNames[favIndex];
      }

      FavoriteSetting.save();
    } on DioException catch (e) {
      Log.error(isRemoveFavorite ? 'removeFavoriteFailed'.tr : 'favoriteGalleryFailed'.tr, e.message);
      snack(isRemoveFavorite ? 'removeFavoriteFailed'.tr : 'favoriteGalleryFailed'.tr, e.message ?? '', longDuration: true);
      state.favoriteState = LoadingState.error;
      updateSafely([addFavoriteStateId]);
      return;
    } on EHSiteException catch (e) {
      Log.error(isRemoveFavorite ? 'removeFavoriteFailed'.tr : 'favoriteGalleryFailed'.tr, e.message);
      snack(isRemoveFavorite ? 'removeFavoriteFailed'.tr : 'favoriteGalleryFailed'.tr, e.message, longDuration: true);
      state.favoriteState = LoadingState.error;
      updateSafely([addFavoriteStateId]);
      return;
    } catch (e, s) {
      Log.error(isRemoveFavorite ? 'removeFavoriteFailed'.tr : 'favoriteGalleryFailed'.tr, e, s);
      snack(isRemoveFavorite ? 'removeFavoriteFailed'.tr : 'favoriteGalleryFailed'.tr, e.toString(), longDuration: true);
      state.favoriteState = LoadingState.error;
      updateSafely([addFavoriteStateId]);
      return;
    }

    _removeCache();

    state.favoriteState = LoadingState.idle;
    updateSafely([addFavoriteStateId]);

    updateGlobalGalleryStatus();

    toast(
      isRemoveFavorite ? 'removeFavoriteSuccess'.tr : 'favoriteGallerySuccess'.tr,
      isCenter: false,
    );
  }

  Future<void> handleTapRating() async {
    if (state.apikey == null) {
      return;
    }
    if (state.galleryDetails?.rating == null && state.gallery?.rating == null) {
      return;
    }

    if (!checkLogin()) {
      return;
    }

    double? rating = await Get.dialog(EHRatingDialog(
      rating: state.galleryDetails?.rating ?? state.gallery!.rating,
      hasRated: state.galleryDetails?.hasRated ?? state.gallery!.hasRated,
    ));

    if (rating == null) {
      return;
    }

    Log.info('Rate gallery: ${state.galleryUrl.gid}, rating: $rating');

    state.ratingState = LoadingState.loading;
    updateSafely([ratingStateId]);

    Map<String, dynamic> ratingInfo;
    try {
      ratingInfo = await EHRequest.requestSubmitRating(
        state.galleryUrl.gid,
        state.galleryUrl.token,
        UserSetting.ipbMemberId.value!,
        state.apikey!,
        (rating * 2).toInt(),
        EHSpiderParser.galleryRatingResponse2RatingInfo,
      );
    } on DioException catch (e) {
      Log.error('ratingFailed'.tr, e.message);
      snack('ratingFailed'.tr, e.message ?? '');
      state.ratingState = LoadingState.error;
      updateSafely([ratingStateId]);
      return;
    } on EHSiteException catch (e) {
      Log.error('ratingFailed'.tr, e.message);
      snack('ratingFailed'.tr, e.message);
      state.ratingState = LoadingState.error;
      updateSafely([ratingStateId]);
      return;
    } on FormatException catch (_) {
      /// expired apikey
      await DetailsPageLogic.current!.handleRefresh();
      return handleTapRating();
    } catch (e, s) {
      Log.error('ratingFailed'.tr, e, s);
      snack('ratingFailed'.tr, e.toString());
      state.ratingState = LoadingState.error;
      updateSafely([ratingStateId]);
      return;
    }

    /// eg: {"rating_avg":0.93000000000000005,"rating_usr":0.5,"rating_cnt":21,"rating_cls":"ir irr"}
    state.gallery?.hasRated = true;
    state.gallery?.rating = ratingInfo['rating_usr'];
    state.galleryDetails?.ratingCount = ratingInfo['rating_cnt'];
    state.galleryDetails?.realRating = ratingInfo['rating_avg'];

    _removeCache();

    state.ratingState = LoadingState.idle;
    updateSafely();

    updateGlobalGalleryStatus();

    toast('ratingSuccess'.tr, isCenter: false);
  }

  Future<void> handleTapArchive() async {
    if (!UserSetting.hasLoggedIn()) {
      showLoginToast();
      return;
    }

    ArchiveStatus? archiveStatus = archiveDownloadService.archiveDownloadInfos[state.galleryUrl.gid]?.archiveStatus;

    /// new download
    if (archiveStatus == null) {
      ({bool isOriginal, int size, String group})? result = await Get.dialog(
        EHArchiveDialog(
          title: 'chooseArchive'.tr,
          archivePageUrl: state.galleryDetails!.archivePageUrl,
          currentGroup: DownloadSetting.defaultArchiveGroup.value,
          candidates: archiveDownloadService.allGroups,
        ),
      );
      if (result == null) {
        return;
      }

      ArchiveDownloadedData archive = state.galleryDetails!.toArchiveDownloadedData(
        archivePageUrl: state.galleryDetails!.archivePageUrl,
        isOriginal: result.isOriginal,
        size: result.size,
        group: result.group,
      );

      archiveDownloadService.downloadArchive(archive);

      updateGlobalGalleryStatus();

      Log.info('${'beginToDownloadArchive'.tr}: ${archive.title}');
      toast('${'beginToDownloadArchive'.tr}:  ${archive.title}', isCenter: false);
      return;
    }

    ArchiveDownloadedData archive = archiveDownloadService.archives.firstWhere((a) => a.gid == state.galleryUrl.gid);

    if (archiveStatus == ArchiveStatus.paused) {
      return archiveDownloadService.resumeDownloadArchive(archive);
    }

    if (ArchiveStatus.unlocking.index <= archiveStatus.index && archiveStatus.index < ArchiveStatus.downloaded.index) {
      return archiveDownloadService.pauseDownloadArchive(archive);
    }

    if (archiveStatus == ArchiveStatus.completed) {
      String storageKey = 'readIndexRecord::${archive.gid}';
      int readIndexRecord = storageService.read(storageKey) ?? 0;
      List<GalleryImage> images = archiveDownloadService.getUnpackedImages(archive.gid);

      toRoute(
        Routes.read,
        arguments: ReadPageInfo(
          mode: ReadMode.archive,
          gid: archive.gid,
          token: archive.token,
          galleryTitle: archive.title,
          galleryUrl: archive.galleryUrl,
          initialIndex: readIndexRecord,
          currentImageIndex: readIndexRecord,
          pageCount: images.length,
          isOriginal: archive.isOriginal,
          readProgressRecordStorageKey: storageKey,
          images: images,
          useSuperResolution: superResolutionService.get(archive.gid, SuperResolutionType.archive) != null,
        ),
      );
    }
  }

  Future<void> handleTapHH() async {
    if (!UserSetting.hasLoggedIn()) {
      showLoginToast();
      return;
    }

    String? resolution = await Get.dialog(EHDownloadHHDialog(archivePageUrl: state.galleryDetails!.archivePageUrl));
    if (resolution == null) {
      return;
    }

    Log.info('HH Download: ${state.galleryUrl.gid}, resolution: $resolution');

    String result;
    try {
      result = await EHRequest.requestHHDownload(
        url: state.galleryDetails!.archivePageUrl,
        resolution: resolution,
        parser: EHSpiderParser.downloadHHPage2Result,
      );
    } on DioException catch (e) {
      Log.error('H@H download error', e.message);
      snack('failed'.tr, e.message ?? '');
      return;
    } on EHSiteException catch (e) {
      Log.error('H@H download error', e.message);
      snack('failed'.tr, e.message);
      return;
    } catch (e, s) {
      Log.error('H@H download error', e, s);
      snack('failed'.tr, e.toString());
      return;
    }

    toast(result, isShort: false);
  }

  void searchSimilar() {
    if (state.galleryDetails?.rawTitle == null) {
      return;
    }
    search('title:"${state.galleryDetails!.rawTitle.replaceAll(RegExp(r'\[.*?\]|\(.*?\)|{.*?}'), '').trim()}"');
  }

  void searchUploader() {
    if (state.galleryDetails?.uploader == null && state.gallery?.uploader == null) {
      return;
    }
    search('uploader:"${state.galleryDetails?.uploader ?? state.gallery!.uploader}"');
  }

  void search(String str) {
    newSearch(str, true);
  }

  Future<void> handleTapTorrent() async {
    Get.dialog(EHGalleryTorrentsDialog(gid: state.galleryUrl.gid, token: state.galleryUrl.token));
  }

  Future<void> handleTapStatistic() async {
    Get.dialog(EHGalleryStatDialog(gid: state.galleryUrl.gid, token: state.galleryUrl.token));
  }

  Future<void> handleTapJumpButton() async {
    if (state.galleryDetails == null) {
      return;
    }

    int? pageIndex = await Get.dialog(
      JumpPageDialog(
        totalPageNo: state.galleryDetails!.thumbnailsPageCount,
        currentNo: 1,
      ),
    );

    if (pageIndex != null) {
      toRoute(Routes.thumbnails, arguments: pageIndex);
    }
  }

  void handleTapHistoryButton(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => EHGalleryHistoryDialog(
        currentGalleryTitle: state.gallery?.title ?? state.galleryDetails?.japaneseTitle ?? state.galleryDetails?.rawTitle ?? '',
        parentUrl: state.galleryDetails?.parentGalleryUrl,
        childrenGallerys: state.galleryDetails?.childrenGallerys,
      ),
    );
  }

  Future<void> shareGallery() async {
    Log.info('Share gallery:${state.galleryUrl}');

    if (GetPlatform.isDesktop) {
      await FlutterClipboard.copy(state.galleryUrl.url);
      toast('hasCopiedToClipboard'.tr);
      return;
    }

    Share.share(
      state.galleryUrl.url,
      sharePositionOrigin: Rect.fromLTWH(0, 0, fullScreenWidth, screenHeight * 2 / 3),
    );
  }

  Future<void> handleTapDeleteDownload(BuildContext context, int gid, DownloadPageGalleryType downloadPageGalleryType) async {
    bool? result = await showDialog(
      context: context,
      builder: (_) => EHDialog(title: 'delete'.tr + '?'),
    );

    if (result == null || !result) {
      return;
    }

    if (downloadPageGalleryType == DownloadPageGalleryType.download) {
      galleryDownloadService.deleteGalleryByGid(gid);
    }

    if (downloadPageGalleryType == DownloadPageGalleryType.archive) {
      archiveDownloadService.deleteArchiveByGid(gid);
    }
  }

  Future<void> handleAddTag(BuildContext context) async {
    if (state.galleryDetails == null) {
      return;
    }

    if (!checkLogin()) {
      return;
    }

    String? newTag = await showDialog(context: context, builder: (_) => EHAddTagDialog());
    if (newTag == null) {
      return;
    }

    Log.info('Add tag:$newTag');

    toast('${'addTag'.tr}: $newTag');

    String? errMsg;
    try {
      errMsg = await EHRequest.voteTag(
        state.galleryUrl.gid,
        state.galleryUrl.token,
        UserSetting.ipbMemberId.value!,
        state.apikey!,
        newTag,
        true,
        parser: EHSpiderParser.voteTagResponse2ErrorMessage,
      );
    } on DioException catch (e) {
      Log.error('addTagFailed'.tr, e.message);
      snack('addTagFailed'.tr, e.message ?? '');
      return;
    } on EHSiteException catch (e) {
      Log.error('addTagFailed'.tr, e.message);
      snack('addTagFailed'.tr, e.message);
      return;
    } catch (e, s) {
      Log.error('addTagFailed'.tr, e, s);
      snack('addTagFailed'.tr, e.toString());
      return;
    }

    if (!isEmptyOrNull(errMsg)) {
      snack('addTagFailed'.tr, errMsg!, longDuration: true);
      return;
    } else {
      toast('addTagSuccess'.tr);
      _removeCache();
    }
  }

  void goToReadPage([int? forceIndex]) {
    String storageKey = 'readIndexRecord::${state.galleryUrl.gid}';
    int readIndexRecord = storageService.read(storageKey) ?? 0;

    /// online
    if (galleryDownloadService.galleryDownloadInfos[state.galleryUrl.gid]?.downloadProgress == null) {
      toRoute(
        Routes.read,
        arguments: ReadPageInfo(
          mode: ReadMode.online,
          gid: state.galleryUrl.gid,
          token: state.galleryUrl.token,
          galleryTitle: state.gallery?.title ?? state.galleryDetails!.japaneseTitle ?? state.galleryDetails!.rawTitle,
          galleryUrl: state.galleryUrl.url,
          initialIndex: forceIndex ?? readIndexRecord,
          currentImageIndex: forceIndex ?? readIndexRecord,
          readProgressRecordStorageKey: storageKey,
          pageCount: state.galleryDetails?.pageCount ?? state.gallery!.pageCount!,
          useSuperResolution: false,
        ),
      )?.then((_) => updateSafely([readButtonId]));
      return;
    }

    if (ReadSetting.useThirdPartyViewer.isTrue && ReadSetting.thirdPartyViewerPath.value != null) {
      /// use GalleryDownloadedData's title
      GalleryDownloadedData gallery = galleryDownloadService.gallerys.firstWhere((g) => g.gid == state.galleryUrl.gid);
      openThirdPartyViewer(galleryDownloadService.computeGalleryDownloadPath(gallery.title, gallery.gid));
      return;
    }

    toRoute(
      Routes.read,
      arguments: ReadPageInfo(
        mode: ReadMode.downloaded,
        gid: state.galleryUrl.gid,
        token: state.galleryUrl.token,
        galleryTitle: state.gallery?.title ?? state.galleryDetails!.japaneseTitle ?? state.galleryDetails!.rawTitle,
        galleryUrl: state.galleryUrl.url,
        initialIndex: forceIndex ?? readIndexRecord,
        currentImageIndex: forceIndex ?? readIndexRecord,
        readProgressRecordStorageKey: storageKey,
        pageCount: state.galleryDetails?.pageCount ?? state.gallery!.pageCount!,
        useSuperResolution: superResolutionService.get(state.galleryUrl.gid, SuperResolutionType.gallery) != null,
      ),
    )?.then((_) => updateSafely([readButtonId]));
  }

  int getReadIndexRecord() {
    return storageService.read('readIndexRecord::${state.galleryUrl.gid}') ?? 0;
  }

  Future<({GalleryDetail galleryDetails, String apikey})> _getDetailsWithRedirectAndFallback({bool useCache = true}) async {
    final String? firstLink;
    final String secondLink;

    /// 1. if redirect is enabled, try EH site first for EX link
    /// 2. if a gallery can't be found in EH site, it may be moved into EX site
    if (state.galleryUrl.url.contains(EHConsts.EXIndex)) {
      if (EHSetting.redirect2Eh.isTrue && !_galleryOnlyInExSite()) {
        firstLink = state.galleryUrl.url.replaceFirst(EHConsts.EXIndex, EHConsts.EHIndex);
        secondLink = state.galleryUrl.url;
      } else {
        firstLink = null;
        secondLink = state.galleryUrl.url;
      }
    } else {
      firstLink = state.galleryUrl.url;
      secondLink = state.galleryUrl.url.replaceFirst(EHConsts.EHIndex, EHConsts.EXIndex);
    }

    /// if we can't find gallery via firstLink, try second link
    EHSiteException? firstException;
    if (!isEmptyOrNull(firstLink)) {
      Log.verbose('Try to find gallery via firstLink: $firstLink');
      try {
        ({GalleryDetail galleryDetails, String apikey}) detailPageInfo = await EHRequest.requestDetailPage<({GalleryDetail galleryDetails, String apikey})>(
          galleryUrl: firstLink!,
          parser: EHSpiderParser.detailPage2GalleryAndDetailAndApikey,
          useCacheIfAvailable: useCache,
        );
        state.galleryUrl = state.galleryUrl.copyWith(isEH: true);
        state.gallery?.galleryUrl = state.galleryUrl;
        state.galleryDetails?.galleryUrl = state.galleryUrl;
        return detailPageInfo;
      } on EHSiteException catch (e) {
        Log.verbose('Can\'t find gallery, firstLink: $firstLink, reason: ${e.message}');
        firstException = e;
      }
    }

    try {
      Log.verbose('Try to find gallery via secondLink: $secondLink');
      ({GalleryDetail galleryDetails, String apikey}) detailPageInfo = await EHRequest.requestDetailPage<({GalleryDetail galleryDetails, String apikey})>(
        galleryUrl: secondLink,
        parser: EHSpiderParser.detailPage2GalleryAndDetailAndApikey,
        useCacheIfAvailable: useCache,
      );
      state.galleryUrl = state.galleryUrl.copyWith(isEH: false);
      state.gallery?.galleryUrl = state.galleryUrl;
      state.galleryDetails?.galleryUrl = state.galleryUrl;
      return detailPageInfo;
    } on EHSiteException catch (e) {
      Log.verbose('Can\'t find gallery, secondLink: $secondLink, reason: ${e.message}');
      throw firstException ?? e;
    }
  }

  bool _galleryOnlyInExSite() {
    if (state.gallery == null) {
      return false;
    }

    if (state.gallery!.tags.isEmpty) {
      return false;
    }

    return state.gallery!.tags.values.any((tagList) => tagList.any((tag) => tag.tagData.key == 'lolicon'));
  }

  /// some field in [gallery] sometimes is null
  List<Object> _judgeUpdateIds() {
    List<Object> updateIds = [detailsId, loadingStateId];

    if (state.gallery == null) {
      updateIds.add(galleryId);
      updateIds.add(languageId);
      updateIds.add(pageCountId);
      updateIds.add(uploaderId);
      updateIds.add(favoriteId);
      updateIds.add(ratingId);
      updateIds.add(pageCountId);
      return updateIds;
    }

    /// language is null in Minimal mode
    if (state.galleryDetails?.language != state.gallery?.language) {
      updateIds.add(languageId);
    }

    /// page count is null in favorite page
    if (state.galleryDetails?.pageCount != state.gallery?.pageCount) {
      updateIds.add(pageCountId);
    }

    /// uploader info is null in favorite page
    if (state.galleryDetails?.uploader != state.gallery?.uploader) {
      updateIds.add(uploaderId);
    }

    /// favorite info is null in ranklist page
    if (state.galleryDetails?.isFavorite != state.gallery?.isFavorite ||
        state.galleryDetails?.favoriteTagIndex != state.gallery?.favoriteTagIndex ||
        state.galleryDetails?.favoriteTagName != state.gallery?.favoriteTagName) {
      updateIds.add(favoriteId);
    }

    /// rating info is null in ranklist page
    if (state.galleryDetails?.hasRated != state.gallery?.hasRated || state.galleryDetails?.rating != state.gallery?.rating) {
      updateIds.add(ratingId);
    }

    return updateIds;
  }

  void _addColor2WatchedTags(LinkedHashMap<String, List<GalleryTag>> fullTags) {
    for (List<GalleryTag> tags in fullTags.values) {
      for (GalleryTag tag in tags) {
        if (tag.color != null || tag.backgroundColor != null) {
          continue;
        }

        TagSet? tagSet = MyTagsSetting.getOnlineTagSetByTagData(tag.tagData);
        if (tagSet == null) {
          continue;
        }

        tag.backgroundColor = tagSet.backgroundColor ?? const Color(0xFF3377FF);
        tag.color = tagSet.backgroundColor == null
            ? const Color(0xFFF1F1F1)
            : ThemeData.estimateBrightnessForColor(tagSet.backgroundColor!) == Brightness.light
                ? const Color.fromRGBO(9, 9, 9, 1)
                : const Color(0xFFF1F1F1);
      }
    }
  }

  void _removeCache() {
    EHRequest.removeCacheByGalleryUrlAndPage(state.galleryUrl.url, 0);
  }
}
