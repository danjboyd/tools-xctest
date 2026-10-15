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

#import <XCTest/GSXCTStatistics.h>

#include <math.h>
#include <stdlib.h>

const double GSXCTSignificanceLevel = 0.05;

static int GSCompareDoubles(const void *a, const void *b)
{
    double x = *(const double *)a;
    double y = *(const double *)b;

    return x < y ? -1 : (x > y ? 1 : 0);
}

GSXCTSummary GSXCTSummarize(NSArray *values)
{
    GSXCTSummary summary = {0, 0, 0, 0, 0, 0};
    NSUInteger count = [values count];
    double *sorted = NULL;
    double sum = 0;
    double squares = 0;

    if (count == 0) {
        return summary;
    }

    sorted = malloc(count * sizeof(double));
    for (NSUInteger i = 0; i < count; i++) {
        sorted[i] = [[values objectAtIndex:i] doubleValue];
        sum += sorted[i];
    }
    qsort(sorted, count, sizeof(double), GSCompareDoubles);

    summary.count = count;
    summary.mean = sum / count;
    summary.minimum = sorted[0];
    summary.maximum = sorted[count - 1];
    summary.median = (count % 2) ? sorted[count / 2] : (sorted[count / 2 - 1] + sorted[count / 2]) / 2;
    if (count > 1) {
        for (NSUInteger i = 0; i < count; i++) {
            squares += (sorted[i] - summary.mean) * (sorted[i] - summary.mean);
        }
        summary.standardDeviation = sqrt(squares / (count - 1));
    }

    free(sorted);
    return summary;
}

// The continued fraction for the regularized incomplete beta function
// (modified Lentz's method).
static double GSBetaContinuedFraction(double a, double b, double x)
{
    const double tiny = 1e-300;
    double c = 1;
    double d = 1 - (a + b) * x / (a + 1);
    double h;

    if (fabs(d) < tiny) {
        d = tiny;
    }
    d = 1 / d;
    h = d;
    for (int m = 1; m <= 300; m++) {
        double numerator = m * (b - m) * x / ((a + 2 * m - 1) * (a + 2 * m));
        double delta;

        d = 1 + numerator * d;
        d = fabs(d) < tiny ? 1 / tiny : 1 / d;
        c = 1 + numerator / c;
        if (fabs(c) < tiny) {
            c = tiny;
        }
        h *= d * c;

        numerator = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 2 * m + 1));
        d = 1 + numerator * d;
        d = fabs(d) < tiny ? 1 / tiny : 1 / d;
        c = 1 + numerator / c;
        if (fabs(c) < tiny) {
            c = tiny;
        }
        delta = d * c;
        h *= delta;
        if (fabs(delta - 1) < 1e-14) {
            break;
        }
    }
    return h;
}

// I_x(a, b), the regularized incomplete beta function, for 0 <= x <= 1.
static double GSIncompleteBeta(double a, double b, double x)
{
    double front;

    if (x <= 0) {
        return 0;
    }
    if (x >= 1) {
        return 1;
    }
    front = exp(lgamma(a + b) - lgamma(a) - lgamma(b) + a * log(x) + b * log(1 - x));
    // The continued fraction converges quickly on this side.
    if (x < (a + 1) / (a + b + 2)) {
        return front * GSBetaContinuedFraction(a, b, x) / a;
    }
    return 1 - front * GSBetaContinuedFraction(b, a, 1 - x) / b;
}

double GSXCTStudentTCDF(double t, double df)
{
    double tail;

    if (isinf(t)) {
        return t > 0 ? 1 : 0;
    }
    // P(|T| > |t|), split between the two tails.
    tail = GSIncompleteBeta(df / 2, 0.5, df / (df + t * t));
    return t > 0 ? 1 - tail / 2 : tail / 2;
}

double GSXCTWelchPValue(double mean1, double standardDeviation1, NSUInteger count1,
                        double mean2, double standardDeviation2, NSUInteger count2)
{
    double variance1, variance2, standardError, df;

    if (count1 < 2 || count2 < 2) {
        return NAN;
    }

    variance1 = standardDeviation1 * standardDeviation1 / count1;
    variance2 = standardDeviation2 * standardDeviation2 / count2;
    standardError = sqrt(variance1 + variance2);
    // Two samples without any spread differ, or don't, for certain.
    if (standardError == 0) {
        return mean1 > mean2 ? 0 : 1;
    }
    // Welch-Satterthwaite.
    df = (variance1 + variance2) * (variance1 + variance2)
        / (variance1 * variance1 / (count1 - 1) + variance2 * variance2 / (count2 - 1));
    return 1 - GSXCTStudentTCDF((mean1 - mean2) / standardError, df);
}
