/*
 * i2c_client_task.xc
 *
 *  Created on: 27. feb.
 *      Author: Teig
 */
#define INCLUDES
#ifdef INCLUDES
#include <platform.h>
#include <xs1.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <xccompat.h> // REFERENCE_PARAM
#include <iso646.h>
#include <string.h>   // memset.
#include <timer.h>    // For delay_milliseconds (but it compiles without?)

#include "_version.h" // First this..
#include "_globals.h" // ..then this
#include "param.h"
#include "button_press.h"

#include "i2c.h"
#include "i2c_client_task.h"
#include "display_ssd1306.h"
#include "core_graphics_adafruit_gfx.h"
#include "_texts_and_constants.h"

#endif

#define DEBUG_PRINT_DISPLAY 0
#define debug_print(fmt, ...) do { if((DEBUG_PRINT_DISPLAY==1) and (DEBUG_PRINT_GLOBAL_APP==1)) printf(fmt, __VA_ARGS__); } while (0)

#define DEBUG_PRINT_AUDIOMUX 0
#define debug_print_audiomux(fmt, ...) do { if((DEBUG_PRINT_AUDIOMUX==1) and (DEBUG_PRINT_GLOBAL_APP==1)) printf(fmt, __VA_ARGS__); } while (0)

// Internal i2c matters (not display matters)
[[combinable]]
void I2C_Client_Task (
        server i2c_internal_commands_if if_i2c_internal_commands[I2C_INTERNAL_NUM_CLIENTS],
        server i2c_general_commands_if  if_i2c_general_commands [I2C_GENERAL_NUM_CLIENTS],
        client i2c_master_if            if_i2c[I2C_HARDWARE_NUM_BUSES][I2C_HARDWARE_NUM_CLIENTS]) { // synchronous

    #if (DEBUG_PRINT_DISPLAY!=0)
        unsigned long int num_chars = 0;
    #endif

    // PRINT
    debug_print("%s", "I2C_Internal_Task started\n");

    while (1) {
        select {

            case if_i2c_internal_commands[int index_of_client].write_display_ok (
                    const i2c_hardware_iof_bus_t i2c_hardware_iof_bus,
                    const i2c_dev_address_t      dev_addr,
                    const i2c_reg_address_t      reg_addr,
                    const i2c_uint8_t            data[], // SSD1306_WRITE_CHUNK_SIZE always is n:
                    const unsigned               nbytes) -> bool ok: {

                #define SSD1306_WRITE_ARR_SIZE (LEN_I2C_SUBADDRESS + SSD1306_WRITE_CHUNK_SIZE)

                i2c_uint8_t write_data[SSD1306_WRITE_ARR_SIZE];

                write_data[0] = reg_addr;

                i2c_result_t i2c_result;

                if (nbytes <= SSD1306_WRITE_CHUNK_SIZE) {
                    unsigned write_nbytes = nbytes + LEN_I2C_SUBADDRESS; // Now including reg_addr as first byte

                    debug_print ("i2c-i dev:%02x reg:%02x r-len:%d:", (int)dev_addr, reg_addr, (int)write_nbytes);

                    for (uint8_t x=LEN_I2C_SUBADDRESS; x<write_nbytes; x++) {
                        write_data[x] = data[x-LEN_I2C_SUBADDRESS];

                        #ifdef DEBUG_PRINT_DISPLAY___qwe // Keep it
                            if (x==(write_nbytes-1)) {
                                debug_print("%02x",write_data[x]); // Last, no comma
                            }
                            else {
                                debug_print("%02x ",write_data[x]);
                            }
                        #endif
                    }
                    // lib_i2c:
                    size_t    num_bytes_sent;
                    int       send_stop_bit = 1;
                    i2c_res_t i2c_res;

                    i2c_res= if_i2c[I2C_HARDWARE_IOF_DISPLAY][i2c_hardware_iof_bus].write ((uint8_t)dev_addr, write_data, (size_t) write_nbytes, num_bytes_sent, send_stop_bit);

                    if ((i2c_res == I2C_NACK) or (num_bytes_sent != write_nbytes)) {
                        i2c_result = I2C_ERR;
                    } else {
                        // ==I2C_ACK
                        i2c_result = I2C_OK;
                    }

                    #ifdef DEBUG_PRINT_DISPLAY___qwe // Keep it
                        debug_print(" r-sent %d\n", num_bytes_sent); // Including reg_addr
                        num_chars += write_nbytes;
                        debug_print(" #%u\n", num_chars); // For a typical display at least 3KB are written
                    #endif

                } else {
                    i2c_result = I2C_PARAM_ERR; // qwe handle later or just do crash or truncate and let i be visible in the dislay
                }
                ok = (i2c_result == I2C_OK); // 1 = (1==1), all OK when 1
            } break;

            case if_i2c_general_commands[int index_of_client].write_reg_ok (
                    const i2c_hardware_iof_bus_t i2c_hardware_iof_bus,
                    const i2c_dev_address_t      dev_addr,
                    const i2c_uint8_t            i2c_bytes[], // reg_addr followed by data
                    const static unsigned        nbytes
                ) -> bool ok: {

                i2c_uint8_t write_data[nbytes];

                for (unsigned ix=0; ix<nbytes; ix++) {
                    write_data[ix] = i2c_bytes[ix];
                }

                // lib_i2c:
                size_t    num_bytes_sent;
                int       send_stop_bit = 1;
                i2c_res_t i2c_res;

                i2c_res= if_i2c[I2C_HARDWARE_IOF_AUDIOMUX][i2c_hardware_iof_bus].write ((uint8_t)dev_addr, write_data, (size_t) nbytes, num_bytes_sent, send_stop_bit);

                debug_print_audiomux("i2c_res=%u, sent=%u\n", i2c_res, num_bytes_sent);

                if ((i2c_res == I2C_NACK) or (num_bytes_sent != nbytes)) {
                    ok = false;
                } else {
                    // ==I2C_ACK
                    ok = true;
                }
            } break;

            case if_i2c_general_commands[int index_of_client].read_reg_ok (
                    const i2c_hardware_iof_bus_t i2c_hardware_iof_bus,
                    const i2c_dev_address_t      dev_addr,
                    const unsigned char          reg_addr,
                          uint8_t                &the_register
                ) -> bool ok: {

                // lib_i2c:
                i2c_regop_res_t result;
                the_register = if_i2c[I2C_HARDWARE_IOF_AUDIOMUX][i2c_hardware_iof_bus].read_reg (dev_addr, reg_addr, result); // First par is not if_i2c since "extends"
                ok = (result == I2C_REGOP_SUCCESS);

            } break;
        }
    }
}
