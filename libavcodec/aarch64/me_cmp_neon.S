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

function hadamard8_diff8x8_neon, export=1
        // x0 - unused
        // x1 - uint8_t *dst
        // x2 - uint8_t *src
        // x3 - ptrdiff_t stride
        // x4 - int h

        cmp             w4, #8
        b.ne            2f

        stp             d8, d9, [sp, #-0x10]!
        stp             d10, d11, [sp, #-0x10]!
        stp             d12, d13, [sp, #-0x10]!
        stp             d14, d15, [sp, #-0x10]!

        // We need to load src and dst into vectors, 8 vectors for each

        // Initialize vectors for src
        ld1             {v8.8b}, [x1], x3
        ld1             {v9.8b}, [x1], x3
        ld1             {v10.8b}, [x1], x3
        ld1             {v11.8b}, [x1], x3
        ld1             {v12.8b}, [x1], x3
        ld1             {v13.8b}, [x1], x3
        ld1             {v14.8b}, [x1], x3
        ld1             {v15.8b}, [x1], x3

        trn1            v30.8b, v8.8b, v8.8b
        trn2            v29.8b, v8.8b, v8.8b
        uaddl           v8.8h, v30.8b, v29.8b
        usubl           v30.8h, v30.8b, v29.8b
        uzp1            v8.8h, v8.8h, v8.8h
        uzp2            v30.8h, v30.8h, v30.8h
        zip1            v29.8h, v8.8h, v30.8h
        zip2            v29.8h, v8.8h, v30.8h

        trn1            v28.8b, v9.8b, v9.8b
        trn2            v27.8b, v9.8b, v9.8b
        uaddl           v9.8h, v28.8b, v27.8b
        usubl           v28.8h, v28.8b, v27.8b
        uzp1            v9.8h, v9.8h, v9.8h
        uzp2            v28.8h, v28.8h, v28.8h
        zip1            v27.8h, v9.8h, v28.8h
        zip2            v27.8h, v9.8h, v28.8h

        trn1            v26.8b, v10.8b, v10.8b
        trn2            v25.8b, v10.8b, v10.8b
        uaddl           v10.8h, v26.8b, v25.8b
        usubl           v26.8h, v26.8b, v25.8b
        uzp1            v10.8h, v10.8h, v10.8h
        uzp2            v26.8h, v26.8h, v26.8h
        zip1            v25.8h, v10.8h, v26.8h
        zip2            v25.8h, v10.8h, v26.8h

        trn1            v24.8b, v11.8b, v11.8b
        trn2            v31.8b, v11.8b, v11.8b
        uaddl           v11.8h, v24.8b, v31.8b
        usubl           v24.8h, v24.8b, v31.8b
        uzp1            v11.8h, v11.8h, v11.8h
        uzp2            v24.8h, v24.8h, v24.8h
        zip1            v31.8h, v11.8h, v24.8h
        zip2            v31.8h, v11.8h, v24.8h

        trn1            v0.8b, v12.8b, v12.8b
        trn2            v1.8b, v12.8b, v12.8b
        uaddl           v12.8h, v0.8b, v1.8b
        usubl           v0.8h, v0.8b, v1.8b
        uzp1            v12.8h, v12.8h, v12.8h
        uzp2            v0.8h, v0.8h, v0.8h
        zip1            v1.8h, v12.8h, v0.8h
        zip2            v1.8h, v12.8h, v0.8h

        trn1            v2.8b, v13.8b, v13.8b
        trn2            v3.8b, v13.8b, v13.8b
        uaddl           v13.8h, v2.8b, v3.8b
        usubl           v2.8h, v2.8b, v3.8b
        uzp1            v13.8h, v13.8h, v13.8h
        uzp2            v2.8h, v2.8h, v2.8h
        zip1            v3.8h, v13.8h, v2.8h
        zip2            v3.8h, v13.8h, v2.8h

        trn1            v4.8b, v14.8b, v14.8b
        trn2            v5.8b, v14.8b, v14.8b
        uaddl           v14.8h, v4.8b, v5.8b
        usubl           v4.8h, v4.8b, v5.8b
        uzp1            v14.8h, v14.8h, v14.8h
        uzp2            v4.8h, v4.8h, v4.8h
        zip1            v5.8h, v14.8h, v4.8h
        zip2            v5.8h, v14.8h, v4.8h

        trn1            v6.8b, v15.8b, v15.8b
        trn2            v7.8b, v15.8b, v15.8b
        uaddl           v15.8h, v6.8b, v7.8b
        usubl           v6.8h, v6.8b, v7.8b
        uzp1            v15.8h, v15.8h, v15.8h
        uzp2            v6.8h, v6.8h, v6.8h
        zip1            v7.8h, v15.8h, v6.8h
        zip2            v7.8h, v15.8h, v6.8h

        // BUTTERFLY2 is calculated and stored in:
        // v29, v27, v25, v31, v1, v3, v5, v7

        // v29 under work with BUTTERFLY1, user registers: v30, v29, v16, v10, v8

        uzp1            v30.8h, v29.8h, v29.8h // ac eg ac eg
        zip1            v8.8h, v30.8h, v30.8h //  aa cc ee gg
        uzp1            v16.4s, v8.4s, v8.4s //   aa ee aa ee <- first vector
        uzp2            v10.4s, v8.4s, v8.4s //   cc gg cc gg <-- second vector

        uzp2            v30.8h, v29.8h, v29.8h // bd fh bd fh
        zip1            v29.8h, v30.8h, v30.8h // bb dd ff hh
        uzp1            v30.4s, v29.4s, v29.4s // bb ff bb ff <-- third vector
        uzp2            v29.4s, v29.4s, v29.4s // dd hh dd hh <-- fourth vector

        sqadd           v8.8h, v16.8h, v10.8h //  a+c a+c e+g e+g ...
        sqsub           v16.8h, v16.8h, v10.8h // a-c a-c e-g e-g ...

        sqadd           v10.8h, v30.8h, v29.8h // b+d b+d f+h f+h ...
        sqsub           v30.8h, v30.8h, v29.8h // b-d b-d f-h f-h ...

        trn1            v16.8h, v16.8h, v8.8h //  a+c a-c a+c a-c e+g e-g e+g e-g
        trn1            v8.8h, v30.8h, v10.8h //  b+d b-d b+d b-d f+h f-h f+h f-h
        rev32           v16.8h, v16.8h
        rev32           v8.8h, v8.8h

        zip1            v29.8h, v16.8h, v8.8h
        zip2            v29.8h, v16.8h, v8.8h // a+c b+d a-c b-d e+g f+h e-g f-h
        // BUTTERFLY1 is now calculated

        // v27 under work with BUTTERFLY1, use registers: v28, v27, v9, v17, v23
        uzp1            v28.8h, v27.8h, v27.8h // ac eg ac eg
        zip1            v9.8h, v28.8h, v28.8h //  aa cc ee gg
        uzp1            v17.4s, v9.4s, v9.4s //   aa ee aa ee <- first vector
        uzp2            v23.4s, v9.4s, v9.4s //   cc gg cc gg <-- second vector

        uzp2            v28.8h, v27.8h, v27.8h // bd fh bd fh
        zip1            v27.8h, v28.8h, v28.8h // bb dd ff hh
        uzp1            v28.4s, v27.4s, v27.4s // bb ff bb ff <-- third vector
        uzp2            v27.4s, v27.4s, v27.4s // dd hh dd hh <-- fourth vector

        sqadd           v9.8h, v17.8h, v23.8h //  a+c a+c e+g e+g ...
        sqsub           v17.8h, v17.8h, v23.8h // a-c a-c e-g e-g ...

        sqadd           v23.8h, v28.8h, v27.8h // b+d b+d f+h f+h ...
        sqsub           v28.8h, v28.8h, v27.8h // b-d b-d f-h f-h ...

        trn1            v17.8h, v17.8h, v9.8h //  a+c a-c a+c a-c e+g e-g e+g e-g
        trn1            v9.8h, v28.8h, v23.8h //  b+d b-d b+d b-d f+h f-h f+h f-h
        rev32           v17.8h, v17.8h
        rev32           v9.8h, v9.8h

        zip1            v27.8h, v17.8h, v9.8h
        zip2            v27.8h, v17.8h, v9.8h // a+c b+d a-c b-d e+g f+h e-g f-h

        // v25 under work with BUTTERFLY1, use registers: v10, v18, v26, v25, v15
        uzp1            v26.8h, v25.8h, v25.8h // ac eg ac eg
        zip1            v10.8h, v26.8h, v26.8h //  aa cc ee gg
        uzp1            v18.4s, v10.4s, v10.4s //   aa ee aa ee <- first vector
        uzp2            v15.4s, v10.4s, v10.4s //   cc gg cc gg <-- second vector

        uzp2            v26.8h, v25.8h, v25.8h // bd fh bd fh
        zip1            v25.8h, v26.8h, v26.8h // bb dd ff hh
        uzp1            v26.4s, v25.4s, v25.4s // bb ff bb ff <-- third vector
        uzp2            v25.4s, v25.4s, v25.4s // dd hh dd hh <-- fourth vector

        sqadd           v10.8h, v18.8h, v15.8h //  a+c a+c e+g e+g ...
        sqsub           v18.8h, v18.8h, v15.8h // a-c a-c e-g e-g ...

        sqadd           v15.8h, v26.8h, v25.8h // b+d b+d f+h f+h ...
        sqsub           v26.8h, v26.8h, v25.8h // b-d b-d f-h f-h ...

        trn1            v18.8h, v18.8h, v10.8h //  a+c a-c a+c a-c e+g e-g e+g e-g
        trn1            v10.8h, v26.8h, v15.8h //  b+d b-d b+d b-d f+h f-h f+h f-h
        rev32           v18.8h, v18.8h
        rev32           v10.8h, v10.8h

        zip1            v25.8h, v18.8h, v10.8h
        zip2            v25.8h, v18.8h, v10.8h // a+c b+d a-c b-d e+g f+h e-g f-h

        // v31 under work with BUTTERFLY1, use registers: v31, v11, v19, v24
        uzp1            v24.8h, v31.8h, v31.8h // ac eg ac eg
        zip1            v11.8h, v24.8h, v24.8h //  aa cc ee gg
        uzp1            v19.4s, v11.4s, v11.4s //   aa ee aa ee <- first vector
        uzp2            v6.4s, v11.4s, v11.4s //   cc gg cc gg <-- second vector

        uzp2            v24.8h, v31.8h, v31.8h // bd fh bd fh
        zip1            v31.8h, v24.8h, v24.8h // bb dd ff hh
        uzp1            v24.4s, v31.4s, v31.4s // bb ff bb ff <-- third vector
        uzp2            v31.4s, v31.4s, v31.4s // dd hh dd hh <-- fourth vector

        sqadd           v11.8h, v19.8h, v6.8h //  a+c a+c e+g e+g ...
        sqsub           v19.8h, v19.8h, v6.8h // a-c a-c e-g e-g ...

        sqadd           v6.8h, v24.8h, v31.8h // b+d b+d f+h f+h ...
        sqsub           v24.8h, v24.8h, v31.8h // b-d b-d f-h f-h ...

        trn1            v19.8h, v19.8h, v11.8h //  a+c a-c a+c a-c e+g e-g e+g e-g
        trn1            v11.8h, v24.8h, v6.8h //  b+d b-d b+d b-d f+h f-h f+h f-h
        rev32           v19.8h, v19.8h
        rev32           v11.8h, v11.8h

        zip1            v31.8h, v19.8h, v11.8h
        zip2            v31.8h, v19.8h, v11.8h // a+c b+d a-c b-d e+g f+h e-g f-h

        // v1 in BUTTERFLY1, use registers: v12, v20, v0, v1
        uzp1            v14.8h, v1.8h, v1.8h // ac eg ac eg
        zip1            v12.8h, v14.8h, v14.8h //  aa cc ee gg
        uzp1            v0.4s, v12.4s, v12.4s //   aa ee aa ee <- first vector
        uzp2            v6.4s, v12.4s, v12.4s //   cc gg cc gg <-- second vector

        uzp2            v14.8h, v1.8h, v1.8h // bd fh bd fh
        zip1            v1.8h, v14.8h, v14.8h // bb dd ff hh
        uzp1            v14.4s, v1.4s, v1.4s // bb ff bb ff <-- third vector
        uzp2            v1.4s, v1.4s, v1.4s // dd hh dd hh <-- fourth vector

        sqadd           v12.8h, v0.8h, v6.8h //  a+c a+c e+g e+g ...
        sqsub           v0.8h, v0.8h, v6.8h // a-c a-c e-g e-g ...

        sqadd           v6.8h, v14.8h, v1.8h // b+d b+d f+h f+h ...
        sqsub           v14.8h, v14.8h, v1.8h // b-d b-d f-h f-h ...

        trn1            v0.8h, v0.8h, v12.8h //  a+c a-c a+c a-c e+g e-g e+g e-g
        trn1            v12.8h, v14.8h, v6.8h //  b+d b-d b+d b-d f+h f-h f+h f-h
        rev32           v0.8h, v0.8h
        rev32           v12.8h, v12.8h

        zip1            v1.8h, v0.8h, v12.8h
        zip2            v1.8h, v0.8h, v12.8h // a+c b+d a-c b-d e+g f+h e-g f-h

        // v3 in BUTTERFLY1, use registers: v13, v3, v21, v2
        uzp1            v13.8h, v3.8h, v3.8h // ac eg ac eg
        zip1            v2.8h, v13.8h, v13.8h //  aa cc ee gg
        uzp1            v21.4s, v2.4s, v2.4s //   aa ee aa ee <- first vector
        uzp2            v28.4s, v2.4s, v2.4s //   cc gg cc gg <-- second vector

        uzp2            v13.8h, v3.8h, v3.8h // bd fh bd fh
        zip1            v3.8h, v13.8h, v13.8h // bb dd ff hh
        uzp1            v13.4s, v3.4s, v3.4s // bb ff bb ff <-- third vector
        uzp2            v3.4s, v3.4s, v3.4s // dd hh dd hh <-- fourth vector

        sqadd           v2.8h, v21.8h, v28.8h //  a+c a+c e+g e+g ...
        sqsub           v21.8h, v21.8h, v28.8h // a-c a-c e-g e-g ...

        sqadd           v28.8h, v13.8h, v3.8h // b+d b+d f+h f+h ...
        sqsub           v13.8h, v13.8h, v3.8h // b-d b-d f-h f-h ...

        trn1            v21.8h, v21.8h, v2.8h //  a+c a-c a+c a-c e+g e-g e+g e-g
        trn1            v2.8h, v13.8h, v28.8h //  b+d b-d b+d b-d f+h f-h f+h f-h
        rev32           v21.8h, v21.8h
        rev32           v2.8h, v2.8h

        zip1            v3.8h, v21.8h, v2.8h
        zip2            v3.8h, v21.8h, v2.8h // a+c b+d a-c b-d e+g f+h e-g f-h

        // v5 in BUTTERFLY1, use registers: v14, v22, v4, v5, v26
        uzp1            v4.8h, v5.8h, v5.8h // ac eg ac eg
        zip1            v14.8h, v4.8h, v4.8h //  aa cc ee gg
        uzp1            v22.4s, v14.4s, v14.4s //   aa ee aa ee <- first vector
        uzp2            v26.4s, v14.4s, v14.4s //   cc gg cc gg <-- second vector

        uzp2            v4.8h, v5.8h, v5.8h // bd fh bd fh
        zip1            v5.8h, v4.8h, v4.8h // bb dd ff hh
        uzp1            v4.4s, v5.4s, v5.4s // bb ff bb ff <-- third vector
        uzp2            v5.4s, v5.4s, v5.4s // dd hh dd hh <-- fourth vector

        sqadd           v14.8h, v22.8h, v26.8h //  a+c a+c e+g e+g ...
        sqsub           v22.8h, v22.8h, v26.8h // a-c a-c e-g e-g ...

        sqadd           v26.8h, v4.8h, v5.8h // b+d b+d f+h f+h ...
        sqsub           v4.8h, v4.8h, v5.8h // b-d b-d f-h f-h ...

        trn1            v22.8h, v22.8h, v14.8h //  a+c a-c a+c a-c e+g e-g e+g e-g
        trn1            v14.8h, v4.8h, v26.8h //  b+d b-d b+d b-d f+h f-h f+h f-h
        rev32           v22.8h, v22.8h
        rev32           v14.8h, v14.8h

        zip1            v5.8h, v22.8h, v14.8h
        zip2            v5.8h, v22.8h, v14.8h // a+c b+d a-c b-d e+g f+h e-g f-h

        // v7 in BUTTERFLY1, use registers: v15, v23, v6, v7
        uzp1            v11.8h, v7.8h, v7.8h // ac eg ac eg
        zip1            v15.8h, v11.8h, v11.8h //  aa cc ee gg
        uzp1            v22.4s, v15.4s, v15.4s //   aa ee aa ee <- first vector
        uzp2            v23.4s, v15.4s, v15.4s //   cc gg cc gg <-- second vector

        uzp2            v11.8h, v7.8h, v7.8h // bd fh bd fh
        zip1            v7.8h, v11.8h, v11.8h // bb dd ff hh
        uzp1            v11.4s, v7.4s, v7.4s // bb ff bb ff <-- third vector
        uzp2            v7.4s, v7.4s, v7.4s // dd hh dd hh <-- fourth vector

        sqadd           v15.8h, v22.8h, v23.8h //  a+c a+c e+g e+g ...
        sqsub           v22.8h, v22.8h, v23.8h // a-c a-c e-g e-g ...

        sqadd           v23.8h, v11.8h, v7.8h // b+d b+d f+h f+h ...
        sqsub           v11.8h, v11.8h, v7.8h // b-d b-d f-h f-h ...

        trn1            v22.8h, v22.8h, v15.8h //  a+c a-c a+c a-c e+g e-g e+g e-g
        trn1            v15.8h, v11.8h, v23.8h //  b+d b-d b+d b-d f+h f-h f+h f-h
        rev32           v22.8h, v22.8h
        rev32           v15.8h, v15.8h

        zip1            v7.8h, v22.8h, v15.8h
        zip2            v7.8h, v22.8h, v15.8h // a+c b+d a-c b-d e+g f+h e-g f-h

        // BUTTERFLY1 ops are finished and stored in:
        // v29, v27, v25, v31, v1, v3, v5, v7

        // Next round of BUTTERFLY1 operations...

        // v29 under work with BUTTERFLY1, user registers: v30, v29, v16, v8
        zip1            v30.8h, v29.8h, v29.8h // aa bb cc dd
        zip2            v16.8h, v29.8h, v29.8h // ee ff gg hh
        sqadd           v8.8h, v30.8h, v16.8h //  a+e a+e b+f b+f c+g c+g d+h d+h
        sqsub           v30.8h, v30.8h, v16.8h // a-e a-e b-f b-f c-g c-g d-h d-h
        uzp1            v8.8h, v8.8h, v8.8h    // a+e b+f c+g d+h ...
        uzp2            v30.8h, v30.8h, v30.8h // a-e b-f c-g d-h ...
        ext             v29.16b, v8.16b, v30.16b, #8 // a+e b+f c+g d+h a-e b-f c-g d-h
        // BUTTERFLY1 is now calculated

        // v27 under work with BUTTERFLY1, use registers: v28, v27, v9, v17
        zip1            v28.8h, v27.8h, v27.8h // aa bb cc dd
        zip2            v9.8h, v27.8h, v27.8h // ee ff gg hh
        sqadd           v17.8h, v28.8h, v9.8h
        sqsub           v28.8h, v28.8h, v9.8h
        uzp1            v17.8h, v17.8h, v17.8h
        uzp2            v28.8h, v28.8h, v28.8h
        zip2            v27.8h, v9.8h, v17.8h
        ext             v27.16b, v17.16b, v28.16b, #8

        // v25 under work with BUTTERFLY1, use registers: v10, v18, v26, v25
        zip1            v26.8h, v25.8h, v25.8h // aa bb cc dd
        zip2            v10.8h, v25.8h, v25.8h // ee ff gg hh
        sqadd           v18.8h, v26.8h, v10.8h
        sqsub           v26.8h, v26.8h, v10.8h
        uzp1            v18.8h, v18.8h, v18.8h
        uzp2            v26.8h, v26.8h, v26.8h
        zip2            v25.8h, v10.8h, v18.8h
        ext             v25.16b, v18.16b, v26.16b, #8

        // v31 under work with BUTTERFLY1, use registers: v31, v11, v19, v24
        zip1            v24.8h, v31.8h, v31.8h // aa bb cc dd
        zip2            v11.8h, v31.8h, v31.8h // ee ff gg hh
        sqadd           v19.8h, v24.8h, v11.8h
        sqsub           v24.8h, v24.8h, v11.8h
        uzp1            v19.8h, v19.8h, v19.8h
        uzp2            v24.8h, v24.8h, v24.8h
        zip2            v31.8h, v11.8h, v19.8h
        ext             v31.16b, v19.16b, v24.16b, #8

        // v1 in BUTTERFLY1, use registers: v12, v20, v0, v1
        zip1            v20.8h, v1.8h, v1.8h // aa bb cc dd
        zip2            v12.8h, v1.8h, v1.8h // ee ff gg hh
        sqadd           v0.8h, v20.8h, v12.8h
        sqsub           v20.8h, v20.8h, v12.8h
        uzp1            v0.8h, v0.8h, v0.8h
        uzp2            v20.8h, v20.8h, v20.8h
        zip2            v1.8h, v12.8h, v0.8h
        ext             v1.16b, v0.16b, v20.16b, #8

        // v3 in BUTTERFLY1, use registers: v13, v3, v21, v2
        zip1            v21.8h, v3.8h, v3.8h // aa bb cc dd
        zip2            v13.8h, v3.8h, v3.8h // ee ff gg hh
        sqadd           v2.8h, v21.8h, v13.8h
        sqsub           v21.8h, v21.8h, v13.8h
        uzp1            v2.8h, v2.8h, v2.8h
        uzp2            v21.8h, v21.8h, v21.8h
        zip2            v3.8h, v13.8h, v2.8h
        ext             v3.16b, v2.16b, v21.16b, #8

        // v5 in BUTTERFLY1, use registers: v14, v22, v4, v5
        zip1            v22.8h, v5.8h, v5.8h // aa bb cc dd
        zip2            v14.8h, v5.8h, v5.8h // ee ff gg hh
        sqadd           v4.8h, v22.8h, v14.8h
        sqsub           v22.8h, v22.8h, v14.8h
        uzp1            v4.8h, v4.8h, v4.8h
        uzp2            v22.8h, v22.8h, v22.8h
        zip2            v5.8h, v14.8h, v4.8h
        ext             v5.16b, v4.16b, v22.16b, #8

        // v7 in BUTTERFLY1, use registers: v15, v23, v6, v7
        zip1            v23.8h, v7.8h, v7.8h // aa bb cc dd
        zip2            v15.8h, v7.8h, v7.8h // ee ff gg hh
        sqadd           v6.8h, v23.8h, v15.8h
        sqsub           v23.8h, v23.8h, v15.8h
        uzp1            v6.8h, v6.8h, v6.8h
        uzp2            v23.8h, v23.8h, v23.8h
        zip2            v7.8h, v15.8h, v6.8h
        ext             v7.16b, v6.16b, v23.16b, #8

        // BUTTERFLY1 ops are finished and stored in:
        // v29, v27, v25, v31, v1, v3, v5, v7

        // Now, expand next 'for loop'
        // Do first round of BUTTERFLY1 ops

        // v29 and v27 as args for BUTTERFLY1, tmp reg: v30
        mov             v30.16b, v29.16b
        add             v29.8h, v29.8h, v27.8h
        sub             v27.8h, v30.8h, v27.8h

        // v25 and v31 as args for BUTTERFLY1, tmp reg: v28
        mov             v28.16b, v25.16b
        add             v25.8h, v25.8h, v31.8h
        sub             v31.8h, v28.8h, v31.8h

        // v1 and v3 as args for BUTTERFLY1, tmp reg: v26
        mov             v26.16b, v1.16b
        add             v1.8h, v1.8h, v3.8h
        sub             v3.8h, v26.8h, v3.8h

        // v5 and v7 as args for BUTTERFLY1, tmp reg: v24
        mov             v24.16b, v5.16b
        add             v5.8h, v5.8h, v7.8h
        sub             v7.8h, v24.8h, v7.8h

        // Do second round of BUTTERFLY1 ops

        // v29 and v25 as args for BUTTERFLY1, tmp reg: v30
        mov             v30.16b, v29.16b
        add             v29.8h, v29.8h, v25.8h
        sub             v25.8h, v30.8h, v25.8h

        // v27 and v31 as args for BUTTERFLY1, tmp reg: v28
        mov             v28.16b, v27.16b
        add             v27.8h, v27.8h, v31.8h
        sub             v31.8h, v28.8h, v31.8h

        // v1 and v5 as args for BUTTERFLY1, tmp reg: v26
        mov             v26.16b, v1.16b
        add             v1.8h, v1.8h, v5.8h
        sub             v5.8h, v26.8h, v5.8h

        // v3 and v7 as args for BUTTERFLY1, tmp reg: v24
        mov             v24.16b, v3.16b
        add             v3.8h, v3.8h, v7.8h
        sub             v7.8h, v24.8h, v7.8h

        // Now calculate sum with BUTTERFLYA

        movi             d0, #0

        // v29 and v1 as args for BUTTERFLYA, tmp regs: v30, v28
        sqadd           v30.8h, v29.8h, v1.8h
        sqabs           v30.8h, v30.8h
        sabd            v2.8h, v29.8h, v1.8h
        uaddlv          s30, v30.8h
        uaddlv          s28, v2.8h
        add             d0, d0, d30
        add             d0, d0, d28

        // v27 and v3 as args for BUTTERFLYA, tmp regs: v26, v24
        sqadd           v26.8h, v27.8h, v3.8h
        sqabs           v26.8h, v26.8h
        sabd            v24.8h, v27.8h, v3.8h
        uaddlv          s26, v26.8h
        uaddlv          s24, v24.8h
        add             d0, d0, d26
        add             d0, d0, d24

        // v25 and v5 as args for BUTTERFLYA, tmp regs: v22, v20
        sqadd           v22.8h, v25.8h, v5.8h
        sqabs           v22.8h, v22.8h
        sabd            v20.8h, v25.8h, v5.8h
        uaddlv          s22, v22.8h
        uaddlv          s20, v20.8h
        add             d0, d0, d22
        add             d0, d0, d20

        // v31 and v7 as args for BUTTERFLYA, tmp regs: v18, v16
        sqadd           v18.8h, v31.8h, v7.8h
        sqabs           v18.8h, v18.8h
        sabd            v16.8h, v31.8h, v7.8h
        uaddlv          s18, v18.8h
        uaddlv          s16, v16.8h
        add             d0, d0, d18
        add             d0, d0, d16

        // sub mean from overall sum
        mov             h4, v29.h[0]
        mov             h5, v1.h[0]

        add             d4, d4, d5
        abs             d4, d4

        sub             d0, d0, d4

2:
        fmov            w0, s0

        ldp             d14, d15, [sp], #0x10
        ldp             d12, d13, [sp], #0x10
        ldp             d10, d11, [sp], #0x10
        ldp             d8, d9, [sp], #0x10

        ret
endfunc

function pix_median_abs16_neon, export=1
        // x0           unused
        // x1           uint8_t *pix1
        // x2           uint8_t *pix2
        // x3           ptrdiff_t stride
        // w4           int h

        stp             d14, d15, [sp, #-0x10]!
        sub             w4, w4, #1

        add             x14, x1, #1
        add             x15, x2, #1

        ld1             {v0.16b}, [x1]
        ld1             {v1.16b}, [x2]
        ld1             {v2.16b}, [x14]
        ld1             {v3.16b}, [x15]

        usubl           v30.8h, v0.8b, v1.8b
        usubl2          v29.8h, v0.16b, v1.16b
        mov             v29.h[7], wzr

        usubl           v28.8h, v2.8b, v3.8b
        usubl2          v27.8h, v2.16b, v3.16b
        mov             v27.h[7], wzr

        sabd            v28.8h, v30.8h, v28.8h
        sabd            v27.8h, v29.8h, v27.8h
        // neon does not allow immediate type extend/sign extend, so
        // we need to do this crane's dance here...
        movi            v18.8h, #1
        smull           v30.4s, v30.4h, v18.4h
        mov             s18, v30.s[0]
        sqabs           s18, s18
        uaddlv          s17, v28.8h
        sqadd           s18, s18, s17
        uaddlv          s17, v27.8h
        sqadd           s18, s18, s17

        cmp             w4, #1
        b.lt            2f

1:

        ld1             {v0.16b}, [x14], x3 // pix1 vector for V(j-stride)
        ld1             {v1.16b}, [x15], x3 // pix2 vector for V(j-stride)

        ld1             {v2.16b}, [x1], x3 // pix1 vector for V(j-stride-1)
        ld1             {v3.16b}, [x2], x3 // pix2 vector for V(j-stride-1)

        ld1             {v4.16b}, [x14] // pix1 vector for V(j)
        ld1             {v5.16b}, [x15] // pix2 vector for V(j)

        ld1             {v6.16b}, [x1] // pix1 vector for V(j-1)
        ld1             {v7.16b}, [x2] // pix2 vector for V(j-1)

        usubl           v30.8h, v6.8b, v7.8b // V(j-1)
        usubl2          v29.8h, v6.16b, v7.16b // V(j-1)
        mov             v29.h[7], wzr

        usubl           v28.8h, v2.8b, v3.8b // V(j-stride - 1)
        usubl2          v27.8h, v2.16b, v3.16b // V(j-stride - 1)
        mov             v27.h[7], wzr

        usubl           v26.8h, v0.8b, v1.8b // V(j-stride)
        usubl2          v25.8h, v0.16b, v1.16b // V(j-stride)
        mov             v25.h[7], wzr

        usubl           v24.8h, v4.8b, v5.8b // V(j)
        usubl2          v23.8h, v4.16b, v5.16b // V(j)
        mov             v23.h[7], wzr

        sabd            v20.8h, v30.8h, v28.8h
        mov             h17, v20.h[0]
        add             d18, d18, d17

        add             v22.8h, v26.8h, v30.8h
        add             v21.8h, v25.8h, v29.8h
        sub             v22.8h, v22.8h, v28.8h
        sub             v21.8h, v21.8h, v27.8h

        // Now we need to find median value for each of three elements of the vectors:
        // V0: V(j-stride)
        // V1: V(j-1)
        // V2: V(j-stride) + V(j-1) - V(j-stride-1)
        //
        // Consider following cases:
        // (1): V0 < V1 < V2
        // (2): V0 < V2 < V1
        // (3): V1 < V0 < V2
        // (4): V1 < V2 < V0
        // (5): V2 < V0 < V1
        // (6): V2 < V1 < V0
        //
        // Now split comparisons between these three vectors and fill the logic table.
        // Depending on previous cases, test whether first vector value is greated than the second
        //
        //                      (1)     (2)     (3)     (4)     (5)     (6)
        //      V0 vs V1:        0       0       1       1       0       1
        //      V0 vs V2:        0       0       0       1       1       1
        //      V1 vs V2:        0       1       0       0       1       1
        //
        //      median:          V1      V2      V0      V2      V0      V1
        //
        //      Now, use bitwise operations to find desired values:
        //      Vx: (V0 vs V1) XOR (V0 vs V2)
        //      Vy: NOT (Vx OR Vy)
        //      Vz: (V0 vs V2) XOR (V1 vs V2)
        //
        // Use the above logic to find the median.

        cmge            v20.8h, v26.8h, v30.8h // V(j-stride) > V(j-1)
        cmge            v19.8h, v25.8h, v29.8h // V(j-stride) > V(j-1)

        cmge            v17.8h, v26.8h, v22.8h // V(j-stride) > V(j-stride) + V(j-1) - V(j-stride-1)
        cmge            v16.8h, v25.8h, v21.8h // V(j-stride) > V(j-stride) + V(j-1) - V(j-stride-1)

        cmge            v15.8h, v30.8h, v22.8h // V(j-1) > V(j-stride) + V(j-1) - V(j-stride-1)
        cmge            v14.8h, v29.8h, v21.8h // V(j-1) > (j-stride) + V(j-1) - V(j-stride-1)

        eor             v0.16b, v20.16b, v17.16b // V(j-stride)
        eor             v1.16b, v19.16b, v16.16b // V(j-stride)
        eor             v2.16b, v17.16b, v15.16b // V(j-stride) + V(j-1) - V(j-stride-1)
        eor             v3.16b, v16.16b, v14.16b // V(j-stride) + V(j-1) - V(j-stride-1)
        orr             v4.16b, v0.16b, v2.16b
        orr             v5.16b, v1.16b, v3.16b
        not             v4.16b, v4.16b // V(j-1)
        not             v5.16b, v5.16b // V(j-1)

        bit             v6.16b, v26.16b, v0.16b // insert V(j-stride) if matches
        bit             v7.16b, v25.16b, v1.16b // insert V(j-stride) if matches
        bit             v6.16b, v22.16b, v2.16b // insert V(j-stride) + V(j-1) - V(j-stride-1) if matches
        bit             v7.16b, v21.16b, v3.16b // insert V(j-stride) + V(j-1) - V(j-stride-1) if matches

        bit             v6.16b, v30.16b, v4.16b // insert V(j-1) if matches
        bit             v7.16b, v29.16b, v5.16b // insert V(j-1) if matches

        sabd            v30.8h, v24.8h, v6.8h
        sabd            v29.8h, v23.8h, v7.8h
        uaddlv          s17, v30.8h
        add             d18, d18, d17
        uaddlv          s17, v29.8h
        add             d18, d18, d17

        subs            w4, w4, #1
        b.ne            1b

2:
        fmov            w0, s18
        ldp             d14, d15, [sp], #0x10

        ret

endfunc