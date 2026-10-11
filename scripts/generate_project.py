#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project. No XcodeGen/CocoaPods required."""
from pathlib import Path
import hashlib, json, plistlib

ROOT = Path(__file__).resolve().parents[1]
objects = {}
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def obj(key_name, isa, **kwargs):
    key = ident(key_name); objects[key] = {'isa': isa, **kwargs}; return key

def settings_list(name, common, debug=None, release=None):
    refs=[]
    for conf, extra in [('Debug',debug or {}),('Release',release or {})]:
        refs.append(obj(name+conf,'XCBuildConfiguration',buildSettings={**common,**extra},name=conf))
    return obj(name+'Settings','XCConfigurationList',buildConfigurations=refs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

def files_for(directory, suffix):
    refs=[]; builds=[]
    for path in sorted((ROOT/directory).glob(suffix)):
        ref=obj(str(path.relative_to(ROOT)), 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=path.name, sourceTree='<group>')
        refs.append(ref); builds.append(obj('build:'+str(path.relative_to(ROOT)),'PBXBuildFile',fileRef=ref))
    return refs, builds

app_refs, app_builds=files_for('AADRIPro','*.swift')
test_refs,test_builds=files_for('UITests','*.swift')
resources=[]
for path, typ in [('Assets.xcassets','folder.assetcatalog'),('Resources/sample.mp4','file'),('PrivacyInfo.xcprivacy','text.xml')]:
    ref=obj('resource:'+path,'PBXFileReference',lastKnownFileType=typ,path=path,sourceTree='<group>')
    app_refs.append(ref);resources.append(obj('build-resource:'+path,'PBXBuildFile',fileRef=ref))
app_refs.append(obj('Info.plist','PBXFileReference',lastKnownFileType='text.plist.xml',path='Info.plist',sourceTree='<group>'))
app_group=obj('AppGroup','PBXGroup',children=app_refs,path='AADRIPro',sourceTree='<group>')
test_group=obj('TestGroup','PBXGroup',children=test_refs,path='UITests',sourceTree='<group>')
app_product=obj('AppProduct','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='AADRIPro.app',sourceTree='BUILT_PRODUCTS_DIR')
test_product=obj('TestProduct','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex=0,path='AADRIProUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
products=obj('Products','PBXGroup',children=[app_product,test_product],name='Products',sourceTree='<group>')
main_group=obj('MainGroup','PBXGroup',children=[app_group,test_group,products],sourceTree='<group>')
base={'IPHONEOS_DEPLOYMENT_TARGET':'16.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SWIFT_STRICT_CONCURRENCY':'minimal'}
project_configs=settings_list('Project',base,{'DEBUG_INFORMATION_FORMAT':'dwarf','ENABLE_TESTABILITY':'YES','SWIFT_OPTIMIZATION_LEVEL':'-Onone','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)'},{'DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym','SWIFT_COMPILATION_MODE':'wholemodule','SWIFT_OPTIMIZATION_LEVEL':'-O'})
app_configs=settings_list('App',{'PRODUCT_BUNDLE_IDENTIFIER':'com.aadripro.ios','PRODUCT_NAME':'AADRIPro','INFOPLIST_FILE':'AADRIPro/Info.plist','GENERATE_INFOPLIST_FILE':'NO','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'0.1.0','TARGETED_DEVICE_FAMILY':'1,2','CODE_SIGN_STYLE':'Automatic','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO'})
test_configs=settings_list('UITest',{'PRODUCT_BUNDLE_IDENTIFIER':'com.aadripro.ios.uitests','PRODUCT_NAME':'AADRIProUITests','GENERATE_INFOPLIST_FILE':'YES','TARGETED_DEVICE_FAMILY':'1,2','CODE_SIGN_STYLE':'Automatic','TEST_TARGET_NAME':'AADRIPro','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @loader_path/Frameworks'})
def phases(name, sources, resources):
    return [obj(name+'Sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=sources,runOnlyForDeploymentPostprocessing=0),obj(name+'Frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0),obj(name+'Resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=resources,runOnlyForDeploymentPostprocessing=0)]
app_target=obj('AppTarget','PBXNativeTarget',buildConfigurationList=app_configs,buildPhases=phases('App',app_builds,resources),buildRules=[],dependencies=[],name='AADRIPro',productName='AADRIPro',productReference=app_product,productType='com.apple.product-type.application')
proxy=obj('AppProxy','PBXContainerItemProxy',containerPortal=ident('Project'),proxyType=1,remoteGlobalIDString=app_target,remoteInfo='AADRIPro')
dependency=obj('Dependency','PBXTargetDependency',target=app_target,targetProxy=proxy)
test_target=obj('UITestTarget','PBXNativeTarget',buildConfigurationList=test_configs,buildPhases=phases('UITest',test_builds,[]),buildRules=[],dependencies=[dependency],name='AADRIProUITests',productName='AADRIProUITests',productReference=test_product,productType='com.apple.product-type.bundle.ui-testing')
project=obj('Project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1600','TargetAttributes':{app_target:{'CreatedOnToolsVersion':'16.0'},test_target:{'CreatedOnToolsVersion':'16.0','TestTargetID':app_target}}},buildConfigurationList=project_configs,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','ar','Base'],mainGroup=main_group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[app_target,test_target])
def encode(value, level=0):
    tabs='\t'*level
    if isinstance(value,dict): return '{\n'+''.join(tabs+'\t'+json.dumps(str(k))+' = '+encode(v,level+1)+';\n' for k,v in value.items())+tabs+'}'
    if isinstance(value,list): return '('+','.join(encode(v,level) for v in value)+(',' if value else '')+')'
    if isinstance(value,int): return str(value)
    return json.dumps(value)
folder=ROOT/'AADRIPro.xcodeproj';folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')

def ref(target,name,ext): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}.{ext}" BlueprintName="{name}" ReferencedContainer="container:AADRIPro.xcodeproj"/>'
a=ref(app_target,'AADRIPro','app');t=ref(test_target,'AADRIProUITests','xctest')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{a}</BuildActionEntry>
  <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{t}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{t}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{a}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{a}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
scheme_dir=folder/'xcshareddata/xcschemes';scheme_dir.mkdir(parents=True,exist_ok=True)
(scheme_dir/'AADRIPro.xcscheme').write_text(scheme)
print('Generated AADRIPro.xcodeproj with app and full-screen UI test targets')
