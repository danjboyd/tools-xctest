/*
 This file is part of the GNUstep XCTEST Library.

 This library is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 2 of the License, or (at your option) any later version.

 This library is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.     See the GNU
 Lesser General Public License for more details.

 You should have received a copy of the GNU Lesser General Public
 License along with this library; see the file COPYING.LIB.
 If not, see <http://www.gnu.org/licenses/> or write to the
 Free Software Foundation, 51 Franklin Street, Fifth Floor,
 Boston, MA 02110-1301, USA.
*/

#import <XCTest/XCTAttachment.h>
#import <XCTest/XCTestPrivate.h>

// File extensions for the types xctest knows how to name.
static NSDictionary *GSExtensionsByType(void)
{
    static NSDictionary *extensions = nil;

    if (extensions == nil) {
        extensions = [[NSDictionary alloc] initWithObjectsAndKeys:
            @"png", @"public.png",
            @"jpg", @"public.jpeg",
            @"tiff", @"public.tiff",
            @"gif", @"com.compuserve.gif",
            @"txt", @"public.plain-text",
            @"txt", @"public.utf8-plain-text",
            @"json", @"public.json",
            @"xml", @"public.xml",
            @"html", @"public.html",
            @"plist", @"com.apple.property-list",
            @"plist", @"com.apple.xml-property-list",
            @"plist", @"com.apple.binary-property-list",
            @"zip", @"public.zip-archive",
            @"pdf", @"com.adobe.pdf",
            @"log", @"com.apple.log",
            @"bin", @"public.data",
            nil];
    }
    return extensions;
}

// The type for a file extension, or "public.data".
static NSString *GSTypeForExtension(NSString *extension)
{
    NSDictionary *extensions = GSExtensionsByType();
    NSString *lowercase = [extension lowercaseString];

    if ([lowercase isEqualToString:@"jpeg"]) {
        return @"public.jpeg";
    }
    if ([lowercase isEqualToString:@"txt"]) {
        return @"public.plain-text";
    }
    for (NSString *type in extensions) {
        if ([[extensions objectForKey:type] isEqualToString:lowercase]) {
            return type;
        }
    }
    return @"public.data";
}

@implementation XCTAttachment

- (id) init
{
    return [self initWithUniformTypeIdentifier:nil name:nil payload:nil userInfo:nil];
}

- (id) initWithUniformTypeIdentifier: (NSString *)identifier
                                name: (NSString *)name
                             payload: (NSData *)payload
                            userInfo: (NSDictionary *)userInfo
{
    self = [super init];
    if (self) {
        _uniformTypeIdentifier = [(identifier ? identifier : @"public.data") copy];
        _name = [name copy];
        _payload = [payload copy];
        _userInfo = [userInfo copy];
        _lifetime = XCTAttachmentLifetimeDeleteOnSuccess;
    }

    return self;
}

+ (id) attachmentWithUniformTypeIdentifier: (NSString *)identifier
                                      name: (NSString *)name
                                   payload: (NSData *)payload
                                  userInfo: (NSDictionary *)userInfo
{
    return [[[self alloc] initWithUniformTypeIdentifier:identifier name:name payload:payload userInfo:userInfo] autorelease];
}

- (void) dealloc
{
    [_uniformTypeIdentifier release];
    [_name release];
    [_payload release];
    [_userInfo release];
    [_gsFileExtension release];
    [super dealloc];
}

+ (id) attachmentWithData: (NSData *)payload
{
    return [self attachmentWithData:payload uniformTypeIdentifier:@"public.data"];
}

+ (id) attachmentWithData: (NSData *)payload uniformTypeIdentifier: (NSString *)identifier
{
    return [self attachmentWithUniformTypeIdentifier:identifier name:nil payload:payload userInfo:nil];
}

+ (id) attachmentWithContentsOfFileAtURL: (NSURL *)url
{
    return [self attachmentWithContentsOfFileAtURL:url
                             uniformTypeIdentifier:GSTypeForExtension([[url path] pathExtension])];
}

+ (id) attachmentWithContentsOfFileAtURL: (NSURL *)url uniformTypeIdentifier: (NSString *)identifier
{
    NSString *path = [url path];
    XCTAttachment *attachment = [self attachmentWithUniformTypeIdentifier:identifier
                                                                     name:[path lastPathComponent]
                                                                  payload:[NSData dataWithContentsOfFile:path]
                                                                 userInfo:nil];

    attachment->_gsFileExtension = [[path pathExtension] copy];
    return attachment;
}

+ (id) attachmentWithString: (NSString *)string
{
    return [self attachmentWithData:[string dataUsingEncoding:NSUTF8StringEncoding]
              uniformTypeIdentifier:@"public.plain-text"];
}

+ (id) attachmentWithArchivableObject: (id<NSCoding>)object
{
    return [self attachmentWithArchivableObject:object uniformTypeIdentifier:@"com.apple.binary-property-list"];
}

+ (id) attachmentWithArchivableObject: (id<NSCoding>)object uniformTypeIdentifier: (NSString *)identifier
{
    return [self attachmentWithData:[NSKeyedArchiver archivedDataWithRootObject:object]
              uniformTypeIdentifier:identifier];
}

+ (id) attachmentWithPlistObject: (id)object
{
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:object
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:NULL];

    return [self attachmentWithData:data uniformTypeIdentifier:@"com.apple.property-list"];
}

+ (id) attachmentWithImage: (NSImage *)image
{
    return [self attachmentWithImage:image quality:XCTImageQualityOriginal];
}

+ (id) attachmentWithImage: (NSImage *)image quality: (XCTImageQuality)quality
{
    // AppKit isn't linked; use it through the runtime.
    Class bitmapClass = NSClassFromString(@"NSBitmapImageRep");
    SEL tiffSelector = @selector(TIFFRepresentation);
    SEL representationSelector = @selector(representationUsingType:properties:);
    NSData *tiff = [(id)image respondsToSelector:tiffSelector] ? [(id)image performSelector:tiffSelector] : nil;
    id bitmap = (tiff && bitmapClass) ? [bitmapClass performSelector:@selector(imageRepWithData:) withObject:tiff] : nil;
    // NSPNGFileType and NSJPEGFileType.
    NSUInteger fileType = quality == XCTImageQualityOriginal ? 4 : 3;
    NSDictionary *properties = quality == XCTImageQualityOriginal ? [NSDictionary dictionary]
        : [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:(quality == XCTImageQualityMedium ? 0.7 : 0.4)]
                                      forKey:@"NSImageCompressionFactor"];
    NSData *data = nil;

    if ([bitmap respondsToSelector:representationSelector]) {
        NSData *(*represent)(id, SEL, NSUInteger, NSDictionary *) =
            (NSData *(*)(id, SEL, NSUInteger, NSDictionary *))[bitmap methodForSelector:representationSelector];
        data = represent(bitmap, representationSelector, fileType, properties);
    }

    if (data != nil) {
        return [self attachmentWithData:data uniformTypeIdentifier:(fileType == 4 ? @"public.png" : @"public.jpeg")];
    }
    // Couldn't encode it; keep what we have.
    return [self attachmentWithData:tiff uniformTypeIdentifier:@"public.tiff"];
}

- (NSString *) uniformTypeIdentifier
{
    return _uniformTypeIdentifier;
}

- (NSString *) name
{
    return [[_name retain] autorelease];
}

- (void) setName: (NSString *)name
{
    NSString *old = _name;

    _name = [name copy];
    [old release];
}

- (NSDictionary *) userInfo
{
    return [[_userInfo retain] autorelease];
}

- (void) setUserInfo: (NSDictionary *)userInfo
{
    NSDictionary *old = _userInfo;

    _userInfo = [userInfo copy];
    [old release];
}

- (XCTAttachmentLifetime) lifetime
{
    return _lifetime;
}

- (void) setLifetime: (XCTAttachmentLifetime)lifetime
{
    _lifetime = lifetime;
}

@end

@implementation XCTAttachment (GSPrivate)

- (NSData *) _gsPayload
{
    return _payload;
}

- (NSString *) _gsFileExtension
{
    if ([_gsFileExtension length] > 0) {
        return _gsFileExtension;
    }

    NSString *extension = [GSExtensionsByType() objectForKey:_uniformTypeIdentifier];
    return extension ? extension : @"bin";
}

@end

void _GSXCTAddAttachment(XCTestCase *test, XCTAttachment *attachment, NSArray *activityPath)
{
    GSXCTAttachmentRecord *record = nil;

    if (test == nil) {
        test = [XCTestCase _gsCurrentTestCase];
    }
    if (attachment == nil) {
        return;
    }
    if (test == nil || [test testRun] == nil) {
        NSLog(@"XCTest: Attachment '%@' added outside of a running test; ignored.",
            [attachment name] ? [attachment name] : @"Attachment");
        return;
    }

    record = [[[GSXCTAttachmentRecord alloc] initWithAttachment:attachment activityPath:activityPath] autorelease];
    [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
        if ([observer respondsToSelector:@selector(_gsTestCase:didAddAttachment:)]) {
            [observer _gsTestCase:test didAddAttachment:record];
        }
    }];
}
