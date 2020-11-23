/*
 * _AudioMux_controller.xc
 *
 *  Created on: 15. aug. 2018
 *      Author: teig
 */

#define INCLUDES
#ifdef INCLUDES
#include <xs1.h>
#include <platform.h> // slice
#include <timer.h>    // delay_milliseconds(200), XS1_TIMER_HZ etc
#include <stdint.h>   // uint8_t
#include <stdio.h>    // printf
#include <string.h>   // memcpy
#include <xccompat.h> // REFERENCE_PARAM(my_app_ports_t, my_app_ports) -> my_app_ports_t &my_app_ports
#include <iso646.h>   // not etc.
#include <i2c.h>

#include "_version.h" // First this..
#include "_globals.h" // ..then this

#include "param.h"
#include "i2c_client_task.h"
#include "display_ssd1306.h"
#include "core_graphics_adafruit_gfx.h"
#include "_texts_and_constants.h"
#include "button_press.h"
#include "pwm_softblinker.h"

#include "_AudioMux_controller.h"
#endif

#if (DEBUG_PRINT_GLOBAL_APP==1)
    #warning Unit must be connected to xTIMEcomposer. Not for off-line battery usage!
#endif

#define DEBUG_PRINT_RFM69 1
#define debug_print(fmt, ...) do { if((DEBUG_PRINT_RFM69==1) and (DEBUG_PRINT_GLOBAL_APP==1)) printf(fmt, __VA_ARGS__); } while (0)

// Observe that I have no control of the ports during xTIMEcomposer downloading
// I have observed a 700-800 ms low on signal pins before my code starts

// ---
// 1 BIT PORT TARGET_XCORE-XA-MODULE
// ---

#if (IS_MYTARGET == IS_MYTARGET_STARTKIT)
    out buffered port:1 outP1_d4_led       = on tile[0]: XS1_PORT_1P; // J7 GPIO23 X0D39 = text D39

    // Open button 3V3 pull-up with 10k, pushed button takes that line via 1k to GND
    in  buffered port:1 inP_button_left    = on tile[0]: XS1_PORT_1O; // External J7 GPIO21 X0D38 = text D38
    in  buffered port:1 inP_button_center  = on tile[0]: XS1_PORT_1I; // External J7 GPIO20 X0D24 = text D24
    in  buffered port:1 inP_button_right   = on tile[0]: XS1_PORT_1L; // External J7 GPIO19 X0D35 = text D35

    port                p_display_scl      = on tile[0]: XS1_PORT_1K; // External J7 GPIO11 X0D34 = text D34
    port                p_display_sda      = on tile[0]: XS1_PORT_1J; // External J7 GPIO10 X0D25 = text D25
    out port            p_display_notReset = on tile[0]: XS1_PORT_1M; // External J7 GPIO15 X0D36 = text D36
                                                                      // Adafruit monochrome 128x32 I2C OLED graphic display PRODUCT ID: 931, containing
                                                                      // module UG-2832HSWEG02 with chip SSD1306 from Univision Technology Inc. Data sheet often says 128 x 64 bits
                                                                      // as it looks like much of the logic is the same as for 128 z 32 bits.
                                                                      // At least 3 us low to reset
    port                p_audiomux_scl     = on tile[0]: XS1_PORT_1H; // External J7 GPIO02 X0D23 = text D23
    port                p_audiomux_sda     = on tile[0]: XS1_PORT_1F; // External J7 GPI001 X0D13 = text D13

#elif (IS_MYTARGET == IS_MYTARGET_XCORE_200_EXPLORER)

    in buffered port:1 inP_button_left     = on tile[0]: XS1_PORT_1M; // External GPIO-PIN63 With pull-up of 9.1k
    in buffered port:1 inP_button_center   = on tile[0]: XS1_PORT_1N; // External GPIO-PIN61 With pull-up of 9.1k
    in buffered port:1 inP_button_right    = on tile[0]: XS1_PORT_1O; // External GPIO-PIN59 With pull-up of 9.1k

#elif (IS_MYTARGET == IS_MYTARGET_XCORE_XA_MODULE)
    out buffered port:1 outP1_d4_led       = on tile[0]: XS1_PORT_1F; // xCORE XA J1 D13 XCORE-XA-MODULE LED D4 (LOW IS ON)

    // Open button 3V3 pull-up with 10k, pushed button takes that line via 1k to GND
    in  buffered port:1 inP_button_left    = on tile[0]: XS1_PORT_1K; // External xCORE XA J9 P34. XCORE-XA-MODULE EXTERNAL BUTTON1
    in  buffered port:1 inP_button_center  = on tile[0]: XS1_PORT_1O; // External xCORE XA J9 P38. XCORE-XA-MODULE EXTERNAL BUTTON2
    in  buffered port:1 inP_button_right   = on tile[0]: XS1_PORT_1P; // External xCORE XA J9 P39. XCORE-XA-MODULE EXTERNAL BUTTON3

    port                p_display_scl      = on tile[0]: XS1_PORT_1H; // External xCORE XA J9 P6
    port                p_display_sda      = on tile[0]: XS1_PORT_1L; // External xCORE XA J9 P8
    out port            p_display_notReset = on tile[0]: XS1_PORT_1G; // External xCORE XA J9 P5 (but the display uses xCORE reset signal P4 instead)
                                                                      // on adafruit monochrome 128x32 I2C OLED graphic display PRODUCT ID: 931, containing
                                                                      // module UG-2832HSWEG02 with chip SSD1306 from Univision Technology Inc. Data sheet often says 128 x 64 bits
                                                                      // as it looks like much of the logic is the same as for 128 z 32 bits.
                                                                      // At least 3 us low to reset
    port                p_audiomux_scl     = on tile[0]: XS1_PORT_1B; // External xCORE XA J1 P6
    port                p_audiomux_sda     = on tile[0]: XS1_PORT_1D; // External xCORE XA J1 P8
#endif


#define I2C_DISPLAY_MASTER_SPEED_KBPS  333 // 333 is same speed as used in the aquarium in i2c_client_task.xc,
                                           // i2c_internal_config.clockTicks 300 for older XMOS code struct r_i2c in i2c.h and module_i2c_master
#define I2C_AUDIOMUX_MASTER_SPEED_KBPS 100 // 100 as seen in MikroElektronik's example

#define I2C_INTERNAL_NUM_CLIENTS 1


#define IRQ_HIGH_MAX_TIME_MILLIS 2000 // This is not critical, but having a value that would display a real stuck IRQ would be most correct I guess
                                      // Have testet 100 and 1000 with debug prints (which would waste the most time in debug_print)

int main() {

    button_if_gen            if_buttons[BUTTONS_NUM_CLIENTS];
    i2c_internal_commands_if if_i2c_internal_commands [I2C_INTERNAL_NUM_CLIENTS];
    i2c_general_commands_if  if_i2c_general_commands  [I2C_GENERAL_NUM_CLIENTS];
    i2c_master_if            if_i2c[I2C_HARDWARE_NUM_BUSES][I2C_HARDWARE_NUM_CLIENTS];
    pwm_if                   if_pwm;
    softblinker_if           if_softblinker;

    // Observe http://www.teigfam.net/oyvind/home/technology/098-my-xmos-notes/#xtag-3_debug_log_hanging!
    par {
        on tile[0]: {
            [[combine]]
            par {
                buttons_client_task (if_i2c_internal_commands[0], if_i2c_general_commands[0], if_buttons, p_display_notReset, if_softblinker);

                #if (USE_BUTTON_TASK_NUM==1)
                    Button_Task_1 (IOF_BUTTON_LEFT,   inP_button_left,   if_buttons[IOF_BUTTON_LEFT]);   // [[combinable]]
                    Button_Task_1 (IOF_BUTTON_CENTER, inP_button_center, if_buttons[IOF_BUTTON_CENTER]); // [[combinable]]
                    Button_Task_1 (IOF_BUTTON_RIGHT,  inP_button_right,  if_buttons[IOF_BUTTON_RIGHT]);  // [[combinable]]
                #elif (USE_BUTTON_TASK_NUM==2)
                    Button_Task_2 (IOF_BUTTON_LEFT,   long_enabled, inP_button_left,   if_buttons[IOF_BUTTON_LEFT]);   // [[combinable]]
                    Button_Task_2 (IOF_BUTTON_CENTER, long_enabled, inP_button_center, if_buttons[IOF_BUTTON_CENTER]); // [[combinable]]
                    Button_Task_2 (IOF_BUTTON_RIGHT,  long_enabled, inP_button_right,  if_buttons[IOF_BUTTON_RIGHT]);  // [[combinable]]
                #elif (USE_BUTTON_TASK_NUM==3)
                    Button_Task_3 (IOF_BUTTON_LEFT,   long_enabled, inP_button_left,   if_buttons[IOF_BUTTON_LEFT]);   // [[combinable]]
                    Button_Task_3 (IOF_BUTTON_CENTER, long_enabled, inP_button_center, if_buttons[IOF_BUTTON_CENTER]); // [[combinable]]
                    Button_Task_3 (IOF_BUTTON_RIGHT,  long_enabled, inP_button_right,  if_buttons[IOF_BUTTON_RIGHT]);  // [[combinable]]
                #endif


            }
        }

        par {
            on tile[0].core[5]: I2C_Client_Task  (if_i2c_internal_commands, if_i2c_general_commands, if_i2c);
            on tile[0].core[6]: i2c_master       (if_i2c[I2C_HARDWARE_IOF_DISPLAY],  1, p_display_scl,  p_display_sda,  I2C_DISPLAY_MASTER_SPEED_KBPS); // Synchronous==distributable
            on tile[0].core[6]: i2c_master       (if_i2c[I2C_HARDWARE_IOF_AUDIOMUX], 1, p_audiomux_scl, p_audiomux_sda, I2C_AUDIOMUX_MASTER_SPEED_KBPS); // Synchronous==distributable
            on tile[0].core[7]: pwm_for_LED_task (if_pwm, outP1_d4_led);
            on tile[0].core[7]: softblinker_task (if_pwm, if_softblinker);
        }
    }

    return 0;
}
