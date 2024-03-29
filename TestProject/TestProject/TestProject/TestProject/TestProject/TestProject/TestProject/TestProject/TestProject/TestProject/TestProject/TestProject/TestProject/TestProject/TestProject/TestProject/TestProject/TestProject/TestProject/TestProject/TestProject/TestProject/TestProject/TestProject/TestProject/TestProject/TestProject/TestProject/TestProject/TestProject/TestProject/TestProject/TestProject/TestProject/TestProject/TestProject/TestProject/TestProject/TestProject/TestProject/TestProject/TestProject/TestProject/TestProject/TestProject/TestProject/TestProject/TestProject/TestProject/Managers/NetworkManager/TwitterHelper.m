//
//  OCTwitterHelper.m
//
//  Created by Serg Shulga on 6/24/14.
//  Copyright (c) 2014 Voxience. All rights reserved.
//

#import "TwitterHelper.h"
#import <Social/Social.h>
#import <Accounts/Accounts.h>
#import "const.h"
#import "TPDBManager.h"

#define TWT_SEARCH_TWEETS_URL         @"https://api.twitter.com/1.1/search/tweets.json"

static TwitterHelper* twitterHelperInstance = nil;

@interface TwitterHelper ()

@property (nonatomic, strong) ACAccount* currentAccount;

@property (nonatomic, strong) NSManagedObjectContext* context;

@end

@implementation TwitterHelper

#pragma mark - General

+ (instancetype) shared
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        twitterHelperInstance = [TwitterHelper new];
    });
    return twitterHelperInstance;
}

- (id) init
{
    if (self = [super init])
    {
        self.context = [TPDBManager getNewDBContext];
    }
    return self;
}

#pragma mark - Login 

- (void) loginTwitterSuccess:(void (^)(NSDictionary *))successBlock failure:(void (^)(NSError *))failure
{
    [self getTwitterAccountsWithCompletionBlock:^(NSArray *twitterAccounts, NSError *error)
    {
        
        if(error != nil)
        {
            if(failure != nil)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
        }
        
        if(twitterAccounts.count > 0)
        {
            ACAccount *twitterAccount = [twitterAccounts lastObject];
            self.currentAccount = twitterAccount;
            successBlock(nil);
        }
        
    }];
}

#pragma mark - Public

- (void) getNextTweetsWithSuccessBlock: (void (^)(NSArray *tweets)) success failure: (void (^)(NSError *error)) failure
{
    NSURL *url = [NSURL URLWithString: TWT_SEARCH_TWEETS_URL];
    NSDictionary *params = @{@"q": @"ukraine"};
    SLRequest *searchRequest = [self requestWithUrl: url parameters: params requestMethod:SLRequestMethodGET];
    [searchRequest setAccount: self.currentAccount];
    [searchRequest performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError* error;
            NSDictionary* response = [NSJSONSerialization JSONObjectWithData:responseData
                                                                 options:kNilOptions
                                                                   error:&error];

            if(error)
            {
                failure(error);
            }
            else
            {
                NSArray* tweetsArray = response[@"statuses"];
                NSMutableArray* tweets = [NSMutableArray array];
                for (NSDictionary* tweetDict in tweetsArray) {
                    Tweet* tweet = [TPDBManager createTweetFromDictionary: tweetDict
                                                                inContext: self.context];
                    if(tweet)
                        [tweets addObject: tweet];
                }
                success(tweets);

            }
            
        });
    }];
}

#pragma mark - Private

- (void) getTwitterAccountsWithCompletionBlock: (void(^)(NSArray* twitterAccounts, NSError* error)) completionBlock
{
    static ACAccountStore *accountStore;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        accountStore = [[ACAccountStore alloc] init];
    });
    
    ACAccountType *accountType = [accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    
    [accountStore requestAccessToAccountsWithType: accountType options: nil completion: ^(BOOL granted, NSError *error)
     {
         if(error == nil)
         {
             // Did user allow us access?
             if(granted == YES)
             {
                 // Populate array with all available Twitter accounts
                 NSArray *arrayOfAccounts = [accountStore accountsWithAccountType:accountType];
                 
                 self.twitterAccounts = arrayOfAccounts;
                 
                 if (self.twitterAccounts == nil || self.twitterAccounts.count == 0)
                 {
                     error = [NSError errorWithDomain:@"Twitter" code:SNNoAccountErrorCode userInfo:@{NSLocalizedDescriptionKey:@"Please login to Twitter in the device Settings"}];
                 }
                 
                 if(completionBlock != nil)
                 {
                     completionBlock(arrayOfAccounts, error);
                 }
             }
             else
             {
                 NSError *localError = [NSError errorWithDomain:NSStringFromClass(self.class) code:SNAccessDisabledCode userInfo:@{NSLocalizedDescriptionKey:@"Twitter access disabled"}];
                 if(completionBlock != nil)
                 {
                     completionBlock(nil, localError);
                 }
             }
         }
         else
         {
             if (error.code == SNNoAccountErrorCode)
             {
                 error = [NSError errorWithDomain:error.domain code:SNNoAccountErrorCode userInfo:@{NSLocalizedDescriptionKey:@"Please login to Twitter in the device Settings"}];
             }
             if(completionBlock != nil)
             {
                 completionBlock(nil, error);
             }
         }
     }];
}

- (SLRequest *)requestWithUrl:(NSURL *)url parameters:(NSDictionary *)dict requestMethod:(SLRequestMethod)requestMethod
{
    return [SLRequest requestForServiceType:SLServiceTypeTwitter requestMethod:requestMethod URL:url parameters:dict];
}

@end
