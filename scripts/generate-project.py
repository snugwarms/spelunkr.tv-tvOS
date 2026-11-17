#!/usr/bin/env python3
"""Generate the checked-in Xcode project without XcodeGen or third-party dependencies."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
objects = {}

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def obj(name, value):
    objects[uid(name)] = value
    return uid(name)

def quote(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'

def refs(items):
    return '(' + ', '.join(items) + (',' if items else '') + ')'

app_files = sorted((root / 'App').glob('*.swift'))
test_files = sorted((root / 'UITests').glob('*.swift'))
file_refs, source_builds = [], []
for file in app_files:
    path = str(file.relative_to(root))
    ref = obj(path, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(path)}; sourceTree = SOURCE_ROOT; }}')
    file_refs.append(ref)
    source_builds.append(obj('build:' + path, f'{{isa = PBXBuildFile; fileRef = {ref}; }}'))

test_refs, test_builds = [], []
for file in test_files:
    path = str(file.relative_to(root))
    ref = obj(path, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(path)}; sourceTree = SOURCE_ROOT; }}')
    test_refs.append(ref)
    test_builds.append(obj('build:' + path, f'{{isa = PBXBuildFile; fileRef = {ref}; }}'))

# Compile the real caption engine in the test runner to exercise native tracks without test hooks in the app.
for path in ('App/LiveCaptions.swift', 'App/PlaybackAudioTap.swift'):
    test_builds.append(obj('test-build:' + path, f'{{isa = PBXBuildFile; fileRef = {uid(path)}; }}'))
test_resource_builds = []
for file in sorted((root / 'UITests/Fixtures').glob('*')):
    if not file.is_file(): continue
    path = str(file.relative_to(root))
    ref = obj(path, f'{{isa = PBXFileReference; lastKnownFileType = file; path = {quote(path)}; sourceTree = SOURCE_ROOT; }}')
    test_refs.append(ref)
    test_resource_builds.append(obj('build:' + path, f'{{isa = PBXBuildFile; fileRef = {ref}; }}'))

asset_ref = obj('assets', '{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = App/Assets.xcassets; sourceTree = SOURCE_ROOT; }')
asset_build = obj('build:assets', f'{{isa = PBXBuildFile; fileRef = {asset_ref}; }}')
product = obj('product', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = Spelunkr.app; sourceTree = BUILT_PRODUCTS_DIR; }')
test_product = obj('test-product', '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = SpelunkrUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }')
package = obj('package', '{isa = XCLocalSwiftPackageReference; relativePath = .; }')
package_product = obj('package-product', f'{{isa = XCSwiftPackageProductDependency; package = {package}; productName = SpelunkrCore; }}')
package_build = obj('package-build', f'{{isa = PBXBuildFile; productRef = {package_product}; }}')
test_package_build = obj('test-package-build', f'{{isa = PBXBuildFile; productRef = {package_product}; }}')

app_group = obj('app-group', f'{{isa = PBXGroup; name = App; children = {refs(file_refs + [asset_ref])}; sourceTree = "<group>"; }}')
tests_group = obj('tests-group', f'{{isa = PBXGroup; name = UITests; children = {refs(test_refs)}; sourceTree = "<group>"; }}')
products_group = obj('products-group', f'{{isa = PBXGroup; name = Products; children = {refs([product, test_product])}; sourceTree = "<group>"; }}')
main_group = obj('main-group', f'{{isa = PBXGroup; children = {refs([app_group, tests_group, products_group])}; sourceTree = "<group>"; }}')

sources = obj('sources', f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(source_builds)}; runOnlyForDeploymentPostprocessing = 0; }}')
resources = obj('resources', f'{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs([asset_build])}; runOnlyForDeploymentPostprocessing = 0; }}')
frameworks = obj('frameworks', f'{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {refs([package_build])}; runOnlyForDeploymentPostprocessing = 0; }}')
test_sources = obj('test-sources', f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(test_builds)}; runOnlyForDeploymentPostprocessing = 0; }}')
test_frameworks = obj('test-frameworks', f'{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {refs([test_package_build])}; runOnlyForDeploymentPostprocessing = 0; }}')
test_resources = obj('test-resources', f'{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs(test_resource_builds)}; runOnlyForDeploymentPostprocessing = 0; }}')

common = {
    'CLANG_ENABLE_MODULES': 'YES', 'SWIFT_VERSION': '5.0',
    'SDKROOT': 'appletvos', 'TVOS_DEPLOYMENT_TARGET': '17.0',
    'SUPPORTED_PLATFORMS': 'appletvos appletvsimulator', 'TARGETED_DEVICE_FAMILY': '3',
    'CODE_SIGN_STYLE': 'Automatic', 'GENERATE_INFOPLIST_FILE': 'YES',
    'SWIFT_EMIT_LOC_STRINGS': 'YES', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES',
    'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
}
app_settings = {
    **common, 'PRODUCT_BUNDLE_IDENTIFIER': 'tv.spelunkr.community', 'PRODUCT_NAME': '$(TARGET_NAME)',
    'MARKETING_VERSION': '0.1.5', 'CURRENT_PROJECT_VERSION': '6',
    'INFOPLIST_KEY_CFBundleDisplayName': 'Spelunkr',
    'INFOPLIST_FILE': 'App/Info.plist',
    'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES', 'INFOPLIST_KEY_UIUserInterfaceStyle': 'Dark',
    'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents': 'YES',
    'ASSETCATALOG_COMPILER_APPICON_NAME': 'App Icon & Top Shelf Image',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor',
}
test_settings = {
    **common, 'PRODUCT_BUNDLE_IDENTIFIER': 'tv.spelunkr.community.uitests',
    'PRODUCT_NAME': '$(TARGET_NAME)', 'TEST_TARGET_NAME': 'Spelunkr',
}

def configs(name, settings):
    ids = []
    for mode in ('Debug', 'Release'):
        config = {**settings, 'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode == 'Debug' else '-O',
                  'ONLY_ACTIVE_ARCH': 'YES' if mode == 'Debug' else 'NO'}
        if mode == 'Debug': config['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG $(inherited)'
        config['DEBUG_INFORMATION_FORMAT'] = 'dwarf' if mode == 'Debug' else 'dwarf-with-dsym'
        value = ' '.join(f'{key} = {quote(val)};' for key, val in config.items())
        ids.append(obj(name + mode, f'{{isa = XCBuildConfiguration; buildSettings = {{{value}}}; name = {mode}; }}'))
    return obj(name + '-list', f'{{isa = XCConfigurationList; buildConfigurations = {refs(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')

app_configs = configs('app', app_settings)
test_configs = configs('tests', test_settings)
project_configs = configs('project', {'ALWAYS_SEARCH_USER_PATHS': 'NO', 'CLANG_ENABLE_MODULES': 'YES'})
target = obj('app-target', f'{{isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {refs([sources, frameworks, resources])}; buildRules = (); dependencies = (); name = Spelunkr; packageProductDependencies = {refs([package_product])}; productName = Spelunkr; productReference = {product}; productType = "com.apple.product-type.application"; }}')
proxy = obj('target-proxy', f'{{isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = Spelunkr; }}')
dependency = obj('test-dependency', f'{{isa = PBXTargetDependency; target = {target}; targetProxy = {proxy}; }}')
test_target = obj('test-target', f'{{isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {refs([test_sources, test_frameworks, test_resources])}; buildRules = (); dependencies = {refs([dependency])}; name = SpelunkrUITests; packageProductDependencies = {refs([package_product])}; productName = SpelunkrUITests; productReference = {test_product}; productType = "com.apple.product-type.bundle.ui-testing"; }}')
project = obj('project', f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 2600; LastUpgradeCheck = 2600; TargetAttributes = {{{target} = {{CreatedOnToolsVersion = 26.0; }}; {test_target} = {{CreatedOnToolsVersion = 26.0; TestTargetID = {target}; }}; }}; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main_group}; packageReferences = {refs([package])}; productRefGroup = {products_group}; projectDirPath = ""; projectRoot = ""; targets = {refs([target, test_target])}; }}')

project_dir = root / 'Spelunkr.xcodeproj'
project_dir.mkdir(exist_ok=True)
body = '\n'.join(f'\t\t{key} = {value};' for key, value in objects.items())
(project_dir / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + body + f'\n\t}};\n\trootObject = {project};\n}}\n')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Spelunkr.app" BlueprintName="Spelunkr" ReferencedContainer="container:Spelunkr.xcodeproj"/></BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
    <TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="SpelunkrUITests.xctest" BlueprintName="SpelunkrUITests" ReferencedContainer="container:Spelunkr.xcodeproj"/></TestableReference>
  </Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Spelunkr.app" BlueprintName="Spelunkr" ReferencedContainer="container:Spelunkr.xcodeproj"/></BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Spelunkr.app" BlueprintName="Spelunkr" ReferencedContainer="container:Spelunkr.xcodeproj"/></BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
schemes = project_dir / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
(schemes / 'Spelunkr.xcscheme').write_text(scheme)
print('Generated Spelunkr.xcodeproj')
