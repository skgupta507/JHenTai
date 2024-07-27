import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:jhentai/src/database/dao/gallery_history_dao.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/model/search_config.dart';
import 'package:jhentai/src/network/eh_request.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/gallery_download_service.dart';
import 'package:jhentai/src/service/isolate_service.dart';
import 'package:jhentai/src/service/local_block_rule_service.dart';
import 'package:jhentai/src/service/local_config_service.dart';
import 'package:jhentai/src/service/storage_service.dart';
import 'package:jhentai/src/service/tag_translation_service.dart';
import 'package:jhentai/src/service/path_service.dart';
import 'package:jhentai/src/setting/read_setting.dart';
import 'package:jhentai/src/setting/super_resolution_setting.dart';
import 'package:jhentai/src/utils/convert_util.dart';
import 'package:path/path.dart';

import '../database/database.dart';
import '../model/gallery.dart';
import '../pages/search/mixin/search_page_logic_mixin.dart';
import '../setting/download_setting.dart';
import '../setting/preference_setting.dart';
import '../utils/locale_util.dart';
import 'jh_service.dart';
import 'log.dart';
import '../utils/uuid_util.dart';

class AppUpdateService with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  late File file;
  int? fromVersion;
  static const int toVersion = 12;

  List<UpdateHandler> updateHandlers = [
    FirstOpenHandler(),
    StyleSettingMigrateHandler(),
    RenameMetadataHandler(),
    UpdateLocalGalleryPathHandler(),
    UpdateReadDirectionHandler(),
    MigrateSearchConfigHandler(),
    ClearSuperResolutionSettingHandler(),
    MigrateCookieHandler(),
    MigrateLocalFilterTagsHandler(),
    MigrateSearchHistoryV2Handler(),
    MigrateStorageConfigHandler(),
  ];

  @override
  List<JHLifeCircleBean> get initDependencies => super.initDependencies..addAll(updateHandlers.map((h) => h.initDependencies).expand((e) => e));

  @override
  Future<void> doOnInit() async {
    super.onInit();

    file = File(join(pathService.getVisibleDir().path, 'jhentai.version'));
    if (file.existsSync()) {
      fromVersion = int.tryParse(await file.readAsString());
    } else {
      file.create().then((_) => file.writeAsString(toVersion.toString()));
    }

    log.debug('AppUpdateService fromVersion: $fromVersion, toVersion: $toVersion');

    Iterator<UpdateHandler> iterator = updateHandlers.iterator;
    while (iterator.moveNext()) {
      UpdateHandler handler = iterator.current;

      if (!await handler.match(fromVersion, toVersion)) {
        updateHandlers.remove(handler);
      }

      try {
        await handler.onInit();
      } on Exception catch (e) {
        log.error('UpdateHandler $handler onInit error', e);
      }
    }
  }

  @override
  Future<void> doOnReady() async {
    for (UpdateHandler handler in updateHandlers) {
      try {
        await handler.onReady();
      } on Exception catch (e) {
        log.error('UpdateHandler $handler onReady error', e);
      }
    }

    await file.writeAsString(toVersion.toString());
  }
}

abstract interface class UpdateHandler {
  List<JHLifeCircleBean> get initDependencies;

  Future<bool> match(int? fromVersion, int toVersion);

  Future<void> onInit();

  Future<void> onReady();
}

class FirstOpenHandler implements UpdateHandler {
  @override
  List<JHLifeCircleBean> get initDependencies => [];

  @override
  Future<bool> match(int? fromVersion, int toVersion) async {
    return fromVersion == null || (await localConfigService.read(configKey: ConfigEnum.firstOpenInited) == null);
  }

  @override
  Future<void> onInit() async {}

  @override
  Future<void> onReady() async {
    if (preferenceSetting.locale.value.languageCode == 'zh') {
      preferenceSetting.saveEnableTagZHTranslation(true);
      tagTranslationService.fetchDataFromGithub();
    }

    localConfigService.write(configKey: ConfigEnum.firstOpenInited, value: 'true');
  }
}

class StyleSettingMigrateHandler implements UpdateHandler {
  @override
  List<JHLifeCircleBean> get initDependencies => [storageService];

  @override
  Future<bool> match(int? fromVersion, int toVersion) async {
    return fromVersion != null && fromVersion <= 2;
  }

  @override
  Future<void> onInit() async {
    log.info('StyleSettingMigrateHandler onInit');

    Map<String, dynamic>? styleSettingMap = storageService.read<Map<String, dynamic>>(ConfigEnum.styleSetting.key);

    if (styleSettingMap?['locale'] != null) {
      preferenceSetting.saveLanguage(localeCode2Locale(styleSettingMap!['locale']));
    }
    if (styleSettingMap?['enableTagZHTranslation'] != null) {
      preferenceSetting.saveEnableTagZHTranslation(styleSettingMap!['enableTagZHTranslation']);
    }
    if (styleSettingMap?['showR18GImageDirectly'] != null) {
      preferenceSetting.saveShowR18GImageDirectly(styleSettingMap!['showR18GImageDirectly']);
    }
    if (styleSettingMap?['enableQuickSearchDrawerGesture'] != null) {
      preferenceSetting.saveEnableQuickSearchDrawerGesture(styleSettingMap!['enableQuickSearchDrawerGesture']);
    }
    if (styleSettingMap?['hideBottomBar'] != null) {
      preferenceSetting.saveHideBottomBar(styleSettingMap!['hideBottomBar']);
    }
  }

  @override
  Future<void> onReady() async {}
}

class RenameMetadataHandler implements UpdateHandler {
  @override
  List<JHLifeCircleBean> get initDependencies => [downloadSetting];

  @override
  Future<bool> match(int? fromVersion, int toVersion) async {
    if (fromVersion == null) {
      await localConfigService.write(configKey: ConfigEnum.renameDownloadMetadata, value: 'true');
      return false;
    } else {
      return fromVersion <= 3 || (await localConfigService.read(configKey: ConfigEnum.renameDownloadMetadata) == null);
    }
  }

  @override
  Future<void> onInit() async {}

  @override
  Future<void> onReady() async {
    log.info('RenameMetadataHandler onReady');

    Directory downloadDir = Directory(downloadSetting.downloadPath.value);
    if (await downloadDir.exists()) {
      downloadDir.list().listen(
        (entity) async {
          if (entity is! Directory) {
            return;
          }

          File oldGalleryMetadataFile = File(join(entity.path, '.metadata'));
          if (await oldGalleryMetadataFile.exists()) {
            oldGalleryMetadataFile.copy('${entity.path}/${GalleryDownloadService.metadataFileName}');
          }

          File oldArchiveMetadataFile = File(join(entity.path, '.archive.metadata'));
          if (await oldArchiveMetadataFile.exists()) {
            oldArchiveMetadataFile.copy('${entity.path}/${ArchiveDownloadService.metadataFileName}');
          }
        },
        onDone: () async {
          await localConfigService.write(configKey: ConfigEnum.renameDownloadMetadata, value: 'true');
        },
      );
    }
  }
}

class UpdateLocalGalleryPathHandler implements UpdateHandler {
  @override
  List<JHLifeCircleBean> get initDependencies => [downloadSetting];

  @override
  Future<bool> match(int? fromVersion, int toVersion) async {
    return fromVersion != null && fromVersion <= 4;
  }

  @override
  Future<void> onInit() async {
    log.info('UpdateLocalGalleryPathHandler onInit');
    downloadSetting.removeExtraGalleryScanPath(downloadSetting.defaultDownloadPath);
  }

  @override
  Future<void> onReady() async {}
}

class UpdateReadDirectionHandler implements UpdateHandler {
  @override
  List<JHLifeCircleBean> get initDependencies => [];

  @override
  Future<bool> match(int? fromVersion, int toVersion) async {
    return fromVersion != null && fromVersion <= 5;
  }

  @override
  Future<void> onInit() async {}

  @override
  Future<void> onReady() async {
    log.info('UpdateReadDirectionHandler onReady');

    if (readSetting.readDirection.value == ReadDirection.left2rightSinglePageFitWidth) {
      readSetting.saveReadDirection(ReadDirection.left2rightDoubleColumn);
    } else if (readSetting.readDirection.value == ReadDirection.left2rightDoubleColumn) {
      readSetting.saveReadDirection(ReadDirection.left2rightList);
    } else if (readSetting.readDirection.value == ReadDirection.left2rightList) {
      readSetting.saveReadDirection(ReadDirection.right2leftSinglePage);
    } else if (readSetting.readDirection.value == ReadDirection.right2leftSinglePage) {
      readSetting.saveReadDirection(ReadDirection.right2leftDoubleColumn);
    } else if (readSetting.readDirection.value == ReadDirection.right2leftSinglePageFitWidth) {
      readSetting.saveReadDirection(ReadDirection.right2leftList);
    }
  }
}

class MigrateSearchConfigHandler implements UpdateHandler {
  @override
  List<JHLifeCircleBean> get initDependencies => [];

  @override
  Future<bool> match(int? fromVersion, int toVersion) async {
    return fromVersion != null && fromVersion <= 6;
  }

  @override
  Future<void> onInit() async {}

  @override
  Future<void> onReady() async {
    log.info('MigrateSearchConfigHandler onReady');

    Map<String, dynamic>? map = storageService.read('${ConfigEnum.searchConfig.key}: DesktopSearchPageTabLogic') ??
        storageService.read('${ConfigEnum.searchConfig.key}: SearchPageMobileV2Logic');
    if (map != null) {
      storageService.write('${ConfigEnum.searchConfig.key}: ${SearchPageLogicMixin.searchPageConfigKey}', map);
    }
  }
}

class ClearSuperResolutionSettingHandler implements UpdateHandler {
  @override
  List<JHLifeCircleBean> get initDependencies => [superResolutionSetting];

  @override
  Future<bool> match(int? fromVersion, int toVersion) async {
    return fromVersion != null && fromVersion <= 7;
  }

  @override
  Future<void> onInit() async {
    log.info('ClearSuperResolutionSettingHandler onInit');
    superResolutionSetting.saveModelDirectoryPath(null);
  }

  @override
  Future<void> onReady() async {}
}

class MigrateCookieHandler implements UpdateHandler {
  @override
  List<JHLifeCircleBean> get initDependencies => [pathService, ehRequest];

  @override
  Future<bool> match(int? fromVersion, int toVersion) async {
    return fromVersion != null && fromVersion <= 8;
  }

  @override
  Future<void> onInit() async {
    log.info('MigrateCookieHandler onInit');

    File cookieFile = File(join(pathService.getVisibleDir().path, 'cookies', 'ie0_ps1', 'exhentai.org'));
    if (!await cookieFile.exists()) {
      return;
    }

    String str = await cookieFile.readAsString();
    Map<String, Map<String, dynamic>> cookieStrs = json.decode(str).cast<String, Map<String, dynamic>>();

    List<Cookie> cookies = [];
    for (Map<String, dynamic> cookieObject in cookieStrs.values) {
      for (MapEntry<String, dynamic> entry in cookieObject.entries) {
        String key = entry.key;
        String exp = '$key=([^;]+);';
        String? value = RegExp(exp).firstMatch(str)?.group(1);
        if (value != null) {
          cookies.add(Cookie(key, value));
        }
      }
    }

    log.info('MigrateCookieHandler migrate cookies: $cookies');
    ehRequest.storeEHCookies(cookies);
  }

  @override
  Future<void> onReady() async {}
}

class MigrateLocalFilterTagsHandler implements UpdateHandler {
  @override
  List<JHLifeCircleBean> get initDependencies => [storageService, localBlockRuleService];

  @override
  Future<bool> match(int? fromVersion, int toVersion) async {
    return fromVersion != null && fromVersion <= 9;
  }

  @override
  Future<void> onInit() async {
    log.info('MigrateLocalFilterTagsHandler onInit');

    Map<String, dynamic>? map = storageService.read<Map<String, dynamic>>(ConfigEnum.myTagsSetting.key);
    if (map != null) {
      List<TagData> localTagSets = (map['localTagSets'] as List).map((e) => TagData.fromJson(e)).toList();

      List<Future> futures = [];
      for (TagData tagData in localTagSets) {
        futures.add(localBlockRuleService.upsertBlockRule(
          LocalBlockRule(
            groupId: newUUID(),
            target: LocalBlockTargetEnum.gallery,
            attribute: LocalBlockAttributeEnum.tag,
            pattern: LocalBlockPatternEnum.equal,
            expression: '${tagData.namespace}:${tagData.key}',
          ),
        ));

        if (tagData.translatedNamespace != null && tagData.tagName != null) {
          futures.add(localBlockRuleService.upsertBlockRule(
            LocalBlockRule(
              groupId: newUUID(),
              target: LocalBlockTargetEnum.gallery,
              attribute: LocalBlockAttributeEnum.tag,
              pattern: LocalBlockPatternEnum.equal,
              expression: '${tagData.translatedNamespace}:${tagData.tagName}',
            ),
          ));
        }
      }
      await Future.wait(futures);
    }
  }

  @override
  Future<void> onReady() async {}
}

class MigrateSearchHistoryV2Handler implements UpdateHandler {
  @override
  List<JHLifeCircleBean> get initDependencies => [storageService];

  @override
  Future<bool> match(int? fromVersion, int toVersion) async {
    if (fromVersion == null) {
      await localConfigService.write(configKey: ConfigEnum.migrateSearchHistoryV2, value: 'true');
      return false;
    } else {
      return fromVersion <= 10 || (await localConfigService.read(configKey: ConfigEnum.migrateSearchHistoryV2) == null);
    }
  }

  @override
  Future<void> onInit() async {}

  @override
  Future<void> onReady() async {
    log.info('MigrateSearchHistoryV2Handler onReady');

    int totalCount = await GalleryHistoryDao.selectTotalCountOld();
    int pageSize = 400;
    int pageCount = (totalCount / pageSize).ceil();

    log.info('Migrate search config, total count: $totalCount');

    for (int i = 0; i < pageCount; i++) {
      try {
        await Future.delayed(const Duration(milliseconds: 500));

        List<GalleryHistoryData> historys = await GalleryHistoryDao.selectByPageIndexOld(i, pageSize);
        Map<int, Gallery> gid2GalleryMap = await isolateService.run<List<GalleryHistoryData>, Map<int, Gallery>>(
          (historys) => historys.map((h) => Gallery.fromJson(json.decode(h.jsonBody))).groupFoldBy((g) => g.gid, (g1, e) => e),
          historys,
        );

        await GalleryHistoryDao.batchReplaceHistory(
          historys.map(
            (h) {
              return GalleryHistoryV2Data(
                gid: h.gid,
                jsonBody: jsonEncode(gallery2GalleryHistoryModel(gid2GalleryMap[h.gid]!)),
                lastReadTime: h.lastReadTime,
              );
            },
          ).toList(),
        );

        GalleryHistoryDao.deleteAllHistoryOld();

        log.info('Migrate search config for page index $i success!');
      } on Exception catch (e) {
        log.error('Migrate search config for page index $i failed!', e);
      }
    }

    await localConfigService.write(configKey: ConfigEnum.migrateSearchHistoryV2, value: 'true');
  }
}

class MigrateStorageConfigHandler implements UpdateHandler {
  @override
  List<JHLifeCircleBean> get initDependencies => [localConfigService, storageService];

  @override
  Future<bool> match(int? fromVersion, int toVersion) async {
    return fromVersion != null && fromVersion <= 11;
  }

  @override
  Future<void> onInit() async {
    log.info('MigrateStorageConfigHandler onInit');

    List<String>? cookies = storageService.read<List?>(ConfigEnum.ehCookie.key)?.cast<String>().toList();
    if (cookies != null) {
      await localConfigService.write(configKey: ConfigEnum.ehCookie, value: jsonEncode(cookies));
    }

    Map<String, dynamic>? dashboardPageSearchConfigMap = storageService.read('${ConfigEnum.searchConfig.key}: DashboardPageLogic');
    if (dashboardPageSearchConfigMap != null) {
      SearchConfig searchConfig = SearchConfig.fromJson(dashboardPageSearchConfigMap);
      await localConfigService.write(configKey: ConfigEnum.searchConfig, subConfigKey: 'DashboardPageLogic', value: jsonEncode(searchConfig));
    }
    Map<String, dynamic>? searchPageSearchConfigMap = storageService.read('${ConfigEnum.searchConfig.key}: ${SearchPageLogicMixin.searchPageConfigKey}');
    if (searchPageSearchConfigMap != null) {
      SearchConfig searchConfig = SearchConfig.fromJson(searchPageSearchConfigMap);
      await localConfigService.write(
          configKey: ConfigEnum.searchConfig, subConfigKey: SearchPageLogicMixin.searchPageConfigKey, value: jsonEncode(searchConfig));
    }
    Map<String, dynamic>? gallerysPageSearchConfigMap = storageService.read('${ConfigEnum.searchConfig.key}: GallerysPageLogic');
    if (gallerysPageSearchConfigMap != null) {
      SearchConfig searchConfig = SearchConfig.fromJson(gallerysPageSearchConfigMap);
      await localConfigService.write(configKey: ConfigEnum.searchConfig, subConfigKey: 'GallerysPageLogic', value: jsonEncode(searchConfig));
    }
    Map<String, dynamic>? favoritePageSearchConfigMap = storageService.read('${ConfigEnum.searchConfig.key}: FavoritePageLogic');
    if (favoritePageSearchConfigMap != null) {
      SearchConfig searchConfig = SearchConfig.fromJson(favoritePageSearchConfigMap);
      await localConfigService.write(configKey: ConfigEnum.searchConfig, subConfigKey: 'FavoritePageLogic', value: jsonEncode(searchConfig));
    }

    int? downloadPageBodyType = storageService.read(ConfigEnum.downloadPageGalleryType.key);
    if (downloadPageBodyType != null) {
      await localConfigService.write(configKey: ConfigEnum.downloadPageGalleryType, value: downloadPageBodyType.toString());
    }

    List<String>? archiveDisplayGroups = storageService.read(ConfigEnum.displayArchiveGroups.key);
    if (archiveDisplayGroups != null) {
      await localConfigService.write(configKey: ConfigEnum.displayArchiveGroups, value: jsonEncode(archiveDisplayGroups));
    }

    List<String>? galleryDisplayGroups = storageService.read(ConfigEnum.displayGalleryGroups.key);
    if (galleryDisplayGroups != null) {
      await localConfigService.write(configKey: ConfigEnum.displayGalleryGroups, value: jsonEncode(galleryDisplayGroups));
    }

    bool? enableSearchHistoryTranslation = storageService.read(ConfigEnum.enableSearchHistoryTranslation.key);
    if (enableSearchHistoryTranslation != null) {
      await localConfigService.write(configKey: ConfigEnum.enableSearchHistoryTranslation, value: enableSearchHistoryTranslation.toString());
    }
  }

  @override
  Future<void> onReady() async {}
}
