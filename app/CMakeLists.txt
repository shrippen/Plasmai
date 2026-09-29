cmake_minimum_required(VERSION 3.20)
project(plasmai-app VERSION 2.0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Svg Core QuickControls2 Network)

# QtDBus: idle detection (org.freedesktop.ScreenSaver) and native notifications
# (org.freedesktop.Notifications) on a real Linux/Plasma session — desktop
# Linux and Plasma Mobile devices both qualify, Android does not.
if(NOT ANDROID)
    find_package(Qt6 COMPONENTS DBus QUIET)
endif()

# KF6: only Kirigami. Translations come from JSON catalogs on every platform
# (i18nfallback.cpp), so no KI18n / gettext runtime is needed anywhere.
find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
find_package(KF6 COMPONENTS Kirigami QUIET)

# Qt6Keychain on every platform (Android too): API tokens never go to plain files.
find_package(Qt6Keychain REQUIRED)

# Platform services: one implementation per platform (ROADMAP pillar 5, step 3).
# D-Bus (idle time, notifications) on Linux and Plasma Mobile; not offered elsewhere.
if(TARGET Qt6::DBus AND UNIX AND NOT APPLE AND NOT ANDROID)
    set(PLASMAI_PLATFORM_SOURCES platform/idlewatcher_dbus.cpp platform/notifier_dbus.cpp)
else()
    set(PLASMAI_PLATFORM_SOURCES platform/idlewatcher_none.cpp platform/notifier_none.cpp)
endif()

qt_add_executable(plasmai-app
    main.cpp
    i18nfallback.cpp
    plasmai-app.qrc
    platform/filestore.h
    platform/idlewatcher.h
    platform/networkstatus.h
    platform/notifier.h
    platform/tokenstore.h
    platform/tokenstore.cpp
    platform/useragentnam.h
    ${PLASMAI_PLATFORM_SOURCES}
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
        QT_ANDROID_VERSION_NAME "2.0.1"
        QT_ANDROID_VERSION_CODE "20001"
        QT_ANDROID_MIN_SDK_VERSION "28"
        QT_ANDROID_TARGET_SDK_VERSION "34"
        # Pinned instead of "newest installed": GitHub's runner and F-Droid's buildserver have
        # different SDK packages, and the reproducible build must use the same ones.
        QT_ANDROID_COMPILE_SDK_VERSION "36"
        QT_ANDROID_SDK_BUILD_TOOLS_REVISION "36.0.0"
        QT_ANDROID_LEGACY_PACKAGING ON
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
    Qt6::Network
    Qt6::Svg
    Qt6::Core
    Qt6::QuickControls2
)

target_link_libraries(plasmai-app PRIVATE Qt6Keychain::Qt6Keychain)

if(PLASMAI_PLATFORM_SOURCES MATCHES "_dbus")
    message(STATUS "Qt6::DBus found — building with idle detection + native notifications")
    target_link_libraries(plasmai-app PRIVATE Qt6::DBus)
endif()

option(PLASMAI_TEST_DRIVER "Compile the scripted UI test driver (development only)" OFF)
if(PLASMAI_TEST_DRIVER)
    target_compile_definitions(plasmai-app PRIVATE PLASMAI_TEST_DRIVER)
endif()

# Internal demo (made-up data for screenshots and testing). Never in published builds:
# off by default, on for the test-driver build.
option(PLASMAI_DEMO "Include the internal demo mode (development only)" ${PLASMAI_TEST_DRIVER})
if(PLASMAI_DEMO)
    target_sources(plasmai-app PRIVATE demo.qrc)
    target_compile_definitions(plasmai-app PRIVATE PLASMAI_DEMO)
endif()

if(KF6_FOUND)
    message(STATUS "KF6 found — building with Kirigami")
    target_compile_definitions(plasmai-app PRIVATE HAVE_KF6)
    target_link_libraries(plasmai-app PRIVATE KF6::Kirigami)
    # Ensure Kirigami QML plugins are found during Android deployment: the qml dir of the KF6
    # prefix Kirigami was found in (<prefix>/lib/cmake/KF6Kirigami -> <prefix>/lib/qml).
    get_filename_component(KF6_QML_DIR "${KF6Kirigami_DIR}/../../qml" ABSOLUTE)
    if(ANDROID AND IS_DIRECTORY "${KF6_QML_DIR}")
        set_target_properties(plasmai-app PROPERTIES
            _qt_native_qml_import_paths "${KF6_QML_DIR}")
    endif()
else()
    message(STATUS "KF6 not found — building without Kirigami")
endif()

# Unit tests of the C++ side (plural rules, catalogs): cmake -DPLASMAI_BUILD_TESTS=ON, ctest.
option(PLASMAI_BUILD_TESTS "Build the C++ unit tests" OFF)
if(PLASMAI_BUILD_TESTS AND NOT ANDROID)
    enable_testing()
    find_package(Qt6 REQUIRED COMPONENTS Test)
    qt_add_executable(tst_i18nfallback tests/tst_i18nfallback.cpp i18nfallback.cpp)
    qt_add_resources(tst_i18nfallback "i18n" PREFIX "/i18n" BASE i18n FILES i18n/ru.json i18n/pl.json i18n/fr.json i18n/ja.json i18n/de.json)
    target_include_directories(tst_i18nfallback PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(tst_i18nfallback PRIVATE Qt6::Core Qt6::Test)
    add_test(NAME i18nfallback COMMAND tst_i18nfallback)

    # With a Secret Service in the session: round trip and migration; without: no plain text.
    qt_add_executable(tst_tokenstore tests/tst_tokenstore.cpp platform/tokenstore.cpp)
    target_include_directories(tst_tokenstore PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(tst_tokenstore PRIVATE Qt6::Core Qt6::Test Qt6Keychain::Qt6Keychain)
    # Log to the console and to a file: CI checks the file (Windows passes no test output to ctest).
    add_test(NAME tokenstore COMMAND tst_tokenstore -v2 -o -,txt -o tokenstore.log,txt)
    # A keychain call that blocks must fail the run, not hang it.
    set_tests_properties(tokenstore PROPERTIES TIMEOUT 180)
    if(WIN32)
        # QtKeychain's DLL is not next to the test: without it on PATH Windows shows a
        # "DLL not found" dialog and the test never starts.
        set_tests_properties(tokenstore PROPERTIES ENVIRONMENT_MODIFICATION
            "PATH=path_list_prepend:$<TARGET_FILE_DIR:Qt6Keychain::Qt6Keychain>")
    endif()
    if(APPLE)
        # QtKeychain answers through the main dispatch queue, which only a Core Foundation
        # event loop runs; a QCoreApplication (the GUI-less test) uses the UNIX one unless
        # told otherwise. The app's QGuiApplication runs Core Foundation anyway.
        set_tests_properties(tokenstore PROPERTIES ENVIRONMENT "QT_EVENT_DISPATCHER_CORE_FOUNDATION=1")
    endif()
endif()

install(TARGETS plasmai-app
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
)
