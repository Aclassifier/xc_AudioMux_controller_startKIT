/*
 * _globals.h
 *
 *  Created on: 15. aug. 2018
 *      Author: teig
 */

#ifndef GLOBALS_H_
#define GLOBALS_H_

#ifdef GLOBALS_H_ // To show that the below may also be defined in library space

    // BOOLEAN #include <stdbool.h> if C99
    // See http://www.teigfam.net/oyvind/home/technology/165-xc-code-examples/#bool
    typedef enum {false,true} bool; // 0,1 This typedef matches any integer-type type like long, int, unsigned, char, bool

    #define min(a,b) (((a)<(b))?(a):(b))
    #define max(a,b) (((a)>(b))?(a):(b))
    #define abs(a)   (((a)<0)?(-(a)):(a))

    #define t_swap(type,a,b) {type t = a; a = b; b = t;}

    #define NUM_ELEMENTS(array) (sizeof(array) / sizeof(array[0])) // Kernighan & Pike p22

    typedef signed int time32_t; // signed int (=signed) or unsigned int (=unsigned) both ok, as long as they are monotoneously increasing
                                 // XC/XMOS 100 MHz increment every 10 ns for max 2exp32 = 4294967296,
                                 // ie. divide by 100 mill = 42.9.. seconds

    typedef enum {led_on, led_off} led_on_low_e; // 0 is led_on

    #define AFTER_32(a,b) ((a-b)>0)

    #ifdef DO_ASSERTS
        #define ASSERT_DELAY_32(d) do {if (d > INT_MAX) fail("Overflow");} while (0) // Needs <so646.h<, <limits.h> and <xassert.h>
        // INT_MAX is 2147483647 is what fits into 31 bits or last value before a signed 32 bits wraps around
    #else
        #define ASSERT_DELAY_32(d)
    #endif

    #define NOW_32(tmr,time) do {tmr :> time;} while(0) // A tick is 10ns
    // “Programming XC on XMOS Devices” (Douglas Watt)
    //     If the delay between the two input values fits in 31 bits, timerafter is guaranteed to behave correctly,
    //     otherwise it may behave incorrectly due to overlow or underflow. This means that a timer can be used to
    //     measure up to a total of 2exp31 / (100 mill) = 21s.

#endif

#define IS_MYTARGET_VOID               0
#define IS_MYTARGET_STARTKIT           1 // Final
#define IS_MYTARGET_XCORE_200_EXPLORER 2 // Not tested
#define IS_MYTARGET_XCORE_XA_MODULE    3 // Not able to flash it
#define IS_MYTARGET_MIC_ARRAY          4


// -------> SEEMS LIKE THE PREPROCESSOR ONLY TAKES THE FIRST <--------
//
#if (MYTARGET==STARTKIT)
    #define IS_MYTARGET IS_MYTARGET_STARTKIT
#elif (MYTARGET==XCORE-200-EXPLORER)
    #define IS_MYTARGET IS_MYTARGET_XCORE_200_EXPLORER
    // Observe AMUX=001 for xflash to work
#elif (MYTARGET==XCORE-XA-MODULE)
    #define IS_MYTARGET IS_MYTARGET_XCORE_XA_MODULE
    //
    // The XMOS XS1-XAU8A-10-FB265 processor that's on XCORE-XA-MODULE
    // https://www.xmos.com/download/XS1-XAU8A-10-FB265-Datasheet(1.1).pdf
    // https://www.farnell.com/datasheets/1886306.pdf (however 8 xCORE)
    // https://www.xmos.com/download/xCORE-XA-Module-Board-Hardware-Manual(1.0).pdf
    //
    // https://www.teigfam.net/oyvind/home/technology/208-my-processor-to-analogue-audio-equaliser-notes/
    //
    // XCORE        64KB internal single-cycle SRAM for code and data storage
    //               8KB internal OTP for application boot code
    //                   DEBUG via xCORE xTAG
    // ARM         128KB internal single-cycle SRAM for code and data storage
    //            1024KB internal SPI FLASH of type AT25FS010 according to XCORE-XA-MODULE.xn. Boots ARM which again may boot XCORE
    //                   DEBUG via SEGGER J-Link OB
    // EXTERNAL    512KB external SPI FLASH of type M25P40. Used to boot XCORE
    //

#elif (MYTARGET==MIC_ARRAY)
    #define IS_MYTARGET IS_MYTARGET_MIC_ARRAY // Just for testing the display on that HW
#else
    #error NO TARGET DEFINED
#endif

#ifndef DISPLAY_FAST_DARK
    #error define DISPLAY_FAST_DARK in makefile
#else
    #if (DISPLAY_FAST_DARK>1)
        #error not defined
    #endif
#endif
                              //                      25Nov2020
#define USE_BUTTON_TASK_NUM 4 // 1 uses Button_Task_1 Constraints: C:8/4 T:10/4 C:32/7 M:25316 S:2824 C:19002 D:3490
                              // 2 uses Button_Task_2 Constraints: C:8/4 T:10/4 C:32/7 M:25484 S:2888 C:19142 D:3486 +168
                              // 3 uses Button_Task_3 Constraints: C:8/4 T:10/4 C:32/7 M:25620 S:2888 C:19246 D:3486 +136
                              // 4 uses Button_Task_4 Constraints: C:8/4 T:10/4 C:32/7 M:25672 S:2896 C:19286 D:3490  +52
#if (USE_BUTTON_TASK_NUM==1)
    #define button_if_gen button_if_1
#elif (USE_BUTTON_TASK_NUM==2)
    #define button_if_gen button_if_2
#elif (USE_BUTTON_TASK_NUM==3)
    #define button_if_gen button_if_3
#elif (USE_BUTTON_TASK_NUM==4)
    #define button_if_gen button_if_3 // same
    #define MAX_BUTTON_NOISY_TIME_US 99999 // Almost 100000 = 100 ms
#endif

#define DEBUG_PRINT_GLOBAL_APP 0 // 0: all printf off
                                 // 1: controlled locally in each xc file. Unit must be connected to xTIMEcomposer. Not for off-line battery usage!

#endif /* GLOBALS_H_ */
