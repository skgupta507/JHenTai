import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/model/gallery.dart';
import 'package:jhentai/src/pages/home/tab_view/widget/gallery_card.dart';
import 'package:jhentai/src/routes/routes.dart';
import 'package:reorderables/reorderables.dart';

import '../../../../config/global_config.dart';
import '../../../../setting/tab_bar_setting.dart';
import '../../../../widget/eh_tab_bar_config_dialog.dart';
import '../../../../widget/eh_sliver_header_delegate.dart';
import '../../../../widget/loading_state_indicator.dart';
import 'gallerys_view_logic.dart';
import 'gallerys_view_state.dart';

final GlobalKey<ExtendedNestedScrollViewState> galleryListKey = GlobalKey<ExtendedNestedScrollViewState>();
final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

class GallerysView extends StatelessWidget {
  final GallerysViewLogic gallerysViewLogic = Get.put(GallerysViewLogic(), permanent: true);
  final GallerysViewState gallerysViewState = Get.find<GallerysViewLogic>().state;

  GallerysView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      endDrawer: _buildDrawer(),
      body: ExtendedNestedScrollView(
        /// use this GlobalKey to get innerController to implement 'scroll to top'
        key: galleryListKey,

        /// this property is needed for TabBar in ExtendedNestedScrollView.
        onlyOneScrollInBody: true,
        floatHeaderSlivers: true,
        headerSliverBuilder: _headerBuilder,
        body: _buildBody(),
      ),
    );
  }

  Widget _buildDrawer() {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: ClipRRect(
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(14)),
          child: SizedBox(
            width: 250,
            child: Drawer(
              child: Column(
                children: [
                  ListTile(
                    tileColor: Get.theme.primaryColorLight,
                    title: Text(
                      'tabBarSetting'.tr,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    trailing: SizedBox(
                      width: 70,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: () =>
                                Get.dialog(const EHTabBarConfigDialog(type: EHTabBarConfigDialogType.addTabBar)),
                            child: const Icon(Icons.add, size: 28, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Obx(() {
                      return ReorderableListView.builder(
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        itemCount: TabBarSetting.configs.length,
                        onReorder: gallerysViewLogic.handleReOrderTab,
                        itemBuilder: (BuildContext context, int index) {
                          return Column(
                            key: Key(TabBarSetting.configs[index].name),
                            children: [
                              Slidable(
                                key: Key(TabBarSetting.configs[index].name),
                                enabled: TabBarSetting.configs[index].isDeleteAble,
                                endActionPane: ActionPane(
                                  motion: const DrawerMotion(),
                                  extentRatio: 0.21,
                                  children: [
                                    SlidableAction(
                                      icon: Icons.delete,
                                      foregroundColor: Colors.white,
                                      backgroundColor: Colors.red,
                                      onPressed: (context) => gallerysViewLogic.handleRemoveTab(index),
                                    )
                                  ],
                                ),
                                child: ListTile(
                                  dense: true,
                                  title: Text(
                                    TabBarSetting.configs[index].name,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                  trailing: TabBarSetting.configs[index].isDeleteAble
                                      ? const Icon(Icons.arrow_forward_ios, size: 16).marginOnly(right: 4)
                                      : null,
                                  onTap: TabBarSetting.configs[index].isEditable
                                      ? () => Get.dialog(
                                            EHTabBarConfigDialog(
                                              tabBarConfig: TabBarSetting.configs[index],
                                              type: EHTabBarConfigDialogType.update,
                                            ),
                                          )
                                      : null,
                                ),
                              ),
                              const Divider(thickness: 0.7, height: 2, indent: 16),
                            ],
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _headerBuilder(BuildContext context, bool innerBoxIsScrolled) {
    return [
      // to absorb the overlapped height (if header is pinned and floating),
      // we must use SliverOverlapAbsorber & SliverOverlapInjector in pair to keep inner scroll view offset right.
      // check https://api.flutter-io.cn/flutter/widgets/NestedScrollView-class.html
      // or [zh-CN] https://book.flutterchina.club/chapter6/nestedscrollview.html
      SliverOverlapAbsorber(
        handle: ExtendedNestedScrollView.sliverOverlapAbsorberHandleFor(context),
        sliver: SliverPersistentHeader(
          pinned: true,
          floating: true,

          /// build AppBar and TabBar.
          /// i used a handy class to avoid write a separate [SliverPersistentHeaderDelegate] class
          delegate: EHSliverHeaderDelegate(
            minHeight: context.mediaQueryPadding.top + GlobalConfig.tabBarHeight,
            maxHeight: context.mediaQueryPadding.top + GlobalConfig.appBarHeight + GlobalConfig.tabBarHeight,

            /// make sure the color changes with theme's change
            otherCondition: Get.theme.appBarTheme.backgroundColor,
            child: Column(
              children: [
                // use Expanded so the AppBar can shrink or expand when scrolling between [minExtent] and [maxExtent]
                Expanded(
                  child: AppBar(
                    centerTitle: true,
                    title: Text('gallery'.tr),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => Get.toNamed(Routes.search),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: GlobalConfig.tabBarHeight,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppBarTheme.of(context).backgroundColor,
                    border: Border(
                      bottom: BorderSide(
                        width: 0.2,
                        color: AppBarTheme.of(context).foregroundColor!,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: GetBuilder<GallerysViewLogic>(builder: (logic) {
                          return TabBar(
                            controller: logic.tabController,
                            isScrollable: true,
                            physics: const BouncingScrollPhysics(),
                            tabs: List.generate(
                              TabBarSetting.configs.length,
                              (index) => Tab(text: TabBarSetting.configs[index].name),
                            ),
                          );
                        }),
                      ),
                      IconButton(
                        icon: Icon(
                          FontAwesomeIcons.bars,
                          color: Get.theme.appBarTheme.actionsIconTheme?.color,
                          size: 20,
                        ),
                        padding: const EdgeInsets.only(bottom: 2),
                        onPressed: () {
                          scaffoldKey.currentState?.openEndDrawer();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildBody() {
    return GetBuilder<GallerysViewLogic>(
      builder: (logic) {
        return TabBarView(
          controller: logic.tabController,
          children: List.generate(
            TabBarSetting.configs.length,
            (tabIndex) => GalleryTabBarView(
              tabIndex: tabIndex,
            ),
          ),
        );
      },
    );
  }
}

class GalleryTabBarView extends StatefulWidget {
  /// the position of the widget
  final int tabIndex;

  const GalleryTabBarView({Key? key, required this.tabIndex}) : super(key: key);

  @override
  _GalleryTabBarViewState createState() => _GalleryTabBarViewState();
}

class _GalleryTabBarViewState extends State<GalleryTabBarView> {
  final GallerysViewLogic gallerysViewLogic = Get.find<GallerysViewLogic>();
  final GallerysViewState gallerysViewState = Get.find<GallerysViewLogic>().state;

  @override
  void initState() {
    if (gallerysViewState.gallerys[widget.tabIndex].isEmpty &&
        gallerysViewState.loadingState[widget.tabIndex] == LoadingState.idle) {
      gallerysViewLogic.handleLoadMore(widget.tabIndex);
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return gallerysViewState.gallerys[widget.tabIndex].isEmpty &&
            gallerysViewState.loadingState[widget.tabIndex] != LoadingState.idle
        ? Center(
            child: LoadingStateIndicator(
              errorTapCallback: () => gallerysViewLogic.handleLoadMore(widget.tabIndex),
              noDataTapCallback: () => gallerysViewLogic.handleRefresh(widget.tabIndex),
              loadingState: gallerysViewState.loadingState[widget.tabIndex],
            ),
          )
        : CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: <Widget>[
              /// generally, we could put a [SliverOverlapInjector] here to take up the height of header.
              /// The collapsed height has been dealt with SliverOverlapAbsorber, so [SliverOverlapInjector] is just
              /// equal to Container(height: SystemBar.height + pinned height in header).
              /// Because i want to place a CupertinoSliverRefreshControl here, but it only works when placed in the first of a
              /// sliver list, so i wrapped it into a SliverPadding with it padding-top equal with [SliverOverlapInjector]'s height.
              SliverPadding(
                padding: EdgeInsets.only(top: context.mediaQueryPadding.top + GlobalConfig.tabBarHeight),
                sliver: CupertinoSliverRefreshControl(
                  refreshTriggerPullDistance: GlobalConfig.refreshTriggerPullDistance,
                  onRefresh: () => gallerysViewLogic.handleRefresh(gallerysViewLogic.tabController.index),
                ),
              ),
              _buildGalleryList(widget.tabIndex),
              SliverPadding(
                padding: EdgeInsets.only(top: 8, bottom: context.mediaQuery.padding.bottom),
                sliver: SliverToBoxAdapter(
                  child: LoadingStateIndicator(
                    errorTapCallback: () => gallerysViewLogic.handleLoadMore(widget.tabIndex),
                    loadingState: gallerysViewState.loadingState[widget.tabIndex],
                  ),
                ),
              ),
            ],
          );
  }

  SliverList _buildGalleryList(int tabIndex) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
        if (index == gallerysViewState.gallerys[tabIndex].length - 1 &&
            gallerysViewState.loadingState[tabIndex] == LoadingState.idle) {
          /// 1. shouldn't call directly, because SliverList is building, if we call [setState] here will cause a exception
          /// that hints circular build.
          /// 2. when callback is called, the SliverGrid's state will call [setState], it'll rebuild all sliver child by index, it means
          /// that this callback will be added again and again! so add a condition to check loadingState so that make sure
          /// the callback is added only once.
          SchedulerBinding.instance?.addPostFrameCallback((timeStamp) {
            gallerysViewLogic.handleLoadMore(tabIndex);
          });
        }
        Gallery gallery = gallerysViewState.gallerys[tabIndex][index];

        return GalleryCard(gallery: gallery, handleTapCard: (gallery) => gallerysViewLogic.handleTapCard(gallery));
      }, childCount: gallerysViewState.gallerys[tabIndex].length),
    );
  }
}
