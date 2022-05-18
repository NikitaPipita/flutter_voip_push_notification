#import "FlutterVoipPushNotificationPlugin.h"

NSString *const FlutterVoipRemoteNotificationsRegistered = @"voipRemoteNotificationsRegistered";
NSString *const FlutterVoipLocalNotificationReceived = @"voipLocalNotificationReceived";
NSString *const FlutterVoipRemoteNotificationReceived = @"voipRemoteNotificationReceived";

BOOL RunningInAppExtension(void)
{
    return [[[[NSBundle mainBundle] bundlePath] pathExtension] isEqualToString:@"appex"];
}

@implementation FlutterVoipPushNotificationPlugin {
    FlutterMethodChannel* _channel;
    BOOL _resumingFromBackground;
    PKPushRegistry * _voipRegistry;
    BOOL _flutterStarted;
    
}

-(BOOL)flutterStarted {
    return _flutterStarted;
}

-(void)setFlutterStarted:(BOOL)flutterStarted {
    _flutterStarted = flutterStarted;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterVoipPushNotificationPlugin* instance = [[FlutterVoipPushNotificationPlugin alloc] initWithRegistrar:registrar messenger:[registrar messenger]];
    
    [registrar addApplicationDelegate:instance];
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar
                        messenger:(NSObject<FlutterBinaryMessenger>*)messenger{
    
    self = [super init];
    
    if (self) {
        _channel = [FlutterMethodChannel
                    methodChannelWithName:@"com.peerwaya/flutter_voip_push_notification"
                    binaryMessenger:[registrar messenger]];
        [registrar addMethodCallDelegate:self channel:_channel];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleRemoteNotificationsRegistered:)
                                                     name:FlutterVoipRemoteNotificationsRegistered
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleLocalNotificationReceived:)
                                                     name:FlutterVoipLocalNotificationReceived
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleRemoteNotificationReceived:)
                                                     name:FlutterVoipRemoteNotificationReceived
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSString *method = call.method;
    if ([@"requestNotificationPermissions" isEqualToString:method]) {
        if (RunningInAppExtension()) {
            result(nil);
            return;
        }
        [self registerUserNotification:call.arguments result:result];
    }if ([@"checkPermissions" isEqualToString:method]) {
        if (RunningInAppExtension()) {
            result(@{@"alert": @NO, @"badge": @NO, @"sound": @NO});
            return;
        }
        result([self checkPermissions]);
    } if (([@"configure" isEqualToString:method])) {
        _flutterStarted = YES;
        NSLog(@"[FlutterVoipPushNotificationPlugin] handleMethodCall pushData = %@", self.pushData);
        if ([self.pushData count] != 0) {
            for (id value in self.pushData) {
                NSLog(@"[FlutterVoipPushNotificationPlugin] handleMethodCall value = %@", value);
                NSString* callBackName = [value objectForKey: @"method"];
                NSDictionary *notificationPayload = [value objectForKey: @"notification"];
                BOOL isLocal = [value objectForKey: @"local"];
                [_channel invokeMethod:callBackName arguments:@{@"local": @(isLocal), @"notification": notificationPayload}];
            }
        }
    } if ([@"presentLocalNotification" isEqualToString:method]) {
        [self presentLocalNotification:call.arguments];
        result(nil);
    }if ([@"getToken" isEqualToString:method]) {
        result([self getToken]);
    }else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)registerUserNotification:(NSDictionary *)permissions result:(FlutterResult)result
{
    UIUserNotificationType notificationTypes = 0;
    if ([permissions[@"sound"] boolValue]) {
        notificationTypes |= UIUserNotificationTypeSound;
    }
    if ([permissions[@"alert"] boolValue]) {
        notificationTypes |= UIUserNotificationTypeAlert;
    }
    if ([permissions[@"badge"] boolValue]) {
        notificationTypes |= UIUserNotificationTypeBadge;
    }
    UIUserNotificationSettings *settings =
    [UIUserNotificationSettings settingsForTypes:notificationTypes categories:nil];
    [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
    result(nil);
}

- (NSDictionary *)checkPermissions
{
    NSUInteger types = [[UIApplication sharedApplication] currentUserNotificationSettings].types;
    return @{
        @"alert": @((types & UIUserNotificationTypeAlert) > 0),
        @"badge": @((types & UIUserNotificationTypeBadge) > 0),
        @"sound": @((types & UIUserNotificationTypeSound) > 0),
    };
}

- (void)voipRegistration
{
    NSLog(@"[FlutterVoipPushNotificationPlugin] voipRegistration");
    dispatch_queue_t mainQueue = dispatch_get_main_queue();
    // Create a push registry object
    _voipRegistry = [[PKPushRegistry alloc] initWithQueue: mainQueue];
    // Set the registry's delegate to self
    _voipRegistry.delegate = (FlutterVoipPushNotificationPlugin *)[UIApplication sharedApplication].delegate;
    // Set the push type to VoIP
    _voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

- (void)presentLocalNotification:(UILocalNotification *)notification
{
    [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
}

#pragma mark - AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self voipRegistration];
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    _resumingFromBackground = YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    _resumingFromBackground = NO;
}


- (NSString*)getToken
{
    NSMutableString *hexString = [NSMutableString string];
    NSData* token = [_voipRegistry pushTokenForType:PKPushTypeVoIP];
    NSUInteger voipTokenLength = token.length;
    const unsigned char *bytes = token.bytes;
    for (NSUInteger i = 0; i < voipTokenLength; i++) {
        [hexString appendFormat:@"%02x", bytes[i]];
    }
    return hexString;
}

#pragma mark - PKPushRegistryDelegate methods

+ (void)didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type
{
    NSLog(@"[FlutterVoipPushNotificationPlugin] didUpdatePushCredentials credentials.token = %@, type = %@", credentials.token, type);
    
    NSMutableString *hexString = [NSMutableString string];
    NSUInteger voipTokenLength = credentials.token.length;
    const unsigned char *bytes = credentials.token.bytes;
    for (NSUInteger i = 0; i < voipTokenLength; i++) {
        [hexString appendFormat:@"%02x", bytes[i]];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:FlutterVoipRemoteNotificationsRegistered
                                                        object:self
                                                      userInfo:@{@"deviceToken" : [hexString copy]}];
    
}

+ (void)didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type
{
    NSLog(@"[FlutterVoipPushNotificationPlugin] didReceiveIncomingPushWithPayload payload.dictionaryPayload = %@, type = %@", payload.dictionaryPayload, type);
    [[NSNotificationCenter defaultCenter] postNotificationName:FlutterVoipRemoteNotificationReceived
                                                        object:self
                                                      userInfo:payload.dictionaryPayload];
}

- (void)handleRemoteNotificationsRegistered:(NSNotification *)notification
{
    NSLog(@"[FlutterVoipPushNotificationPlugin] handleRemoteNotificationsRegistered notification.userInfo = %@", notification.userInfo);
    [_channel invokeMethod:@"onToken" arguments:notification.userInfo];
}

- (void)handleLocalNotificationReceived:(NSNotification *)notification
{
    if (_resumingFromBackground) {
        NSLog(@"[FlutterVoipPushNotificationPlugin] handleLocalNotificationReceived onResume");
        [self saveOrInvoke:notification.userInfo isLocal:YES callBackName:@"onResume"];
    } else {
        NSLog(@"[FlutterVoipPushNotificationPlugin] handleLocalNotificationReceived onMessage");
        [self saveOrInvoke:notification.userInfo isLocal:YES callBackName:@"onMessage"];
    }
}

- (void)handleRemoteNotificationReceived:(NSNotification *)notification
{
    if (_resumingFromBackground) {
        NSLog(@"[FlutterVoipPushNotificationPlugin] handleRemoteNotificationReceived onResume");
        [self saveOrInvoke:notification.userInfo isLocal:NO callBackName:@"onResume"];
    } else {
        NSLog(@"[FlutterVoipPushNotificationPlugin] handleRemoteNotificationReceived onMessage");
        [self saveOrInvoke:notification.userInfo isLocal:NO callBackName:@"onMessage"];
    }
}

-(void)saveOrInvoke: (NSDictionary*)notificationPayload isLocal:(BOOL)isLocal callBackName:(NSString*)callBackName
{
    NSLog(@"[FlutterVoipPushNotificationPlugin] saveOrInvoke flutterStarted = %d", [self flutterStarted]);
    if ([self flutterStarted]) {
        [_channel invokeMethod:callBackName arguments:@{@"local": @(isLocal), @"notification": notificationPayload}];
    }
    else {
        self.pushData = [NSMutableArray new];
        [self.pushData addObject: [NSDictionary dictionaryWithObjectsAndKeys: callBackName, @"method", @(isLocal), @"local", notificationPayload, @"notification", nil]];
        NSLog(@"[FlutterVoipPushNotificationPlugin] saveOrInvoke pushData = %@", self.pushData);
    }
}


@end
