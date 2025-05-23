/*
 * _AudioMux_controller_startKIT.xc
 *
 *  Created on: 22. sep. 2020
 *      Author: teig
 */

#include <platform.h> // core
#include <stdio.h>    // printf
#include <timer.h>    // delay_milliseconds(..), XS1_TIMER_HZ etc
#include <stdint.h>   // uint8_t
#include <iso646.h>   // readability
#include <i2c.h>

#include "_version.h" // First this..
#include "_globals.h" // ..then this
#include "param.h"
#include "i2c_client_task.h"
#include "display_ssd1306.h"
#include "core_graphics_adafruit_gfx.h"
#include "core_graphics_font5x8.h"
#include "_texts_and_constants.h"
#include "button_press.h"
#include "iochip_tda7468_audiomux.h"
#include "maths.h"
#include "pwm_softblinker.h"
#include "_AudioMux_controller.h"

#if (WARNINGS == 1)
    #if (IS_MYTARGET == IS_MYTARGET_STARTKIT)
        #warning TARGET: STARTKIT
    #elif (IS_MYTARGET == IS_MYTARGET_XCORE_200_EXPLORER)
        #warning TARGET: XCORE-200-EXPLORER
    #elif (IS_MYTARGET == IS_MYTARGET_XCORE_XA_MODULE)
        #warning TARGET: XCORE-XA-MODULE
    #elif (IS_MYTARGET == IS_MYTARGET_MIC_ARRAY)
       #warning TARGET: MIC_ARRAY
    #else
        #warning NO TARGET DEFINED
    #endif
#endif
// ---
// Control printing
// See https://stackoverflow.com/questions/1644868/define-macro-for-debug-printing-in-c
// ---

#define DEBUG_PRINT_TEST 1
#define debug_print(fmt, ...) do { if((DEBUG_PRINT_TEST==1) and (DEBUG_PRINT_GLOBAL_APP==1)) printf(fmt, __VA_ARGS__); } while (0)

// ---
// Define data typedefs
// ---

typedef unsigned worked_ms_t;

typedef struct log_t {
    unsigned cnt;
} log_t;

typedef enum display_screen_name_t {
    SCREEN_VOLUME,
    SCREEN_BASS,
    SCREEN_TREBLE,
    SCREEN_RESET,
    SCREEN_INPUT,
    SCREEN_BUTTONS, // AMUX=009
    SCREEN_ABOUT,   // LAST SEEN
    SCREEN_DARK     // LAST
} display_screen_name_t;

typedef enum {is_on, is_off} display_state_e;

typedef struct {
    display_state_e       state;
    display_screen_name_t display_screen_name;
    display_screen_name_t display_screen_name_when_into_dark;
    char                  display_ts1_chars [SSD1306_TS1_DISPLAY_VISIBLE_CHAR_LEN]; // 84 chars for display needs 85 char buffer (with NUL) when sprintf is use (use SSD1306_TS1_DISPLAY_ALL_CHAR_LEN for full flexibility)
    int                   sprintf_numchars;
    unsigned              screen_timeouts_since_last_button_countdown; // From NUM_TIMEOUTS_BEFORE_SCREEN_DARK to zero for SCREEN_DARK
} display_context_t;

// For set_one_percent_ms and set_sofblink_percentages
#define SOFTBLINK_RESTARTED_ONE_PERCENT_MS        1 //  1 ms goes to 100 in 0.1 seconds -> 5 blinks per second
#define SOFTBLINK_RESTARTED_UNIT_MAX_PERCENTAGE 100
#define SOFTBLINK_RESTARTED_UNIT_MIN_PERCENTAGE   0
//
#define SOFTBLINK_DARK_DISPLAY_ONE_PERCENT_MS    30 // 30 ms goes to 100 in 3.0 seconds
#define SOFTBLINK_DARK_DISPLAY_MAX_PERCENTAGE    40
#define SOFTBLINK_DARK_DISPLAY_MIN_PERCENTAGE    10
//
#define SOFTBLINK_LIT_DISPLAY_ONE_PERCENT_MS     10 // 10 ms goes to 100 in 1.0 seconds
#define SOFTBLINK_LIT_DISPLAY_MAX_PERCENTAGE     80
#define SOFTBLINK_LIT_DISPLAY_MIN_PERCENTAGE     10

#define NUM_TIMEOUTS_PER_SECOND     2
#define NUM_TIMEOUTS_BEFORE_REPEAT (1.5 * NUM_TIMEOUTS_PER_SECOND)  // 1,5 seconds
//      BUTTON_ACTION_PRESSED_FOR_LONG_TIMEOUT_MS must be so long that it does not interfere here

// From makefile
#if (DISPLAY_FAST_DARK==1)
    #warning Not standard display to dark timeout
    #define NUM_TIMEOUTS_BEFORE_SCREEN_DARK (10 * NUM_TIMEOUTS_PER_SECOND)     // 10 seconds, for screen_timeouts_since_last_button
#elif (DISPLAY_FAST_DARK==0)
    #define NUM_TIMEOUTS_BEFORE_SCREEN_DARK ((5*60) * NUM_TIMEOUTS_PER_SECOND) // 5 minutes, for screen_timeouts_since_last_button
#endif


typedef struct {
    bool     now;
    unsigned timeouts_after_last_button_cnt;
    unsigned volume_step_factor; // increasing for every repeat taken, so that going to VOLUME_MIN_DB does not feel "endless"
} repeat_t;

typedef enum {was_none, was_button, was_timeout} last_action_e;

#ifdef MAX_BUTTON_NOISY_TIME_US
    #define BUTTON_PARAMS_MAX_VAL_99999 MAX_BUTTON_NOISY_TIME_US
#else
    #define BUTTON_PARAMS_MAX_VAL_99999 99999 // Greater than 99999 becomes 99999, for SCREEN_BUTTONS display space only
#endif

#define BUTTON_PARAMS_MAX_VAL_999     999 // Greater than 999 becomes 999, for SCREEN_BUTTONS display space only
#define BUTTON_PARAMS_MAX_VAL_99       99 // Greater than 99 becomes 99, for SCREEN_BUTTONS display space only
#define BUTTON_PARAMS_MAX_WRAP_VAL_99  99 // Wraps at 99, for SCREEN_BUTTONS display space only


typedef struct {
    bool            pressed_ever;
    bool            button_action_taken;
    button_action_t button_action [BUTTONS_NUM_CLIENTS];
    repeat_t        repeat;
    last_action_e   last_action; // AMUX=005
    bool            ignore_left_button_release_no_wake_from_dark; // AMUX=006 new. Since I started with LEFT_BUTTON take on released
    //
    // FOR SCREEN_BUTTONS buttons debug/research screen
    unsigned button_pressed_now_cnt   [BUTTONS_NUM_CLIENTS];
    unsigned button_released_now_cnt  [BUTTONS_NUM_CLIENTS];
    unsigned button_edge_cnt          [BUTTONS_NUM_CLIENTS];
    unsigned button_edge_cnt_max      [BUTTONS_NUM_CLIENTS]; // No function to ever clear it!
    unsigned button_noisy_time_us_max [BUTTONS_NUM_CLIENTS];

} buttons_context_t;

typedef struct {
    volume_dB_t       volume_dB;
    volume_dB_table_t volume_dB_table;
    bool              volume_buffer_gain_6_dB;
    tone_dB_t         bass_dB;
    tone_dB_t         treble_dB;
    bool              i2c_ok;
    unsigned          i2c_err_cnt;
                      // The idea with i2c_bytes is to keep the full register set as a copy here, and write out all even when a single bit is being changed
                      // Observe that TDA7468 cannot be read from
    i2c_uint8_t       i2c_bytes[LEN_I2C_TDA7468_MAX_BYTES]; // Not including device address i2c_dev_address_internal_e
} audiomux_context_t; // Moved into amuxchan_context_t with AMUX=012

typedef struct {
    input_channel_t    input_channel; // AMUX=007 new
    audiomux_context_t audiomux_context [INPUT_NUM];
} amuxchan_context_t; // New with AMUX=012

// ---
// do_print_log
// Prints log if DEBUG_PRINT_TEST is 1. If DEBUG_PRINT_TEST is 0, this function
// is not generated by the compiler
// ---

unsigned do_print_log (
        const unsigned    caller,
        log_t             &log,
        buttons_context_t &buttons_context) {

    unsigned cnt = log.cnt + 1;

    // buttons_context.button_action
    // BUTTON=0 BUTTON_ACTION_VOID
    // BUTTON=1 BUTTON_ACTION_PRESSED
    // BUTTON=2 BUTTON_ACTION_PRESSED_FOR_LONG
    // BUTTON=3 BUTTON_ACTION_RELEASED

    debug_print ("(%u) cnt %u BUTTON=%u.%u.%u events=%u.%u.%u\n",
            caller,
            log.cnt,
            buttons_context.button_action[IOF_BUTTON_LEFT],
            buttons_context.button_action[IOF_BUTTON_CENTER],
            buttons_context.button_action[IOF_BUTTON_RIGHT],
            buttons_context.button_edge_cnt_max[IOF_BUTTON_LEFT],
            buttons_context.button_edge_cnt_max[IOF_BUTTON_CENTER],
            buttons_context.button_edge_cnt_max[IOF_BUTTON_RIGHT]);

    return (cnt);
}


void do_display_params_zero ( display_context_t &display_context) {

    Clear_All_Pixels_In_Buffer();

    for (int index_of_char = 0; index_of_char < NUM_ELEMENTS(display_context.display_ts1_chars); index_of_char++) {
        display_context.display_ts1_chars [index_of_char] = ' ';
    }

    setTextColor(WHITE);
    setCursor(0,0);
    setTextSize(1); // SSD1306_TS1_LINE_CHAR_NUM gives 21 chars per line (but crlf takes two, if used)
}

// MUST NOT MODIFY ANY STATE VALUES!
bool // i2c_ok
    Display_screen (
        display_context_t                &display_context,
        buttons_context_t                &buttons_context,
        amuxchan_context_t               &amuxchan_context,
        client  i2c_internal_commands_if if_i2c_internal_commands) {

    bool i2c_ok = true;
    bool do_display_print = true;

    const input_channel_t input_channel = amuxchan_context.input_channel;

    if (display_context.state == is_on) {

        do_display_params_zero (display_context);

        switch (display_context.display_screen_name) {
            case SCREEN_VOLUME: {
                if (amuxchan_context.audiomux_context[input_channel].volume_buffer_gain_6_dB) {
                    // ADD "+6 dB" in small letters on the bottom line, to the right
                    setCursor(102,24); // 103 is too far. 24 on the last line, 25 one pixel below (ok) and 26 outside
                    display_context.sprintf_numchars = sprintf (display_context.display_ts1_chars, "+6"); // Two cars, used in next setCursor
                    display_print (display_context.display_ts1_chars, display_context.sprintf_numchars); // num chars not including NUL

                    setCursor(102+(6*2)+2,24); // The space looks too large, even if it's the same ratio as for large chars
                    display_context.sprintf_numchars = sprintf (display_context.display_ts1_chars, "dB");
                    display_print (display_context.display_ts1_chars, display_context.sprintf_numchars); // num chars not including NUL
                } else {}

                setCursor(0,0);
                setTextSize(2); // SSD1306_TS2_DISPLAY_VISIBLE_CHAR_NUM gives 10 chars per line
                display_context.sprintf_numchars = sprintf (display_context.display_ts1_chars, "  VOLUM\n  %d dB", amuxchan_context.audiomux_context[input_channel].volume_dB);
            } break;
            case SCREEN_BASS: {
                setTextSize(2); // SSD1306_TS2_DISPLAY_VISIBLE_CHAR_NUM gives 10 chars per line
                display_context.sprintf_numchars = sprintf (display_context.display_ts1_chars, "  BASS\n  %d dB", amuxchan_context.audiomux_context[input_channel].bass_dB);
            } break;
            case SCREEN_TREBLE: {
                setTextSize(2); // SSD1306_TS2_DISPLAY_VISIBLE_CHAR_NUM gives 10 chars per line
                display_context.sprintf_numchars = sprintf (display_context.display_ts1_chars, "  DISKANT\n  %d dB", amuxchan_context.audiomux_context[input_channel].treble_dB);
            } break;
            case SCREEN_RESET: {
                display_context.sprintf_numchars = sprintf (display_context.display_ts1_chars, "VOLUM BASS DISKANT\n\n");
                display_print (display_context.display_ts1_chars, display_context.sprintf_numchars); // num chars not including NUL

                setTextSize(2); // SSD1306_TS2_DISPLAY_VISIBLE_CHAR_NUM gives 10 chars per line
                display_context.sprintf_numchars = sprintf (display_context.display_ts1_chars, "%3d%3d%3d",
                        amuxchan_context.audiomux_context[input_channel].volume_dB,
                        amuxchan_context.audiomux_context[input_channel].bass_dB,
                        amuxchan_context.audiomux_context[input_channel].treble_dB);
            } break;
            case SCREEN_INPUT: {

                setCursor(0,10);
                setTextSize(2); // SSD1306_TS2_DISPLAY_VISIBLE_CHAR_NUM gives 10 chars per line

                display_context.sprintf_numchars = sprintf (display_context.display_ts1_chars, "IN%d", amuxchan_context.input_channel+1);

                // x,y=0,0 is left top and for SSD1306_128_32 x,y=127,31 is right bottom
                #define X0         60
                #define Y0          8
                #define X_DIST     20
                #define Y_DIST     16
                #define X_OUT_SKEW  5
                #define RADIUS      6

                const int16_t x0 [INPUT_NUM] = {X0, X0,        X0+X_DIST, X0+X_DIST};
                const int16_t y0 [INPUT_NUM] = {Y0, Y0+Y_DIST, Y0,        Y0+Y_DIST};

                // IN1-IN4: circles with thin circumference, but filled for active IN:
                for (unsigned ix=INPUT_MIN_DEFAULT; ix < INPUT_NUM; ix++) {
                    if (ix == amuxchan_context.input_channel) {
                        fillCircle (x0[ix], y0[ix], RADIUS, WHITE);
                    } else {
                        drawCircle (x0[ix], y0[ix], RADIUS, WHITE);
                    }
                }

                // OUT = circle with thick circumference:
                fillCircle (X0+X_DIST+X_DIST+X_OUT_SKEW, Y0, RADIUS,   WHITE);
                fillCircle (X0+X_DIST+X_DIST+X_OUT_SKEW, Y0, RADIUS-2, BLACK);
            } break;
            case SCREEN_BUTTONS: {

                do_display_params_zero (display_context);
                i2c_ok = writeToDisplay_i2c_all_buffer(if_i2c_internal_commands);
                delay_milliseconds (10);

                const char char_aa_str[] = CHAR_aa_STR; // å
                setTextSize(1); // SSD1306_TS1_LINE_CHAR_NUM gives 21 chars per line (but crlf takes two, if used)

                // BUTTON_PARAMS_MAX_VAL_99999   99999 // %5u also if value is MAX_BUTTON_NOISY_TIME_US
                // BUTTON_PARAMS_MAX_VAL_999       999 // %3u
                // BUTTON_PARAMS_MAX_WRAP_VAL_99    99 // %2u
                // BUTTON_PARAMS_MAX_VAL_999        99 // %2u
                display_context.sprintf_numchars = sprintf (display_context.display_ts1_chars,
                        "INN UT  n%s Max usMax\n %2u %2u %3u %3u %5u\n %2u %2u %3u %3u %5u\n %2u %2u %3u %3u %5u",
                        char_aa_str,
                        buttons_context.button_pressed_now_cnt   [IOF_BUTTON_LEFT],
                        buttons_context.button_released_now_cnt  [IOF_BUTTON_LEFT],
                        buttons_context.button_edge_cnt          [IOF_BUTTON_LEFT],
                        buttons_context.button_edge_cnt_max      [IOF_BUTTON_LEFT],
                        buttons_context.button_noisy_time_us_max [IOF_BUTTON_LEFT],
                        buttons_context.button_pressed_now_cnt   [IOF_BUTTON_CENTER],
                        buttons_context.button_released_now_cnt  [IOF_BUTTON_CENTER],
                        buttons_context.button_edge_cnt          [IOF_BUTTON_CENTER],
                        buttons_context.button_edge_cnt_max      [IOF_BUTTON_CENTER],
                        buttons_context.button_noisy_time_us_max [IOF_BUTTON_CENTER],
                        buttons_context.button_pressed_now_cnt   [IOF_BUTTON_RIGHT],
                        buttons_context.button_released_now_cnt  [IOF_BUTTON_RIGHT],
                        buttons_context.button_edge_cnt          [IOF_BUTTON_RIGHT],
                        buttons_context.button_edge_cnt_max      [IOF_BUTTON_RIGHT],
                        buttons_context.button_noisy_time_us_max [IOF_BUTTON_RIGHT]);

                // Observe "nå" (NOW) means for BUTTON_ACTION_PRESSED since that's when this function is called,
                // but "Max" for both BUTTON_ACTION_PRESSED and BUTTON_ACTION_RELEASED. That's why small and capital letter of "nå,Max"
                // usMax also is a Max for both BUTTON_ACTION_PRESSED and BUTTON_ACTION_RELEASED
                //                                            --------------------
                //                                            INN UT  nå Max usMax
                //                                             12 12   1  22   917 (IN and OUT may be seen not to have the same number.. if one press fast enough?)
                //                                             34 34   1  44   975
                //                                             73 73   3  12   952
                //                                             99 99 999 999 99999 (max shown)
                //                                             99 99 102 102  2915 (max seen)
            } break;
            case SCREEN_ABOUT: {
                const char char_OE_str[]          = CHAR_OE_STR; // Ø
                const char char_right_arrow_str[] = CHAR_RIGHT_ARROW_STR;

                setTextSize(1); // SSD1306_TS1_LINE_CHAR_NUM gives 21 chars per line (but crlf takes two, if used)

                #if (IS_MYTARGET == IS_MYTARGET_STARTKIT)
                    display_context.sprintf_numchars = sprintf (display_context.display_ts1_chars,
                                          "AudioMUX + startKIT\nXMOS XC %s\nV:%s  xT:%s\n%s.TEIG   %s BLOG 208",
                                          __DATE__,
                                          AUDIOMUX_VERSION_STR,
                                          XTIMECOMPOSER_VERSION_STR,
                                          char_OE_str,
                                          char_right_arrow_str);
                       //                                            AudioMUX + startKIT
                       //                                            XMOS XC JUN 18 2020
                       //                                            V:1.1.0  xT:14.4.1
                       //                                            Ø.TEIG   → BLOG 208
                #elif (IS_MYTARGET == IS_MYTARGET_XCORE_200_EXPLORER)
                    #warning MISSING TEXT
                #elif (IS_MYTARGET == IS_MYTARGET_XCORE_XA_MODULE)
                    display_context.sprintf_numchars = sprintf (display_context.display_ts1_chars,
                                          "AudioMUX XMOS XA\nXC KODE %s\nV:%s  xT:%s\n%syvind Teig       %s",
                                          __DATE__,
                                          AUDIOMUX_VERSION_STR,
                                          XTIMECOMPOSER_VERSION_STR,
                                          char_OE_str, smiley_str);
                       //                                            AudioMUX XMOS XA
                       //                                            XC CODE JUN 18 2020
                       //                                            V:0.1.75  xT:14.4.1
                       //                                            Øyvind Teig
                #elif (IS_MYTARGET == IS_MYTARGET_MIC_ARRAY)
                    display_context.sprintf_numchars = sprintf (display_context.display_ts1_chars,
                                          "MicArray XMOS XA\nXC KODE %s\nV:%s  xT:%s\n%syvind Teig",
                                          __DATE__,
                                          AUDIOMUX_VERSION_STR,
                                          XTIMECOMPOSER_VERSION_STR,
                                          char_OE_str);
                       //                                            MicArray XMOS XA
                       //                                            XC CODE JUN 18 2020
                       //                                            V:0.1.75  xT:14.4.1
                       //                                            Øyvind Teig
                #endif

            } break;
            default: {} break;
        }

        if (do_display_print) {
            display_print (display_context.display_ts1_chars, display_context.sprintf_numchars); // num chars not including NUL
        } else {}

        i2c_ok = writeToDisplay_i2c_all_buffer(if_i2c_internal_commands);
        // debug_print ("%s\n", i2c_ok ? "ok2" : "err2");

    } else {
        // is_off : no code
    }

    return i2c_ok;
}

void display_context_init (display_context_t &display_context) {

    display_context.display_screen_name                         = SCREEN_VOLUME;
    display_context.state                                       = is_on;
    display_context.screen_timeouts_since_last_button_countdown = NUM_TIMEOUTS_BEFORE_SCREEN_DARK;
}

void button_edge_cnt_init (buttons_context_t &buttons_context) {

    for (int iof_button = 0; iof_button < BUTTONS_NUM_CLIENTS; iof_button++) {
       buttons_context.button_edge_cnt          [iof_button] = 0;
       buttons_context.button_edge_cnt_max      [iof_button] = 0;
       buttons_context.button_pressed_now_cnt   [iof_button] = 0;
       buttons_context.button_released_now_cnt  [iof_button] = 0;
       buttons_context.button_noisy_time_us_max [iof_button] = 0;
    }
}

void buttons_context_init (buttons_context_t &buttons_context) {

    for (int iof_button = 0; iof_button < BUTTONS_NUM_CLIENTS; iof_button++) {
       buttons_context.button_action[iof_button] = BUTTON_ACTION_VOID;
    }

    buttons_context.button_action_taken                          = false;
    buttons_context.repeat.volume_step_factor                    = 1;
    buttons_context.pressed_ever                                 = false;
    buttons_context.last_action                                  = was_none;
    buttons_context.ignore_left_button_release_no_wake_from_dark = false;

    button_edge_cnt_init (buttons_context);
}

void do_audiomux_and_display (
        client  i2c_general_commands_if  if_i2c_general_commands,
        display_context_t                &display_context,
        buttons_context_t                &buttons_context, // Mostly for do_print_log
        amuxchan_context_t               &amuxchan_context,
        log_t                            log,
        client  i2c_internal_commands_if if_i2c_internal_commands) {

    const input_channel_t input_channel = amuxchan_context.input_channel;

    amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R0_INPUT_SELECT_AND_MIC] and_eq compl DATA_INPUT_SELECT_IN_1_4_MASK; // zero those bits only
    //
    amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R0_INPUT_SELECT_AND_MIC] or_eq tda7468_make_input_channel(amuxchan_context.input_channel); // fill those bits
    amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R2_SURROUND]             =     tda7468_make_surround     (amuxchan_context.audiomux_context[input_channel].volume_buffer_gain_6_dB);
    amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R3_VOLUME_LEFT]          =     tda7468_make_volume       (amuxchan_context.audiomux_context[input_channel].volume_dB, amuxchan_context.audiomux_context[input_channel].volume_dB_table);
    amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R4_VOLUME_RIGHT]         =     tda7468_make_volume       (amuxchan_context.audiomux_context[input_channel].volume_dB ,amuxchan_context.audiomux_context[input_channel].volume_dB_table);
    amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R5_TREBLE_AND_BASS]      =     tda7468_make_tone         (amuxchan_context.audiomux_context[input_channel].bass_dB,   amuxchan_context.audiomux_context[input_channel].treble_dB);

    Display_screen (display_context, buttons_context, amuxchan_context, if_i2c_internal_commands);
    do_print_log (0, log, buttons_context); // ingnoring return value to avoid more than one increment

    amuxchan_context.audiomux_context[input_channel].i2c_ok =
            if_i2c_general_commands.write_reg_ok (
                    I2C_HARDWARE_IOF_AUDIOMUX,
                    I2C_AUDIOMUX_IOF_ICLIENT_0,
                    I2C_ADDRESS_OF_AUDIOMUX,
                    amuxchan_context.audiomux_context[input_channel].i2c_bytes,
                    LEN_I2C_TDA7468_MAX_BYTES);

    if (amuxchan_context.audiomux_context[input_channel].i2c_ok == false) { amuxchan_context.audiomux_context[input_channel].i2c_err_cnt++; }

    debug_print ("Volume=%d dB, CMD=%02X ", amuxchan_context.audiomux_context[input_channel].volume_dB, amuxchan_context.audiomux_context[input_channel].i2c_bytes[IOF_I2C_SUBADDRESS]);

    for (unsigned ix=LEN_I2C_SUBADDRESS; ix <LEN_I2C_TDA7468_MAX_BYTES; ix++) {
        debug_print ("R%u=%02X ", ix-LEN_I2C_SUBADDRESS, amuxchan_context.audiomux_context[input_channel].i2c_bytes[ix]);
    }
    debug_print ("%s", "\n");
}

void audiomux_context_init (
        amuxchan_context_t &amuxchan_context) {

    amuxchan_context.input_channel = INPUT_MIN_DEFAULT;

    for (input_channel_t input_channel = INPUT_MIN_DEFAULT; input_channel < (INPUT_MIN_DEFAULT + INPUT_NUM); input_channel++) {

        volume_dB_table_t volume_dB_table = {VOLUME_SETTING_TABLE_INIT};

            for (unsigned ix=0; ix<NUM_VOLUME_SETTINGS; ix++) {
                amuxchan_context.audiomux_context[input_channel].volume_dB_table[ix][IOF_VOLUME1_1DB_STEPS_TABLE] = volume_dB_table[ix][IOF_VOLUME1_1DB_STEPS_TABLE];
                amuxchan_context.audiomux_context[input_channel].volume_dB_table[ix][IOF_VOLUME1_8DB_STEPS_TABLE] = volume_dB_table[ix][IOF_VOLUME1_8DB_STEPS_TABLE];
                amuxchan_context.audiomux_context[input_channel].volume_dB_table[ix][IOF_VOLUME2_8DB_STEPS_TABLE] = volume_dB_table[ix][IOF_VOLUME2_8DB_STEPS_TABLE];
            }

            amuxchan_context.audiomux_context[input_channel].i2c_err_cnt             = 0;
            amuxchan_context.audiomux_context[input_channel].volume_dB               = 0;
            amuxchan_context.audiomux_context[input_channel].volume_buffer_gain_6_dB = false;
            amuxchan_context.audiomux_context[input_channel].bass_dB                 = 0;
            amuxchan_context.audiomux_context[input_channel].treble_dB               = 0;
            amuxchan_context.input_channel              = INPUT_MIN_DEFAULT;

            // INIT THE 8 REGISTERS FOR THE AUDIOMUX

            amuxchan_context.audiomux_context[input_channel].i2c_bytes[IOF_I2C_SUBADDRESS]                                 = TDA7468_R0_INPUT_SELECT_AND_MIC bitor TDA7468_REG_ADDR_AUTOINCREMENT_MASK;
            amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R0_INPUT_SELECT_AND_MIC] = (tda7468_make_input_channel(amuxchan_context.input_channel) bitor DATA_INPUT_SELECT_MUTE_OFF_SOUND_ON_VAL bitor DATA_INPUT_SELECT_MIC_OFF_VAL);
            amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R1_INPUT_GAIN]           = DATA_INPUT_GAIN_00_DB_VAL; // Just hard-code this
            amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R2_SURROUND]             = tda7468_make_surround (amuxchan_context.audiomux_context[input_channel].volume_buffer_gain_6_dB);
            amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R3_VOLUME_LEFT]          = tda7468_make_volume   (amuxchan_context.audiomux_context[input_channel].volume_dB, amuxchan_context.audiomux_context[input_channel].volume_dB_table);
            amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R4_VOLUME_RIGHT]         = tda7468_make_volume   (amuxchan_context.audiomux_context[input_channel].volume_dB, amuxchan_context.audiomux_context[input_channel].volume_dB_table);
            amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R5_TREBLE_AND_BASS]      = tda7468_make_tone     (amuxchan_context.audiomux_context[input_channel].bass_dB,   amuxchan_context.audiomux_context[input_channel].treble_dB);
            amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R7_OUTPUT_MUTE]          = DATA_OUTPUT_MUTE_OFF_SOUND_ON_VAL;
            amuxchan_context.audiomux_context[input_channel].i2c_bytes[LEN_I2C_SUBADDRESS+TDA7468_R7_BASS_ALC]             = 0; // Just hard-code this
    }
}

void buttons_repeat_clear (buttons_context_t &buttons_context) {
    buttons_context.repeat.timeouts_after_last_button_cnt = 0;
    buttons_context.repeat.now = false;
    buttons_context.repeat.volume_step_factor = 1;
}

typedef enum {
    not_pending_dark,
    pending_dark_from_long_left_button,
    pending_dark_only
} display_pending_dark_e; // AMUX=004 new

void set_softblink_as_display_on (client softblinker_if if_softblinker) {
    if_softblinker.set_one_percent_ms (SOFTBLINK_LIT_DISPLAY_ONE_PERCENT_MS);
    if_softblinker.set_sofblink_percentages (SOFTBLINK_LIT_DISPLAY_MAX_PERCENTAGE, SOFTBLINK_LIT_DISPLAY_MIN_PERCENTAGE);
}

// ---
// client_task
// Asks for work from NUM_WORKERS worker_task (service requested
// in different sequences) and results from workers, when they arrive, handled.
// Each interface call is blocking and synchronous, but the net result of the
// pattern is asynchronous worker_task assignments.
// Log, a button and LEDs handled.
// ---

[[combinable]]
void buttons_client_task (
        client i2c_internal_commands_if if_i2c_internal_commands,
        client i2c_general_commands_if  if_i2c_general_commands,
        server button_if_gen            i_buttons_in[BUTTONS_NUM_CLIENTS],
        out port                        p_display_notReset,
        client softblinker_if           if_softblinker)
{
    display_context_t  display_context;
    buttons_context_t  buttons_context;
    amuxchan_context_t amuxchan_context;
    log_t              log;

    timer    tmr;
    time32_t time_ticks; // Ticks to 100 in 1 us

    // STARTUP
    if_softblinker.set_one_percent_ms (SOFTBLINK_RESTARTED_ONE_PERCENT_MS);
    if_softblinker.set_sofblink_percentages (SOFTBLINK_RESTARTED_UNIT_MAX_PERCENTAGE, SOFTBLINK_RESTARTED_UNIT_MIN_PERCENTAGE);

    log.cnt = 0;

    audiomux_context_init (amuxchan_context);
    buttons_context_init  (buttons_context);
    buttons_repeat_clear  (buttons_context);
    display_context_init  (display_context);

    // Set-up display chip
    {
        Adafruit_GFX_constructor (SSD1306_LCDWIDTH, SSD1306_LCDHEIGHT);
        Adafruit_SSD1306_i2c_begin (if_i2c_internal_commands, p_display_notReset);

        Display_screen (display_context, buttons_context, amuxchan_context, if_i2c_internal_commands);
    }

    debug_print ("CMD=%02X ", amuxchan_context.audiomux_context[amuxchan_context.input_channel].i2c_bytes[IOF_I2C_SUBADDRESS]);
    for (unsigned ix=LEN_I2C_SUBADDRESS; ix <LEN_I2C_TDA7468_MAX_BYTES; ix++) {
        debug_print ("R%u=%02X ", ix-LEN_I2C_SUBADDRESS, amuxchan_context.audiomux_context[amuxchan_context.input_channel].i2c_bytes[ix]);
    }
    debug_print ("%s", "\n");

    amuxchan_context.audiomux_context[amuxchan_context.input_channel].i2c_ok =
            if_i2c_general_commands.write_reg_ok (
                    I2C_HARDWARE_IOF_AUDIOMUX,
                    I2C_AUDIOMUX_IOF_ICLIENT_0,
                    I2C_ADDRESS_OF_AUDIOMUX,
                    amuxchan_context.audiomux_context[amuxchan_context.input_channel].i2c_bytes,
                    LEN_I2C_TDA7468_MAX_BYTES);

    if (amuxchan_context.audiomux_context[amuxchan_context.input_channel].i2c_ok == false) { amuxchan_context.audiomux_context[amuxchan_context.input_channel].i2c_err_cnt++; }

    debug_print ("ok = %u err_cnt = %u\n", amuxchan_context.audiomux_context[amuxchan_context.input_channel].i2c_ok, amuxchan_context.audiomux_context[amuxchan_context.input_channel].i2c_err_cnt);

    debug_print ("%s", "client_task\n");

    tmr :> time_ticks;
    time_ticks += (1 * XS1_TIMER_HZ); // 1 second before first timerafter

    while (true) {
        select { // Each case passively waits on an event:

            // --------------------------------------------------------------------------------
            // BUTTON ACTION (REPEAT: BUTTON HELD FOR SOME TIME) AT TIMEOUT
            // --------------------------------------------------------------------------------
            case tmr when timerafter (time_ticks) :> void : {

                display_pending_dark_e display_pending_dark       = not_pending_dark; // AMUX=004 new. AMUX=005 local here
                bool                   do_do_audiomux_and_display = false;
                const input_channel_t  input_channel              = amuxchan_context.input_channel;

                time_ticks += (XS1_TIMER_HZ/NUM_TIMEOUTS_PER_SECOND);

                // HANDLE REPEAT AND SIMULATE BUTTONS
                //
                if ((buttons_context.button_action[IOF_BUTTON_LEFT]   == BUTTON_ACTION_PRESSED) or
                    (buttons_context.button_action[IOF_BUTTON_CENTER] == BUTTON_ACTION_PRESSED) or
                    (buttons_context.button_action[IOF_BUTTON_RIGHT]  == BUTTON_ACTION_PRESSED))
                {
                    if (buttons_context.last_action == was_button) {
                        // no code. To keep pending_dark_from_long_left_button out of it, if
                        // left button is pressed and pressed and pressed and at the same time picked up here
                    } else if (buttons_context.repeat.timeouts_after_last_button_cnt < NUM_TIMEOUTS_BEFORE_REPEAT) {
                        buttons_context.repeat.timeouts_after_last_button_cnt++; // LATER
                    } else { // == NUM_TIMEOUTS_BEFORE_REPEAT
                         buttons_context.repeat.now = true;
                         buttons_context.repeat.volume_step_factor++;
                    }
                } else {}

                // HANDLE REPEAT
                //
                if (buttons_context.repeat.now) {
                    buttons_context.button_action_taken = false;

                    switch (display_context.display_screen_name) {
                        case SCREEN_VOLUME: { // Button pressed for som time (repeat) at timeout
                            if (buttons_context.button_action[IOF_BUTTON_CENTER] == BUTTON_ACTION_PRESSED) {
                                amuxchan_context.audiomux_context[input_channel].volume_dB = amuxchan_context.audiomux_context[input_channel].volume_dB - (buttons_context.repeat.volume_step_factor * VOLUME_STEP_DB);
                                buttons_context.button_action_taken = true;
                            } else if (buttons_context.button_action[IOF_BUTTON_RIGHT] == BUTTON_ACTION_PRESSED) {
                                amuxchan_context.audiomux_context[input_channel].volume_dB = amuxchan_context.audiomux_context[input_channel].volume_dB + (buttons_context.repeat.volume_step_factor * VOLUME_STEP_DB);
                                buttons_context.button_action_taken = true;
                            } else if (buttons_context.button_action[IOF_BUTTON_LEFT] == BUTTON_ACTION_PRESSED) {
                                display_pending_dark = pending_dark_from_long_left_button;
                            } else {}
                        } break;
                        case SCREEN_BASS: { // Button pressed for som time (repeat) at timeouts
                            if (buttons_context.button_action[IOF_BUTTON_CENTER] == BUTTON_ACTION_PRESSED) {
                                amuxchan_context.audiomux_context[input_channel].bass_dB = amuxchan_context.audiomux_context[input_channel].bass_dB - TONE_STEP_DB;
                                buttons_context.button_action_taken = true;
                            } else if (buttons_context.button_action[IOF_BUTTON_RIGHT] == BUTTON_ACTION_PRESSED) {
                                amuxchan_context.audiomux_context[input_channel].bass_dB = amuxchan_context.audiomux_context[input_channel].bass_dB + TONE_STEP_DB;
                                buttons_context.button_action_taken = true;
                            } else if (buttons_context.button_action[IOF_BUTTON_LEFT] == BUTTON_ACTION_PRESSED) {
                                display_pending_dark = pending_dark_from_long_left_button;
                            } else {}
                        } break;
                        case SCREEN_TREBLE: { // Button pressed for som time (repeat) at timeout
                            if (buttons_context.button_action[IOF_BUTTON_CENTER] == BUTTON_ACTION_PRESSED) {
                                buttons_context.button_action_taken = true;
                                amuxchan_context.audiomux_context[input_channel].treble_dB = amuxchan_context.audiomux_context[input_channel].treble_dB - TONE_STEP_DB;
                            } else if (buttons_context.button_action[IOF_BUTTON_RIGHT] == BUTTON_ACTION_PRESSED) {
                                amuxchan_context.audiomux_context[input_channel].treble_dB = amuxchan_context.audiomux_context[input_channel].treble_dB + TONE_STEP_DB;
                                buttons_context.button_action_taken = true;
                            } else if (buttons_context.button_action[IOF_BUTTON_LEFT] == BUTTON_ACTION_PRESSED) {
                                display_pending_dark = pending_dark_from_long_left_button;
                            } else {}
                        } break;
                        case SCREEN_RESET: { // Button pressed for some time (repeat) at timeout
                            if (buttons_context.button_action[IOF_BUTTON_CENTER] == BUTTON_ACTION_PRESSED) {
                                // Keep volume_dB
                                amuxchan_context.audiomux_context[input_channel].bass_dB   = amuxchan_context.audiomux_context[input_channel].bass_dB   - TONE_STEP_DB; // AMUX=003
                                amuxchan_context.audiomux_context[input_channel].treble_dB = amuxchan_context.audiomux_context[input_channel].treble_dB + TONE_STEP_DB; // AMUX=003
                                buttons_context.button_action_taken = true;
                            } else if (buttons_context.button_action[IOF_BUTTON_RIGHT] == BUTTON_ACTION_PRESSED) {
                                // Keep volume_dB
                                amuxchan_context.audiomux_context[input_channel].bass_dB   = amuxchan_context.audiomux_context[input_channel].bass_dB   + TONE_STEP_DB; // AMUX=003
                                amuxchan_context.audiomux_context[input_channel].treble_dB = amuxchan_context.audiomux_context[input_channel].treble_dB - TONE_STEP_DB; // AMUX=003
                                buttons_context.button_action_taken = true;
                            } else if (buttons_context.button_action[IOF_BUTTON_LEFT] == BUTTON_ACTION_PRESSED) {
                                display_pending_dark = pending_dark_from_long_left_button;
                            } else {}
                        } break;
                        case SCREEN_INPUT: // AMUX=008 now shares code with this:
                        case SCREEN_BUTTONS:
                        case SCREEN_ABOUT: { // Button pressed for som time (repeat) at timeout
                            // No code, this also needs to time out into dark
                            if (buttons_context.button_action[IOF_BUTTON_LEFT] == BUTTON_ACTION_PRESSED) {
                                display_pending_dark = pending_dark_from_long_left_button;
                            } else {}
                        } break;
                        default: {} break;
                    }

                    {
                        bool min_set;
                        bool max_set;

                        {amuxchan_context.audiomux_context[input_channel].volume_dB, min_set, max_set} = in_range_int8_min_max_set (amuxchan_context.audiomux_context[input_channel].volume_dB, VOLUME_MIN_DB, VOLUME_MAX_DB);

                        if (min_set) {
                            // No code. At first I thought this was smart, but it feels wrong after I introduced toggling on max_set
                            // amuxchan_context.audiomux_context[input_channel].volume_buffer_gain_6_dB = false;
                        } else if (max_set) {
                            amuxchan_context.audiomux_context[input_channel].volume_buffer_gain_6_dB = not amuxchan_context.audiomux_context[input_channel].volume_buffer_gain_6_dB; // Toggle it
                        } else {}
                    }

                    amuxchan_context.audiomux_context[input_channel].bass_dB   = in_range_int8 (amuxchan_context.audiomux_context[input_channel].bass_dB,   TONE_MIN_DB, TONE_MAX_DB);
                    amuxchan_context.audiomux_context[input_channel].treble_dB = in_range_int8 (amuxchan_context.audiomux_context[input_channel].treble_dB, TONE_MIN_DB, TONE_MAX_DB);

                    if (buttons_context.button_action_taken) {
                        display_context.screen_timeouts_since_last_button_countdown = NUM_TIMEOUTS_BEFORE_SCREEN_DARK; // timeout
                        do_do_audiomux_and_display = true;
                    } else {}

                } else {
                    // Not buttons_context.repeat.now, no code
                }

                // Just any timeout

                if (display_context.display_screen_name == SCREEN_DARK) {
                    // No code
                    // display_context.screen_timeouts_since_last_button_countdown is zero, ok!
                } else {

                    if (display_context.screen_timeouts_since_last_button_countdown > 0) {
                        display_context.screen_timeouts_since_last_button_countdown--;
                    } else {}
                    if (display_context.screen_timeouts_since_last_button_countdown == 0) {
                        display_pending_dark = pending_dark_only;
                    } else {}

                    if (display_pending_dark != not_pending_dark) {

                        if (display_pending_dark == pending_dark_from_long_left_button) {
                            buttons_context.ignore_left_button_release_no_wake_from_dark = true;
                        } else {}

                        display_context.display_screen_name_when_into_dark = display_context.display_screen_name;
                        display_context.display_screen_name = SCREEN_DARK;

                        buttons_repeat_clear (buttons_context);

                        do_do_audiomux_and_display = true;

                        if (buttons_context.pressed_ever) {
                            // INTO DARK SCREEN
                            if_softblinker.set_one_percent_ms (SOFTBLINK_DARK_DISPLAY_ONE_PERCENT_MS);
                            if_softblinker.set_sofblink_percentages (SOFTBLINK_DARK_DISPLAY_MAX_PERCENTAGE, SOFTBLINK_DARK_DISPLAY_MIN_PERCENTAGE);
                        } else {} // No code, keep initial blinking until button pressed at least once
                    } else {}
                }

                if (do_do_audiomux_and_display) {
                    do_audiomux_and_display (if_i2c_general_commands, display_context, buttons_context, amuxchan_context, log, if_i2c_internal_commands);
                } else {}

                buttons_context.last_action = was_timeout;
            } break; // timerafter

            // --------------------------------------------------------------------------------
            // BUTTON PRESSES
            // --------------------------------------------------------------------------------

            case
                #if (USE_BUTTON_TASK_NUM==1)
                    i_buttons_in[int iof_button].button (const button_action_t button_action) : {
                        const unsigned button_edge_cnt = 0;
                        const unsigned button_noisy_time_us   = 0;
                #elif (USE_BUTTON_TASK_NUM==2)
                    i_buttons_in[int iof_button].button (const button_action_t button_action, const unsigned button_edge_cnt) : {
                        const unsigned button_noisy_time_us = 0;
                #elif ((USE_BUTTON_TASK_NUM==3) or (USE_BUTTON_TASK_NUM==4))
                    i_buttons_in[int iof_button].button (const button_action_t button_action, const unsigned button_edge_cnt, const unsigned button_noisy_time_us) : {
                #endif

                // HANDLE BUTTONS (button_states_t not needed) (BUTTON_ACTION_PRESSED_FOR_LONG not used)

                const bool pressed_now  = (button_action == BUTTON_ACTION_PRESSED);
                const bool released_now = (button_action == BUTTON_ACTION_RELEASED);

                input_channel_t input_channel = amuxchan_context.input_channel; // search for "aliasing" below

                // Left button is taken on released_now since I can press and hold it and then the display goes to dark.
                // And when it went to dark it has not shown a next screen first (it did show this phantom screen when I took ,
                // it on pressed_now, and I had to restore the screen on wakeup to before the phantom screen, which looked very strange).
                // But then, when the long button press that caused the screen to go dark is released, the display must not go
                // immediately on again!
                // That's why ignore_left_button_release_no_wake_from_dark and left_button_filtered were introduced (AMUX=006)
                //
                const bool left_button   = released_now and  (iof_button==IOF_BUTTON_LEFT);
                const bool other_buttons = pressed_now  and ((iof_button==IOF_BUTTON_CENTER) or (iof_button==IOF_BUTTON_RIGHT));

                bool screen_dark_on_button = (display_context.display_screen_name == SCREEN_DARK);

                bool left_button_filtered;

                if (left_button and buttons_context.ignore_left_button_release_no_wake_from_dark) {
                    buttons_context.ignore_left_button_release_no_wake_from_dark = false;
                    left_button_filtered = false; // Filtered to not accept
                } else {
                    left_button_filtered = left_button; // Not filtered
                }

                buttons_context.button_action_taken = false;

                buttons_context.button_action [iof_button] = button_action;

                // Handle values for the button edge debug monitor SCREEN_BUTTONS

                buttons_context.button_edge_cnt          [iof_button] = in_range_unsigned (     button_edge_cnt,                                                             0, BUTTON_PARAMS_MAX_VAL_999);
                buttons_context.button_edge_cnt_max      [iof_button] = in_range_unsigned (max (button_edge_cnt,      buttons_context.button_edge_cnt_max     [iof_button]), 0, BUTTON_PARAMS_MAX_VAL_999);
                buttons_context.button_noisy_time_us_max [iof_button] = in_range_unsigned (max (button_noisy_time_us, buttons_context.button_noisy_time_us_max[iof_button]), 0, BUTTON_PARAMS_MAX_VAL_99999);

                if (pressed_now) {
                    buttons_context.button_pressed_now_cnt [iof_button]  = (buttons_context.button_pressed_now_cnt [iof_button]  + 1) % (BUTTON_PARAMS_MAX_WRAP_VAL_99+1);
                } else if (released_now) {
                    buttons_context.button_released_now_cnt [iof_button] = (buttons_context.button_released_now_cnt [iof_button] + 1) % (BUTTON_PARAMS_MAX_WRAP_VAL_99+1);
                } else {} // Not possible

                if (released_now and (display_context.display_screen_name == SCREEN_BUTTONS)) {
                    // Special case for the button edge debug monitor SCREEN_BUTTONS
                    Display_screen (display_context, buttons_context, amuxchan_context, if_i2c_internal_commands);
                } else {}

                // Go on with the "real" code

                log.cnt = do_print_log (1, log, buttons_context);

                if (left_button_filtered or other_buttons) {

                    if (not buttons_context.pressed_ever) {
                        buttons_context.pressed_ever = true;
                        // FIRST BUTTON PRESS AFTER STARTUP. SAME AS JUST ABOVE HERE AND BELOW
                        set_softblink_as_display_on (if_softblinker);
                    } else {}

                    if (left_button_filtered) {

                        bool allow_next_screen = false;

                        if (screen_dark_on_button) {
                            display_context.display_screen_name = display_context.display_screen_name_when_into_dark;
                            // FROM DARK SCREEN, GENERALA CASE
                            set_softblink_as_display_on (if_softblinker);
                        } else {}

                        switch (display_context.display_screen_name) {
                            case SCREEN_VOLUME: { // Button press
                                if (buttons_context.button_action[IOF_BUTTON_CENTER] == BUTTON_ACTION_PRESSED) {
                                    amuxchan_context.audiomux_context[input_channel].volume_dB = VOLUME_MIN_DB; // "Minus" goes to muted
                                    amuxchan_context.audiomux_context[input_channel].volume_buffer_gain_6_dB = false; // Since VOLUME_MIN_DB by repeat button takes too long
                                } else if (buttons_context.button_action[IOF_BUTTON_RIGHT] == BUTTON_ACTION_PRESSED) {
                                    amuxchan_context.audiomux_context[input_channel].volume_dB = VOLUME_MAX_DB; // "Plus" goes to fully on
                                } else {
                                    allow_next_screen = true;
                                }
                            } break;
                            case SCREEN_BASS: { // Button press
                                if (buttons_context.button_action[IOF_BUTTON_CENTER] == BUTTON_ACTION_PRESSED) {
                                    amuxchan_context.audiomux_context[input_channel].bass_dB = TONE_MIN_DB;
                                } else if (buttons_context.button_action[IOF_BUTTON_RIGHT] == BUTTON_ACTION_PRESSED) {
                                    amuxchan_context.audiomux_context[input_channel].bass_dB = TONE_MAX_DB; // "Plus" goes to fully on
                                } else {
                                    allow_next_screen = true;
                                }
                            } break;
                            case SCREEN_TREBLE: { // Button press
                                if (buttons_context.button_action[IOF_BUTTON_CENTER] == BUTTON_ACTION_PRESSED) {
                                     amuxchan_context.audiomux_context[input_channel].treble_dB = TONE_MIN_DB;
                                 } else if (buttons_context.button_action[IOF_BUTTON_RIGHT] == BUTTON_ACTION_PRESSED) {
                                     amuxchan_context.audiomux_context[input_channel].treble_dB = TONE_MAX_DB;
                                 } else {
                                     allow_next_screen = true;
                                 }
                            } break;
                            case SCREEN_RESET: { // Button press
                                if ((buttons_context.button_action[IOF_BUTTON_CENTER] == BUTTON_ACTION_PRESSED) or
                                    (buttons_context.button_action[IOF_BUTTON_RIGHT] == BUTTON_ACTION_PRESSED)) {

                                    amuxchan_context.audiomux_context[input_channel].volume_dB = 0;
                                    amuxchan_context.audiomux_context[input_channel].bass_dB   = 0;
                                    amuxchan_context.audiomux_context[input_channel].treble_dB = 0;

                                    // Not cleared since it basically has to do with normal input level. So no code:
                                    // amuxchan_context.audiomux_context[input_channel].volume_buffer_gain_6_dB = false;

                                 } else {
                                     allow_next_screen = true;
                                 }
                            } break;
                            case SCREEN_INPUT:
                            case SCREEN_BUTTONS:
                            case SCREEN_ABOUT: { // Button press
                                allow_next_screen = true;
                            } break;
                            default: {} break;
                        }

                        if ((allow_next_screen) and (not screen_dark_on_button)) {
                            display_context.display_screen_name = (display_context.display_screen_name + 1) % SCREEN_DARK;
                        } else {}

                    } else if (other_buttons) {

                         switch (iof_button) {
                            case IOF_BUTTON_CENTER: {
                                switch (display_context.display_screen_name) {
                                    case SCREEN_VOLUME: { // Button press
                                        amuxchan_context.audiomux_context[input_channel].volume_dB = amuxchan_context.audiomux_context[input_channel].volume_dB - VOLUME_STEP_DB;
                                        buttons_repeat_clear (buttons_context);
                                    } break;
                                    case SCREEN_BASS: { // Button press
                                        amuxchan_context.audiomux_context[input_channel].bass_dB = amuxchan_context.audiomux_context[input_channel].bass_dB - TONE_STEP_DB;
                                        buttons_repeat_clear (buttons_context);
                                    } break;
                                    case SCREEN_TREBLE: {
                                        amuxchan_context.audiomux_context[input_channel].treble_dB = amuxchan_context.audiomux_context[input_channel].treble_dB - TONE_STEP_DB;
                                        buttons_repeat_clear (buttons_context);
                                    } break;
                                    case SCREEN_RESET: { // Button press
                                        // Keep volume_dB
                                        amuxchan_context.audiomux_context[input_channel].bass_dB   = amuxchan_context.audiomux_context[input_channel].bass_dB   - TONE_STEP_DB; // AMUX=001
                                        amuxchan_context.audiomux_context[input_channel].treble_dB = amuxchan_context.audiomux_context[input_channel].treble_dB + TONE_STEP_DB; // AMUX=001
                                        buttons_repeat_clear (buttons_context);
                                    } break;
                                    case SCREEN_INPUT: { // Button press
                                        amuxchan_context.input_channel = amuxchan_context.input_channel - 1;
                                        amuxchan_context.input_channel and_eq (INPUT_NUM-1);
                                        input_channel = amuxchan_context.input_channel; // Removes the effect of the above aliasing
                                    } break;
                                    case SCREEN_ABOUT: { // Button press
                                        // No code
                                    } break;
                                    default: {} break;
                                }
                            } break;

                            case IOF_BUTTON_RIGHT: {
                                switch (display_context.display_screen_name) {
                                    case SCREEN_VOLUME: { // Button press
                                        amuxchan_context.audiomux_context[input_channel].volume_dB = amuxchan_context.audiomux_context[input_channel].volume_dB + VOLUME_STEP_DB;
                                        buttons_repeat_clear (buttons_context);
                                    } break;
                                    case SCREEN_BASS: { // Button press
                                        amuxchan_context.audiomux_context[input_channel].bass_dB = amuxchan_context.audiomux_context[input_channel].bass_dB + TONE_STEP_DB;
                                        buttons_repeat_clear (buttons_context);
                                    } break;
                                    case SCREEN_TREBLE: { // Button press
                                        amuxchan_context.audiomux_context[input_channel].treble_dB = amuxchan_context.audiomux_context[input_channel].treble_dB + TONE_STEP_DB;
                                        buttons_repeat_clear (buttons_context);
                                    } break;
                                    case SCREEN_RESET: { // Button press
                                        // Keep volume_dB
                                        amuxchan_context.audiomux_context[input_channel].bass_dB   = amuxchan_context.audiomux_context[input_channel].bass_dB   + TONE_STEP_DB; // AMUX=001
                                        amuxchan_context.audiomux_context[input_channel].treble_dB = amuxchan_context.audiomux_context[input_channel].treble_dB - TONE_STEP_DB; // AMUX=001
                                        buttons_repeat_clear (buttons_context);
                                    } break;
                                    case SCREEN_INPUT: { // Button press
                                        amuxchan_context.input_channel = amuxchan_context.input_channel + 1;
                                        amuxchan_context.input_channel and_eq (INPUT_NUM-1);
                                        input_channel = amuxchan_context.input_channel; // Removes the effect of the above aliasing
                                    } break;
                                    case SCREEN_ABOUT: { // Button press
                                        // No code
                                    } break;
                                    default: {} break;
                                }
                            } break;
                        } // Outer switch


                    } else {
                        // Not left_button_filtered or other_buttons, no code, plus will not happen here
                    }

                    // Common code for left_button_filtered or other_buttons

                    amuxchan_context.audiomux_context[input_channel].volume_dB = in_range_int8 (amuxchan_context.audiomux_context[input_channel].volume_dB, VOLUME_MIN_DB, VOLUME_MAX_DB);
                    amuxchan_context.audiomux_context[input_channel].bass_dB   = in_range_int8 (amuxchan_context.audiomux_context[input_channel].bass_dB,   TONE_MIN_DB,   TONE_MAX_DB);
                    amuxchan_context.audiomux_context[input_channel].treble_dB = in_range_int8 (amuxchan_context.audiomux_context[input_channel].treble_dB, TONE_MIN_DB,   TONE_MAX_DB);

                    display_context.screen_timeouts_since_last_button_countdown = NUM_TIMEOUTS_BEFORE_SCREEN_DARK; // Button press
                    do_audiomux_and_display (if_i2c_general_commands, display_context, buttons_context, amuxchan_context, log, if_i2c_internal_commands);

                } else {
                    // Not left_button_filtered or other_buttons, no code
                }
                buttons_context.last_action = was_button;
            } break; // select i_buttons_in
        }
    }
}
