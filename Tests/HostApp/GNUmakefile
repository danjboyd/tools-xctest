ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
 $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

include $(GNUSTEP_MAKEFILES)/common.make

# A minimal GUI application for the hosted test regressions.
APP_NAME = HostApp
HostApp_OBJC_FILES = HostApp.m

include $(GNUSTEP_MAKEFILES)/application.make
