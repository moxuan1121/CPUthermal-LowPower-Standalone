#import <Foundation/Foundation.h>
#import <notify.h>
#include <stdint.h>

static const char *CTForegroundNotification = "com.mox1121.cpulowpower/foreground";
static const char *CTSettingsNotification = "com.mox1121.cpulowpower/settingsChanged";

static inline uint64_t CTBundleHash(NSString *identifier) {
    const unsigned char *p = (const unsigned char *)identifier.UTF8String;
    if (!p || !*p) return 0;
    uint64_t h = UINT64_C(1469598103934665603);
    while (*p) { h ^= *p++; h *= UINT64_C(1099511628211); }
    return h ?: 1;
}

static inline uint64_t CTForegroundHash(void) {
    int token;
    uint64_t value = 0;
    if (notify_register_check(CTForegroundNotification, &token) == NOTIFY_STATUS_OK) {
        notify_get_state(token, &value);
        notify_cancel(token);
    }
    return value;
}

static inline void CTPublishForeground(NSString *identifier) {
    int token;
    if (notify_register_check(CTForegroundNotification, &token) != NOTIFY_STATUS_OK) return;
    notify_set_state(token, CTBundleHash(identifier));
    notify_post(CTForegroundNotification);
    notify_cancel(token);
}
