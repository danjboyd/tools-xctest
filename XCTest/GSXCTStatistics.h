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

// Private (not installed): the statistics behind performance measurements.

#ifndef GSXCTSTATISTICS_H
#define GSXCTSTATISTICS_H

#import <Foundation/Foundation.h>

/*! A summary of a measurement's values. */
typedef struct {
    NSUInteger count;
    double mean;
    double median;
    /*! The sample standard deviation (n - 1); 0 for fewer than 2 values. */
    double standardDeviation;
    double minimum;
    double maximum;
} GSXCTSummary;

/*! Summarizes \a values (NSNumbers); all zero for none. */
GSXCTSummary GSXCTSummarize(NSArray *values);

/*! P(T <= t) for Student's t distribution with \a df degrees of freedom
 * (df > 0, which need not be a whole number). */
double GSXCTStudentTCDF(double t, double df);

/*!
 * Welch's t-test, one-sided: the p-value for the first sample's mean being
 * larger than the second's, from each sample's mean, sample standard
 * deviation and size. Small values mean the first is significantly larger.
 * NAN if either sample has fewer than 2 values.
 */
double GSXCTWelchPValue(double mean1, double standardDeviation1, NSUInteger count1,
                        double mean2, double standardDeviation2, NSUInteger count2);

/*! A p-value below this is a significant difference. */
extern const double GSXCTSignificanceLevel;

#endif
