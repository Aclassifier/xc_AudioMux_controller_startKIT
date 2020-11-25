/*
 * button_press.xc
 *
 *  Created on: 18. mars 2015
 *      Author: teig
 */
#define INCLUDES
#ifdef INCLUDES
    #include <platform.h>
    #include <xs1.h>
    #include <stdlib.h>
    #include <stdint.h>
    #include <stdio.h>
    #include <iso646.h>
    #include <xccompat.h> // REFERENCE_PARAM

    #include "_version.h" // First this..
    #include "_globals.h" // ..then this
    #include "param.h"
    #include "button_press.h"
#endif

#define DEBUG_PRINT_BUTTON_PRESS 0
#define debug_print(fmt, ...) do { if((DEBUG_PRINT_BUTTON_PRESS==1) and (DEBUG_PRINT_GLOBAL_APP==1)) printf(fmt, __VA_ARGS__); } while (0)


#define DEBOUNCE_TIMEOUT_MS 50


#define BUTTON_PRESSED   0 // If pullup resistor
#define BUTTON_RELEASED  1 // If pullup resistor

[[combinable]]
void Button_Task_1 (
        const unsigned      button_n,
        in buffered port:1  p_button,
        client button_if_1  i_button_out) // See http://www.teigfam.net/oyvind/home/technology/141-xc-is-c-plus-x/#the_combined_code_6_to_zero_channels
{
    // From XMOS-Programming-Guide.
    int      button_on_event = BUTTON_PRESSED;
    bool     is_stable       = true;
    timer    tmr;
    time32_t timeout;
    time32_t current_time;

    // ¯yvind's matters:
    bool initial_released_stopped = false; // Since it would do BUTTON_ACTION_RELEASED always after start
    bool ruled_as_pressed_but_not_released = false;

    debug_print("inP_Button_Task_1[%u] started\n", button_n);

    while(1) {
        select {
            // If the button is "stable", react when the I/O pin changes value
            case is_stable => p_button when pinsneq(button_on_event) :> button_on_event: {
                if (button_on_event == BUTTON_PRESSED) {
                    // debug_print(": Button %u pressed\n", button_n);
                } else {
                    // debug_print(": Button %u released\n", button_n);
                }

                ruled_as_pressed_but_not_released = false; // Not ruled as pressed yet
                is_stable = false; // Don't know yet

                tmr :> current_time;
                // Calculate time to event after debounce period
                // note that XS1_TIMER_HZ is defined in timer.h
                timeout = current_time + (DEBOUNCE_TIMEOUT_MS * XS1_TIMER_KHZ);
                // If the button is not stable (i.e. bouncing around) then select
                // when we the timer reaches the timeout to reenter a stable period
            } break;

            case (ruled_as_pressed_but_not_released or (is_stable == false)) => tmr when timerafter(timeout) :> void: {

                if (is_stable == false) {
                    if (button_on_event == BUTTON_PRESSED) {
                        initial_released_stopped = true; // Not if BUTTON_ACTION_PRESSED was sent first
                        ruled_as_pressed_but_not_released = true; // ONLY PLACE IT'S SET

                        i_button_out.button (BUTTON_ACTION_PRESSED); // Button down
                        debug_print(" BUTTON_ACTION_PRESSED %u sent\n", button_n);
                        tmr :> current_time;
                        timeout = current_time + (BUTTON_ACTION_PRESSED_FOR_LONG_TIMEOUT_MS * XS1_TIMER_KHZ);
                    } else {
                        if (initial_released_stopped == false) { // Also after BUTTON_ACTION_PRESSED_FOR_LONG
                            initial_released_stopped = true;
                            debug_print(" BUTTON_ACTION_RELEASED %u filtered\n", button_n);
                        } else {
                            ruled_as_pressed_but_not_released = false;
                            i_button_out.button (BUTTON_ACTION_RELEASED);
                            debug_print(" BUTTON_ACTION_RELEASED %u sent\n", button_n);
                        }
                    }
                    is_stable = true;
                } else { // == ruled_as_pressed_but_not_released (is_stable == true, so pinsneq would have stopped it)
                    // xTIMEcomposer 14.2.4 works fine
                    // xTIMEcomposer 14.3.0 does 880997 times in 30 seconds with DEBUG_PRINT_BUTTON_PRESS==0, yields about 30000 per second probably livelocked (but printed in receiver)
                    ruled_as_pressed_but_not_released = false;
                    initial_released_stopped = false; // To avoid BUTTON_ACTION_RELEASED when it's released (RFM69=003)
                    i_button_out.button (BUTTON_ACTION_PRESSED_FOR_LONG);
                    debug_print(" BUTTON_ACTION_PRESSED_FOR_LONG %u sent\n", button_n);
                }
            } break;
        }
    }
}

// AMUX=009 new
// Rewrote Button_Task to Button_Task_2 to withstand not only debounce, but also EMC (assumed to always be leaving line high BUTTON_RELEASED after EMC)
//
// The XMOS-Programming-Guide (2015/9/18 XM004440A, chapter 8 "Handling button presses") shows an example of how to handle debouncing. This works as described there,
// and I have used it in several projects. However, the "is_stable" bool there does not reflect what it pertains to indicate. It goes "not stable" on the first change
// of the button line, then just waits for some time. The line may then go up and down several times (from bouncing and from EMC, like starting fridge compressors,
// which I experienced) without the software delaying after the last of these pulses. It may then deliver a button pressed or released signal on pure EMC.
//
// This implementation discovers all noise, and will then add a delay after the last edge. It also counts the number of such edges.

[[combinable]]
void Button_Task_2 (
        const unsigned              button_n,
        const long_button_enabled_e long_button_enabled,
        in buffered port:1          p_button,
        client button_if_2          i_button_out)
{
    int      button_on_event = BUTTON_PRESSED;
    bool     do_timeout_debounce_now = false;
    bool     do_timeout_long_now = false;
    bool     filter_next_button_released = true; // This would come initially
    timer    tmr_debounce; // Only one combined hardware timer..
    timer    tmr_long;     // ..is used for these two software timers
    time32_t timeout_debounce;
    time32_t timeout_long;
    time32_t current_time;
    unsigned button_edge_cnt = 0;

    debug_print("inP_Button_Task_2[%u] started\n", button_n);

    while(1) {
        select {
            case p_button when pinsneq(button_on_event) :> button_on_event: {
                do_timeout_debounce_now = true;
                do_timeout_long_now     = false;
                button_edge_cnt++;
                tmr_debounce :> current_time;
                timeout_debounce = current_time + (DEBOUNCE_TIMEOUT_MS * XS1_TIMER_KHZ);
            } break;

            case do_timeout_debounce_now => tmr_debounce when timerafter(timeout_debounce) :> void: {
                do_timeout_debounce_now = false;
                if (button_on_event == BUTTON_PRESSED) {
                    debug_print(" BUTTON_ACTION_PRESSED %u send, cnt %u\n", button_n, button_edge_cnt);
                    i_button_out.button (BUTTON_ACTION_PRESSED, button_edge_cnt); // Button down
                    if (long_button_enabled == long_enabled) {
                        do_timeout_long_now = true;
                        tmr_long :> current_time;
                        timeout_long = current_time + (BUTTON_ACTION_PRESSED_FOR_LONG_TIMEOUT_MS * XS1_TIMER_KHZ);
                    } else {
                        // long_disabled, no code
                    }
                } else if (filter_next_button_released) {
                    // BUTTON_RELEASED, but we don't want it after BUTTON_ACTION_PRESSED_FOR_LONG, no code
                    debug_print(" BUTTON_ACTION_RELEASED %u filtered\n", button_n);
                } else { // BUTTON_RELEASED
                    debug_print(" BUTTON_ACTION_RELEASED %u send, cnt %u\n", button_n, button_edge_cnt);
                    i_button_out.button (BUTTON_ACTION_RELEASED, button_edge_cnt);
                }
                filter_next_button_released = false;
                button_edge_cnt = 0;
            } break;

            case do_timeout_long_now => tmr_long when timerafter(timeout_long) :> void: {
                do_timeout_long_now = false;
                if (button_on_event == BUTTON_PRESSED) {
                    debug_print(" BUTTON_ACTION_PRESSED_FOR_LONG %u send, cnt %u\n", button_n, button_edge_cnt);
                    i_button_out.button (BUTTON_ACTION_PRESSED_FOR_LONG, button_edge_cnt);
                    filter_next_button_released = true;
                } else { // BUTTON_RELEASED
                    // cannot happen here since do_timeout_long_now was set when BUTTON_PRESSED, no code
                    debug_print(" BUTTON_ACTION_RELEASED_FOR_LONG %u NOT sent, cnt %u\n", button_n, button_edge_cnt);
                }
                button_edge_cnt = 0;
            } break;
        }
    }
}

[[combinable]]
void Button_Task_3 (
        const unsigned              button_n,
        const long_button_enabled_e long_button_enabled,
        in buffered port:1          p_button,
        client button_if_3          i_button_out)
{
    int      button_on_event = BUTTON_PRESSED;
    bool     do_timeout_debounce_now = false;
    bool     do_timeout_long_now = false;
    bool     filter_next_button_released = true; // This would come initially
    timer    tmr_debounce; // Only one combined hardware timer..
    timer    tmr_long;     // ..is used for these two software timers
    time32_t timeout_debounce;
    time32_t timeout_long;
    time32_t current_time;
    unsigned button_edge_cnt = 0;
    time32_t noisy_start_time;
    unsigned button_noisy_time_us = 0;
    bool     noisy_start_measure = true;

    debug_print("inP_Button_Task_3[%u] started\n", button_n);

    while(1) {
        select {
            case p_button when pinsneq(button_on_event) :> button_on_event: {
                do_timeout_debounce_now = true;
                do_timeout_long_now     = false;
                button_edge_cnt++;

                tmr_debounce :> current_time;

                if (noisy_start_measure) {
                    noisy_start_measure = false;
                    noisy_start_time = current_time;
                } else {}

                button_noisy_time_us = (current_time - noisy_start_time) / XS1_TIMER_MHZ; // DEBOUNCE_TIMEOUT_MS may start several times after this
                timeout_debounce     =  current_time + (DEBOUNCE_TIMEOUT_MS * XS1_TIMER_KHZ);
            } break;

            case do_timeout_debounce_now => tmr_debounce when timerafter(timeout_debounce) :> void: {
                do_timeout_debounce_now = false;
                if (button_on_event == BUTTON_PRESSED) {
                    debug_print(" BUTTON_ACTION_PRESSED %u send, cnt %u, noisy %u\n", button_n, button_edge_cnt, button_noisy_time_us);
                    i_button_out.button (BUTTON_ACTION_PRESSED, button_edge_cnt, button_noisy_time_us); // Button down
                    if (long_button_enabled == long_enabled) {
                        do_timeout_long_now = true;
                        tmr_long :> current_time;
                        timeout_long = current_time + (BUTTON_ACTION_PRESSED_FOR_LONG_TIMEOUT_MS * XS1_TIMER_KHZ);
                    } else {
                        // long_disabled, no code
                    }
                } else if (filter_next_button_released) {
                    // BUTTON_RELEASED, but we don't want it after BUTTON_ACTION_PRESSED_FOR_LONG, no code
                    debug_print(" BUTTON_ACTION_RELEASED %u filtered\n", button_n);
                } else { // BUTTON_RELEASED
                    debug_print(" BUTTON_ACTION_RELEASED %u send, cnt %u, noisy %u\n", button_n, button_edge_cnt, button_noisy_time_us);
                    i_button_out.button (BUTTON_ACTION_RELEASED, button_edge_cnt, button_noisy_time_us);
                }
                filter_next_button_released = false;
                button_edge_cnt = 0;
                noisy_start_measure = true;
            } break;

            case do_timeout_long_now => tmr_long when timerafter(timeout_long) :> void: {
                do_timeout_long_now = false;
                if (button_on_event == BUTTON_PRESSED) {
                    debug_print(" BUTTON_ACTION_PRESSED_FOR_LONG %u send, cnt %u, noisy %u\n", button_n, button_edge_cnt, button_noisy_time_us);
                    i_button_out.button (BUTTON_ACTION_PRESSED_FOR_LONG, button_edge_cnt, button_noisy_time_us);
                    filter_next_button_released = true;
                } else { // BUTTON_RELEASED
                    // cannot happen here since do_timeout_long_now was set when BUTTON_PRESSED, no code
                    debug_print(" BUTTON_ACTION_RELEASED_FOR_LONG %u NOT sent, cnt %u, noisy %u\n", button_n, button_edge_cnt, button_noisy_time_us);
                }
                button_edge_cnt = 0;
                noisy_start_measure = true;
            } break;
        }
    }
}

[[combinable]]
void Button_Task_4 (
        const unsigned              button_n,
        const unsigned              max_button_noisy_time_us, // added
        const long_button_enabled_e long_button_enabled,
        in buffered port:1          p_button,
        client button_if_3          i_button_out)
{
    int      button_on_event = BUTTON_PRESSED;
    bool     do_timeout_debounce_now = false;
    bool     do_timeout_long_now = false;
    bool     filter_next_button_released = true; // This would come initially
    timer    tmr_debounce; // Only one combined hardware timer..
    timer    tmr_long;     // ..is used for these two software timers
    time32_t timeout_debounce;
    time32_t timeout_long;
    time32_t current_time;
    unsigned button_edge_cnt = 0;
    time32_t noisy_start_time;
    unsigned button_noisy_time_us = 0;
    bool     noisy_start_measure = true; // AMUX=011 new
    bool     max_time_reached = false;   // AMUX=011 new

    debug_print("inP_Button_Task_3[%u] started\n", button_n);

    while(1) {
        select {
            case (not max_time_reached) => p_button when pinsneq(button_on_event) :> button_on_event: {
                do_timeout_debounce_now = true;
                do_timeout_long_now     = false;
                button_edge_cnt++;

                tmr_debounce :> current_time;

                if (noisy_start_measure) {
                    noisy_start_measure = false;
                    noisy_start_time = current_time;
                } else {}

                button_noisy_time_us = (current_time - noisy_start_time) / XS1_TIMER_MHZ; // DEBOUNCE_TIMEOUT_MS may start several times after this
                max_time_reached = (button_noisy_time_us > max_button_noisy_time_us);

                if (max_time_reached) {
                    // Avoid forever picking up noise in the DEBOUNCE_TIMEOUT_MS "shadow"
                    timeout_debounce = current_time; // immediately
                } else {
                    timeout_debounce = current_time + (DEBOUNCE_TIMEOUT_MS * XS1_TIMER_KHZ);
                }
            } break;

            case do_timeout_debounce_now => tmr_debounce when timerafter(timeout_debounce) :> void: {

                if (button_on_event == BUTTON_PRESSED) {
                    debug_print(" BUTTON_ACTION_PRESSED %u send, cnt %u, noisy %u\n", button_n, button_edge_cnt, button_noisy_time_us);
                    i_button_out.button (BUTTON_ACTION_PRESSED, button_edge_cnt, button_noisy_time_us); // Button down
                    if (long_button_enabled == long_enabled) {
                        do_timeout_long_now = true;
                        tmr_long :> current_time;
                        timeout_long = current_time + (BUTTON_ACTION_PRESSED_FOR_LONG_TIMEOUT_MS * XS1_TIMER_KHZ);
                    } else {
                        // long_disabled, no code
                    }
                } else if (filter_next_button_released) {
                    // BUTTON_RELEASED, but we don't want it after BUTTON_ACTION_PRESSED_FOR_LONG, no code
                    debug_print(" BUTTON_ACTION_RELEASED %u filtered\n", button_n);
                } else { // BUTTON_RELEASED
                    debug_print(" BUTTON_ACTION_RELEASED %u send, cnt %u, noisy %u\n", button_n, button_edge_cnt, button_noisy_time_us);
                    i_button_out.button (BUTTON_ACTION_RELEASED, button_edge_cnt, button_noisy_time_us);
                }

                do_timeout_debounce_now     = false;
                filter_next_button_released = false;
                button_edge_cnt             = 0;
                noisy_start_measure         = true;
                max_time_reached            = false;
            } break;

            case do_timeout_long_now => tmr_long when timerafter(timeout_long) :> void: {
                // It is important that during this waiting max_time_reached is false, so that a BUTTON_ACTION_PRESSED may cancel this waiting
                do_timeout_long_now = false;
                if (button_on_event == BUTTON_PRESSED) {
                    debug_print(" BUTTON_ACTION_PRESSED_FOR_LONG %u send, cnt %u, noisy %u\n", button_n, button_edge_cnt, button_noisy_time_us);
                    i_button_out.button (BUTTON_ACTION_PRESSED_FOR_LONG, button_edge_cnt, button_noisy_time_us);
                    filter_next_button_released = true;
                } else { // BUTTON_RELEASED
                    // cannot happen here since do_timeout_long_now was set when BUTTON_PRESSED, no code
                    debug_print(" BUTTON_ACTION_RELEASED_FOR_LONG %u NOT sent, cnt %u, noisy %u\n", button_n, button_edge_cnt, button_noisy_time_us);
                }
                button_edge_cnt = 0;
                noisy_start_measure = true;
            } break;
        }
    }
}
