#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

static void printJSON(NSDictionary *result) {
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:&error];
  if (!data) return;
  fwrite(data.bytes, 1, data.length, stdout);
  fflush(stdout);
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    if (argc == 3 && strcmp(argv[1], "--send") == 0) {
      NSError *error = nil;
      NSData *data = [NSData dataWithContentsOfFile:@(argv[2]) options:0 error:&error];
      id payload = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
      if (![payload isKindOfClass:NSDictionary.class]
          || ![payload[@"title"] isKindOfClass:NSString.class]
          || ![payload[@"message"] isKindOfClass:NSString.class]) {
        fprintf(stderr, "Invalid notification payload\n");
        return 1;
      }
      __block int status = 1;
      void (^send)(void) = ^{
        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
        content.title = payload[@"title"];
        content.body = payload[@"message"];
        NSString *image = payload[@"image"];
        if ([image isKindOfClass:NSString.class] && image.length > 0) {
          NSError *attachError = nil;
          NSURL *url = [NSURL fileURLWithPath:image];
          UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:@"avatar" URL:url options:nil error:&attachError];
          if (attachment) content.attachments = @[attachment];
          else if (attachError) fprintf(stderr, "Avatar attachment skipped: %s\n", attachError.localizedDescription.UTF8String);
        }
        NSString *identifier = NSUUID.UUID.UUIDString;
        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil];
        [center addNotificationRequest:request withCompletionHandler:^(NSError *sendError) {
          if (sendError) fprintf(stderr, "Notification rejected: %s\n", sendError.localizedDescription.UTF8String);
          else {
            printJSON(@{@"accepted": @YES, @"notificationId": identifier});
            status = 0;
          }
          dispatch_semaphore_signal(done);
        }];
      };
      [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
          [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert completionHandler:^(BOOL granted, NSError *authError) {
            if (granted) send();
            else {
              fprintf(stderr, "Notification permission not granted\n");
              dispatch_semaphore_signal(done);
            }
          }];
        } else if (settings.authorizationStatus == UNAuthorizationStatusDenied || settings.alertSetting != UNNotificationSettingEnabled) {
          fprintf(stderr, "Notification alerts disabled\n");
          dispatch_semaphore_signal(done);
        } else {
          send();
        }
      }];
      if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) != 0) {
        fprintf(stderr, "Notification delivery timed out\n");
        return 1;
      }
      return status;
    }
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
      printJSON(@{
        @"bundleId": NSBundle.mainBundle.bundleIdentifier ?: @"",
        @"authorizationStatus": @(settings.authorizationStatus),
        @"alertSetting": @(settings.alertSetting),
        @"alertStyle": @(settings.alertStyle)
      });
      dispatch_semaphore_signal(done);
    }];
    return dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0 ? 0 : 1;
  }
}
