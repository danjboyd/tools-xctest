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

#import <Foundation/Foundation.h>

// Parts of this header are annotated for Swift; clang would warn about the rest.
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#endif

@class NSImage;

// For Swift: the attribute makes this an enum with cases like .keepAlways;
// gnustep-base's NS_ENUM doesn't add it.
#if defined(__clang__)
enum __attribute__((enum_extensibility(open))) XCTAttachmentLifetime : NSInteger {
#else
enum XCTAttachmentLifetime {
#endif
    /*! Saved whatever the outcome of the test. */
    XCTAttachmentLifetimeKeepAlways = 0,
    /*! Saved only if the test fails (the default). */
    XCTAttachmentLifetimeDeleteOnSuccess = 1,
};
typedef enum XCTAttachmentLifetime XCTAttachmentLifetime;

// For Swift: Apple's name, where the imported one would differ.
#if defined(__clang__)
#  define GS_XCT_SWIFT_NAME(name) __attribute__((swift_name(#name)))
#else
#  define GS_XCT_SWIFT_NAME(name)
#endif

typedef enum {
    /*! Lossless (PNG). */
    XCTImageQualityOriginal = 0,
    /*! JPEG, medium compression. */
    XCTImageQualityMedium = 1,
    /*! JPEG, high compression. */
    XCTImageQualityLow = 2,
} XCTImageQuality;

/*!
 * Data kept with a test's results: logs, files, images, archived objects.
 * Add one with -[XCTestCase addAttachment:], -[XCTActivity addAttachment:]
 * or an issue's attachments. xctest saves them under -attachments-path
 * (or next to the -junit-report) and lists them in the JUnit report.
 */
@interface XCTAttachment : NSObject {
    NSString *_uniformTypeIdentifier;
    NSString *_name;
    NSData *_payload;
    NSDictionary *_userInfo;
    XCTAttachmentLifetime _lifetime;
    NSString *_gsFileExtension;
}

- (id) initWithUniformTypeIdentifier: (NSString *)identifier
                                name: (NSString *)name
                             payload: (NSData *)payload
                            userInfo: (NSDictionary *)userInfo;
+ (id) attachmentWithUniformTypeIdentifier: (NSString *)identifier
                                      name: (NSString *)name
                                   payload: (NSData *)payload
                                  userInfo: (NSDictionary *)userInfo;

NS_ASSUME_NONNULL_BEGIN

/*! Data, as "public.data" unless given a type. */
+ (instancetype) attachmentWithData: (NSData *)payload;
+ (instancetype) attachmentWithData: (NSData *)payload uniformTypeIdentifier: (NSString *)identifier;

/*! A file's contents, read now; named after the file. */
+ (instancetype) attachmentWithContentsOfFileAtURL: (NSURL *)url
    GS_XCT_SWIFT_NAME(init(contentsOfFile:));
+ (instancetype) attachmentWithContentsOfFileAtURL: (NSURL *)url uniformTypeIdentifier: (NSString *)identifier
    GS_XCT_SWIFT_NAME(init(contentsOfFile:uniformTypeIdentifier:));

/*! UTF-8 text. */
+ (instancetype) attachmentWithString: (NSString *)string;

/*! An object archived with NSKeyedArchiver. */
+ (instancetype) attachmentWithArchivableObject: (id<NSCoding>)object;
+ (instancetype) attachmentWithArchivableObject: (id<NSCoding>)object uniformTypeIdentifier: (NSString *)identifier;

/*! A property list, as XML. */
+ (instancetype) attachmentWithPlistObject: (id)object;

/*! An image, as PNG (or JPEG for lower qualities). Needs AppKit to be
 * loaded, as it is in tests that use NSImage. */
+ (instancetype) attachmentWithImage: (NSImage *)image;
+ (instancetype) attachmentWithImage: (NSImage *)image quality: (XCTImageQuality)quality;

NS_ASSUME_NONNULL_END

/*! e.g. "public.png". */
@property (readonly, copy) NSString *uniformTypeIdentifier;
/*! Used to name the saved file; nil for a default name. */
@property (copy) NSString *name;
@property (copy) NSDictionary *userInfo;
/*! Defaults to XCTAttachmentLifetimeDeleteOnSuccess. */
@property XCTAttachmentLifetime lifetime;

@end

#if defined(__clang__)
#pragma clang diagnostic pop
#endif
