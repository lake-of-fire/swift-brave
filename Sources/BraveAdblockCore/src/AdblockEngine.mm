/* Copyright (c) 2022 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#include "AdblockEngine.h"

#include <string>
#include <vector>

#include "adblock/lib.rs.h"

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

namespace brave_adblock {
static std::string SysNSStringToUTF8(NSString* string) {
  if (string == nil) {
    return std::string();
  }
  const char* utf8 = [string UTF8String];
  if (utf8 == nullptr) {
    return std::string();
  }
  return std::string(utf8);
}

static NSString* SysUTF8ToNSString(const std::string& string) {
  if (string.empty()) {
    return @"";
  }
  NSString* value = [[NSString alloc] initWithBytes:string.data()
                                             length:string.size()
                                           encoding:NSUTF8StringEncoding];
  return value ?: @"";
}

static std::vector<std::string> NSStringArrayToVector(NSArray<NSString*>* array) {
  std::vector<std::string> vector;
  if (array == nil) {
    return vector;
  }
  vector.reserve(array.count);
  for (NSString* value in array) {
    vector.emplace_back(SysNSStringToUTF8(value));
  }
  return vector;
}
}  // namespace brave_adblock

@interface AdblockEngineMatchResult ()
@property(nonatomic, readwrite) bool didMatchRule;
@property(nonatomic, readwrite) bool didMatchException;
@property(nonatomic, readwrite) bool didMatchImportant;
@property(nonatomic, readwrite, copy) NSString* redirect;
@property(nonatomic, readwrite, copy) NSString* rewrittenURL;
@end

@interface ContentBlockingRulesResult ()
@property(nonatomic, readwrite, copy) NSString* rulesJSON;
@property(nonatomic, readwrite) bool truncated;
@end

@implementation AdblockEngineMatchResult
- (instancetype)init {
  if ((self = [super init])) {
    self.redirect = @"";
    self.rewrittenURL = @"";
  }
  return self;
}
@end

@implementation ContentBlockingRulesResult
- (instancetype)init {
  if ((self = [super init])) {
    self.rulesJSON = @"";
  }
  return self;
}
@end

/// rust::Box's default constructor is deleted, so we must box it again so we
/// can assign it `adblock::new_engine()` by default since C++ types inside of
/// Obj-C built with ARC call their default constructor on `-init` regardless
class AdblockEngineBox final {
 public:
  AdblockEngineBox() : adblock_engine_(adblock::new_engine()) {}
  AdblockEngineBox(const AdblockEngineBox&) = delete;
  AdblockEngineBox& operator=(const AdblockEngineBox&) = delete;
  ~AdblockEngineBox() = default;

  rust::Box<adblock::Engine>& operator->() { return adblock_engine_; }
  void operator=(rust::Box<adblock::Engine>&& engine) {
    adblock_engine_ = std::move(engine);
  }

 private:
  rust::Box<adblock::Engine> adblock_engine_;
};

@implementation AdblockEngine {
  AdblockEngineBox adblock_engine;
}

- (instancetype)init {
  // An empty engine is already created with `AdblockEngineBox`
  return [super init];
}

- (instancetype)initWithRules:(NSString*)rules error:(NSError**)error {
  if ((self = [super init])) {
    if (rules.length > 0) {
      std::vector<std::uint8_t> vecRules;
      NSData* data = [rules dataUsingEncoding:NSUTF8StringEncoding];

      if (data) {
        vecRules.resize(data.length);
        [data getBytes:vecRules.data() length:data.length];
      }

      auto result = adblock::engine_with_rules(vecRules);
      if (result.result_kind == adblock::ResultKind::Success) {
        adblock_engine = std::move(result.value);
      } else {
        if (error) {
          *error = [[self class] adblockErrorForKind:result.result_kind
                                             message:result.error_message];
        } else {
          *error = [[self class]
              adblockErrorForKind:adblock::ResultKind::AdblockError
                          message:
                              "Unknown error initializing engine with rules"];
        }
        return nil;
      }
    }
  }
  return self;
}

- (instancetype)initWithSerializedData:(NSData*)data error:(NSError**)error {
  if ((self = [super init])) {
    if (![self deserialize:data]) {
      if (error) {
        *error =
            [[self class] adblockErrorForKind:adblock::ResultKind::AdblockError
                                      message:"Failed to deserialize data"];
        return nil;
      }
    }
  }
  return self;
}

+ (NSError*)adblockErrorForKind:(adblock::ResultKind)kind
                        message:(rust::String)message {
  return [NSError
      errorWithDomain:@"com.brave.adblock"
                 code:static_cast<NSInteger>(kind)
             userInfo:@{
               NSLocalizedDescriptionKey :
                   brave_adblock::SysUTF8ToNSString(
                       static_cast<std::string>(message))
             }];
}

- (AdblockEngineMatchResult*)matchesURL:(NSString*)url
                                   host:(NSString*)host
                                tabHost:(NSString*)tabHost
                           isThirdParty:(bool)isThirdParty
                           resourceType:(NSString*)resourceType {
  return [self matchesURL:url
                       host:host
                    tabHost:tabHost
               isThirdParty:isThirdParty
               resourceType:resourceType
      previouslyMatchedRule:false
       forceCheckExceptions:false];
}

- (AdblockEngineMatchResult*)matchesURL:(NSString*)url
                                   host:(NSString*)host
                                tabHost:(NSString*)tabHost
                           isThirdParty:(bool)isThirdParty
                           resourceType:(NSString*)resourceType
                  previouslyMatchedRule:(bool)previouslyMatchedRule
                   forceCheckExceptions:(bool)forceCheckExceptions {
  auto engine_result = adblock_engine->matches(
      brave_adblock::SysNSStringToUTF8(url),
      brave_adblock::SysNSStringToUTF8(host),
      brave_adblock::SysNSStringToUTF8(tabHost),
      brave_adblock::SysNSStringToUTF8(resourceType),
      isThirdParty, previouslyMatchedRule, forceCheckExceptions);
  auto result = [[AdblockEngineMatchResult alloc] init];
  result.didMatchRule = engine_result.matched;
  result.didMatchException = engine_result.has_exception;
  result.didMatchImportant = engine_result.important;
  if (engine_result.redirect.has_value) {
    result.redirect = brave_adblock::SysUTF8ToNSString(
        static_cast<std::string>(engine_result.redirect.value));
  }
  if (engine_result.rewritten_url.has_value) {
    ;
    result.rewrittenURL = brave_adblock::SysUTF8ToNSString(
        static_cast<std::string>(engine_result.rewritten_url.value));
  }
  return result;
}

- (NSString*)cspDirectivesForURL:(NSString*)url
                            host:(NSString*)host
                         tabHost:(NSString*)tabHost
                    isThirdParty:(bool)isThirdParty
                    resourceType:(NSString*)resourceType {
  return brave_adblock::SysUTF8ToNSString(
      static_cast<std::string>(adblock_engine->get_csp_directives(
          brave_adblock::SysNSStringToUTF8(url),
          brave_adblock::SysNSStringToUTF8(host),
          brave_adblock::SysNSStringToUTF8(tabHost),
          brave_adblock::SysNSStringToUTF8(resourceType), isThirdParty)));
}

- (bool)deserialize:(NSData*)data {
  std::vector<std::uint8_t> vecData(data.length);
  [data getBytes:vecData.data() length:data.length];
  return adblock_engine->deserialize(vecData);
}

- (nullable NSData*)serialize:(NSError**)error {
  auto result = adblock_engine->serialize();

  if (result.empty()) {
    if (error) {
      *error =
          [[self class] adblockErrorForKind:adblock::ResultKind::AdblockError
                                    message:"Failed to serialize data"];
    }
    return nil;
  }

  return [NSData dataWithBytes:result.data() length:result.size()];
}

- (void)addTag:(NSString*)tag {
  adblock_engine->enable_tag(brave_adblock::SysNSStringToUTF8(tag));
}

- (void)removeTag:(NSString*)tag {
  adblock_engine->disable_tag(brave_adblock::SysNSStringToUTF8(tag));
}

- (bool)tagExists:(NSString*)tag {
  return adblock_engine->tag_exists(brave_adblock::SysNSStringToUTF8(tag));
}

- (bool)useResources:(NSString*)resources {
  // TODO(https://github.com/brave/brave-browser/issues/51103):
  // Reuse the once created storage for the both engines.
  auto storage =
      adblock::new_resource_storage(brave_adblock::SysNSStringToUTF8(resources));
  adblock_engine->use_resource_storage(*storage);
  return true;
}

- (NSString*)cosmeticResourcesForURL:(NSString*)url {
  return brave_adblock::SysUTF8ToNSString(static_cast<std::string>(
      adblock_engine->url_cosmetic_resources(
          brave_adblock::SysNSStringToUTF8(url))));
}

- (nullable NSArray<NSString*>*)
    stylesheetForCosmeticRulesIncludingClasses:(NSArray<NSString*>*)classes
                                           ids:(NSArray<NSString*>*)ids
                                    exceptions:(NSArray<NSString*>*)exceptions
                                         error:(NSError**)error {
  const auto result = adblock_engine->hidden_class_id_selectors(
      brave_adblock::NSStringArrayToVector(classes),
      brave_adblock::NSStringArrayToVector(ids),
      brave_adblock::NSStringArrayToVector(exceptions));
  if (result.result_kind != adblock::ResultKind::Success) {
    if (error) {
      *error = [[self class] adblockErrorForKind:result.result_kind
                                         message:result.error_message];
    }
    return nil;
  }
  auto selectors = [[NSMutableArray<NSString*> alloc] init];
  for (auto selector : result.value) {
    [selectors
        addObject:brave_adblock::SysUTF8ToNSString(
                              static_cast<std::string>(selector))];
  }
  return [selectors copy];
}

+ (bool)setDomainResolver {
  return adblock::set_domain_resolver();
}

+ (nullable ContentBlockingRulesResult*)
    contentBlockerRulesFromFilterSet:(NSString*)filterSet
                               error:(NSError**)error {
  auto result = adblock::convert_rules_to_content_blocking(
      brave_adblock::SysNSStringToUTF8(filterSet));
  if (result.result_kind != adblock::ResultKind::Success) {
    if (error) {
      *error = [self adblockErrorForKind:result.result_kind
                                 message:result.error_message];
    }
    return nil;
  }
  auto value = [[ContentBlockingRulesResult alloc] init];
  value.rulesJSON = brave_adblock::SysUTF8ToNSString(
      static_cast<std::string>(result.value.rules_json));
  value.truncated = result.value.truncated;
  return value;
}

@end
