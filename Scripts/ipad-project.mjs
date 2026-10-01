#!/usr/bin/env node
import { createHash } from 'node:crypto'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const id = value => createHash('sha256').update(value).digest('hex').slice(0, 24).toUpperCase()
const q = value => JSON.stringify(String(value))
const xml = value => String(value).replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;')

// A small deterministic project keeps platform sources under apps/ipad without
// adding XcodeGen/CocoaPods or storing machine-specific Xcode configuration.
export function ipadProject({ version, buildNumber = '1', team = '' }) {
  if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error('iPad version must be major.minor.patch')
  if (!/^\d+$/.test(String(buildNumber))) throw new Error('iPad build number must be an integer')
  if (team && !/^[A-Z0-9]{10}$/.test(team)) throw new Error('Apple team ID must contain 10 uppercase letters/digits')
  const objects = new Map()
  const put = (name, body) => { objects.set(id(name), body); return id(name) }
  const list = values => `(${values.join(', ')})`
  const appFiles = ['BenchGaugeApp.swift', 'DebugFixtures.swift'].map(name => {
    const file = put(name, `isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${q(`App/${name}`)}; sourceTree = "<group>";`)
    return put(`build-${name}`, `isa = PBXBuildFile; fileRef = ${file};`)
  })
  const testFile = put('uitest-file', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UITests/LeaderboardPadTests.swift; sourceTree = "<group>";')
  const testBuild = put('uitest-build', `isa = PBXBuildFile; fileRef = ${testFile};`)
  const assetFile = put('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = App/Assets.xcassets; sourceTree = "<group>";')
  const privacyFile = put('privacy', 'isa = PBXFileReference; lastKnownFileType = text.xml; path = App/PrivacyInfo.xcprivacy; sourceTree = "<group>";')
  const logoFile = put('logos', 'isa = PBXFileReference; lastKnownFileType = folder; path = ../../assets/logos; sourceTree = "<group>";')
  const resources = [assetFile, privacyFile, logoFile].map(fileRef => put(`resource-${fileRef}`, `isa = PBXBuildFile; fileRef = ${fileRef};`))
  const infoFile = put('info', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = App/Info.plist; sourceTree = "<group>";')
  const appProduct = put('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "AI BenchGauge.app"; sourceTree = BUILT_PRODUCTS_DIR;')
  const testProduct = put('test-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = BenchGaugeUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
  const packageRef = put('package', 'isa = XCLocalSwiftPackageReference; relativePath = "../..";')
  const uiProduct = put('ui-library', `isa = XCSwiftPackageProductDependency; package = ${packageRef}; productName = LeaderboardPadUI;`)
  const uiBuild = put('ui-library-build', `isa = PBXBuildFile; productRef = ${uiProduct};`)
  function phase(name, isa, files) {
    return put(name, `isa = ${isa}; buildActionMask = 2147483647; files = ${list(files)}; runOnlyForDeploymentPostprocessing = 0;`)
  }
  const appPhases = [phase('app-sources', 'PBXSourcesBuildPhase', appFiles), phase('app-frameworks', 'PBXFrameworksBuildPhase', [uiBuild]), phase('app-resources', 'PBXResourcesBuildPhase', resources)]
  const testPhases = [phase('test-sources', 'PBXSourcesBuildPhase', [testBuild]), phase('test-frameworks', 'PBXFrameworksBuildPhase', []), phase('test-resources', 'PBXResourcesBuildPhase', [])]
  function configurations(name, settings) {
    const configs = ['Debug', 'Release'].map(config => {
      const values = { ...settings, SWIFT_OPTIMIZATION_LEVEL: config === 'Debug' ? '-Onone' : '-O',
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: config === 'Debug' ? 'DEBUG $(inherited)' : '$(inherited)',
        DEBUG_INFORMATION_FORMAT: config === 'Debug' ? 'dwarf' : 'dwarf-with-dsym',
        ENABLE_TESTABILITY: config === 'Debug' ? 'YES' : 'NO',
        ONLY_ACTIVE_ARCH: config === 'Debug' ? 'YES' : 'NO' }
      const body = Object.entries(values).map(([key, value]) => `${key} = ${q(value)};`).join('\n')
      return put(`${name}-${config}`, `isa = XCBuildConfiguration; buildSettings = { ${body} }; name = ${config};`)
    })
    return put(`${name}-config-list`, `isa = XCConfigurationList; buildConfigurations = ${list(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;`)
  }
  const common = { IPHONEOS_DEPLOYMENT_TARGET: '17.0', SDKROOT: 'iphoneos', SWIFT_VERSION: '6.0',
    TARGETED_DEVICE_FAMILY: '2', SUPPORTED_PLATFORMS: 'iphoneos iphonesimulator',
    CODE_SIGN_STYLE: 'Automatic', ...(team ? { DEVELOPMENT_TEAM: team } : {}),
    CLANG_ENABLE_MODULES: 'YES', SWIFT_STRICT_CONCURRENCY: 'complete' }
  const projectConfigs = configurations('project', common)
  const appConfigs = configurations('app', { ...common, PRODUCT_NAME: 'AI BenchGauge', PRODUCT_BUNDLE_IDENTIFIER: 'com.cloydlau.ai-benchgauge.ipad',
    INFOPLIST_FILE: 'App/Info.plist', GENERATE_INFOPLIST_FILE: 'NO', MARKETING_VERSION: version, CURRENT_PROJECT_VERSION: buildNumber,
    ASSETCATALOG_COMPILER_APPICON_NAME: 'AppIcon', SUPPORTS_MACCATALYST: 'NO', SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: 'NO',
    LD_RUNPATH_SEARCH_PATHS: '$(inherited) @executable_path/Frameworks' })
  const testConfigs = configurations('test', { ...common, SWIFT_VERSION: '5.0', PRODUCT_NAME: 'BenchGaugeUITests', PRODUCT_BUNDLE_IDENTIFIER: 'com.cloydlau.ai-benchgauge.ipad.uitests',
    GENERATE_INFOPLIST_FILE: 'YES', TEST_TARGET_NAME: 'BenchGauge', LD_RUNPATH_SEARCH_PATHS: '$(inherited) @executable_path/Frameworks @loader_path/Frameworks' })
  const appTarget = put('app-target', `isa = PBXNativeTarget; buildConfigurationList = ${appConfigs}; buildPhases = ${list(appPhases)}; buildRules = (); dependencies = (); name = BenchGauge; packageProductDependencies = (${uiProduct}); productName = "AI BenchGauge"; productReference = ${appProduct}; productType = "com.apple.product-type.application";`)
  const proxy = put('app-proxy', `isa = PBXContainerItemProxy; containerPortal = ${id('project')}; proxyType = 1; remoteGlobalIDString = ${appTarget}; remoteInfo = BenchGauge;`)
  const dependency = put('test-app-dependency', `isa = PBXTargetDependency; target = ${appTarget}; targetProxy = ${proxy};`)
  const testTarget = put('test-target', `isa = PBXNativeTarget; buildConfigurationList = ${testConfigs}; buildPhases = ${list(testPhases)}; buildRules = (); dependencies = (${dependency}); name = BenchGaugeUITests; productName = BenchGaugeUITests; productReference = ${testProduct}; productType = "com.apple.product-type.bundle.ui-testing";`)
  const products = put('products', `isa = PBXGroup; children = (${appProduct}, ${testProduct}); name = Products; sourceTree = "<group>";`)
  const group = put('group', `isa = PBXGroup; children = ${list([...['BenchGaugeApp.swift', 'DebugFixtures.swift'].map(id), testFile, assetFile, privacyFile, logoFile, infoFile, products])}; sourceTree = "<group>";`)
  put('project', `isa = PBXProject; attributes = { LastUpgradeCheck = 1600; BuildIndependentTargetsInParallel = YES; TargetAttributes = { ${testTarget} = { TestTargetID = ${appTarget}; }; }; }; buildConfigurationList = ${projectConfigs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, "zh-Hans", "zh-Hant", Base); mainGroup = ${group}; packageReferences = (${packageRef}); productRefGroup = ${products}; projectDirPath = ""; projectRoot = ""; targets = (${appTarget}, ${testTarget});`)
  const project = `// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n${[...objects].map(([key, body]) => `${key} = { ${body} };`).join('\n')}\n}; rootObject = ${id('project')}; }\n`
  const ref = (target, product, name) => `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${target}" BuildableName="${xml(product)}" BlueprintName="${xml(name)}" ReferencedContainer="container:AI-BenchGauge.xcodeproj"/>`
  const appRef = ref(appTarget, 'AI BenchGauge.app', 'BenchGauge')
  const testRef = ref(testTarget, 'BenchGaugeUITests.xctest', 'BenchGaugeUITests')
  const scheme = `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">${appRef}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">${testRef}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">${appRef}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">${appRef}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n`
  return { project, scheme }
}

export function generateIpadProject(directory = root, options = {}) {
  const { version } = JSON.parse(readFileSync(join(directory, 'config/app.json'), 'utf8'))
  const generated = ipadProject({ version, ...options })
  const projectPath = join(directory, 'apps/ipad/AI-BenchGauge.xcodeproj')
  mkdirSync(join(projectPath, 'xcshareddata/xcschemes'), { recursive: true })
  writeFileSync(join(projectPath, 'project.pbxproj'), generated.project)
  writeFileSync(join(projectPath, 'xcshareddata/xcschemes/BenchGauge.xcscheme'), generated.scheme)
  return projectPath
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  console.log(generateIpadProject(root, { buildNumber: process.env.IPAD_BUILD_NUMBER || '1', team: process.env.APPLE_TEAM_ID || '' }))
}
