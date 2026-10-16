#!/usr/bin/env python3
"""Generate a dependency-free Xcode project; stable IDs preserve Xcode user state."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def q(value):
    if isinstance(value, list):
        return '(' + ', '.join(q(item) for item in value) + ',)'
    return json.dumps(value, ensure_ascii=False)
existing_settings = {}
existing_watch_settings = {}
project_file = ROOT / 'LvLian.xcodeproj/project.pbxproj'
if project_file.exists():
    previous = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(project_file)]))['objects']
    for target in previous.values():
        if target.get('isa') == 'PBXNativeTarget' and target.get('name') in ['LvLian', 'LvLianWatch']:
            configs = previous[target['buildConfigurationList']]['buildConfigurations']
            for config in configs:
                item = previous[config]
                (existing_settings if target['name'] == 'LvLian' else existing_watch_settings)[item['name']] = item.get('buildSettings', {})
objects = []
def add(name, body):
    objects.append(f'\t\t{uid(name)} = {{ {body} }};')
    return uid(name)
def ids(values):
    return '(' + ', '.join(values) + ',)'

sources = sorted((ROOT / 'LvLian').rglob('*.swift'))
refs, builds = [], []
for path in sources:
    rel = path.relative_to(ROOT).as_posix()
    ref = add('ref:' + rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
    refs.append(ref)
    builds.append(add('build:' + rel, f'isa = PBXBuildFile; fileRef = {ref};'))
asset = add('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = LvLian/Assets.xcassets; sourceTree = SOURCE_ROOT;')
asset_build = add('assetsBuild', f'isa = PBXBuildFile; fileRef = {asset};')
privacy = add('privacy', 'isa = PBXFileReference; lastKnownFileType = text.xml; path = LvLian/PrivacyInfo.xcprivacy; sourceTree = SOURCE_ROOT;')
privacy_build = add('privacyBuild', f'isa = PBXBuildFile; fileRef = {privacy};')
product = add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LvLian.app; sourceTree = BUILT_PRODUCTS_DIR;')
watch_refs, watch_builds = [], []
for rel in ['LvLianWatch/LvLianWatchApp.swift', 'LvLian/Core/WatchCue.swift',
            'LvLian/Core/SquatMachine.swift', 'LvLian/Core/TrainingMachine.swift', 'LvLian/Core/Course.swift']:
    ref = uid('ref:' + rel) if rel.startswith('LvLian/') else add('ref:' + rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
    if not rel.startswith('LvLian/'): watch_refs.append(ref)
    watch_builds.append(add('watchBuild:' + rel, f'isa = PBXBuildFile; fileRef = {ref};'))
watch_product = add('watchProduct', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LvLianWatch.app; sourceTree = BUILT_PRODUCTS_DIR;')
watch_asset = add('watchAsset', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = LvLianWatch/Assets.xcassets; sourceTree = SOURCE_ROOT;')
watch_refs.append(watch_asset)
watch_asset_build = add('watchAssetBuild', f'isa = PBXBuildFile; fileRef = {watch_asset};')
watch_sources = add('watchSources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {ids(watch_builds)}; runOnlyForDeploymentPostprocessing = 0;')
watch_privacy_build = add('watchPrivacyBuild', f'isa = PBXBuildFile; fileRef = {privacy};')
watch_resources = add('watchResources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {ids([watch_asset_build, watch_privacy_build])}; runOnlyForDeploymentPostprocessing = 0;')
watch_frameworks = add('watchFrameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
watch_embed_build = add('watchEmbedBuild', f'isa = PBXBuildFile; fileRef = {watch_product}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy,); }};')
watch_embed = add('watchEmbed', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"; dstSubfolderSpec = 16; files = {ids([watch_embed_build])}; name = "Embed Watch Content"; runOnlyForDeploymentPostprocessing = 0;')
watch_proxy = add('watchProxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("watchTarget")}; remoteInfo = LvLianWatch;')
watch_dependency = add('watchDependency', f'isa = PBXTargetDependency; target = {uid("watchTarget")}; targetProxy = {watch_proxy};')
products = add('products' , f'isa = PBXGroup; children = {ids([product, watch_product])}; name = Products; sourceTree = "<group>";')
main = add('main', f'isa = PBXGroup; children = {ids(refs + watch_refs + [asset, privacy, products])}; sourceTree = "<group>";')
sources_phase = add('sourcesPhase', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {ids(builds)}; runOnlyForDeploymentPostprocessing = 0;')
resources_phase = add('resourcesPhase', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {ids([asset_build, privacy_build])}; runOnlyForDeploymentPostprocessing = 0;')
frameworks_phase = add('frameworksPhase', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
project_configs, target_configs, watch_configs = [], [], []
for config in ['Debug', 'Release']:
    project_settings = {
        'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES',
        'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SDKROOT': 'iphoneos',
        'SWIFT_VERSION': '5.0', 'SWIFT_STRICT_CONCURRENCY': 'targeted',
        'DEBUG_INFORMATION_FORMAT': 'dwarf' if config == 'Debug' else 'dwarf-with-dsym',
        'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if config == 'Debug' else '-O',
        'ENABLE_TESTABILITY': 'YES' if config == 'Debug' else 'NO',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG' if config == 'Debug' else '',
    }
    target_settings = {
        'PRODUCT_BUNDLE_IDENTIFIER': 'com.personal.lvlian',
        'PRODUCT_NAME': '$(TARGET_NAME)', 'MARKETING_VERSION': '1.0', 'CURRENT_PROJECT_VERSION': '1',
        'CODE_SIGN_STYLE': 'Automatic', 'GENERATE_INFOPLIST_FILE': 'YES',
        'INFOPLIST_KEY_CFBundleDisplayName': '律练', 'INFOPLIST_KEY_LSApplicationCategoryType': 'public.app-category.healthcare-fitness',
        'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES',
        'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES',
        'INFOPLIST_KEY_UISupportedInterfaceOrientations': 'UIInterfaceOrientationPortrait',
        'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption': 'NO',
        'TARGETED_DEVICE_FAMILY': '1', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
        'SUPPORTS_MACCATALYST': 'NO', 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD': 'NO',
        'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
        'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor',
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
    }
    target_settings.update(existing_settings.get(config, {}))
    target_settings['MARKETING_VERSION'] = '1.10'
    target_settings['CURRENT_PROJECT_VERSION'] = '11'
    watch_settings = {
        'SDKROOT': 'watchos', 'WATCHOS_DEPLOYMENT_TARGET': '10.0',
        'TARGETED_DEVICE_FAMILY': '4', 'SUPPORTED_PLATFORMS': 'watchos watchsimulator',
        'PRODUCT_NAME': '$(TARGET_NAME)',
        'PRODUCT_BUNDLE_IDENTIFIER': target_settings['PRODUCT_BUNDLE_IDENTIFIER'] + '.watchkitapp',
        'DEVELOPMENT_TEAM': target_settings.get('DEVELOPMENT_TEAM', ''),
        'CODE_SIGN_STYLE': 'Automatic', 'GENERATE_INFOPLIST_FILE': 'YES',
        'INFOPLIST_KEY_CFBundleDisplayName': '律练',
        'INFOPLIST_KEY_WKCompanionAppBundleIdentifier': target_settings['PRODUCT_BUNDLE_IDENTIFIER'],
        'INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp': 'YES',
        'INFOPLIST_KEY_NSHealthShareUsageDescription': '深蹲训练时读取 Apple Watch 心率并实时显示。',
        'INFOPLIST_KEY_NSHealthUpdateUsageDescription': '将深蹲保存为功能性力量训练，便于在健康 App 中查看。',
        'INFOPLIST_KEY_WKBackgroundModes': ['workout-processing', 'physical-therapy'],
        'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption': 'NO',
        'INFOPLIST_KEY_UISupportedInterfaceOrientations': 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown',
        'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
        'CODE_SIGN_ENTITLEMENTS': 'LvLianWatch/LvLianWatch.entitlements',
        'SKIP_INSTALL': 'YES', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
    }
    watch_settings.update(existing_watch_settings.get(config, {}))
    watch_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    watch_settings['INFOPLIST_FILE'] = 'LvLianWatch/Info.plist'
    watch_settings['INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp'] = 'YES'
    watch_settings['MARKETING_VERSION'] = target_settings['MARKETING_VERSION']
    watch_settings['CURRENT_PROJECT_VERSION'] = target_settings['CURRENT_PROJECT_VERSION']
    for label, settings, output in [('watch', watch_settings, watch_configs), ('project', project_settings, project_configs), ('target', target_settings, target_configs)]:
        body = ' '.join(f'{k} = {q(v)};' for k, v in settings.items())
        output.append(add(label + config, f'isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {config};'))
project_config = add('projectConfig', f'isa = XCConfigurationList; buildConfigurations = {ids(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target_config = add('targetConfig', f'isa = XCConfigurationList; buildConfigurations = {ids(target_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
watch_config = add('watchConfig', f'isa = XCConfigurationList; buildConfigurations = {ids(watch_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
watch_target = add('watchTarget', f'isa = PBXNativeTarget; buildConfigurationList = {watch_config}; buildPhases = {ids([watch_sources, watch_frameworks, watch_resources])}; buildRules = (); dependencies = (); name = LvLianWatch; productName = LvLianWatch; productReference = {watch_product}; productType = "com.apple.product-type.application";')
target = add('target', f'isa = PBXNativeTarget; buildConfigurationList = {target_config}; buildPhases = {ids([sources_phase, frameworks_phase, resources_phase, watch_embed])}; buildRules = (); dependencies = {ids([watch_dependency])}; name = LvLian; productName = LvLian; productReference = {product}; productType = "com.apple.product-type.application";')
project = add('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 16.0; }}; }}; }}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {ids([target, watch_target])};')
path = ROOT / 'LvLian.xcodeproj/project.pbxproj'
path.parent.mkdir(exist_ok=True)
path.write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {project};\n}}\n')
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="LvLian.app" BlueprintName="LvLian" ReferencedContainer="container:LvLian.xcodeproj"/>'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_path = ROOT / 'LvLian.xcodeproj/xcshareddata/xcschemes/LvLian.xcscheme'
scheme_path.parent.mkdir(parents=True, exist_ok=True)
scheme_path.write_text(scheme)
print(f'Generated project with {len(sources)} Swift source files.')

watch_reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{watch_target}" BuildableName="LvLianWatch.app" BlueprintName="LvLianWatch" ReferencedContainer="container:LvLian.xcodeproj"/>'
watch_scheme = scheme.replace(reference, watch_reference)
(ROOT / 'LvLian.xcodeproj/xcshareddata/xcschemes/LvLianWatch.xcscheme').write_text(watch_scheme)
