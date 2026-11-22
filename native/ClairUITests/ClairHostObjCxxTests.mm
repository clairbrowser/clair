// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// Compiles ClairHost.h in an Objective-C++ unit, as Chromium does, and checks
// ClairUI.framework the way Chromium's loader will: by its principal class.

#import <XCTest/XCTest.h>

#include <string>

#import <objc/runtime.h>

#import "ClairHost.h"

@interface ObjCxxHost : NSObject <ClairHost>
@end

@implementation ObjCxxHost
- (NSString*)chromiumVersion {
  return @(std::string("156.0.8078.73").c_str());
}
- (NSString*)ungoogledChromiumVersion {
  return @"156.0.8078.73-1";
}
- (ClairRelaunchBlockers)silentRelaunchBlockers {
  return ClairRelaunchBlockersIncognitoWindow | ClairRelaunchBlockersUnloadPrompt;
}
- (void)relaunch {
}
- (void)updateWillInstallOnQuit {
}
- (void)openURL:(NSURL*)url {
}
- (NSArray<id<ClairSpace>>*)spaces {
  return @[];
}
- (NSArray<id<ClairTab>>*)tabsInSpace:(ClairSpaceID)spaceID {
  return @[];
}
- (void)addObserver:(id<ClairSpacesObserver>)observer {
}
- (ClairSpaceID)createSpaceNamed:(NSString*)name icon:(NSString*)icon profile:(ClairProfileID)profileID {
  return name.length && profileID.length ? [NSUUID UUID].UUIDString : nil;
}
- (void)renameSpace:(ClairSpaceID)spaceID to:(NSString*)name {
}
- (void)setIcon:(NSString*)icon forSpace:(ClairSpaceID)spaceID {
}
- (void)moveSpace:(ClairSpaceID)spaceID toIndex:(NSInteger)index {
}
- (void)deleteSpace:(ClairSpaceID)spaceID {
}
- (void)moveTab:(ClairTabID)tabID toSpace:(ClairSpaceID)spaceID {
}
- (NSArray<id<ClairProfile>>*)profiles {
  return @[];
}
- (void)createProfileNamed:(NSString*)name completion:(void (^)(ClairProfileID))completion {
  completion(name.length ? @"Profile 1" : nil);
}
- (void)renameProfile:(ClairProfileID)profileID to:(NSString*)name {
}
- (void)deleteProfile:(ClairProfileID)profileID {
}
- (void)setProfile:(ClairProfileID)profileID forSpace:(ClairSpaceID)spaceID {
}
- (void)downloadSettingsForProfile:(ClairProfileID)profileID
                        completion:(void (^)(NSURL*, BOOL))completion {
  completion([NSURL fileURLWithPath:@(std::string("/Users/test/Downloads").c_str())], NO);
}
- (void)setDownloadDirectory:(NSURL*)directory forProfile:(ClairProfileID)profileID {
}
- (void)setAsksWhereToSave:(BOOL)asks forProfile:(ClairProfileID)profileID {
}
- (void)openURL:(NSURL*)url inProfile:(ClairProfileID)profileID {
}
- (NSArray<id<ClairPin>>*)pinsInSpace:(ClairSpaceID)spaceID {
  return @[];
}
- (NSArray<id<ClairPin>>*)favoritesOfProfile:(ClairProfileID)profileID {
  return @[];
}
- (void)pinTab:(ClairTabID)tabID atIndex:(NSInteger)index {
}
- (void)favoriteTab:(ClairTabID)tabID atIndex:(NSInteger)index {
}
- (void)movePin:(ClairPinID)pinID toSpace:(ClairSpaceID)spaceID atIndex:(NSInteger)index {
}
- (void)movePin:(ClairPinID)pinID toFavoritesAtIndex:(NSInteger)index {
}
- (void)removePin:(ClairPinID)pinID {
}
- (void)returnToPinnedURL:(ClairPinID)pinID {
}
- (void)replacePinnedURLWithCurrent:(ClairPinID)pinID {
}
- (void)setPinnedURL:(NSURL*)url forPin:(ClairPinID)pinID {
}
- (void)setName:(NSString*)name forTab:(ClairTabID)tabID {
}
- (void)setName:(NSString*)name forPin:(ClairPinID)pinID {
}
- (void)clearTodayInSpace:(ClairSpaceID)spaceID {
}
- (NSArray<id<ClairLinkRule>>*)linkRules {
  return @[];
}
- (void)replaceLinkRules:(NSArray<id<ClairLinkRule>>*)rules {
  for (id<ClairLinkRule> rule in rules) {
    (void)std::string(rule.text.UTF8String);
  }
}
- (BOOL)isValidLinkRuleText:(NSString*)text {
  return text.length > 0;
}
@synthesize warnsBeforeQuitting = _warnsBeforeQuitting;
- (void)quitWithoutWarning {
}
@end

// A rule as ClairUI hands it over (add-link-rules design D4).
@interface ObjCxxLinkRule : NSObject <ClairLinkRule>
@end

@implementation ObjCxxLinkRule
- (ClairLinkRuleMatch)match {
  return ClairLinkRuleMatchPrefix;
}
- (NSString*)text {
  return @"github.com/acme";
}
- (ClairSpaceID)spaceID {
  return @"6f1c0d1e-0000-4000-8000-000000000001";
}
@end

@interface ClairHostObjCxxTests : XCTestCase
@end

@implementation ClairHostObjCxxTests

- (void)testHostCompilesInObjectiveCxx {
  id<ClairHost> host = [[ObjCxxHost alloc] init];
  XCTAssertTrue([host conformsToProtocol:@protocol(ClairHost)]);
  XCTAssertEqualObjects(host.chromiumVersion, @"156.0.8078.73");
  XCTAssertEqual(host.silentRelaunchBlockers & ClairRelaunchBlockersIncognitoWindow,
                 ClairRelaunchBlockersIncognitoWindow);
  // The Space calls (add-spaces design D9), as the overlay calls them.
  ClairSpaceID space = [host createSpaceNamed:@(std::string("Work").c_str())
                                         icon:nil
                                      profile:@"Default"];
  XCTAssertNotNil(space);
  XCTAssertNil([host createSpaceNamed:@"" icon:@"💼" profile:@"Default"]);
  // The profile calls (add-profiles design D11).
  __block ClairProfileID created = nil;
  [host createProfileNamed:@"Work"
                completion:^(ClairProfileID profileID) {
                  created = profileID;
                }];
  XCTAssertEqualObjects(created, @"Profile 1");
  __block std::string folder;
  [host downloadSettingsForProfile:@"Default"
                        completion:^(NSURL* directory, BOOL asks) {
                          folder = directory.fileSystemRepresentation;
                          XCTAssertFalse(asks);
                        }];
  XCTAssertEqual(folder, "/Users/test/Downloads");
  host.warnsBeforeQuitting = YES;
  XCTAssertTrue(host.warnsBeforeQuitting);
  [host quitWithoutWarning];
  XCTAssertEqual([host tabsInSpace:space].count, 0u);
  // The pin calls (add-pinned-tabs-and-favorites design D10).
  XCTAssertEqual([host pinsInSpace:space].count, 0u);
  XCTAssertEqual([host favoritesOfProfile:@"Default"].count, 0u);
  [host pinTab:3 atIndex:0];
  [host setName:nil forTab:3];
  ClairPinID pin = @(std::string("6f1c0d1e-0000-4000-8000-000000000000").c_str());
  [host movePin:pin toSpace:space atIndex:NSIntegerMax];
  [host setPinnedURL:[NSURL URLWithString:@"https://example.com/"] forPin:pin];
  // The link rule calls (add-link-rules design D4).
  XCTAssertEqual(host.linkRules.count, 0u);
  [host replaceLinkRules:@[ [[ObjCxxLinkRule alloc] init] ]];
  XCTAssertTrue([host isValidLinkRuleText:@"example.com"]);
  std::string matches[] = {"contains", "exact", "prefix"};
  XCTAssertEqual(matches[ClairLinkRuleMatchExact], "exact");
  ClairBrowserID browser = 7;
  XCTAssertEqual(browser, 7);
}

// The window contract's value types and protocols, used from C++ as the
// overlay uses them.
- (void)testWindowContractCompilesInObjectiveCxx {
  ClairDevToolsLayout layout = {ClairDevToolsDockSideRight, NSMakeRect(0, 0, 640, 480), false};
  XCTAssertEqual(layout.dockSide, ClairDevToolsDockSideRight);
  ClairAnchor anchor = {NSMakeRect(12, 700, 24, 24), ClairAnchorEdgeTrailing};
  XCTAssertEqual(anchor.edge, ClairAnchorEdgeTrailing);
  ClairFindResult find = {1, 3, true};
  XCTAssertEqual(find.matchCount, 3);
  ClairTabIndicators indicators = ClairTabIndicatorsCamera | ClairTabIndicatorsBlockedPermission;
  XCTAssertTrue(indicators & ClairTabIndicatorsCamera);
  ClairTabID none = ClairTabIDNone;
  XCTAssertEqual(none, -1);
  std::string kinds[] = {"regular", "incognito", "guest"};
  XCTAssertEqual(kinds[ClairProfileKindGuest], "guest");
  for (Protocol* protocol in @[
         @protocol(ClairBrowser), @protocol(ClairWindow), @protocol(ClairTab),
         @protocol(ClairAutocomplete), @protocol(ClairAutocompleteDelegate),
         @protocol(ClairSuggestion), @protocol(ClairDownload),
         @protocol(ClairExtensionAction), @protocol(ClairExtensionPrompt), @protocol(ClairInfobar),
         @protocol(ClairHistoryMenu), @protocol(ClairHistoryMenuDelegate), @protocol(ClairHistoryItem),
         @protocol(ClairSpace), @protocol(ClairSpacesObserver), @protocol(ClairProfile),
         @protocol(ClairPin), @protocol(ClairLinkRule)
       ]) {
    XCTAssertTrue(protocol_conformsToProtocol(protocol, @protocol(NSObject)));
  }
}

- (void)testFrameworkPrincipalClassConformsToEntryPoint {
  NSBundle* bundle = [NSBundle bundleWithIdentifier:@"dev.joshuapark.Clair.ClairUI"];
  XCTAssertNotNil(bundle);
  XCTAssertTrue([bundle load]);
  Class principal = bundle.principalClass;
  XCTAssertNotNil(principal);
  XCTAssertTrue([principal conformsToProtocol:@protocol(ClairUIEntryPoint)]);
  XCTAssertTrue([principal respondsToSelector:@selector(startWithHost:)]);
  XCTAssertTrue([principal respondsToSelector:@selector(windowForBrowser:)]);
}

@end
