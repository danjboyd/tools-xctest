#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

static XCTAttachment *Named(XCTAttachment *attachment, NSString *name)
{
    [attachment setName:name];
    return attachment;
}

@interface AttachmentTests : XCTestCase
@end

@implementation AttachmentTests

+ (void)setUp
{
    // Not in a test: ignored, with a message.
    [[[[self alloc] init] autorelease] addAttachment:Named([XCTAttachment attachmentWithString:@"class"], @"class-level")];
}

// A passing test keeps only attachments it asks to keep.
- (void)testPassingKeepsOnlyKeepAlways
{
    XCTAttachment *kept = Named([XCTAttachment attachmentWithString:@"kept text"], @"notes");

    [kept setLifetime:XCTAttachmentLifetimeKeepAlways];
    [self addAttachment:Named([XCTAttachment attachmentWithString:@"dropped text"], @"dropped")];
    [self addAttachment:kept];
}

// A failing test keeps everything.
- (void)testFailingKeepsAll
{
    NSString *logPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"attachment-fixture.log"];

    [@"log line\n" writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [self addAttachment:[XCTAttachment attachmentWithContentsOfFileAtURL:[NSURL fileURLWithPath:logPath]]];
    [self addAttachment:Named([XCTAttachment attachmentWithData:[@"raw" dataUsingEncoding:NSUTF8StringEncoding]], @"blob")];
    [self addAttachment:Named([XCTAttachment attachmentWithPlistObject:
        [NSDictionary dictionaryWithObject:@"value" forKey:@"key"]], @"settings")];
    [self addAttachment:Named([XCTAttachment attachmentWithArchivableObject:
        [NSArray arrayWithObjects:@"a", @"b", nil]], @"archive")];
    [self addAttachment:Named([XCTAttachment attachmentWithString:@"first"], @"dup")];
    [self addAttachment:Named([XCTAttachment attachmentWithString:@"second"], @"dup")];
    [self addAttachment:Named([XCTAttachment attachmentWithString:@"slashes"], @"a/b")];
    [self addAttachment:[XCTAttachment attachmentWithString:@"no name"]];
    [[NSFileManager defaultManager] removeItemAtPath:logPath error:NULL];
    XCTFail(@"fails to keep attachments");
}

- (void)testActivityAttachment
{
    [XCTContext runActivityNamed:@"Capture" block:^(id<XCTActivity> activity) {
        [activity addAttachment:Named([XCTAttachment attachmentWithString:@"from activity"], @"inside")];
    }];
    XCTFail(@"fails after the activity");
}

- (void)testIssueAttachment
{
    XCTMutableIssue *issue = [[[XCTMutableIssue alloc] initWithType:XCTIssueTypeAssertionFailure
                                                 compactDescription:@"issue with an attachment"] autorelease];

    [issue addAttachment:Named([XCTAttachment attachmentWithString:@"issue data"], @"evidence")];
    XCTAssertEqual([[issue attachments] count], (NSUInteger)1);
    [self recordIssue:issue];
}

- (void)testAttachmentProperties
{
    XCTAttachment *attachment = [XCTAttachment attachmentWithData:[NSData data]];

    XCTAssertEqualObjects([attachment uniformTypeIdentifier], @"public.data");
    XCTAssertEqual([attachment lifetime], XCTAttachmentLifetimeDeleteOnSuccess);
    XCTAssertNil([attachment name]);
    XCTAssertEqualObjects([[XCTAttachment attachmentWithString:@"x"] uniformTypeIdentifier], @"public.plain-text");
    XCTAssertEqualObjects([[XCTAttachment attachmentWithContentsOfFileAtURL:[NSURL fileURLWithPath:@"/tmp/x.json"]]
                             uniformTypeIdentifier], @"public.json");
}

@end
