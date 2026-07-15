#import "BudsTLSOptions.h"

#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>

void BudsConfigureTLSPSK(sec_protocol_options_t options, const char *pairingCode) {
    NSString *code = [NSString stringWithUTF8String:pairingCode] ?: @"";
    NSData *input = [[NSString stringWithFormat:@"BudsBridge/v1:%@", code]
        dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(input.bytes, (CC_LONG)input.length, digest);

    NSData *key = [NSData dataWithBytes:digest length:sizeof(digest)];
    NSData *identity = [@"BudsControl-v1" dataUsingEncoding:NSUTF8StringEncoding];
    dispatch_data_t keyData = dispatch_data_create(key.bytes, key.length,
        dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ (void)key; });
    dispatch_data_t identityData = dispatch_data_create(identity.bytes, identity.length,
        dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ (void)identity; });

    sec_protocol_options_set_min_tls_protocol_version(options, tls_protocol_version_TLSv12);
    sec_protocol_options_set_max_tls_protocol_version(options, tls_protocol_version_TLSv12);
    sec_protocol_options_append_tls_ciphersuite(options, TLS_PSK_WITH_AES_128_GCM_SHA256);
    sec_protocol_options_add_pre_shared_key(options, keyData, identityData);
}
