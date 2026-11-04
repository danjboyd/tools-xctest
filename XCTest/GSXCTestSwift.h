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

#ifndef GSXCTestSwift_h
#define GSXCTestSwift_h

// Swift support, kept to this header and GSXCTestSwiftOverlay.h. The other
// headers mark what Swift needs with these macros. When Swift imports the
// headers (__swift__ is defined), they add the annotations that give Apple's
// Swift names and types. Otherwise they're empty, or give the plain
// Objective-C declaration, so the headers read as if there were no Swift
// support at all.

#if defined(__swift__)

/* Apple's Swift name for a declaration, where the imported one would differ. */
#  define GS_XCT_SWIFT_NAME(name) __attribute__((swift_name(#name)))

/* Non-null by default, and optional where marked. */
#  define GS_XCT_ASSUME_NONNULL_BEGIN _Pragma("clang assume_nonnull begin")
#  define GS_XCT_ASSUME_NONNULL_END _Pragma("clang assume_nonnull end")
#  define GS_XCT_NULLABLE _Nullable

/* Around a header only partly annotated, which clang would otherwise warn about. */
#  define GS_XCT_PARTLY_ANNOTATED_BEGIN \
     _Pragma("clang diagnostic push") \
     _Pragma("clang diagnostic ignored \"-Wnullability-completeness\"")
#  define GS_XCT_PARTLY_ANNOTATED_END _Pragma("clang diagnostic pop")

/* An enum Swift imports as an enum with cases like .completed. gnustep-base's
 * NS_ENUM doesn't give that. Its type is unsigned int, as for the plain
 * typedef enum below, which the library is compiled with: the two must match. */
#  define GS_XCT_ENUM_BEGIN(name) enum __attribute__((enum_extensibility(open))) name : unsigned int {
#  define GS_XCT_ENUM_END(name) }; typedef enum name name;

/* A class method that Swift imports as a class property, by another name. */
#  define GS_XCT_CLASS_GETTER(type, name, swiftName) \
     @property (class, readonly, copy) type _Nonnull name __attribute__((swift_name(#swiftName)));

#else

#  define GS_XCT_SWIFT_NAME(name)
#  define GS_XCT_ASSUME_NONNULL_BEGIN
#  define GS_XCT_ASSUME_NONNULL_END
#  define GS_XCT_NULLABLE
#  define GS_XCT_PARTLY_ANNOTATED_BEGIN
#  define GS_XCT_PARTLY_ANNOTATED_END
#  define GS_XCT_ENUM_BEGIN(name) typedef enum {
#  define GS_XCT_ENUM_END(name) } name;
#  define GS_XCT_CLASS_GETTER(type, name, swiftName) + (type) name;

#endif

#endif
