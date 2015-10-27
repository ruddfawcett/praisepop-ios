//
//  PraisePopAPI.m
//  PraisePop
//
//  Created by Rudd Fawcett on 10/4/15.
//  Copyright © 2015 PraisePop. All rights reserved.
//

#import <Parse/Parse.h>
#import <SSKeychain/SSKeychain.h>
#import <CommonCrypto/CommonDigest.h>

#import "PPUser.h"
#import "PPPost.h"
#import "PPReaction.h"
#import "PPAuthentication.h"
#import "PPOrganization.h"

#import "PraisePopAPI.h"

static NSString * const PraisePopAPIBaseURLString = @"https://praisepop.herokuapp.com/api/v1/";

static CGFloat const PRAISE_POP_FEED_LIMIT = 25;

@interface PraisePopAPI ()

@property (nonatomic) NSUInteger currentPage;

@end

@implementation PraisePopAPI

+ (instancetype)sharedClient {
    static PraisePopAPI *_sharedClient = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedClient = [[PraisePopAPI alloc] initWithBaseURL:[NSURL URLWithString:PraisePopAPIBaseURLString]];
        _sharedClient.responseSerializer.acceptableStatusCodes = [_sharedClient.acceptableStatusCodes copy];
    });
    
    return _sharedClient;
}

+ (NSDictionary *)modelClassesByResourcePath {
    return @{
             @"users/authenticate" : [PPAuthentication class],
             @"orgs/*/users/random" : [PPUser class],
             @"orgs/*/posts" : [PPPost class]
             };
}

- (NSIndexSet *)acceptableStatusCodes {
    NSMutableIndexSet *acceptedCodes = [[NSMutableIndexSet alloc]
                                        initWithIndexSet:self.responseSerializer.acceptableStatusCodes];
    
    NSIndexSet *acceptable = [NSIndexSet.alloc initWithIndexesInRange:NSMakeRange(100, 600)];
    
    [acceptedCodes addIndexes:acceptable];
    
    return acceptedCodes;
}

- (void)signup:(NSString *)email password:(NSString *)password name:(NSDictionary *)name success:(void (^)(BOOL))success failure:(void (^)(AFHTTPRequestOperation *, NSError *))failure {
    NSDictionary *paramters = @{
                                @"email" : email,
                                @"password" : [self md5:password],
                                @"name" : name
                                };
    
    [self POST:@"users/new" parameters:paramters success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSDictionary *response = (NSDictionary *)responseObject;
        
        if (response[@"result"] && [response[@"result"] boolValue] == NO) {
            success(NO);
        }
        else {
            success(YES);
        }
    } failure:^(AFHTTPRequestOperation * _Nonnull operation, NSError * _Nonnull error) {
        [error pp_showError];
    }];
}

- (void)login:(NSString *)email withPassword:(NSString *)password success:(void (^)(BOOL result))success failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure; {
    NSDictionary *paramters = @{
                                @"email" : email,
                                @"password" : [self md5:password]
                                };
    
    [self POST:@"users/authenticate" parameters:paramters success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSDictionary *response = (NSDictionary *)responseObject;
        
        if (response[@"result"] && [response[@"result"] boolValue] == NO) {
            success(NO);
        }
        else {
            PPAuthentication *authentication = [MTLJSONAdapter modelOfClass:PPAuthentication.class fromJSONDictionary:response error:nil];
            [PraisePop saveToken:authentication.token email:authentication.user.email];
            [PraisePop saveOrganizations:authentication.user.organizations];
            [PraisePop saveUserAccount:authentication.user];
            
            [PFPush subscribeToChannelInBackground:authentication.user._id block:nil];
            [PFPush subscribeToChannelInBackground:PraisePop.parentOrganization._id block:nil];
            
            if (PraisePop.childOrganization) {
                [PFPush subscribeToChannelInBackground:PraisePop.childOrganization._id block:nil];
            }
            success(YES);
        }
    } failure:^(AFHTTPRequestOperation * _Nonnull operation, NSError * _Nonnull error) {
        [error pp_showError];
    }];
}

- (void)posts:(void (^)(BOOL result, NSArray *))success failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure; {
    NSString *path = [NSString stringWithFormat:@"orgs/%@/posts", PraisePop.parentOrganization._id];

    NSDictionary *paramters = @{
                            @"token" : PraisePop.userToken,
                            @"limit" : @(PRAISE_POP_FEED_LIMIT),
                            @"page" : @(1)
                            };

    [self GET:path parameters:paramters success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSDictionary *response = (NSDictionary *)responseObject;
        
        if (response[@"result"] && [response[@"result"] boolValue] == NO) {
            success(NO, nil);
        }
        else {
            NSMutableArray *posts = [@[] mutableCopy];
            for (NSDictionary *aPost in response[@"data"]) {
                PPPost *post = [MTLJSONAdapter modelOfClass:PPPost.class fromJSONDictionary:aPost error:nil];
                [posts addObject:post];
            }
            
            success(YES, posts);
        }
    } failure:^(AFHTTPRequestOperation * _Nonnull operation, NSError * _Nonnull error) {
        [error pp_showError];
    }];
}

- (void)upvote:(PPPost *)post success:(void (^)(BOOL result))success failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure; {
    NSString *path = [NSString stringWithFormat:@"posts/%@/upvote", post._id];
    
    NSDictionary *parameters = @{
                                 @"token" : PraisePop.userToken
                                 };
    
    [self POST:path parameters:parameters success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSDictionary *response = (NSDictionary *)responseObject;
        
        if (response[@"result"] && [response[@"result"] boolValue] == NO) {
            success(NO);
        }
        else {
            success(YES);
        }
    } failure:failure];
}

- (void)send:(NSString *)postBody type:(NSString *)postType recepient:(NSDictionary *)recipient hashtags:(NSArray *)hashtags success:(void (^)(BOOL))success failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure; {
    NSString *path = [NSString stringWithFormat:@"orgs/%@/posts/new", PraisePop.parentOrganization._id];
    
    NSDictionary *parameters = @{
                                 @"token" : PraisePop.userToken,
                                 @"hashtags" : hashtags,
                                 @"to" : @{
                                     @"name" : recipient
                                 },
                                 @"body" : postBody,
                                 @"type" : postType
                                 };
    
    [self POST:path parameters:parameters success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSDictionary *response = (NSDictionary *)responseObject;
        
        if (response[@"result"] && [response[@"result"] boolValue] == NO) {
            success(NO);
        }
        else {
            success(YES);
        }
    } failure:^(AFHTTPRequestOperation * _Nonnull operation, NSError * _Nonnull error) {
        [error pp_showError];
    }];
}

- (void)post:(PPPost *)post success:(void (^)(BOOL, PPPost *))success failure:(void (^)(AFHTTPRequestOperation *, NSError *))failure {
    NSString *path = [NSString stringWithFormat:@"posts/%@", post._id];

    NSDictionary *parameters = @{
                                 @"token" : PraisePop.userToken
                                 };
    
    [self GET:path parameters:parameters success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSDictionary *response = (NSDictionary *)responseObject;
        
        if (response[@"result"] && [response[@"result"] boolValue] == NO) {
            success(NO, nil);
        }
        else {
            PPPost *post = [MTLJSONAdapter modelOfClass:PPPost.class fromJSONDictionary:response error:nil];
            success(YES, post);
        }
    } failure:^(AFHTTPRequestOperation * _Nonnull operation, NSError * _Nonnull error) {
        [error pp_showError];
    }];
}

- (void)flag:(PPPost *)post success:(void (^)(BOOL))success failure:(void (^)(AFHTTPRequestOperation *, NSError *))failure {
    NSString *path = [NSString stringWithFormat:@"posts/%@/flag", post._id];
    
    NSDictionary *parameters = @{
                                 @"token" : PraisePop.userToken
                                 };
    
    [self POST:path parameters:parameters success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSDictionary *response = (NSDictionary *)responseObject;
        
        if (response[@"result"] && [response[@"result"] boolValue] == NO) {
            success(NO);
        }
        else {
            success(YES);
        }
    } failure:^(AFHTTPRequestOperation * _Nonnull operation, NSError * _Nonnull error) {
        [error pp_showError];
    }];
}

- (void)delete:(PPPost *)post success:(void (^)(BOOL))success failure:(void (^)(AFHTTPRequestOperation *, NSError *))failure {
    NSString *path = [NSString stringWithFormat:@"posts/%@", post._id];
    
    NSDictionary *parameters = @{
                                 @"token" : PraisePop.userToken
                                 };
    
    [self DELETE:path parameters:parameters success:^(AFHTTPRequestOperation * _Nonnull operation, id  _Nonnull responseObject) {
        NSDictionary *response = (NSDictionary *)responseObject;
        
        if (response[@"result"] && [response[@"result"] boolValue] == NO) {
            success(NO);
        }
        else {
            success(YES);
        }
    } failure:^(AFHTTPRequestOperation * _Nonnull operation, NSError * _Nonnull error) {
        [error pp_showError];
    }];
}

- (NSString *)md5:(NSString *)input {
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5( cStr, (int)strlen(cStr), digest );
    
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];
    
    return  output;
}

@end
