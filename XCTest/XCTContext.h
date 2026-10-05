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
#import <XCTest/XCTActivity.h>

@interface XCTContext : NSObject

/*!
 * Runs \a block as a named step of the current test. Activities nest, per
 * thread; issues recorded while one runs are reported with its name (and
 * those of the activities around it), e.g. "Log in > Enter password:
 * ((valid) is true) failed". Exceptions raised by the block propagate.
 */
+ (void) runActivityNamed: (NSString *)name block: (void (^)(id<XCTActivity> activity))block;

@end
