#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>
#import <Network/Network.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

static const uuid_t kSamsungServiceUUID = {
    0x2E, 0x73, 0xA4, 0xAD, 0x33, 0x2D, 0x41, 0xFC,
    0x90, 0xE2, 0x16, 0xBE, 0xF0, 0x65, 0x23, 0xF2
};

static uint16_t CRC16CCITT(NSData *data) {
    uint16_t crc = 0;
    const uint8_t *bytes = data.bytes;
    for (NSUInteger index = 0; index < data.length; index++) {
        crc ^= (uint16_t)bytes[index] << 8;
        for (NSUInteger bit = 0; bit < 8; bit++) {
            crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
        }
    }
    return crc;
}

static NSData *BudsPacket(uint8_t messageID, NSData *payload) {
    NSMutableData *checksumInput = [NSMutableData dataWithBytes:&messageID length:1];
    [checksumInput appendData:payload];
    uint16_t crc = CRC16CCITT(checksumInput);
    uint16_t messageSize = (uint16_t)(1 + payload.length + 2);

    NSMutableData *packet = [NSMutableData dataWithCapacity:payload.length + 7];
    uint8_t start = 0xFD;
    uint8_t end = 0xDD;
    uint8_t sizeBytes[] = { (uint8_t)(messageSize & 0xFF), (uint8_t)(messageSize >> 8) };
    uint8_t crcBytes[] = { (uint8_t)(crc & 0xFF), (uint8_t)(crc >> 8) };
    [packet appendBytes:&start length:1];
    [packet appendBytes:sizeBytes length:2];
    [packet appendBytes:&messageID length:1];
    [packet appendData:payload];
    [packet appendBytes:crcBytes length:2];
    [packet appendBytes:&end length:1];
    return packet;
}

static BOOL BudsFrameHasValidCRC(NSData *frame) {
    if (frame.length < 7) { return NO; }
    const uint8_t *bytes = frame.bytes;
    NSUInteger checksumInputLength = frame.length - 6;
    NSData *checksumInput = [frame subdataWithRange:NSMakeRange(3, checksumInputLength)];
    uint16_t expected = CRC16CCITT(checksumInput);
    uint16_t actual = bytes[frame.length - 3] | ((uint16_t)bytes[frame.length - 2] << 8);
    return expected == actual;
}

static NSString *HexString(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:data.length];
    for (NSUInteger index = 0; index < data.length; index++) {
        [parts addObject:[NSString stringWithFormat:@"%02X", bytes[index]]];
    }
    return [parts componentsJoinedByString:@" "];
}

static NSData *BridgePSK(NSString *pairingCode) {
    NSData *input = [[NSString stringWithFormat:@"BudsBridge/v1:%@", pairingCode]
        dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(input.bytes, (CC_LONG)input.length, digest);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

static dispatch_data_t DispatchDataFromData(NSData *data) {
    return dispatch_data_create(data.bytes, data.length,
                                dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ (void)data; });
}

static nw_parameters_t BridgeSecureParameters(NSString *pairingCode) {
    NSData *psk = BridgePSK(pairingCode);
    NSData *identity = [@"BudsControl-v1" dataUsingEncoding:NSUTF8StringEncoding];
    return nw_parameters_create_secure_tcp(^(nw_protocol_options_t tlsOptions) {
        sec_protocol_options_t securityOptions = nw_tls_copy_sec_protocol_options(tlsOptions);
        sec_protocol_options_set_min_tls_protocol_version(securityOptions, tls_protocol_version_TLSv12);
        sec_protocol_options_set_max_tls_protocol_version(securityOptions, tls_protocol_version_TLSv12);
        sec_protocol_options_append_tls_ciphersuite(securityOptions, TLS_PSK_WITH_AES_128_GCM_SHA256);
        sec_protocol_options_set_tls_pre_shared_key_identity_hint(securityOptions,
                                                                  DispatchDataFromData(identity));
        sec_protocol_options_add_pre_shared_key(securityOptions,
                                                DispatchDataFromData(psk),
                                                DispatchDataFromData(identity));
    }, NW_PARAMETERS_DEFAULT_CONFIGURATION);
}

static NSString *GeneratePairingSecret(void) {
    uint8_t bytes[16];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) {
        return [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    }
    NSMutableString *secret = [NSMutableString stringWithCapacity:32];
    for (NSUInteger index = 0; index < sizeof(bytes); index++) {
        [secret appendFormat:@"%02X", bytes[index]];
    }
    return secret;
}

static BOOL IntegerInRange(id value, NSInteger minimum, NSInteger maximum) {
    if (![value isKindOfClass:NSNumber.class]) { return NO; }
    NSNumber *number = value;
    NSInteger integer = number.integerValue;
    return number.doubleValue == (double)integer && integer >= minimum && integer <= maximum;
}

static BOOL ValuesAreBooleans(NSArray *values, NSUInteger count) {
    if (![values isKindOfClass:NSArray.class] || values.count != count) { return NO; }
    for (id value in values) {
        if (!IntegerInRange(value, 0, 1)) { return NO; }
    }
    return YES;
}

static NSData *DataFromNumberArray(NSArray<NSNumber *> *values) {
    NSMutableData *data = [NSMutableData dataWithCapacity:values.count];
    for (NSNumber *value in values) {
        uint8_t byte = (uint8_t)value.unsignedIntegerValue;
        [data appendBytes:&byte length:1];
    }
    return data;
}

static NSDictionary *BudsCommandDescriptor(NSString *name, NSArray *values, NSString **errorMessage) {
    if (![name isKindOfClass:NSString.class] || ![values isKindOfClass:NSArray.class]) {
        if (errorMessage) { *errorMessage = @"缺少 command 或 values"; }
        return nil;
    }

    uint8_t messageID = 0;
    BOOL requiresAcknowledgement = YES;
    NSData *ackPrefix = nil;

    if ([name isEqualToString:@"noiseControl"] && values.count == 1 && IntegerInRange(values[0], 0, 3)) {
        messageID = 0x78;
    } else if ([name isEqualToString:@"equalizer"] && values.count == 1 && IntegerInRange(values[0], 0, 5)) {
        messageID = 0x86;
    } else if ([name isEqualToString:@"ambientVolume"] && values.count == 1 && IntegerInRange(values[0], 0, 2)) {
        messageID = 0x84;
    } else if ([name isEqualToString:@"ambientCustomization"] && values.count == 4 &&
               IntegerInRange(values[0], 0, 1) && IntegerInRange(values[1], 0, 2) &&
               IntegerInRange(values[2], 0, 2) && IntegerInRange(values[3], 0, 4)) {
        messageID = 0x82;
    } else if ([name isEqualToString:@"noiseReductionLevel"] && ValuesAreBooleans(values, 1)) {
        messageID = 0x83;
    } else if ([name isEqualToString:@"voiceDetect"] && ValuesAreBooleans(values, 1)) {
        messageID = 0x7A;
    } else if ([name isEqualToString:@"voiceDetectTimeout"] && values.count == 1 && IntegerInRange(values[0], 0, 2)) {
        messageID = 0x7B;
    } else if ([name isEqualToString:@"noiseControlWithOneEarbud"] && ValuesAreBooleans(values, 1)) {
        messageID = 0x6F;
    } else if ([name isEqualToString:@"touchLock"] && ValuesAreBooleans(values, 7)) {
        messageID = 0x90;
        ackPrefix = [NSData data];
    } else if ([name isEqualToString:@"touchActions"] && values.count == 2 &&
               IntegerInRange(values[0], 1, 4) && IntegerInRange(values[1], 1, 4)) {
        messageID = 0x92;
    } else if ([name isEqualToString:@"touchNoiseCycle"] && values.count == 2 &&
               [@[@4, @8, @12] containsObject:values[0]] && [@[@4, @8, @12] containsObject:values[1]]) {
        messageID = 0x79;
        ackPrefix = [NSData data];
    } else if ([name isEqualToString:@"edgeDoubleTapVolume"] && ValuesAreBooleans(values, 1)) {
        messageID = 0x95;
    } else if ([name isEqualToString:@"stereoBalance"] && values.count == 1 && IntegerInRange(values[0], 0, 32)) {
        messageID = 0x8F;
    } else if ([name isEqualToString:@"seamlessConnection"] && ValuesAreBooleans(values, 1)) {
        messageID = 0xAF;
        uint8_t semanticValue = [values[0] integerValue] == 0 ? 1 : 0;
        ackPrefix = [NSData dataWithBytes:&semanticValue length:1];
    } else if ([name isEqualToString:@"sidetone"] && ValuesAreBooleans(values, 1)) {
        messageID = 0x8B;
    } else if ([name isEqualToString:@"callPathControl"] && ValuesAreBooleans(values, 1)) {
        messageID = 0x6E;
        uint8_t semanticValue = [values[0] integerValue] == 0 ? 1 : 0;
        ackPrefix = [NSData dataWithBytes:&semanticValue length:1];
    } else if ([name isEqualToString:@"extraClearCall"] && ValuesAreBooleans(values, 1)) {
        messageID = 0x48;
    } else if ([name isEqualToString:@"extraHighAmbient"] && ValuesAreBooleans(values, 1)) {
        messageID = 0x96;
    } else if ([name isEqualToString:@"spatialAudio"] && ValuesAreBooleans(values, 1)) {
        messageID = 0x7C;
        requiresAcknowledgement = NO;
    } else if ([name isEqualToString:@"gamingMode"] && ValuesAreBooleans(values, 1)) {
        messageID = 0x87;
        requiresAcknowledgement = NO;
    } else if ([name isEqualToString:@"autoPauseResume"] && ValuesAreBooleans(values, 1)) {
        messageID = 0x6C;
        requiresAcknowledgement = NO;
    } else if ([name isEqualToString:@"fitTest"] && ValuesAreBooleans(values, 1)) {
        messageID = 0x9D;
        requiresAcknowledgement = NO;
    } else if ([name isEqualToString:@"adaptiveVolume"] && ValuesAreBooleans(values, 1)) {
        messageID = 0xC5;
        requiresAcknowledgement = NO;
    } else if ([name isEqualToString:@"sirenDetect"] && ValuesAreBooleans(values, 1)) {
        messageID = 0xDE;
        requiresAcknowledgement = NO;
    } else if ([name isEqualToString:@"findEarbudsStart"] && values.count == 0) {
        messageID = 0xA6;
        requiresAcknowledgement = NO;
    } else if ([name isEqualToString:@"findEarbudsStop"] && values.count == 0) {
        messageID = 0xA1;
        requiresAcknowledgement = NO;
    } else if ([name isEqualToString:@"muteEarbuds"] && ValuesAreBooleans(values, 2)) {
        messageID = 0xA2;
    } else {
        if (errorMessage) { *errorMessage = @"命令不存在或 values 超出允许范围"; }
        return nil;
    }

    NSData *payload = DataFromNumberArray(values);
    if (ackPrefix == nil && requiresAcknowledgement) { ackPrefix = payload; }
    return @{
        @"messageID": @(messageID),
        @"payload": payload,
        @"ackPrefix": ackPrefix ?: NSNull.null,
        @"requiresAcknowledgement": @(requiresAcknowledgement)
    };
}

@interface BudsTransport : NSObject <IOBluetoothRFCOMMChannelDelegate>
@property(nonatomic, copy, readonly) NSString *deviceName;
@property(nonatomic, copy, readonly) NSString *statusMessage;
@property(nonatomic, assign, readonly, getter=isReady) BOOL ready;
@property(nonatomic, strong, readonly) NSMutableDictionary *deviceState;
- (instancetype)initWithPreferredAddress:(NSString *)address;
- (void)start;
- (BOOL)sendMessageID:(uint8_t)messageID
              payload:(NSData *)payload
expectedAcknowledgement:(NSData *)expectedAcknowledgement
requiresAcknowledgement:(BOOL)requiresAcknowledgement
         acknowledged:(BOOL *)acknowledged
                error:(NSString **)errorMessage;
@end

@interface BudsTransport ()
@property(nonatomic, copy) NSString *preferredAddress;
@property(nonatomic, copy, readwrite) NSString *deviceName;
@property(nonatomic, copy, readwrite) NSString *statusMessage;
@property(nonatomic, assign, readwrite, getter=isReady) BOOL ready;
@property(nonatomic, strong) IOBluetoothDevice *device;
@property(nonatomic, strong) IOBluetoothRFCOMMChannel *channel;
@property(nonatomic, assign) BOOL queryInFlight;
@property(nonatomic, strong) NSDate *queryStartedAt;
@property(nonatomic, assign) BOOL basebandInFlight;
@property(nonatomic, strong) NSDate *basebandStartedAt;
@property(nonatomic, assign) BOOL channelOpenInFlight;
@property(nonatomic, strong) NSDate *channelOpenStartedAt;
@property(nonatomic, strong) NSTimer *retryTimer;
@property(nonatomic, strong) NSMutableData *receiveBuffer;
@property(nonatomic, assign) NSInteger leftBattery;
@property(nonatomic, assign) NSInteger rightBattery;
@property(nonatomic, assign) NSInteger caseBattery;
@property(nonatomic, assign) uint8_t lastAcknowledgedMessageID;
@property(nonatomic, strong) NSData *lastAcknowledgedParameters;
@property(nonatomic, strong) dispatch_queue_t commandQueue;
@property(nonatomic, strong) dispatch_semaphore_t pendingAcknowledgement;
@property(nonatomic, assign) uint8_t pendingMessageID;
@property(nonatomic, strong) NSData *pendingExpectedAcknowledgement;
@property(nonatomic, assign) BOOL pendingWasAcknowledged;
- (BOOL)openServiceRecord:(IOBluetoothSDPServiceRecord *)record;
- (void)beginSDPQuery;
- (void)markChannelReady:(IOBluetoothRFCOMMChannel *)channel;
- (void)requestState;
- (void)processFrame:(NSData *)frame;
@end

@implementation BudsTransport

- (instancetype)initWithPreferredAddress:(NSString *)address {
    self = [super init];
    if (self) {
        _preferredAddress = address.uppercaseString;
        _deviceName = @"Galaxy Buds3 Pro";
        _statusMessage = @"正在查找已配对的 Buds3 Pro";
        _receiveBuffer = [NSMutableData data];
        _leftBattery = -1;
        _rightBattery = -1;
        _caseBattery = -1;
        _deviceState = [NSMutableDictionary dictionary];
        _commandQueue = dispatch_queue_create("com.qiao.budsbridge.commands", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)start {
    [self attemptConnection];
    self.retryTimer = [NSTimer scheduledTimerWithTimeInterval:8
                                                       target:self
                                                     selector:@selector(attemptConnection)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (IOBluetoothDevice *)findPairedDevice {
    NSArray<IOBluetoothDevice *> *devices = [IOBluetoothDevice pairedDevices] ?: @[];
    for (IOBluetoothDevice *candidate in devices) {
        if (self.preferredAddress.length > 0 &&
            [candidate.addressString.uppercaseString isEqualToString:self.preferredAddress]) {
            return candidate;
        }
    }
    for (IOBluetoothDevice *candidate in devices) {
        NSString *name = candidate.nameOrAddress.lowercaseString;
        if ([name containsString:@"buds3 pro"] || [name containsString:@"sm-r630"]) {
            return candidate;
        }
    }
    return nil;
}

- (void)attemptConnection {
    if (self.channel.isOpen) {
        self.ready = YES;
        return;
    }
    if (self.channelOpenInFlight) {
        if ([self.channelOpenStartedAt timeIntervalSinceNow] > -25) { return; }
        self.channelOpenInFlight = NO;
        self.channel = nil;
        self.statusMessage = @"耳机连接超时，等待再次尝试";
    }
    if (self.basebandInFlight) {
        if (self.device.isConnected) {
            self.basebandInFlight = NO;
        } else {
            if ([self.basebandStartedAt timeIntervalSinceNow] > -25) { return; }
            self.basebandInFlight = NO;
            self.statusMessage = @"耳机基础蓝牙连接超时";
        }
    }
    if (self.queryInFlight) {
        if ([self.queryStartedAt timeIntervalSinceNow] > -30) { return; }
        self.queryInFlight = NO;
        self.statusMessage = @"耳机没有响应，等待再次尝试";
    }

    self.device = [self findPairedDevice];
    if (self.device == nil) {
        self.statusMessage = @"Mac 上没有已配对的 Buds3 Pro";
        return;
    }

    self.deviceName = self.device.nameOrAddress ?: @"Galaxy Buds3 Pro";
    NSLog(@"Cached SDP records for %@: %lu", self.deviceName, (unsigned long)self.device.services.count);
    IOBluetoothSDPUUID *uuid = [IOBluetoothSDPUUID uuidWithBytes:kSamsungServiceUUID length:16];
    IOBluetoothSDPServiceRecord *cachedRecord = [self.device getServiceRecordForUUID:uuid];
    if (cachedRecord != nil) {
        [self openServiceRecord:cachedRecord];
        return;
    }

    if (!self.device.isConnected) {
        if (self.basebandInFlight) { return; }
        IOReturn connectionStatus = [self.device openConnection:self];
        NSLog(@"Baseband open started status=0x%08X", connectionStatus);
        if (connectionStatus == kIOReturnSuccess) {
            self.basebandInFlight = YES;
            self.basebandStartedAt = [NSDate date];
            self.statusMessage = @"正在连接耳机";
        } else {
            self.statusMessage = @"耳机基础蓝牙连接失败";
        }
        return;
    }

    [self beginSDPQuery];
}

- (void)connectionComplete:(IOBluetoothDevice *)device status:(IOReturn)status {
    if (device != self.device) { return; }
    self.basebandInFlight = NO;
    if (self.channel.isOpen || self.channelOpenInFlight) { return; }
    NSLog(@"Baseband open completed status=0x%08X connected=%d", status, device.isConnected);
    if (status == kIOReturnSuccess || device.isConnected) {
        [self beginSDPQuery];
    } else {
        self.statusMessage = @"耳机基础蓝牙连接失败";
    }
}

- (void)beginSDPQuery {
    if (self.queryInFlight) { return; }
    self.statusMessage = @"正在打开三星 RFCOMM 控制通道";
    self.queryInFlight = YES;
    self.queryStartedAt = [NSDate date];

    IOReturn result = [self.device performSDPQuery:self];
    NSLog(@"SDP query started for %@: 0x%08X", self.deviceName, result);
    if (result != kIOReturnSuccess) {
        self.queryInFlight = NO;
        self.statusMessage = [NSString stringWithFormat:@"SDP 查询启动失败：0x%08X", result];
    }
}

- (void)sdpQueryComplete:(IOBluetoothDevice *)device status:(IOReturn)status {
    self.queryInFlight = NO;
    NSLog(@"SDP query completed: 0x%08X", status);
    if (status != kIOReturnSuccess) {
        self.ready = NO;
        self.statusMessage = @"未能连接耳机；请打开充电盒并断开手机";
        return;
    }

    IOBluetoothSDPUUID *uuid = [IOBluetoothSDPUUID uuidWithBytes:kSamsungServiceUUID length:16];
    IOBluetoothSDPServiceRecord *record = [device getServiceRecordForUUID:uuid];
    if (![self openServiceRecord:record]) {
        self.statusMessage = record == nil ? @"耳机没有公布三星控制服务" : @"RFCOMM 控制通道打开失败";
    }
}

- (BOOL)openServiceRecord:(IOBluetoothSDPServiceRecord *)record {
    BluetoothRFCOMMChannelID channelID = 0;
    if (record == nil || [record getRFCOMMChannelID:&channelID] != kIOReturnSuccess || channelID == 0) {
        return NO;
    }

    if (self.channelOpenInFlight) { return YES; }
    IOBluetoothRFCOMMChannel *channel = nil;
    self.channelOpenInFlight = YES;
    self.channelOpenStartedAt = [NSDate date];
    self.ready = NO;
    self.statusMessage = @"正在连接耳机控制通道";
    IOReturn status = [self.device openRFCOMMChannelAsync:&channel withChannelID:channelID delegate:self];
    self.channel = channel;
    NSLog(@"RFCOMM open started channel=%u status=0x%08X", channelID, status);
    if (channel.isOpen) {
        [self markChannelReady:channel];
        return YES;
    }
    if (status != kIOReturnSuccess || channel == nil) {
        self.channelOpenInFlight = NO;
        self.channel = nil;
        self.ready = NO;
        self.statusMessage = @"RFCOMM 控制通道打开失败";
        return NO;
    }

    return YES;
}

- (void)markChannelReady:(IOBluetoothRFCOMMChannel *)channel {
    if (!channel.isOpen) { return; }
    BOOL wasReady = self.ready && self.channel == channel;
    self.channelOpenInFlight = NO;
    self.channel = channel;
    self.ready = YES;
    self.statusMessage = @"耳机控制通道已连接";
    if (wasReady) { return; }
    [self.deviceState removeAllObjects];
    [self requestState];
}

- (void)requestState {
    if (!self.channel.isOpen) { return; }
    NSData *stateRequest = BudsPacket(0x26, [NSData data]);
    IOReturn stateStatus = [self.channel writeSync:(void *)stateRequest.bytes length:(uint16_t)stateRequest.length];
    if (stateStatus != kIOReturnSuccess) {
        self.ready = NO;
        self.statusMessage = @"耳机状态请求失败，正在重连";
        [self.channel closeChannel];
        self.channel = nil;
    }
}

- (BOOL)sendMessageID:(uint8_t)messageID
              payload:(NSData *)payload
expectedAcknowledgement:(NSData *)expectedAcknowledgement
requiresAcknowledgement:(BOOL)requiresAcknowledgement
         acknowledged:(BOOL *)acknowledgedResult
                error:(NSString **)errorMessage {
    __block BOOL acknowledged = NO;
    __block BOOL sent = NO;
    __block NSString *failure = nil;

    dispatch_sync(self.commandQueue, ^{
        dispatch_semaphore_t semaphore = requiresAcknowledgement ? dispatch_semaphore_create(0) : nil;
        __block BOOL wrotePacket = NO;

        dispatch_sync(dispatch_get_main_queue(), ^{
            if (!self.channel.isOpen) {
                failure = self.statusMessage ?: @"耳机未连接";
                return;
            }

            self.pendingMessageID = messageID;
            self.pendingExpectedAcknowledgement = expectedAcknowledgement;
            self.pendingWasAcknowledged = NO;
            self.pendingAcknowledgement = semaphore;

            NSData *packet = BudsPacket(messageID, payload);
            IOReturn status = [self.channel writeSync:(void *)packet.bytes length:(uint16_t)packet.length];
            NSLog(@"TX %@ status=0x%08X", HexString(packet), status);
            if (status != kIOReturnSuccess) {
                self.pendingAcknowledgement = nil;
                self.ready = NO;
                self.statusMessage = @"写入耳机失败，正在重连";
                [self.channel closeChannel];
                self.channel = nil;
                failure = self.statusMessage;
                return;
            }
            wrotePacket = YES;
            sent = YES;
        });

        if (!wrotePacket) { return; }
        if (!requiresAcknowledgement) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self requestState]; });
            return;
        }
        long waitResult = dispatch_semaphore_wait(semaphore,
            dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        dispatch_sync(dispatch_get_main_queue(), ^{
            acknowledged = waitResult == 0 && self.pendingWasAcknowledged;
            if (self.pendingAcknowledgement == semaphore) {
                self.pendingAcknowledgement = nil;
            }
            self.pendingWasAcknowledged = NO;
            if (!acknowledged) { failure = @"耳机未确认命令"; }
            if (acknowledged) { [self requestState]; }
        });
    });

    if (acknowledgedResult) { *acknowledgedResult = acknowledged; }
    BOOL succeeded = sent && (!requiresAcknowledgement || acknowledged);
    if (!succeeded && errorMessage) { *errorMessage = failure ?: @"耳机未确认命令"; }
    return succeeded;
}

- (void)rfcommChannelData:(IOBluetoothRFCOMMChannel *)rfcommChannel
                     data:(void *)dataPointer
                   length:(size_t)dataLength {
    [self.receiveBuffer appendBytes:dataPointer length:dataLength];
    while (self.receiveBuffer.length >= 7) {
        const uint8_t *bytes = self.receiveBuffer.bytes;
        if (bytes[0] != 0xFD) {
            NSUInteger startIndex = 1;
            while (startIndex < self.receiveBuffer.length && bytes[startIndex] != 0xFD) { startIndex++; }
            [self.receiveBuffer replaceBytesInRange:NSMakeRange(0, startIndex) withBytes:NULL length:0];
            continue;
        }

        NSUInteger messageSize = bytes[1] | ((NSUInteger)(bytes[2] & 0x03) << 8);
        NSUInteger frameLength = messageSize + 4;
        if (frameLength < 7 || frameLength > 4096) {
            [self.receiveBuffer replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
            continue;
        }
        if (self.receiveBuffer.length < frameLength) { break; }

        NSData *frame = [self.receiveBuffer subdataWithRange:NSMakeRange(0, frameLength)];
        [self.receiveBuffer replaceBytesInRange:NSMakeRange(0, frameLength) withBytes:NULL length:0];
        const uint8_t *frameBytes = frame.bytes;
        if (frameBytes[frameLength - 1] == 0xDD && BudsFrameHasValidCRC(frame)) {
            [self processFrame:frame];
        } else {
            NSLog(@"Dropped invalid RFCOMM frame: %@", HexString(frame));
        }
    }
}

- (void)processFrame:(NSData *)frame {
    const uint8_t *bytes = frame.bytes;
    uint8_t messageID = bytes[3];
    NSUInteger payloadLength = frame.length >= 7 ? frame.length - 7 : 0;
    if (messageID == 0x42 && payloadLength >= 1) {
        self.lastAcknowledgedMessageID = bytes[4];
        NSUInteger parameterLength = payloadLength - 1;
        self.lastAcknowledgedParameters = parameterLength > 0
            ? [frame subdataWithRange:NSMakeRange(5, parameterLength)]
            : [NSData data];
        NSLog(@"ACK command=0x%02X parameters=%@", self.lastAcknowledgedMessageID,
              HexString(self.lastAcknowledgedParameters));
        BOOL parametersMatch = self.pendingExpectedAcknowledgement == nil ||
            self.pendingExpectedAcknowledgement.length == 0 ||
            (self.lastAcknowledgedParameters.length >= self.pendingExpectedAcknowledgement.length &&
             [[self.lastAcknowledgedParameters subdataWithRange:
                 NSMakeRange(0, self.pendingExpectedAcknowledgement.length)]
                 isEqualToData:self.pendingExpectedAcknowledgement]);
        if (self.pendingAcknowledgement != nil &&
            self.pendingMessageID == self.lastAcknowledgedMessageID &&
            parametersMatch) {
            self.pendingWasAcknowledged = YES;
            dispatch_semaphore_signal(self.pendingAcknowledgement);
        }
        return;
    }

    if (messageID == 0x60 && frame.length >= 14) {
        self.leftBattery = bytes[5] <= 100 ? bytes[5] : -1;
        self.rightBattery = bytes[6] <= 100 ? bytes[6] : -1;
        if (bytes[10] <= 100) { self.caseBattery = bytes[10]; }
        NSLog(@"Battery left=%ld right=%ld case=%ld",
              (long)self.leftBattery, (long)self.rightBattery, (long)self.caseBattery);
    } else if (messageID == 0x61 && payloadLength >= 8) {
        const uint8_t *payload = bytes + 4;
        self.leftBattery = bytes[6] <= 100 ? bytes[6] : -1;
        self.rightBattery = bytes[7] <= 100 ? bytes[7] : -1;
        if (bytes[11] > 0 && bytes[11] <= 100) { self.caseBattery = bytes[11]; }

        self.deviceState[@"hasExtendedState"] = @YES;
        self.deviceState[@"revision"] = @(payload[0]);
        if (payloadLength > 9 && payload[9] <= 5) { self.deviceState[@"equalizer"] = @(payload[9]); }
        if (payloadLength > 10) {
            uint8_t touchState = payload[10];
            self.deviceState[@"touchLocked"] = @((touchState & 0x80) == 0);
            self.deviceState[@"singleTapEnabled"] = @((touchState & 0x08) != 0);
            self.deviceState[@"doubleTapEnabled"] = @((touchState & 0x04) != 0);
            self.deviceState[@"tripleTapEnabled"] = @((touchState & 0x02) != 0);
            self.deviceState[@"touchAndHoldEnabled"] = @((touchState & 0x01) != 0);
            self.deviceState[@"doubleTapCallEnabled"] = @((touchState & 0x10) != 0);
            self.deviceState[@"touchAndHoldCallEnabled"] = @((touchState & 0x20) != 0);
        }
        if (payloadLength > 11) {
            self.deviceState[@"leftTouchAction"] = @((payload[11] & 0xF0) >> 4);
            self.deviceState[@"rightTouchAction"] = @(payload[11] & 0x0F);
        }
        if (payloadLength > 12 && payload[12] <= 3) { self.deviceState[@"noiseMode"] = @(payload[12]); }
        if (payloadLength > 19) { self.deviceState[@"seamlessConnection"] = @(payload[19] == 0); }
        if (payloadLength > 21) { self.deviceState[@"touchNoiseCycleRaw"] = @(payload[21]); }
        if (payloadLength > 23 && payload[23] <= 3) { self.deviceState[@"ambientVolume"] = @(payload[23]); }
        if (payloadLength > 24) { self.deviceState[@"noiseReductionHigh"] = @(payload[24] == 1); }
        if (payloadLength > 25 && payload[25] <= 32) { self.deviceState[@"stereoBalance"] = @(payload[25]); }
        if (payloadLength > 26) { self.deviceState[@"voiceDetectEnabled"] = @(payload[26] == 1); }
        if (payloadLength > 27 && payload[27] <= 2) { self.deviceState[@"voiceDetectTimeout"] = @(payload[27]); }
        if (payloadLength > 28) { self.deviceState[@"noiseControlWithOneEarbud"] = @(payload[28] == 1); }
        if (payloadLength > 29) { self.deviceState[@"ambientCustomizationEnabled"] = @(payload[29] == 1); }
        if (payloadLength > 30) {
            self.deviceState[@"ambientVolumeLeft"] = @((payload[30] & 0xF0) >> 4);
            self.deviceState[@"ambientVolumeRight"] = @(payload[30] & 0x0F);
        }
        if (payloadLength > 31 && payload[31] <= 4) { self.deviceState[@"ambientTone"] = @(payload[31]); }
        if (payloadLength > 32) { self.deviceState[@"edgeDoubleTapVolume"] = @(payload[32] == 1); }
        if (payloadLength > 33) { self.deviceState[@"sidetoneEnabled"] = @(payload[33] == 1); }
        if (payloadLength > 34) { self.deviceState[@"callPathControlEnabled"] = @(payload[34] == 0); }
        if (payloadLength > 35) { self.deviceState[@"spatialAudioEnabled"] = @(payload[35] == 1); }
        if (payloadLength > 45) { self.deviceState[@"spatialHeadTrackingEnabled"] = @(payload[45] == 1); }
        if (payloadLength > 47) { self.deviceState[@"extraClearCallEnabled"] = @(payload[47] == 1); }
        if (payloadLength > 48) { self.deviceState[@"extraHighAmbientEnabled"] = @(payload[48] == 1); }
        if (payloadLength > 49) { self.deviceState[@"autoPauseResumeEnabled"] = @(payload[49] == 1); }
        if (payloadLength > 50) { self.deviceState[@"hotCommandEnabled"] = @(payload[50] == 1); }
        if (payloadLength > 53) { self.deviceState[@"adaptiveVolumeEnabled"] = @(payload[53] == 1); }
        if (payloadLength > 54) { self.deviceState[@"lightingControl"] = @(payload[54]); }
        if (payloadLength > 56) { self.deviceState[@"sirenDetectEnabled"] = @(payload[56] == 1); }
        if (payloadLength > 57) { self.deviceState[@"adaptSoundEnabled"] = @(payload[57] == 1); }
        self.deviceState[@"stateUpdatedAt"] = @([NSDate date].timeIntervalSince1970);
        NSLog(@"Battery left=%ld right=%ld case=%ld",
              (long)self.leftBattery, (long)self.rightBattery, (long)self.caseBattery);
    } else if (messageID == 0x9E && payloadLength >= 2) {
        self.deviceState[@"fitTestLeft"] = @(bytes[4]);
        self.deviceState[@"fitTestRight"] = @(bytes[5]);
        self.deviceState[@"fitTestActive"] = @NO;
        uint8_t stop = 0;
        NSData *packet = BudsPacket(0x9D, [NSData dataWithBytes:&stop length:1]);
        IOReturn status = [self.channel writeSync:(void *)packet.bytes length:(uint16_t)packet.length];
        NSLog(@"Fit test complete; stop TX status=0x%08X", status);
    }
}

- (void)rfcommChannelOpenComplete:(IOBluetoothRFCOMMChannel *)rfcommChannel
                            status:(IOReturn)error {
    NSLog(@"RFCOMM open callback: 0x%08X", error);
    self.channelOpenInFlight = NO;
    if (rfcommChannel.isOpen) {
        [self markChannelReady:rfcommChannel];
    } else {
        if (self.channel == rfcommChannel) { self.channel = nil; }
        self.ready = NO;
        self.statusMessage = @"RFCOMM 控制通道打开失败";
    }
}

- (void)rfcommChannelClosed:(IOBluetoothRFCOMMChannel *)rfcommChannel {
    if (self.channel != rfcommChannel) { return; }
    self.channelOpenInFlight = NO;
    if (self.pendingAcknowledgement != nil) {
        dispatch_semaphore_signal(self.pendingAcknowledgement);
    }
    self.channel = nil;
    self.ready = NO;
    [self.deviceState removeAllObjects];
    self.statusMessage = @"耳机已断开，正在等待重连";
    NSLog(@"RFCOMM channel closed");
}

@end

@class BudsHTTPServer;

@interface BudsHTTPConnection : NSObject
- (instancetype)initWithConnection:(nw_connection_t)connection server:(BudsHTTPServer *)server;
- (void)start;
@end

@interface BudsHTTPServer : NSObject
@property(nonatomic, strong, readonly) BudsTransport *transport;
- (instancetype)initWithTransport:(BudsTransport *)transport port:(NSString *)port;
- (BOOL)start;
- (NSDictionary *)handleMethod:(NSString *)method
                           path:(NSString *)path
                        headers:(NSDictionary<NSString *, NSString *> *)headers
                           body:(NSData *)body
                         status:(NSInteger *)status;
@end

@interface BudsHTTPServer ()
@property(nonatomic, strong, readwrite) BudsTransport *transport;
@property(nonatomic, copy) NSString *port;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) nw_listener_t listener;
@property(nonatomic, copy) NSString *pairingCode;
@property(nonatomic, assign) NSInteger failedAuthAttempts;
@property(nonatomic, strong) NSDate *blockedUntil;
@end

@implementation BudsHTTPServer

- (instancetype)initWithTransport:(BudsTransport *)transport port:(NSString *)port {
    self = [super init];
    if (self) {
        _transport = transport;
        _port = port;
        _queue = dispatch_queue_create("com.qiao.budsbridge.http", DISPATCH_QUEUE_SERIAL);
        _pairingCode = GeneratePairingSecret();
    }
    return self;
}

- (BOOL)start {
    nw_parameters_t parameters = BridgeSecureParameters(self.pairingCode);
    self.listener = nw_listener_create_with_port(self.port.UTF8String, parameters);
    if (self.listener == nil) { return NO; }

    nw_advertise_descriptor_t descriptor =
        nw_advertise_descriptor_create_bonjour_service("BudsBridge", "_budscontrol._tcp", NULL);
    nw_listener_set_advertise_descriptor(self.listener, descriptor);
    nw_listener_set_queue(self.listener, self.queue);
    nw_listener_set_state_changed_handler(self.listener, ^(nw_listener_state_t state, nw_error_t error) {
        if (state == nw_listener_state_ready) {
            NSLog(@"BudsBridge ready on port %u and advertised as _budscontrol._tcp",
                  nw_listener_get_port(self.listener));
        } else if (state == nw_listener_state_failed) {
            NSLog(@"HTTP listener failed: %@", error);
        }
    });
    nw_listener_set_new_connection_handler(self.listener, ^(nw_connection_t connection) {
        BudsHTTPConnection *handler = [[BudsHTTPConnection alloc] initWithConnection:connection server:self];
        objc_setAssociatedObject(connection, @selector(start), handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [handler start];
    });
    nw_listener_start(self.listener);
    NSLog(@"BudsBridge pairing secret: %@", self.pairingCode);
    return YES;
}

- (NSDictionary *)handleMethod:(NSString *)method
                           path:(NSString *)path
                        headers:(NSDictionary<NSString *,NSString *> *)headers
                           body:(NSData *)body
                         status:(NSInteger *)status {
    if (self.blockedUntil.timeIntervalSinceNow > 0) {
        *status = 429;
        return @{ @"sent": @NO, @"message": @"配对尝试过多，请稍后再试" };
    }

    NSString *providedCode = headers[@"x-buds-pairing-code"] ?: @"";
    if (![providedCode isEqualToString:self.pairingCode]) {
        self.failedAuthAttempts += 1;
        if (self.failedAuthAttempts >= 5) {
            self.blockedUntil = [NSDate dateWithTimeIntervalSinceNow:30];
            self.failedAuthAttempts = 0;
        }
        *status = 401;
        return @{ @"sent": @NO, @"message": @"请粘贴 Mac 上显示的 32 位配对密钥" };
    }
    self.failedAuthAttempts = 0;

    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/v1/status"]) {
        __block NSMutableDictionary *payload;
        dispatch_sync(dispatch_get_main_queue(), ^{
            payload = [@{
                @"ready": @(self.transport.isReady),
                @"serviceName": @"BudsBridge",
                @"deviceName": self.transport.deviceName ?: @"Galaxy Buds3 Pro",
                @"message": self.transport.statusMessage ?: @"",
                @"leftBattery": self.transport.leftBattery >= 0 ? @(self.transport.leftBattery) : NSNull.null,
                @"rightBattery": self.transport.rightBattery >= 0 ? @(self.transport.rightBattery) : NSNull.null,
                @"caseBattery": self.transport.caseBattery >= 0 ? @(self.transport.caseBattery) : NSNull.null
            } mutableCopy];
            [payload addEntriesFromDictionary:self.transport.deviceState];
        });
        *status = 200;
        return payload;
    }

    if (![method isEqualToString:@"POST"] ||
        !([path isEqualToString:@"/v1/noise"] || [path isEqualToString:@"/v1/equalizer"] ||
          [path isEqualToString:@"/v1/command"])) {
        *status = 404;
        return @{ @"sent": @NO, @"message": @"未知接口" };
    }

    NSError *jsonError = nil;
    NSDictionary *json = body.length > 0 ? [NSJSONSerialization JSONObjectWithData:body options:0 error:&jsonError] : nil;
    if (![json isKindOfClass:NSDictionary.class] || jsonError != nil) {
        *status = 400;
        return @{ @"sent": @NO, @"message": @"请求体必须是 JSON 对象" };
    }

    NSString *commandName = json[@"command"];
    NSArray *values = json[@"values"];
    if ([path isEqualToString:@"/v1/noise"] || [path isEqualToString:@"/v1/equalizer"]) {
        NSNumber *value = json[@"value"];
        commandName = [path isEqualToString:@"/v1/noise"] ? @"noiseControl" : @"equalizer";
        values = [value isKindOfClass:NSNumber.class] ? @[value] : nil;
    }

    NSString *validationError = nil;
    NSDictionary *descriptor = BudsCommandDescriptor(commandName, values, &validationError);
    if (descriptor == nil) {
        *status = 400;
        return @{ @"sent": @NO, @"message": validationError ?: @"命令无效" };
    }

    NSData *expectedAcknowledgement = descriptor[@"ackPrefix"] == NSNull.null
        ? nil : descriptor[@"ackPrefix"];
    BOOL requiresAcknowledgement = [descriptor[@"requiresAcknowledgement"] boolValue];
    BOOL acknowledged = NO;
    NSString *errorMessage = nil;
    BOOL sent = [self.transport sendMessageID:[descriptor[@"messageID"] unsignedCharValue]
                                      payload:descriptor[@"payload"]
                      expectedAcknowledgement:expectedAcknowledgement
                     requiresAcknowledgement:requiresAcknowledgement
                                 acknowledged:&acknowledged
                                        error:&errorMessage];
    if (sent && [commandName isEqualToString:@"fitTest"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL active = [values.firstObject boolValue];
            self.transport.deviceState[@"fitTestActive"] = @(active);
            if (active) {
                [self.transport.deviceState removeObjectForKey:@"fitTestLeft"];
                [self.transport.deviceState removeObjectForKey:@"fitTestRight"];
            }
        });
    }
    *status = sent ? 200 : 503;
    NSString *confirmation = acknowledged ? @"acknowledged" : (sent ? @"written" : @"failed");
    NSString *message = acknowledged ? @"耳机已确认命令" :
        (sent ? @"命令已写入，等待状态包确认" : (errorMessage ?: @"耳机未连接"));
    return @{ @"sent": @(sent), @"acknowledged": @(acknowledged),
              @"confirmation": confirmation, @"message": message };
}

@end

@interface BudsHTTPConnection ()
@property(nonatomic, strong) nw_connection_t connection;
@property(nonatomic, weak) BudsHTTPServer *server;
@property(nonatomic, strong) NSMutableData *buffer;
@property(nonatomic, assign) BOOL finished;
@property(nonatomic, strong) dispatch_queue_t queue;
- (void)finishConnection;
@end


@implementation BudsHTTPConnection

- (instancetype)initWithConnection:(nw_connection_t)connection server:(BudsHTTPServer *)server {
    self = [super init];
    if (self) {
        _connection = connection;
        _server = server;
        _buffer = [NSMutableData data];
        _queue = dispatch_queue_create("com.qiao.budsbridge.connection", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)start {
    nw_connection_set_queue(self.connection, self.queue);
    nw_connection_set_state_changed_handler(self.connection, ^(nw_connection_state_t state, nw_error_t error) {
        if (state == nw_connection_state_ready) {
            [self receiveNext];
        } else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
            objc_setAssociatedObject(self.connection, @selector(start), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
    nw_connection_start(self.connection);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), self.queue, ^{
        if (!self.finished) {
            self.finished = YES;
            [self finishConnection];
        }
    });
}

- (void)receiveNext {
    nw_connection_receive(self.connection, 1, 64 * 1024,
                          ^(dispatch_data_t content, nw_content_context_t context, bool complete, nw_error_t error) {
        if (content != nil) {
            const void *bytes = NULL;
            size_t length = 0;
            dispatch_data_t mapped = dispatch_data_create_map(content, &bytes, &length);
            if (mapped && bytes && length > 0) {
                if (self.buffer.length + length > 16 * 1024) {
                    [self sendJSON:@{ @"sent": @NO, @"message": @"HTTP 请求过大" } status:413];
                    return;
                }
                [self.buffer appendBytes:bytes length:length];
                NSRange headerRange = [self headerRange];
                if (headerRange.location != NSNotFound) {
                    NSData *headerData = [self.buffer subdataWithRange:NSMakeRange(0, headerRange.location)];
                    NSString *header = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding] ?: @"";
                    if ([self contentLengthFromHeader:header] > 4096) {
                        [self sendJSON:@{ @"sent": @NO, @"message": @"HTTP 请求体过大" } status:413];
                        return;
                    }
                }
            }
        }
        if (error != nil) {
            [self finishConnection];
            return;
        }
        if ([self requestIsComplete]) {
            [self handleRequest];
        } else if (complete) {
            [self sendJSON:@{ @"sent": @NO, @"message": @"HTTP 请求不完整" } status:400];
        } else {
            [self receiveNext];
        }
    });
}

- (NSRange)headerRange {
    NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    return [self.buffer rangeOfData:separator options:0 range:NSMakeRange(0, self.buffer.length)];
}

- (NSUInteger)contentLengthFromHeader:(NSString *)header {
    for (NSString *line in [header componentsSeparatedByString:@"\r\n"]) {
        if ([line.lowercaseString hasPrefix:@"content-length:"]) {
            return [[line componentsSeparatedByString:@":"].lastObject stringByTrimmingCharactersInSet:
                    NSCharacterSet.whitespaceCharacterSet].integerValue;
        }
    }
    return 0;
}

- (BOOL)requestIsComplete {
    NSRange range = [self headerRange];
    if (range.location == NSNotFound) { return NO; }
    NSData *headerData = [self.buffer subdataWithRange:NSMakeRange(0, range.location)];
    NSString *header = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding] ?: @"";
    NSUInteger expected = NSMaxRange(range) + [self contentLengthFromHeader:header];
    return self.buffer.length >= expected;
}

- (void)handleRequest {
    NSRange range = [self headerRange];
    NSData *headerData = [self.buffer subdataWithRange:NSMakeRange(0, range.location)];
    NSString *header = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *requestLine = [header componentsSeparatedByString:@"\r\n"].firstObject ?: @"";
    NSArray<NSString *> *parts = [requestLine componentsSeparatedByString:@" "];
    if (parts.count < 2) {
        [self sendJSON:@{ @"sent": @NO, @"message": @"HTTP 请求行无效" } status:400];
        return;
    }

    NSUInteger contentLength = [self contentLengthFromHeader:header];
    NSData *body = contentLength > 0
        ? [self.buffer subdataWithRange:NSMakeRange(NSMaxRange(range), contentLength)]
        : [NSData data];
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    NSArray<NSString *> *headerLines = [header componentsSeparatedByString:@"\r\n"];
    for (NSUInteger index = 1; index < headerLines.count; index++) {
        NSString *line = headerLines[index];
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) { continue; }
        NSString *name = [[line substringToIndex:colon.location] lowercaseString];
        NSString *value = [[line substringFromIndex:colon.location + 1]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        headers[name] = value;
    }
    NSInteger status = 500;
    NSDictionary *payload = [self.server handleMethod:parts[0]
                                                    path:parts[1]
                                                 headers:headers
                                                    body:body
                                                  status:&status];
    [self sendJSON:payload status:status];
}

- (void)sendJSON:(NSDictionary *)json status:(NSInteger)status {
    if (self.finished) { return; }
    self.finished = YES;
    NSData *body = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil] ?: [NSData data];
    NSString *reason = status == 200 ? @"OK"
        : (status == 400 ? @"Bad Request"
        : (status == 401 ? @"Unauthorized"
        : (status == 404 ? @"Not Found"
        : (status == 413 ? @"Payload Too Large"
        : (status == 429 ? @"Too Many Requests" : @"Service Unavailable")))));
    NSString *header = [NSString stringWithFormat:
        @"HTTP/1.1 %ld %@\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
        (long)status, reason, (unsigned long)body.length];
    NSMutableData *response = [[header dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [response appendData:body];
    dispatch_data_t content = dispatch_data_create(response.bytes, response.length,
                                                   dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ (void)response; });
    nw_connection_send(self.connection, content, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t error) {
        [self finishConnection];
    });
}

- (void)finishConnection {
    self.finished = YES;
    nw_connection_set_state_changed_handler(self.connection, nil);
    objc_setAssociatedObject(self.connection, @selector(start), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    nw_connection_cancel(self.connection);
}

@end

static NSString *ArgumentValue(NSArray<NSString *> *arguments, NSString *flag) {
    NSUInteger index = [arguments indexOfObject:flag];
    if (index == NSNotFound || index + 1 >= arguments.count) { return nil; }
    return arguments[index + 1];
}

static int RunProtocolSelfTest(void) {
    NSArray<NSDictionary *> *vectors = @[
        @{ @"name": @"noiseControl", @"values": @[@3], @"messageID": @0x78,
           @"packet": @"FD 04 00 78 03 93 B1 DD" },
        @{ @"name": @"ambientVolume", @"values": @[@2], @"messageID": @0x84,
           @"packet": @"FD 04 00 84 02 1E F7 DD" },
        @{ @"name": @"ambientCustomization", @"values": @[@1, @2, @1, @3], @"messageID": @0x82,
           @"packet": @"FD 07 00 82 01 02 01 03 D5 7D DD" },
        @{ @"name": @"touchLock", @"values": @[@1, @1, @1, @1, @1, @1, @1], @"messageID": @0x90,
           @"packet": @"FD 0A 00 90 01 01 01 01 01 01 01 31 F5 DD" },
        @{ @"name": @"touchNoiseCycle", @"values": @[@8, @12], @"messageID": @0x79,
           @"packet": @"FD 05 00 79 08 0C BC 0E DD" },
        @{ @"name": @"seamlessConnection", @"values": @[@0], @"messageID": @0xAF,
           @"packet": @"FD 04 00 AF 00 40 0D DD" }
    ];

    for (NSDictionary *vector in vectors) {
        NSString *error = nil;
        NSDictionary *descriptor = BudsCommandDescriptor(vector[@"name"], vector[@"values"], &error);
        if (descriptor == nil || ![descriptor[@"messageID"] isEqual:vector[@"messageID"]]) {
            NSLog(@"SELF-TEST FAIL %@: %@", vector[@"name"], error ?: @"message ID mismatch");
            return 10;
        }
        NSData *packet = BudsPacket([descriptor[@"messageID"] unsignedCharValue], descriptor[@"payload"]);
        if (![HexString(packet) isEqualToString:vector[@"packet"]]) {
            NSLog(@"SELF-TEST FAIL %@: %@", vector[@"name"], HexString(packet));
            return 11;
        }
    }

    NSArray<NSDictionary *> *invalid = @[
        @{ @"name": @"noiseControl", @"values": @[@4] },
        @{ @"name": @"touchActions", @"values": @[@0, @2] },
        @{ @"name": @"ambientCustomization", @"values": @[@1, @3, @1, @2] },
        @{ @"name": @"rawMessage", @"values": @[@120, @1] }
    ];
    for (NSDictionary *request in invalid) {
        if (BudsCommandDescriptor(request[@"name"], request[@"values"], nil) != nil) {
            NSLog(@"SELF-TEST FAIL: invalid command accepted %@", request);
            return 12;
        }
    }

    NSLog(@"Protocol self-test passed: %lu vectors and %lu rejection cases",
          (unsigned long)vectors.count, (unsigned long)invalid.count);
    return 0;
}

static int RunTLSProbe(NSString *host, NSString *port, NSString *pairingCode) {
    nw_endpoint_t endpoint = nw_endpoint_create_host(host.UTF8String, port.UTF8String);
    nw_connection_t connection = nw_connection_create(endpoint, BridgeSecureParameters(pairingCode));
    dispatch_queue_t queue = dispatch_queue_create("com.qiao.budsbridge.probe", DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    __block NSMutableData *response = [NSMutableData data];
    __block int exitCode = 1;

    void (^receiveOnce)(void) = ^{
        nw_connection_receive_message(connection,
                              ^(dispatch_data_t content, nw_content_context_t context, bool complete, nw_error_t error) {
            if (content != nil) {
                const void *bytes = NULL;
                size_t length = 0;
                dispatch_data_t mapped = dispatch_data_create_map(content, &bytes, &length);
                if (mapped && bytes && length > 0) { [response appendBytes:bytes length:length]; }
            }
            if (error != nil) {
                NSLog(@"TLS probe receive failed: %@", error);
                dispatch_semaphore_signal(finished);
            } else if (complete) {
                NSString *text = [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding] ?: @"";
                NSLog(@"TLS probe response: %@", text);
                exitCode = [text containsString:@"200 OK"] ? 0 : 2;
                dispatch_semaphore_signal(finished);
            }
        });
    };

    nw_connection_set_queue(connection, queue);
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        if (state == nw_connection_state_ready) {
            NSString *request = [NSString stringWithFormat:
                @"GET /v1/status HTTP/1.1\r\nHost: %@\r\nX-Buds-Pairing-Code: %@\r\nConnection: close\r\nContent-Length: 0\r\n\r\n",
                host, pairingCode];
            NSData *requestData = [request dataUsingEncoding:NSUTF8StringEncoding];
            nw_connection_send(connection, DispatchDataFromData(requestData),
                               NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t sendError) {
                if (sendError != nil) {
                    NSLog(@"TLS probe send failed: %@", sendError);
                    dispatch_semaphore_signal(finished);
                } else {
                    receiveOnce();
                }
            });
        } else if (state == nw_connection_state_failed) {
            NSLog(@"TLS probe connection failed: %@", error);
            dispatch_semaphore_signal(finished);
        }
    });
    nw_connection_start(connection);

    if (dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC)) != 0) {
        NSLog(@"TLS probe timed out");
        exitCode = 3;
    }
    nw_connection_cancel(connection);
    return exitCode;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
        if ([arguments containsObject:@"--protocol-self-test"]) {
            return RunProtocolSelfTest();
        }
        NSString *probePort = ArgumentValue(arguments, @"--probe-port");
        NSString *probeCode = ArgumentValue(arguments, @"--pairing-code");
        if (probePort.length > 0 && probeCode.length > 0) {
            return RunTLSProbe(@"127.0.0.1", probePort, probeCode);
        }
        NSString *address = ArgumentValue(arguments, @"--address");
        NSString *port = ArgumentValue(arguments, @"--port") ?: @"0";

        BudsTransport *transport = [[BudsTransport alloc] initWithPreferredAddress:address];
        [transport start];
        BudsHTTPServer *server = [[BudsHTTPServer alloc] initWithTransport:transport port:port];
        if (![server start]) {
            NSLog(@"Unable to start BudsBridge HTTP server");
            return 1;
        }

        NSLog(@"Keep this process running while using the iPhone app. Press Control-C to stop.");
        [[NSRunLoop mainRunLoop] run];
        return 0;
    }
}
