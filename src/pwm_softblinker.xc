/*
  * pwm_softblinker.xc
 *
 *  Created on: 22. juni 2020
 *      Author: teig
 */

#include <xs1.h>
#include <platform.h> // slice
#include <timer.h>    // delay_milliseconds(200), XS1_TIMER_HZ etc
#include <stdint.h>   // uint8_t
#include <stdio.h>    // printf
#include <string.h>   // memcpy
#include <xccompat.h> // REFERENCE_PARAM(my_app_ports_t, my_app_ports) -> my_app_ports_t &my_app_ports
#include <iso646.h>   // not etc.

#include "_version.h"        // First this..
#include "_globals.h"        // ..then this
#include "maths.h"
#include "pwm_softblinker.h"

// ---
// Control printing
// See https://stackoverflow.com/questions/1644868/define-macro-for-debug-printing-in-c
// ---

#define DEBUG_PRINT_TEST 0
#define debug_print(fmt, ...) do { if((DEBUG_PRINT_TEST==1) and (DEBUG_PRINT_GLOBAL_APP==1)) printf(fmt, __VA_ARGS__); } while (0)


[[combinable]]
void softblinker_task (
        client pwm_if         if_pwm,
        server softblinker_if if_softblinker)
{
    timer        tmr;
    time32_t     timeout;
    bool         pwm_running = false;
    unsigned     pwm_one_percent_ticks = SOFTBLINK_DEFAULT_ONE_PERCENT_MS * XS1_TIMER_KHZ;
    signed       now_percentage        = SOFTBLINK_DEFAULT_MAX_PERCENTAGE; // [-1..101]
    percentage_t max_percentage        = SOFTBLINK_DEFAULT_MAX_PERCENTAGE;
    percentage_t min_percentage        = SOFTBLINK_DEFAULT_MIN_PERCENTAGE;
    signed       inc_percentage        = (-1); // [-1,+1]

    // if_pwm.set_port_in_sign (port_pin_sign);

    tmr :> timeout;
    timeout += pwm_one_percent_ticks;

    while (1) {
        select {
            case (pwm_running) => tmr when timerafter(timeout) :> void: {
                bool min_set;
                bool max_set;

                timeout += pwm_one_percent_ticks;

                now_percentage += inc_percentage; // [0..100] but [-1..101] possible if 0 or 100 was just set in set_sofblink_percentages
                {now_percentage, min_set, max_set} = in_range_signed_min_max_set (now_percentage, min_percentage, max_percentage); // [0..100]

                if ((min_set) or (max_set)) { // Send 100 and 0 only once
                    inc_percentage = (-inc_percentage); // Change sign for next timeout to scan in the other direction
                } else {
                    if_pwm.set_percentage ((percentage_t) now_percentage); // [0..100]
                }

            } break;

            case if_softblinker.set_sofblink_percentages (const percentage_t max_percentage_, const percentage_t min_percentage_): {
                debug_print ("set_sofblink_percentages %u %u\n", max_percentage_, min_percentage_);

                // Conflict with jumping above or below present range resolved with in_range_signed_min_max_set in timerafter

                                                                 // Also overflow/underflow problems solved there:
                max_percentage = (percentage_t) max_percentage_; // 100 here and max_percentage may be incrmeneted to 101 in timerafter
                min_percentage = (percentage_t) min_percentage_; //   0 here and min_percentage may be decremented to  -1 in timerafter

                if (max_percentage == min_percentage) {
                    pwm_running = false;
                    if_pwm.set_percentage (max_percentage);
                    // No code, timerafter will do it
                } else if (not pwm_running) {
                    pwm_running = true;
                    tmr :> timeout; // immediate timeout
                } else { // pwm_running already
                    // No code
                    // Don't disturb running timerafter
                }
            } break;

            case if_softblinker.set_one_percent_ms (const unsigned ms): {
                debug_print ("set_one_percent_ms %u\n", ms);

                pwm_one_percent_ticks = (ms * XS1_TIMER_KHZ);
            } break;
        }
    }
}


typedef enum {activated, deactivated} port_is_e;

void activeate_port (out buffered port:1 outP1, const port_pin_sign_e port_pin_sign) {
    outP1 <: (1 xor port_pin_sign);
}

void deactiveate_port (out buffered port:1 outP1, const port_pin_sign_e port_pin_sign) {
    outP1 <: (0 xor port_pin_sign);
}

#define ACTIVATE_PORT   do {outP1 <: (1 xor port_pin_sign);} while (0) // to activated:   0 = 1 xor 1 = [1 xor active_low]
#define DEACTIVATE_PORT do {outP1 <: (0 xor port_pin_sign);} while (0) // to deactivated: 1 = 0 xor 1 = [0 xor active_low]

// Standard type PWM based on timeouts
// But there would be another way to do this:
// This does not attach a timer to the port itself and use the @ number-of-ticks and timed output feature of XC. More about that here:
//     XS1 Ports: use and specification 2008 see https://www.xmos.com/file/xs1-ports-specification/
//     Introduction to XS1 ports        2010 see https://www.xmos.com/file/xs1-ports-introduction/
//     XMOS Programming Guide           2015 see https://www.xmos.com/download/XMOS-Programming-Guide-(documentation)(F).pdf

[[combinable]]
void pwm_for_LED_task (
        server pwm_if       if_pwm,
        out buffered port:1 outP1)
{
    timer           tmr;
    time32_t        timeout;
    port_pin_sign_e port_pin_sign             = PWM_PORT_PIN_SIGN;

    debug_print ("port_pin_sign %u\n", port_pin_sign);

    unsigned        pwm_one_percent_ticks     = PWM_ONE_PERCENT_TICS; // 10 uS. So 99% means 990 us activated and 10 us deactivated
    time32_t        port_activated_percentage = 100;                  // This implies [1], [2] and [3] below
    bool            pwm_running               = false;                // [1] no timerafter (doing_pwn when not 0% or not 100%)
    port_is_e       port_is                   = activated;            // [2] "LED on"
                                                                      //
    ACTIVATE_PORT;                                                    // [3]

    while (1) {
        select {
            case (pwm_running) => tmr when timerafter(timeout) :> void: {
                if (port_is == deactivated) {
                    ACTIVATE_PORT;
                    timeout += (port_activated_percentage * pwm_one_percent_ticks);
                    port_is  = activated;
                } else {
                    DEACTIVATE_PORT;
                    timeout += ((100 - port_activated_percentage) * pwm_one_percent_ticks);
                    port_is  = deactivated;;
                }
            } break;

            case if_pwm.set_percentage (const percentage_t percentage) : {

                port_activated_percentage = percentage;

                if (port_activated_percentage == 100) { // No need to involve any timerafter and get a short off blip
                    pwm_running = false;
                    ACTIVATE_PORT;
                } else if (port_activated_percentage == 0) { // No need to involve any timerafter and get a short on blink
                    pwm_running = false;
                    DEACTIVATE_PORT;
                } else if (not pwm_running) {
                    pwm_running = true;
                    tmr :> timeout; // immediate timeout
                } else { // pwm_running already
                    // No code
                    // Don't disturb running timerafter, just let it use the new port_activated_percentage when it gets there
                }
            } break;
        }
    }
}
