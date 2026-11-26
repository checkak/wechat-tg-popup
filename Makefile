TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

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

after-install::
	install.exec "killall -9 WeChat || true"
