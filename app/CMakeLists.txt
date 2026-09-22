cmake_minimum_required(VERSION 3.20)
project(plasmai-app VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Svg Core QuickControls2)

# QtDBus: idle detection (org.freedesktop.ScreenSaver) and native notifications
# (org.freedesktop.Notifications) on a real Linux/Plasma session — desktop
# Linux and Plasma Mobile devices both qualify, Android does not.
if(NOT ANDROID)
    find_package(Qt6 COMPONENTS DBus QUIET)
endif()

# KF6 — available for desktop and cross-compiled Android builds
find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
if(CMAKE_CROSSCOMPILING)
    # For Android, only Kirigami is needed (I18n pulls in host Qt6Core)
    find_package(KF6 COMPONENTS Kirigami QUIET)
else()
    find_package(KF6 COMPONENTS Kirigami I18n CoreAddons QUIET)
endif()

# Qt6Keychain: use native when available, file-based fallback for Android
if(NOT CMAKE_CROSSCOMPILING)
    find_package(Qt6Keychain REQUIRED)
endif()

qt_add_executable(plasmai-app
    main.cpp
    plasmai-app.qrc
    addons/yearmodel.cpp
    addons/monthmodel.cpp
    addons/infinitecalendarviewmodel.cpp
)

if(ANDROID)
    set_property(TARGET plasmai-app APPEND PROPERTY
        QT_ANDROID_PACKAGE_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/android"
    )
    set_target_properties(plasmai-app PROPERTIES
        QT_ANDROID_PACKAGE_NAME "com.github.shrippen.plasmai"
        QT_ANDROID_VERSION_NAME "2.0.0"
        QT_ANDROID_VERSION_CODE "200"
        QT_ANDROID_MIN_SDK_VERSION "28"
        QT_ANDROID_TARGET_SDK_VERSION "34"
    )
    # OpenSSL for HTTPS (Qt QML XMLHttpRequest needs it)
    # Pre-built libs from KDAB/android_openssl
    set(OPENSSL_ANDROID_DIR "${CMAKE_CURRENT_SOURCE_DIR}/libs/openssl")
    if(EXISTS "${OPENSSL_ANDROID_DIR}")
        set(OPENSSL_LIBS "${OPENSSL_ANDROID_DIR}/arm64-v8a/libcrypto_3.so;${OPENSSL_ANDROID_DIR}/arm64-v8a/libssl_3.so")
    else()
        set(OPENSSL_LIBS "")
    endif()
    # libomp.so is needed by Kirigami QML plugin on Android
    find_library(LIBOMP_PATH omp HINTS "${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/*/lib/linux/aarch64")
    if(NOT LIBOMP_PATH)
        # Fallback: look in known NDK path
        file(GLOB LIBOMP_CANDIDATES "${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/*/lib/linux/aarch64/libomp.so")
        if(LIBOMP_CANDIDATES)
            list(GET LIBOMP_CANDIDATES 0 LIBOMP_PATH)
        endif()
    endif()
    if(LIBOMP_PATH)
        set_target_properties(plasmai-app PROPERTIES
            QT_ANDROID_EXTRA_LIBS "${OPENSSL_LIBS};${LIBOMP_PATH}"
        )
    elseif(OPENSSL_LIBS)
        set_target_properties(plasmai-app PROPERTIES
            QT_ANDROID_EXTRA_LIBS "${OPENSSL_LIBS}"
        )
    endif()
endif()

target_link_libraries(plasmai-app PRIVATE
    Qt6::Quick
    Qt6::Svg
    Qt6::Core
    Qt6::QuickControls2
)

if(NOT CMAKE_CROSSCOMPILING AND TARGET Qt6Keychain::Qt6Keychain)
    target_include_directories(plasmai-app PRIVATE /usr/include/qt6keychain)
    target_link_libraries(plasmai-app PRIVATE Qt6Keychain::Qt6Keychain)
endif()

if(TARGET Qt6::DBus)
    message(STATUS "Qt6::DBus found — building with idle detection + native notifications")
    target_compile_definitions(plasmai-app PRIVATE HAVE_QTDBUS)
    target_link_libraries(plasmai-app PRIVATE Qt6::DBus)
endif()

option(PLASMAI_TEST_DRIVER "Compile the scripted UI test driver (development only)" OFF)
if(PLASMAI_TEST_DRIVER)
    target_compile_definitions(plasmai-app PRIVATE PLASMAI_TEST_DRIVER)
endif()

if(KF6_FOUND)
    message(STATUS "KF6 found — building with Kirigami")
    target_compile_definitions(plasmai-app PRIVATE HAVE_KF6)
    target_link_libraries(plasmai-app PRIVATE KF6::Kirigami)
    if(TARGET KF6::I18n)
        target_link_libraries(plasmai-app PRIVATE KF6::I18n)
    endif()
    if(TARGET KF6::I18nQml)
        target_link_libraries(plasmai-app PRIVATE KF6::I18nQml)
    endif()
    if(TARGET KF6::CoreAddons)
        target_link_libraries(plasmai-app PRIVATE KF6::CoreAddons)
        target_compile_definitions(plasmai-app PRIVATE HAVE_KF6_COREADDONS)
    endif()
    # Ensure Kirigami QML plugins are found during Android deployment
    if(ANDROID AND IS_DIRECTORY "$ENV{HOME}/kf6-android/lib/qml")
        set_target_properties(plasmai-app PROPERTIES
            _qt_native_qml_import_paths "$ENV{HOME}/kf6-android/lib/qml")
    endif()
else()
    message(STATUS "KF6 not found — building without Kirigami")
endif()

# Translations for Plasma Mobile / desktop Linux: compile translate/*.po into
# <lang>/LC_MESSAGES/plasmai.mo (KLocalizedString domain "plasmai"). Android has
# no gettext runtime and bundles JSON catalogs instead (app/i18n, see main.cpp).
if(NOT ANDROID)
    include(GNUInstallDirs)
    find_program(MSGFMT_EXECUTABLE msgfmt)
    if(MSGFMT_EXECUTABLE)
        file(GLOB PLASMAI_PO_FILES "${CMAKE_CURRENT_SOURCE_DIR}/../translate/*.po")
        set(PLASMAI_MO_FILES)
        foreach(po ${PLASMAI_PO_FILES})
            get_filename_component(lang ${po} NAME_WE)
            set(mo "${CMAKE_CURRENT_BINARY_DIR}/locale/${lang}/LC_MESSAGES/plasmai.mo")
            add_custom_command(
                OUTPUT ${mo}
                COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/locale/${lang}/LC_MESSAGES"
                COMMAND ${MSGFMT_EXECUTABLE} -o ${mo} ${po}
                DEPENDS ${po}
                COMMENT "Compiling ${lang} translation"
            )
            list(APPEND PLASMAI_MO_FILES ${mo})
            install(FILES ${mo} DESTINATION ${CMAKE_INSTALL_LOCALEDIR}/${lang}/LC_MESSAGES)
        endforeach()
        add_custom_target(plasmai-translations ALL DEPENDS ${PLASMAI_MO_FILES})
        add_dependencies(plasmai-app plasmai-translations)
        target_compile_definitions(plasmai-app PRIVATE
            PLASMAI_BUILD_LOCALE_DIR="${CMAKE_CURRENT_BINARY_DIR}/locale")
    else()
        message(WARNING "msgfmt not found: translations will not be built")
    endif()
endif()

install(TARGETS plasmai-app
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
)
