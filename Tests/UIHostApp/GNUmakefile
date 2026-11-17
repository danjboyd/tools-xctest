ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
 $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

include $(GNUSTEP_MAKEFILES)/common.make

# An application with a few kinds of control, for the XCUI regressions.
APP_NAME = UIHostApp
UIHostApp_OBJC_FILES = UIHostApp.m

include $(GNUSTEP_MAKEFILES)/application.make
