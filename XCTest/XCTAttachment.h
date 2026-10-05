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

@class NSImage;

typedef enum {
    /*! Saved whatever the outcome of the test. */
    XCTAttachmentLifetimeKeepAlways = 0,
    /*! Saved only if the test fails (the default). */
    XCTAttachmentLifetimeDeleteOnSuccess = 1,
} XCTAttachmentLifetime;

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

/*! Data, as "public.data" unless given a type. */
+ (id) attachmentWithData: (NSData *)payload;
+ (id) attachmentWithData: (NSData *)payload uniformTypeIdentifier: (NSString *)identifier;

/*! A file's contents, read now; named after the file. */
+ (id) attachmentWithContentsOfFileAtURL: (NSURL *)url;
+ (id) attachmentWithContentsOfFileAtURL: (NSURL *)url uniformTypeIdentifier: (NSString *)identifier;

/*! UTF-8 text. */
+ (id) attachmentWithString: (NSString *)string;

/*! An object archived with NSKeyedArchiver. */
+ (id) attachmentWithArchivableObject: (id<NSCoding>)object;
+ (id) attachmentWithArchivableObject: (id<NSCoding>)object uniformTypeIdentifier: (NSString *)identifier;

/*! A property list, as XML. */
+ (id) attachmentWithPlistObject: (id)object;

/*! An image, as PNG (or JPEG for lower qualities). Needs AppKit to be
 * loaded, as it is in tests that use NSImage. */
+ (id) attachmentWithImage: (NSImage *)image;
+ (id) attachmentWithImage: (NSImage *)image quality: (XCTImageQuality)quality;

/*! e.g. "public.png". */
@property (readonly, copy) NSString *uniformTypeIdentifier;
/*! Used to name the saved file; nil for a default name. */
@property (copy) NSString *name;
@property (copy) NSDictionary *userInfo;
/*! Defaults to XCTAttachmentLifetimeDeleteOnSuccess. */
@property XCTAttachmentLifetime lifetime;

@end
