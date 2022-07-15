import 'package:jhentai/src/pages/watched/watched_page_state.dart';

import '../../consts/eh_consts.dart';
import '../../network/eh_request.dart';
import '../../utils/eh_spider_parser.dart';
import '../../utils/log.dart';
import '../base/base_page_logic.dart';

class WatchedPageLogic extends BasePageLogic {
  @override
  final String pageId = 'pageId';
  @override
  final String appBarId = 'appBarId';
  @override
  final String bodyId = 'bodyId';
  @override
  final String refreshStateId = 'refreshStateId';
  @override
  final String loadingStateId = 'loadingStateId';

  @override
  int get tabIndex => 5;

  @override
  final WatchedPageState state = WatchedPageState();

  @override
  Future<List<dynamic>> getGallerysAndPageInfoByPage(int pageNo) async {
    Log.info('get watched data, pageNo:$pageNo', false);

    List<dynamic> gallerysAndPageInfo = await EHRequest.requestGalleryPage(
      url: EHConsts.EWatched,
      pageNo: pageNo,
      parser: EHSpiderParser.galleryPage2GalleryListAndPageInfo,
    );

    await translateGalleryTagsIfNeeded(gallerysAndPageInfo[0]);
    return gallerysAndPageInfo;
  }

  void updateBody() {
    update([bodyId]);
  }
}