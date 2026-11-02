#!/usr/bin/env python3
"""Generate the small, deterministic Xcode host project without external dependencies."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def q(s): return json.dumps(s)
objects=[]
def obj(key,body):
    identifier=uid(key);objects.append(f'{identifier} = {{ {body} }};');return identifier
def arr(values): return '('+','.join(values)+',)'
modules=['FormaGeometry','FormaDomain','FormaApplication','FormaCanvasEngine','FormaDesignSystem','FormaWorkspaceFeature','FormaDocumentIO','FormaInterchange','FormaCatalogInfrastructure','FormaLocalization']
sourceFiles=sorted(Path('App').glob('*.swift'))
sourceRefs=[];sourceBuild=[]
for f in sourceFiles:
    r=obj('ref:'+str(f),f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(str(f))}; sourceTree = SOURCE_ROOT;')
    sourceRefs.append(r);sourceBuild.append(obj('build:'+str(f),f'isa = PBXBuildFile; fileRef = {r};'))
assets=obj('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = App/Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;')
assetBuild=obj('assetBuild',f'isa = PBXBuildFile; fileRef = {assets};')
privacy=obj('privacy','isa = PBXFileReference; lastKnownFileType = text.xml; path = App/Resources/PrivacyInfo.xcprivacy; sourceTree = SOURCE_ROOT;')
privacyBuild=obj('privacyBuild',f'isa = PBXBuildFile; fileRef = {privacy};')
info=obj('info','isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = App/Configuration/Info.plist; sourceTree = SOURCE_ROOT;')
product=obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = Forma.app; sourceTree = BUILT_PRODUCTS_DIR;')
products=obj('products',f'isa = PBXGroup; name = Products; children = {arr([product])}; sourceTree = "<group>";')
package=obj('package','isa = XCLocalSwiftPackageReference; relativePath = Packages/FormaKit;')
packageProducts=[];frameworkBuild=[]
for m in modules:
 p=obj('package:'+m,f'isa = XCSwiftPackageProductDependency; package = {package}; productName = {m};')
 packageProducts.append(p);frameworkBuild.append(obj('link:'+m,f'isa = PBXBuildFile; productRef = {p};'))
sources=obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(sourceBuild)}; runOnlyForDeploymentPostprocessing = 0;')
resources=obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr([assetBuild,privacyBuild])}; runOnlyForDeploymentPostprocessing = 0;')
frameworks=obj('frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {arr(frameworkBuild)}; runOnlyForDeploymentPostprocessing = 0;')
root=obj('root',f'isa = PBXGroup; children = {arr(sourceRefs+[assets,privacy,info,products])}; sourceTree = "<group>";')
projectConfigs=[];targetConfigs=[]
for name in ['Debug','Release']:
 common={'ARCHS':'arm64','ONLY_ACTIVE_ARCH':'YES','MACOSX_DEPLOYMENT_TARGET':'14.0','SDKROOT':'macosx','SWIFT_VERSION':'6.0','CLANG_ENABLE_MODULES':'YES','SWIFT_STRICT_CONCURRENCY':'complete','DEBUG_INFORMATION_FORMAT':'dwarf' if name=='Debug' else 'dwarf-with-dsym','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O'}
 if name=='Debug': common['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
 def settings(values):return ' '.join(f'{k} = {q(v)};' for k,v in values.items())
 projectConfigs.append(obj('project-config:'+name,f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ {settings(common)} }};'))
 specific={'PRODUCT_NAME':'Forma','PRODUCT_BUNDLE_IDENTIFIER':'com.forma.diagram.app','INFOPLIST_FILE':'App/Configuration/Info.plist','GENERATE_INFOPLIST_FILE':'NO','CODE_SIGN_STYLE':'Automatic','CODE_SIGN_ENTITLEMENTS':'App/Configuration/Forma.entitlements','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks','ENABLE_HARDENED_RUNTIME':'YES'}
 targetConfigs.append(obj('target-config:'+name,f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ {settings(specific)} }};'))
pcl=obj('project-configs',f'isa = XCConfigurationList; buildConfigurations = {arr(projectConfigs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tcl=obj('target-configs',f'isa = XCConfigurationList; buildConfigurations = {arr(targetConfigs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=obj('app-target',f'isa = PBXNativeTarget; name = Forma; productName = Forma; productReference = {product}; productType = "com.apple.product-type.application"; buildConfigurationList = {tcl}; buildPhases = {arr([sources,frameworks,resources])}; buildRules = (); dependencies = (); packageProductDependencies = {arr(packageProducts)};')
project=obj('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; }}; buildConfigurationList = {pcl}; compatibilityVersion = "Xcode 15.0"; developmentRegion = zh-Hans; knownRegions = ("zh-Hans",en,Base); mainGroup = {root}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; packageReferences = {arr([package])}; targets = {arr([target])};')
folder=Path('Forma.xcodeproj');folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {project}; }}\n')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Forma.app" BlueprintName="Forma" ReferencedContainer="container:Forma.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Forma.app" BlueprintName="Forma" ReferencedContainer="container:Forma.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Forma.app" BlueprintName="Forma" ReferencedContainer="container:Forma.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
schemeDir=folder/'xcshareddata/xcschemes';schemeDir.mkdir(parents=True,exist_ok=True);(schemeDir/'Forma.xcscheme').write_text(scheme)
print('Generated Forma.xcodeproj with local package products.')
