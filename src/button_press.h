/*
 * button_press.h
 *
 *  Created on: 18. mars 2015
 *      Author: teig
 */

#ifndef BUTTON_PRESS_H_
#define BUTTON_PRESS_H_

typedef enum {
    BUTTON_ACTION_VOID,
    BUTTON_ACTION_PRESSED,
    BUTTON_ACTION_PRESSED_FOR_LONG, // BUTTON_ACTION_PRESSED_FOR_LONG_TIMEOUT_MS
    BUTTON_ACTION_RELEASED          // Not after BUTTON_ACTION_PRESSED_FOR_LONG
} button_action_t;

typedef enum {long_enabled, long_disabled} long_button_enabled_e;

typedef interface button_if_1 {
    // caused the potentially recursive call to cause error from the linker:
    // Error: Meta information. Error: lower bound could not be calculated (function is recursive?).
    //
    void button (const button_action_t button_action); // timerafter-driven

} button_if_1;

typedef interface button_if_2 {
    // caused the potentially recursive call to cause error from the linker:
    // Error: Meta information. Error: lower bound could not be calculated (function is recursive?).
    //
    void button (const button_action_t button_action, const unsigned button_edge_cnt); // timerafter-driven

} button_if_2;

typedef interface button_if_3 {
    // caused the potentially recursive call to cause error from the linker:
    // Error: Meta information. Error: lower bound could not be calculated (function is recursive?).
    //
    //[[guarded]] void button (const button_action_t button_action); // timerafter-driven
    void button (const button_action_t button_action, const unsigned button_edge_cnt, const unsigned button_noisy_time_us); // timerafter-driven

} button_if_3;

// If client has its own button REPEAT by holding button depressed, this should not be used
#define BUTTON_ACTION_PRESSED_FOR_LONG_TIMEOUT_MS 20000 // 20 seconds. Max 2exp31 = 2147483648 = 21.47483648 seconds (not one less)

#define IOF_BUTTON_LEFT   0
#define IOF_BUTTON_CENTER 1
#define IOF_BUTTON_RIGHT  2

#define BUTTONS_NUM_CLIENTS 3

typedef struct {
    bool pressed_now;
    bool pressed_for_long;
    bool inhibit_released_once;
} button_states_t;

[[combinable]]
void Button_Task_1 (
        const unsigned     button_n,
        in buffered port:1 p_button,
        client button_if_1 i_button_out);

[[combinable]]
void Button_Task_2 (
        const unsigned              button_n,
        const long_button_enabled_e long_button_enabled,
        in buffered port:1          p_button,
        client button_if_2          i_button_out); // const unsigned button_edge_cnt added

[[combinable]]
void Button_Task_3 (
        const unsigned              button_n,
        const long_button_enabled_e long_button_enabled,
        in buffered port:1          p_button,
        client button_if_3          i_button_out); // const unsigned button_noisy_time_us added

#else
    #error Nested include BUTTON_PRESS_H_
#endif
