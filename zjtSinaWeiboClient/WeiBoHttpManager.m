//
//  WeiBoHttpManager.m
//  test
//
//  Created by jianting zhu on 11-12-31.
//  Copyright (c) 2011年 Dunbar Science & Technology. All rights reserved.
//

#import "WeiBoHttpManager.h"
#import "ASINetworkQueue.h"
#import "ASIFormDataRequest.h"
#import "Status.h"
#import "JSON.h"

@implementation WeiBoHttpManager
@synthesize requestQueue;
@synthesize delegate;
@synthesize authCode;
@synthesize authToken;
@synthesize userId;

#pragma mark - Init

-(void)dealloc
{
    self.userId = nil;
    self.authToken = nil;
    self.authCode = nil;
    self.requestQueue = nil;
    [super dealloc];
}

//初始化
- (id)initWithDelegate:(id)theDelegate {
    self = [super init];
    if (self) {
        requestQueue = [[ASINetworkQueue alloc] init];
        [requestQueue setDelegate:self];
        [requestQueue setRequestDidFailSelector:@selector(requestFailed:)];
        [requestQueue setRequestDidFinishSelector:@selector(requestFinished:)];
        [requestQueue setRequestWillRedirectSelector:@selector(request:willRedirectToURL:)];
		[requestQueue setShouldCancelAllRequestsOnFailure:NO];
        [requestQueue setShowAccurateProgress:YES];
        self.delegate = theDelegate;
    }
    return self;
}

#pragma mark - Methods
- (void)setGetUserInfo:(ASIHTTPRequest *)request withRequestType:(RequestType)requestType {
    NSMutableDictionary * dict = [[NSMutableDictionary alloc] init];
    [dict setObject:[NSNumber numberWithInt:requestType] forKey:USER_INFO_KEY_TYPE];
    [request setUserInfo:dict];
    [dict release];
}

- (void)setPostUserInfo:(ASIFormDataRequest *)request withRequestType:(RequestType)requestType {
    NSMutableDictionary * dict = [[NSMutableDictionary alloc] init];
    [dict setObject:[NSNumber numberWithInt:requestType] forKey:USER_INFO_KEY_TYPE];
    [request setUserInfo:dict];
    [dict release];
}

- (NSURL*)generateURL:(NSString*)baseURL params:(NSDictionary*)params {
	if (params) {
		NSMutableArray* pairs = [NSMutableArray array];
		for (NSString* key in params.keyEnumerator) {
			NSString* value = [params objectForKey:key];
			NSString* escaped_value = (NSString *)CFURLCreateStringByAddingPercentEscapes(
																						  NULL, /* allocator */
																						  (CFStringRef)value,
																						  NULL, /* charactersToLeaveUnescaped */
																						  (CFStringRef)@"!*'();:@&=+$,/?%#[]",
																						  kCFStringEncodingUTF8);

            [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
			[escaped_value release];
		}
		
		NSString* query = [pairs componentsJoinedByString:@"&"];
		NSString* url = [NSString stringWithFormat:@"%@?%@", baseURL, query];
		return [NSURL URLWithString:url];
	} else {
		return [NSURL URLWithString:baseURL];
	}
}

//提取用户ID
- (NSString *) extractUsernameFromHTTPBody: (NSString *) body {
	if (!body) {
        return nil;
    }
	
	NSArray	*tuples = [body componentsSeparatedByString: @"&"];
	if (tuples.count < 1) {
        return nil;
    }
	
	for (NSString *tuple in tuples) {
		NSArray *keyValueArray = [tuple componentsSeparatedByString: @"="];
		
		if (keyValueArray.count == 2) {
			NSString    *key = [keyValueArray objectAtIndex: 0];
			NSString    *value = [keyValueArray objectAtIndex: 1];
			
			if ([key isEqualToString:@"screen_name"]) return value;
			if ([key isEqualToString:@"user_id"]) return value;
		}
	}
	return nil;
}

#pragma mark - Http Operate
//获取auth_code or access_token
-(NSURL*)getOauthCodeUrl //留给webview用
{
    //https://api.weibo.com/oauth2/authorize
    
    NSMutableDictionary* params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
								   SINA_APP_KEY,        @"client_id",       //申请的appkey
								   @"token",            @"response_type",   //access_token
								   @"",                 @"redirect_uri",    //申请时的重定向地址
								   @"wap2.0",           @"display",         //web页面的显示方式
                                   nil];
	
	NSURL *url = [self generateURL:SINA_API_AUTHORIZE params:params];
	NSLog(@"url= %@",url);
    return url;
}

//获取access_token
//-(void)getAccessToken
//{
//    //https://api.weibo.com/oauth2/access_token
//    NSURL *url = [NSURL URLWithString:SINA_API_ACCESS_TOKEN];
//    ASIFormDataRequest *item = [[ASIFormDataRequest alloc] initWithURL:url];
//    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
//    if (!authToken) {
//        return;
//    }
//    [item setPostValue:SINA_APP_KEY             forKey:@"client_id"];
//    [item setPostValue:SINA_APP_SECRET          forKey:@"client_secret"];
//    [item setPostValue:@"authorization_code"    forKey:@"grant_type"];
//    
//    [item setPostValue:authToken                forKey:@"code"];
//    [item setPostValue:@""                      forKey:@"redirect_uri"];
//    
//    [self setPostUserInfo:item withRequestType:SinaGetOauthToken];
//    [requestQueue addOperation:item];
//    [item release];
//}

-(void)getPublicTimelineWithCount:(int)count withPage:(int)page
{
    //https://api.weibo.com/2/statuses/public_timeline.json
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    NSString                *countString = [NSString stringWithFormat:@"%d",count];
    NSString                *pageString = [NSString stringWithFormat:@"%d",page];
    NSMutableDictionary     *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       authToken,   @"access_token",
                                       countString, @"count",
                                       pageString,  @"page",
                                       nil];
    NSString                *baseUrl =[NSString  stringWithFormat:@"%@/statuses/public_timeline.json",SINA_V2_DOMAIN];
    NSURL                   *url = [self generateURL:baseUrl params:params];
    
    ASIHTTPRequest *request = [[ASIHTTPRequest alloc] initWithURL:url];
    NSLog(@"url=%@",url);
    [self setGetUserInfo:request withRequestType:SinaGetPublicTimeline];
    [requestQueue addOperation:request];
    [request release];
}

//获取登陆用户的UID
-(void)getUserID
{
    //https://api.weibo.com/2/account/get_uid.json
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    NSMutableDictionary     *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       authToken,   @"access_token",
                                       nil];
    NSString                *baseUrl = [NSString  stringWithFormat:@"%@/account/get_uid.json",SINA_V2_DOMAIN];
    NSURL                   *url = [self generateURL:baseUrl params:params];
    
    ASIHTTPRequest *request = [[ASIHTTPRequest alloc] initWithURL:url];
    NSLog(@"url=%@",url);
    [self setGetUserInfo:request withRequestType:SinaGetUserID];
    [requestQueue addOperation:request];
    [request release];
}

//获取任意一个用户的信息
-(void)getUserInfoWithUserID:(long long)uid
{
    //https://api.weibo.com/2/users/show.json
    
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    self.userId = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_USER_ID];
    
    NSMutableDictionary     *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       authToken,                                   @"access_token",
                                       [NSString stringWithFormat:@"%lld",uid],     @"uid",
                                       nil];
    NSString                *baseUrl =[NSString  stringWithFormat:@"%@/users/show.json",SINA_V2_DOMAIN];
    NSURL                   *url = [self generateURL:baseUrl params:params];
    
    ASIHTTPRequest *request = [[ASIHTTPRequest alloc] initWithURL:url];
    NSLog(@"url=%@",url);
    [self setGetUserInfo:request withRequestType:SinaGetUserInfo];
    [requestQueue addOperation:request];
    [request release];
}

//获取用户双向关注的用户ID列表，即互粉UID列表
-(void)getBilateralIdList:(long long)uid count:(int)count page:(int)page sort:(int)sort
{
    //https://api.weibo.com/2/friendships/friends/bilateral/ids.json
    
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    self.userId = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_USER_ID];
    
    NSMutableDictionary     *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       authToken,                                   @"access_token",
                                       [NSString stringWithFormat:@"%lld",uid],     @"uid",
                                       [NSString stringWithFormat:@"%d",count],     @"count",
                                       [NSString stringWithFormat:@"%d",page],      @"page",
                                       [NSString stringWithFormat:@"%d",sort],      @"sort",
                                       nil];
    NSString                *baseUrl =[NSString  stringWithFormat:@"%@/friendships/friends/bilateral/ids.json",SINA_V2_DOMAIN];
    NSURL                   *url = [self generateURL:baseUrl params:params];
    
    ASIHTTPRequest *request = [[ASIHTTPRequest alloc] initWithURL:url];
    NSLog(@"url=%@",url);
    [self setGetUserInfo:request withRequestType:SinaGetBilateralIdList];
    [requestQueue addOperation:request];
    [request release];
}

//获取用户双向关注的用户ID列表，即互粉UID列表 不分页
-(void)getBilateralIdListAll:(long long)uid sort:(int)sort
{
    //https://api.weibo.com/2/friendships/friends/bilateral/ids.json
    
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    self.userId = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_USER_ID];
    
    NSMutableDictionary     *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       authToken,                                   @"access_token",
                                       [NSString stringWithFormat:@"%lld",uid],     @"uid",
                                       [NSString stringWithFormat:@"%d",sort],      @"sort",
                                       nil];
    NSString                *baseUrl =[NSString  stringWithFormat:@"%@/friendships/friends/bilateral/ids.json",SINA_V2_DOMAIN];
    NSURL                   *url = [self generateURL:baseUrl params:params];
    
    ASIHTTPRequest *request = [[ASIHTTPRequest alloc] initWithURL:url];
    NSLog(@"url=%@",url);
    [self setGetUserInfo:request withRequestType:SinaGetBilateralIdListAll];
    [requestQueue addOperation:request];
    [request release];
}

//获取用户的双向关注user列表，即互粉列表
-(void)getBilateralUserList:(long long)uid count:(int)count page:(int)page sort:(int)sort
{
    //https://api.weibo.com/2/friendships/friends/bilateral.json
    
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    self.userId = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_USER_ID];
    
    NSMutableDictionary     *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       authToken,                                   @"access_token",
                                       [NSString stringWithFormat:@"%lld",uid],     @"uid",
                                       [NSString stringWithFormat:@"%d",count],     @"count",
                                       [NSString stringWithFormat:@"%d",page],      @"page",
                                       [NSString stringWithFormat:@"%d",sort],      @"sort",
                                       nil];
    NSString                *baseUrl =[NSString  stringWithFormat:@"%@/friendships/friends/bilateral.json",SINA_V2_DOMAIN];
    NSURL                   *url = [self generateURL:baseUrl params:params];
    
    ASIHTTPRequest *request = [[ASIHTTPRequest alloc] initWithURL:url];
    NSLog(@"url=%@",url);
    [self setGetUserInfo:request withRequestType:SinaGetBilateralUserList];
    [requestQueue addOperation:request];
    [request release];
}

//获取用户双向关注的用户user列表，即互粉user列表 不分页
-(void)getBilateralUserListAll:(long long)uid sort:(int)sort
{
    //https://api.weibo.com/2/friendships/friends/bilateral/ids.json
    
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    self.userId = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_USER_ID];
    
    NSMutableDictionary     *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       authToken,                                   @"access_token",
                                       [NSString stringWithFormat:@"%lld",uid],     @"uid",
                                       [NSString stringWithFormat:@"%d",sort],      @"sort",
                                       nil];
    NSString                *baseUrl =[NSString  stringWithFormat:@"%@/friendships/friends/bilateral.json",SINA_V2_DOMAIN];
    NSURL                   *url = [self generateURL:baseUrl params:params];
    
    ASIHTTPRequest *request = [[ASIHTTPRequest alloc] initWithURL:url];
    NSLog(@"url=%@",url);
    [self setGetUserInfo:request withRequestType:SinaGetBilateralUserListAll];
    [requestQueue addOperation:request];
    [request release];
}

//关注一个用户 by User ID
-(void)followByUserID:(long long)uid
{
    //https://api.weibo.com/2/friendships/create.json
    NSURL *url = [NSURL URLWithString:@"https://api.weibo.com/2/friendships/create.json"];
    ASIFormDataRequest *item = [[ASIFormDataRequest alloc] initWithURL:url];
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    
    [item setPostValue:authToken                                forKey:@"access_token"];
    [item setPostValue:[NSString stringWithFormat:@"%lld",uid]  forKey:@"uid"];
    
    [self setPostUserInfo:item withRequestType:SinaFollowByUserID];
    [requestQueue addOperation:item];
    [item release];
}

//关注一个用户 by User Name
-(void)followByUserName:(NSString*)userName
{
    //https://api.weibo.com/2/friendships/create.json
    NSURL *url = [NSURL URLWithString:@"https://api.weibo.com/2/friendships/create.json"];
    ASIFormDataRequest *item = [[ASIFormDataRequest alloc] initWithURL:url];
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    
    [item setPostValue:authToken    forKey:@"access_token"];
    [item setPostValue:userName     forKey:@"screen_name"];
    
    [self setPostUserInfo:item withRequestType:SinaFollowByUserName];
    [requestQueue addOperation:item];
    [item release];
}

//取消关注一个用户 by User ID
-(void)unfollowByUserID:(long long)uid
{
    //https://api.weibo.com/2/friendships/destroy.json
    NSURL *url = [NSURL URLWithString:@"https://api.weibo.com/2/friendships/destroy.json"];
    ASIFormDataRequest *item = [[ASIFormDataRequest alloc] initWithURL:url];
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    
    [item setPostValue:authToken                                forKey:@"access_token"];
    [item setPostValue:[NSString stringWithFormat:@"%lld",uid]  forKey:@"uid"];
    
    [self setPostUserInfo:item withRequestType:SinaUnfollowByUserID];
    [requestQueue addOperation:item];
    [item release];
}

//取消关注一个用户 by User Name
-(void)unfollowByUserName:(NSString*)userName
{
    //https://api.weibo.com/2/friendships/destroy.json
    NSURL *url = [NSURL URLWithString:@"https://api.weibo.com/2/friendships/destroy.json"];
    ASIFormDataRequest *item = [[ASIFormDataRequest alloc] initWithURL:url];
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    
    [item setPostValue:authToken    forKey:@"access_token"];
    [item setPostValue:userName     forKey:@"screen_name"];
    
    [self setPostUserInfo:item withRequestType:SinaUnfollowByUserName];
    [requestQueue addOperation:item];
    [item release];
}

//获取某话题下的微博消息
-(void)getTrendStatues:(NSString *)trendName
{   
    //http://api.t.sina.com.cn/trends/statuses.json
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    NSMutableDictionary     *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       SINA_APP_KEY,@"source",
                                       [trendName encodeAsURIComponent],@"trend_name",
                                       nil];
    NSString                *baseUrl = @"http://api.t.sina.com.cn/trends/statuses.json";
    NSURL                   *url = [self generateURL:baseUrl params:params];
    ASIHTTPRequest *request = [[ASIHTTPRequest alloc] initWithURL:url];
    NSLog(@"url=%@",url);
    [self setGetUserInfo:request withRequestType:SinaGetTrendStatues];
    [requestQueue addOperation:request];
    [request release];
}

//关注某话题
-(void)followTrend:(NSString*)trendName
{
    //https://api.weibo.com/2/trends/follow.json
    NSURL *url = [NSURL URLWithString:@"https://api.weibo.com/2/trends/follow.json"];
    ASIFormDataRequest *item = [[ASIFormDataRequest alloc] initWithURL:url];
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    
    [item setPostValue:authToken    forKey:@"access_token"];
    [item setPostValue:trendName    forKey:@"trend_name"];
    
    [self setPostUserInfo:item withRequestType:SinaFollowTrend];
    [requestQueue addOperation:item];
    [item release];
}

//取消对某话题的关注
-(void)unfollowTrend:(long long)trendID
{
    //https://api.weibo.com/2/trends/destroy.json 
    NSURL *url = [NSURL URLWithString:@"https://api.weibo.com/2/trends/destroy.json"];
    ASIFormDataRequest *item = [[ASIFormDataRequest alloc] initWithURL:url];
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    
    [item setPostValue:authToken                                    forKey:@"access_token"];
    [item setPostValue:[NSString stringWithFormat:@"%lld",trendID]   forKey:@"trend_id"];
    NSLog(@"trendID = %lld",trendID);
    [self setPostUserInfo:item withRequestType:SinaUnfollowTrend];
    [requestQueue addOperation:item];
    [item release];
}


//发布文字微博
-(void)postWithText:(NSString*)text
{
    //https://api.weibo.com/2/statuses/update.json
    NSURL *url = [NSURL URLWithString:@"https://api.weibo.com/2/statuses/update.json"];
    ASIFormDataRequest *item = [[ASIFormDataRequest alloc] initWithURL:url];
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    
    [item setPostValue:authToken    forKey:@"access_token"];
    [item setPostValue:text         forKey:@"status"];
    
    [self setPostUserInfo:item withRequestType:SinaPostText];
    [requestQueue addOperation:item];
    [item release];
}

//发布文字图片微博
-(void)postWithText:(NSString *)text imageName:(NSString*)imageName
{
    //https://api.weibo.com/2/statuses/upload.json
    NSURL *url = [NSURL URLWithString:@"https://api.weibo.com/2/statuses/upload.json"];
    ASIFormDataRequest *item = [[ASIFormDataRequest alloc] initWithURL:url];
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    
    NSString *path = [[NSBundle mainBundle] bundlePath];
    NSString *finalPath = [path stringByAppendingPathComponent:imageName];
    
    [item setPostValue:authToken    forKey:@"access_token"];
    [item setPostValue:text         forKey:@"status"];
    [item setFile:finalPath         forKey:@"pic"];
    
    [self setPostUserInfo:item withRequestType:SinaPostTextAndImage];
    [requestQueue addOperation:item];
    [item release];
}

//获取当前登录用户及其所关注用户的最新微博
-(void)getHomeLine:(int64_t)sinceID maxID:(int64_t)maxID count:(int)count page:(int)page baseApp:(int)baseApp feature:(int)feature
{
    //https://api.weibo.com/2/statuses/home_timeline.json
    
    self.authToken = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_ACCESS_TOKEN];
    self.userId = [[NSUserDefaults standardUserDefaults] objectForKey:USER_STORE_USER_ID];
    
    NSMutableDictionary     *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:authToken,@"access_token",nil];
    if (sinceID >= 0) {
        NSString *tempString = [NSString stringWithFormat:@"%lld",sinceID];
        [params setObject:tempString forKey:@"since_id"];
    }
    if (maxID >= 0) {
        NSString *tempString = [NSString stringWithFormat:@"%lld",maxID];
        [params setObject:tempString forKey:@"max_id"];
    }
    if (count >= 0) {
        NSString *tempString = [NSString stringWithFormat:@"%d",count];
        [params setObject:tempString forKey:@"count"];
    }
    if (page >= 0) {
        NSString *tempString = [NSString stringWithFormat:@"%d",page];
        [params setObject:tempString forKey:@"page"];
    }
    if (baseApp >= 0) {
        NSString *tempString = [NSString stringWithFormat:@"%d",baseApp];
        [params setObject:tempString forKey:@"baseApp"];
    }
    if (feature >= 0) {
        NSString *tempString = [NSString stringWithFormat:@"%d",feature];
        [params setObject:tempString forKey:@"feature"];
    }
    
    NSString                *baseUrl =[NSString  stringWithFormat:@"%@/statuses/home_timeline.json",SINA_V2_DOMAIN];
    NSURL                   *url = [self generateURL:baseUrl params:params];
    
    ASIHTTPRequest *request = [[ASIHTTPRequest alloc] initWithURL:url];
    NSLog(@"url=%@",url);
    [self setGetUserInfo:request withRequestType:SinaGetHomeLine];
    [requestQueue addOperation:request];
    [request release];
}

#pragma mark - Http Result

#pragma mark - Operate queue
- (BOOL)isRunning
{
	return ![requestQueue isSuspended];
}

- (void)start
{
	if( [requestQueue isSuspended] )
		[requestQueue go];
}

- (void)pause
{
	[requestQueue setSuspended:YES];
}

- (void)resume
{
	[requestQueue setSuspended:NO];
}

- (void)cancel
{
	[requestQueue cancelAllOperations];
}

#pragma mark - ASINetworkQueueDelegate
//失败
- (void)requestFailed:(ASIHTTPRequest *)request{
    NSLog(@"requestFailed");
}

//成功
- (void)requestFinished:(ASIHTTPRequest *)request{
    NSDictionary *userInfo = [request userInfo];
    RequestType requestType = [[userInfo objectForKey:USER_INFO_KEY_TYPE] intValue];
    NSString * responseString = [request responseString];
    NSLog(@"responseString = %@",responseString);
    
    //认证失败
    //{"error":"auth faild!","error_code":21301,"request":"/2/statuses/home_timeline.json"}
    SBJsonParser    *parser     = [[SBJsonParser alloc] init];    
    id  returnObject = [parser objectWithString:responseString];
    [parser release];
    if ([returnObject isKindOfClass:[NSDictionary class]]) {
        NSString *errorString = [returnObject  objectForKey:@"error"];
        if (errorString != nil && [errorString isEqualToString:@"auth faild!"]) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:USER_STORE_ACCESS_TOKEN];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:USER_STORE_USER_ID];
            NSLog(@"detected auth faild!");
        }
    }
    
    //获取最新的公共微博
    if (requestType == SinaGetPublicTimeline) {
        SBJsonParser    *parser     = [[SBJsonParser alloc] init];    
        NSDictionary    *info       = [parser objectWithString:responseString];
        NSArray         *arr        = [info objectForKey:@"statuses"];
        NSMutableArray  *statuesArr = [[NSMutableArray alloc]initWithCapacity:0];
        for (id item in arr) {
            Status* sts = [Status statusWithJsonDictionary:item];
            [statuesArr addObject:sts];
        }
        [parser release];
        if ([delegate respondsToSelector:@selector(didGetPublicTimelineWithStatues:)]) {
            [delegate didGetPublicTimelineWithStatues:statuesArr];
        }
        [statuesArr release];
    }
    
    //获取登陆用户ID
    if (requestType == SinaGetUserID) {
        SBJsonParser *parser = [[SBJsonParser alloc] init];    
        NSDictionary *info = [parser objectWithString:responseString];
        NSNumber *userID = [info objectForKey:@"uid"];
        self.userId = [NSString stringWithFormat:@"%@",userID];
        [[NSUserDefaults standardUserDefaults] setObject:userID forKey:USER_STORE_USER_ID];
        [parser release];
        if ([delegate respondsToSelector:@selector(didGetUserID:)]) {
            [delegate didGetUserID:userId];
        }
    }
    
    //获取任意一个用户的信息
    if (requestType == SinaGetUserInfo) {
        SBJsonParser *parser = [[SBJsonParser alloc] init];    
        NSDictionary *userInfo = [parser objectWithString:responseString];
        User *user = [[User alloc]initWithJsonDictionary:userInfo];
        [parser release];
        if ([delegate respondsToSelector:@selector(didGetUserInfo:)]) {
            [delegate didGetUserInfo:user];
        }
        [user release];
    }
    
    //获取用户双向关注的用户ID列表，即互粉UID列表
    if (requestType == SinaGetBilateralIdList || requestType == SinaGetBilateralIdListAll) {
        SBJsonParser *parser = [[SBJsonParser alloc] init];    
        NSDictionary *userInfo = [parser objectWithString:responseString];
        NSArray *arr = [userInfo objectForKey:@"ids"];
        [parser release];
        if ([delegate respondsToSelector:@selector(didGetBilateralIdList:)]) {
            [delegate didGetBilateralIdList:arr];
        }
    }
    
    //获取用户的双向关注user列表，即互粉列表
    if (requestType == SinaGetBilateralUserList || requestType == SinaGetBilateralUserListAll) {
        SBJsonParser *parser = [[SBJsonParser alloc] init];    
        NSDictionary *userInfo = [parser objectWithString:responseString];
        NSArray *arr = [userInfo objectForKey:@"users"];
        NSMutableArray *userArr = [[NSMutableArray alloc]initWithCapacity:0];
        for (id item in arr) {
            User *user = [[User alloc]initWithJsonDictionary:item];
            [userArr addObject:user];
            [user release];
        }
        [parser release];
        if ([delegate respondsToSelector:@selector(didGetBilateralUserList:)]) {
            [delegate didGetBilateralUserList:userArr];
        }
        [userArr release];
    }
    
    //关注一个用户 by User ID or Name
    if (requestType == SinaFollowByUserID || requestType == SinaFollowByUserName) {
        int result = 1;
        SBJsonParser *parser = [[SBJsonParser alloc] init];    
        NSDictionary *userInfo = [parser objectWithString:responseString];
        id ID = [userInfo objectForKey:@"id"];
        
        if (ID != nil && ID != [NSNull null]) {
            result = 0; //succeed
        }
        else
        {
            result = 1; //failed
        }
        [parser release];
        if ([delegate respondsToSelector:@selector(didFollowByUserIDWithResult:)]) {
            [delegate didFollowByUserIDWithResult:result];
        }
    }
    
    //取消关注一个用户 by User ID or Name
    if (requestType == SinaUnfollowByUserID || requestType == SinaUnfollowByUserName) {
        int result = 1;
        SBJsonParser *parser = [[SBJsonParser alloc] init];    
        NSDictionary *userInfo = [parser objectWithString:responseString];
        id ID = [userInfo objectForKey:@"id"];
        
        if (ID != nil && ID != [NSNull null]) {
            result = 0; //succeed
        }
        else
        {
            result = 1; //failed
        }
        [parser release];
        if ([delegate respondsToSelector:@selector(didUnfollowByUserIDWithResult:)]) {
            [delegate didUnfollowByUserIDWithResult:result];
        }
    }
    
    //
    if (requestType == SinaGetTrendStatues) {
        SBJsonParser    *parser     = [[SBJsonParser alloc] init];   
        NSArray         *arr        = [parser objectWithString:responseString];
        NSMutableArray  *statuesArr = [[NSMutableArray alloc]initWithCapacity:0];
        for (id item in arr) {
            Status* sts = [Status statusWithJsonDictionary:item];
            [statuesArr addObject:sts];
        }
        [parser release];
        if ([delegate respondsToSelector:@selector(didGetTrendStatues:)]) {
            [delegate didGetTrendStatues:statuesArr];
        }
        [statuesArr release];
    }
    
    //关注某话题
    if (requestType == SinaFollowTrend) {
        SBJsonParser *parser = [[SBJsonParser alloc] init];    
        NSDictionary *userInfo = [parser objectWithString:responseString];
        int64_t topicID = [[userInfo objectForKey:@"topicid"] longLongValue];
        [parser release];
        if ([delegate respondsToSelector:@selector(didGetTrendIDAfterFollowed:)]) {
            [delegate didGetTrendIDAfterFollowed:topicID];
        }
    }
    
    //取消对某话题的关注
    if (requestType == SinaUnfollowTrend) {
        SBJsonParser *parser = [[SBJsonParser alloc] init];    
        NSDictionary *userInfo = [parser objectWithString:responseString];
        BOOL isTrue = [[userInfo objectForKey:@"result"] boolValue];
        [parser release];
        if ([delegate respondsToSelector:@selector(didGetTrendResultAfterUnfollowed:)]) {
            [delegate didGetTrendResultAfterUnfollowed:isTrue];
        }
    }
    
    //发布文字微博 & 图文微博
    if (requestType ==SinaPostText || requestType == SinaPostTextAndImage) {
        SBJsonParser *parser = [[SBJsonParser alloc] init];    
        NSDictionary *userInfo = [parser objectWithString:responseString];
        Status* sts = [Status statusWithJsonDictionary:userInfo];
        [parser release];
        if ([delegate respondsToSelector:@selector(didGetPostResult:)]) {
            [delegate didGetPostResult:sts];
        }
    }
    
    //获取当前登录用户及其所关注用户的最新微博
    if (requestType == SinaGetHomeLine) {
        SBJsonParser    *parser     = [[SBJsonParser alloc] init];    
        NSDictionary    *info       = [parser objectWithString:responseString];
        NSArray         *arr        = [info objectForKey:@"statuses"];
        [parser release];
        
        if (arr == nil || [arr isEqual:[NSNull null]]) 
        {
            if ([delegate respondsToSelector:@selector(didGetHomeLine:)]) {
                [delegate didGetHomeLine:[NSArray arrayWithObject:info]];
                return;
            }
        }
        
        NSMutableArray  *statuesArr = [[NSMutableArray alloc]initWithCapacity:0];
        for (id item in arr) {
            Status* sts = [Status statusWithJsonDictionary:item];
            [statuesArr addObject:sts];
        }
        if ([delegate respondsToSelector:@selector(didGetHomeLine:)]) {
            [delegate didGetHomeLine:statuesArr];
        }
        [statuesArr release];
    }
}

//跳转
- (void)request:(ASIHTTPRequest *)request willRedirectToURL:(NSURL *)newURL {
    NSLog(@"request will redirect");
}

@end
