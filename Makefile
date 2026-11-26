TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

# ------------------------------------------------------------------ 主插件
TWEAK_NAME = WCTGPOPUP

WCTGPOPUP_FILES = Tweak.xm \
                  WCTGPopupCenter.m \
                  WCTGPopupView.m \
                  WCTGPConfig.m

WCTGPOPUP_CFLAGS = -fobjc-arc -Wno-unused-function -Wno-deprecated-declarations \
                   -I$(THEOS_PROJECT_DIR)

# 只注入微信
WCTGPOPUP_INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS_MAKE_PATH)/tweak.mk

# ------------------------------------------------------------------ 设置面板
BUNDLE_NAME = WCTGPOPUPPrefs

WCTGPOPUPPrefs_FILES = prefs/WCTGPOPUPRootListController.m
WCTGPOPUPPrefs_INSTALL_PATH = /Library/PreferenceBundles
WCTGPOPUPPrefs_PRIVATE_FRAMEWORKS = Preferences
WCTGPOPUPPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations \
                        -I$(THEOS_PROJECT_DIR)
WCTGPOPUPPrefs_RESOURCE_FILES = prefs/Root.plist

include $(THEOS_MAKE_PATH)/bundle.mk

# 设置里改完立刻生效：通知插件重载 + 重启设置
after-install::
	install.exec "killall -9 WeChat || true"
	install.exec "killall -9 Preferences || true"
