/*
 * Copyright (c) 2022 Jonathan Swinney <jswinney@amazon.com>
 *
 * This file is part of FFmpeg.
 *
 * FFmpeg is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include "libavutil/aarch64/asm.S"

function ff_pix_abs16_neon, export=1
        // x0           unused
        // x1           uint8_t *pix1
        // x2           uint8_t *pix2
        // x3           ptrdiff_t stride
        // w4           int h
        cmp             w4, #4                      // if h < 4, jump to completion section
        movi            v16.8h, #0                  // clear result accumulator
        movi            v17.8h, #0                  // clear result accumulator
        b.lt            2f
1:
        ld1             {v0.16b}, [x1], x3          // load pix1
        ld1             {v4.16b}, [x2], x3          // load pix2
        ld1             {v1.16b}, [x1], x3          // load pix1
        ld1             {v5.16b}, [x2], x3          // load pix2
        uabal           v16.8h, v0.8b, v4.8b        // absolute difference accumulate
        uabal2          v17.8h, v0.16b, v4.16b
        ld1             {v2.16b}, [x1], x3          // load pix1
        ld1             {v6.16b}, [x2], x3          // load pix2
        uabal           v16.8h, v1.8b, v5.8b        // absolute difference accumulate
        uabal2          v17.8h, v1.16b, v5.16b
        ld1             {v3.16b}, [x1], x3
        ld1             {v7.16b}, [x2], x3
        uabal           v16.8h, v2.8b, v6.8b
        uabal2          v17.8h, v2.16b, v6.16b
        sub             w4, w4, #4                  // h -= 4
        uabal           v16.8h, v3.8b, v7.8b
        uabal2          v17.8h, v3.16b, v7.16b
        cmp             w4, #4                      // if h >= 4, loop

        b.ge            1b
        cbnz            w4, 2f                      // if iterations remain, jump to completion section

        add             v16.8h, v16.8h, v17.8h
        uaddlv          s16, v16.8h                 // add up everything in v16 accumulator
        fmov            w0, s16                     // copy result to general purpose register
        ret

2:
        ld1             {v0.16b}, [x1], x3          // load pix1
        ld1             {v4.16b}, [x2], x3          // load pix2
        subs            w4, w4, #1                  // h -= 1
        uabal           v16.8h, v0.8b, v4.8b        // absolute difference accumulate
        uabal2          v17.8h, v0.16b, v4.16b
        b.ne            2b

        add             v16.8h, v16.8h, v17.8h
        uaddlv          s16, v16.8h                 // add up everything in v16 accumulator
        fmov            w0, s16                     // copy result to general purpose register
        ret
endfunc

function ff_pix_abs8_neon, export=1
        // x0           unused
        // x1           uint8_t *pix1
        // x2           uint8_t *pix2
        // x3           ptrdiff_t stride
        // x4           int h

        movi            d18, #0
        cmp             w4, #4
        b.lt            2f

// make 4 iterations at once
1:
        ld1             {v0.8b}, [x1], x3               // Load pix1 for first iteration
        ld1             {v1.8b}, [x2], x3               // Load pix2 for first iteration
        uabdl           v30.8h, v0.8b, v1.8b            // Absolute difference, first iteration
        ld1             {v2.8b}, [x1], x3               // Load pix1 for second iteration
        ld1             {v3.8b}, [x2], x3               // Load pix2 for second iteration
        uabal           v30.8h, v2.8b, v3.8b            // Absolute difference, second iteration
        ld1             {v4.8b}, [x1], x3               // Load pix1 for third iteration
        ld1             {v5.8b}, [x2], x3               // Load pix2 for third iteration
        uabal           v30.8h, v4.8b, v5.8b            // Absolute difference, third iteration
        ld1             {v6.8b}, [x1], x3               // Load pix1 for foruth iteration
        ld1             {v7.8b}, [x2], x3               // Load pix2 for fourth iteration
        uabal           v30.8h, v6.8b, v7.8b            // Absolute difference, foruth iteration

        sub             w4, w4, #4                      // h -= 4
        uaddlv          s20, v30.8h                     // Add up vector
        cmp             w4, #4
        add             d18, d18, d20
        b.ge            1b
        cbnz            w4, 2f
        fmov            w0, s18

        ret

// iterate by one
2:
        ld1             {v0.8b}, [x1], x3               // Load pix1
        ld1             {v1.8b}, [x2], x3               // Load pix2

        uabdl           v16.8h, v0.8b, v1.8b

        uaddlv          s17, v16.8h
        add             d18, d18, d17
        subs            w4, w4, #1
        b.ne            2b
        fmov            w0, s18

        ret

endfunc

function ff_pix_abs16_xy2_neon, export=1
        // x0           unused
        // x1           uint8_t *pix1
        // x2           uint8_t *pix2
        // x3           ptrdiff_t stride
        // w4           int h

        add             x5, x2, x3                  // use x5 to hold uint8_t *pix3
        movi            v21.8h, #0                  // initialize the result register
        movi            v22.8h, #0                  // initialize the result register

        // Load initial pix2 values for either the unrolled version or completion version.
        ldur            q4, [x2, #1]                // load pix2+1
        ldr             q3, [x2]                    // load pix2
        uaddl           v2.8h, v4.8b, v3.8b         // pix2 + pix2+1 0..7
        uaddl2          v3.8h, v4.16b, v3.16b       // pix2 + pix2+1 8..15
        cmp             w4, #4                      // if h < 4 jump to the completion version
        b.lt            2f
1:
        // This is an unrolled implementation. It completes 4 iterations of the C for each branch.
        // In each iteration, pix2[i+1] == pix3[i]. This means we need only three loads per iteration,
        // plus two at the beginning to start.
        ldur            q5, [x5, #1]                // load pix3+1
        ld1             {v4.16b}, [x5], x3          // load pix3
        ld1             {v1.16b}, [x1], x3          // load pix1

        ldur            q7, [x5, #1]                // load pix3+1
        ld1             {v6.16b}, [x5], x3          // load pix3
        ld1             {v16.16b}, [x1], x3         // load pix1

        // These blocks compute the average: avg(pix2[n], pix2[n+1], pix3[n], pix3[n+1])
        uaddl           v30.8h, v4.8b, v5.8b        // pix3 + pix3+1 0..7
        uaddl2          v31.8h, v4.16b, v5.16b      // pix3 + pix3+1 8..15

        ldur            q19, [x5, #1]               // load pix3+1

        add             v23.8h, v2.8h, v30.8h       // add up 0..7, using pix2 + pix2+1 values from previous iteration
        add             v24.8h, v3.8h, v31.8h       // add up 8..15, using pix2 + pix2+1 values from previous iteration

        ld1             {v18.16b}, [x5], x3         // load pix3
        ld1             {v17.16b}, [x1], x3         // load pix1

        rshrn           v23.8b, v23.8h, #2          // shift right 2 0..7 (rounding shift right)
        rshrn2          v23.16b, v24.8h, #2         // shift right 2 8..15

        uaddl           v2.8h, v6.8b, v7.8b         // pix3 + pix3+1 0..7
        uaddl2          v3.8h, v6.16b, v7.16b       // pix3 + pix3+1 8..15

        ldur            q7, [x5, #1]                // load pix3+1

        add             v26.8h, v30.8h, v2.8h       // add up 0..7, using pix2 + pix2+1 values from pix3 above
        add             v27.8h, v31.8h, v3.8h       // add up 8..15, using pix2 + pix2+1 values from pix3 above

        uabal           v21.8h, v1.8b,  v23.8b      // absolute difference 0..7, i=0
        uabal2          v22.8h, v1.16b, v23.16b     // absolute difference 8..15, i=0

        ld1             {v6.16b}, [x5], x3          // load pix3
        ld1             {v20.16b}, [x1], x3         // load pix1

        rshrn           v26.8b, v26.8h, #2          // shift right 2 0..7 (rounding shift right)
        rshrn2          v26.16b, v27.8h, #2         // shift right 2 8..15

        uaddl           v4.8h, v18.8b, v19.8b       // pix3 + pix3+1 0..7
        uaddl2          v5.8h, v18.16b, v19.16b     // pix3 + pix3+1 8..15
        add             v28.8h, v2.8h, v4.8h        // add up 0..7, using pix2 + pix2+1 values from pix3 above
        add             v29.8h, v3.8h, v5.8h        // add up 8..15, using pix2 + pix2+1 values from pix3 above
        rshrn           v28.8b, v28.8h, #2          // shift right 2 0..7 (rounding shift right)
        rshrn2          v28.16b, v29.8h, #2         // shift right 2 8..15

        uabal           v21.8h, v16.8b,  v26.8b     // absolute difference 0..7, i=1
        uabal2          v22.8h, v16.16b, v26.16b    // absolute difference 8..15, i=1

        uaddl           v2.8h, v6.8b,  v7.8b        // pix3 + pix3+1 0..7
        uaddl2          v3.8h, v6.16b, v7.16b       // pix3 + pix3+1 8..15
        add             v30.8h, v4.8h, v2.8h        // add up 0..7, using pix2 + pix2+1 values from pix3 above
        add             v31.8h, v5.8h, v3.8h        // add up 8..15, using pix2 + pix2+1 values from pix3 above
        rshrn           v30.8b, v30.8h, #2          // shift right 2 0..7 (rounding shift right)
        rshrn2          v30.16b, v31.8h, #2         // shift right 2 8..15

        sub             w4, w4, #4                  // h -= 4

        uabal           v21.8h, v17.8b,  v28.8b     // absolute difference 0..7, i=2
        uabal2          v22.8h, v17.16b, v28.16b    // absolute difference 8..15, i=2

        cmp             w4, #4                      // loop if h >= 4


        uabal           v21.8h, v20.8b,  v30.8b     // absolute difference 0..7, i=3
        uabal2          v22.8h, v20.16b, v30.16b    // absolute difference 8..15, i=3

        b.ge            1b
        cbnz            w4, 2f                      // if iterations remain jump to completion section

        add             v4.8h, v21.8h, v22.8h
        uaddlv          s0, v4.8h                   // finish adding up accumulated values

        fmov            w0, s0                      // copy result to general purpose register
        ret
2:
        // v2 and v3 are set either at the end of this loop or at from the unrolled version
        // which branches here to complete iterations when h % 4 != 0.
        ldur            q5, [x5, #1]                // load pix3+1
        ld1             {v4.16b}, [x5], x3          // load pix3
        ld1             {v1.16b}, [x1], x3          // load pix1
        subs            w4, w4, #1                  // decrement h

        uaddl           v18.8h, v4.8b, v5.8b        // pix3 + pix3+1 0..7
        uaddl2          v19.8h, v4.16b, v5.16b      // pix3 + pix3+1 8..15
        add             v16.8h, v2.8h, v18.8h       // add up 0..7, using pix2 + pix2+1 values from previous iteration
        add             v17.8h, v3.8h, v19.8h       // add up 8..15, using pix2 + pix2+1 values from previous iteration
        // divide by 4 to compute the average of values summed above
        rshrn           v16.8b,  v16.8h, #2         // shift right by 2 0..7 (rounding shift right)
        rshrn2          v16.16b, v17.8h, #2         // shift right by 2 8..15

        uabal           v21.8h, v1.8b,  v16.8b      // absolute difference 0..7
        uabal2          v22.8h, v1.16b, v16.16b     // absolute difference accumulate 8..15
        mov             v2.16b, v18.16b             // pix3 -> pix2
        mov             v3.16b, v19.16b             // pix3+1 -> pix2+1

        b.ne            2b                          // loop if h > 0

        add             v4.8h, v21.8h, v22.8h
        uaddlv          s0, v4.8h                   // finish adding up accumulated values
        fmov            w0, s0                      // copy result to general purpose register
        ret
endfunc

function ff_pix_abs16_x2_neon, export=1
        // x0           unused
        // x1           uint8_t *pix1
        // x2           uint8_t *pix2
        // x3           ptrdiff_t stride
        // w4           int h

        cmp             w4, #4
        // initialize buffers
        movi            v16.8h, #0
        movi            v17.8h, #0
        add             x5, x2, #1 // pix2 + 1
        b.lt            2f

// make 4 iterations at once
1:

        // abs(pix1[0] - avg2(pix2[0], pix2[1]))
        // avg2(a,b) = (((a) + (b) + 1) >> 1)
        // abs(x) = (x < 0 ? -x : x)

        ld1             {v1.16b}, [x2], x3
        ld1             {v2.16b}, [x5], x3
        urhadd          v30.16b, v1.16b, v2.16b
        ld1             {v0.16b}, [x1], x3
        uabal           v16.8h, v0.8b, v30.8b
        ld1             {v4.16b}, [x2], x3
        uabal2          v17.8h, v0.16b, v30.16b
        ld1             {v5.16b}, [x5], x3
        urhadd          v29.16b, v4.16b, v5.16b
        ld1             {v3.16b}, [x1], x3
        uabal           v16.8h, v3.8b, v29.8b
        ld1             {v7.16b}, [x2], x3
        uabal2          v17.8h, v3.16b, v29.16b
        ld1             {v22.16b}, [x5], x3
        urhadd          v28.16b, v7.16b, v22.16b
        ld1             {v6.16b}, [x1], x3
        uabal           v16.8h, v6.8b, v28.8b
        ld1             {v24.16b}, [x2], x3
        sub             w4, w4, #4
        uabal2          v17.8h, v6.16b, v28.16b
        ld1             {v25.16b}, [x5], x3
        urhadd          v27.16b, v24.16b, v25.16b
        ld1             {v23.16b}, [x1], x3
        cmp             w4, #4
        uabal           v16.8h, v23.8b, v27.8b
        uabal2          v17.8h, v23.16b, v27.16b

        b.ge            1b
        cbz             w4, 3f

// iterate by one
2:
        ld1             {v1.16b}, [x2], x3
        ld1             {v2.16b}, [x5], x3
        subs            w4, w4, #1
        urhadd          v29.16b, v1.16b, v2.16b
        ld1             {v0.16b}, [x1], x3
        uabal           v16.8h, v0.8b,  v29.8b
        uabal2          v17.8h, v0.16b, v29.16b


        b.ne            2b

3:
        add             v16.8h, v16.8h, v17.8h
        uaddlv          s16, v16.8h
        fmov            w0, s16

        ret
endfunc

function sse16_neon, export=1
        // x0 - unused
        // x1 - pix1
        // x2 - pix2
        // x3 - stride
        // w4 - h

        cmp             w4, #4
        movi            d18, #0
        b.lt            2f

// Make 4 iterations at once
1:

        // res = abs(pix1[0] - pix2[0])
        // res * res

        ld1             {v0.16b}, [x1], x3              // Load pix1 vector for first iteration
        ld1             {v1.16b}, [x2], x3              // Load pix2 vector for first iteration
        uabd            v30.16b, v0.16b, v1.16b         // Absolute difference, first iteration
        ld1             {v2.16b}, [x1], x3              // Load pix1 vector for second iteration
        umull           v29.8h, v30.8b, v30.8b          // Multiply lower half of vectors, first iteration
        ld1             {v3.16b}, [x2], x3              // Load pix2 vector for second iteration
        umull2          v28.8h, v30.16b, v30.16b        // Multiply upper half of vectors, first iteration
        uabd            v27.16b, v2.16b, v3.16b         // Absolute difference, second iteration
        uaddlp          v17.4s, v29.8h                  // Pairwise add, first iteration
        umull           v26.8h, v27.8b, v27.8b          // Mulitply lower half, second iteration
        umull2          v25.8h, v27.16b, v27.16b        // Multiply upper half, second iteration
        ld1             {v4.16b}, [x1], x3              // Load pix1 for third iteration
        uadalp          v17.4s, v26.8h                  // Pairwise add and accumulate, second iteration
        ld1             {v5.16b}, [x2], x3              // Load pix2 for third iteration
        uadalp          v17.4s, v25.8h                  // Pairwise add andd accumulate, second iteration
        uabd            v24.16b, v4.16b, v5.16b         // Absolute difference, third iteration
        ld1             {v6.16b}, [x1], x3              // Load pix1 for fourth iteration
        umull           v23.8h, v24.8b, v24.8b          // Multiply lower half, third iteration
        umull2          v22.8h, v24.16b, v24.16b        // Multiply upper half, third iteration
        uadalp          v17.4s, v23.8h                  // Pairwise add and accumulate, third iteration
        uadalp          v17.4s, v22.8h                  // Pairwise add and accumulate, third iteration
        ld1             {v7.16b}, [x2], x3              // Load pix2 for fouth iteration
        uadalp          v17.4s, v28.8h                  // Pairwise add and accumulate, first iteration
        uabd            v21.16b, v6.16b, v7.16b         // Absolute difference, fourth iteration
        umull           v20.8h, v21.8b, v21.8b          // Multiply lower half, fourth iteration
        uadalp          v17.4s, v20.8h                  // Pairwise add and accumulate, fourth iteration
        umull2          v19.8h, v21.16b, v21.16b        // Multiply upper half, fourth iteration
        uadalp          v17.4s, v19.8h                  // Pairwise add and accumulate, fourth iteration

        sub             w4, w4, #4                      // h -= 4
        uaddlv          d16, v17.4s                     // add up accumulator vector
        cmp             w4, #4
        add             d18, d18, d16

        b.ge            1b

        cbnz            w4, 2f
        fmov            w0, s18

        ret

// iterate by one
2:

        ld1             {v0.16b}, [x1], x3              // Load pix1
        ld1             {v1.16b}, [x2], x3              // Load pix2

        uabd            v30.16b, v0.16b, v1.16b
        umull           v29.8h, v0.8b, v1.8b
        umull2          v28.8h, v0.16b, v1.16b
        uaddlp          v17.4s, v29.8h
        uadalp          v17.4s, v28.8h


        subs            w4, w4, #1
        uaddlv          d16, v17.4s
        add             d18, d18, d16

        b.ne            2b
        fmov            w0, s18

        ret

endfunc

function sse8_neon, export=1
        // x0 - unused
        // x1 - pix1
        // x2 - pix2
        // x3 - stride
        // w4 - h

        movi            d18, #0
        cmp             w4, #4
        b.le            2f

// make 4 iterations at once
1:

        // res = abs(pix1[0] - pix2[0])
        // res * res

        ld1             {v0.8b}, [x1], x3               // Load pix1 for first iteration
        ld1             {v1.8b}, [x2], x3               // Load pix2 for second iteration
        uabdl           v30.8h, v0.8b, v1.8b            // Absolute difference, first iteration
        umull           v21.4s, v30.4h, v30.4h          // Multiply lower half, first iteration
        ld1             {v2.8b}, [x1], x3               // Load pix1 for second iteration
        umull2          v20.4s, v30.8h, v30.8h          // Multiply upper half, second iteration
        ld1             {v3.8b}, [x2], x3               // Load pix2 for second iteration
        uabdl           v29.8h, v2.8b, v3.8b            // Absolute difference, second iteration
        ld1             {v4.8b}, [x1], x3               // Load pix1 for third iteration
        umlal           v21.4s, v29.4h, v29.4h          // Multiply lower half, second iteration
        ld1             {v5.8b}, [x2], x3               // Load pix2 for third iteration
        umlal2          v20.4s, v29.8h, v29.8h          // Multiply upper half, second iteration
        uabdl           v28.8h, v4.8b, v5.8b            // Absolute difference, third iteration
        ld1             {v6.8b}, [x1], x3               // Load pix1 for fourth iteration
        umlal           v21.4s, v28.4h, v28.4h          // Multiply lower half, third iteration
        ld1             {v7.8b}, [x2], x3               // Load pix2 for fourth iteration
        umlal2          v20.4s, v28.8h, v28.8h          // Multiply upper half, third iteration
        uabdl           v27.8h, v6.8b, v7.8b            // Absolute difference, fourth iteration
        umlal           v21.4s, v27.4h, v27.4h          // Multiply lower half, fourth iteration
        umlal2          v20.4s, v27.8h, v27.8h          // Multiply upper ha;f, fourth iteration

        add             v21.4s, v21.4s, v20.4s          // Add accumulator vectors together
        sub             w4, w4, #4                      // h -= 4
        uaddlv          d17, v21.4s                     // Add up vector
        add             d18, d18, d17
        cmp             w4, #4
        b.ge            1b

        cbnz            w4, 2f
        fmov            w0, s18

        ret

// iterate by one
2:
        ld1             {v0.8b}, [x1], x3               // Load pix1
        ld1             {v1.8b}, [x2], x3               // Load pix2

        uabdl           v30.8h, v0.8b, v1.8b
        umull           v21.4s, v30.4h, v30.4h
        umull2          v20.4s, v30.8h, v30.8h

        subs            w4, w4, #1

        uaddlv          d17, v21.4s
        add             d18, d18, d17
        uaddlv          d17, v20.4S
        add             d18, d18, d17

        b.ne            2b
        fmov            w0, s18

        ret
endfunc

function sse4_neon, export=1
        // x0 - unused
        // x1 - pix1
        // x2 - pix2
        // x3 - stride
        // w4 - h

        movi            d18, #0
        movi            d17, #0
        cmp             w4, #4
        b.le            2f

// make 4 iterations at once
1:

        // res = abs(pix1[0] - pix2[0])
        // res * res

        ld1             {v0.s}[0], [x1], x3             // Load pix1, first iteration
        ld1             {v1.s}[0], [x2], x3             // Load pix2, first iteration
        uabdl           v30.8h, v0.8b, v1.8b            // Absolute difference, first iteration
        ld1             {v2.s}[0], [x1], x3             // Load pix1, second iteration
        ld1             {v3.s}[0], [x2], x3             // Load pix2, second iteration
        umull           v16.4s, v30.4h, v30.4h          // Multiply vectors, first iteration
        uabdl           v29.8h, v2.8b, v3.8b            // Absolute difference, second iteration
        ld1             {v4.s}[0], [x1], x3             // Load pix1, third iteration
        ld1             {v5.s}[0], [x2], x3             // Load pix2, third iteration
        umlal           v16.4s, v29.4h, v29.4h          // Multiply and accumulate, second iteration
        uabdl           v28.8h, v4.8b, v5.8b            // Absolute difference, third iteration
        ld1             {v6.s}[0], [x1], x3             // Load pix1, fourth iteration
        ld1             {v7.s}[0], [x2], x3             // Load pix2, fourth iteration
        umlal           v16.4s, v28.4h, v28.4h          // Multiply and accumulate, third iteration
        uabdl           v27.8h, v6.8b, v7.8b            // Absolue difference, fourth iteration
        umlal           v16.4s, v27.4h, v27.4h          // Multiply and accumulate, fourth iteration

        uaddlv          d17, v16.4s                     // Add vector
        add             d18, d18, d17

        sub             w4, w4, #4
        cmp             w4, #4
        b.ge            1b

        cbnz            w4, 2f
        fmov            w0, s18

        ret

// iterate by one
2:
        ld1             {v0.s}[0], [x1], x3               // Load pix1
        ld1             {v1.s}[0], [x2], x3               // Load pix2
        uabdl           v30.8h, v0.8b, v1.8b
        umull           v16.4s, v30.4h, v30.4h

        uaddlv          d17, v16.4s
        add             d18, d18, d17

        subs            w4, w4, #1
        b.ne            2b
        fmov            w0, s18

        ret

endfunc

function ff_pix_abs16_y2_neon, export=1
        // x0           unused
        // x1           uint8_t *pix1
        // x2           uint8_t *pix2
        // x3           ptrdiff_t stride
        // x4           int h

        // initialize buffers
        movi            d18, #0
        add             x5, x2, x3                      // pix2 + stride
        cmp             w4, #4
        b.lt            2f

// make 4 iterations at once
1:

        // abs(pix1[0], avg2(pix2[0], pix2[0 + stride]))
        // avg2(a, b) = (((a) + (b) + 1) >> 1)
        // abs(x) = (x < 0 ? (-x) : (x))

        ld1             {v1.16b}, [x2], x3              // Load pix2 for first iteration
        ld1             {v2.16b}, [x5], x3              // Load pix3 for first iteration
        urhadd          v30.16b, v1.16b, v2.16b         // Rounding halving add, first iteration
        ld1             {v0.16b}, [x1], x3              // Load pix1 for first iteration
        uabdl           v29.8h, v0.8b, v30.8b           // Absolute difference of lower half, first iteration
        ld1             {v4.16b}, [x2], x3              // Load pix2 for second iteration
        uabdl2          v28.8h, v0.16b, v30.16b         // Absolute difference of upper half, first iteration
        ld1             {v5.16b}, [x5], x3              // Load pix3 for second iteartion
        ld1             {v3.16b}, [x1], x3              // Load pix1 for second iteration
        urhadd          v27.16b, v4.16b, v5.16b         // Rounding halving add, second iteration
        uabal           v29.8h, v3.8b, v27.8b           // Absolute difference of lower half for second iteration
        ld1             {v7.16b}, [x2], x3              // Load pix2 for third iteration
        uabal2          v28.8h, v3.16b, v27.16b         // Absolute difference of upper half for second iteration
        ld1             {v20.16b}, [x5], x3             // Load pix3 for third iteration
        urhadd          v26.16b, v7.16b, v20.16b        // Rounding halving add, third iteration
        ld1             {v6.16b}, [x1], x3              // Load pix1 for third iteration
        uabal           v29.8h, v6.8b, v26.8b           // Absolute difference of lower half for third iteration
        ld1             {v22.16b}, [x2], x3             // Load pix2 for fourth iteration
        uabal2          v28.8h, v6.16b, v26.16b         // Absolute difference of upper half for third iteration
        ld1             {v23.16b}, [x5], x3             // Load pix3 for fourth iteration
        urhadd          v25.16b, v22.16b, v23.16b       // Rounding halving add
        ld1             {v21.16b}, [x1], x3             // Load pix1 for fourth iteration
        uabal           v29.8h, v21.8b, v25.8b          // Absolute difference of lower half for fourth iteration
        uabal2          v28.8h, v21.16b, v25.16b        // Absolute difference of upper half for fourth iteration

        add             v29.8h, v29.8h, v28.8h          // Add vectors together
        sub             w4, w4, #4                      // h-= 4
        uaddlv          s16, v29.8h                     // Add up vector values
        cmp             w4, #4
        add             d18, d18, d16
        b.ge            1b
        cbz             w4, 3f

// iterate by one
2:

        ld1             {v1.16b}, [x2], x3              // Load pix2
        ld1             {v2.16b}, [x5], x3              // Load pix3
        urhadd          v30.16b, v1.16b, v2.16b         // Rounding halving add
        ld1             {v0.16b}, [x1], x3              // Load pix1
        uabd            v30.16b, v30.16b, v30.16b

        uaddlv          h17, v30.16b
        subs            w4, w4, #1
        add             d18, d18, d17
        b.ne            2b

3:
        fmov            w0, s18

        ret
endfunc

function vsad16_neon, export=1
        // x0           unused
        // x1           uint8_t *pix1
        // x2           uint8_t *pix2
        // x3           ptrdiff_t stride
        // x4           int h
        // x5           uint8_t *pix1 + stride
        // x6           uint8_t *pix2 + stride

        // put v10-v13 registers on stack
        stp             d14, d15, [sp, #-0x10]!
        stp             d12, d13, [sp, #-0x10]!
        stp             d10, d11, [sp, #-0x10]!
        stp             d8, d9, [sp, #-0x10]!

        add             x5, x1, x3
        add             x6, x2, x3
        movi            d18, #0
        subs            w4, w4, #1 // we need to make h-1 iterations
        cmp             w4, #4 // check if we can make 4 iterations at once
        b.le            2f

1:
        // abs(pix1[0] - pix2[0] - pix1[0 + stride] + pix2[0 + stride]) =
        // abs( (pix1[0] + pix2[0 + stride]) - (pix2[0] + pix2[0 + stride]) )
        // abs(x) = (x < 0 ? (-x) : (x))

        ld1             {v0.16b}, [x1], x3 // pix1[0]
        ld1             {v1.16b}, [x2], x3 // pix2[0]
        ld1             {v2.16b}, [x5], x3 // pix1[0 + stride]
        ld1             {v3.16b}, [x6], x3 // pix2[0 + stride]

        ld1             {v4.16b}, [x1], x3
        ld1             {v5.16b}, [x2], x3
        ld1             {v6.16b}, [x5], x3
        ld1             {v7.16b}, [x6], x3

        ld1             {v8.16b}, [x1], x3
        ld1             {v9.16b}, [x2], x3
        ld1             {v10.16b}, [x5], x3
        ld1             {v11.16b}, [x6], x3

        ld1             {v12.16b}, [x1], x3
        ld1             {v13.16b}, [x2], x3
        ld1             {v14.16b}, [x5], x3
        ld1             {v15.16b}, [x6], x3

        // first iteration
        usubl           v30.8h, v0.8b, v1.8b
        usubl2          v29.8h, v0.16b, v1.16b
        usubl           v28.8h, v3.8b, v2.8b
        usubl2          v27.8h, v3.16b, v2.16b

        sqadd           v28.8h, v30.8h, v28.8h
        sqadd           v27.8h, v29.8h, v27.8h

        sqabs           v28.8h, v28.8h
        sqabs           v27.8h, v27.8h

        saddlv          s17, v28.8h
        add             d18, d18, d17
        saddlv          s17, v27.8h
        add             d18, d18, d17

        // second iteration
        usubl           v26.8h, v4.8b, v5.8b
        usubl2          v25.8h, v4.16b, v5.16b
        usubl           v24.8h, v7.8b, v6.8b
        usubl2          v23.8h, v7.16b, v6.16b

        sqadd           v24.8h, v26.8h, v24.8h
        sqadd           v23.8h, v25.8h, v23.8h

        sqabs           v24.8h, v24.8h
        sqabs           v23.8h, v23.8h

        saddlv          s17, v24.8h
        add             d18, d18, d17
        saddlv          s17, v23.8h
        add             d18, d18, d17

        // third iteration
        usubl           v22.8h, v8.8b, v9.8b
        usubl2          v21.8h, v8.16b, v9.16b
        usubl           v20.8h, v11.8b, v10.8b
        usubl2          v19.8h, v11.16b, v10.16b

        sqadd           v20.8h, v22.8h, v20.8h
        sqadd           v19.8h, v21.8h, v19.8h

        sqabs           v20.8h, v20.8h
        sqabs           v19.8h, v19.8h

        saddlv          s17, v20.8h
        add             d18, d18, d17
        saddlv          s17, v19.8h
        add             d18, d18, d17

        // fourth iteration
        usubl           v17.8h, v12.8b, v13.8b
        usubl2          v16.8h, v12.16b, v13.16b
        usubl           v30.8h, v15.8b, v14.8b
        usubl2          v29.8h, v15.16b, v14.16b

        sqadd           v17.8h, v17.8h, v30.8h
        sqadd           v16.8h, v16.8h, v29.8h

        sqabs           v17.8h, v17.8h
        sqabs           v16.8h, v16.8h

        saddlv          s17, v17.8h
        add             d18, d18, d17
        saddlv          s17, v16.8h
        add             d18, d18, d17

        sub             w4, w4, #4
        cmp             w4, #4
        b.ge            1b

        fmov            w0, s18
        cbnz            w4, 2f
        cbz             w4, 3f

2:
        cmp             w4, #0
        b.le            3f

        ld1             {v0.16b}, [x1], x3
        ld1             {v1.16b}, [x2], x3
        ld1             {v2.16b}, [x5], x3
        ld1             {v3.16b}, [x6], x3

        usubl           v30.8h, v0.8b, v1.8b
        usubl2          v29.8h, v0.16b, v1.16b
        usubl           v28.8h, v3.8b, v2.8b
        usubl2          v27.8h, v3.16b, v2.16b

        sqadd           v28.8h, v30.8h, v28.8h
        sqadd           v27.8h, v29.8h, v27.8h

        sqabs           v28.8h, v28.8h
        sqabs           v27.8h, v27.8h

        saddlv          s17, v28.8h
        add             d18, d18, d17
        saddlv          s17, v27.8h
        add             d18, d18, d17

        subs            w4, w4, #1
        b.ne            2b
        fmov            w0, s18

3:
        // here preserve registers v8-v15...
        ldp             d8, d9, [sp], 0x10
        ldp             d10, d11, [sp], 0x10
        ldp             d12, d13, [sp], 0x10
        ldp             d14, d15, [sp], 0x10
        ret
endfunc

function vsse16_neon, export=1
        // x0           unused
        // x1           uint8_t *pix1
        // x2           uint8_t *pix2
        // x3           ptrdiff_t stride
        // x4           int h

        // preserve values of v8-v15 registers
        stp             d14, d15, [sp, #-0x10]!
        stp             d12, d13, [sp, #-0x10]!
        stp             d10, d11, [sp, #-0x10]!
        stp             d8, d9, [sp, #-0x10]!

        add             x5, x1, x3 // uint8_t *pix1 + stride
        add             x6, x2, x3 // uint8_t *pix2 + stride
        movi            d18, #0
        subs            w4, w4, #1 // we need to make h-1 iterations
        cmp             w4, #4 // check if we can make 4 iterations at once
        b.le            2f

// make 4 iterations at once
1:
        // abs(pix1[0] - pix2[0] - pix1[0 + stride] + pix2[0 + stride]) =
        // abs( (pix1[0] + pix2[0 + stride]) - (pix2[0] + pix2[0 + stride]) )
        // abs(x) = (x < 0 ? (-x) : (x))

        ld1             {v0.16b}, [x1], x3 // pix1[0]
        ld1             {v1.16b}, [x2], x3 // pix2[0]
        ld1             {v2.16b}, [x5], x3 // pix1[0 + stride]
        ld1             {v3.16b}, [x6], x3 // pix2[0 + stride]

        ld1             {v4.16b}, [x1], x3
        ld1             {v5.16b}, [x2], x3
        ld1             {v6.16b}, [x5], x3
        ld1             {v7.16b}, [x6], x3

        ld1             {v8.16b}, [x1], x3
        ld1             {v9.16b}, [x2], x3
        ld1             {v10.16b}, [x5], x3
        ld1             {v11.16b}, [x6], x3

        ld1             {v12.16b}, [x1], x3
        ld1             {v13.16b}, [x2], x3
        ld1             {v14.16b}, [x5], x3
        ld1             {v15.16b}, [x6], x3

        // first iteration
        usubl           v30.8h, v0.8b, v1.8b
        usubl2          v29.8h, v0.16b, v1.16b
        usubl           v28.8h, v3.8b, v2.8b
        usubl2          v27.8h, v3.16b, v2.16b

        sqadd           v28.8h, v30.8h, v28.8h
        sqadd           v27.8h, v29.8h, v27.8h

        smull           v30.4s, v28.4h, v28.4h
        smull2          v29.4s, v28.8h, v28.8h
        smlal           v30.4s, v27.4h, v27.4h
        smlal2          v29.4s, v27.8h, v27.8h

        saddlv          d17, v30.4s
        add             d18, d18, d17
        saddlv          d17, v29.4s
        add             d18, d18, d17

        // second iteration
        usubl           v26.8h, v4.8b, v5.8b
        usubl2          v25.8h, v4.16b, v5.16b
        usubl           v24.8h, v7.8b, v6.8b
        usubl2          v23.8h, v7.16b, v6.16b

        sqadd           v24.8h, v26.8h, v24.8h
        sqadd           v23.8h, v25.8h, v23.8h

        smull           v26.4s, v24.4h, v24.4h
        smull2          v25.4s, v24.8h, v24.8h
        smlal           v26.4s, v23.4h, v23.4h
        smlal2          v25.4s, v23.8h, v23.8h

        saddlv          d17, v26.4s
        add             d18, d18, d17
        saddlv          d17, v25.4s
        add             d18, d18, d17

        // third iteration
        usubl           v22.8h, v8.8b, v9.8b
        usubl2          v21.8h, v8.16b, v9.16b
        usubl           v20.8h, v11.8b, v10.8b
        usubl2          v19.8h, v11.16b, v10.16b

        sqadd           v20.8h, v22.8h, v20.8h
        sqadd           v19.8h, v21.8h, v19.8h

        smull           v22.4s, v20.4h, v20.4h
        smull2          v21.4s, v20.8h, v20.8h
        smlal           v22.4s, v19.4h, v19.4h
        smlal2          v21.4s, v19.8h, v19.8h

        saddlv          d17, v22.4s
        add             d18, d18, d17
        saddlv          d17, v21.4s
        add             d18, d18, d17

        // fourth iteration
        usubl           v17.8h, v12.8b, v13.8b
        usubl2          v16.8h, v12.16b, v13.16b
        usubl           v30.8h, v15.8b, v14.8b
        usubl2          v29.8h, v15.16b, v14.16b

        sqadd           v17.8h, v17.8h, v30.8h
        sqadd           v16.8h, v16.8h, v29.8h

        smull           v30.4s, v17.4h, v17.4h
        smull2          v29.4s, v17.8h, v17.8h
        smlal           v30.4s, v16.4h, v16.4h
        smlal2          v29.4s, v16.8h, v16.8h

        saddlv          d17, v30.4s
        add             d18, d18, d17
        saddlv          d17, v29.4s
        add             d18, d18, d17

        sub             w4, w4, #4
        cmp             w4, #4
        b.ge            1b

        cbz             w4, 3f

// iterate by once
2:
        cmp             w4, #0
        b.le            3f

        ld1             {v0.16b}, [x1], x3
        ld1             {v1.16b}, [x2], x3
        ld1             {v2.16b}, [x5], x3
        ld1             {v3.16b}, [x6], x3

        usubl           v30.8h, v0.8b, v1.8b
        usubl2          v29.8h, v0.16b, v1.16b
        usubl           v28.8h, v3.8b, v2.8b
        usubl2          v27.8h, v3.16b, v2.16b

        sqadd           v28.8h, v30.8h, v28.8h
        sqadd           v27.8h, v29.8h, v27.8h

        smull           v30.4s, v28.4h, v28.4h
        smull2          v29.4s, v28.8h, v28.8h
        smlal           v30.4s, v27.4h, v27.4h
        smlal2          v29.4s, v27.8h, v27.8h

        saddlv          d17, v30.4s
        add             d18, d18, d17
        saddlv          d17, v29.4s
        add             d18, d18, d17

        subs            w4, w4, #1
        b.ne            2b

3:
        fmov            w0, s18

        ldp             d8, d9, [sp], 0x10
        ldp             d10, d11, [sp], 0x10
        ldp             d12, d13, [sp], 0x10
        ldp             d14, d15, [sp], 0x10

        ret
endfunc

function vsad_intra16_neon, export=1
        // x0           unused
        // x1           uint8_t *pix1
        // x2           uint8_t *dummy
        // x3           ptrdiff_t stride
        // x4           int h

        add             x5, x1, x3 // pix1 + stride
        movi            d18, #0

        sub             w4, w4, #1 // we need to make h-1 iterations
        cmp             w4, #4
        b.lt            2f

// make 4 iterations at once
1:
        // v = abs( pix1[0] - pix1[0 + stride] )
        // score = sum(v)
        // abs(x) = ( (x > 0) ? (x) : (-x) )
        ld1             {v0.16b}, [x1], x3
        ld1             {v1.16b}, [x5], x3

        ld1             {v2.16b}, [x1], x3
        ld1             {v3.16b}, [x5], x3

        ld1             {v4.16b}, [x1], x3
        ld1             {v5.16b}, [x5], x3

        ld1             {v6.16b}, [x1], x3
        ld1             {v7.16b}, [x5], x3

        uabd            v30.16b, v0.16b, v1.16b
        uaddlv          h19, v30.16b
        add             d18, d18, d19

        uabd            v29.16b, v2.16b, v3.16b
        uaddlv          h20, v29.16b
        add             d18, d18, d20

        uabd            v28.16b, v4.16b, v5.16b
        uaddlv          h21, v28.16b
        add             d18, d18, d21

        uabd            v27.16b, v6.16b, v7.16b
        uaddlv          h22, v27.16b
        add             d18, d18, d22

        sub             w4, w4, #4
        cmp             w4, #4
        b.ge            1b
        cbnz            w4, 2f

        fmov            w0, s18

        ret

// iterate by one
2:
        ld1             {v0.16b}, [x1], x3
        ld1             {v1.16b}, [x5], x3

        uabd            v30.16b, v0.16b, v1.16b
        uaddlv          h17, v30.16b
        add             d18, d18, d17

        subs            w4, w4, #1
        cbnz            w4, 2b
        fmov            w0, s18

        ret

endfunc

function vsse_intra16_neon, export=1
        // x0           unused
        // x1           uint8_t *pix1
        // x2           uint8_t *dummy
        // x3           ptrdiff_t stride
        // x4           int h

        add             x5, x1, x3 // pix1 + stride
        movi            d18, #0

        sub             w4, w4, #1 // we need to make h-1 iterations
        cmp             w4, #4
        b.lt            2f

// make 4 iterations at once
1:
        // v = abs( pix1[0] - pix1[0 + stride] )
        // score = sum( v * v )
        // abs(x) = ( (x > 0) ? (x) : (-x) )
        ld1             {v0.16b}, [x1], x3
        ld1             {v1.16b}, [x5], x3

        ld1             {v2.16b}, [x1], x3
        ld1             {v3.16b}, [x5], x3

        ld1             {v4.16b}, [x1], x3
        ld1             {v5.16b}, [x5], x3

        ld1             {v6.16b}, [x1], x3
        ld1             {v7.16b}, [x5], x3

        uabdl           v30.8h, v0.8b, v1.8b
        uabdl2          v29.8h, v0.16b, v1.16b
        mul             v30.8h, v30.8h, v30.8h
        mul             v29.8h, v29.8h, v29.8h
        uaddlv          s19, v30.8h
        add             d18, d18, d19
        uaddlv          s19, v29.8h
        add             d18, d18, d19

        uabdl           v28.8h, v2.8b, v3.8b
        uabdl2          v27.8h, v2.16b, v3.16b
        mul             v28.8h, v28.8h, v28.8h
        mul             v27.8h, v27.8h, v27.8h
        uaddlv          s20, v28.8h
        add             d18, d18, d20
        uaddlv          s20, v27.8h
        add             d18, d18, d20

        uabdl           v26.8h, v4.8b, v5.8b
        uabdl2          v25.8h, v4.16b, v5.16b
        mul             v26.8h, v26.8h, v26.8h
        mul             v25.8h, v25.8h, v25.8h
        uaddlv          s21, v26.8h
        add             d18, d18, d21
        uaddlv          s21, v25.8h
        add             d18, d18, d21

        uabdl           v24.8h, v6.8b, v7.8b
        uabdl2          v23.8h, v6.16b, v7.16b
        mul             v24.8h, v24.8h, v24.8h
        mul             v23.8h, v23.8h, v23.8h
        uaddlv          s22, v24.8h
        add             d18, d18, d22
        uaddlv          s22, v23.8h
        add             d18, d18, d22

        sub             w4, w4, #4
        cmp             w4, #4
        b.ge            1b
        cbnz            w4, 2f

        fmov            w0, s18

        ret

// iterate by one
2:
        ld1             {v0.16b}, [x1], x3
        ld1             {v1.16b}, [x5], x3

        uabdl           v30.8h, v0.8b, v1.8b
        uabdl2          v29.8h, v0.16b, v1.16b
        mul             v30.8h, v30.8h, v30.8h
        mul             v29.8h, v29.8h, v29.8h
        uaddlv          s17, v30.8h
        add             d18, d18, d17
        uaddlv          s17, v29.8h
        add             d18, d18, d17

        subs            w4, w4, #1
        cbnz            w4, 2b
        fmov            w0, s18

        ret

endfunc

function nsse16_neon, export=1
        // x0           multiplier
        // x1           uint8_t *pix1
        // x2           uint8_t *pix2
        // x3           ptrdiff_t stride
        // x4           int h

        stp             d8, d9, [sp, #-0x10]!
        stp             d10, d11, [sp, #-0x10]!
        stp             d12, d13, [sp, #-0x10]!
        stp             d14, d15, [sp, #-0x10]!

        str             x0, [sp, #-0x10]!
        stp             x1, x2, [sp, #-0x10]!
        stp             x3, x4, [sp, #-0x10]!
        str             lr, [sp, #-0x10]!
        bl              sse16_neon
        ldr             lr, [sp], #0x10
        mov             w9, w0 /// here we store score1
        ldp             x3, x4, [sp], #0x10
        ldp             x1, x2, [sp], #0x10
        ldr             x5, [sp], #0x10

        movi            v16.8h, #0
        mov             x10, x1         // x1
        add             x11, x1, x3     // x1 + stride
        add             x12, x1, #1      // x1 + 1
        add             x13, x11, #1     // x1 + stride + 1

        mov             x14, x2         // x2
        add             x15, x2, x3     // x2 + stride
        add             x16, x2, #1      // x2 + 1
        add             x17, x15, #1     // x2 + stride + 1

        subs            w4, w4, #1 /// we need to make h-1 iterations
        cmp             w4, #2
        b.lt            2f

// make 4 iterations at once
1:
        ld1             {v0.16b}, [x10], x3
        ld1             {v1.16b}, [x11], x3
        ld1             {v2.16b}, [x12], x3
        ld1             {v3.16b}, [x13], x3
        ld1             {v4.16b}, [x14], x3
        ld1             {v5.16b}, [x15], x3
        ld1             {v6.16b}, [x16], x3
        ld1             {v7.16b}, [x17], x3

        ld1             {v8.16b}, [x10], x3
        ld1             {v9.16b}, [x11], x3
        ld1             {v10.16b}, [x12], x3
        ld1             {v11.16b}, [x13], x3
        ld1             {v12.16b}, [x14], x3
        ld1             {v13.16b}, [x15], x3
        ld1             {v14.16b}, [x16], x3
        ld1             {v15.16b}, [x17], x3

        usubl           v30.8h, v0.8b, v1.8b
        usubl2          v29.8h, v0.16b, v1.16b
        usubl           v28.8h, v3.8b, v2.8b
        usubl2          v27.8h, v3.16b, v2.16b

        sqadd           v30.8h, v30.8h, v28.8h
        sqadd           v29.8h, v29.8h, v27.8h
        sqabs           v30.8h, v30.8h
        sqabs           v29.8h, v29.8h

        usubl           v28.8h, v4.8b, v5.8b
        usubl2          v27.8h, v4.16b, v5.16b
        usubl           v26.8h, v7.8b, v6.8b
        usubl2          v25.8h, v7.16b, v6.16b

        sqadd           v28.8h, v28.8h, v26.8h
        sqadd           v27.8h, v27.8h, v25.8h
        sqabs           v28.8h, v28.8h
        sqabs           v27.8h, v27.8h

        sqsub           v30.8h, v30.8h, v28.8h
        sqsub           v29.8h, v29.8h, v27.8h

        ins             v29.h[7], wzr

        saddlv          s17, v30.8h
        sqadd           d16, d16, d17
        saddlv          s17, v29.8h
        sqadd           d16, d16, d17 // first iteration ends here

        usubl           v24.8h, v8.8b, v9.8b
        usubl2          v23.8h, v8.16b, v9.16b
        usubl           v22.8h, v11.8b, v10.8b
        usubl2          v21.8h, v11.16b, v10.16b

        sqadd           v24.8h, v24.8h, v22.8h
        sqadd           v23.8h, v23.8h, v21.8h
        sqabs           v24.8h, v24.8h
        sqabs           v23.8h, v23.8h

        usubl           v22.8h, v12.8b, v13.8b
        usubl2          v21.8h, v12.16b, v13.16b
        usubl           v20.8h, v15.8b, v14.8b
        usubl2          v19.8h, v15.16b, v14.16b

        sqadd           v22.8h, v22.8h, v20.8h
        sqadd           v21.8h, v21.8h, v19.8h
        sqabs           v22.8h, v22.8h
        sqabs           v21.8h, v21.8h

        sqsub           v24.8h, v24.8h, v22.8h
        sqsub           v23.8h, v23.8h, v21.8h

        ins             v23.h[7], wzr

        saddlv          s17, v24.8h
        add             d16, d16, d17
        saddlv          s17, v23.8h
        add             d16, d16, d17 /// in d16 we store score2

        sub             w4, w4, #2
        cmp             w4, #2
        b.ge            1b
        cbz             w4, 3f

// iterate by one
2:

        ld1             {v0.16b}, [x10], x3
        ld1             {v1.16b}, [x11], x3
        ld1             {v2.16b}, [x12], x3
        ld1             {v3.16b}, [x13], x3
        ld1             {v4.16b}, [x14], x3
        ld1             {v5.16b}, [x15], x3
        ld1             {v6.16b}, [x16], x3
        ld1             {v7.16b}, [x17], x3

        usubl           v30.8h, v0.8b, v1.8b
        usubl2          v29.8h, v0.16b, v1.16b
        usubl           v28.8h, v3.8b, v2.8b
        usubl2          v27.8h, v3.16b, v2.16b

        sqadd           v30.8h, v30.8h, v28.8h
        sqadd           v29.8h, v29.8h, v27.8h
        sqabs           v30.8h, v30.8h
        sqabs           v29.8h, v29.8h

        usubl           v28.8h, v4.8b, v5.8b
        usubl2          v27.8h, v4.16b, v5.16b
        usubl           v26.8h, v7.8b, v6.8b
        usubl2          v25.8h, v7.16b, v6.16b

        sqadd           v28.8h, v28.8h, v26.8h
        sqadd           v27.8h, v27.8h, v25.8h
        sqabs           v28.8h, v28.8h
        sqabs           v27.8h, v27.8h

        sqsub           v30.8h, v30.8h, v28.8h
        sqsub           v29.8h, v29.8h, v27.8h

        ins             v29.h[7], wzr

        saddlv          s17, v30.8h
        add             d16, d16, d17
        saddlv          s17, v29.8h
        add             d16, d16, d17 // first iteration ends here

        subs            w4, w4, #1
        cbnz            w4, 2b

3:
        sqabs           s16, s16
        fmov            w0, s16

        mul             w0, w0, w5
        add             w0, w0, w9

        ldp             d14, d15, [sp], #0x10
        ldp             d12, d13, [sp], #0x10
        ldp             d10, d11, [sp], #0x10
        ldp             d8, d9, [sp], #0x10

        ret
endfunc
